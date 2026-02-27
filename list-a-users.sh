#!/bin/bash

# Script to list Open Horizon users using REST API
# Usage: ./list-a-users.sh [OPTIONS] [ENV_FILE]

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
            echo "List Open Horizon users using REST API"
            echo ""
            echo "Options:"
            echo "  -o, --org ORG    Target organization to query (default: auth org from HZN_ORG_ID)"
            echo "  -v, --verbose    Show detailed JSON response from API with headers"
            echo "  -j, --json       Output raw JSON only (no headers, colors, or messages)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Default: Shows simple list of user names"
            echo ""
            echo "Examples:"
            echo "  $0                          # Interactive mode, prompts for .env file"
            echo "  $0 mycreds.env              # Use specific .env file"
            echo "  $0 -o other-org             # Query users in different organization"
            echo "  $0 --json mycreds.env       # JSON output with specific .env file"
            echo "  $0 --verbose                # Verbose output, prompts for .env file"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
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
select_env_file "$ENV_FILE" || exit 1
load_credentials "$selected_file" || exit 1

# Set target org to auth org if not specified
if [ -z "$TARGET_ORG" ]; then
    TARGET_ORG="$HZN_ORG_ID"
fi

# Display configuration
display_config

# Show target org if different from auth org
if [ "$TARGET_ORG" != "$HZN_ORG_ID" ]; then
    if [ "$JSON_ONLY" = false ]; then
        print_info "Target Organization: $TARGET_ORG"
        echo ""
    fi
fi

# Check if curl is installed
check_curl || exit 1

# Check if jq is installed (optional but recommended)
check_jq

# Parse authentication credentials
parse_auth

# Use the Exchange URL as-is (it should already include the API version path)
# Remove trailing slash if present
BASE_URL="${HZN_EXCHANGE_URL%/}"

# List users using REST API
if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching users from Exchange API..."
    echo ""
fi

# Display the API request in verbose mode
display_api_request "GET" "${BASE_URL}/orgs/${TARGET_ORG}/users"

# Make the API call
# Note: HZN_EXCHANGE_URL should already include the API version (e.g., /v1)
response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${TARGET_ORG}/users" 2>&1)

# Extract HTTP status code (last line)
http_code=$(echo "$response" | tail -n1)
# Extract response body (all but last line)
response_body=$(echo "$response" | sed '$d')

# Check HTTP status code
if [ "$http_code" -ne 200 ]; then
    print_error "Failed to list users (HTTP $http_code)"
    echo ""
    echo "Response:"
    echo "$response_body"
    echo ""
    
    # Check if it's an authentication error
    if echo "$response_body" | grep -q "invalid credentials"; then
        print_error "Authentication failed - invalid credentials"
        echo ""
        echo "Troubleshooting authentication:"
        echo "  1. Verify HZN_EXCHANGE_USER_AUTH format is 'username:password'"
        echo "  2. Check that the user exists in organization '$TARGET_ORG'"
        echo "  3. Verify the password is correct"
        echo "  4. Try using the hzn CLI to test: hzn exchange user list"
        echo ""
        # Show the auth format being used (mask password)
        AUTH_DISPLAY="${FULL_AUTH%%:*}:****"
        echo "Current auth format being used: ${AUTH_DISPLAY}"
    else
        echo "Troubleshooting tips:"
        echo "  1. Verify your credentials are correct"
        echo "  2. Check that the Exchange URL is reachable: $BASE_URL"
        echo "  3. Ensure your user has permission to list users"
        echo "  4. Check if the organization '$TARGET_ORG' exists"
    fi
    exit 1
fi

if [ "$JSON_ONLY" = false ]; then
    print_success "Users retrieved successfully"
    echo ""
fi

# Check if response is valid JSON
if ! echo "$response_body" | python3 -m json.tool &> /dev/null; then
    print_error "Invalid JSON response from API"
    echo ""
    echo "Response:"
    echo "$response_body"
    exit 1
fi

# Parse the response to get user names and details
if [ "$JQ_AVAILABLE" = true ]; then
    # Use jq for better JSON parsing (portable array population for Bash 3.x compatibility)
    user_names=()
    while IFS= read -r item; do
        [ -n "$item" ] && user_names+=("$item")
    done < <(echo "$response_body" | jq -r '.users | keys[]' 2>/dev/null || echo "")
    total_users=$(echo "$response_body" | jq -r '.users | length' 2>/dev/null || echo "0")
