#!/bin/bash

# Script to list Open Horizon organizations using REST API
# Usage: ./list-a-orgs.sh [OPTIONS] [ENV_FILE]

# Strict error handling
set -euo pipefail

# Default output mode
VERBOSE=false
JSON_ONLY=false
ENV_FILE=""

# Parse command line arguments
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
            echo "List Open Horizon organizations using REST API"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed JSON response from API with headers"
            echo "  -j, --json       Output raw JSON only (no headers, colors, or messages)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Default: Shows simple list of organization names"
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
setup_cleanup_trap

# Handle .env file selection
# Handle .env file selection and load credentials
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

# List organizations using REST API
if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching organizations from Exchange API..."
    echo ""
fi

# Make the API call
# Note: HZN_EXCHANGE_URL should already include the API version (e.g., /v1)
response=$(curl -sS -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs" 2>&1)

# Extract HTTP status code (last line)
http_code=$(echo "$response" | tail -n1)
# Extract response body (all but last line)
response_body=$(echo "$response" | sed '$d')

# Check HTTP status code
if [ "$http_code" -ne 200 ]; then
    print_error "Failed to list organizations (HTTP $http_code)"
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
        echo "  2. Check that the user exists in organization '$HZN_ORG_ID'"
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
        echo "  3. Ensure your user has permission to list organizations"
        echo "  4. Check if the organization '$HZN_ORG_ID' exists"
    fi
    exit 1
fi

if [ "$JSON_ONLY" = false ]; then
    print_success "Organizations retrieved successfully"
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

# Parse the response to get organization names and details
if [ "$JQ_AVAILABLE" = true ]; then
    # Use jq for better JSON parsing
    org_names=($(echo "$response_body" | jq -r '.orgs | keys[]' 2>/dev/null || echo ""))
    total_orgs=$(echo "$response_body" | jq -r '.orgs | length' 2>/dev/null || echo "0")
else
    # Fallback to basic parsing without jq
    org_names=($(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(data.get('orgs', {}).keys()))" 2>/dev/null || echo ""))
    total_orgs=${#org_names[@]}
fi

# Check if user has access to all organizations (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    accessible_orgs=0
    inaccessible_orgs=0
    access_errors=()

    print_header "Organization Access Summary"
    echo ""

    # Test access to each organization
    for org in "${org_names[@]}"; do
        # Try to get detailed info for each org
        org_response=$(curl -sS -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${org}" 2>&1)
        org_http_code=$(echo "$org_response" | tail -n1)
        
        if [ "$org_http_code" -eq 200 ]; then
            ((accessible_orgs++))
        else
            ((inaccessible_orgs++))
            access_errors+=("$org (HTTP $org_http_code)")
        fi
    done

    echo "Total organizations found: $total_orgs"
    echo "Accessible organizations: $accessible_orgs"
    echo "Inaccessible organizations: $inaccessible_orgs"
    echo ""

    if [ $inaccessible_orgs -gt 0 ]; then
        print_warning "You do not have access to all organizations"
        echo ""
        echo "Organizations with access issues:"
        for error in "${access_errors[@]}"; do
            echo "  - $error"
        done
        echo ""
    fi
fi

# Display output based on mode
if [ "$JSON_ONLY" = true ]; then
    # JSON-only mode: output raw JSON without any formatting
    echo "$response_body"
    
elif [ "$VERBOSE" = true ]; then
    # Verbose mode: show full JSON response with headers
    print_header "Organizations (Detailed JSON)"
    echo ""
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$response_body" | jq '.'
    else
        echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    fi
    echo ""
    print_success "Listed $total_orgs organization(s)"
    
else
    # Default mode: simple list of org names
    print_header "Organizations"
    echo ""
    for org in "${org_names[@]}"; do
        echo "$org"
    done
    echo ""
    print_success "Listed $total_orgs organization(s)"
fi

# Additional info (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    echo ""
    print_info "API Endpoint: ${BASE_URL}/orgs"
    print_info "Authenticated as: ${HZN_ORG_ID}/${AUTH_USER}"
    echo ""

    # Summary of access permissions
    if [ $inaccessible_orgs -eq 0 ]; then
        print_success "You have full access to all organizations"
    else
        print_warning "Limited access: You can view $accessible_orgs out of $total_orgs organizations"
        echo ""
        echo "To gain access to restricted organizations:"
        echo "  1. Contact your Open Horizon administrator"
        echo "  2. Request appropriate permissions for your user account"
        echo "  3. Verify you're using the correct organization context"
    fi
fi