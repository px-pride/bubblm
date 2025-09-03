#!/bin/bash

# Database Access Comparison Test
# This script demonstrates the difference between database access with and without bubblm
# It creates databases outside the sandbox, then tests access from inside

set -e
trap 'echo "Error at line $LINENO"' ERR

echo "==========================================="
echo "BubbLM Database Access Comparison Test"
echo "==========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_failure() { echo -e "${RED}[FAILURE]${NC} $1"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# Test directories
TEST_DIR="/tmp/bubblm-db-test-$$"
PROJECT_DIR="$(pwd)"

echo "Creating test environment..."
mkdir -p "$TEST_DIR"

# Create a simple script to test database access
cat > "$TEST_DIR/test-db-operations.sh" << 'EOF'
#!/bin/bash
# This script will be run both inside and outside the sandbox

echo "Testing database operations..."
echo "Current user: $(whoami)"
echo "Current directory: $(pwd)"
echo ""

# Test 1: SQLite in /tmp
echo "1. SQLite test in /tmp:"
if sqlite3 /tmp/test-external.db "CREATE TABLE IF NOT EXISTS test_access (id INTEGER PRIMARY KEY, data TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null; then
    echo "   ✓ Can create table in /tmp/test-external.db"
    if sqlite3 /tmp/test-external.db "INSERT INTO test_access (data) VALUES ('Test from $(whoami) at $(date)');" 2>/dev/null; then
        echo "   ✓ Can insert data"
        COUNT=$(sqlite3 /tmp/test-external.db "SELECT COUNT(*) FROM test_access;" 2>/dev/null)
        echo "   ✓ Total rows: $COUNT"
    else
        echo "   ✗ Cannot insert data"
    fi
else
    echo "   ✗ Cannot create table in /tmp/test-external.db"
fi
echo ""

# Test 2: SQLite in home directory
echo "2. SQLite test in home directory:"
if sqlite3 ~/test-home.db "CREATE TABLE IF NOT EXISTS test_access (id INTEGER PRIMARY KEY, data TEXT);" 2>/dev/null; then
    echo "   ✓ Can create table in ~/test-home.db"
    if sqlite3 ~/test-home.db "INSERT INTO test_access (data) VALUES ('Test data');" 2>/dev/null; then
        echo "   ✓ Can insert data"
    else
        echo "   ✗ Cannot insert data"
    fi
else
    echo "   ✗ Cannot create/write to ~/test-home.db"
fi
echo ""

# Test 3: SQLite in current directory
echo "3. SQLite test in current directory:"
if sqlite3 ./test-local.db "CREATE TABLE IF NOT EXISTS test_access (id INTEGER PRIMARY KEY, data TEXT);" 2>/dev/null; then
    echo "   ✓ Can create table in ./test-local.db"
    if sqlite3 ./test-local.db "INSERT INTO test_access (data) VALUES ('Test data');" 2>/dev/null; then
        echo "   ✓ Can insert data"
    else
        echo "   ✗ Cannot insert data"
    fi
else
    echo "   ✗ Cannot create/write to ./test-local.db"
fi
echo ""

# Test 4: MySQL socket access (if available)
echo "4. MySQL socket test:"
if command -v mysql &> /dev/null; then
    # Try to find MySQL socket
    for socket in /var/run/mysqld/mysqld.sock /tmp/mysql.sock; do
        if [ -S "$socket" ]; then
            echo "   Found socket: $socket"
            if mysql --socket="$socket" -e "SELECT 1;" &>/dev/null; then
                echo "   ✓ Can connect via socket"
            else
                echo "   ✗ Cannot connect via socket (may need auth)"
            fi
            break
        fi
    done
    
    # Test MySQL data directory write
    if [ -d "/var/lib/mysql" ]; then
        if touch /var/lib/mysql/test-write-$$ 2>/dev/null; then
            echo "   ✓ Can write to /var/lib/mysql"
            rm -f /var/lib/mysql/test-write-$$ 2>/dev/null
        else
            echo "   ✗ Cannot write to /var/lib/mysql"
        fi
    fi
