#!/bin/bash

# Script to list Open Horizon services for a specific user using REST API
# Usage: ./list-a-user-services.sh [OPTIONS] [USER_ID] [ENV_FILE]

# Strict error handling
set -euo pipefail

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
            echo "List Open Horizon services for a specific user using REST API"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed JSON response from API with headers"
            echo "  -j, --json       Output raw JSON only (no headers, colors, or messages)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  USER_ID          Optional: User ID to query services for"
            echo "                   If not provided, uses authenticated user from credentials"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Default: Shows simple list of service URLs with version and architecture"
            echo ""
            echo "Examples:"
            echo "  $0                          # Query services for authenticated user"
            echo "  $0 myuser                   # Query services for 'myuser'"
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

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Setup cleanup trap
# shellcheck disable=SC2119  # Function doesn't use positional parameters
setup_cleanup_trap

# Handle .env file selection and load credentials
selected_file=""  # Will be set by select_env_file
select_env_file "$ENV_FILE" || exit 1
load_credentials "$selected_file" || exit 1

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

# Display configuration with user info
if [ "$JSON_ONLY" = false ]; then
    print_info "Configuration:"
    echo "  Exchange URL: $HZN_EXCHANGE_URL"
    echo "  Organization: $HZN_ORG_ID"
    echo "  User: ${HZN_EXCHANGE_USER_AUTH%%:*}"
    echo "  Querying services for: $USER_ID"
    echo ""
fi

# Check if curl is installed
check_curl || exit 1

# Check if jq is installed (optional but recommended)
check_jq

# Parse authentication credentials
parse_auth

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

# List services using REST API
if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching services from Exchange API..."
    echo ""
fi

# Make the API call to get services owned by the user
# API endpoint: /orgs/{orgid}/services?owner={org/userid}
# Note: The owner parameter must be in org/user format
response=$(curl -sS -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${HZN_ORG_ID}/services?owner=${OWNER_ID}" 2>&1)

# Extract HTTP status code (last line)
http_code=$(echo "$response" | tail -n1)
# Extract response body (all but last line)
response_body=$(echo "$response" | sed '$d')

# Check HTTP status code
if [ "$http_code" -ne 200 ]; then
    print_error "Failed to list services (HTTP $http_code)"
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
        echo "  4. Try using the hzn CLI to test: hzn exchange service list"
        echo ""
        # Show the auth format being used (mask password)
        AUTH_DISPLAY="${FULL_AUTH%%:*}:****"
        echo "Current auth format being used: ${AUTH_DISPLAY}"
    else
        echo "Troubleshooting tips:"
        echo "  1. Verify your credentials are correct"
        echo "  2. Check that the Exchange URL is reachable: $BASE_URL"
        echo "  3. Ensure your user has permission to list services"
        echo "  4. Check if the organization '$HZN_ORG_ID' exists"
        echo "  5. Verify that user '$USER_ID' exists in the organization"
        echo "  6. Note: API requires owner in 'org/user' format (using: $OWNER_ID)"
    fi
    exit 1
fi

if [ "$JSON_ONLY" = false ]; then
    print_success "Services retrieved successfully"
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

# Parse the response to get service names and details
if [ "$JQ_AVAILABLE" = true ]; then
    # Use jq for better JSON parsing
    service_keys=()
    while IFS= read -r service; do
        [ -n "$service" ] && service_keys+=("$service")
    done < <(echo "$response_body" | jq -r '.services | keys[]' 2>/dev/null || echo "")
    total_services=$(echo "$response_body" | jq -r '.services | length' 2>/dev/null || echo "0")
else
    # Fallback to basic parsing without jq
    service_keys=()
    while IFS= read -r service; do
        [ -n "$service" ] && service_keys+=("$service")
    done < <(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(data.get('services', {}).keys()))" 2>/dev/null || echo "")
    total_services=${#service_keys[@]}
fi

# Check service details (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    public_services=0
    private_services=0
    
    print_header "Service Summary"
    echo ""

    # Analyze service details
    for service_key in "${service_keys[@]}"; do
        # Extract service details from the response
        if [ "$JQ_AVAILABLE" = true ]; then
            public=$(echo "$response_body" | jq -r ".services[\"$service_key\"].public // false" 2>/dev/null)
        else
            public=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('services', {}).get('$service_key', {}).get('public', False)).lower())" 2>/dev/null)
        fi
        
        # Count services by their visibility
        if [ "$public" = "true" ]; then
            ((public_services++))
        else
            ((private_services++))
        fi
    done

    echo "Total services found: $total_services"
    echo "Public services: $public_services"
    echo "Private services: $private_services"
    echo ""
fi

# Display output based on mode
if [ "$JSON_ONLY" = true ]; then
    # JSON-only mode: output raw JSON without any formatting
    echo "$response_body"
    
