#!/bin/bash

# Claude Code Sandbox Runner with bwrap (bubblewrap)
# This script creates a sandboxed environment for running Claude Code with
# --dangerously-skip-permissions while minimizing risk of unwanted file edits

set -euo pipefail

# Configuration
CLAUDE_CMD="${CLAUDE_CMD:-claude}"
PROJECT_DIR="${1:-.}"  # First argument or current directory
PROJECT_DIR="$(realpath "$PROJECT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if bwrap is installed
if ! command -v bwrap &> /dev/null; then
    log_error "bubblewrap (bwrap) is not installed. Please install it first:"
    echo "  sudo apt-get install bubblewrap  # Debian/Ubuntu"
    echo "  sudo dnf install bubblewrap      # Fedora"
    exit 1
fi

# Check if Claude Code is accessible
if ! command -v "$CLAUDE_CMD" &> /dev/null; then
    log_error "Claude Code command '$CLAUDE_CMD' not found. Please ensure it's installed."
    exit 1
fi

# Create necessary directories if they don't exist
mkdir -p "$HOME/.claude-sandbox/cache"
mkdir -p "$HOME/.claude-sandbox/config"
mkdir -p "$HOME/.claude-sandbox/local"

log_info "Setting up sandbox for project: $PROJECT_DIR"

# Build the bwrap command
BWRAP_CMD=(
    bwrap
    
    # Basic filesystem setup
    --ro-bind /usr /usr
    --ro-bind /lib /lib
    --ro-bind /lib64 /lib64
    --ro-bind /bin /bin
    --ro-bind /sbin /sbin
    --ro-bind /etc /etc
    
    # System resources (read-only)
    --ro-bind /sys /sys
    --proc /proc
    --dev /dev
    
    # Temporary directories (writable)
    --bind /tmp /tmp
    --bind /var/tmp /var/tmp
    
    # Project directory (writable)
    --bind "$PROJECT_DIR" "$PROJECT_DIR"
    
    # Home directory setup (selective write access)
    --ro-bind "$HOME" "$HOME"
    
    # Writable home subdirectories
    --bind "$HOME/.claude-sandbox/cache" "$HOME/.cache"
    --bind "$HOME/.claude-sandbox/config" "$HOME/.config"
    --bind "$HOME/.claude-sandbox/local" "$HOME/.local"
    
    # Claude Code configuration (writable)
    --bind-try "$HOME/.claude" "$HOME/.claude"
    
    # Package manager caches (writable if they exist)
    --bind-try "$HOME/.npm" "$HOME/.npm"
    --bind-try "$HOME/.yarn" "$HOME/.yarn"
    --bind-try "$HOME/.pnpm" "$HOME/.pnpm"
    --bind-try "$HOME/.cargo" "$HOME/.cargo"
    --bind-try "$HOME/.rustup" "$HOME/.rustup"
    --bind-try "$HOME/.poetry" "$HOME/.poetry"
    --bind-try "$HOME/.pyenv" "$HOME/.pyenv"
    --bind-try "$HOME/.rbenv" "$HOME/.rbenv"
    --bind-try "$HOME/.nvm" "$HOME/.nvm"
    --bind-try "$HOME/.composer" "$HOME/.composer"
    
    # Git configuration (read-only, but allow project .git)
    --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"
    --ro-bind-try "$HOME/.ssh" "$HOME/.ssh"
    
    # Database sockets (if they exist)
    --bind-try /var/run/postgresql /var/run/postgresql
    --bind-try /var/run/mysqld /var/run/mysqld
    
    # X11 forwarding for GUI applications (if needed)
    --bind-try /tmp/.X11-unix /tmp/.X11-unix
    
    # Network access
    --share-net
    
    # Environment preservation
    --setenv HOME "$HOME"
    --setenv USER "$USER"
    --setenv TERM "$TERM"
    --setenv LANG "${LANG:-en_US.UTF-8}"
    --setenv PATH "$PATH"
    
    # Preserve display for GUI apps
    --setenv DISPLAY "${DISPLAY:-}"
    
    # Working directory
    --chdir "$PROJECT_DIR"
    
    # Unshare user namespace for additional isolation
    --unshare-user
    --uid 1000
    --gid 1000
    
    # The actual command
    -- "$CLAUDE_CMD" --dangerously-skip-permissions
)

# Optional: Add database directories if they exist and are needed
if [ -d "/var/lib/postgresql" ] && [ -n "${ENABLE_POSTGRES:-}" ]; then
    log_info "Enabling PostgreSQL data directory access"
    BWRAP_CMD+=(--bind /var/lib/postgresql /var/lib/postgresql)
fi

if [ -d "/var/lib/mysql" ] && [ -n "${ENABLE_MYSQL:-}" ]; then
    log_info "Enabling MySQL data directory access"
    BWRAP_CMD+=(--bind /var/lib/mysql /var/lib/mysql)
fi

# Show sandbox configuration
log_info "Sandbox configuration:"
echo "  - Project directory: $PROJECT_DIR (writable)"
echo "  - Cache directory: $HOME/.claude-sandbox/cache (writable)"
echo "  - Config directory: $HOME/.claude-sandbox/config (writable)"
echo "  - System directories: read-only"
echo "  - Network: enabled"
echo "  - Claude flags: --dangerously-skip-permissions"

log_warn "Claude Code will run with autonomous permissions within the sandbox"
log_warn "Project directory '$PROJECT_DIR' is fully writable"

# Ask for confirmation
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Aborted by user"
    exit 0
fi

# Execute the sandboxed Claude Code
log_info "Starting Claude Code in sandbox..."
exec "${BWRAP_CMD[@]}"