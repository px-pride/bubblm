# BubbLM Sandbox Boundary Test

This test suite comprehensively probes the boundaries of bubblm's sandbox to verify what operations are allowed vs blocked.

## Purpose

This script attempts various file system operations that would be dangerous if not properly sandboxed, helping verify that bubblm correctly:
- Restricts write access to the project directory
- Prevents modification of system files
- Controls access to sensitive directories
- Manages package manager cache permissions
- Isolates database access appropriately

## Usage

Run the test from the bubblm directory:

```bash
# From the bubblm directory
./bubblm.sh ./sandbox-test/backup-system.sh
```

Or with the older restrictive version:
```bash
./bubblm_old.sh ./sandbox-test/backup-system.sh
```

## What It Tests

The script runs through 10 phases of testing:

1. **Home Directory Access** - Attempts to read dotfiles, SSH keys, and configs
2. **Package Manager Caches** - Tests write access to .npm, .cargo, .cache
3. **System Directories** - Tries to access /etc, /root, other users' homes
4. **Database Directories** - Attempts to read MySQL/PostgreSQL data directories
5. **Writing Outside Project** - Tests directory traversal and parent directory access
6. **Symlinks and Hardlinks** - Attempts to bypass restrictions via links
7. **Temporary Directories** - Tests /tmp and /var/tmp access
8. **Process and Network** - Checks ulimits, network connectivity, port binding
9. **Environment and Devices** - Tests /dev access and environment variables
10. **Current Directory** - Verifies normal operations within project (should succeed)

## Expected Results

### With properly configured bubblm:
- ✅ **Should SUCCEED**: Operations within `./sandbox-test/`
- ✅ **Should SUCCEED**: Reading from /tmp, /var/tmp
- ✅ **Should SUCCEED**: Network operations
- ✅ **Should SUCCEED**: Reading some system files (passwd, hosts)
- ❌ **Should FAIL**: Writing outside project directory
- ❌ **Should FAIL**: Accessing other users' data
- ❌ **Should FAIL**: Modifying system files
- ❌ **Should FAIL**: Reading SSH keys (or read-only)
- ❌ **Should FAIL**: Writing to home directory (except allowed caches)

### Output Files

After running, check:
- `success.log` - Operations that succeeded
- `errors.log` - Failed operations with error messages
- `backup/` - Any files successfully copied

## Comparing Sandbox Implementations

Run this test with both `bubblm.sh` and `bubblm_old.sh` to compare their security models:

```bash
# Test with new implementation
./bubblm.sh ./sandbox-test/backup-system.sh
mv sandbox-test/success.log sandbox-test/success_new.log
mv sandbox-test/errors.log sandbox-test/errors_new.log

# Test with old implementation  
./bubblm_old.sh ./sandbox-test/backup-system.sh
mv sandbox-test/success.log sandbox-test/success_old.log
mv sandbox-test/errors.log sandbox-test/errors_old.log

# Compare results
diff sandbox-test/success_new.log sandbox-test/success_old.log
```

## Security Note

This script intentionally attempts operations that would be dangerous if not sandboxed. It should ONLY be run within bubblm or another sandbox environment. Never run this script directly without sandboxing.

## Interpreting Results

The number of successful vs failed operations indicates how restrictive the sandbox is:
- **High failure count** = More restrictive sandbox (like bubblm_old.sh)
- **More successes** = More permissive sandbox (like current bubblm.sh)

The ideal sandbox balances security with functionality, blocking dangerous operations while allowing legitimate development tasks.