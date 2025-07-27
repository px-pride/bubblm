#!/bin/bash
# JailLM: Sandboxed agent execution with write access only to current directory and databases

CONFIG_FILE="$HOME/.jaillm-default"

# If arguments provided, save them as new default
if [ $# -gt 0 ]; then
    echo "$@" > "$CONFIG_FILE"
    DEFAULT_CMD="$@"
else
    # No arguments - use saved default or fallback
    if [ -f "$CONFIG_FILE" ]; then
        DEFAULT_CMD=$(cat "$CONFIG_FILE")
    else
        DEFAULT_CMD="claude --dangerously-skip-permissions"
    fi
    set -- $DEFAULT_CMD
fi

# Show what command is being run
echo "→ $@"
sleep 0.5

firejail --quiet \
  --read-only=/ \
  --read-write="$(pwd)" \
  --read-write=/tmp \
  --whitelist=/var/run/mysqld/mysqld.sock \
  --whitelist=/var/run/postgresql \
  --read-write=/var/run/mysqld \
  --read-write=/var/run/postgresql \
  "$@"