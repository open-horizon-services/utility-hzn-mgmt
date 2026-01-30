#!/bin/bash

# Script to determine which Open Horizon admin utility scripts the user can run
# based on their authenticated role and permissions
# Usage: ./can-i-do-anything.sh [OPTIONS] [ENV_FILE]

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
            echo "Determine which Open Horizon admin utility scripts you can run based on"
            echo "your authenticated role and permissions."
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show detailed output with permission explanations"
            echo "  -j, --json       Output JSON only (for scripting/automation)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "Arguments:"
            echo "  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)"
            echo "                   If not provided, will prompt for selection"
            echo ""
            echo "Output Modes:"
            echo "  Default:  Interactive numbered list grouped by category"
            echo "  JSON:     Machine-readable structured output"
            echo "  Verbose:  Detailed descriptions with permission explanations"
            echo ""
            echo "Examples:"
            echo "  $0                    # Interactive mode"
            echo "  $0 --json mycreds.env # JSON output"
            echo "  $0 --verbose          # Detailed output"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 2
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
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Setup cleanup trap
# shellcheck disable=SC2119  # Function doesn't use positional parameters
setup_cleanup_trap

# Handle .env file selection and load credentials
selected_file=""  # Will be set by select_env_file
select_env_file "$ENV_FILE" || exit 2
load_credentials "$selected_file" || exit 2

# Display configuration (unless JSON mode)
if [ "$JSON_ONLY" = false ]; then
    print_header "Analyzing Available Scripts"
    echo ""
    print_info "Configuration:"
    echo "  Exchange URL:      $HZN_EXCHANGE_URL"
    echo "  Auth Organization: $HZN_ORG_ID"
    echo "  Auth User:         ${HZN_EXCHANGE_USER_AUTH%%:*}"
    echo ""
fi

# Check if curl is installed
check_curl || exit 2

# Check if jq is installed (optional but recommended)
check_jq

# Parse authentication credentials
parse_auth

# Use the Exchange URL as-is (it should already include the API version path)
# Remove trailing slash if present
BASE_URL="${HZN_EXCHANGE_URL%/}"

# Resolve actual username if using API key
if [ "$IS_API_KEY" = true ]; then
    resolve_apikey_username || exit 2
fi

# ============================================================================
# PHASE 1: Gather User Information
# ============================================================================

if [ "$JSON_ONLY" = false ]; then
    print_info "Fetching user information..."
    echo ""
fi

# Display the API request in verbose mode
display_api_request "GET" "${BASE_URL}/orgs/${HZN_ORG_ID}/users/${AUTH_USER}"

# Fetch current user info
user_response=$(curl -sS -k -w "\n%{http_code}" -u "$FULL_AUTH" "${BASE_URL}/orgs/${HZN_ORG_ID}/users/${AUTH_USER}" 2>&1)
user_http_code=$(echo "$user_response" | tail -n1)
user_body=$(echo "$user_response" | sed '$d')

if [ "$user_http_code" -ne 200 ]; then
    if [ "$JSON_ONLY" = true ]; then
        echo "{\"error\": \"Failed to fetch user info\", \"http_code\": $user_http_code}"
    else
        print_error "Failed to fetch user information (HTTP $user_http_code)"
        echo ""
        echo "Response: $user_body"
    fi
    exit 2
fi

# Parse user admin status
if [ "$JQ_AVAILABLE" = true ]; then
    user_key=$(echo "$user_body" | jq -r '.users | keys[0]')
    is_admin=$(echo "$user_body" | jq -r ".users[\"$user_key\"].admin // false")
    is_hub_admin=$(echo "$user_body" | jq -r ".users[\"$user_key\"].hubAdmin // false")
