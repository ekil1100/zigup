# zigup

A Zig version manager - install, manage, and switch between multiple Zig versions.

## Features

- 🚀 Install any Zig version (latest, master, stable, or specific versions)
- 🔄 Switch between installed versions instantly
- 📦 Cross-platform support (detects your OS and architecture automatically)
- 💾 Caches downloads for faster reinstalls
- ✅ SHA256 verification for security

## Installation

```bash
# Clone and build
git clone https://github.com/yourusername/zigup.git
cd zigup
zig build

# Copy to your PATH
cp zig-out/bin/zigup ~/.local/bin/

# Ensure ~/.local/bin is in your PATH
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

```bash
# Install latest stable version and set as default
zigup install latest --default

# Install specific version
zigup install 0.13.0

# Install master (development) version
zigup install master

# Switch to a different installed version
zigup use 0.13.0

# List installed versions
zigup list

# List all available versions
zigup list -r

# Uninstall a version
zigup uninstall 0.11.0
```

### Command Aliases

- `i` = `install`
- `rm` = `uninstall`
- `ls` = `list`

```bash
# These are equivalent
zigup install 0.13.0
zigup i 0.13.0

zigup list
zigup ls
```

## How It Works

### Directory Structure

```
~/.zigup/
├── cache/                     # Download cache
│   ├── index.json             # Version index
│   └── zig-linux-x86_64-*.tar.xz
├── versions/                  # Installed versions
│   ├── 0.11.0/
│   ├── 0.13.0/
│   └── master/
└── current                    # Current version (text file)

~/.local/bin/zig -> ~/.zigup/versions/0.13.0/zig
```

### Version Selection

- **master**: Latest development build
- **stable**: Latest stable release
- **0.13.0**: Specific version number

### Platform Detection

zigup automatically detects your platform at runtime:

- Linux (x86_64, aarch64, etc.)
- macOS (x86_64, aarch64)
- Windows (x86_64, aarch64)

## Development

```bash
# Build
zig build

# Run with arguments
zig build run -- install latest

# Run tests
zig build test
```

## Project Goals

This is a **learning project** with the following educational objectives:

- Understanding Zig standard library (JSON, file I/O, process spawning, crypto)
- System programming patterns (symlinks, PATH management, archive extraction)
- Cross-platform development in Zig
- Build system and project structure

See [CLAUDE.md](CLAUDE.md) for development notes and architecture details.

## Requirements

- Zig compiler (latest stable recommended)
- `curl` (for downloads)
- `tar` (for extraction)

## License

MIT
