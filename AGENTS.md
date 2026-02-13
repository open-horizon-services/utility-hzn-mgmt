# Open Horizon Admin Utilities

The purpose of this repo is to collect scripts that will automate creation, listing, and removing of organizations, users, services, and nodes in an Open Horizon instance.

## Project Structure

```
hzn-utils/
├── lib/
│   └── common.sh              # Shared library with common functions
├── list-orgs.sh               # Interactive organization listing (hzn CLI)
├── list-users.sh              # Interactive user listing (hzn CLI)
├── list-user.sh               # Current user info (hzn CLI)
├── list-a-orgs.sh             # API-based organization listing
├── list-a-users.sh            # API-based user listing
├── list-a-user.sh             # API-based current user info
├── can-i-list-users.sh      # Permission verification script
├── list-a-org-nodes.sh        # API-based organization node listing
├── list-a-user-nodes.sh       # API-based user node listing
├── list-a-user-services.sh    # API-based user service listing
├── list-a-user-deployment.sh  # API-based user deployment policy listing
├── monitor-nodes.sh           # Real-time node monitoring utility
├── test-credentials.sh        # Credential validation tool
├── test-hzn.sh                # CLI installation test
└── *.env                      # Credential files (not in git)
```

├── can-i-list-services.sh     # Service permission verification
├── can-i-do-anything.sh       # Comprehensive permission checker

## Available Scripts

This repository contains several utility scripts for managing Open Horizon instances:

### Interactive Scripts (using hzn CLI)
- **`list-orgs.sh`** - Interactive script to list organizations and optionally view users
- **`list-users.sh`** - Interactive script to list users in an organization
- **`list-user.sh`** - Display current authenticated user info and validate credentials
- **`test-credentials.sh`** - Test and validate your Open Horizon credentials

### Permission Scripts
- **`can-i-list-services.sh`** - Check if user can list services at different levels
- **`can-i-do-anything.sh`** - Comprehensive checker showing all runnable scripts

- **`can-i-list-users.sh`** - Check if user can list users in an organization
- **`can-i-list-orgs.sh`** - Check if user can list organizations

### API-Based Scripts (using REST API)
- **`list-a-orgs.sh`** - List organizations using REST API with multiple output modes
- **`list-a-users.sh`** - List users using REST API with multiple output modes
- **`list-a-user.sh`** - Display current authenticated user info using REST API
- **`list-a-org-nodes.sh`** - List nodes in an organization using REST API
- **`list-a-user-nodes.sh`** - List nodes for a specific user using REST API
- **`list-a-user-services.sh`** - List services for a specific user using REST API
- **`list-a-user-deployment.sh`** - List deployment policies for a specific user using REST API

### Monitoring Scripts
- **`monitor-nodes.sh`** - Real-time node monitoring utility (like 'top' for nodes)

### Testing Scripts
- **`test-hzn.sh`** - Test Open Horizon CLI installation and configuration

### Shared Library
- **`lib/common.sh`** - Common functions used across all scripts including:
  - Color-coded output functions
  - Credential management and validation
  - Environment file selection
  - Tool availability checks (curl, jq, hzn)
  - Error handling and cleanup
  - API key authentication support with automatic username resolution

## Shell Compatibility Notes

### Bash Version Requirements
**CRITICAL: All scripts in this repository MUST be compatible with Bash 3.2+**

These scripts are designed to work with Bash 3.2+ for maximum compatibility across different systems (including older macOS versions). This is a hard requirement - do not use features that require Bash 4.0+.

**Bash 4.0+ Features That Are NOT ALLOWED:**
- **Associative Arrays (`declare -A`)**: NOT AVAILABLE in Bash 3.x. Use indexed arrays instead.
- **`mapfile` / `readarray`**: NOT AVAILABLE in Bash 3.x. Use `while read` loops instead for array population.
- **`&>>` redirect operator**: NOT AVAILABLE in Bash 3.x. Use `>> file 2>&1` instead.
- **`**` globstar pattern**: NOT AVAILABLE in Bash 3.x without `shopt -s globstar`.
- **Negative array indices**: NOT AVAILABLE in Bash 3.x. Use `${array[@]: -1}` workarounds.

**Bash 3.2+ Features That ARE ALLOWED:**
- **Process substitution** (`< <(command)`): Available in Bash 3.2+ and used throughout scripts.
- **Indexed arrays** with `+=()` operator: Available in Bash 3.2+.
- **`[[ ]]` test operator**: Available in Bash 3.2+.
- **`${var//pattern/replacement}` substitution**: Available in Bash 3.2+.

**Portable Array Population Pattern:**
```bash
# Instead of: mapfile -t array < <(command)
# Use this portable approach:
array=()
while IFS= read -r item; do
    [ -n "$item" ] && array+=("$item")
done < <(command)
```

This pattern is used throughout the scripts to ensure compatibility with Bash 3.2+ while maintaining functionality.

## Usage

### Is the CLI installed, configured, and running?

#### Installed and location
`which hzn` should tell you if the binary is installed and available.

#### Running
`hzn version` should tell you if the CLI is running.  You should receive values for both the CLI and the agent.  If the agent is not running, you will receive an error message like below:

```bash
$ hzn version
Horizon CLI version: 2.31.0-1528
Horizon Agent version: failed to get.
```

On macOS, you can try running the agent with IF docker desktop or podman desktop is installed and running:

```bash
horizon-container start
```

If that throws an error message like the following, then start Docker Desktop or Podman Desktop:

```bash
Starting the Horizon agent container openhorizon/amd64_anax:2.31.0-1528...
failed to connect to the docker API at unix:///Users/josephpearson/.docker/run/docker.sock; check if the path is correct and if the daemon is running: dial unix /Users/josephpearson/.docker/run/docker.sock: connect: no such file or directory
Error: exit code 1 from: docker run
```

