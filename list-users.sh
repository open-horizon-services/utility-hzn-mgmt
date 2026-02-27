#!/bin/bash

# Script to select credentials from .env files and list Open Horizon users in an organization
# Usage: ./list-users.sh [OPTIONS] [org-id]

# Strict error handling
set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Show usage information
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [org-id]

List Open Horizon users in an organization.

OPTIONS:
    -h, --help      Show this help message and exit

ARGUMENTS:
    org-id          Optional: Organization ID to query
                    If not provided, uses HZN_ORG_ID from environment/credentials

EXAMPLES:
    $(basename "$0")                    # List users in auth organization
    $(basename "$0") myorg              # List users in specific organization

REQUIRED ENVIRONMENT VARIABLES (in .env file or environment):
    HZN_EXCHANGE_URL          The Horizon Exchange API URL
    HZN_ORG_ID                Your organization ID (for authentication)
    HZN_EXCHANGE_USER_AUTH    User credentials (user:password)

NOTES:
    - Can be called standalone or from list-orgs.sh
    - If credentials are in environment, skips .env file selection
    - Requires hzn CLI to be installed and agent running

EOF
    exit 0
}

# Setup cleanup trap
# shellcheck disable=SC2119  # Function doesn't use positional parameters
setup_cleanup_trap

# Parse command line arguments
TARGET_ORG=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            ;;
        *)
            TARGET_ORG="$1"
            shift
            ;;
    esac
done

if [ -n "$TARGET_ORG" ]; then
    print_info "Organization specified: $TARGET_ORG"
    echo ""
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
    # shellcheck disable=SC2119  # select_env_file accepts optional arg, intentionally called without args for interactive mode
    select_env_file || exit 1
    load_credentials "$selected_file" || exit 1
fi

# Determine which organization to query
if [ -z "$TARGET_ORG" ]; then
    TARGET_ORG="$HZN_ORG_ID"
    print_info "Using organization from .env file: $TARGET_ORG"
else
    print_info "Using specified organization: $TARGET_ORG"
fi
echo ""

# Display configuration
print_info "Configuration:"
echo "  Exchange URL: $HZN_EXCHANGE_URL"
echo "  Query Organization: $TARGET_ORG"
echo "  Auth Organization: $HZN_ORG_ID"
echo "  User: ${HZN_EXCHANGE_USER_AUTH%%:*}"
echo ""

# Check if hzn CLI is installed
check_hzn_cli || exit 1

# Check if hzn agent is running
check_hzn_agent

# List users in the organization
print_info "Fetching users from organization '$TARGET_ORG'..."
echo ""

# Use hzn exchange user list with the target organization
if HZN_ORG_ID="$TARGET_ORG" hzn exchange user list -a 2>&1; then
    echo ""
    print_success "Users listed successfully for organization '$TARGET_ORG'"
else
    echo ""
    print_error "Failed to list users for organization '$TARGET_ORG'"
    echo ""
    echo "Troubleshooting tips:"
    echo "  1. Verify your credentials are correct"
    echo "  2. Check that the Exchange URL is reachable"
    echo "  3. Ensure your user has permission to list users in organization '$TARGET_ORG'"
    echo "  4. Verify the organization '$TARGET_ORG' exists"
    echo "  5. Try: curl -u \"\$HZN_ORG_ID/\${HZN_EXCHANGE_USER_AUTH%%:*}:\${HZN_EXCHANGE_USER_AUTH#*:}\" \"\$HZN_EXCHANGE_URL/orgs/$TARGET_ORG/users\""
    exit 1
fi