#!/bin/bash

# Script to check if the authenticated user can list users in an organization
# Performs three-level verification (general to specific):
#   Level 1: List ALL users (across all organizations) - Hub Admin only
#   Level 2: List users in auth organization - Org Admin or Hub Admin
#   Level 3: View own user information - Any authenticated user
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
            echo "Check if the authenticated user can list users"
            echo ""
            echo "This script performs three-level verification (general to specific):"
            echo "  Level 1: List ALL users (across all organizations) - Hub Admin only"
            echo "  Level 2: List users in auth organization - Org Admin or Hub Admin"
            echo "  Level 3: View own user information - Any authenticated user"
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
            echo "  0  User CAN list users (at org level or higher)"
            echo "  1  User CANNOT list users (can only view own info)"
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
    echo "  Exchange URL:      $HZN_EXCHANGE_URL"
    echo "  Auth Organization: $HZN_ORG_ID"
    echo "  Target Organization: $TARGET_ORG"
    echo "  Auth User:         ${HZN_EXCHANGE_USER_AUTH%%:*}"
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

# Resolve actual username if using API key
if [ "$IS_API_KEY" = true ]; then
    resolve_apikey_username || exit 2
fi

# ============================================================================
# PHASE 1: Fetch User Information
# ============================================================================

if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching user information..."
    echo ""
fi

# Display the API request in verbose mode
display_api_request "GET" "${BASE_URL}/orgs/${HZN_ORG_ID}/users/${AUTH_USER}"

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

if [ "$JSON_ONLY" = false ]; then
    echo "User Permissions:"
    echo "  Org Admin:  $is_admin"
    echo "  Hub Admin:  $is_hub_admin"
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
# PHASE 2: Three-Level Permission Testing (General → Specific)
# ============================================================================

if [ "$JSON_ONLY" = false ]; then
    print_header "Testing Access Levels (General → Specific)"
fi

# Initialize result tracking
level1_predicted=false
level1_actual=false
level1_http_code=0
level1_reason=""
level1_count=0

level2_predicted=false
level2_actual=false
level2_http_code=0
level2_reason=""
level2_count=0

level3_predicted=false
level3_actual=false
level3_http_code=0
level3_reason=""

# ----------------------------------------------------------------------------
# Level 1: List ALL Users (across all organizations)
# ----------------------------------------------------------------------------

# Predict Level 1
if [ "$is_hub_admin" = "true" ]; then
    level1_predicted=true
    level1_pred_reason="User is a Hub Admin"
else
    level1_predicted=false
    level1_pred_reason="User is not a Hub Admin"
fi

# Test Level 1 - Note: There's no single endpoint to list ALL users
# We'll test by trying to list users in a different org (if target != auth)
# Or indicate this requires iterating through all orgs
if [ "$TARGET_ORG" != "$HZN_ORG_ID" ]; then
    # Test access to different org as proxy for "all users" capability
    test_api_access "/orgs/${TARGET_ORG}/users" "List users in different organization"
    level1_actual="$test_can_access"
    level1_http_code="$test_http_code"
    level1_reason="Tested access to different org ($TARGET_ORG)"
    if [ "$level1_actual" = "true" ]; then
        level1_count=$(count_json_items "$test_response_body" "users")
    fi
else
    # Same org - hub admin can list all orgs, so mark as "would need to test other orgs"
    if [ "$is_hub_admin" = "true" ]; then
        level1_actual=true
        level1_http_code=200
        level1_reason="Hub Admin can access all organizations"
        level1_count="N/A"
    else
        level1_actual=false
        level1_http_code=403
        level1_reason="Would need Hub Admin to access other organizations"
        level1_count=0
    fi
fi

# Display Level 1 result
format_level_result 1 "List ALL Users (across all organizations)" \
    "$level1_predicted" "$level1_pred_reason" \
    "$level1_actual" "$level1_reason" "$level1_http_code"

if [ "$JSON_ONLY" = false ] && [ "$level1_actual" = "true" ] && [ "$level1_count" != "N/A" ]; then
    echo "  Users found: $level1_count"
fi

# ----------------------------------------------------------------------------
# Level 2: List Users in Auth Organization
# ----------------------------------------------------------------------------

# Predict Level 2
if [ "$is_hub_admin" = "true" ]; then
    level2_predicted=true
    level2_pred_reason="User is a Hub Admin"
elif [ "$is_admin" = "true" ] && [ "$TARGET_ORG" = "$HZN_ORG_ID" ]; then
    level2_predicted=true
    level2_pred_reason="User is an Org Admin in target organization"
elif [ "$is_admin" = "true" ] && [ "$TARGET_ORG" != "$HZN_ORG_ID" ]; then
    level2_predicted=false
    level2_pred_reason="User is Org Admin but target org differs from auth org"
else
    level2_predicted=false
    level2_pred_reason="User is not an admin"
fi

# Test Level 2
test_api_access "/orgs/${TARGET_ORG}/users" "List users in organization '$TARGET_ORG'"
level2_actual="$test_can_access"
level2_http_code="$test_http_code"