IF running `horizon-contain start` results in an error message like the following, then you need to stop and restart the container:

```bash
Starting the Horizon agent container openhorizon/amd64_anax:2.31.0-1528...
docker: Error response from daemon: Conflict. The container name "/horizon1" is already in use by container "1ff9c8e008e5c9900108db92570b564efac8b2d72f08d30bf32de3502d8c7c72". You have to remove (or rename) that container to be able to reuse that name.

Run 'docker run --help' for more information
Error: exit code 125 from: docker run
```

Then `horizon-container stop` and `horizon-container start` should resolve the issue.  NOTE: Stopping the container may require you to enter your password.

When it is running properly, you should see something like the following:

```bash
% hzn version
Horizon CLI version: 2.31.0-1528
Horizon Agent version: 2.31.0-1528
```

#### Configured

##### Node configured?

```bash
hzn node ls
```

Should return something like the following:

```bash
% hzn node ls
{
  "id": "joeinteel",
  "organization": null,
  "pattern": null,
  "name": null,
  "nodeType": null,
  "clusterNamespace": null,
  "token_last_valid_time": "",
  "token_valid": null,
  "ha_group": null,
  "configstate": {
    "state": "unconfigured",
    "last_update_time": ""
  },
  "configuration": {
    "exchange_api": "http://open-horizon.lfedge.iol.unh.edu:3090/v1/",
    "exchange_version": "2.110.4",
    "required_minimum_exchange_version": "2.90.1",
    "preferred_exchange_version": "2.110.1",
    "mms_api": "http://open-horizon.lfedge.iol.unh.edu:9443",
    "architecture": "amd64",
    "horizon_version": "2.31.0-1528"
  }
}
```

##### Exchange reachable and user authenticated?

```bash
hzn ex user ls
```

If you see something like the following, you do not have the proper environment variables set:

```bash
Error: organization ID must be specified with either the -o flag or HZN_ORG_ID
```

If it is properly configured and reachable, the response will be similar to the following:

```bash
{
  "examples/joewxboy": {
    "password": "********",
    "email": "joe.pearson@us.ibm.com",
    "admin": true,
    "hubAdmin": false,
    "lastUpdated": "2025-04-25T18:26:34.773362847Z[UTC]",
    "updatedBy": "root/root"
  }
}
```

Where "examples/joewxboy" is your org ID and user ID, "email" is your email address, and "admin" is true if you are an admin.

## Script Documentation

### list-orgs.sh (Interactive Organization Listing)

Interactive script that allows you to select credentials from multiple .env files and list organizations. After listing organizations, it prompts you to select one to view its users.

**Usage:**
```bash
./list-orgs.sh
```

**Features:**
- Interactive .env file selection
- Lists all organizations
- Prompts to select an organization to view users
- Automatically calls list-users.sh for the selected organization
- Color-coded output with status indicators

**Workflow:**
1. Searches for .env files in current directory
2. Prompts user to select credentials
3. Loads and validates credentials
4. Lists all organizations
5. Prompts to select an organization
6. Calls list-users.sh to display users in selected organization

### list-users.sh (Interactive User Listing)

Interactive script to list users in a specific organization. Can be called standalone or from list-orgs.sh.

**Usage:**
```bash
# Interactive mode (prompts for .env file)
./list-users.sh

# Specify organization (uses environment credentials)
./list-users.sh <org-id>

# Called from list-orgs.sh (credentials passed via environment)
# Automatically uses credentials from parent script
```

**Features:**
- Interactive .env file selection (if not called from another script)
- Lists users with email addresses
- Shows admin and hub admin status
- Can query different organization than auth organization
- Reuses credentials when called from list-orgs.sh

### list-a-orgs.sh (API-Based Organization Listing)

Advanced script using REST API directly with multiple output modes for automation and scripting.

**Usage:**
```bash
# Interactive mode
./list-a-orgs.sh

# Use specific .env file
./list-a-orgs.sh mycreds.env

# JSON output only (for piping/automation)
./list-a-orgs.sh --json mycreds.env

# Verbose mode with full JSON details
./list-a-orgs.sh --verbose
```

**Options:**
- `-v, --verbose` - Show detailed JSON response with headers
- `-j, --json` - Output raw JSON only (no colors, headers, or messages)
- `-h, --help` - Show help message

**Features:**
- Direct REST API calls using curl
- Multiple output modes (simple, verbose, JSON-only)
- Access permission checking for each organization
- Supports both interactive and non-interactive modes
- Detailed error messages and troubleshooting tips
- Optional jq support for better JSON parsing

**Output Modes:**
1. **Default**: Simple list of organization names
2. **Verbose** (`--verbose`): Full JSON response with formatting
3. **JSON-only** (`--json`): Raw JSON for automation/piping

### list-a-users.sh (API-Based User Listing)

Advanced script using REST API directly with multiple output modes for automation and scripting.

**Usage:**
```bash
# Interactive mode
./list-a-users.sh

# Use specific .env file
./list-a-users.sh mycreds.env

# JSON output only (for piping/automation)
./list-a-users.sh --json mycreds.env

# Verbose mode with full JSON details
./list-a-users.sh --verbose
```

**Options:**
- `-v, --verbose` - Show detailed JSON response with headers
- `-j, --json` - Output raw JSON only (no colors, headers, or messages)
- `-h, --help` - Show help message

**Features:**
- Direct REST API calls using curl
- Multiple output modes (simple, verbose, JSON-only)
- User role analysis (admin, hub admin, regular users)
- Email address display
- Color-coded role indicators
- Supports both interactive and non-interactive modes
- Optional jq support for better JSON parsing

**User Role Legend:**
- `[Org Admin]` (Yellow) - Administrative access within the organization
- `[Hub Admin]` (Magenta) - Hub-level administrative access
- (no badge) - Regular user with standard permissions

