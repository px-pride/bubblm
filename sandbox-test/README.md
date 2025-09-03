# BubbLM Sandbox Security Test

This test suite validates that bubblm's sandbox correctly blocks dangerous operations while allowing legitimate development tasks.

## Purpose

The test script verifies that bubblm properly:
- Blocks write access outside the project directory
- Protects sensitive files like SSH keys
- Prevents modification of system files
- Restricts access to parent directories
- Protects git hooks in the main repository
- Allows normal development operations within the sandbox

## Usage

### Security Test
Run the security test from the sandbox-test directory:

```bash
cd sandbox-test
../bubblm.sh ./backup-system.sh

# Test with additional writable paths
../bubblm.sh -w /tmp/test-write ./backup-system.sh

# Test with database write access
../bubblm.sh -d mysql -d postgres ./backup-system.sh
```

### Database Functionality Test
Test actual database operations:

```bash
# From main bubblm directory
./bubblm -d mysql -d postgres ./sandbox-test/test-databases.sh

# Test specific databases
./bubblm -d mysql ./sandbox-test/test-databases.sh
./bubblm -d sqlite3 ./sandbox-test/test-databases.sh
```

## What It Tests

The script runs through 7 phases of security testing:

1. **Home Directory Security** 
   - ✅ Read access to .gitconfig, .bashrc (allowed)
   - ✅ Write protection for home directory (blocked)

2. **System Directory Security**
   - ✅ Read access to /etc/passwd, /etc/hosts (allowed)
   - ✅ Write protection for /etc, /usr (blocked)

3. **Directory Traversal Protection**
   - ✅ Parent directory write protection (blocked)
   - ✅ Absolute path escape prevention (blocked)

4. **Allowed Operations**
   - ✅ Write access to current directory (allowed)
   - ✅ Write access to /tmp (typically allowed)
   - ✅ Network connectivity (allowed)

5. **Git Repository Protection**
   - ✅ Main repository .git/hooks read-only (blocked)
   - ✅ Git operations in sandboxed directories (allowed)

6. **Database Write Tests**
   - ✅ SQLite operations (always allowed in project directory)
   - MySQL socket/directory access (with -d mysql flag)
   - PostgreSQL socket/directory access (with -d postgres flag)

7. **Special Features**
   - Database write flags (-d option)
   - Extra writable paths (-w option)

## Expected Results

### Security Test (backup-system.sh)
A properly configured sandbox should show:
- **~16-17 SUCCESS** entries - Security features working correctly
- **0 FAILURE** entries - No security issues

### Database Test (test-databases.sh)
Results vary based on your environment:
- SQLite tests should always pass
- MySQL/PostgreSQL tests may show connection failures if servers aren't running
- Look for successful write permissions when using -d flags

If you see any FAILURE entries, review the output for details about potential security vulnerabilities or over-restrictions.

## Output Files

After running the security test, check:
- `success.log` - Operations that worked as expected
- `errors.log` - Any security issues or unexpected behavior
- `backup/` - Test files that were successfully created

## Test Scripts

- `backup-system.sh` - Main security validation test
- `test-databases.sh` - Database functionality test

## Security Note

This script intentionally attempts dangerous operations to validate the sandbox. It should ONLY be run within bubblm or another sandbox environment. Never run this script directly without sandboxing.

## Interpreting Results

- **SUCCESS** = The sandbox is working correctly (blocking dangerous operations, allowing safe ones)
- **FAILURE** = Security issue detected (either a vulnerability or over-restriction)
- **INFO** = Informational messages about optional features

A result of 0 failures means the sandbox is properly configured and secure.