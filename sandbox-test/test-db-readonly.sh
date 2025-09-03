#!/bin/bash

# Database Read-Only Test
# Demonstrates sandbox protection of databases outside project directory

echo "======================================="
echo "Database Read-Only Protection Test"
echo "======================================="
echo ""

# Create test directories and database
TEST_DIR="/opt/test-db-$$"
echo "Creating test database in $TEST_DIR (requires sudo)..."
sudo mkdir -p "$TEST_DIR"
sudo chown $(whoami):$(whoami) "$TEST_DIR"

# Create database outside sandbox
sqlite3 "$TEST_DIR/protected.db" "CREATE TABLE data (id INTEGER PRIMARY KEY, info TEXT, created DATETIME DEFAULT CURRENT_TIMESTAMP);"
sqlite3 "$TEST_DIR/protected.db" "INSERT INTO data (info) VALUES ('Original data created outside sandbox');"
echo "✓ Created database at $TEST_DIR/protected.db"
echo ""

# Test script
cat > /tmp/readonly-test.sh << EOF
#!/bin/bash
echo "Testing database access to $TEST_DIR/protected.db"
echo "Current directory: \$(pwd)"
echo ""

echo "1. Reading database:"
sqlite3 "$TEST_DIR/protected.db" "SELECT * FROM data;" 2>&1
echo ""

echo "2. Attempting to write:"
if sqlite3 "$TEST_DIR/protected.db" "INSERT INTO data (info) VALUES ('Written from \$(pwd)');" 2>&1; then
    echo "   ✓ Write successful"
else
    echo "   ✗ Write failed - database is protected"
fi
echo ""

echo "3. Count records:"
COUNT=\$(sqlite3 "$TEST_DIR/protected.db" "SELECT COUNT(*) FROM data;" 2>/dev/null || echo "N/A")
echo "   Total records: \$COUNT"
EOF

chmod +x /tmp/readonly-test.sh

echo "Test 1: WITHOUT sandbox"
echo "-----------------------"
/tmp/readonly-test.sh

echo ""
echo "Test 2: WITH sandbox (default)"
echo "-------------------------------"
cd /home/user/claude-projects/bubblm
./bubblm.sh /tmp/readonly-test.sh

echo ""
echo "Test 3: WITH sandbox + write permission"
echo "----------------------------------------"
echo "Using: ./bubblm.sh -w $TEST_DIR"
./bubblm.sh -w "$TEST_DIR" /tmp/readonly-test.sh

# Cleanup
echo ""
echo "Cleanup"
echo "-------"
sudo rm -rf "$TEST_DIR" /tmp/readonly-test.sh
echo "✓ Cleaned up test files"

echo ""
echo "======================================="
echo "Key Findings"
echo "======================================="
echo "1. Databases outside project/tmp dirs are read-only by default"
echo "2. -w flag grants write access to specific directories"
echo "3. This protects system databases from accidental modification"