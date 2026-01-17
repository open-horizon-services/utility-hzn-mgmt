# Test Fixtures

This directory contains test fixture files used by the test suite.

## Environment Files

These `.env` files are used to test credential loading and validation:

- **`valid.env`** - A complete, valid environment configuration with all required variables
- **`invalid.env`** - An invalid configuration missing all required variables
- **`partial.env`** - A partial configuration with only some required variables
- **`with-org-prefix.env`** - A valid configuration with organization prefix in the auth string

## Important Notes

- These files contain **test credentials only** and are safe to commit to version control
- They are explicitly allowed in `.gitignore` via `!tests/fixtures/*.env`
- Do NOT use these credentials for actual Open Horizon instances
- Real credential files (outside this directory) are still excluded by `.gitignore`

## Usage

These fixtures are automatically used by the BATS test suite. They should not be modified unless you're updating the test cases that depend on them.