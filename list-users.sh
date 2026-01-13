#!/bin/bash

# Script to select credentials from .env files and list Open Horizon users in an organization
# Usage: ./list-users.sh [org-id]
#   If org-id is not provided, uses HZN_ORG_ID from the selected .env file

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

# Parse command line arguments
TARGET_ORG=""
if [ $# -gt 0 ]; then
    TARGET_ORG="$1"
    print_info "Organization specified: $TARGET_ORG"
    echo ""
fi

# Check if credentials are already set in environment (called from another script)
SKIP_ENV_SELECTION=false
if [ -n "$HZN_EXCHANGE_URL" ] && [ -n "$HZN_ORG_ID" ] && [ -n "$HZN_EXCHANGE_USER_AUTH" ]; then
    print_info "Using credentials from environment variables"
    SKIP_ENV_SELECTION=true
    echo ""
fi

# Only prompt for .env file selection if credentials are not already set
if [ "$SKIP_ENV_SELECTION" = false ]; then
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
    
    print_success "Credentials loaded successfully"
    echo ""
fi

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