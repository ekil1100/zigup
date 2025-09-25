# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**This is a LEARNING PROJECT** - a Zig version management tool (similar to rustup) written in Zig. The primary goal is education, not production use.

### Learning Objectives
- **Zig Fundamentals**: Basic syntax, memory management, error handling patterns
- **Standard Library**: HTTP clients, JSON parsing, file system operations, process management
- **Build System**: Understanding build.zig, build.zig.zon, and dependency management
- **System Programming**: Cross-platform considerations, symlink management, package installation patterns

### Teaching Methodology
When working with this codebase:
1. **Explain concepts first** - Before implementing, explain the "why" behind design decisions
2. **Interactive learning** - Request user input on 2-10 line code pieces for key algorithms or design decisions
3. **Progressive complexity** - Build features incrementally, reinforcing previous concepts
4. **Real-world context** - Connect each implementation to broader systems programming principles

The MVP focuses on Linux x86_64 support with core functionality: install, uninstall, and list Zig versions.

## Build Commands

- `zig build` - Build the zigup executable
- `zig build run` - Build and run the application
- `zig build run -- <args>` - Run with command line arguments (e.g., `zig build run -- install latest`)
- `zig build test` - Run tests for the zigup.zig module

## Architecture

### Core Structure
- `src/main.zig` - Entry point with memory allocator setup, delegates to zigup module
- `src/zigup.zig` - Main application logic containing all CLI commands and core functionality

### Key Components in zigup.zig:

**Command Handling**: CLI argument parsing with command dispatch for `install`, `uninstall`, `list`

**Release Management**:
- Fetches from https://ziglang.org/download/index.json with 6-hour caching
- Parses JSON to extract Linux x86_64 releases with URL/shasum validation
- Version resolution: supports "latest", "stable", "master"/"dev", and specific versions

**Installation Pipeline**:
- Downloads tar.xz archives to `~/.zigup/cache/downloads/`
- Verifies SHA256 checksums using Zig's crypto.hash.sha2.Sha256
- Extracts to `~/.zigup/dist/<version>/` using external tar command
- Creates symlinks in `~/.zigup/bin/zig` for default version management

**Directory Structure**:
```
~/.zigup/
├── dist/<version>/linux-x86_64/zig    # Extracted Zig binaries
├── bin/zig                           # Symlink to default version
├── cache/downloads/                  # Downloaded archives
├── cache/index.json                  # Cached version index
└── current                          # File containing default version
```

### External Dependencies
- Uses `curl` for HTTP downloads (via std.process.Child.run)
- Uses `tar` for archive extraction
- No Zig package dependencies (empty .dependencies in build.zig.zon)

### Error Handling Patterns
- Custom error types (InvalidCommand, InvalidArguments, etc.)
- File operation error handling with appropriate fallbacks
- Network operation validation and retry logic

## Learning Focus Areas

### Zig Concepts Demonstrated
- **Memory Management**: GeneralPurposeAllocator patterns, defer cleanup, owned vs borrowed memory
- **Error Handling**: Custom error types, error unions, try/catch patterns
- **Standard Library**: JSON parsing, file I/O, process spawning, cryptographic hashing
- **String Handling**: Zig's approach to UTF-8, slices, and string comparison
- **Build System**: Module system, conditional compilation, external tool integration

### Teaching Opportunities
1. **HTTP Client Evolution**: Start with external curl, migrate to std.http for learning
2. **JSON Processing**: Demonstrate parsing strategies, memory ownership in JSON trees
3. **File System Patterns**: Path manipulation, directory traversal, atomic operations
4. **Version Management Logic**: String parsing, semantic versioning, dependency resolution
5. **CLI Design**: Argument parsing, user experience, error messaging

### Interactive Learning Guidelines
- Use TodoWrite to track learning objectives and progress
- Request user implementation of core algorithms (version comparison, path resolution)
- Explain trade-offs between external tools vs pure Zig implementations
- Connect each feature to broader software engineering principles
- Provide "Learn by Doing" opportunities for key business logic

Current implementation uses external tools (curl, tar) as stepping stones - perfect opportunities to demonstrate Zig alternatives and discuss architectural evolution.
