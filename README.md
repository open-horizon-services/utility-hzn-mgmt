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
├── can-i-list-users.sh        # Permission verification script
├── can-i-list-orgs.sh         # Organization permission verification
├── can-i-list-services.sh     # Service permission verification
├── can-i-do-anything.sh       # Comprehensive permission checker
├── list-a-org-nodes.sh        # API-based organization node listing
├── list-a-user-nodes.sh       # API-based user node listing
├── list-a-user-services.sh    # API-based user service listing
├── list-a-user-deployment.sh  # API-based user deployment policy listing
├── monitor-nodes.sh           # Real-time node monitoring utility
├── test-credentials.sh        # Credential validation tool
├── test-hzn.sh                # CLI installation test
├── test-blessed-samples.sh    # Validate blessedSamples.txt files
└── *.env                      # Credential files (not in git)
```

## Available Scripts

This repository contains several utility scripts for managing Open Horizon instances:

### Interactive Scripts (using hzn CLI)
- **`list-orgs.sh`** - Interactive script to list organizations and optionally view users
- **`list-users.sh`** - Interactive script to list users in an organization
- **`list-user.sh`** - Display current authenticated user info and validate credentials
- **`test-credentials.sh`** - Test and validate your Open Horizon credentials

### Permission Scripts
- **`can-i-list-users.sh`** - Check if user can list users in an organization
- **`can-i-list-orgs.sh`** - Check if user can list organizations
- **`can-i-list-services.sh`** - Check if user can list services at different levels
- **`can-i-do-anything.sh`** - Comprehensive checker showing all runnable scripts

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
- **`test-blessed-samples.sh`** - Validate blessedSamples.txt files used by exchangePublish.sh

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

### can-i-do-anything.sh (Comprehensive Permission Checker)

Determines which Open Horizon admin utility scripts you can run based on your authenticated role and permissions.

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

**Features:**
- Analyzes user role and permissions
- Tests access to organizations, users, and services
- Groups scripts by category (org, user, node, service, deployment, test)
- Shows which scripts are runnable based on current permissions
- Three output modes for different use cases

**Output Modes:**
1. **Interactive** (Default): Numbered list grouped by category with brief descriptions
2. **JSON**: Machine-readable structured output for automation
3. **Verbose**: Detailed descriptions with permission requirements and explanations

**Example Output (Interactive):**
```
Available Scripts for User: myuser (Organization: myorg)

Your Role: Org Admin

Organization Management (3 scripts)
  1. list-orgs.sh              - List organizations interactively
  2. list-a-orgs.sh            - List organizations via API
  3. can-i-list-orgs.sh        - Check organization listing permissions

User Management (5 scripts)
  4. list-users.sh             - List users in organization
  ...

Total: 16 scripts available
```

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

# Query a different organization
./list-a-users.sh -o target-org

# JSON output only (for piping/automation)
./list-a-users.sh --json mycreds.env

# Verbose mode with full JSON details
./list-a-users.sh --verbose
```

**Options:**
- `-o, --org ORG` - Target organization to query (default: auth org from HZN_ORG_ID)
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
### test-blessed-samples.sh (Blessed Samples Validator)

Validates `blessedSamples.txt` files used by the Open Horizon `exchangePublish.sh` script. Checks file format and verifies GitHub repository accessibility using the GitHub API.

**Usage:**
```bash
# Test default file (./blessedSamples.txt)
./test-blessed-samples.sh

# Test specific file
./test-blessed-samples.sh tools/blessedSamples.txt

# Verbose output with detailed checks
./test-blessed-samples.sh --verbose tools/blessedSamples.txt

# JSON output for CI/CD
./test-blessed-samples.sh --json tools/blessedSamples.txt

# Skip network checks (format validation only)
./test-blessed-samples.sh --skip-network tools/blessedSamples.txt

# With GitHub token for higher rate limits
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
./test-blessed-samples.sh tools/blessedSamples.txt
```