### test-credentials.sh (Credential Testing)

Test and validate Open Horizon credentials from .env files.

**Usage:**
```bash
./test-credentials.sh
```

**Features:**
- Interactive .env file selection
- Validates all required environment variables
- Tests Exchange connectivity
- Verifies user authentication
- Checks user permissions
- Displays credential summary
- Provides detailed troubleshooting tips on failure

**Validation Checks:**
- ✓ Exchange URL is reachable
- ✓ Organization exists
- ✓ User is authenticated
- ✓ User has permission to list users
- ✓ Counts users in organization

### can-i-list-orgs.sh (Organization Permission Verification)

Advanced script to check if the authenticated user can list organizations using two-phase verification.

**Technical Implementation:**

**Two-Phase Verification Process:**
1. **Phase 1 - Predictive Check**: Fetches user info from `/orgs/{HZN_ORG_ID}/users/{AUTH_USER}` and analyzes `admin` and `hubAdmin` status to predict permission
2. **Phase 2 - Actual Verification**: Calls `GET /orgs` API endpoint to verify actual permission
3. **Phase 3 - Comparison**: Compares predicted vs actual results and reports status (CONFIRMED or MISMATCH)

**Permission Logic:**
- **Hub Admin** (`hubAdmin: true`): Can list ALL organizations (predicted: YES, scope: ALL)
- **Org Admin** (`admin: true`, `hubAdmin: false`): Can only list their own organization (predicted: YES, scope: OWN)
- **Regular User** (`admin: false`, `hubAdmin: false`): Cannot list organizations (predicted: NO, scope: NONE)

**Key Differences from can-i-list-users.sh:**
1. **No target organization parameter**: Listing orgs is a global operation, not org-specific
2. **Different API endpoint**: Uses `/orgs` instead of `/orgs/{org}/users`
3. **Simpler permission model**: Only hubAdmin can list ALL orgs; org admins see only their own
4. **Organization count tracking**: Counts and displays number of organizations returned
5. **Scope indication**: Shows whether user can see ALL orgs or just OWN org

**Output Modes:**
- **Default**: Human-readable with color-coded status indicators
- **Verbose** (`--verbose`): Includes full API responses with JSON formatting
- **JSON** (`--json`): Machine-readable output for automation

**Exit Codes:**
- `0`: User CAN list organizations (actual permission granted)
- `1`: User CANNOT list organizations (actual permission denied)
- `2`: Error (invalid arguments, API error, authentication failure)

**API Key Authentication:**
Like `can-i-list-users.sh`, this script supports API key authentication and automatically resolves the username before performing permission checks.

**Integration Points:**
- Uses `lib/common.sh` for credential management and output formatting
- Shares credential loading logic with other API-based scripts
- Compatible with multiple `.env` file support
- Supports API key authentication with automatic username resolution

### can-i-list-users.sh (User Permission Verification)

Advanced script to check if the authenticated user can list users using three-level verification (general to specific).

**Usage:**
```bash
# Check permission in auth organization
./can-i-list-users.sh

# Check permission in different organization
./can-i-list-users.sh -o other-org

# JSON output for automation
./can-i-list-users.sh --json mycreds.env

# Verbose mode for debugging
./can-i-list-users.sh --verbose
```

**Options:**
- `-o, --org ORG` - Target organization to check (default: auth org)
- `-v, --verbose` - Show detailed output with API responses
- `-j, --json` - Output JSON only (for scripting/automation)
- `-h, --help` - Show help message

**Three-Level Verification (General → Specific):**

**Level 1: List ALL Users (across all organizations)**
- **Endpoint**: Tests access to different organization's users
- **Permission Required**: Hub Admin only
- **Purpose**: Verify if user can access users across ALL organizations

**Level 2: List Users in Target Organization**
- **Endpoint**: `GET /orgs/{target_org}/users`
- **Permission Required**: Org Admin (in target org) or Hub Admin
- **Purpose**: Verify if user can list users in the specified organization

**Level 3: View Own User Information**
- **Endpoint**: `GET /orgs/{auth_org}/users/{auth_user}`
- **Permission Required**: Any authenticated user (self-access)
- **Purpose**: Verify user can at least access their own information

**Features:**
- Progressive permission testing from broadest to narrowest scope
- Shows exactly what the user can and cannot access
- Detailed troubleshooting showing where permissions break down
- Multiple output modes (human-readable, JSON, verbose)
- **API key authentication support** - Automatically resolves username from API key
- Exit codes: 0 (can list org users), 1 (cannot list), 2 (error)

**API Key Authentication:**
When using API key authentication (`HZN_EXCHANGE_USER_AUTH=apikey:<key>`), the script automatically:
1. Detects the API key format
2. Queries `/orgs/{org}/users/apikey` to resolve the actual username
3. Uses the resolved username for permission checks

## Environment File Configuration

All scripts use `.env` files for credential management. Create one or more `.env` files with the following format:


### can-i-list-services.sh (Service Permission Verification)

Advanced script to check if the authenticated user can list services at different access levels using three-level verification (general to specific).

**Technical Implementation:**

**Three-Level Verification Process:**
1. **Level 1 - IBM Public Services**: Tests `GET /orgs/{ibm_org}/services` to verify access to IBM's public service catalog
2. **Level 2 - Org Public Services**: Tests `GET /orgs/{target_org}/services` to verify access to organization's public services
3. **Level 3 - Own Services**: Tests `GET /orgs/{auth_org}/services?owner={auth_org}/{auth_user}` to verify access to user's own services

**Service Visibility Model:**
- **Public Services**: Visible to all authenticated users across all organizations
- **Private Services**: Only visible to the service owner
- **IBM Services**: Special organization containing shared public services accessible to all users

**Permission Logic:**

