# Implementation Plan: can-i-do-anything.sh

## Overview

Create a comprehensive permission checker script that determines which Open Horizon admin utility scripts the authenticated user can run without errors based on their role and permissions.

## Purpose

- **Primary Goal**: Provide users with a clear understanding of what operations they can perform
- **User Experience**: Offer multiple output modes for different use cases (interactive exploration, automation, debugging)
- **Maintainability**: Design for easy updates when new scripts are added to the repository

## Script Behavior

### Three Output Modes

1. **Interactive Mode (Default)**
   - Display a numbered multiple-choice list of runnable scripts
   - Show brief description for each script
   - Group scripts by category (listing, permission checking, monitoring)
   - Color-coded indicators for permission levels
   - User-friendly formatting with headers and sections

2. **JSON Mode (`--json`)**
   - Output structured JSON array of runnable scripts
   - Include script name, path, description, required permissions
   - Machine-readable for automation and integration
   - No color codes or interactive elements

3. **Verbose Mode (`--verbose`)**
   - Detailed list with full descriptions
   - Show permission requirements for each script
   - Display why certain scripts are/aren't runnable
   - Include API endpoints used by each script
   - Show detailed permission test results

## Permission Testing Strategy

### Phase 1: Gather User Information
```bash
# Fetch authenticated user's role information
GET /orgs/{HZN_ORG_ID}/users/{AUTH_USER}

# Extract:
- is_admin (boolean)
- is_hub_admin (boolean)
- organization membership
```

### Phase 2: Test Core Permissions

Use existing `can-i-*` scripts to test permissions:

1. **Organizations** - `can-i-list-orgs.sh --json`
   - Determines: Hub Admin (all orgs) vs Org Admin (own org) vs Regular User (none)
   
2. **Users** - `can-i-list-users.sh --json`
   - Determines: Can list users in organization
   
3. **Services** - `can-i-list-services.sh --json`
   - Determines: Can list IBM public, org public, and own services

### Phase 3: Map Permissions to Scripts

Based on test results, determine which scripts are runnable:

## Script Permission Matrix

### Category: Organization Management

| Script | Required Permission | Notes |
|--------|-------------------|-------|
| `list-orgs.sh` | Any authenticated user | Uses hzn CLI, lists accessible orgs |
| `list-a-orgs.sh` | Any authenticated user | API-based, lists accessible orgs |
| `can-i-list-orgs.sh` | Any authenticated user | Permission checker, always runnable |

### Category: User Management

| Script | Required Permission | Notes |
|--------|-------------------|-------|
| `list-users.sh` | Org Admin or Hub Admin | Lists users in organization |
| `list-a-users.sh` | Org Admin or Hub Admin | API-based user listing |
| `list-user.sh` | Any authenticated user | Shows own user info |
| `list-a-user.sh` | Any authenticated user | API-based own user info |
| `can-i-list-users.sh` | Any authenticated user | Permission checker, always runnable |

### Category: Node Management

| Script | Required Permission | Notes |
|--------|-------------------|-------|
| `list-a-org-nodes.sh` | Org Admin or Hub Admin | Lists all nodes in organization |
| `list-a-user-nodes.sh` | Any authenticated user | Lists own nodes or specified user's nodes |
| `monitor-nodes.sh` | Any authenticated user | Real-time monitoring of own nodes |

### Category: Service Management

| Script | Required Permission | Notes |
|--------|-------------------|-------|
| `list-a-user-services.sh` | Any authenticated user | Lists own services or specified user's services |
| `can-i-list-services.sh` | Any authenticated user | Permission checker, always runnable |

### Category: Deployment Policy Management

| Script | Required Permission | Notes |
|--------|-------------------|-------|
| `list-a-user-deployment.sh` | Any authenticated user | Lists own deployment policies or specified user's |

### Category: Testing & Validation

| Script | Required Permission | Notes |
|--------|-------------------|-------|
| `test-credentials.sh` | Any authenticated user | Tests and validates credentials |
| `test-hzn.sh` | Any authenticated user | Tests CLI installation |

## Implementation Details

