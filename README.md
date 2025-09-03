# BubbLM

A lightweight sandboxing wrapper for Claude (Anthropic's coding assistant) and other commands with restricted filesystem access.

## ⚠️ Disclaimer

**USE AT YOUR OWN RISK.** This tool is experimental and provided "as is" without warranty of any kind. While BubbLM aims to provide sandboxing capabilities, it is not a complete security solution. Users are responsible for:
- Understanding the security implications of running commands in the sandbox
- Verifying the sandbox configuration meets their security requirements
- Not relying on this tool as the sole security measure for untrusted code
- Testing thoroughly in their own environment before production use

## What it does

BubbLM creates a secure sandbox using bubblewrap where:
- The entire filesystem is **read-only** by default
- Write access is limited to:
  - Current working directory
  - `/tmp` and `/var/tmp`
  - Claude's config files (`~/.claude.json`, `~/.claude/`)
  - Additional paths via `-w/--write` flags
  - Database directories via `-d/--writable-db` flags

Perfect for running Claude and other commands safely while preventing unwanted system modifications.

## Installation

```bash
chmod +x setup.sh
sudo ./setup.sh
```

The setup script will:
- Install `bubblewrap` (bwrap) if not present
- Install the `bubblm` command globally

## Usage

### Basic Usage

```bash
# Run Claude with --dangerously-skip-permissions (default)
bubblm

# Run any command in the sandbox
bubblm python script.py
bubblm npm install
bubblm ./my-application
```

### Advanced Options

```bash
# Add writable paths (multiple ways)
bubblm -w /path/to/dir command          # Single path
bubblm -w /path1 -w /path2 command      # Multiple flags
bubblm -w "/path1:/path2:/path3" command # Colon-separated

# Grant database write access
bubblm -d mysql command                 # MySQL socket access
bubblm -d postgres command               # PostgreSQL socket access
bubblm -d "mysql:postgres" command      # Multiple databases

# Combine options
bubblm -w /data -d mysql python app.py
```

### MySQL Support

BubbLM supports MySQL operations with proper configuration:

1. **TCP Connections (Recommended)**: Use TCP connections on non-standard ports (e.g., 3307) with password authentication instead of Unix socket authentication
2. **Socket Access**: Use `-d mysql` flag to grant write access to MySQL socket directories
3. **User-space MySQL**: Run MySQL as a regular user process within the sandbox (see `mysql_sandbox_setup.sh` for example)

The included MySQL CRUD demo shows a complete working example:
```bash
# Setup and run MySQL entirely within sandbox
./setup_venv.sh
./bubblm ./run_mysql_crud.sh
```

This runs MySQL on port 3307 with TCP authentication, avoiding privilege escalation issues.

## Requirements

- **WSL2 on Windows 10** - Currently only tested on WSL2 (Windows Subsystem for Linux 2) on Windows 10
- `bubblewrap` support
- `sudo` access for installation

> **Note**: This tool has only been tested on WSL2 running on Windows 10. Support for WSL1, Windows 11, native Linux, and other platforms is untested and may require adjustments. The current implementation includes WSL-specific handling that may not work correctly in other environments.

## Customizing for Other LLMs

To adapt BubbLM for other LLM tools, edit `bubblm.sh`:

1. **Change the command**: Replace `claude --dangerously-skip-permissions` with your LLM command
2. **Update config bindings**: Modify the file/directory bindings for your LLM's config files

For example, to use with a hypothetical "gpt-cli" that stores config in `~/.gpt/`:

```bash
# Replace lines 37-39 with:
if [ -d "$HOME/.gpt" ]; then
  BWRAP_CMD+=(--bind "$HOME/.gpt" "$HOME/.gpt")
fi

# Replace lines 46-47 with:
  gpt-cli
  "$@"
```

## Security Features

- **Git Hook Protection**: Automatically installs protective git hooks to prevent:
  - Force pushes to protected branches (master, main, develop, production)
  - Branch deletions on protected branches
  - Commits with files larger than 50MB
  - Destructive rebasing operations

- **Filesystem Isolation**: Complete read-only filesystem with selective write permissions
- **Network Access**: Enabled by default (can be used for package installation, API calls)
- **Database Protection**: Database sockets are read-only unless explicitly granted write access

## Files

- `bubblm.sh` - The main sandboxing script with full feature support
- `bubblm2.sh` - Minimal sandbox variant for CRUD applications
- `setup.sh` - Installer script
- `mysql_sandbox_setup.sh` - MySQL setup for sandbox environment
- `crud_app.py` - Example MySQL CRUD application