# BubbLM

A lightweight sandboxing wrapper for Claude (Anthropic's coding assistant) with restricted filesystem access.

## What it does

BubbLM runs Claude in a secure sandbox where:
- The entire filesystem is **read-only**
- Write access is limited to:
  - Current working directory
  - `/tmp`
  - Claude's config files (`~/.claude.json`, `~/.claude/`)

Perfect for running Claude safely while preventing unwanted system modifications.

## Installation

```bash
chmod +x setup.sh
sudo ./setup.sh
```

The setup script will:
- Install `bubblewrap` (bwrap) if not present
- Install the `bubblm` command globally

## Usage

```bash
# Run Claude (always with --dangerously-skip-permissions)
bubblm

# Pass additional arguments to Claude
bubblm --version
bubblm --help
```

## Requirements

- Linux with `bubblewrap` support (works on WSL2)
- `sudo` access for installation

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

## Files

- `bubblm.sh` - The main sandboxing script
- `setup.sh` - Installer script