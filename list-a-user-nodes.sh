#!/bin/bash

# Script to list Open Horizon nodes for a specific user using REST API
# Usage: ./list-a-user-nodes.sh [OPTIONS] [USER_ID] [ENV_FILE]

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
USER_ID=""

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
            echo "Usage: $0 [OPTIONS] [USER_ID] [ENV_FILE]"
            echo ""
            echo "List Open Horizon nodes for a specific user using REST API"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed JSON response from API with headers"
            echo "  -j, --json       Output raw JSON only (no headers, colors, or messages)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  USER_ID          Optional: User ID to query nodes for"
            echo "                   If not provided, uses authenticated user from credentials"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Default: Shows simple list of node IDs with status"
            echo ""
            echo "Examples:"
            echo "  $0                          # Query nodes for authenticated user"
            echo "  $0 myuser                   # Query nodes for 'myuser'"
            echo "  $0 myuser mycreds.env       # Use specific user and .env file"
            echo "  $0 --json mycreds.env       # JSON output for authenticated user"
            echo "  $0 --json myuser mycreds.env # JSON output with specific user"
            echo "  $0 --verbose myuser         # Verbose output for specific user"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Non-option argument
            # Check if it's an .env file (ends with .env)
            if [[ "$1" == *.env ]]; then
                ENV_FILE="$1"
            elif [ -z "$USER_ID" ]; then
                # First non-.env argument is user ID
                USER_ID="$1"
            else
                # Second non-.env argument is env file
                ENV_FILE="$1"
            fi
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

# Handle .env file selection first (we need credentials to extract default user)
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
        echo "Or specify a .env file: $0 $USER_ID path/to/file.env"
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

# If USER_ID not provided, extract it from HZN_EXCHANGE_USER_AUTH
if [ -z "$USER_ID" ]; then
    # Extract user from HZN_EXCHANGE_USER_AUTH
    # Format can be: user:password or org/user:password
    if [[ "$HZN_EXCHANGE_USER_AUTH" == *"/"* ]]; then
        # Has org/user:password format, extract user part
        USER_ID="${HZN_EXCHANGE_USER_AUTH#*/}"  # Remove org/ prefix
        USER_ID="${USER_ID%%:*}"  # Remove :password suffix
    else
        # Has user:password format
        USER_ID="${HZN_EXCHANGE_USER_AUTH%%:*}"
    fi
    
    if [ "$JSON_ONLY" = false ]; then
        print_info "No user ID specified, using authenticated user: $USER_ID"
        echo ""
    fi
fi

if [ "$JSON_ONLY" = false ]; then
    print_success "Credentials loaded successfully"
    echo ""

    # Display configuration
    print_info "Configuration:"
    echo "  Exchange URL: $HZN_EXCHANGE_URL"
    echo "  Organization: $HZN_ORG_ID"
    echo "  User: ${HZN_EXCHANGE_USER_AUTH%%:*}"
    echo "  Querying nodes for: $USER_ID"
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

# Construct the full owner identifier (org/user format required by API)
# If USER_ID already contains org/ prefix, use as-is, otherwise prepend org
if [[ "$USER_ID" == *"/"* ]]; then
    OWNER_ID="$USER_ID"
else
    OWNER_ID="${HZN_ORG_ID}/${USER_ID}"
fi

# List nodes using REST API
if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching nodes from Exchange API..."
    echo ""
fi

