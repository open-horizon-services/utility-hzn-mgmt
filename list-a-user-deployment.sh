#!/bin/bash

# Script to list Open Horizon deployment policies for a specific user using REST API
# Usage: ./list-a-user-deployment.sh [OPTIONS] [USER_ID] [ENV_FILE]

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
            echo "List Open Horizon deployment policies for a specific user using REST API"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed JSON response from API with headers"
            echo "  -j, --json       Output raw JSON only (no headers, colors, or messages)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  USER_ID          Optional: User ID to query deployment policies for"
            echo "                   If not provided, uses authenticated user from credentials"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Default: Shows simple list of deployment policy names with service references"
            echo ""
            echo "Examples:"
            echo "  $0                          # Query policies for authenticated user"
            echo "  $0 myuser                   # Query policies for 'myuser'"
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
    echo "  Querying deployment policies for: $USER_ID"
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

# List deployment policies using REST API
if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching deployment policies from Exchange API..."
    echo ""
fi

# Display the API request in verbose mode
display_api_request "GET" "${BASE_URL}/orgs/${HZN_ORG_ID}/business/policies?owner=${OWNER_ID}"

# Make the API call to get deployment policies owned by the user
# API endpoint: /orgs/{orgid}/business/policies?owner={org/userid}
# Note: The owner parameter must be in org/user format
response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${HZN_ORG_ID}/business/policies?owner=${OWNER_ID}" 2>&1)

# Extract HTTP status code (last line)
http_code=$(echo "$response" | tail -n1)
# Extract response body (all but last line)
response_body=$(echo "$response" | sed '$d')

# Check HTTP status code
if [ "$http_code" -ne 200 ]; then
    print_error "Failed to list deployment policies (HTTP $http_code)"
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
        echo "  4. Try using the hzn CLI to test: hzn exchange deployment listpolicy"
        echo ""
        # Show the auth format being used (mask password)
        AUTH_DISPLAY="${FULL_AUTH%%:*}:****"
        echo "Current auth format being used: ${AUTH_DISPLAY}"
    else
        echo "Troubleshooting tips:"
        echo "  1. Verify your credentials are correct"
        echo "  2. Check that the Exchange URL is reachable: $BASE_URL"
        echo "  3. Ensure your user has permission to list deployment policies"
        echo "  4. Check if the organization '$HZN_ORG_ID' exists"
        echo "  5. Verify that user '$USER_ID' exists in the organization"
        echo "  6. Note: API requires owner in 'org/user' format (using: $OWNER_ID)"
    fi
    exit 1
fi

if [ "$JSON_ONLY" = false ]; then
    print_success "Deployment policies retrieved successfully"
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

# Parse the response to get policy names and details
if [ "$JQ_AVAILABLE" = true ]; then
    # Use jq for better JSON parsing
    # Read into array using while loop for portability (mapfile not available in older bash)
    policy_keys=()
    while IFS= read -r key; do
        [ -n "$key" ] && policy_keys+=("$key")
    done < <(echo "$response_body" | jq -r '.businessPolicy | keys[]' 2>/dev/null)
    total_policies=${#policy_keys[@]}
else
    # Fallback to basic parsing without jq
    policy_keys=()
    while IFS= read -r key; do
        [ -n "$key" ] && policy_keys+=("$key")
    done < <(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(data.get('businessPolicy', {}).keys()))" 2>/dev/null)
    total_policies=${#policy_keys[@]}
fi

# Check policy details (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    policies_with_services=0
    policies_with_constraints=0
    
    print_header "Deployment Policy Summary"
    echo ""

    # Analyze policy details
    for policy_key in "${policy_keys[@]}"; do
        # Extract policy details from the response
        if [ "$JQ_AVAILABLE" = true ]; then
            services=$(echo "$response_body" | jq -c ".businessPolicy[\"$policy_key\"].service // []" 2>/dev/null)
            constraints=$(echo "$response_body" | jq -r ".businessPolicy[\"$policy_key\"].constraints // []" 2>/dev/null)
        else
            services=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('businessPolicy', {}).get('$policy_key', {}).get('service', [])))" 2>/dev/null)
            constraints=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('businessPolicy', {}).get('$policy_key', {}).get('constraints', [])))" 2>/dev/null)
        fi
        
        # Count policies with services
        if [ "$services" != "[]" ] && [ "$services" != "null" ] && [ -n "$services" ]; then
            ((policies_with_services++))
        fi
        
        # Count policies with constraints
        if [ "$constraints" != "[]" ] && [ "$constraints" != "null" ] && [ -n "$constraints" ]; then
            ((policies_with_constraints++))
        fi
    done

    echo "Total deployment policies found: $total_policies"
    echo "Policies with service references: $policies_with_services"
    echo "Policies with constraints: $policies_with_constraints"
    echo ""
fi

# Display output based on mode
if [ "$JSON_ONLY" = true ]; then
    # JSON-only mode: output raw JSON without any formatting
    echo "$response_body"
    
elif [ "$VERBOSE" = true ]; then
    # Verbose mode: show full JSON response with headers
    print_header "Deployment Policies (Detailed JSON)"
    echo ""
    
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$response_body" | jq '.'
    else
        echo "$response_body" | python3 -m json.tool 2>/dev/null || echo "$response_body"
    fi
    echo ""
    print_success "Listed $total_policies deployment policy(ies)"
    
