#!/bin/bash

# BubbLM - Bubblewrap Sandbox Runner
# This script creates a sandboxed environment for running commands with restricted filesystem access
# Usage: bubblm.sh [-w PATH]... [command] [args...]
#        -w, --write PATH: Add additional writable directory
#                          Can be used multiple times: -w /path1 -w /path2
#                          Or with colon-separated paths: -w "/path1:/path2:/path3"
#        If no command given, runs Claude Code with --dangerously-skip-permissions

set -euo pipefail

# Initialize arrays for extra writable paths
EXTRA_WRITE_PATHS=()

# Parse arguments
PARSING_FLAGS=true
COMMAND=""
ARGS=()

while [[ $# -gt 0 ]] && [ "$PARSING_FLAGS" = true ]; do
    case "$1" in
        -w|--write)
            if [ -z "${2:-}" ]; then
                echo "Error: $1 requires a path argument"
                exit 1
            fi
            # Split on colons to support multiple paths
            IFS=':' read -ra PATHS <<< "$2"
            for WRITE_PATH in "${PATHS[@]}"; do
                # Skip empty paths (from :: or trailing :)
                if [ -z "$WRITE_PATH" ]; then
                    continue
                fi
                # Convert to absolute path if relative
                if [[ ! "$WRITE_PATH" = /* ]]; then
                    WRITE_PATH="$(realpath "$WRITE_PATH")"
                fi
                EXTRA_WRITE_PATHS+=("$WRITE_PATH")
            done
            shift 2
            ;;
        -*)
            echo "Error: Unknown flag: $1"
            echo "Usage: bubblm [-w PATH]... [command] [args...]"
            echo "  -w PATH can be repeated: -w /path1 -w /path2"
            echo "  -w PATH can use colons: -w \"/path1:/path2\""
            exit 1
            ;;
        *)
            # First non-flag argument is the command
            COMMAND="$1"
            shift
            # Rest are arguments for the command
            ARGS=("$@")
            PARSING_FLAGS=false
            ;;
    esac
done

# If no command specified, default to Claude
if [ -z "$COMMAND" ]; then
    COMMAND="claude"
    ARGS=("--dangerously-skip-permissions")
fi

PROJECT_DIR="$(pwd)"

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

# Check if command is accessible (only for claude)
if [ "$COMMAND" = "claude" ] && ! command -v "$COMMAND" &> /dev/null; then
    log_error "Claude Code command '$COMMAND' not found. Please ensure it's installed."
    exit 1
fi

# Create necessary directories if they don't exist
mkdir -p "$HOME/.claude-sandbox/cache"
mkdir -p "$HOME/.claude-sandbox/config"
mkdir -p "$HOME/.claude-sandbox/local"

# Create Claude configuration files/directories if they don't exist
[ -d "$HOME/.claude" ] || mkdir -p "$HOME/.claude"
[ -f "$HOME/.claude.json" ] || touch "$HOME/.claude.json"

log_info "Setting up sandbox in: $PROJECT_DIR"
log_info "Running command: $COMMAND ${ARGS[*]}"
if [ ${#EXTRA_WRITE_PATHS[@]} -gt 0 ]; then
    log_info "Additional writable paths:"
    for path in "${EXTRA_WRITE_PATHS[@]}"; do
        echo "  - $path"
    done
fi

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
    
    # Home directory setup (selective write access)
    --ro-bind "$HOME" "$HOME"
    
    # Project directory (writable) - MUST come after home directory to override
    --bind "$PROJECT_DIR" "$PROJECT_DIR"
    
    # Writable home subdirectories
    --bind "$HOME/.claude-sandbox/cache" "$HOME/.cache"
    --bind "$HOME/.claude-sandbox/config" "$HOME/.config"
    --bind "$HOME/.claude-sandbox/local" "$HOME/.local"
    
    # Claude Code configuration (writable)
    --bind "$HOME/.claude" "$HOME/.claude"
    --bind "$HOME/.claude.json" "$HOME/.claude.json"
    
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
    
    # Mount /mnt for WSL symlinks (like /etc/resolv.conf -> /mnt/wsl/resolv.conf)
    --ro-bind /mnt /mnt
    
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
    
    # Note: Not using --unshare-user to allow proper file ownership and writing
    # The filesystem isolation via bind mounts still provides security boundaries
)

# Add user-specified writable paths
for path in "${EXTRA_WRITE_PATHS[@]}"; do
    if [ -e "$path" ]; then
        BWRAP_CMD+=(--bind "$path" "$path")
    else
        log_warn "Path does not exist, creating: $path"
        mkdir -p "$path" 2>/dev/null || {
            log_error "Cannot create path: $path"
            exit 1
        }
        BWRAP_CMD+=(--bind "$path" "$path")
    fi
done

# Add the command to execute
BWRAP_CMD+=(-- "$COMMAND" "${ARGS[@]}")

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
echo "  - Working directory: $PROJECT_DIR (writable)"
if [ ${#EXTRA_WRITE_PATHS[@]} -gt 0 ]; then
    for path in "${EXTRA_WRITE_PATHS[@]}"; do
        echo "  - Additional path: $path (writable)"
    done
fi
echo "  - Cache directory: $HOME/.claude-sandbox/cache (writable)"
echo "  - Config directory: $HOME/.claude-sandbox/config (writable)"
echo "  - System directories: read-only"
echo "  - Network: enabled"

if [ "$COMMAND" = "claude" ]; then
    log_warn "Claude Code will run with autonomous permissions within the sandbox"
fi
log_warn "Directory '$PROJECT_DIR' is fully writable"

# Skip confirmation - proceed directly

# Execute the sandboxed command
log_info "Starting in sandbox..."
exec "${BWRAP_CMD[@]}"