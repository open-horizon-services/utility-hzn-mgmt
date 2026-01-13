#!/bin/bash

# Script to test Open Horizon credentials from .env files
# Usage: ./test-credentials.sh

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