# Make the API call to get nodes owned by the user
# API endpoint: /orgs/{orgid}/nodes?owner={org/userid}
# Note: The owner parameter must be in org/user format
response=$(curl -sS -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${HZN_ORG_ID}/nodes?owner=${OWNER_ID}" 2>&1)

# Extract HTTP status code (last line)
http_code=$(echo "$response" | tail -n1)
# Extract response body (all but last line)
response_body=$(echo "$response" | sed '$d')

# Check HTTP status code
if [ "$http_code" -ne 200 ]; then
    print_error "Failed to list nodes (HTTP $http_code)"
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
        echo "  4. Try using the hzn CLI to test: hzn exchange node list"
        echo ""
        # Show the auth format being used (mask password)
        AUTH_DISPLAY="${FULL_AUTH%%:*}:****"
        echo "Current auth format being used: ${AUTH_DISPLAY}"
    else
        echo "Troubleshooting tips:"
        echo "  1. Verify your credentials are correct"
        echo "  2. Check that the Exchange URL is reachable: $BASE_URL"
        echo "  3. Ensure your user has permission to list nodes"
        echo "  4. Check if the organization '$HZN_ORG_ID' exists"
        echo "  5. Verify that user '$USER_ID' exists in the organization"
        echo "  6. Note: API requires owner in 'org/user' format (using: $OWNER_ID)"
    fi
    exit 1
fi

if [ "$JSON_ONLY" = false ]; then
    print_success "Nodes retrieved successfully"
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

# Parse the response to get node names and details
if [ "$JQ_AVAILABLE" = true ]; then
    # Use jq for better JSON parsing
    node_names=($(echo "$response_body" | jq -r '.nodes | keys[]' 2>/dev/null || echo ""))
    total_nodes=$(echo "$response_body" | jq -r '.nodes | length' 2>/dev/null || echo "0")
else
    # Fallback to basic parsing without jq
    node_names=($(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(data.get('nodes', {}).keys()))" 2>/dev/null || echo ""))
    total_nodes=${#node_names[@]}
fi

# Check node details and status (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    configured_nodes=0
    unconfigured_nodes=0
    
    print_header "Node Summary"
    echo ""

    # Analyze node details
    for node in "${node_names[@]}"; do
        # Extract node details from the response
        if [ "$JQ_AVAILABLE" = true ]; then
            config_state=$(echo "$response_body" | jq -r ".nodes[\"$node\"].configstate.state // \"unknown\"" 2>/dev/null)
        else
            config_state=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('configstate', {}).get('state', 'unknown'))" 2>/dev/null)
        fi
        
        # Count nodes by their configuration state
        if [ "$config_state" = "configured" ]; then
            ((configured_nodes++))
        elif [ "$config_state" = "unconfigured" ]; then
            ((unconfigured_nodes++))
        fi
    done

    echo "Total nodes found: $total_nodes"
    echo "Configured nodes: $configured_nodes"
    echo "Unconfigured nodes: $unconfigured_nodes"
    echo ""
fi

# Display output based on mode
if [ "$JSON_ONLY" = true ]; then
    # JSON-only mode: output raw JSON without any formatting
    echo "$response_body"
    
elif [ "$VERBOSE" = true ]; then
    # Verbose mode: show full JSON response with headers
    print_header "Nodes (Detailed JSON)"
    echo ""
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$response_body" | jq '.'
    else
        echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    fi
    echo ""
    print_success "Listed $total_nodes node(s)"
    
else
    # Default mode: simple list of node names with status
    print_header "Nodes for User: $USER_ID (Organization: $HZN_ORG_ID)"
    echo ""
    
    if [ $total_nodes -eq 0 ]; then
        print_warning "No nodes found for user '$USER_ID'"
    else
        for node in "${node_names[@]}"; do
            # Extract just the node ID (remove org/ prefix if present)
            display_node="${node#*/}"
            
            # Extract node details
            if [ "$JQ_AVAILABLE" = true ]; then
                config_state=$(echo "$response_body" | jq -r ".nodes[\"$node\"].configstate.state // \"unknown\"" 2>/dev/null)
                pattern=$(echo "$response_body" | jq -r ".nodes[\"$node\"].pattern // \"\"" 2>/dev/null)
                node_type=$(echo "$response_body" | jq -r ".nodes[\"$node\"].nodeType // \"device\"" 2>/dev/null)
                arch=$(echo "$response_body" | jq -r ".nodes[\"$node\"].arch // \"unknown\"" 2>/dev/null)
                registered_services=$(echo "$response_body" | jq -c ".nodes[\"$node\"].registeredServices // []" 2>/dev/null)
            else
                config_state=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('configstate', {}).get('state', 'unknown'))" 2>/dev/null)
                pattern=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('pattern', ''))" 2>/dev/null)
                node_type=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('nodeType', 'device'))" 2>/dev/null)
                arch=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('arch', 'unknown'))" 2>/dev/null)
                registered_services=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('nodes', {}).get('$node', {}).get('registeredServices', [])))" 2>/dev/null)
            fi
            
            # Format output with status indicator
            if [ "$config_state" = "configured" ]; then
                status_badge="${GREEN}[Configured]${NC}"
            elif [ "$config_state" = "unconfigured" ]; then
                status_badge="${YELLOW}[Unconfigured]${NC}"
            else
                status_badge="${RED}[Unknown]${NC}"
            fi
            
            # Build output line
            output_line="$display_node $status_badge - Type: $node_type, Arch: $arch"
            
            # Add pattern if not empty
            if [ -n "$pattern" ] && [ "$pattern" != "null" ]; then
                output_line="$output_line, Pattern: $pattern"
            fi
            
            # Add registered services if not empty array
            if [ "$registered_services" != "[]" ] && [ "$registered_services" != "null" ]; then
                # Format the services list
                if [ "$JQ_AVAILABLE" = true ]; then
                    services_list=$(echo "$registered_services" | jq -r '.[] | "\(.url)"' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
                else
                    services_list=$(echo "$registered_services" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join([s.get('url', '') for s in data]))" 2>/dev/null)
                fi
                if [ -n "$services_list" ]; then
                    output_line="$output_line, Services: $services_list"
                fi
            fi
            
            echo -e "$output_line"
        done
        echo ""
        print_success "Listed $total_nodes node(s)"
    fi
fi

# Additional info (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    echo ""
    print_info "API Endpoint: ${BASE_URL}/orgs/${HZN_ORG_ID}/nodes?owner=${USER_ID}"
    print_info "Authenticated as: ${HZN_ORG_ID}/${AUTH_USER}"
    echo ""

    # Summary of node status
    if [ $total_nodes -gt 0 ]; then
        print_success "Successfully retrieved all nodes for user '$USER_ID' in organization '$HZN_ORG_ID'"
        echo ""
        echo "Node status legend:"
        echo -e "  ${GREEN}[Configured]${NC}   - Node is configured and registered"
        echo -e "  ${YELLOW}[Unconfigured]${NC} - Node is registered but not configured"
        echo -e "  ${RED}[Unknown]${NC}      - Node status is unknown"
    else
        print_warning "No nodes found for user '$USER_ID' in organization '$HZN_ORG_ID'"
        echo ""
        echo "This could mean:"
        echo "  - The user has not registered any nodes yet"
        echo "  - The user ID is incorrect"
        echo "  - You don't have permission to view this user's nodes"
    fi
fi