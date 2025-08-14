#!/bin/bash

# Direct bwrap runner for the sandbox test
# This runs the test script in a sandbox similar to bubblm

echo "Running sandbox boundary test with bwrap..."
echo ""

# Run with bwrap directly
bwrap \
    --ro-bind /usr /usr \
    --ro-bind /lib /lib \
    --ro-bind /lib64 /lib64 \
    --ro-bind /bin /bin \
    --ro-bind /sbin /sbin \
    --ro-bind /etc /etc \
    --ro-bind /sys /sys \
    --proc /proc \
    --dev /dev \
    --bind /tmp /tmp \
    --bind /var/tmp /var/tmp \
    --bind "$(pwd)" "$(pwd)" \
    --ro-bind "$HOME" "$HOME" \
    --bind "$HOME/.cache" "$HOME/.cache" \
    --bind "$HOME/.config" "$HOME/.config" \
    --bind "$HOME/.local" "$HOME/.local" \
    --bind-try "$HOME/.npm" "$HOME/.npm" \
    --bind-try "$HOME/.cargo" "$HOME/.cargo" \
    --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig" \
    --ro-bind-try "$HOME/.ssh" "$HOME/.ssh" \
    --share-net \
    --setenv HOME "$HOME" \
    --setenv USER "$USER" \
    --setenv PATH "$PATH" \
    --chdir "$(pwd)" \
    --unshare-user \
    --uid 1000 \
    --gid 1000 \
    -- /bin/bash ./backup-system.sh

echo ""
echo "Test complete. Check success.log and errors.log for results."