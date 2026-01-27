#!/bin/bash

# Common library for Open Horizon admin utilities
# This file contains shared functions used across multiple scripts
# Source this file in your scripts with: source "${SCRIPT_DIR}/lib/common.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'  # Used by list-a-users.sh for hub admin badge
NC='\033[0m' # No Color

# Global flag for JSON-only mode (can be set by calling script)
JSON_ONLY=${JSON_ONLY:-false}

# Print functions
# These respect the JSON_ONLY flag to suppress output when needed
print_info() {
    if [ "$JSON_ONLY" != true ]; then
        echo -e "${BLUE}ℹ${NC} $1"
    fi
}

print_success() {
    if [ "$JSON_ONLY" != true ]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
}

print_error() {
    if [ "$JSON_ONLY" != true ]; then
        echo -e "${RED}✗${NC} $1" >&2
    else
        # In JSON mode, still output errors to stderr
        echo -e "${RED}✗${NC} $1" >&2
    fi
}

print_warning() {
    if [ "$JSON_ONLY" != true ]; then
        echo -e "${YELLOW}⚠${NC} $1"
    fi
}

print_header() {
    if [ "$JSON_ONLY" != true ]; then
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}$1${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    fi
}

# Find and list .env files in the current directory
# Returns: Array of .env file paths in the global variable env_files
find_env_files() {
    env_files=()
    while IFS= read -r file; do
        env_files+=("$file")
    done < <(find . -maxdepth 1 -name "*.env" -type f | sort)
}

