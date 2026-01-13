# Open Horizon Admin Utilities

The purpose of this repo is to collect scripts that will automate creation, listing, and removing of organizations, users, services, and nodes in an Open Horizon instance.

## Available Scripts

This repository contains several utility scripts for managing Open Horizon instances:

### Interactive Scripts (using hzn CLI)
- **`list-orgs.sh`** - Interactive script to list organizations and optionally view users
- **`list-users.sh`** - Interactive script to list users in an organization
- **`test-credentials.sh`** - Test and validate your Open Horizon credentials

### API-Based Scripts (using REST API)
- **`list-a-orgs.sh`** - List organizations using REST API with multiple output modes
- **`list-a-users.sh`** - List users using REST API with multiple output modes

### Testing Scripts
- **`test-hzn.sh`** - Test Open Horizon CLI installation and configuration

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

### Open Horizon Operations

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

## Build, Test, and Lint Commands

### Python Environment Setup
```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # On Unix/macOS
# or
venv\Scripts\activate     # On Windows

# Install dependencies
pip install -r requirements.txt

# Install development dependencies
pip install -r requirements-dev.txt
```

### Testing
```bash
# Run all tests
python -m pytest

# Run tests with coverage
python -m pytest --cov=.

# Run a single test file
python -m pytest tests/test_specific_file.py

# Run a single test function
python -m pytest tests/test_file.py::TestClass::test_function

# Run tests in verbose mode
python -m pytest -v

# Run tests with output capturing disabled
python -m pytest -s
```

### Linting and Code Quality
```bash
# Run flake8 linter
flake8 .

# Run black code formatter
black .

# Run isort import sorter
isort .

# Run mypy type checker
mypy .

# Run all quality checks together
pre-commit run --all-files
```

### Build and Package
```bash
# Build distribution packages
python -m build

# Install in development mode
pip install -e .

# Create wheel
python setup.py bdist_wheel
```

## Code Style Guidelines

### Python Style
- Follow PEP 8 style guidelines
- Use Black for code formatting with 88 character line length
- Use isort for import sorting with 4-space indentation
- Write docstrings for all public functions, classes, and modules using Google style

### Imports
```python
# Standard library imports first
import os
import sys
from pathlib import Path

# Third-party imports second
import requests
import click

# Local imports last
from . import utils
from .api_client import APIClient
```

### Naming Conventions
- **Functions**: `snake_case` (e.g., `get_user_info`, `create_organization`)
- **Variables**: `snake_case` (e.g., `user_data`, `org_name`)
- **Constants**: `UPPER_SNAKE_CASE` (e.g., `DEFAULT_TIMEOUT`, `API_BASE_URL`)
- **Classes**: `PascalCase` (e.g., `OrganizationManager`, `UserAPI`)
- **Modules**: `snake_case` (e.g., `user_utils.py`, `api_client.py`)

### Type Hints
```python
from typing import Dict, List, Optional, Any
import requests

def get_user(user_id: str) -> Dict[str, Any]:
    """Get user information by ID."""
    response = requests.get(f"/users/{user_id}")
    return response.json()

def list_users(limit: Optional[int] = None) -> List[Dict[str, Any]]:
    """List users with optional limit."""
    # Implementation here
    pass
```

### Error Handling
```python
import logging
from typing import Optional

logger = logging.getLogger(__name__)

def safe_api_call(url: str, timeout: int = 30) -> Optional[dict]:
    """Make API call with proper error handling."""
    try:
        response = requests.get(url, timeout=timeout)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.Timeout:
        logger.error(f"Timeout calling {url}")
        return None
    except requests.exceptions.HTTPError as e:
        logger.error(f"HTTP error calling {url}: {e}")
        return None
    except requests.exceptions.RequestException as e:
        logger.error(f"Request error calling {url}: {e}")
        return None
```

### Logging
```python
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def process_data(data: dict) -> None:
    """Process data with appropriate logging."""
    logger.info("Starting data processing")
    try:
        # Processing logic
        logger.debug(f"Processing {len(data)} items")
        # ... process data ...
        logger.info("Data processing completed successfully")
    except Exception as e:
        logger.error(f"Error processing data: {e}")
        raise
```

### Command Line Interfaces
Use Click for CLI applications:
```python
import click

@click.group()
@click.option('--api-url', default='https://api.example.com', help='API base URL')
@click.option('--verbose', '-v', is_flag=True, help='Enable verbose output')
@click.pass_context
def cli(ctx, api_url, verbose):
    """Open Horizon Admin CLI."""
    ctx.ensure_object(dict)
    ctx.obj['api_url'] = api_url
    ctx.obj['verbose'] = verbose

@cli.command()
@click.argument('org_name')
@click.pass_context
def create_org(ctx, org_name):
    """Create a new organization."""
    api_url = ctx.obj['api_url']
    verbose = ctx.obj['verbose']

    if verbose:
        click.echo(f"Creating organization: {org_name}")

    # Implementation here
    click.echo(f"Organization '{org_name}' created successfully")
```