### Script Structure

```bash
#!/bin/bash
# can-i-do-anything.sh - Determine which scripts user can run

# Strict error handling
set -euo pipefail

# Default output mode
VERBOSE=false
JSON_ONLY=false
ENV_FILE=""

# Parse command line arguments
# Support: -v/--verbose, -j/--json, -h/--help, [ENV_FILE]

# Source common library
source "${SCRIPT_DIR}/lib/common.sh"

# Load credentials
# Parse authentication
# Resolve API key if needed

# Phase 1: Gather user information
# Phase 2: Test core permissions using can-i-* scripts
# Phase 3: Build runnable scripts list
# Phase 4: Output results based on mode
```

### Data Structure for Scripts

```bash
# Define all scripts with metadata
declare -A SCRIPTS=(
    # Format: "script_name|category|description|permission_test_function"
    
    # Organization Management
    ["list-orgs.sh"]="org|List organizations interactively|always_runnable"
    ["list-a-orgs.sh"]="org|List organizations via API|always_runnable"
    ["can-i-list-orgs.sh"]="org|Check organization listing permissions|always_runnable"
    
    # User Management
    ["list-users.sh"]="user|List users in organization|requires_org_admin"
    ["list-a-users.sh"]="user|List users via API|requires_org_admin"
    ["list-user.sh"]="user|Show current user info|always_runnable"
    ["list-a-user.sh"]="user|Show current user info via API|always_runnable"
    ["can-i-list-users.sh"]="user|Check user listing permissions|always_runnable"
    
    # Node Management
    ["list-a-org-nodes.sh"]="node|List all nodes in organization|requires_org_admin"
    ["list-a-user-nodes.sh"]="node|List nodes for specific user|always_runnable"
    ["monitor-nodes.sh"]="node|Real-time node monitoring|always_runnable"
    
    # Service Management
    ["list-a-user-services.sh"]="service|List services for specific user|always_runnable"
    ["can-i-list-services.sh"]="service|Check service listing permissions|always_runnable"
    
    # Deployment Policy Management
    ["list-a-user-deployment.sh"]="deployment|List deployment policies for user|always_runnable"
    
    # Testing & Validation
    ["test-credentials.sh"]="test|Test and validate credentials|always_runnable"
    ["test-hzn.sh"]="test|Test CLI installation|always_runnable"
)
```

### Permission Test Functions

```bash
# Test if user can run scripts requiring org admin
requires_org_admin() {
    # Use can-i-list-users.sh to test org admin permission
    # Return 0 if can list users, 1 otherwise
    local result
    result=$(./can-i-list-users.sh --json "$ENV_FILE" 2>/dev/null)
    
    # Parse JSON to check if can_list_org_users is true
    if echo "$result" | jq -e '.result.can_list_org_users == true' >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Scripts that are always runnable
always_runnable() {
    return 0
}

# Test if user can run scripts requiring hub admin
requires_hub_admin() {
    # Use can-i-list-orgs.sh to test hub admin permission
    local result
    result=$(./can-i-list-orgs.sh --json "$ENV_FILE" 2>/dev/null)
    
    # Parse JSON to check if scope is ALL
    if echo "$result" | jq -e '.result.scope == "ALL"' >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
```

### Output Formatting

#### Interactive Mode Output

```
═══════════════════════════════════════════════════════════════
Available Scripts for User: myuser (Organization: myorg)
═══════════════════════════════════════════════════════════════

Your Role: Org Admin

Organization Management (3 scripts)
  1. list-orgs.sh              - List organizations interactively
  2. list-a-orgs.sh            - List organizations via API
  3. can-i-list-orgs.sh        - Check organization listing permissions

User Management (5 scripts)
  4. list-users.sh             - List users in organization
  5. list-a-users.sh           - List users via API
  6. list-user.sh              - Show current user info
  7. list-a-user.sh            - Show current user info via API
  8. can-i-list-users.sh       - Check user listing permissions

Node Management (3 scripts)
  9. list-a-org-nodes.sh       - List all nodes in organization
 10. list-a-user-nodes.sh      - List nodes for specific user
 11. monitor-nodes.sh          - Real-time node monitoring

Service Management (2 scripts)
 12. list-a-user-services.sh   - List services for specific user
 13. can-i-list-services.sh    - Check service listing permissions

Deployment Policy Management (1 script)
 14. list-a-user-deployment.sh - List deployment policies for user

Testing & Validation (2 scripts)
 15. test-credentials.sh       - Test and validate credentials
 16. test-hzn.sh               - Test CLI installation

═══════════════════════════════════════════════════════════════
Total: 16 scripts available
═══════════════════════════════════════════════════════════════

Note: Some scripts may require additional parameters when run.
Use --help flag with any script for detailed usage information.
```

