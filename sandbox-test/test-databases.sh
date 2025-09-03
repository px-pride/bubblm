#!/bin/bash

# Database Functionality Test for BubbLM
# This script tests actual database operations when running with -d flags
# Usage: ./bubblm -d mysql -d postgres ./sandbox-test/test-databases.sh

set -e
trap 'echo "Error at line $LINENO"' ERR

echo "==================================="
echo "BubbLM Database Functionality Test"
echo "==================================="
echo ""

# Function to log successes
log_success() {
    echo "[SUCCESS] $1"
}

# Function to log failures
log_failure() {
    echo "[FAILURE] $1"
}

# Function to log info
log_info() {
    echo "[INFO] $1"
}

# Check environment variables
echo "Environment Check:"
echo "------------------"
if [ -n "${BUBBLM_WRITABLE_DBS:-}" ]; then
    echo "Database write flags: $BUBBLM_WRITABLE_DBS"
else
    echo "No database write flags detected"
fi

if [ -n "${BUBBLM_EXTRA_WRITE_PATHS:-}" ]; then
    echo "Extra write paths: $BUBBLM_EXTRA_WRITE_PATHS"
fi
echo ""

# Test SQLite (should always work)
echo "SQLite Test:"
echo "------------"
if command -v sqlite3 &> /dev/null; then
    TEST_DB="./test_sqlite.db"
    rm -f "$TEST_DB" 2>/dev/null || true
    
    # Create database and table
    if sqlite3 "$TEST_DB" "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null; then
        log_success "Created SQLite database and table"
        
        # Insert data
        if sqlite3 "$TEST_DB" "INSERT INTO users (name) VALUES ('Test User 1'), ('Test User 2');" 2>/dev/null; then
            log_success "Inserted data into SQLite"
            
            # Query data
            RESULT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM users;" 2>/dev/null)
            if [ "$RESULT" = "2" ]; then
                log_success "SQLite queries work correctly (found $RESULT rows)"
            else
                log_failure "SQLite query returned unexpected result: $RESULT"
            fi
        else
            log_failure "Failed to insert data into SQLite"
        fi
    else
        log_failure "Failed to create SQLite database"
    fi
    
    # Cleanup
    rm -f "$TEST_DB" 2>/dev/null || true
else
    log_info "SQLite not installed, skipping"
fi
echo ""

# Test MySQL
echo "MySQL Test:"
echo "-----------"
if [ -n "${BUBBLM_WRITABLE_DBS:-}" ] && [[ "$BUBBLM_WRITABLE_DBS" == *"mysql"* ]]; then
    if command -v mysql &> /dev/null; then
        log_info "MySQL client found, attempting connection tests..."
        
        # Try different connection methods
        MYSQL_CONNECTED=false
        
        # Method 1: TCP on default port
        if mysql -h 127.0.0.1 -P 3306 -e "SELECT 1;" &>/dev/null; then
            log_success "MySQL TCP connection on port 3306 works"
            MYSQL_CONNECTED=true
        fi
        
        # Method 2: TCP on alternate port (3307)
        if ! $MYSQL_CONNECTED && mysql -h 127.0.0.1 -P 3307 -e "SELECT 1;" &>/dev/null; then
            log_success "MySQL TCP connection on port 3307 works"
            MYSQL_CONNECTED=true
        fi
        
        # Method 3: Unix socket
        if ! $MYSQL_CONNECTED; then
            for socket in /var/run/mysqld/mysqld.sock /tmp/mysql.sock /var/lib/mysql/mysql.sock; do
                if [ -S "$socket" ] && mysql --socket="$socket" -e "SELECT 1;" &>/dev/null; then
                    log_success "MySQL socket connection via $socket works"
                    MYSQL_CONNECTED=true
                    break
                fi
            done
        fi
        
        if ! $MYSQL_CONNECTED; then
            log_info "Could not connect to MySQL (may need authentication or MySQL server not running)"
        fi
    else
        log_info "MySQL client not installed"
    fi
else
    log_info "MySQL write flag not set, skipping MySQL tests"
fi
echo ""

# Test PostgreSQL
echo "PostgreSQL Test:"
echo "----------------"
if [ -n "${BUBBLM_WRITABLE_DBS:-}" ] && [[ "$BUBBLM_WRITABLE_DBS" == *"postgres"* ]]; then
    if command -v psql &> /dev/null; then
        log_info "PostgreSQL client found, attempting connection tests..."
        
        PSQL_CONNECTED=false
        
        # Method 1: TCP on default port
        if PGPASSWORD="${PGPASSWORD:-}" psql -h 127.0.0.1 -p 5432 -U "${PGUSER:-postgres}" -l &>/dev/null; then
            log_success "PostgreSQL TCP connection on port 5432 works"
            PSQL_CONNECTED=true
        fi
        
        # Method 2: Unix socket
        if ! $PSQL_CONNECTED; then
            for socket_dir in /var/run/postgresql /run/postgresql /tmp; do
                if [ -d "$socket_dir" ] && ls "$socket_dir"/.s.PGSQL.* 2>/dev/null | grep -q .; then
                    if psql -h "$socket_dir" -l &>/dev/null; then
                        log_success "PostgreSQL socket connection via $socket_dir works"
                        PSQL_CONNECTED=true
                        break
                    fi
                fi
            done
        fi
        
        if ! $PSQL_CONNECTED; then
            log_info "Could not connect to PostgreSQL (may need authentication or PostgreSQL server not running)"
        fi
    else
        log_info "PostgreSQL client not installed"
    fi
else
    log_info "PostgreSQL write flag not set, skipping PostgreSQL tests"
fi
echo ""

# Test creating a local MySQL instance (like in the CRUD demo)
echo "Local MySQL Instance Test:"
echo "--------------------------"
if [ -n "${BUBBLM_WRITABLE_DBS:-}" ] && [[ "$BUBBLM_WRITABLE_DBS" == *"mysql"* ]]; then
    if command -v mysqld &> /dev/null; then
        log_info "MySQL server binary found, could run local instance"
        log_info "See mysql_sandbox_setup.sh for example of running MySQL in userspace"
    else
        log_info "MySQL server not installed"
    fi
else
    log_info "MySQL write flag not set, skipping local instance test"
fi

echo ""
echo "==================================="
echo "Database Test Complete"
echo "==================================="
echo ""
echo "Note: Connection failures may be due to:"
echo "  - Database servers not running"
echo "  - Authentication requirements"
echo "  - Different socket/port configurations"
echo ""
echo "For a complete MySQL example that works in the sandbox,"
echo "see the included CRUD demo (mysql_sandbox_setup.sh)"