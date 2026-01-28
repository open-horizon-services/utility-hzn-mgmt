#!/bin/bash

# Script to display the current authenticated Open Horizon user
# This validates credentials and shows user information including admin privileges
# Usage: ./list-user.sh [env-file]

# Strict error handling
set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Setup cleanup trap
# shellcheck disable=SC2119  # Function doesn't use positional parameters
setup_cleanup_trap

# Parse command line arguments
ENV_FILE_ARG=""
if [ $# -gt 0 ]; then
    ENV_FILE_ARG="$1"
fi

# Check if credentials are already set in environment (called from another script)
SKIP_ENV_SELECTION=false
if [ -n "${HZN_EXCHANGE_URL:-}" ] && [ -n "${HZN_ORG_ID:-}" ] && [ -n "${HZN_EXCHANGE_USER_AUTH:-}" ]; then
    print_info "Using credentials from environment variables"
    SKIP_ENV_SELECTION=true
    echo ""
fi

# Only prompt for .env file selection if credentials are not already set
if [ "$SKIP_ENV_SELECTION" = false ]; then
    selected_file=""  # Will be set by select_env_file
    if [ -n "$ENV_FILE_ARG" ]; then
        select_env_file "$ENV_FILE_ARG" || exit 1
    else
        # shellcheck disable=SC2119  # select_env_file accepts optional arg, intentionally called without args for interactive mode
        select_env_file || exit 1
    fi
    load_credentials "$selected_file" || exit 1
fi

# Display configuration
print_info "Configuration:"
echo "  Exchange URL: $HZN_EXCHANGE_URL"
echo "  Organization: $HZN_ORG_ID"
echo "  User: ${HZN_EXCHANGE_USER_AUTH%%:*}"
echo ""

# Check if hzn CLI is installed
check_hzn_cli || exit 1

# Check if hzn agent is running
check_hzn_agent

# Check if jq is available for better JSON parsing
check_jq

# Fetch current user information
print_info "Fetching current user information..."
echo ""

# Use hzn exchange user list (without -a flag to get only current user)
# Capture output and exit code separately to preserve error messages
user_output=$(hzn exchange user list 2>&1) || {
    exit_code=$?
    echo ""
    print_error "Failed to retrieve user information"
    echo ""
    echo "Error output:"
    echo "$user_output"
    echo ""
    echo "Troubleshooting tips:"
    echo "  1. Verify your credentials are correct"
    echo "  2. Check that the Exchange URL is reachable"
    echo "  3. Ensure your user exists in organization '$HZN_ORG_ID'"
    echo "  4. Try: hzn exchange user list"
    echo "  5. Check the Horizon agent is running: hzn version"
    exit $exit_code
}

print_success "User credentials validated successfully"
echo ""

print_header "Current User Information"
echo ""

# Parse and display user information
if [ "$JQ_AVAILABLE" = true ]; then
    # Use jq for structured output
    user_key=$(echo "$user_output" | jq -r 'keys[0]')
    user_data=$(echo "$user_output" | jq -r ".[\"$user_key\"]")
    
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
        echo -e "  Org Admin:     No"
    fi
    
    if [ "$hub_admin" = "true" ]; then
        echo -e "  Hub Admin:     ${MAGENTA}Yes${NC}"
    else
        echo -e "  Hub Admin:     No"
    fi
    
    echo "  Last Updated:  $last_updated"
    echo "  Updated By:    $updated_by"
else
    # Fallback: display raw JSON
    print_warning "jq not installed - displaying raw JSON output"
    echo ""
    echo "$user_output"
fi

echo ""
print_success "User information retrieved successfully"