else
    # Fallback parsing without jq
    if echo "$user_body" | grep -q '"admin"[[:space:]]*:[[:space:]]*true'; then
        is_admin="true"
    else
        is_admin="false"
    fi
    if echo "$user_body" | grep -q '"hubAdmin"[[:space:]]*:[[:space:]]*true'; then
        is_hub_admin="true"
    else
        is_hub_admin="false"
    fi
fi

# Determine user role
if [ "$is_hub_admin" = "true" ]; then
    user_role="Hub Admin"
elif [ "$is_admin" = "true" ]; then
    user_role="Org Admin"
else
    user_role="Regular User"
fi

if [ "$JSON_ONLY" = false ]; then
    echo "User Role: $user_role"
    echo "  Org Admin:  $is_admin"
    echo "  Hub Admin:  $is_hub_admin"
    echo ""
fi

# ============================================================================
# PHASE 2: Test Core Permissions
# ============================================================================

if [ "$JSON_ONLY" = false ]; then
    print_info "Testing permissions..."
    echo ""
fi

# Test organization permissions
can_list_all_orgs=false
can_list_own_org=false
if [ -f "${SCRIPT_DIR}/can-i-list-orgs.sh" ]; then
    org_perms=$(bash "${SCRIPT_DIR}/can-i-list-orgs.sh" --json "$selected_file" 2>/dev/null || echo '{}')
    if [ "$JQ_AVAILABLE" = true ]; then
        org_scope=$(echo "$org_perms" | jq -r '.result.scope // "NONE"' 2>/dev/null)
        if [ "$org_scope" = "ALL" ]; then
            can_list_all_orgs=true
            can_list_own_org=true
        elif [ "$org_scope" = "OWN" ]; then
            can_list_own_org=true
        fi
    else
        # Fallback: assume based on admin status
        if [ "$is_hub_admin" = "true" ]; then
            can_list_all_orgs=true
            can_list_own_org=true
        elif [ "$is_admin" = "true" ]; then
            can_list_own_org=true
        fi
    fi
fi

# Test user permissions
can_list_users=false
if [ -f "${SCRIPT_DIR}/can-i-list-users.sh" ]; then
    user_perms=$(timeout 10 bash "${SCRIPT_DIR}/can-i-list-users.sh" --json "$selected_file" 2>/dev/null || echo '{}')
    if [ "$JQ_AVAILABLE" = true ]; then
        can_list_users=$(echo "$user_perms" | jq -r '.result.can_list_org_users // false' 2>/dev/null | head -1 | tr -d '\n\r')
    else
        # Fallback: assume based on admin status
        if [ "$is_admin" = "true" ] || [ "$is_hub_admin" = "true" ]; then
            can_list_users=true
        fi
    fi
fi

# Test service permissions (all authenticated users can list services)
can_list_services=true

if [ "$JSON_ONLY" = false ]; then
    print_success "Permission testing complete"
    echo ""
    echo "Permissions:"
    echo "  Can list all organizations:  $can_list_all_orgs"
    echo "  Can list own organization:   $can_list_own_org"
    echo "  Can list users:              $can_list_users"
    echo "  Can list services:           $can_list_services"
    echo ""
fi

# ============================================================================
# PHASE 3: Define Scripts and Test Runnability
# ============================================================================

# Temporarily disable unbound variable check for all array operations
# This is needed for Bash 3.2+ compatibility
set +u