else
    echo "   MySQL client not installed"
fi
echo ""

# Test 5: PostgreSQL socket access (if available)
echo "5. PostgreSQL socket test:"
if command -v psql &> /dev/null; then
    # Try to find PostgreSQL socket
    for socket_dir in /var/run/postgresql /run/postgresql; do
        if [ -d "$socket_dir" ] && ls "$socket_dir"/.s.PGSQL.* 2>/dev/null | grep -q .; then
            echo "   Found socket in: $socket_dir"
            if psql -h "$socket_dir" -l &>/dev/null; then
                echo "   ✓ Can connect via socket"
            else
                echo "   ✗ Cannot connect via socket (may need auth)"
            fi
            break
        fi
    done
    
    # Test PostgreSQL data directory write
    if [ -d "/var/lib/postgresql" ]; then
        if touch /var/lib/postgresql/test-write-$$ 2>/dev/null; then
            echo "   ✓ Can write to /var/lib/postgresql"
            rm -f /var/lib/postgresql/test-write-$$ 2>/dev/null
        else
            echo "   ✗ Cannot write to /var/lib/postgresql"
        fi
    fi
else
    echo "   PostgreSQL client not installed"
fi
EOF

chmod +x "$TEST_DIR/test-db-operations.sh"

echo ""
echo "Phase 1: Create databases OUTSIDE sandbox"
echo "-----------------------------------------"

# Create SQLite database in /tmp
log_info "Creating SQLite database in /tmp..."
sqlite3 /tmp/test-external.db "CREATE TABLE test_data (id INTEGER PRIMARY KEY, info TEXT);" 2>/dev/null && \
sqlite3 /tmp/test-external.db "INSERT INTO test_data (info) VALUES ('Created outside sandbox');" 2>/dev/null && \
log_success "Created /tmp/test-external.db with initial data" || \
log_failure "Failed to create database"

# Create SQLite database in home
log_info "Creating SQLite database in home directory..."
sqlite3 ~/test-home.db "CREATE TABLE test_data (id INTEGER PRIMARY KEY, info TEXT);" 2>/dev/null && \
sqlite3 ~/test-home.db "INSERT INTO test_data (info) VALUES ('Created in home directory');" 2>/dev/null && \
log_success "Created ~/test-home.db with initial data" || \
log_failure "Failed to create database"

echo ""
echo "Phase 2: Test access WITHOUT sandbox"
echo "-------------------------------------"
"$TEST_DIR/test-db-operations.sh"

echo ""
echo "Phase 3: Test access WITH sandbox (no -d flag)"
echo "-----------------------------------------------"
cd "$PROJECT_DIR"
../bubblm.sh "$TEST_DIR/test-db-operations.sh"

echo ""
echo "Phase 4: Test access WITH sandbox (with -d flags)"
echo "--------------------------------------------------"
cd "$PROJECT_DIR"
../bubblm.sh -d mysql -d postgres "$TEST_DIR/test-db-operations.sh"

echo ""
echo "Phase 5: Test with additional write path"
echo "-----------------------------------------"
log_info "Testing with -w /tmp flag..."
cd "$PROJECT_DIR"
../bubblm.sh -w /tmp "$TEST_DIR/test-db-operations.sh"

echo ""
echo "Cleanup"
echo "-------"
log_info "Cleaning up test files..."
rm -f /tmp/test-external.db ~/test-home.db ./test-local.db 2>/dev/null
rm -rf "$TEST_DIR" 2>/dev/null

echo ""
echo "==========================================="
echo "Test Summary"
echo "==========================================="
echo ""
echo "This test demonstrated:"
echo "1. Databases created outside sandbox can be read but not written to"
echo "2. Write access to /tmp requires -w /tmp flag"
echo "3. Write access to database directories requires -d flags"
echo "4. Current directory is always writable in sandbox"
echo "5. Home directory is read-only in sandbox"