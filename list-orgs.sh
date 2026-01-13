#!/bin/bash

# Script to select credentials from .env files and list Open Horizon organizations
# Usage: ./list-orgs.sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Find all .env files in the current directory
print_info "Searching for .env files..."
env_files=()
while IFS= read -r file; do
    env_files+=("$file")
done < <(find . -maxdepth 1 -name "*.env" -type f | sort)

if [ ${#env_files[@]} -eq 0 ]; then
    print_error "No .env files found in the current directory"
    echo ""
    echo "Please create a .env file with the following variables:"
    echo "  HZN_EXCHANGE_URL=https://<exchange-host>/api/v1"
    echo "  HZN_ORG_ID=<your-org-id>"
    echo "  HZN_EXCHANGE_USER_AUTH=<user>:<password>"
    exit 1
fi

print_success "Found ${#env_files[@]} .env file(s)"
echo ""

# Display available .env files
echo "Available credential files:"
for i in "${!env_files[@]}"; do
    filename=$(basename "${env_files[$i]}")
    echo "  $((i+1)). $filename"
done
echo ""

# Prompt user to select a file
while true; do
    read -p "Select a file (1-${#env_files[@]}): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#env_files[@]}" ]; then
        selected_file="${env_files[$((selection-1))]}"
        break
    else
        print_error "Invalid selection. Please enter a number between 1 and ${#env_files[@]}"
    fi
done

print_success "Selected: $(basename "$selected_file")"
echo ""

# Source the selected .env file
print_info "Loading credentials from $(basename "$selected_file")..."
set -a  # Automatically export all variables
source "$selected_file"
set +a

# Verify required environment variables are set
required_vars=("HZN_EXCHANGE_URL" "HZN_ORG_ID" "HZN_EXCHANGE_USER_AUTH")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -gt 0 ]; then
    print_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

print_success "Credentials loaded successfully"
echo ""

# Display configuration
print_info "Configuration:"
echo "  Exchange URL: $HZN_EXCHANGE_URL"
echo "  Organization: $HZN_ORG_ID"
echo "  User: ${HZN_EXCHANGE_USER_AUTH%%:*}"
echo ""

# Check if hzn CLI is installed
if ! command -v hzn &> /dev/null; then
    print_error "hzn CLI is not installed or not in PATH"
    echo ""
    echo "Please install the Open Horizon CLI:"
    echo "  https://github.com/open-horizon/anax/releases"
    exit 1
fi

# Check if hzn agent is running
print_info "Checking if Horizon agent is running..."
if ! hzn version &> /dev/null; then
    print_warning "Horizon agent may not be running"
    echo ""
    echo "On macOS, you can start it with:"
    echo "  horizon-container start"
    echo ""
fi

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