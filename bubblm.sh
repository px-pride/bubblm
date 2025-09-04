#!/bin/bash

# BubbLM - Bubblewrap Sandbox Runner
# This script creates a sandboxed environment for running commands with restricted filesystem access
# Usage: bubblm.sh [-w PATH]... [-d DB]... [command] [args...]
#        -w, --write PATH: Add additional writable directory (can be used multiple times)
#        -d, --writable-db DB: Allow write access to specific database (can be used multiple times)
#        If no command given, runs Claude Code with --dangerously-skip-permissions
#        Automatically installs protective git hooks if in a git repository

set -euo pipefail

# Initialize arrays for extra writable paths and databases
EXTRA_WRITE_PATHS=()
WRITABLE_DATABASES=()

# Parse arguments
COMMAND=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--write)
            if [ -z "${2:-}" ]; then
                echo "Error: $1 requires a path argument"
                exit 1
            fi
            # Convert to absolute path if relative
            if [[ ! "$2" = /* ]]; then
                EXTRA_WRITE_PATHS+=("$(realpath "$2")")
            else
                EXTRA_WRITE_PATHS+=("$2")
            fi
            shift 2
            ;;
        -d|--writable-db)
            if [ -z "${2:-}" ]; then
                echo "Error: $1 requires a database argument"
                exit 1
            fi
            WRITABLE_DATABASES+=("$2")
            shift 2
            ;;
        -*)
            echo "Error: Unknown flag: $1"
            echo "Usage: bubblm [-w PATH]... [-d DB]... [command] [args...]"
            exit 1
            ;;
        *)
            # First non-flag argument is the command
            COMMAND="$1"
            shift
            # Rest are arguments for the command
            ARGS=("$@")
            break
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

# Function to check and install git hooks
check_and_install_git_hooks() {
    # Only proceed if we're in a git repo
    if [ ! -d ".git" ]; then
        return 0
    fi
    
    if [ ! -d ".git/hooks" ]; then
        mkdir -p ".git/hooks"
    fi
    
    local hooks_installed=0
    
    # Pre-push hook - prevent force pushes and deletions
    if [ ! -f ".git/hooks/pre-push" ]; then
        cat > ".git/hooks/pre-push" << 'HOOK_EOF'
#!/bin/bash
# BUBBLM_PROTECTIVE_HOOK - Prevent destructive git operations

protected_branches="^(master|main|develop|production)$"

while read local_ref local_sha remote_ref remote_sha; do
    # Check for force push (non-fast-forward)
    if [ "$remote_sha" != "0000000000000000000000000000000000000000" ]; then
        # Remote ref exists, check if this is a force push
        if ! git merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
            branch_name="${remote_ref#refs/heads/}"
            if [[ "$branch_name" =~ $protected_branches ]]; then
                echo "Error: Force push to protected branch '$branch_name' is not allowed."
                echo "Use --force-with-lease for safer force pushes to feature branches."
                exit 1
            fi
        fi
    fi
    
    # Check for branch deletion
    if [ "$local_sha" = "0000000000000000000000000000000000000000" ]; then
        branch_name="${remote_ref#refs/heads/}"
        if [[ "$branch_name" =~ $protected_branches ]]; then
            echo "Error: Deleting protected branch '$branch_name' is not allowed."
            exit 1
        fi
    fi
done

exit 0
HOOK_EOF
        chmod +x ".git/hooks/pre-push"
        hooks_installed=$((hooks_installed + 1))
    elif ! grep -q "BUBBLM_PROTECTIVE_HOOK" ".git/hooks/pre-push" 2>/dev/null; then
        log_warn "Git hook pre-push already exists (user-defined), skipping protection"
    fi
    
    # Pre-rebase hook - prevent rebasing protected branches
    if [ ! -f ".git/hooks/pre-rebase" ]; then
        cat > ".git/hooks/pre-rebase" << 'HOOK_EOF'
#!/bin/bash
# BUBBLM_PROTECTIVE_HOOK - Prevent destructive git operations

protected_branches="^(master|main|develop|production)$"
current_branch="$(git symbolic-ref HEAD 2>/dev/null | sed 's/refs\/heads\///')"

if [[ "$current_branch" =~ $protected_branches ]]; then
    echo "Error: Rebasing protected branch '$current_branch' is not allowed."
    echo "Create a feature branch for your changes instead."
    exit 1
fi

# Prevent rebasing commits that are already pushed to protected branches
upstream_branch="$1"
if [ -n "$upstream_branch" ] && [[ "$upstream_branch" =~ $protected_branches ]]; then
    echo "Error: Rebasing onto protected branch '$upstream_branch' requires careful review."
    echo "Consider using merge instead of rebase for protected branches."
    exit 1
fi

exit 0
HOOK_EOF
        chmod +x ".git/hooks/pre-rebase"
        hooks_installed=$((hooks_installed + 1))
    elif ! grep -q "BUBBLM_PROTECTIVE_HOOK" ".git/hooks/pre-rebase" 2>/dev/null; then
        log_warn "Git hook pre-rebase already exists (user-defined), skipping protection"
    fi
    
    # Pre-commit hook - prevent commits that might be destructive
    if [ ! -f ".git/hooks/pre-commit" ]; then
        cat > ".git/hooks/pre-commit" << 'HOOK_EOF'
#!/bin/bash
# BUBBLM_PROTECTIVE_HOOK - Prevent destructive git operations

# Check for large files (>50MB)
for file in $(git diff --cached --name-only); do
    if [ -f "$file" ]; then
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        if [ "$size" -gt 52428800 ]; then
            echo "Error: File '$file' is larger than 50MB."
            echo "Large files should not be committed to git. Consider using Git LFS."
            exit 1
        fi
    fi
done

# Check for common sensitive files
sensitive_patterns="private_key|secret|password|token|\.env$|credentials"
for file in $(git diff --cached --name-only); do
    if echo "$file" | grep -qiE "$sensitive_patterns"; then
        echo "Warning: File '$file' may contain sensitive information."
        echo "Please review before committing. Continue? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
done

exit 0
HOOK_EOF
        chmod +x ".git/hooks/pre-commit"
        hooks_installed=$((hooks_installed + 1))
    elif ! grep -q "BUBBLM_PROTECTIVE_HOOK" ".git/hooks/pre-commit" 2>/dev/null; then
        log_warn "Git hook pre-commit already exists (user-defined), skipping protection"
    fi
    
    if [ $hooks_installed -gt 0 ]; then
        log_info "Installed $hooks_installed protective git hook(s)"
    fi
    
    # Make hooks directory read-only to prevent modification
    chmod -w ".git/hooks" 2>/dev/null || true
}

# Install git hooks if in a git repository
check_and_install_git_hooks

# Create sandbox directories if they don't exist
mkdir -p "$HOME/.claude-sandbox/cache"
mkdir -p "$HOME/.claude-sandbox/config"
mkdir -p "$HOME/.claude-sandbox/local"

# Check if bubblewrap is installed
if ! command -v bwrap &> /dev/null; then
    log_error "bubblewrap is not installed. Please install it first:"
    echo "  Ubuntu/Debian: sudo apt-get install bubblewrap"
    echo "  macOS: brew install bubblewrap"
    echo "  Fedora: sudo dnf install bubblewrap"
    exit 1
fi

log_info "Setting up sandbox in: $PROJECT_DIR"
if [ -n "$COMMAND" ]; then
    log_info "Running command: $COMMAND ${ARGS[*]}"
else
    log_info "No command specified"
fi

# Show configuration
log_info "Sandbox configuration:"
echo "  - Working directory: $PROJECT_DIR (writable)"
echo "  - Cache directory: $HOME/.claude-sandbox/cache (writable)"
echo "  - Config directory: $HOME/.claude-sandbox/config (writable)"
echo "  - System directories: read-only"
echo "  - Database sockets: read-only"
echo "  - Network: enabled"

# Show extra write paths
if [ ${#EXTRA_WRITE_PATHS[@]} -gt 0 ]; then
    echo "  - Additional writable paths:"
    for path in "${EXTRA_WRITE_PATHS[@]}"; do
        echo "    - $path"
    done
fi

# Show database write permissions
if [ ${#WRITABLE_DATABASES[@]} -gt 0 ]; then
    echo "  - Writable databases:"
    for db in "${WRITABLE_DATABASES[@]}"; do
        echo "    - $db"
    done
fi

# Warn if potentially dangerous
log_warn "Directory '$PROJECT_DIR' is fully writable"

# Build bubblewrap command
BWRAP_CMD=(
    bwrap
    # Basic filesystem structure (read-only)
    --ro-bind /usr /usr
    --ro-bind /lib /lib
    --ro-bind /lib64 /lib64
    --ro-bind /bin /bin
    --ro-bind /sbin /sbin
    --ro-bind /etc /etc
    
    # /sys for hardware info (read-only)
    --ro-bind /sys /sys
    
    # /dev essentials
    --dev /dev
    
    # Writable temp directories
    --bind /tmp /tmp
    --bind /var/tmp /var/tmp
    
    # Home directory (read-only, with exceptions below)
    --ro-bind "$HOME" "$HOME"
    
    # Claude sandbox directories (writable)
    --bind "$HOME/.claude-sandbox/cache" "$HOME/.cache"
    --bind "$HOME/.claude-sandbox/config" "$HOME/.config"
    --bind "$HOME/.claude-sandbox/local" "$HOME/.local"
    
    # Claude configuration files (if they exist)
    --bind-try "$HOME/.claude" "$HOME/.claude"
    --bind-try "$HOME/.claude.json" "$HOME/.claude.json"
    
    # Package manager caches (writable)
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
    
    # Git config (read-only)
    --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"
    --ro-bind-try "$HOME/.ssh" "$HOME/.ssh"
    
    # Database sockets (read-only by default)
    --ro-bind-try /var/run/postgresql /var/run/postgresql
    --ro-bind-try /var/run/mysqld /var/run/mysqld
    
    # X11 socket for GUI apps
    --bind-try /tmp/.X11-unix /tmp/.X11-unix
    
    # /proc for process info
    --proc /proc
    
    # Mount /mnt for WSL compatibility (for /mnt/wslg)
    --ro-bind /mnt /mnt
    
    # Project directory (writable) - must come after /mnt mount to override it
    --bind "$PROJECT_DIR" "$PROJECT_DIR"
    
    # Make .git/hooks read-only to prevent escape via git hooks - must be last
    --ro-bind-try "$PROJECT_DIR/.git/hooks" "$PROJECT_DIR/.git/hooks"
    
    # Network access
    --share-net
    
    # Hostname (requires --unshare-uts)
    --unshare-uts
    --hostname "sandbox"
    
    # New session
    --new-session
    
    # Die when parent dies
    --die-with-parent
)

# Add extra writable paths
for path in "${EXTRA_WRITE_PATHS[@]}"; do
    if [ ! -e "$path" ]; then
        log_warn "Path does not exist, creating: $path"
        mkdir -p "$path"
    fi
    if [ -d "$path" ]; then
        BWRAP_CMD+=(--bind "$path" "$path")
        log_info "Added writable path: $path"
    else
        log_error "Path is not a directory: $path"
        exit 1
    fi
done

# Handle database write permissions
for db in "${WRITABLE_DATABASES[@]}"; do
    case "$db" in
        postgres|postgresql)
            # PostgreSQL socket and data directories
            for socket_dir in /var/run/postgresql /run/postgresql /tmp; do
                if [ -d "$socket_dir" ] && ls "$socket_dir"/.s.PGSQL.* 2>/dev/null | grep -q .; then
                    BWRAP_CMD+=(--bind "$socket_dir" "$socket_dir")
                    log_info "PostgreSQL socket directory made writable: $socket_dir"
                    break
                fi
            done
            if [ -d /var/lib/postgresql ]; then
                BWRAP_CMD+=(--bind /var/lib/postgresql /var/lib/postgresql)
                log_info "PostgreSQL data directory made writable"
            fi
            ;;
        mysql|mariadb)
            # MySQL/MariaDB socket and data directories
            for socket_dir in /var/run/mysqld /run/mysqld /tmp; do
                if [ -e "$socket_dir/mysqld.sock" ]; then
                    BWRAP_CMD+=(--bind "$socket_dir" "$socket_dir")
                    log_info "MySQL socket directory made writable: $socket_dir"
                    break
                fi
            done
            if [ -d /var/lib/mysql ]; then
                BWRAP_CMD+=(--bind /var/lib/mysql /var/lib/mysql)
                log_info "MySQL data directory made writable"
            fi
            ;;
        sqlite|sqlite3)
            # SQLite doesn't need special handling - files are in project directory
            log_info "SQLite write access enabled (project directory already writable)"
            ;;
        *)
            log_warn "Unknown database type: $db (ignoring)"
            ;;
    esac
done

# Export environment variables for database access
if [ ${#WRITABLE_DATABASES[@]} -gt 0 ]; then
    export BUBBLM_WRITABLE_DBS="${WRITABLE_DATABASES[*]}"
fi

# Export environment variable for extra write paths
if [ ${#EXTRA_WRITE_PATHS[@]} -gt 0 ]; then
    export BUBBLM_EXTRA_WRITE_PATHS="${EXTRA_WRITE_PATHS[*]}"
fi

# Set working directory
BWRAP_CMD+=(--chdir "$PROJECT_DIR")

# Add command to run
BWRAP_CMD+=("$COMMAND")
BWRAP_CMD+=("${ARGS[@]}")

# Run in sandbox
log_info "Starting in sandbox..."
exec "${BWRAP_CMD[@]}"