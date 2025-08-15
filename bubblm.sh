#!/bin/bash

# BubbLM - Cross-platform Sandbox Runner
# This script creates a sandboxed environment for running commands with restricted filesystem access
# Supports Linux (bubblewrap) and macOS (sandbox-exec/Docker)
# Usage: bubblm.sh [command] [args...]
#        If no command given, runs Claude Code with --dangerously-skip-permissions

set -euo pipefail

# Detect operating system
OS_TYPE="unknown"
case "$(uname -s)" in
    Darwin)
        OS_TYPE="macos"
        HOME_PREFIX="/Users"
        ;;
    Linux)
        OS_TYPE="linux"
        HOME_PREFIX="/home"
        ;;
    *)
        echo "Error: Unsupported operating system: $(uname -s)"
        echo "BubbLM currently supports Linux and macOS only"
        exit 1
        ;;
esac

# Parse arguments
if [ $# -eq 0 ]; then
    # No arguments - run Claude Code
    COMMAND="claude"
    ARGS=("--dangerously-skip-permissions")
    PROJECT_DIR="$(pwd)"
else
    # Arguments provided - run the specified command
    COMMAND="$1"
    shift
    ARGS=("$@")
    PROJECT_DIR="$(pwd)"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check for sandbox tool based on OS
if [ "$OS_TYPE" = "linux" ]; then
    # Check if bwrap is installed
    if ! command -v bwrap &> /dev/null; then
        log_error "bubblewrap (bwrap) is not installed. Please install it first:"
        echo "  sudo apt-get install bubblewrap  # Debian/Ubuntu"
        echo "  sudo dnf install bubblewrap      # Fedora"
        exit 1
    fi
    SANDBOX_METHOD="bwrap"
elif [ "$OS_TYPE" = "macos" ]; then
    # Check for sandbox options on macOS
    if command -v docker &> /dev/null; then
        SANDBOX_METHOD="docker"
        log_info "Using Docker for sandboxing on macOS"
    elif command -v podman &> /dev/null; then
        SANDBOX_METHOD="podman"
        log_info "Using Podman for sandboxing on macOS"
    elif command -v sandbox-exec &> /dev/null; then
        SANDBOX_METHOD="sandbox-exec"
        log_warn "Using deprecated sandbox-exec. Consider installing Docker or Podman for better isolation"
    else
        log_error "No sandbox tool found on macOS. Please install one of:"
        echo "  - Docker Desktop: https://www.docker.com/products/docker-desktop"
        echo "  - Podman: brew install podman"
        echo "  - Or run without sandboxing (not recommended)"
        exit 1
    fi
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

# Execute based on sandbox method
case "$SANDBOX_METHOD" in
    bwrap)
        # Linux: Build the bwrap command
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
    
    # The actual command
    -- "$COMMAND" "${ARGS[@]}"
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
echo "  - Working directory: $PROJECT_DIR (writable)"
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
        ;;
        
    docker|podman)
        # macOS: Use Docker or Podman container
        CONTAINER_CMD="$SANDBOX_METHOD"
        
        log_info "Sandbox configuration (Docker/Podman):"
        echo "  - Working directory: $PROJECT_DIR (writable)"
        echo "  - Container image: alpine:latest"
        echo "  - Network: enabled"
        
        # Build container command
        CONTAINER_ARGS=(
            run
            --rm                           # Remove container after exit
            -it                           # Interactive + TTY
            --network host                # Use host network
            -v "$PROJECT_DIR:$PROJECT_DIR" # Mount project directory
            -v "$HOME/.claude:/root/.claude:rw" # Claude config
            -v "$HOME/.claude.json:/root/.claude.json:rw" # Claude config file
            -v "/tmp:/tmp:rw"             # Temp directory
            -w "$PROJECT_DIR"             # Working directory
            --env HOME=/root
            --env USER=root
            alpine:latest                 # Minimal Linux image
            sh -c "apk add --no-cache bash nodejs npm python3 && $COMMAND ${ARGS[*]}"
        )
        
        log_info "Starting container sandbox..."
        exec "$CONTAINER_CMD" "${CONTAINER_ARGS[@]}"
        ;;
        
    sandbox-exec)
        # macOS: Use deprecated sandbox-exec with minimal profile
        
        # Create a temporary Seatbelt profile
        PROFILE_FILE=$(mktemp /tmp/bubblm.XXXXXX.sb)
        cat > "$PROFILE_FILE" << 'EOF'
(version 1)
(debug deny)
(allow default)

; Deny writes outside project directory and /tmp
(deny file-write*
    (regex "^/[^/]+")           ; Root level directories
    (regex "^/Users/[^/]+/[^/]+") ; User home subdirectories
    (subpath "/System")
    (subpath "/Library")
    (subpath "/Applications")
    (subpath "/usr")
    (subpath "/bin")
    (subpath "/sbin")
    (subpath "/etc")
    (subpath "/var")
    (subpath "/private"))

; Allow writes to specific locations
(allow file-write*
    (subpath "PROJECT_DIR_PLACEHOLDER")
    (subpath "/tmp")
    (subpath "/private/tmp")
    (subpath "/Users/USER_PLACEHOLDER/.claude")
    (literal "/Users/USER_PLACEHOLDER/.claude.json"))

; Allow network
(allow network*)

; Allow process execution
(allow process*)
EOF
        
        # Replace placeholders in profile
        sed -i '' "s|PROJECT_DIR_PLACEHOLDER|$PROJECT_DIR|g" "$PROFILE_FILE"
        sed -i '' "s|USER_PLACEHOLDER|$USER|g" "$PROFILE_FILE"
        
        log_info "Sandbox configuration (sandbox-exec):"
        echo "  - Working directory: $PROJECT_DIR (writable)"
        echo "  - Profile: Seatbelt (limited write access)"
        echo "  - Network: enabled"
        
        log_warn "sandbox-exec is deprecated by Apple and may be removed in future macOS versions"
        
        # Execute with sandbox-exec
        log_info "Starting sandbox-exec..."
        sandbox-exec -f "$PROFILE_FILE" "$COMMAND" "${ARGS[@]}"
        EXIT_CODE=$?
        
        # Clean up profile
        rm -f "$PROFILE_FILE"
        exit $EXIT_CODE
        ;;
        
    *)
        log_error "Unknown sandbox method: $SANDBOX_METHOD"
        exit 1
        ;;
esac