elif [ "$VERBOSE" = true ]; then
    # Verbose mode: show full JSON response with headers
    print_header "Services (Detailed JSON)"
    echo ""
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$response_body" | jq '.'
    else
        echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    fi
    echo ""
    print_success "Listed $total_services service(s)"
    
else
    # Default mode: simple list of service URLs with version and architecture
    print_header "Services for User: $USER_ID (Organization: $HZN_ORG_ID)"
    echo ""
    
    if [ "$total_services" -eq 0 ]; then
        print_warning "No services found for user '$USER_ID'"
    else
        for service_key in "${service_keys[@]}"; do
            # Extract service details
            if [ "$JQ_AVAILABLE" = true ]; then
                service_url=$(echo "$response_body" | jq -r ".services[\"$service_key\"].url // \"unknown\"" 2>/dev/null)
                version=$(echo "$response_body" | jq -r ".services[\"$service_key\"].version // \"unknown\"" 2>/dev/null)
                arch=$(echo "$response_body" | jq -r ".services[\"$service_key\"].arch // \"unknown\"" 2>/dev/null)
                public=$(echo "$response_body" | jq -r ".services[\"$service_key\"].public // false" 2>/dev/null)
                sharable=$(echo "$response_body" | jq -r ".services[\"$service_key\"].sharable // \"singleton\"" 2>/dev/null)
                deployment=$(echo "$response_body" | jq -r ".services[\"$service_key\"].deployment // \"\"" 2>/dev/null)
            else
                service_url=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('services', {}).get('$service_key', {}).get('url', 'unknown'))" 2>/dev/null)
                version=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('services', {}).get('$service_key', {}).get('version', 'unknown'))" 2>/dev/null)
                arch=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('services', {}).get('$service_key', {}).get('arch', 'unknown'))" 2>/dev/null)
                public=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(str(data.get('services', {}).get('$service_key', {}).get('public', False)).lower())" 2>/dev/null)
                sharable=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('services', {}).get('$service_key', {}).get('sharable', 'singleton'))" 2>/dev/null)
                deployment=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('services', {}).get('$service_key', {}).get('deployment', ''))" 2>/dev/null)
            fi
            
            # Format output with visibility indicator
            if [ "$public" = "true" ]; then
                visibility_badge="${GREEN}[Public]${NC}"
            else
                visibility_badge="${YELLOW}[Private]${NC}"
            fi
            
            # Build output line
            output_line="$service_url $visibility_badge"
            output_line="$output_line - Version: $version, Arch: $arch"
            
            # Add sharable mode if not singleton
            if [ "$sharable" != "singleton" ] && [ "$sharable" != "null" ] && [ -n "$sharable" ]; then
                output_line="$output_line, Sharable: $sharable"
            fi
            
            # Add deployment type if available
            if [ -n "$deployment" ] && [ "$deployment" != "null" ] && [ "$deployment" != "{}" ]; then
                # Try to extract deployment type (docker, kubernetes, etc.)
                if [ "$JQ_AVAILABLE" = true ]; then
                    deployment_type=$(echo "$deployment" | jq -r 'keys[0] // "unknown"' 2>/dev/null)
                else
                    deployment_type=$(echo "$deployment" | python3 -c "import sys, json; data=json.load(sys.stdin); print(list(data.keys())[0] if data else 'unknown')" 2>/dev/null)
                fi
                if [ -n "$deployment_type" ] && [ "$deployment_type" != "null" ] && [ "$deployment_type" != "unknown" ]; then
                    output_line="$output_line, Deployment: $deployment_type"
                fi
            fi
            
            echo -e "$output_line"
        done
        echo ""
        print_success "Listed $total_services service(s)"
    fi
fi

# Additional info (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    echo ""
    print_info "API Endpoint: ${BASE_URL}/orgs/${HZN_ORG_ID}/services?owner=${USER_ID}"
    print_info "Authenticated as: ${HZN_ORG_ID}/${AUTH_USER}"
    echo ""

    # Summary of service visibility
    if [ "$total_services" -gt 0 ]; then
        print_success "Successfully retrieved all services for user '$USER_ID' in organization '$HZN_ORG_ID'"
        echo ""
        echo "Service visibility legend:"
        echo -e "  ${GREEN}[Public]${NC}  - Service is publicly accessible"
        echo -e "  ${YELLOW}[Private]${NC} - Service is private to the organization"
    else
        print_warning "No services found for user '$USER_ID' in organization '$HZN_ORG_ID'"
        echo ""
        echo "This could mean:"
        echo "  - The user has not published any services yet"
        echo "  - The user ID is incorrect"
        echo "  - You don't have permission to view this user's services"
    fi
fi
