# Current Status and Next Steps

## Current Status
- Project restructured with CLI entry point and supporting modules (`core`, `fs`, `net`, `zls`).
- Implemented path management, remote index fetching/parsing, download/extract helpers, checksum verification, Zig/ZLS install and default management, plus CLI command routing.
- Build currently fails against Zig 0.16 due to API changes (JSON dynamic value access, ArrayList/allocator APIs, filesystem error sets, HTTP writer usage).

## Next Steps
1. Update JSON handling in `src/core/remote.zig` to match the Zig 0.16 dynamic value API (avoid pointer dereference, adjust object iteration and `get` usage).
2. Replace obsolete `std.ArrayList` initialization with the new managed/unmanaged variants (e.g., `std.array_list.AlignedManaged`) and adjust cleanup.
3. Fix error sets in filesystem helpers (use `std.fs.Dir.MakeError`/`OpenError` names) and ensure tar extraction compiles.
4. Adapt HTTP download logic to the new `std.Io.Writer` interface (`file.writer(&buffer)` + `Writer` usage) and ensure buffers are flushed correctly.
5. Re-run `zig fmt`/`zig build`, then exercise CLI commands (`install`, `list`, `default`, `which`, `zls`) to verify end-to-end behaviour.