**Options:**
- `-v, --verbose` - Show detailed validation output with API responses
- `-j, --json` - Output JSON only (for scripting/automation)
- `-b, --branch BRANCH` - Branch to check (default: master)
- `-s, --skip-network` - Skip network checks (validate format only)
- `-h, --help` - Show help message

**Environment Variables:**
- `GITHUB_TOKEN` - Optional GitHub personal access token for authenticated API calls (increases rate limit from 60 to 5000 requests/hour)

**File Format:**
The `blessedSamples.txt` file supports two formats:
- **Relative paths**: `edge/services/helloworld` (always refers to `https://github.com/open-horizon/examples/`)
- **Absolute URLs**: `https://github.com/open-horizon-services/web-helloworld-python`
- Blank lines and comments (lines starting with `#`) are ignored

**Validation Checks:**
1. **Format Validation**: Checks syntax of each entry
2. **Type Detection**: Identifies relative vs absolute URLs
3. **Format Consistency**: Warns if file contains mixed formats
4. **GitHub API Verification**: Confirms repositories/paths exist (unless `--skip-network`)

**Output Modes:**

**1. Interactive (Default):**
```
═══════════════════════════════════════════════════════════
  Validating Blessed Samples File
═══════════════════════════════════════════════════════════

File: tools/blessedSamples.txt
Format: relative
Base Repository: https://github.com/open-horizon/examples (for relative paths)
Branch: master

ℹ Validating entries...

✓ Line 1: edge/services/cpu_percent
✓ Line 2: edge/services/gps
✗ Line 3: edge/services/invalid_path
  Error: Path not found in repository (HTTP 404)

═══════════════════════════════════════════════════════════
  Validation Summary
═══════════════════════════════════════════════════════════

Total Entries: 3
Valid: 2
Invalid: 1
Warnings: 0

Status: FAILED (1 error(s) found)
```

**2. Verbose Mode (`--verbose`):**
Shows detailed information for each entry including:
- Entry type (relative/absolute)
- Full GitHub URL being checked
- HTTP response codes
- API rate limit information

**3. JSON Mode (`--json`):**
```json
{
  "file": "tools/blessedSamples.txt",
  "format": "relative",
  "base_repository": "https://github.com/open-horizon/examples",
  "branch": "master",
  "skip_network": false,
  "github_token_set": true,
  "total_entries": 3,
  "valid_count": 2,
  "invalid_count": 1,
  "warning_count": 0,
  "status": "failed",
  "entries": [
    {
      "line": 1,
      "content": "edge/services/cpu_percent",
      "type": "relative",
      "status": "valid",
      "message": "Path exists in repository",
      "http_code": 200
    }
  ]
}
```

**Exit Codes:**
- `0` - All validations passed
- `1` - Validation failures found
- `2` - Script error (invalid arguments, missing file, missing dependencies)

**Use Cases:**
- **Pre-commit validation**: Verify blessedSamples.txt before committing changes
- **CI/CD integration**: Automated validation in GitHub Actions or other CI systems
- **Local development**: Quick check before running exchangePublish.sh
- **Troubleshooting**: Identify broken repository links or invalid paths

**GitHub API Rate Limits:**
- **Unauthenticated**: 60 requests/hour
- **Authenticated** (with `GITHUB_TOKEN`): 5000 requests/hour
- The script displays current rate limit status in verbose mode

**Example Workflow:**
```bash
# 1. Validate format only (fast, no network)
./test-blessed-samples.sh --skip-network tools/blessedSamples.txt

# 2. Full validation with GitHub API
export GITHUB_TOKEN=your_token_here
./test-blessed-samples.sh tools/blessedSamples.txt

# 3. Use in CI/CD pipeline
./test-blessed-samples.sh --json tools/blessedSamples.txt | jq '.status'
```

- `2`: Error (invalid arguments, API error, authentication failure)

## Environment File Configuration

All scripts use `.env` files for credential management. Create one or more `.env` files with the following format:

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