# Display available .env files and prompt user to select one
# Arguments:
#   $1 - Optional: Pre-selected env file path
# Returns: Selected file path in the global variable selected_file
# shellcheck disable=SC2034  # selected_file is used by calling scripts
select_env_file() {
    # Declare selected_file for shellcheck
    selected_file=""
    local env_file_arg="${1:-}"
    
    # If env file specified as argument, use it
    if [ -n "$env_file_arg" ]; then
        if [ ! -f "$env_file_arg" ]; then
            print_error "Specified .env file not found: $env_file_arg"
            echo ""
            echo "Please provide a valid .env file path"
            return 1
        fi
        selected_file="$env_file_arg"
        if [ "$JSON_ONLY" != true ]; then
            print_success "Using specified file: $(basename "$selected_file")"
            echo ""
        fi
        return 0
    fi
    
    # Find .env files
    if [ "$JSON_ONLY" != true ]; then
        print_info "Searching for .env files..."
    fi
    
    find_env_files
    
    if [ ${#env_files[@]} -eq 0 ]; then
        print_error "No .env files found in the current directory"
        echo ""
        echo "Please create a .env file with the following variables:"
        echo "  HZN_EXCHANGE_URL=https://<exchange-host>/api/v1"
        echo "  HZN_ORG_ID=<your-org-id>"
        echo "  HZN_EXCHANGE_USER_AUTH=<user>:<password>"
        echo ""
        echo "Or specify a .env file as an argument"
        return 1
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
        read -r -p "Select a file (1-${#env_files[@]}): " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#env_files[@]}" ]; then
            selected_file="${env_files[$((selection-1))]}"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and ${#env_files[@]}"
        fi
    done
    
    print_success "Selected: $(basename "$selected_file")"
    echo ""
    return 0
}

# Load and validate credentials from .env file
# Arguments:
#   $1 - Path to .env file
# Returns: 0 on success, 1 on failure
# Sets: HZN_EXCHANGE_URL, HZN_ORG_ID, HZN_EXCHANGE_USER_AUTH environment variables
load_credentials() {
    local env_file="$1"
    
    if [ ! -f "$env_file" ]; then
        print_error "Environment file not found: $env_file"
        return 1
    fi
    
    print_info "Loading credentials from $(basename "$env_file")..."
    
    # Source the .env file
    set -a  # Automatically export all variables
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
    
    # Verify required environment variables are set
    local required_vars=("HZN_EXCHANGE_URL" "HZN_ORG_ID" "HZN_EXCHANGE_USER_AUTH")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        # Use parameter expansion with default to avoid unbound variable error
        if [ -z "${!var:-}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        return 1
    fi
    
    print_success "Credentials loaded successfully"
    echo ""
    return 0
}

# Parse authentication credentials from HZN_EXCHANGE_USER_AUTH
# Sets global variables: FULL_AUTH, AUTH_USER, AUTH_PASS
# HZN_EXCHANGE_USER_AUTH can be in format:
#   - user:password (will prepend HZN_ORG_ID)
#   - org/user:password (will use as-is)
parse_auth() {
    if [[ "$HZN_EXCHANGE_USER_AUTH" == *"/"* ]]; then
        # Already has org/user:password format
        FULL_AUTH="$HZN_EXCHANGE_USER_AUTH"
        AUTH_USER="${HZN_EXCHANGE_USER_AUTH%%:*}"  # This will be org/user
        AUTH_USER="${AUTH_USER#*/}"  # Extract just the user part
        AUTH_PASS="${HZN_EXCHANGE_USER_AUTH#*:}"
    else
        # Only has user:password format, need to prepend org
        AUTH_USER="${HZN_EXCHANGE_USER_AUTH%%:*}"
        AUTH_PASS="${HZN_EXCHANGE_USER_AUTH#*:}"
        FULL_AUTH="${HZN_ORG_ID}/${AUTH_USER}:${AUTH_PASS}"
    fi
}

# Display current configuration
# Requires: HZN_EXCHANGE_URL, HZN_ORG_ID, HZN_EXCHANGE_USER_AUTH to be set
display_config() {
    if [ "$JSON_ONLY" = true ]; then
        return 0
    fi
    
    print_info "Configuration:"
    echo "  Exchange URL: $HZN_EXCHANGE_URL"
    echo "  Organization: $HZN_ORG_ID"
    echo "  User: ${HZN_EXCHANGE_USER_AUTH%%:*}"
    echo ""
}

# Check if hzn CLI is installed
# Returns: 0 if installed, 1 if not
check_hzn_cli() {
    if ! command -v hzn &> /dev/null; then
        print_error "hzn CLI is not installed or not in PATH"
        echo ""
        echo "Please install the Open Horizon CLI:"
        echo "  https://github.com/open-horizon/anax/releases"
        return 1
    fi
    return 0
}

# Check if hzn agent is running
# Prints warning if not running, but doesn't fail
check_hzn_agent() {
    if [ "$JSON_ONLY" = true ]; then
        return 0
    fi
    
    print_info "Checking if Horizon agent is running..."
    if ! hzn version &> /dev/null; then
        print_warning "Horizon agent may not be running"
        echo ""
        echo "On macOS, you can start it with:"
        echo "  horizon-container start"
        echo ""
    fi
}

# Check if curl is installed
# Returns: 0 if installed, 1 if not
check_curl() {
    if ! command -v curl &> /dev/null; then
        print_error "curl is not installed or not in PATH"
        echo ""
        echo "Please install curl to use this script"
        return 1
    fi
    return 0
}

# Check if jq is installed (optional)
# Sets global variable: JQ_AVAILABLE (true/false)
check_jq() {
    JQ_AVAILABLE=false  # Used by scripts that source this library
    if command -v jq &> /dev/null; then
        JQ_AVAILABLE=true
    fi
    export JQ_AVAILABLE
}

# Validate URL format
# Arguments:
#   $1 - URL to validate
# Returns: 0 if valid, 1 if invalid
validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        print_error "Invalid URL format: $url"
        return 1
    fi
    return 0
}

# Validate organization ID format
# Arguments:
#   $1 - Organization ID to validate
# Returns: 0 if valid, 1 if invalid
validate_org_id() {
    local org="$1"
    if [[ ! "$org" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid organization ID: $org"
        return 1
    fi
    return 0
}

# Make an API call using curl
# Arguments:
#   $1 - HTTP method (GET, POST, PUT, DELETE)
#   $2 - API endpoint (relative to BASE_URL)
#   $3 - Optional: JSON data for POST/PUT
# Returns: HTTP response body and status code
# Sets global variables: http_code, response_body (used by calling scripts)
make_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local url="${BASE_URL}${endpoint}"
    
    if [ -n "$data" ]; then
        response=$(curl -sS -k -w "\n%{http_code}" -X "$method" -u "$FULL_AUTH" \
            -H "Content-Type: application/json" -d "$data" "$url" 2>&1)
    else
        response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" "$url" 2>&1)
    fi
    
    # Extract HTTP status code (last line) - used by calling scripts
    http_code=$(echo "$response" | tail -n1)
    # Extract response body (all but last line) - used by calling scripts
    response_body=$(echo "$response" | sed '$d')
    
    # Export for use by calling scripts
    export http_code response_body
}

# Validate JSON response
# Arguments:
#   $1 - JSON string to validate
# Returns: 0 if valid, 1 if invalid
validate_json() {
    local json="$1"
    if ! echo "$json" | python3 -m json.tool &> /dev/null; then
        print_error "Invalid JSON response from API"
        echo ""
        echo "Response:"
        echo "$json"
        return 1
    fi
    return 0
}

# Setup cleanup trap
# This should be called at the beginning of scripts that need cleanup
# Arguments:
#   $1 - Optional: Custom cleanup function name
setup_cleanup_trap() {
    local cleanup_func="${1:-cleanup}"
    
    # Default cleanup function if not provided
    if [ "$cleanup_func" = "cleanup" ] && ! declare -f cleanup &> /dev/null; then
        # shellcheck disable=SC2317,SC2329  # Function invoked indirectly via trap
        cleanup() {
            local exit_code=$?
            # Clean up temporary files if they exist
            [ -n "${temp_env_file:-}" ] && [ -f "$temp_env_file" ] && rm -f "$temp_env_file"
            [ -n "${temp_response_file:-}" ] && [ -f "$temp_response_file" ] && rm -f "$temp_response_file"
            exit "$exit_code"
        }
    fi
    
    trap "$cleanup_func" EXIT INT TERM
}

# Export functions and variables for use in other scripts
export -f print_info print_success print_error print_warning print_header
export -f find_env_files select_env_file load_credentials parse_auth
export -f display_config check_hzn_cli check_hzn_agent check_curl check_jq
export -f validate_url validate_org_id make_api_call validate_json
export -f setup_cleanup_trap

# Export color codes for use in other scripts
export RED GREEN YELLOW BLUE CYAN MAGENTA NC

# Made with Bob
