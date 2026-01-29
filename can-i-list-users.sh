#!/bin/bash

# Script to check if the authenticated user can list users in an organization
# Performs two-phase verification:
#   1. Predictive check based on user's admin/hubAdmin status
#   2. Actual API call to verify permission
# Usage: ./can-i-list-users.sh [OPTIONS] [ENV_FILE]

# Strict error handling
set -euo pipefail

# Default output mode
VERBOSE=false
JSON_ONLY=false
ENV_FILE=""
TARGET_ORG=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -j|--json)
            JSON_ONLY=true
            shift
            ;;
        -o|--org)
            if [[ -n "${2:-}" ]]; then
                TARGET_ORG="$2"
                shift 2
            else
                echo "Error: --org requires an organization ID argument"
                exit 2
            fi
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS] [ENV_FILE]"
            echo ""
            echo "Check if the authenticated user can list users in an organization"
            echo ""
            echo "This script performs two-phase verification:"
            echo "  1. Predictive check - determines if user SHOULD be able to list users"
            echo "     based on their admin/hubAdmin status"
            echo "  2. Actual verification - confirms with an API call if user CAN list users"
            echo ""
            echo "Options:"
            echo "  -o, --org ORG    Target organization to check (default: auth org)"
            echo "  -v, --verbose    Show detailed output with API responses"
            echo "  -j, --json       Output JSON only (for scripting/automation)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Exit Codes:"
            echo "  0  User CAN list users"
            echo "  1  User CANNOT list users"
            echo "  2  Error (invalid arguments, API error, etc.)"
            echo ""
            echo "Examples:"
            echo "  $0                          # Check permission in auth org"
            echo "  $0 -o other-org             # Check permission in different org"
            echo "  $0 --json mycreds.env       # JSON output with specific .env file"
            echo "  $0 --verbose                # Detailed output for debugging"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 2
            ;;
        *)
            # Non-option argument, treat as env file
            ENV_FILE="$1"
            shift
            ;;
    esac
done

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Setup cleanup trap
# shellcheck disable=SC2119  # Function doesn't use positional parameters
setup_cleanup_trap

# Handle .env file selection and load credentials
selected_file=""  # Will be set by select_env_file
select_env_file "$ENV_FILE" || exit 2
load_credentials "$selected_file" || exit 2

# Set target org to auth org if not specified
if [ -z "$TARGET_ORG" ]; then
    TARGET_ORG="$HZN_ORG_ID"
fi

# Display configuration (unless JSON mode)
if [ "$JSON_ONLY" = false ]; then
    print_header "Permission Check: Can I List Users?"
    echo ""
    print_info "Configuration:"
    echo "  Exchange URL:     $HZN_EXCHANGE_URL"
    echo "  Auth Organization: $HZN_ORG_ID"
    echo "  Target Organization: $TARGET_ORG"
    echo "  Auth User:        ${HZN_EXCHANGE_USER_AUTH%%:*}"
    echo ""
fi

# Check if curl is installed
check_curl || exit 2

# Check if jq is installed (optional but recommended)
check_jq

# Parse authentication credentials
parse_auth

# Use the Exchange URL as-is (it should already include the API version path)
# Remove trailing slash if present
BASE_URL="${HZN_EXCHANGE_URL%/}"

# ============================================================================
# PHASE 1: Predictive Permission Check
# ============================================================================

if [ "$JSON_ONLY" = false ]; then
    print_info "Phase 1: Checking user permissions..."
    echo ""
fi

# Fetch current user info
user_response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${HZN_ORG_ID}/users/${AUTH_USER}" 2>&1)
user_http_code=$(echo "$user_response" | tail -n1)
user_body=$(echo "$user_response" | sed '$d')

if [ "$user_http_code" -ne 200 ]; then
    if [ "$JSON_ONLY" = true ]; then
        echo "{\"error\": \"Failed to fetch user info\", \"http_code\": $user_http_code}"
    else
        print_error "Failed to fetch user information (HTTP $user_http_code)"
        echo ""
        echo "Response: $user_body"
    fi
    exit 2
fi

# Parse user admin status
if [ "$JQ_AVAILABLE" = true ]; then
    user_key=$(echo "$user_body" | jq -r '.users | keys[0]')
    is_admin=$(echo "$user_body" | jq -r ".users[\"$user_key\"].admin // false")
    is_hub_admin=$(echo "$user_body" | jq -r ".users[\"$user_key\"].hubAdmin // false")
else
    # Fallback parsing without jq
    if echo "$user_body" | grep -q '"admin"[[:space:]]*:[[:space:]]*true'; then
        is_admin="true"
    else
        is_admin="false"
    fi
    if echo "$user_body" | grep -q '"hubAdmin"[[:space:]]*:[[:space:]]*true'; then
        is_hub_admin="true"
    else
        is_hub_admin="false"
    fi
fi

# Determine predicted permission
predicted_can_list=false
prediction_reason=""

if [ "$is_hub_admin" = "true" ]; then
    predicted_can_list=true
    prediction_reason="User is a Hub Admin (can access any organization)"
elif [ "$is_admin" = "true" ] && [ "$TARGET_ORG" = "$HZN_ORG_ID" ]; then
    predicted_can_list=true
    prediction_reason="User is an Org Admin in the target organization"
elif [ "$is_admin" = "true" ] && [ "$TARGET_ORG" != "$HZN_ORG_ID" ]; then
    predicted_can_list=false
    prediction_reason="User is an Org Admin but target org ($TARGET_ORG) differs from auth org ($HZN_ORG_ID)"
else
    predicted_can_list=false
    prediction_reason="User is not an admin (admin=$is_admin, hubAdmin=$is_hub_admin)"
