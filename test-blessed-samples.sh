#!/bin/bash

# Script to validate blessedSamples.txt files used by exchangePublish.sh
# Validates file format and checks GitHub repository accessibility using GitHub API
# Usage: ./test-blessed-samples.sh [OPTIONS] [blessed-samples-file]

# Strict error handling
set -euo pipefail

# Get script directory and source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Default values
VERBOSE=false
JSON_ONLY=false
SKIP_NETWORK=false
CHECK_FILES=false  # Phase 2A: Check for required files
REPO_BASE="https://github.com/open-horizon/examples"  # Hardcoded for relative paths
BRANCH="master"
FILE_PATH=""
GITHUB_TOKEN="${GITHUB_TOKEN:-}"  # Optional GitHub token for authenticated API calls

# Validation counters
TOTAL_ENTRIES=0
VALID_COUNT=0
INVALID_COUNT=0
WARNING_COUNT=0

# Arrays to store validation results (Bash 3.2+ compatible)
VALIDATION_RESULTS=()

# Show usage information
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [blessed-samples-file]

Validate blessedSamples.txt files used by exchangePublish.sh.
Checks file format and GitHub repository accessibility using GitHub API.

OPTIONS:
    -v, --verbose       Show detailed validation output with API responses
    -j, --json          Output JSON only (for scripting/automation)
    -b, --branch BRANCH Branch to check (default: master)
    -s, --skip-network  Skip network checks (validate format only)
    -f, --check-files   Check for required files (Makefile, service.definition.json, etc.)
    -h, --help          Show this help message and exit

ARGUMENTS:
    blessed-samples-file  Optional: Path to blessedSamples.txt file
                         If not provided, looks for ./blessedSamples.txt

ENVIRONMENT VARIABLES:
    GITHUB_TOKEN        Optional: GitHub personal access token for authenticated API calls
                       Increases rate limit from 60 to 5000 requests/hour
                       Set with: export GITHUB_TOKEN=your_token_here

EXAMPLES:
    $(basename "$0")                           # Test ./blessedSamples.txt
    $(basename "$0") tools/blessedSamples.txt  # Test specific file
    $(basename "$0") --verbose                 # Detailed output
    $(basename "$0") --json                    # JSON output for CI/CD
    $(basename "$0") --skip-network            # Format validation only
    $(basename "$0") --check-files             # Verify required files exist
    
    # With GitHub token for higher rate limits:
    export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
    $(basename "$0") tools/blessedSamples.txt

FILE FORMAT:
    - One path per line
    - Blank lines ignored
    - Comments (lines starting with #) ignored
    - Two valid formats:
      * Relative: edge/services/helloworld
        (always refers to https://github.com/open-horizon/examples/)
      * Absolute: https://github.com/open-horizon-services/web-helloworld-python

VALIDATION CHECKS:
    ✓ File format and syntax
    ✓ Path format (relative vs absolute)
    ✓ Format consistency (warns on mixed formats)
    ✓ GitHub repository accessibility via API (if not --skip-network)
    ✓ Required files exist (if --check-files):
      - Makefile
      - service.definition.json or horizon/service.definition.json
      - deployment.policy.json or horizon/deployment.policy.json

EXIT CODES:
    0 - All validations passed
    1 - Validation failures found
    2 - Script error (invalid arguments, missing file, missing dependencies)

EOF
    exit 0
}

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
        -s|--skip-network)
            SKIP_NETWORK=true
            shift
            ;;
        -f|--check-files)
            CHECK_FILES=true
            shift
            ;;
        -b|--branch)
            if [[ -n "${2:-}" ]]; then
                BRANCH="$2"
                shift 2
            else
                echo "Error: --branch requires a branch name argument"
                exit 2
            fi
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 2
            ;;
        *)
            # Non-option argument, treat as file path
            FILE_PATH="$1"
            shift
            ;;
    esac
done

# Setup cleanup trap
# shellcheck disable=SC2119  # Function doesn't use positional parameters
setup_cleanup_trap

# If no file specified, look for blessedSamples.txt in current directory
if [ -z "$FILE_PATH" ]; then
    FILE_PATH="./blessedSamples.txt"
fi

# Check if file exists
if [ ! -f "$FILE_PATH" ]; then
    if [ "$JSON_ONLY" = true ]; then
        echo '{"error":"File not found","file":"'"$FILE_PATH"'","status":"error"}'
    else
        print_error "File not found: $FILE_PATH"
        echo ""
        echo "Please specify a valid blessedSamples.txt file"
        echo "Usage: $(basename "$0") [OPTIONS] [blessed-samples-file]"
    fi
    exit 2