#### JSON Mode Output

```json
{
  "user": {
    "username": "myuser",
    "organization": "myorg",
    "is_admin": true,
    "is_hub_admin": false,
    "role": "Org Admin"
  },
  "permissions": {
    "can_list_orgs": true,
    "can_list_all_orgs": false,
    "can_list_users": true,
    "can_list_services": true
  },
  "scripts": [
    {
      "name": "list-orgs.sh",
      "category": "org",
      "description": "List organizations interactively",
      "path": "./list-orgs.sh",
      "runnable": true,
      "requires": "authenticated"
    },
    {
      "name": "list-users.sh",
      "category": "user",
      "description": "List users in organization",
      "path": "./list-users.sh",
      "runnable": true,
      "requires": "org_admin"
    }
    // ... more scripts
  ],
  "summary": {
    "total_scripts": 16,
    "runnable_scripts": 16,
    "restricted_scripts": 0
  }
}
```

#### Verbose Mode Output

```
═══════════════════════════════════════════════════════════════
Detailed Script Analysis for User: myuser (Organization: myorg)
═══════════════════════════════════════════════════════════════

User Information:
  Username:      myuser
  Organization:  myorg
  Org Admin:     true
  Hub Admin:     false
  Role:          Org Admin

Permission Test Results:
  ✓ Can list organizations (own org only)
  ✓ Can list users in organization
  ✓ Can list services (public and own)
  ✓ Can list own nodes
  ✓ Can list own deployment policies

═══════════════════════════════════════════════════════════════
Organization Management Scripts
═══════════════════════════════════════════════════════════════

1. list-orgs.sh
   Description:  List organizations interactively using hzn CLI
   Path:         ./list-orgs.sh
   Runnable:     ✓ YES
   Requires:     Any authenticated user
   API Used:     hzn exchange org list
   Notes:        Will show only accessible organizations

2. list-a-orgs.sh
   Description:  List organizations via REST API
   Path:         ./list-a-orgs.sh
   Runnable:     ✓ YES
   Requires:     Any authenticated user
   API Used:     GET /orgs
   Notes:        Supports --json and --verbose modes

3. can-i-list-orgs.sh
   Description:  Check organization listing permissions
   Path:         ./can-i-list-orgs.sh
   Runnable:     ✓ YES
   Requires:     Any authenticated user
   API Used:     GET /orgs, GET /orgs/{org}
   Notes:        Three-level permission verification

═══════════════════════════════════════════════════════════════
User Management Scripts
═══════════════════════════════════════════════════════════════

4. list-users.sh
   Description:  List users in organization using hzn CLI
   Path:         ./list-users.sh
   Runnable:     ✓ YES (Org Admin)
   Requires:     Org Admin or Hub Admin
   API Used:     hzn exchange user list
   Notes:        Can query different organization than auth org

// ... more detailed entries
```

## Integration with Existing Scripts

### Reuse Existing Permission Checkers

The script will call existing `can-i-*` scripts to determine permissions:

```bash
# Test organization permissions
org_perms=$(./can-i-list-orgs.sh --json "$ENV_FILE" 2>/dev/null)
can_list_all_orgs=$(echo "$org_perms" | jq -r '.result.scope == "ALL"')

# Test user permissions
user_perms=$(./can-i-list-users.sh --json "$ENV_FILE" 2>/dev/null)
can_list_users=$(echo "$user_perms" | jq -r '.result.can_list_org_users')

# Test service permissions
service_perms=$(./can-i-list-services.sh --json "$ENV_FILE" 2>/dev/null)
can_list_services=$(echo "$service_perms" | jq -r '.result.can_list_own_services')
```

