# Repository Guidelines

## Project Structure & Module Organization
This Zig project is driven by `build.zig`, with source under `src/`. `main.zig` bootstraps the CLI runner in `cli/`, while `core/` packages the app logic (`app.zig`, `paths.zig`, `remote.zig`, `install.zig`, `list.zig`). `fs/` and `net/` wrap platform IO helpers, and `zls/` contains the Zig language service integration. Inline `test` blocks live next to the code they exercise, so new functionality should keep its tests in the same module.

## Build, Test, and Development Commands
Run `zig build` to compile and install artifacts into `zig-out/`. Use `zig build run -- <args>` to execute the CLI with custom arguments via the build runner. Execute `zig build test` to compile and run both module and executable test suites. Format sources with `zig fmt src` before sending changes. `./install_zig.sh` installs the latest master toolchain; it requires `curl`, `tar`, and an internet connection.

## Coding Style & Naming Conventions
Rely on `zig fmt` for 4-space indentation, trailing comma normalization, and import ordering. Keep module filenames lowercase with underscores, mirror directory structure in import paths, and use PascalCase for public types or error sets. Favor descriptive const names and avoid abbreviations that are not established in the codebase.

## Testing Guidelines
Use Zig’s built-in testing (`std.testing`) and add focused `test` blocks beside the implementation. Prefer arranging fixtures with scope-limited allocators (see `src/root.zig`). Run `zig build test` locally before every commit; include regression scenarios that interact with the CLI by invoking helper functions rather than shelling out when possible.

## Commit & Pull Request Guidelines
Commits should be short, imperative statements (e.g., `mvp`, `add bash script`). Group related edits into a single commit and avoid mixing refactors with feature changes. Pull requests should describe intent, reference related issues, list validation steps (`zig build`, `zig build test`), and include any relevant CLI output captures when behavior changes.
