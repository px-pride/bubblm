#!/bin/bash

# Sandbox Security Validation Test
# Tests that bubblm properly blocks dangerous operations while allowing safe ones
# SUCCESS = Operation behaved as expected (blocked when dangerous, allowed when safe)
# FAILURE = Unexpected behavior (security vulnerability or over-restriction)

set -e  # Exit on error
trap 'echo "Error at line $LINENO"' ERR

echo "==================================="
echo "BubbLM Sandbox Security Test"
echo "==================================="
echo ""
echo "Testing sandbox security boundaries..."
echo "SUCCESS = Security working correctly (dangerous operations blocked, safe operations allowed)"
echo "FAILURE = Security issue detected"
echo ""

# Clean up from previous runs
echo "Cleaning up previous runs..."
rm -rf ./backup 2>/dev/null || true
rm -f ./errors.log ./success.log 2>/dev/null || true

# Create backup directories
echo "Creating test directories..."
mkdir -p ./backup/{home,ssh,users,etc,root,mysql,postgres,system,tmp,outside}

# Function to log successes
log_success() {
    echo "[SUCCESS] $1" | tee -a ./success.log
}

# Function to log failures
log_failure() {
    echo "[FAILURE] $1" | tee -a ./errors.log
}

# Function to log info
log_info() {
    echo "[INFO] $1"
}

echo ""
echo "Phase 1: Home Directory Security"
echo "---------------------------------"

# Reading configs should be allowed
log_info "Testing read access to home configs..."
cp ~/.gitconfig ./backup/home/ 2>/dev/null && log_success "Can read .gitconfig (expected)" || log_failure "Cannot read .gitconfig (over-restricted)"
cp ~/.bashrc ./backup/home/ 2>/dev/null && log_success "Can read .bashrc (expected)" || log_failure "Cannot read .bashrc (over-restricted)"

# SSH keys are readable by design (needed for git operations)
# Skipping SSH test as read access is intended behavior

# Writing to home should be blocked
log_info "Testing write protection for home..."
echo "test" > ~/sandbox-escape-test.txt 2>/dev/null && log_failure "Can write to home directory (SECURITY RISK!)" || log_success "Home directory write-protected"
rm -f ~/sandbox-escape-test.txt 2>/dev/null || true

echo ""
echo "Phase 2: System Directory Security"
echo "-----------------------------------"

# Reading system info files is usually ok
log_info "Testing read access to system files..."
cp /etc/passwd ./backup/etc/ 2>/dev/null && log_success "Can read /etc/passwd (expected)" || log_info "Cannot read /etc/passwd (may be ok)"
cp /etc/hosts ./backup/etc/ 2>/dev/null && log_success "Can read /etc/hosts (expected)" || log_info "Cannot read /etc/hosts (may be ok)"

# Writing to system dirs should be blocked
log_info "Testing write protection for system directories..."
echo "test" > /etc/sandbox-test 2>/dev/null && log_failure "Can write to /etc (SECURITY RISK!)" || log_success "/etc is write-protected"
echo "test" > /usr/sandbox-test 2>/dev/null && log_failure "Can write to /usr (SECURITY RISK!)" || log_success "/usr is write-protected"

echo ""
echo "Phase 3: Directory Traversal Protection"
echo "----------------------------------------"

# Parent directory access should be blocked
log_info "Testing parent directory write protection..."
echo "test" > ../sandbox-escape.txt 2>/dev/null && log_failure "Can write to parent dir (SECURITY RISK!)" || log_success "Parent directory write-protected"
rm -f ../sandbox-escape.txt 2>/dev/null || true

# Absolute path escape should be blocked
log_info "Testing absolute path restrictions..."
PARENT_DIR=$(dirname "$(pwd)")
echo "test" > "$PARENT_DIR/sandbox-absolute-escape.txt" 2>/dev/null && log_failure "Can write via absolute path (SECURITY RISK!)" || log_success "Absolute path escape blocked"
rm -f "$PARENT_DIR/sandbox-absolute-escape.txt" 2>/dev/null || true

