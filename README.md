# JailLM

A lightweight sandboxing wrapper for running LLM agents and other commands with restricted filesystem access.

## What it does

JailLM runs any command in a sandbox where:
- The entire filesystem is **read-only**
- Write access is limited to:
  - Current working directory
  - `/tmp`
  - MySQL/PostgreSQL sockets

Perfect for running agentic coding tools that need to modify your project but shouldn't touch system files.

## Installation

```bash
chmod +x setup.sh
sudo ./setup.sh
```

The setup script will:
- Install `firejail` if not present
- Install the `jaillm` command globally

## Usage

```bash
# Run default (claude --dangerously-skip-permissions)
jaillm

# Run any command
jaillm python script.py
jaillm npm run dev
jaillm cargo build
```

## Stateful defaults

JailLM remembers your last command:

```bash
jaillm python app.py    # Sets python app.py as default
jaillm                  # Now runs python app.py
jaillm npm start        # Sets npm start as default  
jaillm                  # Now runs npm start
```

## Requirements

- Linux with `firejail` support
- `sudo` access for installation

## Files

- `jaillm.sh` - The main sandboxing script
- `setup.sh` - Installer script
- `~/.jaillm-default` - Stores your default command