**Level 1: IBM Public Services**
- **Prediction**: Always YES for authenticated users
- **Reason**: IBM public services are accessible to all authenticated users
- **Filtering**: Counts only services where `public: true`
- **Scope**: IBM organization (configurable via `--ibm-org` flag)

**Level 2: Organization Public Services**
- **Prediction**: Always YES for authenticated users
- **Reason**: Public services in any organization are accessible to all users
- **Filtering**: Counts only services where `public: true`
- **Scope**: Target organization (specified via `--org` flag or defaults to auth org)

**Level 3: Own Services (Public + Private)**
- **Prediction**: Always YES for authenticated users
- **Reason**: Users can always list their own services
- **Filtering**: Counts all services (both public and private)
- **Scope**: Services owned by authenticated user in auth organization

**Key Differences from Other Permission Scripts:**

1. **No Admin Requirements**: Unlike user/org listing, service listing doesn't require admin privileges


### can-i-do-anything.sh (Comprehensive Permission Checker)

Advanced meta-script that determines which Open Horizon admin utility scripts the authenticated user can run based on their role and permissions. Provides a comprehensive overview of available operations.

**Technical Implementation:**

**Core Architecture:**

1. **Phase 1: User Information Gathering**
   - Fetches authenticated user's role via `GET /orgs/{HZN_ORG_ID}/users/{AUTH_USER}`
   - Extracts `admin` and `hubAdmin` status
   - Determines user role: Hub Admin, Org Admin, or Regular User

2. **Phase 2: Permission Testing**
   - Calls existing `can-i-list-orgs.sh --json` to test organization permissions
   - Calls existing `can-i-list-users.sh --json` to test user listing permissions
   - Calls existing `can-i-list-services.sh --json` to test service permissions
   - Aggregates results to build permission profile

3. **Phase 3: Script Mapping**
   - Maintains internal registry of all available scripts with metadata
   - Maps each script to required permission level
   - Filters scripts based on user's actual permissions
   - Groups scripts by category for organized display

4. **Phase 4: Output Generation**
   - Formats results based on selected output mode
   - Provides actionable information about available operations

**Script Registry Structure:**

```bash
declare -A SCRIPTS=(
    # Format: "script_name"="category|description|requires_org_admin|requires_hub_admin|notes"
    
    # Organization Management
    ["list-orgs.sh"]="org|List organizations interactively|false|false|Uses hzn CLI"
    ["list-a-orgs.sh"]="org|List organizations via API|false|false|API-based"
    ["can-i-list-orgs.sh"]="org|Check organization listing permissions|false|false|Always runnable"
    
    # User Management
    ["list-users.sh"]="user|List users in organization|true|false|Requires org admin"
    ["list-a-users.sh"]="user|List users via API|true|false|Requires org admin"
    ["list-user.sh"]="user|Show current user info|false|false|Always runnable"
    ["list-a-user.sh"]="user|Show current user info via API|false|false|Always runnable"
    ["can-i-list-users.sh"]="user|Check user listing permissions|false|false|Always runnable"
    
    # Node Management
    ["list-a-org-nodes.sh"]="node|List all nodes in organization|true|false|Requires org admin"
    ["list-a-user-nodes.sh"]="node|List nodes for specific user|false|false|Always runnable"
    ["monitor-nodes.sh"]="node|Real-time node monitoring|false|false|Always runnable"
    
    # Service Management
    ["list-a-user-services.sh"]="service|List services for specific user|false|false|Always runnable"
    ["can-i-list-services.sh"]="service|Check service listing permissions|false|false|Always runnable"
    
    # Deployment Policy Management
    ["list-a-user-deployment.sh"]="deployment|List deployment policies for user|false|false|Always runnable"
    
    # Testing & Validation
    ["test-credentials.sh"]="test|Test and validate credentials|false|false|Always runnable"
    ["test-hzn.sh"]="test|Test CLI installation|false|false|Always runnable"
)
```

**Permission Logic:**

```bash
# Determine if script is runnable
is_runnable=true

if [ "$requires_hub_admin" = "true" ] && [ "$is_hub_admin" != "true" ]; then
    is_runnable=false
elif [ "$requires_org_admin" = "true" ] && [ "$is_admin" != "true" ] && [ "$is_hub_admin" != "true" ]; then
    is_runnable=false
fi
```

**Usage:**
```bash
# Interactive mode (default)
./can-i-do-anything.sh

# Use specific .env file
./can-i-do-anything.sh mycreds.env

# JSON output for automation
./can-i-do-anything.sh --json mycreds.env

# Verbose mode with detailed explanations
./can-i-do-anything.sh --verbose
```

**Options:**
- `-v, --verbose` - Show detailed output with permission explanations
- `-j, --json` - Output JSON only (for scripting/automation)
- `-h, --help` - Show help message

**Output Modes:**

**1. Interactive Mode (Default):**
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
```

**2. JSON Mode (`--json`):**
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
    "can_list_all_orgs": false,
    "can_list_own_org": true,
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

**3. Verbose Mode (`--verbose`):**
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
  ✓ Can list own organization
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
   Notes:        Uses hzn CLI, lists accessible orgs

2. list-a-orgs.sh
   Description:  List organizations via REST API
   Path:         ./list-a-orgs.sh
   Runnable:     ✓ YES
   Requires:     Any authenticated user
   Notes:        API-based, lists accessible orgs

// ... more detailed entries
```

**Script Categories:**

1. **Organization Management** (3 scripts)
   - Organization listing and permission checking
   - Available to all authenticated users
   - Hub admins see all orgs, org admins see own org

2. **User Management** (5 scripts)
   - User listing and information retrieval
   - Admin scripts require org admin or hub admin
   - Self-info scripts available to all users

3. **Node Management** (3 scripts)
   - Node listing and monitoring
   - Org-wide listing requires admin
   - User-specific listing available to all