### Configuration Management
```python
import os
from pathlib import Path
from typing import Dict, Any
import yaml

class Config:
    """Configuration management for Open Horizon admin tools."""

    def __init__(self, config_file: Optional[str] = None):
        self.config_file = config_file or self._default_config_path()
        self._config = self._load_config()

    def _default_config_path(self) -> str:
        """Get default configuration file path."""
        return os.path.expanduser("~/.openhorizon/config.yaml")

    def _load_config(self) -> Dict[str, Any]:
        """Load configuration from file."""
        if not Path(self.config_file).exists():
            return self._default_config()

        with open(self.config_file, 'r') as f:
            return yaml.safe_load(f) or {}

    def _default_config(self) -> Dict[str, Any]:
        """Return default configuration."""
        return {
            'api_url': 'https://api.openhorizon.io',
            'timeout': 30,
            'retries': 3
        }

    def get(self, key: str, default: Any = None) -> Any:
        """Get configuration value."""
        return self._config.get(key, default)
```

### API Client Pattern
```python
from typing import Dict, Any, Optional
import requests
from .config import Config

class OpenHorizonAPI:
    """Open Horizon API client."""

    def __init__(self, config: Optional[Config] = None):
        self.config = config or Config()
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {self.config.get("api_key")}',
            'Content-Type': 'application/json'
        })

    def _make_request(self, method: str, endpoint: str, **kwargs) -> dict:
        """Make HTTP request with error handling."""
        url = f"{self.config.get('api_url')}{endpoint}"
        timeout = self.config.get('timeout', 30)

        try:
            response = self.session.request(method, url, timeout=timeout, **kwargs)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            raise OpenHorizonAPIError(f"API request failed: {e}")

    def list_organizations(self) -> Dict[str, Any]:
        """List all organizations."""
        return self._make_request('GET', '/orgs')

    def create_organization(self, org_data: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new organization."""
        return self._make_request('POST', '/orgs', json=org_data)

class OpenHorizonAPIError(Exception):
    """Open Horizon API error."""
    pass
```

### Testing Guidelines
```python
import pytest
from unittest.mock import Mock, patch
from .api_client import OpenHorizonAPI

class TestOpenHorizonAPI:
    """Test Open Horizon API client."""

    @pytest.fixture
    def api_client(self):
        """Create API client for testing."""
        config = Mock()
        config.get.return_value = 'https://api.test.com'
        return OpenHorizonAPI(config)

    def test_list_organizations(self, api_client):
        """Test listing organizations."""
        with patch.object(api_client.session, 'request') as mock_request:
            mock_response = Mock()
            mock_response.json.return_value = {'orgs': []}
            mock_request.return_value = mock_response

            result = api_client.list_organizations()
            assert result == {'orgs': []}
            mock_request.assert_called_once()

    def test_create_organization(self, api_client):
        """Test creating organization."""
        org_data = {'name': 'test-org', 'description': 'Test organization'}

        with patch.object(api_client.session, 'request') as mock_request:
            mock_response = Mock()
            mock_response.json.return_value = {'id': '123', **org_data}
            mock_request.return_value = mock_response

            result = api_client.create_organization(org_data)
            assert result['name'] == 'test-org'
            mock_request.assert_called_with(
                'POST', 'https://api.test.com/orgs',
                json=org_data, timeout=30
            )
```

### File Structure
```
openhorizon-admin/
├── openhorizon/
│   ├── __init__.py
│   ├── api.py              # Main API client
│   ├── cli.py              # Command line interface
│   ├── config.py           # Configuration management
│   └── utils.py            # Utility functions
├── tests/
│   ├── __init__.py
│   ├── test_api.py
│   └── test_cli.py
├── requirements.txt
├── requirements-dev.txt
├── setup.py
├── pyproject.toml
└── README.md
```

### Security Best Practices
- Never log sensitive information (API keys, passwords)
- Use environment variables for secrets
- Validate all user inputs
- Use HTTPS for all API calls
- Implement proper authentication and authorization
- Handle secrets securely (no hardcoded credentials)

### Git Workflow
- Use descriptive commit messages
- Keep commits focused and atomic
- Use feature branches for new functionality
- Write meaningful pull request descriptions
- Run tests and linting before committing

This guide ensures consistent, maintainable, and secure code across all Open Horizon admin utilities.