# Define all scripts with metadata in a simple indexed array
# Format: script_name|category|description|requires_org_admin|requires_hub_admin|notes
declare -a ALL_SCRIPTS=(
    "list-orgs.sh|org|List organizations interactively|false|false|Uses hzn CLI, lists accessible orgs"
    "list-a-orgs.sh|org|List organizations via API|false|false|API-based, lists accessible orgs"
    "can-i-list-orgs.sh|org|Check organization listing permissions|false|false|Permission checker, always runnable"
    "list-users.sh|user|List users in organization|true|false|Lists users in organization"
    "list-a-users.sh|user|List users via API|true|false|API-based user listing"
    "list-user.sh|user|Show current user info|false|false|Shows own user info"
    "list-a-user.sh|user|Show current user info via API|false|false|API-based own user info"
    "can-i-list-users.sh|user|Check user listing permissions|false|false|Permission checker, always runnable"
    "list-a-org-nodes.sh|node|List all nodes in organization|true|false|Lists all nodes in organization"
    "list-a-user-nodes.sh|node|List nodes for specific user|false|false|Lists own nodes or specified user's nodes"
    "monitor-nodes.sh|node|Real-time node monitoring|false|false|Real-time monitoring of own nodes"
    "list-a-user-services.sh|service|List services for specific user|false|false|Lists own services or specified user's services"
    "can-i-list-services.sh|service|Check service listing permissions|false|false|Permission checker, always runnable"
    "list-a-user-deployment.sh|deployment|List deployment policies for user|false|false|Lists own deployment policies or specified user's"
    "test-credentials.sh|test|Test and validate credentials|false|false|Tests and validates credentials"
    "test-hzn.sh|test|Test CLI installation|false|false|Tests CLI installation"
)

# Build list of runnable scripts
declare -a runnable_scripts=()
declare -a restricted_scripts=()

for script_entry in "${ALL_SCRIPTS[@]}"; do
    IFS='|' read -r script_name category description requires_org_admin requires_hub_admin notes <<< "$script_entry"
    
    # Check if script file exists
    if [ ! -f "${SCRIPT_DIR}/${script_name}" ]; then
        continue
    fi
    
    # Determine if script is runnable
    is_runnable=true
    
    if [ "$requires_hub_admin" = "true" ] && [ "$is_hub_admin" != "true" ]; then
        is_runnable=false
    elif [ "$requires_org_admin" = "true" ] && [ "$is_admin" != "true" ] && [ "$is_hub_admin" != "true" ]; then
        is_runnable=false
    fi
    
    if [ "$is_runnable" = true ]; then
        runnable_scripts+=("$script_name|$category|$description|$requires_org_admin|$requires_hub_admin|$notes")
    else
        restricted_scripts+=("$script_name|$category|$description|$requires_org_admin|$requires_hub_admin|$notes")
    fi
done

