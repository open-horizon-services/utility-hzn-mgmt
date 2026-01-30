#!/bin/bash

# Script to list Open Horizon nodes in an organization using REST API
# Usage: ./list-a-org-nodes.sh [OPTIONS] [ENV_FILE]

# Strict error handling
set -euo pipefail

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
            echo "List Open Horizon nodes in an organization using REST API"
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
            echo "Default: Shows simple list of node IDs with status and owner"
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

# Display configuration
display_config

# Check if curl is installed
check_curl || exit 1

# Check if jq is installed (optional but recommended)
check_jq

# Parse authentication credentials
parse_auth

# Use the Exchange URL as-is (it should already include the API version path)
# Remove trailing slash if present
BASE_URL="${HZN_EXCHANGE_URL%/}"

# List nodes using REST API
if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching nodes from Exchange API..."
    echo ""
fi

# Display the API request in verbose mode
display_api_request "GET" "${BASE_URL}/orgs/${HZN_ORG_ID}/nodes"

# Make the API call to get all nodes in the organization
# API endpoint: /orgs/{orgid}/nodes
response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${HZN_ORG_ID}/nodes" 2>&1)

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
    node_names=()
    while IFS= read -r node; do
        [ -n "$node" ] && node_names+=("$node")
    done < <(echo "$response_body" | jq -r '.nodes | keys[]' 2>/dev/null || echo "")
    total_nodes=$(echo "$response_body" | jq -r '.nodes | length' 2>/dev/null || echo "0")
else
    # Fallback to basic parsing without jq
    node_names=()
    while IFS= read -r node; do
        [ -n "$node" ] && node_names+=("$node")
    done < <(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join(data.get('nodes', {}).keys()))" 2>/dev/null || echo "")
    total_nodes=${#node_names[@]}
fi

# Check node details and status (skip in JSON-only mode)
if [ "$JSON_ONLY" = false ]; then
    configured_nodes=0
    unconfigured_nodes=0
    device_nodes=0
    cluster_nodes=0
    
    # Track unique owners using a simple string approach (compatible with older bash)
    unique_owners=""
    
    print_header "Node Summary"
    echo ""

    # Analyze node details
    for node in "${node_names[@]}"; do
        # Extract node details from the response
        if [ "$JQ_AVAILABLE" = true ]; then
            config_state=$(echo "$response_body" | jq -r ".nodes[\"$node\"].configstate.state // \"unknown\"" 2>/dev/null)
            node_type=$(echo "$response_body" | jq -r ".nodes[\"$node\"].nodeType // \"device\"" 2>/dev/null)
            owner=$(echo "$response_body" | jq -r ".nodes[\"$node\"].owner // \"unknown\"" 2>/dev/null)
        else
            config_state=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('configstate', {}).get('state', 'unknown'))" 2>/dev/null)
            node_type=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('nodeType', 'device'))" 2>/dev/null)
            owner=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('owner', 'unknown'))" 2>/dev/null)
        fi
        
        # Count nodes by their configuration state
        if [ "$config_state" = "configured" ]; then
            ((configured_nodes++))
        elif [ "$config_state" = "unconfigured" ]; then
            ((unconfigured_nodes++))
        fi
        
        # Count nodes by type
        if [ "$node_type" = "device" ]; then
            ((device_nodes++))
        elif [ "$node_type" = "cluster" ]; then
            ((cluster_nodes++))
        fi
        
        # Track unique owners (add to list if not already present)
        if [ "$owner" != "unknown" ]; then
            if ! echo "$unique_owners" | grep -q "^${owner}$"; then
                if [ -z "$unique_owners" ]; then
                    unique_owners="$owner"
                else
                    unique_owners="${unique_owners}"$'\n'"${owner}"
                fi
            fi
        fi
    done

    # Count unique owners
    if [ -z "$unique_owners" ]; then
        owner_count=0
    else
        owner_count=$(echo "$unique_owners" | wc -l | tr -d ' ')
    fi

    echo "Total nodes found: $total_nodes"
    echo "Configured nodes: $configured_nodes"
    echo "Unconfigured nodes: $unconfigured_nodes"
    echo "Device nodes: $device_nodes"
    echo "Cluster nodes: $cluster_nodes"
    echo "Unique owners: $owner_count"
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
    # Default mode: simple list of node names with status and owner
    print_header "Nodes in Organization: $HZN_ORG_ID"
    echo ""
    
    if [ "$total_nodes" -eq 0 ]; then
        print_warning "No nodes found in organization '$HZN_ORG_ID'"
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
                owner=$(echo "$response_body" | jq -r ".nodes[\"$node\"].owner // \"unknown\"" 2>/dev/null)
                registered_services=$(echo "$response_body" | jq -c ".nodes[\"$node\"].registeredServices // []" 2>/dev/null)
            else
                config_state=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('configstate', {}).get('state', 'unknown'))" 2>/dev/null)
                pattern=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('pattern', ''))" 2>/dev/null)
                node_type=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('nodeType', 'device'))" 2>/dev/null)
                arch=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('arch', 'unknown'))" 2>/dev/null)
                owner=$(echo "$response_body" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('nodes', {}).get('$node', {}).get('owner', 'unknown'))" 2>/dev/null)
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
            
            # Format node type badge
            if [ "$node_type" = "cluster" ]; then
                type_badge="${MAGENTA}[Cluster]${NC}"
            else
                type_badge="${BLUE}[Device]${NC}"
            fi
            
            # Build output line
            output_line="$display_node $status_badge $type_badge - Arch: $arch, Owner: $owner"
            
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
    print_info "API Endpoint: ${BASE_URL}/orgs/${HZN_ORG_ID}/nodes"
    print_info "Authenticated as: ${HZN_ORG_ID}/${AUTH_USER}"
    echo ""

    # Summary of node status
    if [ "$total_nodes" -gt 0 ]; then
        print_success "Successfully retrieved all nodes in organization '$HZN_ORG_ID'"
        echo ""
        echo "Node status legend:"
        echo -e "  ${GREEN}[Configured]${NC}   - Node is configured and registered"
        echo -e "  ${YELLOW}[Unconfigured]${NC} - Node is registered but not configured"
        echo -e "  ${RED}[Unknown]${NC}      - Node status is unknown"
        echo ""
        echo "Node type legend:"
        echo -e "  ${BLUE}[Device]${NC}  - Edge device node"
        echo -e "  ${MAGENTA}[Cluster]${NC} - Edge cluster node"
    else
        print_warning "No nodes found in organization '$HZN_ORG_ID'"
        echo ""
        echo "This could mean:"
        echo "  - No nodes have been registered in this organization yet"
        echo "  - You don't have permission to view nodes in this organization"
    fi
fi