4. **Service Management** (2 scripts)
   - Service listing and permission checking
   - All authenticated users can list services
   - Public services visible to everyone

5. **Deployment Policy Management** (1 script)
   - Deployment policy listing
   - Users can list their own policies

6. **Testing & Validation** (2 scripts)
   - Credential and CLI testing
   - Available to all authenticated users

**Integration with Existing Scripts:**

The script leverages existing permission checkers:

```bash
# Test organization permissions
org_perms=$(bash "${SCRIPT_DIR}/can-i-list-orgs.sh" --json "$selected_file" 2>/dev/null)
can_list_all_orgs=$(echo "$org_perms" | jq -r '.result.scope == "ALL"')

# Test user permissions
user_perms=$(bash "${SCRIPT_DIR}/can-i-list-users.sh" --json "$selected_file" 2>/dev/null)
can_list_users=$(echo "$user_perms" | jq -r '.result.can_list_org_users')

# Test service permissions
service_perms=$(bash "${SCRIPT_DIR}/can-i-list-services.sh" --json "$selected_file" 2>/dev/null)
can_list_services=$(echo "$service_perms" | jq -r '.result.can_list_own_services')
```

**Key Features:**

1. **Automatic Permission Detection**
   - No manual configuration needed
   - Tests actual API permissions
   - Handles API key authentication

2. **Comprehensive Coverage**
   - Covers all 16+ utility scripts in repository
   - Groups by functional category
   - Shows both available and restricted scripts

3. **Multiple Output Formats**
   - Interactive for exploration
   - JSON for automation
   - Verbose for troubleshooting

4. **User-Friendly**
   - Clear role identification
   - Numbered list for easy reference
   - Helpful notes and descriptions

**Maintenance Guidelines:**

When adding a new script to the repository:

1. **Update the SCRIPTS array:**
   ```bash
   ["new-script.sh"]="category|Description|requires_org_admin|requires_hub_admin|notes"
   ```

2. **Choose appropriate category:**
   - `org` - Organization management
   - `user` - User management
   - `node` - Node management
   - `service` - Service management
   - `deployment` - Deployment policy management
   - `test` - Testing and validation

3. **Set permission requirements:**
   - `requires_org_admin`: true if script needs org admin or hub admin
   - `requires_hub_admin`: true if script needs hub admin only
   - Both false if available to all authenticated users

4. **Add descriptive notes:**
   - Brief explanation of what the script does
   - Any special requirements or behaviors

5. **Update documentation:**
   - Add entry to README.md
   - Add entry to AGENTS.md
   - Update this section if new categories are added

**Error Handling:**

1. **Permission Test Failures:**
   - Gracefully degrades if permission scripts fail
   - Falls back to role-based assumptions
   - Logs warnings in verbose mode

2. **Missing Scripts:**
   - Checks for script file existence before listing
   - Skips non-existent scripts silently
   - No errors if optional scripts are missing

3. **Authentication Failures:**
   - Clear error messages with troubleshooting tips
   - Suggests running `test-credentials.sh`
   - Exit code 2 for errors

