#!/bin/bash

# Script to select credentials from .env files and list Open Horizon users in an organization
# Usage: ./list-users.sh [org-id]
#   If org-id is not provided, uses HZN_ORG_ID from the selected .env file

# Strict error handling
set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Setup cleanup trap
# shellcheck disable=SC2119  # Function doesn't use positional parameters
setup_cleanup_trap

# Parse command line arguments
TARGET_ORG=""
if [ $# -gt 0 ]; then
    TARGET_ORG="$1"
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
    # shellcheck disable=SC2119  # Function doesn't use positional parameters
    selected_file=""  # Will be set by select_env_file
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