if [ "$level2_actual" = "true" ]; then
    level2_reason="Successfully listed users"
    level2_count=$(count_json_items "$test_response_body" "users")
elif [ "$level2_http_code" -eq 401 ]; then
    level2_reason="Unauthorized"
elif [ "$level2_http_code" -eq 403 ]; then
    level2_reason="Forbidden"
elif [ "$level2_http_code" -eq 404 ]; then
    level2_reason="Organization not found"
else
    level2_reason="HTTP $level2_http_code"
fi

# Display Level 2 result
format_level_result 2 "List Users in Organization '$TARGET_ORG'" \
    "$level2_predicted" "$level2_pred_reason" \
    "$level2_actual" "$level2_reason" "$level2_http_code"

if [ "$JSON_ONLY" = false ] && [ "$level2_actual" = "true" ]; then
    echo "  Users found: $level2_count"
fi

if [ "$JSON_ONLY" = false ] && [ "$VERBOSE" = true ] && [ "$level2_actual" = "true" ]; then
    echo ""
    print_info "Level 2 API Response:"
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$test_response_body" | jq '.'
    else
        echo "$test_response_body" | python3 -m json.tool 2>/dev/null || echo "$test_response_body"
    fi
fi

# ----------------------------------------------------------------------------
# Level 3: View Own User Information
# ----------------------------------------------------------------------------

# Predict Level 3 - all authenticated users can view their own info
level3_predicted=true
level3_pred_reason="All authenticated users can view their own information"

# Test Level 3
test_api_access "/orgs/${HZN_ORG_ID}/users/${AUTH_USER}" "View own user information"
level3_actual="$test_can_access"
level3_http_code="$test_http_code"

if [ "$level3_actual" = "true" ]; then
    level3_reason="Successfully retrieved own user info"
else
    level3_reason="Failed to retrieve own user info"
fi

# Display Level 3 result
format_level_result 3 "View Own User Information" \
    "$level3_predicted" "$level3_pred_reason" \
    "$level3_actual" "$level3_reason" "$level3_http_code"

if [ "$JSON_ONLY" = false ] && [ "$VERBOSE" = true ] && [ "$level3_actual" = "true" ]; then
    echo ""
    print_info "Level 3 API Response:"
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$test_response_body" | jq '.'
    else
        echo "$test_response_body" | python3 -m json.tool 2>/dev/null || echo "$test_response_body"
    fi
fi

# ============================================================================
# PHASE 3: Summary and Results
# ============================================================================

if [ "$JSON_ONLY" = false ]; then
    echo ""
    print_header "Result"
    echo ""
fi

# Determine overall result and exit code
# Exit code based on Level 2 (org-level access) for backward compatibility
exit_code=1
result_message=""

if [ "$level2_actual" = "true" ]; then
    exit_code=0
    if [ "$level1_actual" = "true" ]; then
        result_message="User can list users across all organizations"
    else
        result_message="User can list users in organization '$TARGET_ORG'"
    fi
else
    exit_code=1
    if [ "$level3_actual" = "true" ]; then
        result_message="User cannot list users but can view own information"
    else
        result_message="User cannot list users or view own information"
    fi
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
  "levels": {
    "level1": {
      "description": "List ALL users (across all organizations)",
      "predicted": $level1_predicted,
      "predicted_reason": "$level1_pred_reason",
      "actual": $level1_actual,
      "actual_reason": "$level1_reason",
      "http_code": $level1_http_code,
      "users_found": "$level1_count"
    },
    "level2": {
      "description": "List users in organization '$TARGET_ORG'",
      "predicted": $level2_predicted,
      "predicted_reason": "$level2_pred_reason",
      "actual": $level2_actual,
      "actual_reason": "$level2_reason",
      "http_code": $level2_http_code,
      "users_found": $level2_count
    },
    "level3": {
      "description": "View own user information",
      "predicted": $level3_predicted,
      "predicted_reason": "$level3_pred_reason",
      "actual": $level3_actual,
      "actual_reason": "$level3_reason",
      "http_code": $level3_http_code
    }
  },
  "result": {
    "message": "$result_message",
    "can_list_all_users": $level1_actual,
    "can_list_org_users": $level2_actual,
    "can_view_own_info": $level3_actual,
    "exit_code": $exit_code
  }
}
EOF
else
    # Human-readable output
    if [ "$exit_code" -eq 0 ]; then
        echo -e "  ${GREEN}✓${NC} $result_message"
    else
        echo -e "  ${YELLOW}✓${NC} $result_message"
    fi
    
    echo ""
    print_info "Summary:"
    echo "  Can list ALL users:     $([ "$level1_actual" = "true" ] && echo "YES" || echo "NO")"
    echo "  Can list org users:     $([ "$level2_actual" = "true" ] && echo "YES" || echo "NO")"
    echo "  Can view own info:      $([ "$level3_actual" = "true" ] && echo "YES" || echo "NO")"
    echo ""
fi

exit $exit_code