**Exit Codes:**
- `0` - Success, displayed available scripts
- `1` - No scripts available (shouldn't happen for authenticated users)
- `2` - Error (invalid arguments, API error, authentication failure)

**Design Decisions:**

1. **Why use existing can-i-* scripts:**
   - Avoids code duplication
   - Ensures consistent permission logic
   - Leverages well-tested implementations

2. **Why group by category:**
   - Easier to find related scripts
   - Logical organization for users
   - Scales well as more scripts are added

3. **Why three output modes:**
   - Interactive for human exploration
   - JSON for automation and integration
   - Verbose for debugging and learning

4. **Why test actual permissions:**
   - More accurate than role-based assumptions
   - Handles edge cases and custom configurations
   - Provides real-world validation

**Performance Considerations:**

1. **Permission Testing:**
   - Runs 3 permission check scripts (orgs, users, services)
   - Each makes 1-3 API calls
   - Total execution time: 2-5 seconds typically

2. **Optimization Opportunities:**
   - Cache permission test results
   - Parallel execution of permission checks
   - Skip tests if role is obvious (e.g., hub admin)

3. **Current Trade-offs:**
   - Accuracy over speed
   - Comprehensive testing over quick results
   - Real API validation over assumptions

**Future Enhancements:**

1. **Filtering Options:**
   - Filter by category
   - Filter by permission level
   - Search by script name or description

2. **Interactive Execution:**
   - Allow running scripts directly from the list
   - Pass parameters interactively
   - Chain multiple script executions

3. **Permission Caching:**
   - Cache permission test results
   - Configurable cache duration
   - Force refresh option

4. **Custom Script Registry:**
   - Support for user-defined scripts
   - External script registry file
   - Plugin architecture for extensions

This implementation provides a powerful, user-friendly tool for understanding and navigating the Open Horizon admin utilities ecosystem, with careful attention to maintainability, accuracy, and user experience.


2. **Public/Private Filtering**: Must accurately filter and count services by visibility
3. **IBM Organization**: Special handling for IBM org as a shared service catalog
4. **Owner Parameter**: Uses `owner={org}/{user}` format for Level 3 queries
5. **Service Counting**: Tracks total, public, and private service counts separately

**Output Modes:**
- **Default**: Human-readable with service counts at each level
- **Verbose** (`--verbose`): Includes full API responses with JSON formatting
- **JSON** (`--json`): Machine-readable output for automation

**Exit Codes:**
- `0`: User CAN list services at all tested levels
- `1`: User CANNOT list services at one or more levels (but can list own)
- `2`: Error (invalid arguments, API error, authentication failure)

**Service Filtering Implementation:**

```bash
# For Level 1 & 2 (public services only):
if [ "$JQ_AVAILABLE" = true ]; then
  public_count=$(echo "$response" | jq '[.services[] | select(.public == true)] | length')
else
  # Fallback parsing for public services
  public_count=$(echo "$response" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len([s for s in data.get('services', {}).values() if s.get('public', False)]))")
fi

# For Level 3 (all own services):
total_count=$(echo "$response" | jq '.services | length')
public_count=$(echo "$response" | jq '[.services[] | select(.public == true)] | length')
private_count=$((total_count - public_count))
```

**API Key Authentication:**
Like other permission scripts, this script supports API key authentication and automatically resolves the username before performing permission checks.

**Integration Points:**
- Uses `lib/common.sh` for credential management and output formatting
- Shares credential loading logic with other API-based scripts
- Compatible with multiple `.env` file support
- Supports API key authentication with automatic username resolution
- Uses `test_api_access` and `count_json_items` functions from common library

**Special Considerations:**
1. **IBM Org Configuration**: Supports custom IBM org names via `--ibm-org` flag (default: "IBM")
2. **Public Service Filtering**: Must accurately filter services by `public: true` field for Levels 1 & 2
3. **Service Counting**: Distinguishes between total services and public-only services
4. **Owner Format**: Uses `{org}/{user}` format for owner parameter in Level 3
5. **Error Handling**: Handles cases where IBM org doesn't exist or is inaccessible
6. **Backward Compatibility**: Follows same patterns as `can-i-list-users.sh` and `can-i-list-orgs.sh`


```bash
HZN_EXCHANGE_URL=https://open-horizon.lfedge.iol.unh.edu:3090/v1/
HZN_ORG_ID=myorg
HZN_EXCHANGE_USER_AUTH=myuser:mypassword
```

**Multiple Environment Support:**
You can create multiple `.env` files for different environments:
- `production.env`
- `staging.env`
- `development.env`
- `mycreds.env`
- etc.

**Security Note:** Never commit `.env` files to version control. Add `*.env` to `.gitignore` (except `example.env`).

### Listing Organizations

**Using the hzn CLI:**

**Using the hzn CLI:**
```bash
# Set required environment variables
export HZN_EXCHANGE_URL="https://<exchange-host>/api/v1"
export HZN_ORG_ID="<your-org-id>"
export HZN_EXCHANGE_USER_AUTH="<user>:<password>"

# List all organizations
hzn exchange org list

# List organizations with detailed info
hzn exchange org list -l

# List a specific organization
hzn exchange org list <org-id>
```

**Required Configuration:**
- `HZN_EXCHANGE_URL`: The Horizon Exchange API URL
- `HZN_ORG_ID`: Your organization ID
- `HZN_EXCHANGE_USER_AUTH`: User credentials in format `<user>:<password>`

**Using the REST API:**
```bash
# List all organizations
curl -u "<org>/<user>:<password>" \
  "https://<exchange-host>/api/v1/orgs"

# List only IBM-managed organizations
curl -u "<org>/<user>:<password>" \
  "https://<exchange-host>/api/v1/orgs?orgtype=IBM"
```

**Configuration File:**
You can also configure these settings in `~/.hzn/hzn.json`:
```json
{
  "HZN_EXCHANGE_URL": "https://my-exchange.example.com/api/v1",
  "HZN_ORG_ID": "myorg",
  "HZN_EXCHANGE_USER_AUTH": "myuser:mypassword"
}
```

### Other Common Operations

**Create an organization:**
```bash
hzn exchange org create --description="My Organization" myorg
```

**List users:**
```bash
hzn exchange user list
```

**List nodes:**
```bash
hzn exchange node list
```

**List services:**
```bash
hzn exchange service list
```

**Note:** Version numbers shown in examples (e.g., 2.31.0-1528) may vary based on your Open Horizon installation.

## Development Workflow

### Git Workflow Pattern

When performing new work in this repository:

1. **Check for open issues first** - Ask the user if unsure whether to use an existing issue
2. **If no open issue exists:**
   - Open a new issue describing the work
   - Label it `bug` or `enhancement` depending on the type of work
   - Create the label if it doesn't exist in the repository
3. **Create a branch** with the pattern `issue-#` (e.g., `issue-3`)
4. **Before committing changes:**
   - **Always update `README.md` and `AGENTS.md`** to document any new scripts or features
   - Run tests: `./run-tests.sh`
   - Run shellcheck: `shellcheck *.sh`
5. **When committing changes:**
   - Use the `-s` sign-off flag
   - Prefix the commit title with `Issue #: ` (e.g., `Issue #3: Fix false failure report`)
6. **When opening the PR:**
   - Use the same `Issue #: ` prefix in the PR title
   - Link to the issue in the PR description
   - Ensure CI/CD tests pass

### Design Principles

1. **Three operation modes:**
   - **Default**: Interactive exploration with prompts and helpful output
   - **Verbose**: Exhaustive details for troubleshooting (`--verbose`)
   - **Minimal**: Machine-readable JSON for automation (`--json`)

2. **Minimal dependencies:**
   - Bash 3.2+ compatibility (macOS support)
   - curl (required for API scripts)
   - jq (optional but recommended for JSON parsing)
   - hzn CLI (optional, only for CLI-based scripts)

3. **Security first:**
   - Never commit `.env` files to version control
   - Support multiple credential files for different environments
   - Clear error messages for authentication failures
   - Validate SSL certificates (with option to skip for dev environments)

4. **Error handling:**
   - Use `set -euo pipefail` for strict error handling
   - Implement trap handlers for cleanup
   - Provide helpful error messages with troubleshooting tips
   - Exit with appropriate status codes

5. **Testing:**
   - Write unit tests for shared library functions
   - Write integration tests for complete scripts
   - Run tests before committing: `./run-tests.sh`
   - Maintain test fixtures in `tests/fixtures/`

### Code Style Guidelines

- Use consistent indentation (2 spaces)
- Add comments for complex logic
- Use descriptive variable names
- Follow existing patterns in the codebase
- Use color-coded output for user-facing messages
- Implement cleanup functions with trap handlers
- Validate inputs before processing
- Provide multiple output modes where appropriate

### Testing Requirements

Before submitting a PR:

```bash
# Run all tests
./run-tests.sh

# Run specific test types
./run-tests.sh --unit          # Unit tests only
./run-tests.sh --integration   # Integration tests only
./run-tests.sh --shellcheck    # Static analysis only

# Run shellcheck manually
shellcheck *.sh lib/*.sh
```

### Documentation Requirements

When adding new features:

1. Update `README.md` with:
   - Script description and usage examples
   - Available options and flags
   - Output format examples
   - Troubleshooting tips

2. Update `AGENTS.md` with:
   - Technical implementation details
   - Design decisions
   - Integration points with other scripts

3. Update `.cursor/scratchpad.md` (project roadmap) if:
   - Completing a roadmap item
   - Identifying new improvement opportunities

4. Add inline comments for:
   - Complex logic or algorithms
   - Non-obvious design decisions
   - Workarounds for compatibility issues

This guide ensures consistent, maintainable, and secure code across all Open Horizon admin utilities.

### monitor-nodes.sh (Real-Time Node Monitoring)

Real-time monitoring utility for Open Horizon nodes, functioning like the `top` command for system processes. Provides a continuously updating display of node status sorted by most recent heartbeat activity.

**Technical Implementation:**

**Core Architecture:**
1. **Initialization Phase:**
   - Parse command line arguments (interval, user, output mode)
   - Load credentials from .env file
   - Validate configuration
   - Set up terminal control (hide cursor, trap signals)

2. **Data Fetching:**
   - API endpoint: `GET /orgs/{orgid}/nodes?owner={org/userid}`
   - Extracts node metadata including `lastHeartbeat` timestamp
   - Parses ISO 8601 UTC timestamps with nanosecond precision
   - Handles both jq and Python fallback for JSON parsing

3. **Data Processing:**
   - Converts ISO 8601 timestamps to Unix epoch seconds
   - Calculates time difference from current time
   - Sorts nodes by heartbeat timestamp (most recent first)
   - Categorizes nodes by heartbeat age (active/stale/inactive)
   - Formats timestamps as human-readable relative time

4. **Display Loop:**
   - Clears screen (in interactive mode)
   - Renders header with summary statistics
   - Displays table with node information
   - Shows footer with interactive controls
   - Sleeps for configured interval
   - Repeats until user exits

**Key Implementation Details:**

**Timestamp Handling:**
```bash
# Convert ISO 8601 to Unix epoch
timestamp_to_seconds() {
    local timestamp="$1"
    timestamp="${timestamp%\[UTC\]}"  # Remove [UTC] suffix
    # Try Linux date format first, then macOS
    if date -d "$timestamp" +%s 2>/dev/null; then
        return 0
    elif date -j -f "%Y-%m-%dT%H:%M:%S" "${timestamp%.*}" +%s 2>/dev/null; then
        return 0
    else
        echo "0"
    fi
}
```

**Human-Readable Time Formatting:**
```bash
format_time_ago() {
    local diff=$((now - then))
    if [ $diff -lt 60 ]; then
        echo "${diff}s ago"
    elif [ $diff -lt 3600 ]; then
        echo "$((diff / 60))m ago"
    elif [ $diff -lt 86400 ]; then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}
```

**Status Determination Logic:**
Since the Exchange API doesn't provide a `configstate` field in the node response, status is determined by heartbeat age:
- **Active** (Green): `lastHeartbeat` < 2 minutes ago
- **Stale** (Yellow): `lastHeartbeat` 2-10 minutes ago
- **Inactive** (Red): `lastHeartbeat` > 10 minutes ago

**Color Coding Implementation:**
```bash
get_heartbeat_color() {
    local diff=$((now - then))
    if [ $diff -lt 120 ]; then
        echo "$GREEN"      # < 2 minutes
    elif [ $diff -lt 600 ]; then
        echo "$YELLOW"     # 2-10 minutes
    else
        echo "$RED"        # > 10 minutes
    fi
}
```

**Terminal Control:**
- Uses `tput civis` to hide cursor during monitoring
- Uses `tput cnorm` to restore cursor on exit
- Implements trap handler for graceful cleanup on INT/TERM signals
- Uses `clear` command to refresh display between updates

**Interactive Input Handling:**
```bash
# Non-blocking read with timeout
if read -t "$REFRESH_INTERVAL" -n 1 key 2>/dev/null; then
    case "$key" in
        q|Q) break ;;           # Quit
        r|R) fetch_and_display_nodes ;;  # Force refresh
    esac
else
    # Timeout reached, auto-refresh
    fetch_and_display_nodes
fi
```

**Node Data Structure:**
Each node is stored as a pipe-delimited string for sorting:
```
{timestamp}|{name}|{type}|{arch}|{pattern}|{heartbeat}
```

This format allows efficient sorting by timestamp using `sort -t'|' -k1 -rn`.

**API Response Fields Used:**
- `lastHeartbeat` - Primary field for monitoring and sorting
- `name` - Node identifier (without org prefix)
- `nodeType` - "device" or "cluster"
- `arch` - Architecture (arm64, amd64, etc.)
- `pattern` - Deployment pattern (empty string if none)
- `owner` - Full owner identifier (org/user format)

**Output Modes:**

1. **Interactive Mode (Default):**
   - Continuous monitoring with screen refresh
   - Color-coded status indicators
   - Summary statistics in header
   - Interactive controls (q, r)
   - Cursor hidden during operation

2. **Once Mode (`--once`):**
   - Single execution, no loop
   - Display output once and exit
   - Useful for scripting and automation
   - Cursor remains visible

3. **JSON Mode (`--json`):**
   - Raw JSON output from API
   - No formatting or color codes
   - Implies `--once` mode
   - Suitable for piping to other tools

**Cross-Platform Compatibility:**

**Date Command Differences:**
- **Linux**: `date -d "$timestamp" +%s`
- **macOS**: `date -j -f "%Y-%m-%dT%H:%M:%S" "$timestamp" +%s`
- Script tries both formats for maximum compatibility

**Terminal Capabilities:**
- Uses `tput` commands with error suppression (`2>/dev/null || true`)
- Gracefully degrades if terminal doesn't support cursor control
- Color codes can be disabled with `--no-color` flag

**Performance Considerations:**

1. **API Call Frequency:**
   - Default 10-second refresh interval balances responsiveness and load
   - Configurable via `-i` flag (minimum 1 second)
   - Single API call per refresh (efficient)

2. **JSON Parsing:**
   - Prefers `jq` for performance (if available)
   - Falls back to Python for compatibility
   - Parses entire response once, extracts all needed fields

3. **Sorting:**
   - Uses Unix `sort` command (highly optimized)
   - Sorts by numeric timestamp (fast)
   - Reverse order for most recent first

**Error Handling:**

1. **API Failures:**
   - Displays error message with HTTP status code
   - Shows response body for debugging
   - Provides troubleshooting tips
   - Exits gracefully (doesn't loop on errors)

2. **Invalid JSON:**
   - Validates JSON before parsing
   - Shows raw response on validation failure
   - Prevents script crashes from malformed data

3. **Signal Handling:**
   - Trap handler for EXIT, INT, TERM signals
   - Always restores cursor visibility
   - Clean terminal state on exit

**Integration Points:**

1. **Common Library (`lib/common.sh`):**
   - Uses `select_env_file()` for credential selection
   - Uses `load_credentials()` for .env file loading
   - Uses `parse_auth()` for authentication parsing
   - Uses `check_curl()` and `check_jq()` for dependency checks
   - Uses color code constants (RED, GREEN, YELLOW, etc.)
   - Uses `print_*()` functions for consistent output

2. **Credential Management:**
   - Supports multiple .env files
   - Interactive selection if not specified
   - Validates required environment variables
   - Extracts user ID from credentials if not provided

3. **API Authentication:**
   - Uses same authentication format as other scripts
   - Supports both `user:password` and `org/user:password` formats
   - Compatible with API key authentication (via common library)

**Design Decisions:**

1. **Why `lastHeartbeat` over `lastUpdated`:**
   - `lastHeartbeat` specifically tracks node check-ins
   - `lastUpdated` can change for other reasons (config updates, etc.)
   - More accurate indicator of node health and activity

2. **Why 2-minute threshold for "Active":**
   - Default heartbeat interval is typically 60 seconds
   - 2 minutes allows for one missed heartbeat
   - Balances sensitivity with false positives

3. **Why sort by heartbeat (not alphabetically):**
   - Most important information is node health/activity
   - Recent activity indicates healthy nodes
   - Stale nodes naturally sink to bottom
   - Easier to spot problems at a glance

4. **Why terminal control (hide cursor):**
   - Reduces visual noise during updates
   - Prevents cursor flicker on refresh
   - Professional appearance similar to `top`
   - Always restored on exit for safety

5. **Why default 10-second interval:**
   - Balances responsiveness with API load
   - Frequent enough to catch issues quickly
   - Not so frequent as to overwhelm Exchange
   - User-configurable for different needs

**Limitations and Future Enhancements:**

**Current Limitations:**
1. No pagination (displays all nodes)
2. No filtering by status or pattern
3. No detailed node information view
4. No historical data or trends
5. Terminal size not dynamically adjusted

**Potential Enhancements:**
1. Add filtering options (by status, pattern, arch)
2. Implement pagination for large node lists
3. Add detailed view mode (press 'd' for details)
4. Track heartbeat history and show trends
5. Add sorting options (by name, type, arch)
6. Implement search/filter functionality
7. Add export to CSV/JSON file
8. Show node resource usage (if available)
9. Add alerts for nodes going offline
10. Implement dashboard mode with multiple views

**Testing Considerations:**

1. **Unit Tests Needed:**
   - `timestamp_to_seconds()` function
   - `format_time_ago()` function
   - `get_heartbeat_color()` function
   - Sorting logic
   - Status categorization

2. **Integration Tests Needed:**
   - API call with valid credentials
   - API call with invalid credentials
   - Handling empty node list
   - Handling malformed API responses
   - Terminal control (cursor hide/show)
   - Signal handling (Ctrl+C)

3. **Manual Tests Needed:**
   - Different terminal sizes
   - Different refresh intervals
   - Nodes in different states (active/stale/inactive)
   - Long-running monitoring sessions
   - Keyboard controls (q, r)
   - Color output vs no-color mode

**Security Considerations:**

1. **Credential Handling:**
   - Never displays passwords in output
   - Uses masked authentication in verbose mode
   - Credentials loaded from secure .env files
   - No credentials in process arguments

2. **API Communication:**
   - Uses HTTPS for production environments
   - Supports self-signed certificates (common in OH deployments)
   - No credential caching or storage
   - Clean exit on authentication failures

**Comparison with Similar Tools:**

**vs. `top` command:**
- Similar: Real-time updates, sorted display, interactive controls
- Different: Monitors distributed nodes, not local processes

**vs. `watch hzn exchange node list`:**
- Similar: Periodic updates of node list
- Different: Sorted by activity, color-coded, summary stats, cleaner display

**vs. `list-a-user-nodes.sh`:**
- Similar: Uses same API endpoint, same authentication
- Different: Continuous monitoring vs one-time listing, sorted by heartbeat

This implementation provides a powerful, user-friendly tool for monitoring Open Horizon node health in real-time, with careful attention to cross-platform compatibility, error handling, and user experience.