else
    # Default mode: simple list of policy names with service references
    print_header "Deployment Policies for User: $USER_ID (Organization: $HZN_ORG_ID)"
    echo ""
    
    if [ "$total_policies" -eq 0 ]; then
        print_warning "No deployment policies found for user '$USER_ID'"
    else
        for policy_key in "${policy_keys[@]}"; do
            # Extract just the policy name (remove org/ prefix if present)
            display_policy="${policy_key#*/}"
            
            # Extract policy details
            if [ "$JQ_AVAILABLE" = true ]; then
                label=$(echo "$response_body" | jq -r ".businessPolicy[\"$policy_key\"].label // \"\"" 2>/dev/null)
                description=$(echo "$response_body" | jq -r ".businessPolicy[\"$policy_key\"].description // \"\"" 2>/dev/null)
                services=$(echo "$response_body" | jq -c ".businessPolicy[\"$policy_key\"].service // []" 2>/dev/null)
                constraints=$(echo "$response_body" | jq -c ".businessPolicy[\"$policy_key\"].constraints // []" 2>/dev/null)
                properties=$(echo "$response_body" | jq -c ".businessPolicy[\"$policy_key\"].properties // []" 2>/dev/null)
            else
                label=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('businessPolicy', {}).get('$policy_key', {}).get('label', ''))" 2>/dev/null)
                description=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('businessPolicy', {}).get('$policy_key', {}).get('description', ''))" 2>/dev/null)
                services=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('businessPolicy', {}).get('$policy_key', {}).get('service', [])))" 2>/dev/null)
                constraints=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('businessPolicy', {}).get('$policy_key', {}).get('constraints', [])))" 2>/dev/null)
                properties=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data.get('businessPolicy', {}).get('$policy_key', {}).get('properties', [])))" 2>/dev/null)
            fi
            
            # Build output line
            output_line="$display_policy"
            
            # Add label if not empty
            if [ -n "$label" ] && [ "$label" != "null" ]; then
                output_line="$output_line - Label: $label"
            fi
            
            # Add description if not empty (truncate if too long)
            if [ -n "$description" ] && [ "$description" != "null" ]; then
                # Truncate description to 60 characters
                if [ ${#description} -gt 60 ]; then
                    description="${description:0:57}..."
                fi
                output_line="$output_line, Description: $description"
            fi
            
            # Add service references if not empty array
            if [ "$services" != "[]" ] && [ "$services" != "null" ] && [ -n "$services" ]; then
                # Format the services list
                if [ "$JQ_AVAILABLE" = true ]; then
                    # Check if services is an array or a single object
                    services_list=$(echo "$services" | jq -r 'if type == "array" then .[] else . end | "\(.name)@\(.org)/\(.arch)/\(.serviceVersions[0].version // "latest")"' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
                else
                    services_list=$(echo "$services" | python3 -c "import sys, json; data=json.load(sys.stdin); print(', '.join([f\"{s.get('name', '')}@{s.get('org', '')}/{s.get('arch', '')}/{s.get('serviceVersions', [{}])[0].get('version', 'latest') if s.get('serviceVersions') else 'latest'}\" for s in data]))" 2>/dev/null)
                fi
                if [ -n "$services_list" ]; then
                    output_line="$output_line, Services: $services_list"
                fi
            fi
            
            # Add constraint indicator if present
            if [ "$constraints" != "[]" ] && [ "$constraints" != "null" ] && [ -n "$constraints" ]; then
                # Count constraints
                if [ "$JQ_AVAILABLE" = true ]; then
                    constraint_count=$(echo "$constraints" | jq 'length' 2>/dev/null)
                else
                    constraint_count=$(echo "$constraints" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null)
                fi
                output_line="$output_line ${YELLOW}[${constraint_count} constraint(s)]${NC}"
            fi
            
            # Add properties indicator if present
            if [ "$properties" != "[]" ] && [ "$properties" != "null" ] && [ -n "$properties" ]; then
                # Count properties
                if [ "$JQ_AVAILABLE" = true ]; then
                    property_count=$(echo "$properties" | jq 'length' 2>/dev/null)
                else
                    property_count=$(echo "$properties" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null)
                fi
                output_line="$output_line ${CYAN}[${property_count} property(ies)]${NC}"
            fi
            
            # Output the formatted policy line
            echo -e "$output_line"
        done
        echo ""
        print_success "Listed $total_policies deployment policy(ies)"
    fi
fi

# Additional info (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    echo ""
    print_info "API Endpoint: ${BASE_URL}/orgs/${HZN_ORG_ID}/business/policies?owner=${USER_ID}"
    print_info "Authenticated as: ${HZN_ORG_ID}/${AUTH_USER}"
    echo ""

    # Summary of deployment policies
    if [ "$total_policies" -gt 0 ]; then
        print_success "Successfully retrieved all deployment policies for user '$USER_ID' in organization '$HZN_ORG_ID'"
        echo ""
        echo "Deployment policy indicators:"
        echo -e "  ${YELLOW}[N constraint(s)]${NC} - Policy has node placement constraints"
        echo -e "  ${CYAN}[N property(ies)]${NC} - Policy has custom properties defined"
    else
        print_warning "No deployment policies found for user '$USER_ID' in organization '$HZN_ORG_ID'"
        echo ""
        echo "This could mean:"
        echo "  - The user has not created any deployment policies yet"
        echo "  - The user ID is incorrect"
        echo "  - You don't have permission to view this user's deployment policies"
    fi
fi