echo ""
echo "Phase 4: Allowed Operations"
echo "----------------------------"

# Current directory should be writable
log_info "Testing current directory write access..."
echo "test" > ./test-write.txt 2>/dev/null && log_success "Can write to current directory (expected)" || log_failure "Cannot write to current directory (over-restricted)"
rm -f ./test-write.txt 2>/dev/null || true

# /tmp should typically be writable
log_info "Testing /tmp write access..."
echo "test" > /tmp/sandbox-test-$$.txt 2>/dev/null && log_success "Can write to /tmp (expected)" || log_info "Cannot write to /tmp (may be intentional)"
rm -f /tmp/sandbox-test-$$.txt 2>/dev/null || true

# Network should work
log_info "Testing network access..."
(echo -n | timeout 1 nc -zv google.com 80 2>&1) >/dev/null 2>&1 && log_success "Network access works (expected)" || log_info "No network access (may be intentional)"

echo ""
echo "Phase 5: Git Repository Protection"
echo "-----------------------------------"

# Test main repository hooks protection
MAIN_HOOKS="../.git/hooks"
if [ -d "$MAIN_HOOKS" ]; then
    log_info "Testing main repository .git/hooks protection..."
    echo "#!/bin/bash" > "$MAIN_HOOKS/test-hook-$$" 2>/dev/null && log_failure "Main repo .git/hooks is writable (SECURITY RISK!)" || log_success "Main repo .git/hooks is read-only"
    rm -f "$MAIN_HOOKS/test-hook-$$" 2>/dev/null || true
else
    log_info "Main repository .git/hooks not found (skipping)"
fi

# Test that we can work with git in sandboxed directories
log_info "Testing git functionality in sandbox..."
TEMP_GIT_DIR="./backup/test-git-repo"
mkdir -p "$TEMP_GIT_DIR" 2>/dev/null && log_success "Can create directories (expected)" || log_failure "Cannot create directories (over-restricted)"

if [ -d "$TEMP_GIT_DIR" ]; then
    (cd "$TEMP_GIT_DIR" && timeout 2 git init -q 2>/dev/null) && log_success "Can initialize git repos in sandbox (expected)" || log_failure "Cannot use git in sandbox (over-restricted)"
    
    if [ -d "$TEMP_GIT_DIR/.git" ]; then
        mkdir -p "$TEMP_GIT_DIR/.git/hooks" 2>/dev/null
        echo "#!/bin/bash" > "$TEMP_GIT_DIR/.git/hooks/test-hook" 2>/dev/null && log_success "Can manage hooks in sandboxed repos (expected)" || log_failure "Cannot manage hooks in sandboxed repos (over-restricted)"
    fi
fi

echo ""
echo "Phase 6: Database Write Tests"
echo "------------------------------"

# SQLite test (should always work in project directory)
log_info "Testing SQLite database operations..."
if command -v sqlite3 &> /dev/null; then
    sqlite3 ./backup/test.db "CREATE TABLE test (id INTEGER PRIMARY KEY, data TEXT);" 2>/dev/null && \
    sqlite3 ./backup/test.db "INSERT INTO test (data) VALUES ('sandbox test');" 2>/dev/null && \
    sqlite3 ./backup/test.db "SELECT * FROM test;" &>/dev/null && \
    log_success "SQLite database operations work (expected)" || \
    log_failure "SQLite database operations failed (over-restricted)"
    rm -f ./backup/test.db 2>/dev/null || true
else
    log_info "SQLite not installed, skipping test"
fi

