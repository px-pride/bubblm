#!/bin/bash

# Simple Database Access Test
# Shows the difference between database access with and without bubblm

echo "======================================="
echo "Simple Database Access Test"
echo "======================================="
echo ""

# Create a test database outside sandbox first
echo "Step 1: Create test database in /var/tmp (outside sandbox)"
echo "---------------------------------------------------------"
sqlite3 /var/tmp/test-db.sqlite "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);"
sqlite3 /var/tmp/test-db.sqlite "INSERT INTO users (name) VALUES ('Created Outside Sandbox');"
echo "✓ Created database with 1 record"
echo ""

# Test script that we'll run both inside and outside sandbox
cat > /tmp/db-test-script.sh << 'EOF'
#!/bin/bash
echo "Testing database access..."
echo "User: $(whoami), Directory: $(pwd)"
echo ""

# Try to read the database
echo "1. Reading from /var/tmp/test-db.sqlite:"
sqlite3 /var/tmp/test-db.sqlite "SELECT * FROM users;" 2>&1 || echo "   Failed to read"
echo ""

# Try to write to the database
echo "2. Writing to /var/tmp/test-db.sqlite:"
if sqlite3 /var/tmp/test-db.sqlite "INSERT INTO users (name) VALUES ('Written at $(date)');" 2>&1; then
    echo "   ✓ Write successful"
    COUNT=$(sqlite3 /var/tmp/test-db.sqlite "SELECT COUNT(*) FROM users;")
    echo "   Total records: $COUNT"
else
    echo "   ✗ Write failed (read-only)"
fi
echo ""

# Try to create a new database in various locations
echo "3. Creating new database in /var/tmp:"
if sqlite3 /var/tmp/new-db.sqlite "CREATE TABLE test (id INTEGER);" 2>&1; then
    echo "   ✓ Can create new database"
else
    echo "   ✗ Cannot create new database"
fi
echo ""

echo "4. Creating database in current directory:"
if sqlite3 ./local-db.sqlite "CREATE TABLE test (id INTEGER);" 2>&1; then
    echo "   ✓ Can create database in current directory"
else
    echo "   ✗ Cannot create database in current directory"
fi
EOF

chmod +x /tmp/db-test-script.sh

echo "Step 2: Test WITHOUT sandbox"
echo "-----------------------------"
/tmp/db-test-script.sh

echo ""
echo "Step 3: Test WITH sandbox (default)"
echo "------------------------------------"
cd /home/user/claude-projects/bubblm
./bubblm.sh /tmp/db-test-script.sh

echo ""
echo "Step 4: Test WITH sandbox + write permission"
echo "---------------------------------------------"
echo "Using: ./bubblm.sh -w /var/tmp"
./bubblm.sh -w /var/tmp /tmp/db-test-script.sh

# Cleanup
echo ""
echo "Cleanup"
echo "-------"
rm -f /var/tmp/test-db.sqlite /var/tmp/new-db.sqlite ./local-db.sqlite /tmp/db-test-script.sh 2>/dev/null
echo "✓ Cleaned up test files"

echo ""
echo "======================================="
echo "Summary"
echo "======================================="
echo "This test demonstrated:"
echo "1. Without sandbox: Full read/write access everywhere"
echo "2. With sandbox (default): Read-only access to system dirs, write to current dir only"
echo "3. With sandbox + -w flag: Write access to specified directories"