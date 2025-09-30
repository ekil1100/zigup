# CLAUDE.md

## Project Overview

**This is a LEARNING PROJECT** - a Zig version management tool (similar to rustup). Primary goal is education, not production use.

**Learning Focus**: Zig fundamentals, standard library (JSON, file I/O, process spawning, crypto), build system, system programming patterns.

**Teaching Methodology**: Explain concepts before implementing, provide educational insights, connect to broader principles.

MVP targets Linux x86_64 with core commands: install, uninstall, list.

## Build Commands

- `zig build` - Build zigup
- `zig build run -- <args>` - Run with arguments (e.g., `zig build run -- install latest`)

## Architecture

**Files**: `src/main.zig` (entry point), `src/zigup.zig` (core logic)

**Data Structures**:
- `StringHashMap(VersionEntry)` - Version index with O(1) lookup
- `VersionEntry` - Version metadata + `platforms: StringHashMap(PlatformEntry)`
- `PlatformEntry` - Platform tarball/shasum/size

**Commands**: `install [version] [--default]`, `uninstall <version>`, `list [-r]`

**Flow**: Fetch index.json → Download tar.xz → Verify SHA256 → Extract → Symlink `~/.zigup/bin/zig`

**Directory**: `~/.zigup/{dist/<version>/, bin/, cache/downloads/, cache/index.json, current}`

**External tools**: `curl` (downloads), `tar` (extraction)

## Key Implementation Notes

- **Memory**: Arena allocator - no manual deinit needed
- **API lookup**: Check `/home/like/.local/zig/lib/std/` source for latest dev APIs
- **Version sorting**: `versionCompare()` does semantic versioning, puts master last
- **JSON parsing**: Dynamic with `std.json.Value`, HashMap stores platform info