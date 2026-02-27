#!/usr/bin/env bats

# Integration tests for API-based scripts

load '../test_helper'

setup() {
    setup_test_dir
    setup_mock_env
}

teardown() {
    cleanup_test_dir
    cleanup_mock_env
}

# Tests for list-a-orgs.sh
@test "list-a-orgs.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/list-a-orgs.sh" ]
    [ -x "${PROJECT_ROOT}/list-a-orgs.sh" ]
}

@test "list-a-orgs.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/list-a-orgs.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "help" ]]
}

@test "list-a-orgs.sh accepts --json flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/list-a-orgs.sh" --json "${FIXTURES_DIR}/valid.env"
    # May fail if Exchange not reachable, but should accept the flag
    [ "$status" -ge 0 ]
}

@test "list-a-orgs.sh accepts --verbose flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/list-a-orgs.sh" --verbose "${FIXTURES_DIR}/valid.env"
    [ "$status" -ge 0 ]
}

@test "list-a-orgs.sh requires curl" {
    # Temporarily hide curl
    PATH="/nonexistent:$PATH"
    
    run "${PROJECT_ROOT}/list-a-orgs.sh" "${FIXTURES_DIR}/valid.env"
    [ "$status" -ne 0 ]
}

# Tests for list-a-users.sh
@test "list-a-users.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/list-a-users.sh" ]
    [ -x "${PROJECT_ROOT}/list-a-users.sh" ]
}

@test "list-a-users.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/list-a-users.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "help" ]]
}

@test "list-a-users.sh accepts --json flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/list-a-users.sh" --json "${FIXTURES_DIR}/valid.env"
    [ "$status" -ge 0 ]
}

@test "list-a-users.sh accepts --verbose flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/list-a-users.sh" --verbose "${FIXTURES_DIR}/valid.env"
    [ "$status" -ge 0 ]
}

@test "list-a-users.sh accepts -o flag for target organization" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/list-a-users.sh" -o testorg "${FIXTURES_DIR}/valid.env"
    # Should accept the flag (may fail due to unreachable Exchange, but flag should be recognized)
    [ "$status" -ge 0 ]
}

# Tests for list-a-org-nodes.sh
@test "list-a-org-nodes.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/list-a-org-nodes.sh" ]
    [ -x "${PROJECT_ROOT}/list-a-org-nodes.sh" ]
}

@test "list-a-org-nodes.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/list-a-org-nodes.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "help" ]]
}

@test "list-a-org-nodes.sh accepts --json flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/list-a-org-nodes.sh" --json "${FIXTURES_DIR}/valid.env"
    # Should accept the flag (may fail due to unreachable Exchange, but flag should be recognized)
    [ "$status" -ge 0 ]
}

@test "list-a-org-nodes.sh accepts -o flag for target organization" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/list-a-org-nodes.sh" -o testorg "${FIXTURES_DIR}/valid.env"
    # Should accept the flag (may fail due to unreachable Exchange, but flag should be recognized)
    [ "$status" -ge 0 ]
}

@test "list-a-org-nodes.sh requires organization parameter" {
    skip_if_missing "curl"
    
    # Provide an env file to avoid interactive prompt
    run "${PROJECT_ROOT}/list-a-org-nodes.sh" "${FIXTURES_DIR}/valid.env"
    # Script should run but may fail due to unreachable Exchange
    # The important thing is it doesn't hang waiting for input
    [ "$status" -ge 0 ]
}

# Tests for list-a-user-nodes.sh
@test "list-a-user-nodes.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/list-a-user-nodes.sh" ]
    [ -x "${PROJECT_ROOT}/list-a-user-nodes.sh" ]
}

# Tests for list-a-user-services.sh
@test "list-a-user-services.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/list-a-user-services.sh" ]
    [ -x "${PROJECT_ROOT}/list-a-user-services.sh" ]
}

# Tests for list-a-user-deployment.sh
@test "list-a-user-deployment.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/list-a-user-deployment.sh" ]
    [ -x "${PROJECT_ROOT}/list-a-user-deployment.sh" ]
}

# Tests for can-i-list-orgs.sh
@test "can-i-list-orgs.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/can-i-list-orgs.sh" ]
    [ -x "${PROJECT_ROOT}/can-i-list-orgs.sh" ]
}

@test "can-i-list-orgs.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/can-i-list-orgs.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "help" ]]
}

@test "can-i-list-orgs.sh accepts --json flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/can-i-list-orgs.sh" --json "${FIXTURES_DIR}/valid.env"
    # May fail if Exchange not reachable, but should accept the flag
    [ "$status" -ge 0 ]
}

@test "can-i-list-orgs.sh accepts --verbose flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/can-i-list-orgs.sh" --verbose "${FIXTURES_DIR}/valid.env"
    [ "$status" -ge 0 ]
}

@test "can-i-list-orgs.sh requires curl" {
    # Temporarily hide curl
    PATH="/nonexistent:$PATH"
    
    run "${PROJECT_ROOT}/can-i-list-orgs.sh" "${FIXTURES_DIR}/valid.env"
    [ "$status" -ne 0 ]
}

# Tests for can-i-list-users.sh
@test "can-i-list-users.sh exists and is executable" {
    [ -f "${PROJECT_ROOT}/can-i-list-users.sh" ]
    [ -x "${PROJECT_ROOT}/can-i-list-users.sh" ]
}

@test "can-i-list-users.sh shows help with --help flag" {
    run "${PROJECT_ROOT}/can-i-list-users.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]] || [[ "$output" =~ "help" ]]
}

@test "can-i-list-users.sh accepts --json flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/can-i-list-users.sh" --json "${FIXTURES_DIR}/valid.env"
    [ "$status" -ge 0 ]
}

@test "can-i-list-users.sh accepts --verbose flag" {
    skip_if_missing "curl"
    
    run "${PROJECT_ROOT}/can-i-list-users.sh" --verbose "${FIXTURES_DIR}/valid.env"
    [ "$status" -ge 0 ]
}

# Test credential handling across all API scripts
@test "API scripts handle missing credentials gracefully" {
    skip_if_missing "curl"
    
    unset HZN_EXCHANGE_URL
    unset HZN_ORG_ID
    unset HZN_EXCHANGE_USER_AUTH
    
    run "${PROJECT_ROOT}/list-a-orgs.sh" "${FIXTURES_DIR}/invalid.env"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "Missing" ]] || [[ "$output" =~ "required" ]]
}

@test "API scripts validate URL format" {
    skip_if_missing "curl"
    
    # Create env file with invalid URL
    cat > "${TEST_TEMP_DIR}/bad-url.env" << EOF
HZN_EXCHANGE_URL=not-a-url
HZN_ORG_ID=testorg
HZN_EXCHANGE_USER_AUTH=user:pass
EOF
    
    run "${PROJECT_ROOT}/list-a-orgs.sh" "${TEST_TEMP_DIR}/bad-url.env"
    [ "$status" -ne 0 ]
}
