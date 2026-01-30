#!/bin/bash

# Script to check if the authenticated user can list organizations
# Performs three-level verification (general to specific):
#   Level 1: List ALL organizations - Hub Admin (all) or Org Admin (own)
#   Level 2: View auth organization details - Organization member
#   Level 3: View user's role in organization - Any authenticated user
# Usage: ./can-i-list-orgs.sh [OPTIONS] [ENV_FILE]

# Strict error handling
set -euo pipefail

# Default output mode
VERBOSE=false
JSON_ONLY=false
ENV_FILE=""

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
        -h|--help)
            echo "Usage: $0 [OPTIONS] [ENV_FILE]"
            echo ""
            echo "Check if the authenticated user can list organizations"
            echo ""
            echo "This script performs three-level verification (general to specific):"
            echo "  Level 1: List ALL organizations - Hub Admin (all) or Org Admin (own)"
            echo "  Level 2: View auth organization details - Organization member"
            echo "  Level 3: View user's role in organization - Any authenticated user"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed output with API responses"
            echo "  -j, --json       Output JSON only (for scripting/automation)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Exit Codes:"
            echo "  0  User CAN list organizations (at least own org)"
            echo "  1  User CANNOT list organizations"
            echo "  2  Error (invalid arguments, API error, etc.)"
            echo ""
            echo "Examples:"
            echo "  $0                          # Check permission"
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

# Display configuration (unless JSON mode)
if [ "$JSON_ONLY" = false ]; then
    print_header "Permission Check: Can I List Organizations?"
    echo ""
    print_info "Configuration:"
    echo "  Exchange URL:      $HZN_EXCHANGE_URL"
    echo "  Auth Organization: $HZN_ORG_ID"
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
level1_scope=""
level1_count=0

level2_predicted=false
level2_actual=false
level2_http_code=0
level2_reason=""

level3_predicted=false
level3_actual=false
level3_http_code=0
level3_reason=""
level3_role=""

# ----------------------------------------------------------------------------
# Level 1: List ALL Organizations
# ----------------------------------------------------------------------------

# Predict Level 1: Only Hub Admins can list ALL organizations
if [ "$is_hub_admin" = "true" ]; then
    level1_predicted=true
    level1_pred_reason="User is a Hub Admin (can see all organizations)"
    level1_scope="ALL"
else
    level1_predicted=false
    if [ "$is_admin" = "true" ]; then
        level1_pred_reason="User is an Org Admin (cannot list all organizations)"
    else
        level1_pred_reason="User is not an admin (cannot list all organizations)"
    fi
    level1_scope="NONE"
fi

# Test Level 1
test_api_access "/orgs" "List all organizations"
level1_actual="$test_can_access"
level1_http_code="$test_http_code"

if [ "$level1_actual" = "true" ]; then
    level1_count=$(count_json_items "$test_response_body" "orgs")
    
    # Determine actual scope based on count
    if [ "$level1_count" -gt 1 ]; then
        level1_scope="ALL"
        level1_reason="Successfully listed $level1_count organizations"
    else
        level1_scope="OWN"
        level1_reason="Successfully listed own organization only"
    fi
elif [ "$level1_http_code" -eq 401 ]; then
    level1_reason="Unauthorized"
    level1_scope="NONE"
elif [ "$level1_http_code" -eq 403 ]; then
    level1_reason="Forbidden"
    level1_scope="NONE"
else
    level1_reason="HTTP $level1_http_code"
    level1_scope="NONE"
fi

# Display Level 1 result
format_level_result 1 "List ALL Organizations" \
    "$level1_predicted" "$level1_pred_reason" \
    "$level1_actual" "$level1_reason" "$level1_http_code"

if [ "$JSON_ONLY" = false ] && [ "$level1_actual" = "true" ]; then
    echo "  Scope: $level1_scope ($level1_count organization(s))"
    
    # List organizations if verbose
    if [ "$VERBOSE" = true ]; then
        echo ""
        print_info "Organizations:"
        if [ "$JQ_AVAILABLE" = true ]; then
            echo "$test_response_body" | jq -r '.orgs | keys[]' | while read -r org; do
                echo "    - $org"
            done
        else
            echo "$test_response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(['    - ' + org for org in data.get('orgs', {}).keys()]))" 2>/dev/null || echo "    (unable to parse)"
        fi
    fi
fi

if [ "$JSON_ONLY" = false ] && [ "$VERBOSE" = true ] && [ "$level1_actual" = "true" ]; then
    echo ""
    print_info "Level 1 API Response:"
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$test_response_body" | jq '.'
    else
        echo "$test_response_body" | python3 -m json.tool 2>/dev/null || echo "$test_response_body"
    fi
