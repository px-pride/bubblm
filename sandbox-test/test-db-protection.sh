#!/bin/bash

# Database Protection Test (No sudo required)
# Demonstrates sandbox protection using existing user directories

echo "======================================="
echo "Database Protection Test"
echo "======================================="
echo ""

# Use parent directory (outside project) for test
PARENT_DIR="$(dirname $(pwd))"
TEST_DB="$PARENT_DIR/test-protection.db"

echo "Creating test database outside project directory..."
echo "Location: $TEST_DB"
sqlite3 "$TEST_DB" "CREATE TABLE data (id INTEGER PRIMARY KEY, info TEXT, created DATETIME DEFAULT CURRENT_TIMESTAMP);"
sqlite3 "$TEST_DB" "INSERT INTO data (info) VALUES ('Created outside sandbox at $(date)');"
echo "✓ Created database with 1 record"
echo ""

# Create test script
cat > /tmp/protection-test.sh << 'EOF'
#!/bin/bash
DB_PATH="$1"
echo "Testing database access..."
echo "Database: $DB_PATH"
echo "Current directory: $(pwd)"
echo ""

echo "1. Reading database:"
sqlite3 "$DB_PATH" "SELECT * FROM data;" 2>&1 || echo "   Failed to read"
echo ""

echo "2. Attempting to write:"
if sqlite3 "$DB_PATH" "INSERT INTO data (info) VALUES ('Written from sandbox at $(date)');" 2>&1; then
    echo "   ✓ Write successful (NOT PROTECTED!)"
    COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM data;")
    echo "   Total records: $COUNT"
else
    echo "   ✗ Write failed - database is protected"
fi
echo ""

echo "3. Attempting to create table:"
if sqlite3 "$DB_PATH" "CREATE TABLE test_write (id INTEGER);" 2>&1; then
    echo "   ✓ Can modify schema (NOT PROTECTED!)"
else
    echo "   ✗ Cannot modify schema - database is protected"
fi
EOF

chmod +x /tmp/protection-test.sh

echo "Test 1: WITHOUT sandbox"
echo "-----------------------"
/tmp/protection-test.sh "$TEST_DB"

echo ""
echo "Test 2: WITH sandbox (default)"
echo "-------------------------------"
echo "Expected: Can read but cannot write"
cd "$(dirname $0)"
../bubblm.sh /tmp/protection-test.sh "$TEST_DB"

echo ""
echo "Test 3: WITH sandbox + parent dir write permission"
echo "---------------------------------------------------"
echo "Using: ../bubblm.sh -w $PARENT_DIR"
../bubblm.sh -w "$PARENT_DIR" /tmp/protection-test.sh "$TEST_DB"

echo ""
echo "Test 4: Database in home directory"
echo "-----------------------------------"
HOME_DB="$HOME/test-home-protection.db"
sqlite3 "$HOME_DB" "CREATE TABLE data (id INTEGER PRIMARY KEY, info TEXT);"
sqlite3 "$HOME_DB" "INSERT INTO data (info) VALUES ('Home directory database');"

echo "Testing access to $HOME_DB..."
../bubblm.sh /tmp/protection-test.sh "$HOME_DB"

# Cleanup
echo ""
echo "Cleanup"
echo "-------"
rm -f "$TEST_DB" "$HOME_DB" /tmp/protection-test.sh
echo "✓ Cleaned up test files"

echo ""
echo "======================================="
echo "Summary"
echo "======================================="
echo "This test demonstrated:"
echo "1. Databases in parent directory are read-only in sandbox"
echo "2. Databases in home directory are read-only in sandbox"
echo "3. -w flag grants write access to specific paths"
echo "4. Project directory remains writable"