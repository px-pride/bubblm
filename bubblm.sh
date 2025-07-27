#!/bin/bash
# BubbLM: Sandboxed Claude execution with write access only to current directory and databases

# Always run Claude with the skip-permissions flag
# For other LLMs, modify this script to bind their config directories

# Show what command is being run
echo "→ claude --dangerously-skip-permissions $*" >&2
sleep 0.5

# Use bubblewrap for sandboxing - more secure than firejail
# This prevents the parent directory write vulnerability

# Build bwrap command
BWRAP_CMD=(
  bwrap
  --ro-bind / /
  --bind "$(pwd)" "$(pwd)"
  --bind /tmp /tmp
  --dev /dev
  --proc /proc
)

# Allow Claude to write to its config files if they exist
if [ -f "$HOME/.claude.json" ]; then
  BWRAP_CMD+=(--bind "$HOME/.claude.json" "$HOME/.claude.json")
elif [ -d "$HOME" ]; then
  # If the file doesn't exist, we need to allow creating it
  # Create an empty file first so we can bind it
  touch "$HOME/.claude.json" 2>/dev/null || true
  if [ -f "$HOME/.claude.json" ]; then
    BWRAP_CMD+=(--bind "$HOME/.claude.json" "$HOME/.claude.json")
  fi
fi

# Also bind .claude directory if it exists
if [ -d "$HOME/.claude" ]; then
  BWRAP_CMD+=(--bind "$HOME/.claude" "$HOME/.claude")
fi

# Add remaining options
BWRAP_CMD+=(
  --unshare-all
  --share-net
  --die-with-parent
  claude
  --dangerously-skip-permissions
  "$@"
)

# Execute the command
exec "${BWRAP_CMD[@]}"