# MySQL/MariaDB test
if [ -n "${BUBBLM_WRITABLE_DBS:-}" ] && [[ "$BUBBLM_WRITABLE_DBS" == *"mysql"* ]]; then
    log_info "Testing MySQL database operations..."
    
    # Check for MySQL client
    if command -v mysql &> /dev/null; then
        # Try to connect via socket (if available)
        for socket in /var/run/mysqld/mysqld.sock /tmp/mysql.sock /var/lib/mysql/mysql.sock; do
            if [ -S "$socket" ]; then
                log_info "Found MySQL socket at: $socket"
                # Try a simple connection test (will fail if no permissions)
                mysql --socket="$socket" -e "SELECT 1;" &>/dev/null && \
                log_success "MySQL socket connection works" || \
                log_info "MySQL socket connection failed (may need auth)"
                break
            fi
        done
        
        # Test directory write access
        if [ -d "/var/lib/mysql" ]; then
            echo "test" > /var/lib/mysql/sandbox-test 2>/dev/null && \
            log_success "MySQL data directory writable" || \
            log_failure "MySQL write flag set but directory not writable"
            rm -f /var/lib/mysql/sandbox-test 2>/dev/null || true
        fi
    else
        log_info "MySQL client not installed, skipping connection test"
    fi
fi

# PostgreSQL test
if [ -n "${BUBBLM_WRITABLE_DBS:-}" ] && [[ "$BUBBLM_WRITABLE_DBS" == *"postgres"* ]]; then
    log_info "Testing PostgreSQL database operations..."
    
    # Check for psql client
    if command -v psql &> /dev/null; then
        # Try to connect via socket (if available)
        for socket_dir in /var/run/postgresql /run/postgresql /tmp; do
            if [ -d "$socket_dir" ] && ls "$socket_dir"/.s.PGSQL.* 2>/dev/null | grep -q .; then
                log_info "Found PostgreSQL socket in: $socket_dir"
                # Try a simple connection test (will fail if no permissions)
                psql -h "$socket_dir" -l &>/dev/null && \
                log_success "PostgreSQL socket connection works" || \
                log_info "PostgreSQL socket connection failed (may need auth)"
                break
            fi
        done
        
        # Test directory write access
        if [ -d "/var/lib/postgresql" ]; then
            echo "test" > /var/lib/postgresql/sandbox-test 2>/dev/null && \
            log_success "PostgreSQL data directory writable" || \
            log_failure "PostgreSQL write flag set but directory not writable"
            rm -f /var/lib/postgresql/sandbox-test 2>/dev/null || true
        fi
    else
        log_info "PostgreSQL client not installed, skipping connection test"
    fi
fi

# Check for database write flags without testing
if [ -n "${BUBBLM_WRITABLE_DBS:-}" ]; then
    log_info "Database write flags set: $BUBBLM_WRITABLE_DBS"
else
    log_info "No database write flags set"
fi

echo ""
echo "Phase 7: Special Features"
echo "--------------------------"

# Check for extra writable paths
if [ -n "${BUBBLM_EXTRA_WRITE_PATHS:-}" ]; then
    log_info "Extra writable paths detected: $BUBBLM_EXTRA_WRITE_PATHS"
fi

echo ""
echo "==================================="
echo "Security Test Summary"
echo "==================================="
echo ""

# Count successes and failures
SUCCESS_COUNT=$(grep -c "SUCCESS" ./success.log 2>/dev/null || echo "0")
FAILURE_COUNT=$(grep -c "FAILURE" ./errors.log 2>/dev/null || echo "0")

echo "Security checks passed: $SUCCESS_COUNT"
echo "Security issues found: $FAILURE_COUNT"
echo ""

if [ "$FAILURE_COUNT" -eq 0 ]; then
    echo "✅ All security checks passed! The sandbox is working correctly."
else
    echo "⚠️  Found $FAILURE_COUNT security issue(s). Review ./errors.log for details."
fi

echo ""
echo "Full results saved to:"
echo "  ./success.log - Security features working correctly"
echo "  ./errors.log - Security issues or over-restrictions"