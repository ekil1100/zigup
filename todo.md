# zigup TODO

- [ ] CLI scaffolding with subcommands
  - [x] `env` prints PATH instructions and install dir
  - [x] Linux-only guard; friendly message for others
  - [ ] `install zig [--version <v>|latest]`
  - [ ] `install zls [--version <v>|latest]`
  - [ ] `list` installed toolchains
  - [ ] `use <version>` to switch active zig

- [ ] Install root: `~/.local/zig`
  - [x] Ensure directories exist on first run
  - [ ] Layout: `versions/<zig-version>/`, `bin/zig` symlink
  - [ ] Layout: `zls/versions/<zls-version>/`, `bin/zls` symlink

- [ ] Fetch metadata
  - [ ] Zig: GET https://ziglang.org/download/index.json
    - [ ] Detect host triplet: `x86_64-linux`, `aarch64-linux`
    - [ ] Resolve latest stable (highest semver, exclude `master`)
    - [ ] Extract `tarball` and `shasum`
  - [ ] ZLS: use zigtools/release-worker API
    - [ ] Determine correct API endpoint and response shape
    - [ ] Select asset for Linux + arch

- [ ] Download + verify + extract
  - [ ] Stream download to temp file
  - [ ] Verify SHA256
  - [ ] Extract `.tar.xz` (zig) and relevant zls archive
  - [ ] Place into versioned dir and create/update symlinks under `bin/`

- [ ] UX polish
  - [x] Print PATH instructions: `export PATH="$HOME/.local/zig/bin:$PATH"`
  - [ ] Print shell snippet to copy-paste for bash/zsh/fish
  - [ ] Handle idempotent installs and updates
  - [ ] Progress bars / sizes during download

- [ ] Tests
  - [ ] Unit tests for semver parsing/compare
  - [ ] Triplet detection table tests
  - [ ] JSON parsing for zig index
  - [ ] Dry-run mode for installers

- [ ] Future (not in v0)
  - [ ] Windows and macOS support
  - [ ] Proxy and offline cache support
  - [ ] Self-update `zigup`

