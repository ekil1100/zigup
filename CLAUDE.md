# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**zigup** is a Zig version manager CLI tool (similar to rustup) written in Zig. It manages multiple Zig compiler versions and the Zig Language Server (ZLS) installations. The project targets Linux, macOS, and Windows platforms for both x86_64 and aarch64 architectures.

## Key Development Commands

### Build & Run
- `zig build` - Compile the project and install to `zig-out/`
- `zig build run -- <args>` - Build and run with CLI arguments
- `zig build test` - Run all tests (module and executable tests)
- `zig fmt src` - Format all source files

### Installation Script
- `./install_zig.sh` - Installs latest master Zig toolchain and ZLS (requires curl, tar, internet)

### CLI Commands (after building)
- `./zig-out/bin/zigup install [version]` - Install Zig version (default: latest)
- `./zig-out/bin/zigup uninstall <version>` - Remove installed version
- `./zig-out/bin/zigup list [--installed|--remote]` - List versions
- `./zig-out/bin/zigup default <version>` - Set default version
- `./zig-out/bin/zigup which [zig|zls]` - Show binary path
- `./zig-out/bin/zigup zls install/update/uninstall` - Manage ZLS

## Architecture & Module Organization

### Entry Points
- `src/main.zig` - Executable entry point with GPA allocator setup
- `src/root.zig` - Library module root (for use as Zig package)
- `src/cli/runner.zig` - CLI command routing and argument parsing

### Core Modules (`src/core/`)
- `app.zig` - Main application state, HTTP client, and operation orchestration
- `paths.zig` - Directory structure management (`~/.zigup/dist/`, `bin/`, `cache/`)
- `remote.zig` - Fetches/parses Zig release index from ziglang.org/download/index.json
- `install.zig` - Version installation, symlink management, default version handling
- `list.zig` - Installed/remote version listing, which command resolution

### Support Modules
- `src/fs/archive.zig` - tar.xz extraction and file operations
- `src/net/download.zig` - HTTP downloads with progress, checksum verification
- `src/zls/service.zig` - ZLS installation and management

### Storage Layout
```
~/.zigup/
├── dist/<version>/<platform-arch>/  # Installed Zig versions
├── bin/                              # Symlinks to active version
├── cache/                            # Download cache
├── zls/<version>/                   # ZLS installations
└── current                          # Default version pointer
```

## Current Status & Known Issues

The project is being updated for Zig 0.16 compatibility. Key areas needing attention:
- JSON dynamic value API changes in `remote.zig`
- ArrayList initialization patterns need updating
- Filesystem error sets require adjustment
- HTTP writer interface changes in download logic

## Testing Strategy

- Tests are inline with implementation using `test` blocks
- Use `std.testing` utilities and scope-limited allocators
- Run `zig build test` before commits
- Test both module (`root.zig`) and executable (`main.zig`) suites

## Development Workflow

1. Make changes following existing patterns and conventions
2. Run `zig fmt src` for consistent formatting
3. Execute `zig build test` to verify tests pass
4. Test CLI functionality with `zig build run -- <command>`
5. Commit with short, imperative messages (e.g., "fix JSON parsing", "add retry logic")