#!/bin/bash

# Test runner script for hzn-utils
# Runs all bats tests with proper setup and reporting

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="${SCRIPT_DIR}/tests"

# Print functions
print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check if bats is installed
check_bats() {
    if ! command -v bats &> /dev/null; then
        print_error "bats is not installed"
        echo ""
        echo "Install bats using one of the following methods:"
        echo ""
        echo "  macOS (Homebrew):"
        echo "    brew install bats-core"
        echo ""
        echo "  Linux (apt):"
        echo "    sudo apt-get install bats"
        echo ""
        echo "  npm:"
        echo "    npm install -g bats"
        echo ""
        echo "  From source:"
        echo "    git clone https://github.com/bats-core/bats-core.git"
        echo "    cd bats-core"
        echo "    sudo ./install.sh /usr/local"
        echo ""
        return 1
    fi
    return 0
}

# Check optional dependencies
check_optional_deps() {
    local missing=()
    
    if ! command -v shellcheck &> /dev/null; then
        missing+=("shellcheck")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "Optional dependencies not installed: ${missing[*]}"
        print_info "Some tests may be skipped"
        echo ""
    fi
}

# Run shellcheck on all scripts
run_shellcheck() {
    if ! command -v shellcheck &> /dev/null; then
        print_warning "Skipping shellcheck (not installed)"
        return 0
    fi
    
    print_header "Running ShellCheck"
    
    local failed=0
    local scripts=(
        "list-orgs.sh"
        "list-users.sh"
        "list-a-orgs.sh"
        "list-a-users.sh"
        "list-a-org-nodes.sh"
        "list-a-user-nodes.sh"
        "list-a-user-services.sh"
        "list-a-user-deployment.sh"
        "test-credentials.sh"
        "test-hzn.sh"
        "lib/common.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "${SCRIPT_DIR}/${script}" ]; then
            print_info "Checking ${script}..."
            if shellcheck -x "${SCRIPT_DIR}/${script}"; then
                print_success "${script} passed"
            else
                print_error "${script} failed"
                failed=$((failed + 1))
            fi
        fi
    done
    
    echo ""
    
    if [ $failed -eq 0 ]; then
        print_success "All scripts passed shellcheck"
        return 0
    else
        print_error "$failed script(s) failed shellcheck"
        return 1
    fi
}

# Run unit tests
run_unit_tests() {
    print_header "Running Unit Tests"
    
    if [ -d "${TEST_DIR}/unit" ]; then
        if bats "${TEST_DIR}/unit"/*.bats; then
            print_success "Unit tests passed"
            return 0
        else
            print_error "Unit tests failed"
            return 1
        fi
    else
        print_warning "No unit tests found"
        return 0
    fi
}

# Run integration tests
run_integration_tests() {
    print_header "Running Integration Tests"
    
    if [ -d "${TEST_DIR}/integration" ]; then
        if bats "${TEST_DIR}/integration"/*.bats; then
            print_success "Integration tests passed"
            return 0
        else
            print_error "Integration tests failed"
            return 1
        fi
    else
        print_warning "No integration tests found"
        return 0
    fi
}

# Run all tests
run_all_tests() {
    local exit_code=0
    
    # Run shellcheck
    if ! run_shellcheck; then
        exit_code=1
    fi
    
    echo ""
    
    # Run unit tests
    if ! run_unit_tests; then
        exit_code=1
    fi
    
    echo ""
    
    # Run integration tests
    if ! run_integration_tests; then
        exit_code=1
    fi
    
    return $exit_code
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run tests for hzn-utils scripts

OPTIONS:
    -u, --unit          Run only unit tests
    -i, --integration   Run only integration tests
    -s, --shellcheck    Run only shellcheck
    -v, --verbose       Verbose output
    -h, --help          Show this help message

EXAMPLES:
    $0                  Run all tests
    $0 --unit           Run only unit tests
    $0 --shellcheck     Run only shellcheck
    $0 -v               Run all tests with verbose output

EOF
}

# Parse command line arguments
UNIT_ONLY=false
INTEGRATION_ONLY=false
SHELLCHECK_ONLY=false
# shellcheck disable=SC2034  # VERBOSE is reserved for future use
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--unit)
            UNIT_ONLY=true
            shift
            ;;
        -i|--integration)
            INTEGRATION_ONLY=true
            shift
            ;;
        -s|--shellcheck)
            SHELLCHECK_ONLY=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            export VERBOSE  # Export for use in test scripts
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_header "hzn-utils Test Suite"
    echo ""
    
    # Check for bats
    if ! check_bats; then
        exit 1
    fi
    
    print_success "bats is installed"
    
    # Check optional dependencies
    check_optional_deps
    
    echo ""
    
    # Run tests based on options
    local exit_code=0
    
    if [ "$SHELLCHECK_ONLY" = true ]; then
        run_shellcheck || exit_code=$?
    elif [ "$UNIT_ONLY" = true ]; then
        run_unit_tests || exit_code=$?
    elif [ "$INTEGRATION_ONLY" = true ]; then
        run_integration_tests || exit_code=$?
    else
        run_all_tests || exit_code=$?
    fi
    
    echo ""
    print_header "Test Summary"
    
    if [ $exit_code -eq 0 ]; then
        print_success "All tests passed!"
    else
        print_error "Some tests failed"
    fi
    
    exit $exit_code
}

# Run main function
main

# Made with Bob
