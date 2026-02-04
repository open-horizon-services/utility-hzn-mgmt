#!/bin/bash

# Script to test Open Horizon credentials from .env files
# Usage: ./test-credentials.sh [OPTIONS] [env-file]

# Strict error handling
set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Show usage information
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [env-file]

Test and validate Open Horizon credentials from .env files.
Verifies Exchange connectivity, authentication, and user permissions.

OPTIONS:
    -h, --help      Show this help message and exit

ARGUMENTS:
    env-file        Optional: Path to .env file with credentials
                    If not provided, will prompt to select from available .env files

EXAMPLES:
    $(basename "$0")                    # Interactive mode - select .env file
    $(basename "$0") mycreds.env        # Test specific .env file

REQUIRED ENVIRONMENT VARIABLES (in .env file):
    HZN_EXCHANGE_URL          The Horizon Exchange API URL
    HZN_ORG_ID                Your organization ID
    HZN_EXCHANGE_USER_AUTH    User credentials (user:password)

VALIDATION CHECKS:
    ✓ Exchange URL is reachable
    ✓ Organization exists
    ✓ User is authenticated
    ✓ User has permission to list users
    ✓ Counts users in organization

EOF
    exit 0
}

# Setup cleanup trap
# shellcheck disable=SC2119  # Function doesn't use positional parameters
setup_cleanup_trap

# Parse command line arguments
ENV_FILE_ARG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            ;;
        *)
            ENV_FILE_ARG="$1"
            shift
            ;;
    esac
done

# Select and load credentials
selected_file=""  # Will be set by select_env_file
if [ -n "$ENV_FILE_ARG" ]; then
    select_env_file "$ENV_FILE_ARG" || exit 1
else
    # shellcheck disable=SC2119  # select_env_file accepts optional arg, intentionally called without args for interactive mode
    select_env_file || exit 1
fi
load_credentials "$selected_file" || exit 1

# Display configuration
display_config

# Check if hzn CLI is installed
check_hzn_cli || exit 1

# Check if hzn agent is running
check_hzn_agent

# Test credentials by listing users
print_info "Testing credentials with 'hzn exchange user list'..."
echo ""

# Capture user list output
user_output=$(hzn exchange user list 2>&1)
exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo "$user_output"
    echo ""
    print_error "Credential test FAILED"
    echo ""
    echo "Troubleshooting tips:"
    echo "  1. Verify your credentials are correct in $(basename "$selected_file")"
    echo "  2. Check that the Exchange URL is reachable: $HZN_EXCHANGE_URL"
    echo "  3. Ensure your user has permission to list users in organization: $HZN_ORG_ID"
    echo "  4. Verify the organization exists and you have access to it"
    echo "  5. Try manually: curl -u \"\$HZN_ORG_ID/\${HZN_EXCHANGE_USER_AUTH%%:*}:\${HZN_EXCHANGE_USER_AUTH#*:}\" \"\$HZN_EXCHANGE_URL/orgs/\$HZN_ORG_ID/users\""
    exit 1
fi

# Display the user list
echo "$user_output"
echo ""
print_success "Credential test PASSED"
echo ""

# Parse user information from the output
print_info "Credential Summary:"
echo "  ✓ Exchange URL is reachable"
echo "  ✓ Organization '$HZN_ORG_ID' exists"
echo "  ✓ User '${HZN_EXCHANGE_USER_AUTH%%:*}' is authenticated"
echo "  ✓ User has permission to list users"
echo ""

# Count users in the output (JSON object format)
# Count only top-level keys that contain "/" (user format: "org/user")
user_count=$(echo "$user_output" | grep -o '"[^"]*/' | wc -l | tr -d ' ')
if [ "$user_count" -gt 0 ]; then
    print_success "Found $user_count user(s) in organization '$HZN_ORG_ID'"
else
    print_warning "No users found or unable to parse user list"
fi

echo ""
print_success "All credential checks completed successfully!"