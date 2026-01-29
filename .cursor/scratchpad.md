# Scratchpad - hzn-utils Project

## Current Project Status

The hzn-utils project is a well-structured collection of bash scripts for managing Open Horizon instances. Recent improvements include:

- ✅ **Error Handling Enhancement** - All scripts now use `set -euo pipefail` and trap handlers
- ✅ **Testing Infrastructure** - Complete test suite with bats-core, unit tests, integration tests, and CI/CD
- ✅ **Documentation Cleanup** - Removed redundant files, created ROADMAP.md

## Active Roadmap Priorities

See [ROADMAP.md](../ROADMAP.md) for complete details.

### High Priority
1. **Create shared library** (Item #1)
   - Reduce code duplication across scripts
   - Centralize common functions (env file selection, credential parsing, print functions)
   - Target: `lib/common.sh` expansion

### Medium Priority
2. **Add input validation** (Item #3)
   - Validate user inputs and API responses
   - Add validation functions for URLs, org IDs, etc.

3. **Security enhancements** (Item #9)
   - Credential encryption option
   - Credential expiry warnings
   - Audit logging for sensitive operations

4. **Configuration management** (Item #5)
   - Centralized configuration file support
   - Default values for timeouts, retry counts, etc.

### Low Priority
- Logging capability (Item #6)
- Performance optimization (Item #7)
- Documentation improvements (Item #8)
- CI/CD enhancements (Item #10)
- Additional scripts (Item #11)
- Code quality tools (Item #12)

## Completed Work Archive

### Issue #5: Add list-user.sh script (COMPLETED)
**Status:** ✅ Merged
- **Issue:** https://github.com/joewxboy/hzn-utils/issues/5
- **PR:** https://github.com/joewxboy/hzn-utils/pull/6
- **Commit:** `9274d72`

**Scripts created:**
- `list-user.sh` - CLI-based (requires Exchange 2.124.0+)
- `list-a-user.sh` - API-based (works with any Exchange version)

**Key features:**
- Display current authenticated user information
- Show admin privileges (org admin, hub admin)
- Multiple output modes (simple, verbose, JSON-only)
- Comprehensive error handling and troubleshooting

## Git Workflow Pattern

When performing new work in this repository:

1. **Check for open issues first** - Ask the user if unsure whether to use an existing issue
2. **If no open issue exists:**
   - Open a new issue describing the work
   - Label it `bug` or `enhancement` depending on the type of work
   - Create the label if it doesn't exist in the repository
3. **Remember the issue number** and create a new branch with the pattern `issue-#` (e.g., `issue-3`)
4. **Before committing changes:**
   - **Always update `README.md` and `AGENTS.md`** to document any new scripts or features
5. **When committing changes:**
   - Use the `-s` sign-off flag
   - Prefix the commit title with `Issue #: ` (e.g., `Issue #3: Fix false failure report`)
6. **When opening the PR:**
   - Use the same `Issue #: ` prefix in the PR title
   - Link to the issue in the PR description

## Development Notes

### Project Structure
```
hzn-utils/
├── lib/common.sh              # Shared library (needs expansion - Item #1)
├── tests/                     # Test suite (bats-core)
│   ├── unit/                  # Unit tests
│   ├── integration/           # Integration tests
│   └── fixtures/              # Test data
├── *.sh                       # Utility scripts
└── *.env                      # Credential files (not in git)
```

### Key Design Principles
1. **Three operation modes:**
   - Default: Interactive exploration with prompts
   - Verbose: Exhaustive details for troubleshooting
   - Minimal: Machine-readable JSON for automation

2. **Minimal dependencies:**
   - Bash 3.2+ compatibility (macOS support)
   - curl and jq (optional but recommended)
   - No hzn CLI required for API scripts

3. **Security first:**
   - Never commit `.env` files
   - Support multiple credential files
   - Clear error messages for auth failures

### Testing
- Run all tests: `./run-tests.sh`
- Unit tests only: `./run-tests.sh --unit`
- Integration tests: `./run-tests.sh --integration`
- Static analysis: `./run-tests.sh --shellcheck`

## Next Steps

Based on ROADMAP.md priorities, the next major improvement should be:

**Item #1: Create shared library** (HIGH PRIORITY)
- Expand `lib/common.sh` with common functions
- Reduce code duplication across all scripts
- Improve maintainability and consistency

This will significantly reduce maintenance burden and make future improvements easier to implement.