fi

# ----------------------------------------------------------------------------
# Level 2: View Auth Organization Details
# ----------------------------------------------------------------------------

# Predict Level 2 - all members can view their own org
level2_predicted=true
level2_pred_reason="User is a member of organization '$HZN_ORG_ID'"

# Test Level 2
test_api_access "/orgs/${HZN_ORG_ID}" "View organization '$HZN_ORG_ID' details"
level2_actual="$test_can_access"
level2_http_code="$test_http_code"

if [ "$level2_actual" = "true" ]; then
    level2_reason="Successfully retrieved organization details"
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
format_level_result 2 "View Organization '$HZN_ORG_ID' Details" \
    "$level2_predicted" "$level2_pred_reason" \
    "$level2_actual" "$level2_reason" "$level2_http_code"

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
# Level 3: View User's Role in Organization
# ----------------------------------------------------------------------------

# Predict Level 3 - all authenticated users can view their own info
level3_predicted=true
level3_pred_reason="All authenticated users can view their own role"

# Test Level 3
test_api_access "/orgs/${HZN_ORG_ID}/users/${AUTH_USER}" "View user's role in organization"
level3_actual="$test_can_access"
level3_http_code="$test_http_code"

if [ "$level3_actual" = "true" ]; then
    level3_reason="Successfully retrieved user role information"
    
    # Extract role information
    if [ "$is_hub_admin" = "true" ]; then
        level3_role="Hub Admin"
    elif [ "$is_admin" = "true" ]; then
        level3_role="Org Admin"
    else
        level3_role="Regular User"
    fi
else
    level3_reason="Failed to retrieve user role"
    level3_role="Unknown"
fi

# Display Level 3 result
format_level_result 3 "View User's Role in Organization" \
    "$level3_predicted" "$level3_pred_reason" \
    "$level3_actual" "$level3_reason" "$level3_http_code"

if [ "$JSON_ONLY" = false ] && [ "$level3_actual" = "true" ]; then
    echo "  Role: $level3_role"
fi

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
# Exit code based on Level 1 (org listing) for backward compatibility
exit_code=1
result_message=""

if [ "$level1_actual" = "true" ]; then
    exit_code=0
    if [ "$level1_scope" = "ALL" ]; then
        result_message="User can list all organizations"
    else
        result_message="User can list own organization only"
    fi
else
    exit_code=1
    if [ "$level2_actual" = "true" ]; then
        result_message="User cannot list organizations but can view own org details"
    else
        result_message="User cannot list organizations or view org details"
    fi
fi

# Output results
if [ "$JSON_ONLY" = true ]; then
    # JSON output mode
    cat << EOF
{
  "auth_org": "$HZN_ORG_ID",
  "auth_user": "$AUTH_USER",
  "user_is_admin": $is_admin,
  "user_is_hub_admin": $is_hub_admin,
  "levels": {
    "level1": {
      "description": "List ALL organizations",
      "predicted": $level1_predicted,
      "predicted_reason": "$level1_pred_reason",
      "actual": $level1_actual,
      "actual_reason": "$level1_reason",
      "http_code": $level1_http_code,
      "scope": "$level1_scope",
      "orgs_found": $level1_count
    },
    "level2": {
      "description": "View organization '$HZN_ORG_ID' details",
      "predicted": $level2_predicted,
      "predicted_reason": "$level2_pred_reason",
      "actual": $level2_actual,
      "actual_reason": "$level2_reason",
      "http_code": $level2_http_code
    },
    "level3": {
      "description": "View user's role in organization",
      "predicted": $level3_predicted,
      "predicted_reason": "$level3_pred_reason",
      "actual": $level3_actual,
      "actual_reason": "$level3_reason",
      "http_code": $level3_http_code,
      "role": "$level3_role"
    }
  },
  "result": {
    "message": "$result_message",
    "can_list_orgs": $level1_actual,
    "can_view_org_details": $level2_actual,
    "can_view_own_role": $level3_actual,
    "scope": "$level1_scope",
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
    echo "  Can list orgs:          $([ "$level1_actual" = "true" ] && echo "YES ($level1_scope)" || echo "NO")"
    echo "  Can view org details:   $([ "$level2_actual" = "true" ] && echo "YES" || echo "NO")"
    echo "  Can view own role:      $([ "$level3_actual" = "true" ] && echo "YES" || echo "NO")"
    if [ "$level3_actual" = "true" ]; then
        echo "  Role in organization:   $level3_role"
    fi
    echo ""
fi

exit $exit_code