else
    # Fallback to basic parsing without jq (portable array population for Bash 3.x compatibility)
    user_names=()
    while IFS= read -r item; do
        [ -n "$item" ] && user_names+=("$item")
    done < <(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(data.get('users', {}).keys()))" 2>/dev/null || echo "")
    total_users=${#user_names[@]}
fi

# Check user details and permissions (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    admin_users=0
    regular_users=0
    hub_admin_users=0
    
    print_header "User Summary"
    echo ""

    # Analyze user details
    for user in "${user_names[@]}"; do
        # Extract user details from the response
        if [ "$JQ_AVAILABLE" = true ]; then
            is_admin=$(echo "$response_body" | jq -r ".users[\"$user\"].admin // false" 2>/dev/null)
            is_hub_admin=$(echo "$response_body" | jq -r ".users[\"$user\"].hubAdmin // false" 2>/dev/null)
        else
            is_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('users', {}).get('$user', {}).get('admin', False)).lower())" 2>/dev/null)
            is_hub_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('users', {}).get('$user', {}).get('hubAdmin', False)).lower())" 2>/dev/null)
        fi
        
        # Count users by their role flags
        if [ "$is_admin" = "true" ]; then
            ((admin_users++))
        fi
        if [ "$is_hub_admin" = "true" ]; then
            ((hub_admin_users++))
        fi
        if [ "$is_admin" = "false" ] && [ "$is_hub_admin" = "false" ]; then
            ((regular_users++))
        fi
    done

    echo "Total users found: $total_users"
    echo "Hub admin users: $hub_admin_users"
    echo "Organization admin users: $admin_users"
    echo "Regular users: $regular_users"
    echo ""
fi

# Display output based on mode
if [ "$JSON_ONLY" = true ]; then
    # JSON-only mode: output raw JSON without any formatting
    echo "$response_body"
    
elif [ "$VERBOSE" = true ]; then
    # Verbose mode: show full JSON response with headers
    print_header "Users (Detailed JSON)"
    echo ""
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$response_body" | jq '.'
    else
        echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    fi
    echo ""
    print_success "Listed $total_users user(s)"
    
else
    # Default mode: simple list of user names with admin status
    print_header "Users in Organization: $TARGET_ORG"
    echo ""
    
    for user in "${user_names[@]}"; do
        # Extract just the username (remove org/ prefix if present)
        display_user="${user#*/}"
        
        # Extract user details
        if [ "$JQ_AVAILABLE" = true ]; then
            is_admin=$(echo "$response_body" | jq -r ".users[\"$user\"].admin // false" 2>/dev/null)
            is_hub_admin=$(echo "$response_body" | jq -r ".users[\"$user\"].hubAdmin // false" 2>/dev/null)
            email=$(echo "$response_body" | jq -r ".users[\"$user\"].email // \"N/A\"" 2>/dev/null)
        else
            is_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('users', {}).get('$user', {}).get('admin', False)).lower())" 2>/dev/null)
            is_hub_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('users', {}).get('$user', {}).get('hubAdmin', False)).lower())" 2>/dev/null)
            email=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('users', {}).get('$user', {}).get('email', 'N/A'))" 2>/dev/null)
        fi
        
        # Format output with role indicator
        # Users can only have ONE badge: Org Admin takes precedence over Hub Admin
        if [ "$is_admin" = "true" ]; then
            echo -e "$display_user ${YELLOW}[Org Admin]${NC} - $email"
        elif [ "$is_hub_admin" = "true" ]; then
            echo -e "$display_user ${MAGENTA}[Hub Admin]${NC} - $email"
        else
            echo "$display_user - $email"
        fi
    done
    echo ""
    print_success "Listed $total_users user(s)"
fi

# Additional info (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    echo ""
    print_info "API Endpoint: ${BASE_URL}/orgs/${TARGET_ORG}/users"
    print_info "Authenticated as: ${HZN_ORG_ID}/${AUTH_USER}"
    echo ""

    # Summary of user permissions
    if [ "$total_users" -gt 0 ]; then
        print_success "Successfully retrieved all users in organization '$TARGET_ORG'"
        echo ""
        echo "User role legend:"
        echo -e "  ${YELLOW}[Org Admin]${NC}  - Administrative access within this organization (admin: true)"
        echo -e "  ${MAGENTA}[Hub Admin]${NC}  - Hub-level administrative access (admin: false, hubAdmin: true)"
        echo "  (no badge)   - Regular user with standard permissions"
    else
        print_warning "No users found in organization '$TARGET_ORG'"
    fi
fi