fi

# Check dependencies
if [ "$SKIP_NETWORK" = false ]; then
    check_curl || exit 2
fi

# Check GitHub API rate limit
check_github_rate_limit() {
    local rate_info
    if [ -n "$GITHUB_TOKEN" ]; then
        rate_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/rate_limit" 2>/dev/null || echo "{}")
    else
        rate_info=$(curl -s "https://api.github.com/rate_limit" 2>/dev/null || echo "{}")
    fi
    
    if [ "$VERBOSE" = true ] && [ "$JSON_ONLY" = false ]; then
        local remaining
        remaining=$(echo "$rate_info" | grep -o '"remaining":[0-9]*' | head -1 | cut -d':' -f2 || echo "unknown")
        local limit
        limit=$(echo "$rate_info" | grep -o '"limit":[0-9]*' | head -1 | cut -d':' -f2 || echo "unknown")
        
        if [ -n "$GITHUB_TOKEN" ]; then
            print_info "GitHub API: Authenticated (Rate limit: $remaining/$limit)"
        else
            print_info "GitHub API: Unauthenticated (Rate limit: $remaining/$limit)"
            echo "  Tip: Set GITHUB_TOKEN environment variable for higher rate limits"
        fi
        echo ""
    fi
}

# Detect format type by analyzing all entries
detect_format() {
    local file="$1"
    local relative_count=0
    local absolute_count=0
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Check if line starts with http:// or https://
        if [[ "$line" =~ ^https?:// ]]; then
            absolute_count=$((absolute_count + 1))
        else
            relative_count=$((relative_count + 1))
        fi
    done < "$file"
    
    # Determine primary format
    if [ $relative_count -gt 0 ] && [ $absolute_count -eq 0 ]; then
        echo "relative"
    elif [ $absolute_count -gt 0 ] && [ $relative_count -eq 0 ]; then
        echo "absolute"
    elif [ $relative_count -gt 0 ] && [ $absolute_count -gt 0 ]; then
        echo "mixed"
    else
        echo "empty"
    fi
}

# Extract owner and repo from GitHub URL
parse_github_url() {
    local url="$1"
    # Extract owner/repo from URLs like https://github.com/owner/repo
    echo "$url" | sed -E 's|https?://github\.com/([^/]+)/([^/]+).*|\1/\2|'
}

# Check if a specific file exists in GitHub repository
# Args: owner_repo, file_path, branch
# Returns: HTTP status code
check_file_exists() {
    local owner_repo="$1"
    local file_path="$2"
    local branch="$3"
    
    local api_url="https://api.github.com/repos/${owner_repo}/contents/${file_path}?ref=${branch}"
    
    local http_code
    if [ -n "$GITHUB_TOKEN" ]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    "$api_url" 2>/dev/null || echo "000")
    else
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                    "$api_url" 2>/dev/null || echo "000")
    fi
    
    echo "$http_code"
}

# Validate required files exist in repository
# Args: owner_repo, base_path, branch
# Returns: JSON object with file check results
validate_required_files() {
    local owner_repo="$1"
    local base_path="$2"
    local branch="$3"
    
    # Remove trailing slash from base_path if present
    base_path="${base_path%/}"
    
    # Initialize results
    local makefile_status="missing"
    local service_def_status="missing"
    local deployment_policy_status="missing"
    local makefile_path=""
    local service_def_path=""
    local deployment_policy_path=""
    
    # Check for Makefile
    local http_code
    http_code=$(check_file_exists "$owner_repo" "${base_path}/Makefile" "$branch")
    if [ "$http_code" = "200" ]; then
        makefile_status="found"
        makefile_path="${base_path}/Makefile"
    fi
    
    # Check for service.definition.json (try root first, then horizon/)
    http_code=$(check_file_exists "$owner_repo" "${base_path}/service.definition.json" "$branch")
    if [ "$http_code" = "200" ]; then
        service_def_status="found"
        service_def_path="${base_path}/service.definition.json"
    else
        http_code=$(check_file_exists "$owner_repo" "${base_path}/horizon/service.definition.json" "$branch")
        if [ "$http_code" = "200" ]; then
            service_def_status="found"
            service_def_path="${base_path}/horizon/service.definition.json"
        fi
    fi
    
    # Check for deployment.policy.json (try root first, then horizon/)
    http_code=$(check_file_exists "$owner_repo" "${base_path}/deployment.policy.json" "$branch")
    if [ "$http_code" = "200" ]; then
        deployment_policy_status="found"
        deployment_policy_path="${base_path}/deployment.policy.json"
    else
        http_code=$(check_file_exists "$owner_repo" "${base_path}/horizon/deployment.policy.json" "$branch")
        if [ "$http_code" = "200" ]; then
            deployment_policy_status="found"
            deployment_policy_path="${base_path}/horizon/deployment.policy.json"
        fi
    fi
    
    # Return JSON object with results
    cat <<EOF
{
  "makefile": {
    "status": "$makefile_status",
    "path": "$makefile_path"
  },
  "service_definition": {
    "status": "$service_def_status",
    "path": "$service_def_path"
  },
  "deployment_policy": {
    "status": "$deployment_policy_status",
    "path": "$deployment_policy_path"
  }
}
EOF
}

