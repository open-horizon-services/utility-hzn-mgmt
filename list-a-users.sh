#!/bin/bash

# Script to list Open Horizon users using REST API
# Usage: ./list-a-users.sh [OPTIONS] [ENV_FILE]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

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
            echo "List Open Horizon users using REST API"
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
            echo "Default: Shows simple list of user names"
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

# Function to print colored messages (skip in JSON-only mode)
print_info() {
    if [ "$JSON_ONLY" = false ]; then
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

print_success() {
    if [ "$JSON_ONLY" = false ]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
}

print_error() {
    if [ "$JSON_ONLY" = false ]; then
        echo -e "${RED}✗${NC} $1"
    else
        # In JSON mode, still output errors to stderr
        echo -e "${RED}✗${NC} $1" >&2
    fi
}

print_warning() {
    if [ "$JSON_ONLY" = false ]; then
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

print_header() {
    if [ "$JSON_ONLY" = false ]; then
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}$1${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    fi
}

# Handle .env file selection
if [ -n "$ENV_FILE" ]; then
    # Env file specified as argument
    if [ ! -f "$ENV_FILE" ]; then
        print_error "Specified .env file not found: $ENV_FILE"
        echo ""
        echo "Please provide a valid .env file path"
        exit 1
    fi
    selected_file="$ENV_FILE"
    if [ "$JSON_ONLY" = false ]; then
        print_success "Using specified file: $(basename "$selected_file")"
        echo ""
    fi
else
    # No env file specified, find and prompt for selection
    if [ "$JSON_ONLY" = false ]; then
        print_info "Searching for .env files..."
    fi
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
        echo ""
        echo "Or specify a .env file: $0 path/to/file.env"
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
fi

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

if [ "$JSON_ONLY" = false ]; then
    print_success "Credentials loaded successfully"
    echo ""

    # Display configuration
    print_info "Configuration:"
    echo "  Exchange URL: $HZN_EXCHANGE_URL"
    echo "  Organization: $HZN_ORG_ID"
    echo "  User: ${HZN_EXCHANGE_USER_AUTH%%:*}"
    echo ""
fi

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    print_error "curl is not installed or not in PATH"
    echo ""
    echo "Please install curl to use this script"
    exit 1
fi

# Check if jq is installed (optional but recommended)
JQ_AVAILABLE=false
if command -v jq &> /dev/null; then
    JQ_AVAILABLE=true
fi

# Parse authentication credentials
# HZN_EXCHANGE_USER_AUTH is already in format org/user:password or user:password
# Check if it already contains org/ prefix
if [[ "$HZN_EXCHANGE_USER_AUTH" == *"/"* ]]; then
    # Already has org/user:password format
    FULL_AUTH="$HZN_EXCHANGE_USER_AUTH"
    AUTH_USER="${HZN_EXCHANGE_USER_AUTH%%:*}"  # This will be org/user
    AUTH_USER="${AUTH_USER#*/}"  # Extract just the user part
else
    # Only has user:password format, need to prepend org
    AUTH_USER="${HZN_EXCHANGE_USER_AUTH%%:*}"
    AUTH_PASS="${HZN_EXCHANGE_USER_AUTH#*:}"
    FULL_AUTH="${HZN_ORG_ID}/${AUTH_USER}:${AUTH_PASS}"
fi

# Use the Exchange URL as-is (it should already include the API version path)
# Remove trailing slash if present
BASE_URL="${HZN_EXCHANGE_URL%/}"

# List users using REST API
if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching users from Exchange API..."
    echo ""
fi

# Make the API call
# Note: HZN_EXCHANGE_URL should already include the API version (e.g., /v1)
response=$(curl -sS -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${HZN_ORG_ID}/users" 2>&1)

# Extract HTTP status code (last line)
http_code=$(echo "$response" | tail -n1)
# Extract response body (all but last line)
response_body=$(echo "$response" | sed '$d')

# Check HTTP status code
if [ "$http_code" -ne 200 ]; then
    print_error "Failed to list users (HTTP $http_code)"
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
        echo "  3. Ensure your user has permission to list users"
        echo "  4. Check if the organization '$HZN_ORG_ID' exists"
    fi
    exit 1
fi

if [ "$JSON_ONLY" = false ]; then
    print_success "Users retrieved successfully"
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

# Parse the response to get user names and details
if [ "$JQ_AVAILABLE" = true ]; then
    # Use jq for better JSON parsing
    user_names=($(echo "$response_body" | jq -r '.users | keys[]' 2>/dev/null || echo ""))
    total_users=$(echo "$response_body" | jq -r '.users | length' 2>/dev/null || echo "0")
else
    # Fallback to basic parsing without jq
    user_names=($(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(data.get('users', {}).keys()))" 2>/dev/null || echo ""))
    total_users=${#user_names[@]}
fi

# Check user details and permissions (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    admin_users=0
    regular_users=0
    hub_admin_users=0
    
    print_header "User Summary"
    echo ""

    # Analyze user details
    for user in "${user_names[@]}"; do
        # Extract user details from the response
        if [ "$JQ_AVAILABLE" = true ]; then
            is_admin=$(echo "$response_body" | jq -r ".users[\"$user\"].admin // false" 2>/dev/null)
            is_hub_admin=$(echo "$response_body" | jq -r ".users[\"$user\"].hubAdmin // false" 2>/dev/null)
        else
            is_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('users', {}).get('$user', {}).get('admin', False)).lower())" 2>/dev/null)
            is_hub_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('users', {}).get('$user', {}).get('hubAdmin', False)).lower())" 2>/dev/null)
        fi
        
        # Count users by their role flags
        if [ "$is_admin" = "true" ]; then
            ((admin_users++))
        fi
        if [ "$is_hub_admin" = "true" ]; then
            ((hub_admin_users++))
        fi
        if [ "$is_admin" = "false" ] && [ "$is_hub_admin" = "false" ]; then
            ((regular_users++))
        fi
    done

    echo "Total users found: $total_users"
    echo "Hub admin users: $hub_admin_users"
    echo "Organization admin users: $admin_users"
    echo "Regular users: $regular_users"
    echo ""
fi

# Display output based on mode
if [ "$JSON_ONLY" = true ]; then
    # JSON-only mode: output raw JSON without any formatting
    echo "$response_body"
    
elif [ "$VERBOSE" = true ]; then
    # Verbose mode: show full JSON response with headers
    print_header "Users (Detailed JSON)"
    echo ""
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$response_body" | jq '.'
    else
        echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    fi
    echo ""
    print_success "Listed $total_users user(s)"
    
else
    # Default mode: simple list of user names with admin status
    print_header "Users in Organization: $HZN_ORG_ID"
    echo ""
    
    for user in "${user_names[@]}"; do
        # Extract just the username (remove org/ prefix if present)
        display_user="${user#*/}"
        
        # Extract user details
        if [ "$JQ_AVAILABLE" = true ]; then
            is_admin=$(echo "$response_body" | jq -r ".users[\"$user\"].admin // false" 2>/dev/null)
            is_hub_admin=$(echo "$response_body" | jq -r ".users[\"$user\"].hubAdmin // false" 2>/dev/null)
            email=$(echo "$response_body" | jq -r ".users[\"$user\"].email // \"N/A\"" 2>/dev/null)
        else
            is_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('users', {}).get('$user', {}).get('admin', False)).lower())" 2>/dev/null)
            is_hub_admin=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('users', {}).get('$user', {}).get('hubAdmin', False)).lower())" 2>/dev/null)
            email=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('users', {}).get('$user', {}).get('email', 'N/A'))" 2>/dev/null)
        fi
        
        # Format output with role indicator
        # Users can only have ONE badge: Org Admin takes precedence over Hub Admin
        if [ "$is_admin" = "true" ]; then
            echo -e "$display_user ${YELLOW}[Org Admin]${NC} - $email"
        elif [ "$is_hub_admin" = "true" ]; then
            echo -e "$display_user ${MAGENTA}[Hub Admin]${NC} - $email"
        else
            echo "$display_user - $email"
        fi
    done
    echo ""
    print_success "Listed $total_users user(s)"
fi

# Additional info (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    echo ""
    print_info "API Endpoint: ${BASE_URL}/orgs/${HZN_ORG_ID}/users"
    print_info "Authenticated as: ${HZN_ORG_ID}/${AUTH_USER}"
    echo ""

    # Summary of user permissions
    if [ $total_users -gt 0 ]; then
        print_success "Successfully retrieved all users in organization '$HZN_ORG_ID'"
        echo ""
        echo "User role legend:"
        echo -e "  ${YELLOW}[Org Admin]${NC}  - Administrative access within this organization (admin: true)"
        echo -e "  ${MAGENTA}[Hub Admin]${NC}  - Hub-level administrative access (admin: false, hubAdmin: true)"
        echo "  (no badge)   - Regular user with standard permissions"
    else
        print_warning "No users found in organization '$HZN_ORG_ID'"
    fi
fi