# Sort scripts by category and name
# Use while read loop for portability (mapfile not available in older bash)
sorted_scripts=()
if [ ${#runnable_scripts[@]} -gt 0 ]; then
    while IFS= read -r line; do
        sorted_scripts+=("$line")
    done < <(printf '%s\n' "${runnable_scripts[@]}" | sort -t'|' -k2,2 -k1,1)
    runnable_scripts=("${sorted_scripts[@]}")
fi

# Re-enable unbound variable check after array operations
set -u

# ============================================================================
# PHASE 4: Output Results
# ============================================================================

if [ "$JSON_ONLY" = true ]; then
    # JSON output mode
    echo "{"
    echo "  \"user\": {"
    echo "    \"username\": \"$AUTH_USER\","
    echo "    \"organization\": \"$HZN_ORG_ID\","
    echo "    \"is_admin\": $is_admin,"
    echo "    \"is_hub_admin\": $is_hub_admin,"
    echo "    \"role\": \"$user_role\""
    echo "  },"
    echo "  \"permissions\": {"
    echo "    \"can_list_all_orgs\": $can_list_all_orgs,"
    echo "    \"can_list_own_org\": $can_list_own_org,"
    echo "    \"can_list_users\": $can_list_users,"
    echo "    \"can_list_services\": $can_list_services"
    echo "  },"
    echo "  \"scripts\": ["
    
    first=true
    for script_entry in "${runnable_scripts[@]}"; do
        IFS='|' read -r script_name category description requires_org_admin requires_hub_admin notes <<< "$script_entry"
        
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        
        # Determine required permission level
        if [ "$requires_hub_admin" = "true" ]; then
            requires="hub_admin"
        elif [ "$requires_org_admin" = "true" ]; then
            requires="org_admin"
        else
            requires="authenticated"
        fi
        
        echo -n "    {"
        echo -n "\"name\": \"$script_name\", "
        echo -n "\"category\": \"$category\", "
        echo -n "\"description\": \"$description\", "
        echo -n "\"path\": \"./$script_name\", "
        echo -n "\"runnable\": true, "
        echo -n "\"requires\": \"$requires\""
        echo -n "}"
    done
    echo ""
    echo "  ],"
    echo "  \"summary\": {"
    echo "    \"total_scripts\": ${#SCRIPTS[@]},"
    echo "    \"runnable_scripts\": ${#runnable_scripts[@]},"
    echo "    \"restricted_scripts\": ${#restricted_scripts[@]}"
    echo "  }"
    echo "}"
    
elif [ "$VERBOSE" = true ]; then
    # Verbose mode: detailed output with explanations
    print_header "Detailed Script Analysis for User: $AUTH_USER (Organization: $HZN_ORG_ID)"
    echo ""
    
    echo "User Information:"
    echo "  Username:      $AUTH_USER"
    echo "  Organization:  $HZN_ORG_ID"
    echo "  Org Admin:     $is_admin"
    echo "  Hub Admin:     $is_hub_admin"
    echo "  Role:          $user_role"
    echo ""
    
    echo "Permission Test Results:"
    if [ "$can_list_all_orgs" = true ]; then
        echo -e "  ${GREEN}✓${NC} Can list all organizations"
    elif [ "$can_list_own_org" = true ]; then
        echo -e "  ${GREEN}✓${NC} Can list own organization"
    else
        echo -e "  ${RED}✗${NC} Cannot list organizations"
    fi
    
    if [ "$can_list_users" = true ]; then
        echo -e "  ${GREEN}✓${NC} Can list users in organization"
    else
        echo -e "  ${RED}✗${NC} Cannot list users in organization"
    fi
    
    echo -e "  ${GREEN}✓${NC} Can list services (public and own)"
    echo -e "  ${GREEN}✓${NC} Can list own nodes"
    echo -e "  ${GREEN}✓${NC} Can list own deployment policies"
    echo ""
    
    # Display scripts by category (Bash 3.2 compatible approach)
    counter=1
    for category in org user node service deployment test; do
        # Find scripts in this category
        category_found=false
        for script_entry in "${runnable_scripts[@]}"; do
            IFS='|' read -r script_name cat description requires_org_admin requires_hub_admin notes <<< "$script_entry"
            if [ "$cat" = "$category" ]; then
                category_found=true
                break
            fi
        done
        
        if [ "$category_found" = false ]; then
            continue
        fi
        
        # Category header
        case $category in
            org) category_name="Organization Management Scripts" ;;
            user) category_name="User Management Scripts" ;;
            node) category_name="Node Management Scripts" ;;
            service) category_name="Service Management Scripts" ;;
            deployment) category_name="Deployment Policy Management Scripts" ;;
            test) category_name="Testing & Validation Scripts" ;;
        esac
        
        print_header "$category_name"
        echo ""
        
        # Display scripts in this category
        for script_entry in "${runnable_scripts[@]}"; do
            IFS='|' read -r script_name cat description requires_org_admin requires_hub_admin notes <<< "$script_entry"
            
            if [ "$cat" = "$category" ]; then
                echo "$counter. $script_name"
                echo "   Description:  $description"
                echo "   Path:         ./$script_name"
                echo -e "   Runnable:     ${GREEN}✓ YES${NC}"
                
                # Determine required permission level
                if [ "$requires_hub_admin" = "true" ]; then
                    echo "   Requires:     Hub Admin"
                elif [ "$requires_org_admin" = "true" ]; then
                    echo "   Requires:     Org Admin or Hub Admin"
                else
                    echo "   Requires:     Any authenticated user"
                fi
                
                if [ -n "$notes" ]; then
                    echo "   Notes:        $notes"
                fi
                echo ""
                
                ((counter++))
            fi
        done
    done
    
    # Show restricted scripts if any
    if [ ${#restricted_scripts[@]} -gt 0 ]; then
        print_header "Restricted Scripts (Not Available)"
        echo ""
        
        for script_entry in "${restricted_scripts[@]}"; do
            IFS='|' read -r script_name category description requires_org_admin requires_hub_admin notes <<< "$script_entry"
            
            echo -e "${RED}✗${NC} $script_name"
            echo "   Description:  $description"
            
            if [ "$requires_hub_admin" = "true" ]; then
                echo "   Requires:     Hub Admin (you are: $user_role)"
            elif [ "$requires_org_admin" = "true" ]; then
                echo "   Requires:     Org Admin or Hub Admin (you are: $user_role)"
            fi
            echo ""
        done
    fi
    
    print_header "Summary"
    echo ""
    echo "Total scripts available: ${#runnable_scripts[@]} of ${#SCRIPTS[@]}"
    if [ ${#restricted_scripts[@]} -gt 0 ]; then
        echo "Restricted scripts: ${#restricted_scripts[@]}"
    fi
    echo ""
    
else
    # Interactive mode: numbered list grouped by category
    print_header "Available Scripts for User: $AUTH_USER (Organization: $HZN_ORG_ID)"
    echo ""
    echo "Your Role: $user_role"
    echo ""
    
    # Display scripts by category (Bash 3.2 compatible - no associative arrays)
    counter=1
    for category in org user node service deployment test; do
        # Find scripts in this category
        category_found=false
        for script_entry in "${runnable_scripts[@]}"; do
            IFS='|' read -r script_name cat description requires_org_admin requires_hub_admin notes <<< "$script_entry"
            if [ "$cat" = "$category" ]; then
                category_found=true
                break
            fi
        done
        
        if [ "$category_found" = false ]; then
            continue
        fi
        
        # Category header
        case $category in
            org) category_name="Organization Management" ;;
            user) category_name="User Management" ;;
            node) category_name="Node Management" ;;
            service) category_name="Service Management" ;;
            deployment) category_name="Deployment Policy Management" ;;
            test) category_name="Testing & Validation" ;;
        esac
        
        # Count scripts in category
        script_count=0
        for script_entry in "${runnable_scripts[@]}"; do
            IFS='|' read -r script_name cat _ _ _ _ <<< "$script_entry"
            if [ "$cat" = "$category" ]; then
                script_count=$((script_count + 1))
            fi
        done
        
        echo "$category_name ($script_count script$([ "$script_count" -ne 1 ] && echo "s" || echo ""))"
        
        # Display scripts in this category
        for script_entry in "${runnable_scripts[@]}"; do
            IFS='|' read -r script_name cat description requires_org_admin requires_hub_admin notes <<< "$script_entry"
            
            if [ "$cat" = "$category" ]; then
                printf "%3d. %-30s - %s\n" "$counter" "$script_name" "$description"
                ((counter++))
            fi
        done
        echo ""
    done
    
    print_header "Summary"
    echo ""
    echo "Total: ${#runnable_scripts[@]} script$([ ${#runnable_scripts[@]} -ne 1 ] && echo "s" || echo "") available"
    echo ""
    
    if [ ${#restricted_scripts[@]} -gt 0 ]; then
        echo -e "${YELLOW}Note:${NC} ${#restricted_scripts[@]} script$([ ${#restricted_scripts[@]} -ne 1 ] && echo "s are" || echo " is") restricted due to insufficient permissions."
        echo "      Run with --verbose to see which scripts require higher privileges."
        echo ""
    fi
    
    echo "Note: Some scripts may require additional parameters when run."
    echo "      Use --help flag with any script for detailed usage information."
    echo ""
fi

exit 0