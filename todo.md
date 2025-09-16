# zigup TODO

## Project framing
- [ ] Document desired CLI behavior compared to `rustup` (install, update, list, default version management).
- [ ] Decide on command structure (e.g. `zigup install`, `zigup default`, `zigup list`, `zigup update`).
- [ ] Define configuration layout under `~/.local/zig` (versions directory, active symlinks, metadata files).

## Foundation work
- [ ] Implement argument parsing in Zig (likely using `std.cli.Parser`).
- [ ] Add logging / progress reporting helpers and colored output guard for TTY.
- [ ] Detect current platform and ensure Linux-only guard with clear error message for macOS/Windows users for now.
- [ ] Create filesystem helpers for expanding `~` and ensuring directories exist under `~/.local/zig`.

## Installing Zig toolchain
- [ ] Fetch latest stable Zig toolchain metadata from `https://ziglang.org/download/index.json` (handle JSON parsing, caching, and falling back to pinned versions).
- [ ] Select matching Linux artifact (tar.xz) per architecture and capture download URL, shasum, version tag.
- [ ] Stream download into temporary file with progress feedback and validate SHA256 before unpacking.
- [ ] Extract archive into versioned directory under `~/.local/zig/zig-{version}` and mark active version (symlink or metadata file).
- [ ] Update or create shim binaries/symlinks in `~/.local/zig/bin` (`zig`, `zigfmt`, etc.) pointing to active toolchain.
- [ ] Provide `zigup update` flow to check if installed version differs from latest and upgrade in-place.
- [ ] Implement `zigup list` to display installed versions and indicate which one is active.
- [ ] Add uninstall support for removing unused versions and cleaning symlinks.

## Installing Zig Language Server (zls)
- [ ] Call release-worker API (https://github.com/zigtools/release-worker) to resolve latest Linux zls artifact (document exact endpoint, likely `https://release-worker.zigtools.org/api/v1/releases/zls/latest`).
- [ ] Download and verify checksum (if provided) or fall back to signature verification; handle gzip/tar extraction.
- [ ] Install zls into `~/.local/zig/zls-{version}` and update shim in `~/.local/zig/bin/zls` to point at active binary.
- [ ] Track installed zls versions separately but reuse listing/selection logic where possible.

## User guidance & UX
- [ ] On install/update completion, print short instructions telling users to add `~/.local/zig/bin` to their PATH and (optionally) set `ZIGUP_HOME`.
- [ ] Add command to output the recommended shell snippet for PATH export (`zigup env`).
- [ ] Provide helpful failure messages for network errors, checksum mismatches, or unsupported architectures.
- [ ] Write integration tests (or end-to-end script) for install/list/update flows using temporary directories.
- [ ] Document usage and troubleshooting in README.

## Nice-to-haves / later
- [ ] Plan for macOS and Windows support (artifact detection, archive handling differences).
- [ ] Consider caching downloaded archives and offering offline install.
- [ ] Investigate parallel downloads for toolchain + zls when both requested.