### Use Common Library Functions

Leverage `lib/common.sh` for:
- Credential loading: `select_env_file()`, `load_credentials()`
- Authentication parsing: `parse_auth()`, `resolve_apikey_username()`
- Output formatting: `print_*()` functions, color codes
- Error handling: `setup_cleanup_trap()`

## Future Maintenance

### Adding New Scripts

When a new script is added to the repository:

1. **Update the SCRIPTS array** in `can-i-do-anything.sh`:
   ```bash
   ["new-script.sh"]="category|Description|permission_test_function"
   ```

2. **Add permission test function** if needed:
   ```bash
   requires_new_permission() {
       # Test logic here
       return 0  # or 1
   }
   ```

3. **Update documentation**:
   - Add entry to README.md
   - Add entry to AGENTS.md
   - Update this plan document

### Testing Checklist

Before committing changes:
- [ ] Run `./can-i-do-anything.sh` in interactive mode
- [ ] Run `./can-i-do-anything.sh --json` and validate JSON structure
- [ ] Run `./can-i-do-anything.sh --verbose` and check output
- [ ] Test with different user roles (regular user, org admin, hub admin)
- [ ] Run shellcheck: `shellcheck can-i-do-anything.sh`
- [ ] Run test suite: `./run-tests.sh`

## Error Handling

### Graceful Degradation

If permission test scripts fail:
- Log warning but continue
- Mark affected scripts as "unknown" status
- Provide troubleshooting tips in verbose mode

### Common Error Scenarios

1. **Can't reach Exchange API**
   - Show error message with troubleshooting tips
   - Exit with code 2

2. **Invalid credentials**
   - Show authentication error
   - Suggest running `test-credentials.sh`
   - Exit with code 2

3. **Missing dependencies**
   - Check for curl, jq (optional)
   - Provide installation instructions
   - Exit with code 2

## Exit Codes

- `0` - Success, displayed available scripts
- `1` - No scripts available (shouldn't happen for authenticated users)
- `2` - Error (invalid arguments, API error, authentication failure)

## Command Line Interface

```bash
Usage: ./can-i-do-anything.sh [OPTIONS] [ENV_FILE]

Determine which Open Horizon admin utility scripts you can run based on
your authenticated role and permissions.

Options:
  -v, --verbose    Show detailed output with permission explanations
  -j, --json       Output JSON only (for scripting/automation)
  -h, --help       Show this help message

Arguments:
  ENV_FILE         Optional: Path to .env file (e.g., mycreds.env)
                   If not provided, will prompt for selection

Examples:
  ./can-i-do-anything.sh                    # Interactive mode
  ./can-i-do-anything.sh --json mycreds.env # JSON output
  ./can-i-do-anything.sh --verbose          # Detailed output
```

## Implementation Timeline

1. **Phase 1**: Core functionality (interactive mode)
   - Credential loading
   - Permission testing
   - Script categorization
   - Basic output formatting

2. **Phase 2**: Additional modes
   - JSON output mode
   - Verbose output mode
   - Error handling improvements

3. **Phase 3**: Polish and testing
   - Comprehensive testing with different roles
   - Documentation updates
   - Integration with CI/CD

## Success Criteria

- [ ] Script correctly identifies user role and permissions
- [ ] All three output modes work correctly
- [ ] Integrates seamlessly with existing scripts
- [ ] Provides clear, actionable information to users
- [ ] Easy to maintain when new scripts are added
- [ ] Passes all tests (shellcheck, unit tests, integration tests)
- [ ] Documentation is complete and accurate

## Notes

- This script is a "meta-script" that helps users understand the ecosystem
- It should be kept up-to-date as new scripts are added
- Consider adding this to the CI/CD pipeline to ensure it stays current
- The script itself should always be runnable by any authenticated user
