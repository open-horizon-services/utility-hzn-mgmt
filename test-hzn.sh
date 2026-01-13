#!/bin/bash

# Script to test Open Horizon agent installation and configuration
# Usage: ./test-hzn.sh

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

print_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Track overall status
all_checks_passed=true

print_section "Open Horizon Agent Status Check"

# Check 1: Is hzn CLI installed?
print_info "Checking if hzn CLI is installed..."
if command -v hzn &> /dev/null; then
    hzn_path=$(which hzn)
    print_success "hzn CLI is installed at: $hzn_path"
else
    print_error "hzn CLI is NOT installed or not in PATH"
    echo ""
    echo "Installation instructions:"
    echo "  • Download from: https://github.com/open-horizon/anax/releases"
    echo "  • macOS: Install the .pkg file"
    echo "  • Linux: Install the appropriate .deb or .rpm package"
    all_checks_passed=false
fi
echo ""

# Check 2: Is hzn agent running?
print_info "Checking if Horizon agent is running..."
version_output=$(hzn version 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ]; then
    # Parse CLI and Agent versions
    cli_version=$(echo "$version_output" | grep "Horizon CLI version:" | awk '{print $4}')
    agent_version=$(echo "$version_output" | grep "Horizon Agent version:" | awk '{print $4}')
    
    if [[ "$agent_version" == "failed"* ]] || [ -z "$agent_version" ]; then
        print_error "Horizon agent is NOT running"
        echo ""
        echo "  CLI Version: $cli_version"
        echo "  Agent Version: Not running"
        echo ""
        echo "To start the agent:"
        echo "  • macOS with Docker/Podman: horizon-container start"
        echo "  • Linux: sudo systemctl start horizon"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Ensure Docker Desktop or Podman Desktop is running (macOS)"
        echo "  2. Check if container is already running: docker ps | grep horizon"
        echo "  3. If container exists but not running: horizon-container stop && horizon-container start"
        all_checks_passed=false
    else
        print_success "Horizon agent is running"
        echo ""
        echo "  CLI Version: $cli_version"
        echo "  Agent Version: $agent_version"
        
        # Check if versions match
        if [ "$cli_version" != "$agent_version" ]; then
            print_warning "CLI and Agent versions do not match"
            echo "  This may cause compatibility issues"
        fi
    fi
else
    print_error "Unable to check Horizon agent status"
    echo "$version_output"
    all_checks_passed=false
fi
echo ""

# Check 3: Is node configured?
print_info "Checking node configuration..."
node_output=$(hzn node list 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ]; then
    # Parse node information
    node_id=$(echo "$node_output" | grep '"id":' | head -1 | awk -F'"' '{print $4}')
    org_id=$(echo "$node_output" | grep '"organization":' | head -1 | awk -F'"' '{print $4}')
    config_state=$(echo "$node_output" | grep '"state":' | head -1 | awk -F'"' '{print $4}')
    exchange_api=$(echo "$node_output" | grep '"exchange_api":' | head -1 | awk -F'"' '{print $4}')
    architecture=$(echo "$node_output" | grep '"architecture":' | head -1 | awk -F'"' '{print $4}')
    
    print_success "Node information retrieved"
    echo ""
    echo "  Node ID: ${node_id:-<not set>}"
    echo "  Organization: ${org_id:-<not set>}"
    echo "  Configuration State: ${config_state:-<unknown>}"
    echo "  Exchange API: ${exchange_api:-<not set>}"
    echo "  Architecture: ${architecture:-<unknown>}"
    echo ""
    
    # Check configuration state
    if [ "$config_state" = "unconfigured" ]; then
        print_warning "Node is unconfigured"
        echo ""
        echo "To configure the node, you need to register it:"
        echo "  hzn register -o <org-id> -u <user>:<password> -n <node-name>"
        echo ""
        echo "Or use a pattern:"
        echo "  hzn register -o <org-id> -u <user>:<password> -p <pattern-name>"
        all_checks_passed=false
    elif [ "$config_state" = "configured" ]; then
        print_success "Node is configured"
    else
        print_warning "Node configuration state: $config_state"
    fi
else
    print_error "Unable to retrieve node information"
    echo "$node_output"
    all_checks_passed=false
fi
echo ""

# Check 4: Can we reach the Exchange?
print_info "Checking Exchange connectivity..."

