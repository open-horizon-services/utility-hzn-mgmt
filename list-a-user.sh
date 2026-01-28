#!/bin/bash

# Script to display the current authenticated Open Horizon user using REST API
# This validates credentials and shows user information including admin privileges
# Usage: ./list-a-user.sh [OPTIONS] [ENV_FILE]

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
            echo "Display the current authenticated Open Horizon user using REST API"
            echo "This validates credentials and shows user information including admin privileges"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed JSON response from API"
            echo "  -j, --json       Output raw JSON only (no headers, colors, or messages)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Examples:"
            echo "  $0                          # Interactive mode, prompts for .env file"
            echo "  $0 mycreds.env              # Use specific .env file"
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

# Display configuration
display_config

# Check if curl is installed
check_curl || exit 1

# Check if jq is installed (optional but recommended)
check_jq

# Parse authentication credentials
parse_auth

# Use the Exchange URL as-is (it should already include the API version path)
# Remove trailing slash if present
BASE_URL="${HZN_EXCHANGE_URL%/}"

# Fetch current user information
if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching current user information from Exchange API..."
    echo ""
fi

# Make the API call to get the specific user
# The endpoint is /orgs/{org}/users/{username}
# Using -k to allow self-signed certificates (common in Open Horizon deployments)
response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${HZN_ORG_ID}/users/${AUTH_USER}" 2>&1)

# Extract HTTP status code (last line)
http_code=$(echo "$response" | tail -n1)
# Extract response body (all but last line)
response_body=$(echo "$response" | sed '$d')

# Check HTTP status code
if [ "$http_code" -ne 200 ]; then
    print_error "Failed to retrieve user information (HTTP $http_code)"
    echo ""
    echo "Response:"
    echo "$response_body"
    echo ""
    
    # Check if it's an authentication error
    if echo "$response_body" | grep -qi "invalid credentials\|not authorized\|authentication"; then
        print_error "Authentication failed - invalid credentials"
        echo ""
        echo "Troubleshooting authentication:"
        echo "  1. Verify HZN_EXCHANGE_USER_AUTH format is 'username:password'"
        echo "  2. Check that the user exists in organization '$HZN_ORG_ID'"
        echo "  3. Verify the password is correct"
        echo ""
        # Show the auth format being used (mask password)
        AUTH_DISPLAY="${FULL_AUTH%%:*}:****"
        echo "Current auth format being used: ${AUTH_DISPLAY}"
    elif echo "$response_body" | grep -qi "not found"; then
        print_error "User not found"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Verify the user '$AUTH_USER' exists in organization '$HZN_ORG_ID'"
        echo "  2. Check the HZN_EXCHANGE_USER_AUTH format"
    else
        echo "Troubleshooting tips:"
        echo "  1. Verify your credentials are correct"
        echo "  2. Check that the Exchange URL is reachable: $BASE_URL"
        echo "  3. Ensure the user '$AUTH_USER' exists in organization '$HZN_ORG_ID'"
    fi
    exit 1
fi

if [ "$JSON_ONLY" = false ]; then
    print_success "User credentials validated successfully"
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

# Display output based on mode
if [ "$JSON_ONLY" = true ]; then
    # JSON-only mode: output raw JSON without any formatting
    echo "$response_body"
    
elif [ "$VERBOSE" = true ]; then
    # Verbose mode: show full JSON response with headers
    print_header "Current User (Detailed JSON)"
    echo ""
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$response_body" | jq '.'
    else
        echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    fi
    echo ""
    print_success "User information retrieved successfully"
    
else
    # Default mode: formatted user information display
    print_header "Current User Information"
    echo ""
    
    # Parse and display user information
    # Response structure: {"users": {"org/user": {...}}, "lastIndex": 0}
    if [ "$JQ_AVAILABLE" = true ]; then
        # Use jq for structured output
        user_key=$(echo "$response_body" | jq -r '.users | keys[0]')
        user_data=$(echo "$response_body" | jq -r ".users[\"$user_key\"]")
        
        # Extract fields
        email=$(echo "$user_data" | jq -r '.email // "N/A"')
        admin=$(echo "$user_data" | jq -r '.admin // false')
        hub_admin=$(echo "$user_data" | jq -r '.hubAdmin // false')
        last_updated=$(echo "$user_data" | jq -r '.lastUpdated // "N/A"')
        updated_by=$(echo "$user_data" | jq -r '.updatedBy // "N/A"')
        
        echo "  User ID:       $user_key"
        echo "  Email:         $email"
        
        # Display admin status with color coding
        if [ "$admin" = "true" ]; then
            echo -e "  Org Admin:     ${GREEN}Yes${NC}"
        else
            echo "  Org Admin:     No"
        fi
        
        if [ "$hub_admin" = "true" ]; then
            echo -e "  Hub Admin:     ${MAGENTA}Yes${NC}"
        else
            echo "  Hub Admin:     No"
        fi
        
        echo "  Last Updated:  $last_updated"
        echo "  Updated By:    $updated_by"
    else
        # Fallback to python for JSON parsing
        user_key=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(list(data.get('users', {}).keys())[0])" 2>/dev/null)
        email=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); u=list(data.get('users', {}).values())[0]; print(u.get('email', 'N/A'))" 2>/dev/null)
        admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); u=list(data.get('users', {}).values())[0]; print(str(u.get('admin', False)).lower())" 2>/dev/null)
        hub_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); u=list(data.get('users', {}).values())[0]; print(str(u.get('hubAdmin', False)).lower())" 2>/dev/null)
        last_updated=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); u=list(data.get('users', {}).values())[0]; print(u.get('lastUpdated', 'N/A'))" 2>/dev/null)
        updated_by=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); u=list(data.get('users', {}).values())[0]; print(u.get('updatedBy', 'N/A'))" 2>/dev/null)
        
        echo "  User ID:       $user_key"
        echo "  Email:         $email"
        
        # Display admin status with color coding
        if [ "$admin" = "true" ]; then
            echo -e "  Org Admin:     ${GREEN}Yes${NC}"
        else
            echo "  Org Admin:     No"
        fi
        
        if [ "$hub_admin" = "true" ]; then
            echo -e "  Hub Admin:     ${MAGENTA}Yes${NC}"
        else
            echo "  Hub Admin:     No"
        fi
        
        echo "  Last Updated:  $last_updated"
        echo "  Updated By:    $updated_by"
    fi
    
    echo ""
    print_success "User information retrieved successfully"
fi

# Additional info (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    echo ""
    print_info "API Endpoint: ${BASE_URL}/orgs/${HZN_ORG_ID}/users/${AUTH_USER}"
    echo ""
    
    # Summary of user permissions
    echo "User role legend:"
    echo -e "  ${GREEN}Org Admin: Yes${NC}  - Administrative access within this organization"
    echo -e "  ${MAGENTA}Hub Admin: Yes${NC}  - Hub-level administrative access"
fi