# Check if GitHub repository/path exists using GitHub API
check_github_path() {
    local owner_repo="$1"
    local path="$2"
    local branch="$3"
    
    # Use GitHub Contents API to check if path exists
    local api_url="https://api.github.com/repos/${owner_repo}/contents/${path}?ref=${branch}"
    
    local http_code
    if [ -n "$GITHUB_TOKEN" ]; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "$api_url" 2>/dev/null || echo "000")
    else
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$api_url" 2>/dev/null || echo "000")
    fi
    
    echo "$http_code"
}

# Validate a single entry
validate_entry() {
    local entry="$1"
    local line_num="$2"
    local format_type="$3"
    local result_status="valid"
    local result_message=""
    local entry_type=""
    local http_code="000"
    local owner_repo=""
    local path=""
    local file_check_results=""
    
    # Determine entry type
    if [[ "$entry" =~ ^https?:// ]]; then
        entry_type="absolute"
        owner_repo=$(parse_github_url "$entry")
        # For absolute URLs, check if the repository root exists
        path=""
    else
        entry_type="relative"
        # Relative paths always refer to open-horizon/examples
        owner_repo="open-horizon/examples"
        path="$entry"
    fi
    
    # Format validation
    if [ "$VERBOSE" = true ] && [ "$JSON_ONLY" = false ]; then
        echo "─────────────────────────────────────────────────────────"
        print_info "Line $line_num: $entry"
        echo "  Type: $entry_type"
        if [ "$entry_type" = "relative" ]; then
            echo "  Full path: https://github.com/$owner_repo/tree/$BRANCH/$path"
        else
            echo "  Repository: https://github.com/$owner_repo"
        fi
    fi
    
    # Check for format consistency
    if [ "$format_type" = "mixed" ]; then
        if [ "$WARNING_COUNT" -eq 0 ]; then
            # Only warn once about mixed format
            WARNING_COUNT=$((WARNING_COUNT + 1))
            if [ "$VERBOSE" = true ] && [ "$JSON_ONLY" = false ]; then
                print_warning "Mixed format detected (both relative and absolute URLs)"
                echo ""
            fi
        fi
    fi
    
    # Network validation (if not skipped)
    if [ "$SKIP_NETWORK" = false ]; then
        if [ "$VERBOSE" = true ] && [ "$JSON_ONLY" = false ]; then
            echo "  Checking GitHub API..."
        fi
        
        # Check if path exists using GitHub API
        http_code=$(check_github_path "$owner_repo" "$path" "$BRANCH")
        
        if [ "$VERBOSE" = true ] && [ "$JSON_ONLY" = false ]; then
            echo "  HTTP Response: $http_code"
        fi
        
        if [ "$http_code" = "200" ]; then
            result_status="valid"
            if [ "$entry_type" = "relative" ]; then
                result_message="Path exists in repository"
            else
                result_message="Repository accessible"
            fi
            
            # Additional file checks if requested
            if [ "$CHECK_FILES" = true ]; then
                if [ "$VERBOSE" = true ] && [ "$JSON_ONLY" = false ]; then
                    echo "  Checking required files..."
                fi
                
                # Validate required files exist
                file_check_results=$(validate_required_files "$owner_repo" "$path" "$BRANCH")
                
                # Parse results
                local makefile_status service_def_status deployment_policy_status
                if command -v jq >/dev/null 2>&1; then
                    makefile_status=$(echo "$file_check_results" | jq -r '.makefile.status')
                    service_def_status=$(echo "$file_check_results" | jq -r '.service_definition.status')
                    deployment_policy_status=$(echo "$file_check_results" | jq -r '.deployment_policy.status')
                else
                    # Fallback parsing without jq
                    makefile_status=$(echo "$file_check_results" | grep -A1 '"makefile"' | grep '"status"' | cut -d'"' -f4)
                    service_def_status=$(echo "$file_check_results" | grep -A1 '"service_definition"' | grep '"status"' | cut -d'"' -f4)
                    deployment_policy_status=$(echo "$file_check_results" | grep -A1 '"deployment_policy"' | grep '"status"' | cut -d'"' -f4)
                fi
                
                # Check if all required files are found
                # Required: Makefile and service.definition.json
                # Optional: deployment.policy.json (only needed for policy-based deployments)
                local missing_files=()
                [ "$makefile_status" != "found" ] && missing_files+=("Makefile")
                [ "$service_def_status" != "found" ] && missing_files+=("service.definition.json")
                
                if [ ${#missing_files[@]} -gt 0 ]; then
                    result_status="invalid"
                    result_message="Missing required files: ${missing_files[*]}"
                    INVALID_COUNT=$((INVALID_COUNT + 1))
                    if [ "$JSON_ONLY" = false ]; then
                        print_error "✗ Line $line_num: $entry"
                        echo "  Error: $result_message"
                    fi
                else
                    VALID_COUNT=$((VALID_COUNT + 1))
                    if [ "$VERBOSE" = true ] && [ "$JSON_ONLY" = false ]; then
                        print_success "  ✓ All required files found"
                        # Note optional files
                        if [ "$deployment_policy_status" = "found" ]; then
                            echo "  ℹ deployment.policy.json found (optional)"
                        else
                            echo "  ℹ deployment.policy.json not found (optional - only needed for policy-based deployments)"
                        fi
                    fi
                    if [ "$JSON_ONLY" = false ]; then
                        print_success "✓ Line $line_num: $entry"
                    fi
                    result_message="Path exists and all required files found"
                fi
                
                # file_check_results variable is available for storing
            else
                VALID_COUNT=$((VALID_COUNT + 1))
                if [ "$JSON_ONLY" = false ]; then
                    print_success "✓ Line $line_num: $entry"
                fi
            fi
        elif [ "$http_code" = "404" ]; then
            result_status="invalid"
            if [ "$entry_type" = "relative" ]; then
                result_message="Path not found in repository (HTTP 404)"
            else
                result_message="Repository not found (HTTP 404)"
            fi
            INVALID_COUNT=$((INVALID_COUNT + 1))
            if [ "$JSON_ONLY" = false ]; then
                print_error "✗ Line $line_num: $entry"
                echo "  Error: $result_message"
            fi
        elif [ "$http_code" = "403" ]; then
            result_status="invalid"
            result_message="API rate limit exceeded or access forbidden (HTTP 403)"
            INVALID_COUNT=$((INVALID_COUNT + 1))
            if [ "$JSON_ONLY" = false ]; then
                print_error "✗ Line $line_num: $entry"
                echo "  Error: $result_message"
                echo "  Tip: Set GITHUB_TOKEN environment variable for higher rate limits"
            fi
        else
            result_status="invalid"
            result_message="Unable to access repository (HTTP $http_code)"
            INVALID_COUNT=$((INVALID_COUNT + 1))
            if [ "$JSON_ONLY" = false ]; then
                print_error "✗ Line $line_num: $entry"
                echo "  Error: $result_message"
            fi
        fi
    else
        # Skip network check, just validate format
        result_status="valid"
        result_message="Format valid (network check skipped)"
        VALID_COUNT=$((VALID_COUNT + 1))
        if [ "$JSON_ONLY" = false ]; then
            print_success "✓ Line $line_num: $entry"
        fi
    fi
    
    # Store result for JSON output (with optional file check results)
    # Encode file_check_results in base64 to preserve newlines
    local encoded_file_checks=""
    if [ "$CHECK_FILES" = true ] && [ -n "${file_check_results:-}" ]; then
        encoded_file_checks=$(echo "$file_check_results" | base64)
    fi
    VALIDATION_RESULTS+=("$line_num|$entry|$entry_type|$result_status|$result_message|$http_code|$encoded_file_checks")
    
    if [ "$VERBOSE" = true ] && [ "$JSON_ONLY" = false ]; then
        echo ""
    fi
}

# Output results in JSON format
output_json() {
    local format_type="$1"
    local overall_status="passed"
    
    if [ $INVALID_COUNT -gt 0 ]; then
        overall_status="failed"
    fi
    
    echo "{"
    echo "  \"file\": \"$FILE_PATH\","
    echo "  \"format\": \"$format_type\","
    echo "  \"base_repository\": \"$REPO_BASE\","
    echo "  \"branch\": \"$BRANCH\","
    echo "  \"skip_network\": $SKIP_NETWORK,"
    echo "  \"check_files\": $CHECK_FILES,"
    echo "  \"github_token_set\": $([ -n "$GITHUB_TOKEN" ] && echo "true" || echo "false"),"
    echo "  \"total_entries\": $TOTAL_ENTRIES,"
    echo "  \"valid_count\": $VALID_COUNT,"
    echo "  \"invalid_count\": $INVALID_COUNT,"
    echo "  \"warning_count\": $WARNING_COUNT,"
    echo "  \"status\": \"$overall_status\","
    echo "  \"entries\": ["
    
    local first=true
    
    for result in "${VALIDATION_RESULTS[@]}"; do
        IFS='|' read -r line_num entry entry_type status message http_code encoded_file_checks <<< "$result"
        
        # Decode file check data if present
        local file_check_data=""
        if [ -n "$encoded_file_checks" ]; then
            file_check_data=$(echo "$encoded_file_checks" | base64 -d 2>/dev/null || echo "")
        fi
        
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        
        echo -n "    {"
        echo -n "\"line\": $line_num, "
        echo -n "\"content\": \"$entry\", "
        echo -n "\"type\": \"$entry_type\", "
        echo -n "\"status\": \"$status\", "
        echo -n "\"message\": \"$message\""
        if [ -n "$http_code" ] && [ "$http_code" != "000" ]; then
            echo -n ", \"http_code\": $http_code"
        fi
        
        # Add file check results if available
        if [ -n "$file_check_data" ] && [ "$CHECK_FILES" = true ]; then
            echo -n ", \"file_checks\": $file_check_data"
            file_check_data=""  # Reset for next entry
        fi
        
        echo -n "}"
    done
    
    echo ""
    echo "  ]"
    echo "}"
}

# Main validation logic
main() {
    # Detect format
    FORMAT_TYPE=$(detect_format "$FILE_PATH")
    
    if [ "$FORMAT_TYPE" = "empty" ]; then
        if [ "$JSON_ONLY" = true ]; then
            echo '{"error":"No valid entries found","file":"'"$FILE_PATH"'","status":"error"}'
        else
            print_error "No valid entries found in $FILE_PATH"
        fi
        exit 2
    fi
    
    # Check GitHub rate limit (if doing network checks)
    if [ "$SKIP_NETWORK" = false ]; then
        check_github_rate_limit
    fi
    
    # Print header (non-JSON mode)
    if [ "$JSON_ONLY" = false ]; then
        echo "═══════════════════════════════════════════════════════════"
        echo "  Validating Blessed Samples File"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        echo "File: $FILE_PATH"
        echo "Format: $FORMAT_TYPE"
        echo "Base Repository: $REPO_BASE (for relative paths)"
        echo "Branch: $BRANCH"
        if [ "$SKIP_NETWORK" = true ]; then
            print_warning "Network checks disabled (--skip-network)"
        fi
        echo ""
        if [ "$VERBOSE" = false ]; then
            print_info "Validating entries..."
            echo ""
        fi
    fi
    
    # Validate each entry
    local line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        TOTAL_ENTRIES=$((TOTAL_ENTRIES + 1))
        validate_entry "$line" "$line_num" "$FORMAT_TYPE"
    done < "$FILE_PATH"
    
    # Output results
    if [ "$JSON_ONLY" = true ]; then
        output_json "$FORMAT_TYPE"
    else
        # Print summary
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "  Validation Summary"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
        echo "Total Entries: $TOTAL_ENTRIES"
        print_success "Valid: $VALID_COUNT"
        if [ $INVALID_COUNT -gt 0 ]; then
            print_error "Invalid: $INVALID_COUNT"
        else
            echo "Invalid: $INVALID_COUNT"
        fi
        if [ $WARNING_COUNT -gt 0 ]; then
            print_warning "Warnings: $WARNING_COUNT"
        else
            echo "Warnings: $WARNING_COUNT"
        fi
        echo ""
        
        if [ $INVALID_COUNT -eq 0 ]; then
            print_success "Status: PASSED"
        else
            print_error "Status: FAILED ($INVALID_COUNT error(s) found)"
        fi
        echo ""
    fi
    
    # Exit with appropriate code
    if [ $INVALID_COUNT -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main
