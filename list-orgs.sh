#!/bin/bash

# Script to select credentials from .env files and list Open Horizon organizations
# Usage: ./list-orgs.sh

# Strict error handling
set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Setup cleanup trap
setup_cleanup_trap

# Select and load credentials
select_env_file || exit 1
load_credentials "$selected_file" || exit 1

# Display configuration
display_config

# Check if hzn CLI is installed
check_hzn_cli || exit 1

# Check if hzn agent is running
check_hzn_agent

# List organizations
print_info "Fetching organizations from Exchange..."
echo ""

# Capture organization list output
org_output=$(hzn exchange org list 2>&1)
if [ $? -ne 0 ]; then
    echo "$org_output"
    echo ""
    print_error "Failed to list organizations"
    echo ""
    echo "Troubleshooting tips:"
    echo "  1. Verify your credentials are correct"
    echo "  2. Check that the Exchange URL is reachable"
    echo "  3. Ensure your user has permission to list organizations"
    echo "  4. Try: curl -u \"\$HZN_ORG_ID/\${HZN_EXCHANGE_USER_AUTH%%:*}:\${HZN_EXCHANGE_USER_AUTH#*:}\" \"\$HZN_EXCHANGE_URL/orgs\""
    exit 1
fi

# Display the organization list
echo "$org_output"
echo ""
print_success "Organizations listed successfully"
echo ""

# Parse organization names from the output (JSON array format)
# Extract org names from JSON array (format: ["org1", "org2", ...])
orgs=()
while IFS= read -r line; do
    # Match quoted strings in the array
    if [[ "$line" =~ \"([^\"]+)\" ]]; then
        org_name="${BASH_REMATCH[1]}"
        # Skip array brackets
        if [[ "$org_name" != "[" ]] && [[ "$org_name" != "]" ]]; then
            orgs+=("$org_name")
        fi
    fi
done <<< "$org_output"

if [ ${#orgs[@]} -eq 0 ]; then
    print_warning "No organizations found or unable to parse organization list"
    exit 0
fi

# Prompt user to select an organization to view users
echo ""
echo "═══════════════════════════════════════════════════════════════"
print_info "Select an organization to view its users:"
echo ""
echo "Available organizations:"
for i in "${!orgs[@]}"; do
    echo "  $((i+1)). ${orgs[$i]}"
done
echo "  0. Exit without viewing users"
echo ""

# Prompt user to select an organization
while true; do
    read -p "Select an organization (0-${#orgs[@]}): " org_selection
    
    if [[ "$org_selection" == "0" ]]; then
        print_info "Exiting without viewing users"
        exit 0
    fi
    
    if [[ "$org_selection" =~ ^[0-9]+$ ]] && [ "$org_selection" -ge 1 ] && [ "$org_selection" -le "${#orgs[@]}" ]; then
        selected_org="${orgs[$((org_selection-1))]}"
        break
    else
        print_error "Invalid selection. Please enter a number between 0 and ${#orgs[@]}"
    fi
done

print_success "Selected organization: $selected_org"
echo ""

# Check if list-users.sh exists
if [ ! -f "./list-users.sh" ]; then
    print_error "list-users.sh script not found in current directory"
    echo ""
    echo "Please ensure list-users.sh is in the same directory as this script"
    exit 1
fi

# Make sure list-users.sh is executable
if [ ! -x "./list-users.sh" ]; then
    print_info "Making list-users.sh executable..."
    chmod +x ./list-users.sh
fi

# Call list-users.sh with the selected organization
print_info "Calling list-users.sh for organization: $selected_org"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Export the current environment variables so list-users.sh can use them
export HZN_EXCHANGE_URL
export HZN_ORG_ID
export HZN_EXCHANGE_USER_AUTH

# Create a temporary .env file for list-users.sh to use
temp_env_file=$(mktemp /tmp/hzn-temp-XXXXXX.env)
cat > "$temp_env_file" << EOF
HZN_EXCHANGE_URL=$HZN_EXCHANGE_URL
HZN_ORG_ID=$HZN_ORG_ID
HZN_EXCHANGE_USER_AUTH=$HZN_EXCHANGE_USER_AUTH
EOF

# Call list-users.sh with the selected organization as an argument
# We'll modify the script to auto-select the temp env file
./list-users.sh "$selected_org"

# Clean up temporary file
rm -f "$temp_env_file"