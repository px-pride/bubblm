#!/bin/bash

# Wrapper script to run the sandbox test using bubblm
# This modifies bubblm.sh temporarily to run our test script instead of claude

# Check if the test script exists
if [ ! -f "./sandbox-test/backup-system.sh" ]; then
    echo "Error: sandbox-test/backup-system.sh not found"
    echo "Please run this from the bubblm directory"
    exit 1
fi

# Create a modified version of bubblm.sh that runs our script
cp bubblm.sh bubblm-test.sh

# Replace the claude command with our test script
sed -i 's|-- "$CLAUDE_CMD" --dangerously-skip-permissions|-- /bin/bash ./backup-system.sh|' bubblm-test.sh

# Change the working directory to sandbox-test
sed -i 's|--chdir "$PROJECT_DIR"|--chdir "$PROJECT_DIR/sandbox-test"|' bubblm-test.sh

# Run the modified sandbox with sandbox-test as the project directory
echo "Running sandbox boundary test..."
./bubblm-test.sh "$(pwd)"

# Clean up
rm -f bubblm-test.sh

echo ""
echo "Test complete. Check sandbox-test/success.log and sandbox-test/errors.log for results."