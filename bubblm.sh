#!/bin/bash

# BubbLM - Bubblewrap Sandbox Runner
# This script creates a sandboxed environment for running commands with restricted filesystem access
# Usage: bubblm.sh [-w PATH]... [-d DB]... [command] [args...]
#        -w, --write PATH: Add additional writable directory
#                          Can be used multiple times: -w /path1 -w /path2
#                          Or with colon-separated paths: -w "/path1:/path2:/path3"
#        -d, --writable-db DB: Allow write access to specific database
#                              Can be used multiple times: -d postgres -d mysql
#                              Or with colon-separated names: -d "postgres:mysql:sqlite"
#        If no command given, runs Claude Code with --dangerously-skip-permissions
#        Automatically installs protective git hooks if in a git repository

set -euo pipefail

# Initialize arrays for extra writable paths and databases
EXTRA_WRITE_PATHS=()
WRITABLE_DATABASES=()

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
        -d|--writable-db)
            if [ -z "${2:-}" ]; then
                echo "Error: $1 requires a database argument"
                exit 1
            fi
            # Split on colons to support multiple databases
            IFS=':' read -ra DBS <<< "$2"
            for DB in "${DBS[@]}"; do
                # Skip empty names (from :: or trailing :)
                if [ -z "$DB" ]; then
                    continue
                fi
                WRITABLE_DATABASES+=("$DB")
            done
            shift 2
            ;;
        -*)
            echo "Error: Unknown flag: $1"
            echo "Usage: bubblm [-w PATH]... [-d DB]... [command] [args...]"
            echo "  -w PATH can be repeated: -w /path1 -w /path2"
            echo "  -w PATH can use colons: -w \"/path1:/path2\""
            echo "  -d DB can be repeated: -d postgres -d mysql"
            echo "  -d DB can use colons: -d \"postgres:mysql\""
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

# Warn about filter-branch in commit message
commit_msg=$(git diff --cached --name-only)
if echo "$commit_msg" | grep -q "filter-branch"; then
    echo "Warning: Detected 'filter-branch' - this operation rewrites history."
    echo "Make sure you understand the implications before proceeding."
fi

exit 0
HOOK_EOF
        chmod +x ".git/hooks/pre-commit"
        hooks_installed=$((hooks_installed + 1))
    elif ! grep -q "BUBBLM_PROTECTIVE_HOOK" ".git/hooks/pre-commit" 2>/dev/null; then
        log_warn "Git hook pre-commit already exists (user-defined), skipping protection"
    fi
    
    if [ "$hooks_installed" -gt 0 ]; then
        log_info "Installed $hooks_installed protective git hooks"
    fi
}

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

# Check and install git hooks if needed
check_and_install_git_hooks

log_info "Setting up sandbox in: $PROJECT_DIR"
log_info "Running command: $COMMAND ${ARGS[*]}"
if [ ${#EXTRA_WRITE_PATHS[@]} -gt 0 ]; then
    log_info "Additional writable paths:"
    for path in "${EXTRA_WRITE_PATHS[@]}"; do
        echo "  - $path"
    done
fi
if [ ${#WRITABLE_DATABASES[@]} -gt 0 ]; then
    log_info "Writable databases:"
    for db in "${WRITABLE_DATABASES[@]}"; do
        echo "  - $db"
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
    
    # Database sockets - read-only by default unless explicitly allowed
    --ro-bind-try /var/run/postgresql /var/run/postgresql
    --ro-bind-try /var/run/mysqld /var/run/mysqld
    
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
    
    # Database write control
    --setenv BUBBLM_WRITABLE_DBS "${WRITABLE_DATABASES[*]}"
    --setenv BUBBLM_DB_READONLY "true"
    
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

# Override database socket bindings if write access is granted
for db in "${WRITABLE_DATABASES[@]}"; do
    case "$db" in
        postgres|postgresql)
            # Remove read-only binding and add writable
            if [ -e "/var/run/postgresql" ]; then
                BWRAP_CMD+=(--bind /var/run/postgresql /var/run/postgresql)
                log_info "PostgreSQL socket mounted with write access"
            fi
            ;;
        mysql|mariadb)
            # Remove read-only binding and add writable
            if [ -e "/var/run/mysqld" ]; then
                BWRAP_CMD+=(--bind /var/run/mysqld /var/run/mysqld)
                log_info "MySQL socket mounted with write access"
            fi
            ;;
        sqlite:*)
            # Extract path after sqlite:
            db_path="${db#sqlite:}"
            if [ -e "$db_path" ]; then
                BWRAP_CMD+=(--bind "$db_path" "$db_path")
                log_info "SQLite database $db_path mounted with write access"
            else
                log_warn "SQLite database $db_path does not exist"
            fi
            ;;
        *)
            log_warn "Unknown database type: $db"
            ;;
    esac
done

# Add the command to execute
BWRAP_CMD+=(-- "$COMMAND" "${ARGS[@]}")

# Database data directories - only if explicitly allowed
for db in "${WRITABLE_DATABASES[@]}"; do
    case "$db" in
        postgres|postgresql)
            if [ -d "/var/lib/postgresql" ]; then
                BWRAP_CMD+=(--bind /var/lib/postgresql /var/lib/postgresql)
                log_info "PostgreSQL data directory mounted with write access"
            fi
            ;;
        mysql|mariadb)
            if [ -d "/var/lib/mysql" ]; then
                BWRAP_CMD+=(--bind /var/lib/mysql /var/lib/mysql)
                log_info "MySQL data directory mounted with write access"
            fi
            ;;
    esac
done

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
if [ ${#WRITABLE_DATABASES[@]} -gt 0 ]; then
    echo "  - Database sockets: selective write access"
else
    echo "  - Database sockets: read-only"
fi
echo "  - Network: enabled"

if [ "$COMMAND" = "claude" ]; then
    log_warn "Claude Code will run with autonomous permissions within the sandbox"
fi
log_warn "Directory '$PROJECT_DIR' is fully writable"

# Skip confirmation - proceed directly

# Execute the sandboxed command
log_info "Starting in sandbox..."
exec "${BWRAP_CMD[@]}"