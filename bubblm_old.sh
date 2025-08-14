#!/bin/bash
# BubbLM: Highly restrictive sandboxed Claude execution
# Based on bubblm2.sh security model with Claude-specific additions

# Show what command is being run
echo "→ claude --dangerously-skip-permissions $*" >&2
sleep 0.5

# Use bubblewrap for restrictive sandboxing
BWRAP_CMD=(
  bwrap
  --ro-bind /usr /usr             # Read-only access to system binaries
  --ro-bind /bin /bin             # Read-only access to essential commands
  --ro-bind /lib /lib             # Read-only access to libraries
  --ro-bind /lib64 /lib64         # Read-only access to 64-bit libraries (if exists)
  --bind "$(pwd)" "$(pwd)"        # Write access to current directory ONLY
  --tmpfs /tmp                    # Private tmpfs for temp files
  --proc /proc                    # Process information
  --dev /dev                      # Minimal device access
  --tmpfs /etc                    # Create empty /etc first
  --ro-bind /etc/passwd /etc/passwd    # User information (required by some programs)
  --ro-bind /etc/group /etc/group      # Group information
  --symlink /proc/self/fd /dev/fd      # File descriptor access
  --symlink /proc/self/fd/0 /dev/stdin
  --symlink /proc/self/fd/1 /dev/stdout
  --symlink /proc/self/fd/2 /dev/stderr
)

# Claude needs access to its binary
if [ -d /usr/local/bin ]; then
  BWRAP_CMD+=(--ro-bind /usr/local/bin /usr/local/bin)
fi

# Allow Claude to write to its config files
# Create .claude directory if it doesn't exist
if [ ! -d "$HOME/.claude" ]; then
  mkdir -p "$HOME/.claude" 2>/dev/null || true
fi

# Bind Claude configuration directory
if [ -d "$HOME/.claude" ]; then
  BWRAP_CMD+=(--bind "$HOME/.claude" "$HOME/.claude")
fi

# Bind Claude config file
if [ ! -f "$HOME/.claude.json" ]; then
  touch "$HOME/.claude.json" 2>/dev/null || true
fi
if [ -f "$HOME/.claude.json" ]; then
  BWRAP_CMD+=(--bind "$HOME/.claude.json" "$HOME/.claude.json")
fi

# Bind SSL certificates for HTTPS
if [ -d /etc/ssl/certs ]; then
  BWRAP_CMD+=(--ro-bind /etc/ssl/certs /etc/ssl/certs)
fi

# MySQL socket access - only bind specific socket paths if they exist
# Check for local MySQL socket first (preferred for security)
if [ -S "$(pwd)/mysql_sandbox/tmp/mysql.sock" ]; then
  # Already accessible via pwd binding
  true
elif [ -S /tmp/mysql.sock ]; then
  # Bind specific socket file only
  BWRAP_CMD+=(--ro-bind /tmp/mysql.sock /tmp/mysql.sock)
elif [ -S /var/run/mysqld/mysqld.sock ]; then
  mkdir -p /tmp/mysqld_bind
  BWRAP_CMD+=(--bind /tmp/mysqld_bind /var/run/mysqld)
  BWRAP_CMD+=(--ro-bind /var/run/mysqld/mysqld.sock /var/run/mysqld/mysqld.sock)
fi

# Network configuration for localhost connections
if [ -f /etc/hosts ]; then
  BWRAP_CMD+=(--ro-bind /etc/hosts /etc/hosts)
fi
if [ -f /etc/resolv.conf ]; then
  BWRAP_CMD+=(--ro-bind /etc/resolv.conf /etc/resolv.conf)
fi

# Claude may need additional network config for API access
if [ -d /etc/ssl ]; then
  BWRAP_CMD+=(--ro-bind /etc/ssl /etc/ssl)
fi
if [ -d /usr/share/ca-certificates ]; then
  BWRAP_CMD+=(--ro-bind /usr/share/ca-certificates /usr/share/ca-certificates)
fi

# Add remaining options and run Claude
BWRAP_CMD+=(
  --die-with-parent              # Terminate if parent dies
  --unshare-all                  # Unshare all namespaces
  --share-net                    # Keep network for API and localhost access
  --hostname bubblm              # Set custom hostname
  --setenv HOME "$HOME"          # Keep HOME for Claude config access
  --setenv USER "$USER"          # Keep USER for Claude
  --setenv PATH /usr/local/bin:/usr/bin:/bin    # Include /usr/local/bin for claude
  --new-session                  # New session to prevent TIOCSTI attacks
  claude                         # Run claude command
  --dangerously-skip-permissions # Skip permission checks
  "$@"                          # User arguments
)

# Execute the sandboxed command
exec "${BWRAP_CMD[@]}"