fi

if [ "$JSON_ONLY" = false ]; then
    echo "  User: $AUTH_USER"
    echo "  Org Admin: $is_admin"
    echo "  Hub Admin: $is_hub_admin"
    echo ""
    if [ "$predicted_can_list" = true ]; then
        echo -e "  Predicted: ${GREEN}YES${NC} - $prediction_reason"
    else
        echo -e "  Predicted: ${RED}NO${NC} - $prediction_reason"
    fi
    echo ""
    
    if [ "$VERBOSE" = true ]; then
        print_info "User API Response:"
        if [ "$JQ_AVAILABLE" = true ]; then
            echo "$user_body" | jq '.'
        else
            echo "$user_body" | python3 -m json.tool 2>/dev/null || echo "$user_body"
        fi
        echo ""
    fi
fi

# ============================================================================
# PHASE 2: Actual Permission Verification
# ============================================================================

if [ "$JSON_ONLY" = false ]; then
    print_info "Phase 2: Verifying with API call..."
    echo ""
fi

# Attempt to list users
list_response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${TARGET_ORG}/users" 2>&1)
list_http_code=$(echo "$list_response" | tail -n1)
list_body=$(echo "$list_response" | sed '$d')

# Determine actual permission
actual_can_list=false
actual_reason=""

if [ "$list_http_code" -eq 200 ]; then
    actual_can_list=true
    actual_reason="API returned HTTP 200 (success)"
elif [ "$list_http_code" -eq 401 ]; then
    actual_can_list=false
    actual_reason="API returned HTTP 401 (unauthorized)"
elif [ "$list_http_code" -eq 403 ]; then
    actual_can_list=false
    actual_reason="API returned HTTP 403 (forbidden)"
elif [ "$list_http_code" -eq 404 ]; then
    actual_can_list=false
    actual_reason="API returned HTTP 404 (organization not found)"
else
    actual_can_list=false
    actual_reason="API returned HTTP $list_http_code"
fi

if [ "$JSON_ONLY" = false ]; then
    if [ "$actual_can_list" = true ]; then
        echo -e "  Actual: ${GREEN}YES${NC} - $actual_reason"
    else
        echo -e "  Actual: ${RED}NO${NC} - $actual_reason"
    fi
    echo ""
    
    if [ "$VERBOSE" = true ]; then
        print_info "List Users API Response (HTTP $list_http_code):"
        if [ "$JQ_AVAILABLE" = true ]; then
            echo "$list_body" | jq '.' 2>/dev/null || echo "$list_body"
        else
            echo "$list_body" | python3 -m json.tool 2>/dev/null || echo "$list_body"
        fi
        echo ""
    fi
fi

# ============================================================================
# PHASE 3: Compare and Report Results
# ============================================================================

if [ "$JSON_ONLY" = false ]; then
    print_header "Result"
    echo ""
fi

# Determine result status
result_status=""
result_message=""
exit_code=0

if [ "$predicted_can_list" = true ] && [ "$actual_can_list" = true ]; then
    result_status="CONFIRMED"
    result_message="Permission confirmed - user can list users as expected"
    exit_code=0
elif [ "$predicted_can_list" = false ] && [ "$actual_can_list" = false ]; then
    result_status="CONFIRMED"
    result_message="Permission correctly denied - user cannot list users as expected"
    exit_code=1
elif [ "$predicted_can_list" = true ] && [ "$actual_can_list" = false ]; then
    result_status="MISMATCH"
    result_message="Unexpected denial - user should be able to list users but cannot"
    exit_code=1
elif [ "$predicted_can_list" = false ] && [ "$actual_can_list" = true ]; then
    result_status="MISMATCH"
    result_message="Unexpected access - user can list users but shouldn't be able to"
    exit_code=0
fi

# Output results
if [ "$JSON_ONLY" = true ]; then
    # JSON output mode
    cat << EOF
{
  "target_org": "$TARGET_ORG",
  "auth_org": "$HZN_ORG_ID",
  "auth_user": "$AUTH_USER",
  "user_is_admin": $is_admin,
  "user_is_hub_admin": $is_hub_admin,
  "predicted": {
    "can_list_users": $predicted_can_list,
    "reason": "$prediction_reason"
  },
  "actual": {
    "can_list_users": $actual_can_list,
    "http_code": $list_http_code,
    "reason": "$actual_reason"
  },
  "result": {
    "status": "$result_status",
    "message": "$result_message",
    "can_list_users": $actual_can_list
  }
}
EOF
else
    # Human-readable output
    if [ "$result_status" = "CONFIRMED" ]; then
        if [ "$actual_can_list" = true ]; then
            echo -e "  ${GREEN}✓${NC} $result_message"
        else
            echo -e "  ${YELLOW}✓${NC} $result_message"
        fi
    else
        echo -e "  ${RED}!${NC} $result_message"
        echo ""
        print_warning "Troubleshooting tips:"
        if [ "$predicted_can_list" = true ] && [ "$actual_can_list" = false ]; then
            echo "  1. The Exchange may have additional permission restrictions"
            echo "  2. The target organization '$TARGET_ORG' may have custom ACLs"
            echo "  3. There may be a temporary issue with the Exchange server"
            echo "  4. Try running with --verbose to see the full API response"
        else
            echo "  1. The user may have been granted additional permissions"
            echo "  2. The Exchange may have permissive default settings"
            echo "  3. Review the organization's permission configuration"
        fi
    fi
    echo ""
    
    # Summary
    print_info "Summary:"
    echo "  Can list users in '$TARGET_ORG': $([ "$actual_can_list" = true ] && echo "YES" || echo "NO")"
    echo ""
fi

exit $exit_code