# Check if environment variables are set
if [ -n "$HZN_EXCHANGE_URL" ] && [ -n "$HZN_ORG_ID" ] && [ -n "$HZN_EXCHANGE_USER_AUTH" ]; then
    print_info "Using credentials from environment variables"
    echo "  Exchange URL: $HZN_EXCHANGE_URL"
    echo "  Organization: $HZN_ORG_ID"
    echo "  User: ${HZN_EXCHANGE_USER_AUTH%%:*}"
    echo ""
    
    # Test Exchange connectivity
    print_info "Testing Exchange API connectivity..."
    user_list_output=$(hzn exchange user list 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        print_success "Exchange API is reachable and credentials are valid"
        
        # Count users
        user_count=$(echo "$user_list_output" | grep -o '"[^"]*/' | wc -l | tr -d ' ')
        if [ "$user_count" -gt 0 ]; then
            echo "  Found $user_count user(s) in organization '$HZN_ORG_ID'"
        fi
    else
        print_error "Unable to connect to Exchange API"
        echo ""
        echo "Error output:"
        echo "$user_list_output"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Verify Exchange URL is correct: $HZN_EXCHANGE_URL"
        echo "  2. Check network connectivity to Exchange"
        echo "  3. Verify credentials are correct"
        echo "  4. Ensure organization exists: $HZN_ORG_ID"
        all_checks_passed=false
    fi
else
    print_warning "Exchange credentials not configured in environment"
    echo ""
    echo "To test Exchange connectivity, set these environment variables:"
    echo "  export HZN_EXCHANGE_URL=https://<exchange-host>/api/v1"
    echo "  export HZN_ORG_ID=<your-org-id>"
    echo "  export HZN_EXCHANGE_USER_AUTH=<user>:<password>"
    echo ""
    echo "Or source a .env file:"
    echo "  source <your-credentials>.env"
    echo ""
    echo "You can use test-credentials.sh to test your credentials"
fi
echo ""

# Check 5: Check for common issues
print_section "Common Issues Check"

# Check if Docker/Podman is running (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    print_info "Checking Docker/Podman status (macOS)..."
    
    if command -v docker &> /dev/null; then
        if docker ps &> /dev/null; then
            print_success "Docker is running"
        else
            print_warning "Docker is installed but not running"
            echo "  Start Docker Desktop to run the Horizon agent"
        fi
    elif command -v podman &> /dev/null; then
        if podman ps &> /dev/null; then
            print_success "Podman is running"
        else
            print_warning "Podman is installed but not running"
            echo "  Start Podman Desktop to run the Horizon agent"
        fi
    else
        print_warning "Neither Docker nor Podman is installed"
        echo "  Install Docker Desktop or Podman Desktop to run the Horizon agent"
    fi
    echo ""
fi

# Check for horizon container (if using containerized agent)
if command -v docker &> /dev/null && docker ps &> /dev/null; then
    print_info "Checking for Horizon container..."
    horizon_container=$(docker ps -a --filter "name=horizon" --format "{{.Names}}: {{.Status}}" 2>/dev/null)
    
    if [ -n "$horizon_container" ]; then
        if echo "$horizon_container" | grep -q "Up"; then
            print_success "Horizon container is running"
            echo "  $horizon_container"
        else
            print_warning "Horizon container exists but is not running"
            echo "  $horizon_container"
            echo ""
            echo "To start: horizon-container start"
        fi
    else
        print_info "No Horizon container found (may be using native agent)"
    fi
    echo ""
fi

# Final summary
print_section "Summary"

if [ "$all_checks_passed" = true ]; then
    print_success "All checks PASSED!"
    echo ""
    echo "Your Open Horizon agent is properly installed, running, and configured."
    echo ""
    echo "Next steps:"
    echo "  • Register a node: hzn register"
    echo "  • Deploy a service: hzn service list"
    echo "  • View agreements: hzn agreement list"
else
    print_error "Some checks FAILED"
    echo ""
    echo "Please review the errors above and follow the troubleshooting steps."
    echo ""
    echo "Common solutions:"
    echo "  1. Install hzn CLI if not installed"
    echo "  2. Start the agent: horizon-container start (macOS) or sudo systemctl start horizon (Linux)"
    echo "  3. Configure credentials: source <your-credentials>.env"
    echo "  4. Register the node: hzn register"
    echo ""
    echo "For more help, see: https://github.com/open-horizon/anax/wiki"
    exit 1
fi