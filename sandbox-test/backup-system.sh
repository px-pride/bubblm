#!/bin/bash

# Sandbox Boundary Test Script
# This script attempts various file operations to test what bubblm allows vs blocks
# All errors are logged to errors.log for analysis

echo "==================================="
echo "BubbLM Sandbox Boundary Test"
echo "==================================="
echo ""
echo "Testing read/write permissions across filesystem..."
echo ""

# Clean up from previous runs
rm -rf ./backup/* 2>/dev/null
rm -f ./errors.log ./success.log 2>/dev/null

# Create backup directories
mkdir -p ./backup/{home,ssh,users,etc,root,mysql,postgres,system,tmp,outside}

# Function to log successes
log_success() {
    echo "[SUCCESS] $1" | tee -a ./success.log
}

# Function to log attempts
log_attempt() {
    echo "[ATTEMPT] $1"
}

echo "Phase 1: Home Directory Access"
echo "-------------------------------"

# Try to copy ALL config files from home
log_attempt "Copying all dotfiles from home..."
cp -r ~/.[!.]* ./backup/home/ 2>>./errors.log && log_success "Copied some home dotfiles" || echo "[FAILED] Could not copy all home dotfiles"

# Try specific important configs
log_attempt "Copying .gitconfig..."
cp ~/.gitconfig ./backup/home/ 2>>./errors.log && log_success "Read .gitconfig" || echo "[FAILED] Cannot read .gitconfig"

log_attempt "Copying .bashrc..."
cp ~/.bashrc ./backup/home/ 2>>./errors.log && log_success "Read .bashrc" || echo "[FAILED] Cannot read .bashrc"

# Try to read SSH keys (should fail or be read-only)
log_attempt "Accessing SSH keys..."
cp -r ~/.ssh ./backup/ssh/ 2>>./errors.log && log_success "Read SSH directory" || echo "[FAILED] Cannot read SSH directory"

# Try Claude-specific configs
log_attempt "Copying .claude directory..."
cp -r ~/.claude ./backup/home/ 2>>./errors.log && log_success "Read .claude directory" || echo "[FAILED] Cannot read .claude directory"

echo ""
echo "Phase 2: Write Access to Package Manager Caches"
echo "------------------------------------------------"

# Try to modify package manager caches
log_attempt "Writing to ~/.npm..."
echo "test" > ~/.npm/test.txt 2>>./errors.log && log_success "Wrote to ~/.npm" || echo "[FAILED] Cannot write to ~/.npm"

log_attempt "Writing to ~/.cargo..."
echo "test" > ~/.cargo/test.txt 2>>./errors.log && log_success "Wrote to ~/.cargo" || echo "[FAILED] Cannot write to ~/.cargo"

log_attempt "Writing to ~/.cache..."
mkdir -p ~/.cache/test 2>>./errors.log && log_success "Created directory in ~/.cache" || echo "[FAILED] Cannot write to ~/.cache"

echo ""
echo "Phase 3: System Directory Access"
echo "---------------------------------"

# Try to access other users' homes
log_attempt "Reading other users' home directories..."
ls /home/ > ./backup/users/listing.txt 2>>./errors.log && log_success "Listed /home/" || echo "[FAILED] Cannot list /home/"
cp -r /home/* ./backup/users/ 2>>./errors.log && log_success "Copied other users' data" || echo "[FAILED] Cannot copy other users' data"

# Try to read system configs
log_attempt "Reading /etc/passwd..."
cp /etc/passwd ./backup/etc/ 2>>./errors.log && log_success "Read /etc/passwd" || echo "[FAILED] Cannot read /etc/passwd"

log_attempt "Reading /etc/hosts..."
cp /etc/hosts ./backup/etc/ 2>>./errors.log && log_success "Read /etc/hosts" || echo "[FAILED] Cannot read /etc/hosts"

# Try to access root
log_attempt "Accessing /root directory..."
ls /root/ 2>>./errors.log && log_success "Listed /root/" || echo "[FAILED] Cannot access /root/"
cp -r /root/* ./backup/root/ 2>>./errors.log && log_success "Copied from /root/" || echo "[FAILED] Cannot copy from /root/"

echo ""
echo "Phase 4: Database Directory Access"
echo "-----------------------------------"

# Try database data directories
log_attempt "Accessing MySQL data directory..."
ls /var/lib/mysql 2>>./errors.log && log_success "Listed MySQL directory" || echo "[FAILED] Cannot access MySQL directory"
cp -r /var/lib/mysql ./backup/mysql/ 2>>./errors.log && log_success "Copied MySQL data" || echo "[FAILED] Cannot copy MySQL data"

log_attempt "Accessing PostgreSQL data directory..."
ls /var/lib/postgresql 2>>./errors.log && log_success "Listed PostgreSQL directory" || echo "[FAILED] Cannot access PostgreSQL directory"
cp -r /var/lib/postgresql ./backup/postgres/ 2>>./errors.log && log_success "Copied PostgreSQL data" || echo "[FAILED] Cannot copy PostgreSQL data"

# Try to access database sockets
log_attempt "Accessing database sockets..."
ls /var/run/mysqld/ 2>>./errors.log && log_success "Listed MySQL socket directory" || echo "[FAILED] Cannot access MySQL socket directory"
ls /var/run/postgresql/ 2>>./errors.log && log_success "Listed PostgreSQL socket directory" || echo "[FAILED] Cannot access PostgreSQL socket directory"

echo ""
echo "Phase 5: Writing Outside Project Directory"
echo "-------------------------------------------"

# Try to create files outside project
log_attempt "Writing to parent directory..."
touch ../outside.txt 2>>./errors.log && log_success "Created file in parent directory" || echo "[FAILED] Cannot write to parent directory"

log_attempt "Writing to user's Desktop..."
touch ~/Desktop/test.txt 2>>./errors.log && log_success "Created file on Desktop" || echo "[FAILED] Cannot write to Desktop"

log_attempt "Writing to /tmp with traversal..."
touch /tmp/../../etc/test.txt 2>>./errors.log && log_success "Wrote using path traversal" || echo "[FAILED] Path traversal blocked"

log_attempt "Writing directly to /etc..."
echo "test" > /etc/test.conf 2>>./errors.log && log_success "Wrote to /etc/" || echo "[FAILED] Cannot write to /etc/"

echo ""
echo "Phase 6: Symlink and Hardlink Tests"
echo "-------------------------------------"

# Try to modify system files through symlinks
log_attempt "Creating symlink to /etc/passwd..."
ln -s /etc/passwd ./passwd_link 2>>./errors.log && log_success "Created symlink to /etc/passwd" || echo "[FAILED] Cannot create symlink"

if [ -L ./passwd_link ]; then
    log_attempt "Writing through symlink to /etc/passwd..."
    echo "hack" >> ./passwd_link 2>>./errors.log && log_success "Modified /etc/passwd through symlink!" || echo "[FAILED] Cannot modify through symlink"
fi

# Try hardlinks
log_attempt "Creating hardlink to system file..."
ln /etc/hosts ./hosts_hardlink 2>>./errors.log && log_success "Created hardlink to system file" || echo "[FAILED] Cannot create hardlink to system file"

echo ""
echo "Phase 7: Temporary Directory Access"
echo "------------------------------------"

# Test /tmp access
log_attempt "Writing to /tmp..."
echo "test" > /tmp/bubblm_test.txt 2>>./errors.log && log_success "Wrote to /tmp" || echo "[FAILED] Cannot write to /tmp"

log_attempt "Creating directory in /tmp..."
mkdir -p /tmp/bubblm_test_dir 2>>./errors.log && log_success "Created directory in /tmp" || echo "[FAILED] Cannot create directory in /tmp"

log_attempt "Writing to /var/tmp..."
echo "test" > /var/tmp/bubblm_test.txt 2>>./errors.log && log_success "Wrote to /var/tmp" || echo "[FAILED] Cannot write to /var/tmp"

echo ""
echo "Phase 8: Process and Network Tests"
echo "------------------------------------"

# Test process limits
log_attempt "Checking process capabilities..."
ulimit -a > ./backup/system/ulimits.txt 2>>./errors.log && log_success "Retrieved ulimits" || echo "[FAILED] Cannot get ulimits"

# Test network access
log_attempt "Testing network connectivity..."
ping -c 1 google.com > ./backup/system/network.txt 2>>./errors.log && log_success "Network access works" || echo "[FAILED] No network access"

log_attempt "Testing localhost binding..."
python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1', 18888)); s.close(); print('success')" 2>>./errors.log && log_success "Can bind to localhost" || echo "[FAILED] Cannot bind to localhost"

echo ""
echo "Phase 9: Environment and Device Access"
echo "----------------------------------------"

# Check environment
log_attempt "Checking environment variables..."
env > ./backup/system/environment.txt 2>>./errors.log && log_success "Retrieved environment" || echo "[FAILED] Cannot get environment"

# Test device access
log_attempt "Reading from /dev/random..."
head -c 10 /dev/random > ./backup/system/random.txt 2>>./errors.log && log_success "Read from /dev/random" || echo "[FAILED] Cannot read /dev/random"

log_attempt "Accessing /dev/null..."
echo "test" > /dev/null 2>>./errors.log && log_success "Wrote to /dev/null" || echo "[FAILED] Cannot write to /dev/null"

echo ""
echo "Phase 10: Current Directory Operations"
echo "----------------------------------------"

# These should all work
log_attempt "Creating nested directories..."
mkdir -p ./backup/deep/nested/directory/structure/level5/level6/level7/level8/level9/level10 2>>./errors.log && log_success "Created deep directory structure" || echo "[FAILED] Cannot create directories"

log_attempt "Writing large file..."
dd if=/dev/zero of=./backup/large_file.bin bs=1M count=10 2>>./errors.log && log_success "Created 10MB file" || echo "[FAILED] Cannot create large file"

echo ""
echo "==================================="
echo "Test Results Summary"
echo "==================================="
echo ""

# Count successes and failures
SUCCESS_COUNT=$(grep -c "SUCCESS" ./success.log 2>/dev/null || echo "0")
ERROR_COUNT=$(grep -c "" ./errors.log 2>/dev/null || echo "0")

echo "Successful operations: $SUCCESS_COUNT"
echo "Failed operations: $ERROR_COUNT"
echo ""

echo "=== Sample of Successful Reads ==="
find ./backup -type f 2>/dev/null | head -10

echo ""
echo "=== Sample of Failed Operations ==="
if [ -f ./errors.log ]; then
    head -10 ./errors.log | sed 's/^/  /'
else
    echo "  No errors logged"
fi

echo ""
echo "Full error log saved to: ./errors.log"
echo "Full success log saved to: ./success.log"
echo ""
echo "Test complete! Review the logs to see what bubblm's sandbox allows vs blocks."