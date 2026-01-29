# Scratchpad - can-i-list-users.sh

## Background and Motivation

The user wants a new script `can-i-list-users.sh` that serves two purposes:

1. **Predictive Check**: Determine whether the authenticated user *should* be able to list users based on their known permissions (admin status, hubAdmin status)
2. **Actual Verification**: Confirm with an actual API call whether the user *can* list users

This is useful for:
- Debugging permission issues before running other scripts
- Understanding why a user might not have access
- Providing clear feedback about expected vs actual permissions

## Key Challenges and Analysis

### Challenge 1: Understanding Open Horizon Permission Model

Based on code analysis, the user API returns these permission-related fields:
- `admin` (boolean): Organization admin - has full access within the org
- `hubAdmin` (boolean): Hub-level admin - has elevated cross-org permissions

**Permission rules for listing users** (need to verify):
- Org admins (`admin: true`) should be able to list users in their own organization
- Hub admins (`hubAdmin: true`) should be able to list users in any organization
- Regular users may only be able to see their own user info (not list all users)

### Challenge 2: Two-Phase Verification Approach

**Phase 1 - Predictive Check**:
1. Fetch the current user's info via `/orgs/{org}/users/{username}`
2. Parse `admin` and `hubAdmin` fields
3. Determine expected permission based on:
   - If querying same org as auth org AND user is admin → SHOULD be able
   - If user is hubAdmin → SHOULD be able (any org)
   - Otherwise → SHOULD NOT be able

**Phase 2 - Actual Verification**:
1. Attempt to list users via `/orgs/{target_org}/users`
2. Check HTTP response code:
   - 200 → CAN list users
   - 401/403 → CANNOT list users
3. Compare actual result with predicted result

### Challenge 3: Target Organization Handling

The script should support:
- Default: Use `HZN_ORG_ID` from credentials (same org)
- Optional: Specify a different organization to check cross-org permissions

## High-level Task Breakdown

### Task 1: Create basic script structure
- [ ] Create `can-i-list-users.sh` with standard boilerplate
- [ ] Source `lib/common.sh` for shared functions
- [ ] Add command-line argument parsing (target org, verbose, json-only, help)
- [ ] Add .env file selection and credential loading
- **Success Criteria**: Script runs, loads credentials, displays help with `-h`

### Task 2: Implement Phase 1 - Predictive Permission Check
- [ ] Fetch current user info via API (`/orgs/{org}/users/{username}`)
- [ ] Parse `admin` and `hubAdmin` fields
- [ ] Implement permission prediction logic:
  - Same org + admin = SHOULD be able
  - hubAdmin = SHOULD be able (any org)
  - Otherwise = SHOULD NOT be able
- [ ] Display predicted permission with explanation
- **Success Criteria**: Script correctly predicts permission based on user's admin status

### Task 3: Implement Phase 2 - Actual Permission Verification
- [ ] Attempt to list users via API (`/orgs/{target_org}/users`)
- [ ] Capture HTTP status code (200 = success, 401/403 = denied)
- [ ] Display actual result (CAN or CANNOT)
- **Success Criteria**: Script correctly reports actual API result

### Task 4: Compare and Report Results
- [ ] Compare predicted vs actual results
- [ ] Display clear summary:
  - ✓ Expected: YES, Actual: YES → "Permission confirmed"
  - ✗ Expected: YES, Actual: NO → "Unexpected denial - investigate"
  - ✓ Expected: NO, Actual: NO → "Permission correctly denied"
  - ! Expected: NO, Actual: YES → "Unexpected access - review permissions"
- [ ] Provide troubleshooting tips for mismatches
- **Success Criteria**: Script provides clear, actionable output

### Task 5: Add output modes and polish
- [ ] Implement `--json` mode for machine-readable output
- [ ] Implement `--verbose` mode for detailed debugging
- [ ] Add proper exit codes (0 = can list, 1 = cannot list, 2 = error)
- [ ] Update AGENTS.md with new script documentation
- **Success Criteria**: All output modes work, documentation updated

### Task 6: Testing
- [ ] Test with org admin user (same org) - should succeed
- [ ] Test with regular user (same org) - should fail
- [ ] Test with hubAdmin (different org) - should succeed
- [ ] Test with invalid credentials - should error gracefully
- **Success Criteria**: All test scenarios produce expected results

## Project Status Board

- [x] Task 1: Create basic script structure
- [x] Task 2: Implement Phase 1 - Predictive Permission Check
- [x] Task 3: Implement Phase 2 - Actual Permission Verification
- [x] Task 4: Compare and Report Results
- [x] Task 5: Add output modes and polish
- [ ] Task 6: User Testing
- [ ] Task 7: Update AGENTS.md and README.md documentation
- [ ] Task 8: Commit and create PR

## Executor's Feedback or Assistance Requests

**Status**: Script `can-i-list-users.sh` is ready for user testing.

The script has been created with all planned features:
- Two-phase verification (predictive + actual)
- `--json` mode for machine-readable output
- `--verbose` mode for debugging
- `-o/--org` option for cross-org permission checking
- Proper exit codes (0=can, 1=cannot, 2=error)
- Color-coded output with clear messaging
- Troubleshooting tips for permission mismatches

**Awaiting**: User testing before updating documentation and committing.

## Lessons

- All curl commands in this repo should use `-k` flag for self-signed certificate compatibility
- Use `# shellcheck disable=SCXXXX` with explanatory comments when intentionally triggering warnings
- Always create GitHub issue before making changes, use branch naming `issue-#`
- Commits must use `-s` sign-off flag and message prefix `Issue #: `
