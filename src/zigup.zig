const std = @import("std");

const INDEX_URL = "https://ziglang.org/download/index.json";
const PLATFORM = "linux-x86_64";
const CACHE_TTL_NS: i128 = @as(i128, std.time.ns_per_hour) * 6;
const MAX_INDEX_SIZE: usize = 16 * 1024 * 1024;

const Release = struct {
    version: []const u8,
    url: []const u8,
    shasum: ?[]const u8,
    size: ?u64,
};

pub fn run(allocator: std.mem.Allocator) !void {
    const stdout = std.fs.File.stdout();
    const stderr = std.fs.File.stderr();

    const args = try std.process.argsAlloc(allocator);

    if (args.len <= 1) {
        try printUsage(stdout);
        return;
    }

    const command = args[1];
    const rest = args[2..];

    if (std.mem.eql(u8, command, "install")) {
        try handleInstall(allocator, rest, stdout, stderr);
    } else if (std.mem.eql(u8, command, "uninstall")) {
        try handleUninstall(allocator, rest, stdout, stderr);
    } else if (std.mem.eql(u8, command, "list")) {
        try handleList(allocator, rest, stdout, stderr);
    } else {
        try printToFile(allocator, stderr, "unknown command: {s}\n", .{command});
        try printUsage(stderr);
        return error.InvalidCommand;
    }
}

fn handleInstall(allocator: std.mem.Allocator, args: [][:0]u8, stdout: std.fs.File, stderr: std.fs.File) !void {
    var set_default = false;
    var version: []const u8 = "latest";

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--default")) {
            set_default = true;
        } else {
            version = arg;
        }
    }

    const releases = try fetchReleases(allocator);

    const release = findRelease(releases, version) orelse {
        try printToFile(allocator, stderr, "unknown version: {s}\n", .{version});
        return error.InvalidArguments;
    };

    const result = try installZig(allocator, release, set_default);
    switch (result) {
        .installed => try printToFile(allocator, stdout, "installed zig {s}\n", .{release.version}),
        .already_installed => try printToFile(allocator, stdout, "zig {s} already installed\n", .{release.version}),
    }

    if (set_default) {
        try printToFile(allocator, stdout, "set default zig to {s}\n", .{release.version});
    }
}

fn handleUninstall(allocator: std.mem.Allocator, args: [][:0]u8, stdout: std.fs.File, stderr: std.fs.File) !void {
    if (args.len == 0) {
        try printToFile(allocator, stderr, "usage: zigup uninstall <version>\n", .{});
        return error.InvalidArguments;
    }
    const version = args[0];
    try uninstallZig(allocator, version);
    try printToFile(allocator, stdout, "removed zig {s}\n", .{version});
}

fn handleList(allocator: std.mem.Allocator, args: [][:0]u8, stdout: std.fs.File, stderr: std.fs.File) !void {
    var show_installed = true;
    var show_remote = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--remote") or std.mem.eql(u8, arg, "-r")) {
            show_remote = true;
            show_installed = false;
        } else {
            try printToFile(allocator, stderr, "unknown flag: {s}\n", .{arg});
            return error.InvalidArguments;
        }
    }

    if (show_installed) {
        const installed = try listInstalled(allocator);

        try stdout.writeAll("Installed versions:\n");
        if (installed.versions.len == 0) {
            try stdout.writeAll("  (none)\n");
        } else {
            for (installed.versions) |version| {
                const is_default = if (installed.default) |d| std.mem.eql(u8, d, version) else false;
                const marker: u8 = if (is_default) '*' else ' ';
                try printToFile(allocator, stdout, "  {c} {s}\n", .{ marker, version });
            }
        }
    }

    if (show_remote) {
        const releases = try fetchReleases(allocator);

        try stdout.writeAll("Available releases:\n");
        for (releases) |release| {
            try printToFile(allocator, stdout, "  {s} - {s}\n", .{ release.version, release.url });
        }
    }
}

fn printUsage(file: std.fs.File) !void {
    try file.writeAll(
        "zigup commands:\n" ++
            "  install [version] [--default]   Install a Zig release (default latest).\n" ++
            "  uninstall <version>             Remove an installed Zig release.\n" ++
            "  list [--installed|--remote]     Show installed or remote Zig versions.\n",
    );
}

const InstallResult = enum { installed, already_installed };

fn installZig(allocator: std.mem.Allocator, release: Release, set_default: bool) !InstallResult {
    const home = try getHomeDir(allocator);
    const zigup_dir = try std.fs.path.join(allocator, &.{ home, ".zigup" });

    const zig_binary_path = try std.fs.path.join(allocator, &.{ zigup_dir, "dist", release.version, PLATFORM, "zig" });

    if (fileExists(zig_binary_path)) {
        if (set_default) try setDefaultZig(allocator, release.version);
        return .already_installed;
    }

    const archive_filename = try std.fmt.allocPrint(allocator, "zig-{s}-{s}.tar.xz", .{ PLATFORM, release.version });
    const archive_path = try std.fs.path.join(allocator, &.{ zigup_dir, "cache", "downloads", archive_filename });

    try ensureDir(zigup_dir);
    try ensureDir(try std.fs.path.join(allocator, &.{ zigup_dir, "cache", "downloads" }));

    if (!fileExists(archive_path)) {
        try downloadFile(allocator, release.url, archive_path);
        if (release.shasum) |expected_hash| {
            try verifyChecksum(allocator, archive_path, expected_hash);
        }
    }

    const dist_dir = try std.fs.path.join(allocator, &.{ zigup_dir, "dist", release.version });
    try extractTarXz(allocator, archive_path, dist_dir);

    if (set_default) {
        try setDefaultZig(allocator, release.version);
    }

    return .installed;
}

fn uninstallZig(allocator: std.mem.Allocator, version: []const u8) !void {
    const home = try getHomeDir(allocator);
    const zigup_dir = try std.fs.path.join(allocator, &.{ home, ".zigup" });

    const version_dir = try std.fs.path.join(allocator, &.{ zigup_dir, "dist", version });

    std.fs.cwd().deleteTree(version_dir) catch |err| switch (err) {
        error.FileSystem => {},
        else => return err,
    };

    const current_file = try std.fs.path.join(allocator, &.{ zigup_dir, "current" });

    const current = readFile(allocator, current_file) catch null;

    if (current) |c| {
        const trimmed = std.mem.trim(u8, c, " \n\r\t");
        if (std.mem.eql(u8, trimmed, version)) {
            const shim_path = try std.fs.path.join(allocator, &.{ zigup_dir, "bin", "zig" });
            std.fs.cwd().deleteFile(shim_path) catch {};
            std.fs.cwd().deleteFile(current_file) catch {};
        }
    }
}

const InstalledVersions = struct {
    versions: [][]const u8,
    default: ?[]const u8,
};

fn listInstalled(allocator: std.mem.Allocator) !InstalledVersions {
    const home = try getHomeDir(allocator);
    const zigup_dir = try std.fs.path.join(allocator, &.{ home, ".zigup" });
    const dist_dir = try std.fs.path.join(allocator, &.{ zigup_dir, "dist" });

    var versions = std.array_list.AlignedManaged([]const u8, null).init(allocator);

    var dir = std.fs.cwd().openDir(dist_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return InstalledVersions{ .versions = try allocator.alloc([]const u8, 0), .default = null },
        else => return err,
    };

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .directory) {
            const version = try allocator.dupe(u8, entry.name);
            try versions.append(version);
        }
    }

    std.mem.sort([]const u8, versions.items, {}, stringLessThan);

    const current_file = try std.fs.path.join(allocator, &.{ zigup_dir, "current" });
    const default_raw = readFile(allocator, current_file) catch null;
    const default = if (default_raw) |d| blk: {
        const trimmed = std.mem.trim(u8, d, " \n\r\t");
        const result = try allocator.dupe(u8, trimmed);
        allocator.free(d);
        break :blk result;
    } else null;

    return InstalledVersions{
        .versions = try versions.toOwnedSlice(),
        .default = default,
    };
}

fn fetchReleases(allocator: std.mem.Allocator) ![]Release {
    const home = try getHomeDir(allocator);
    const cache_path = try std.fs.path.join(allocator, &.{ home, ".zigup", "cache", "index.json" });
    try ensureDir(try std.fs.path.join(allocator, &.{ home, ".zigup", "cache" }));

    try downloadFile(allocator, INDEX_URL, cache_path);
    const data = try readFile(allocator, cache_path);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});

    var releases = std.array_list.AlignedManaged(Release, null).init(allocator);

    const obj = parsed.value.object;
    var it = obj.iterator();
    while (it.next()) |entry| {
        const tag = entry.key_ptr.*;
        std.debug.print("Found tag: {s}\n", .{tag});
        if (std.mem.eql(u8, tag, "master")) continue;
        if (entry.value_ptr.* == .object) {
            const release_obj = entry.value_ptr.*.object;
            if (release_obj.get(PLATFORM)) |platform_info| {
                if (platform_info == .object) {
                    const info = platform_info.object;
                    const url = info.get("tarball").?.string;
                    const shasum = if (info.get("shasum")) |s| s.string else null;
                    const size = if (info.get("size")) |s| @as(u64, @intCast(s.integer)) else null;

                    const version = if (std.mem.startsWith(u8, tag, "zig-")) tag[4..] else tag;

                    try releases.append(.{
                        .version = try allocator.dupe(u8, version),
                        .url = try allocator.dupe(u8, url),
                        .shasum = if (shasum) |s| try allocator.dupe(u8, s) else null,
                        .size = size,
                    });
                }
            }
        }
    }

    std.mem.sort(Release, releases.items, {}, releaseCompare);
    std.debug.print("{any}\n", .{releases.items});
    return try releases.toOwnedSlice();
}

fn findRelease(releases: []const Release, version: []const u8) ?Release {
    if (std.mem.eql(u8, version, "latest") or std.mem.eql(u8, version, "stable")) {
        for (releases) |rel| {
            if (!std.mem.containsAtLeast(u8, rel.version, 1, "dev")) {
                return rel;
            }
        }
    } else if (std.mem.eql(u8, version, "master") or std.mem.eql(u8, version, "dev")) {
        for (releases) |rel| {
            if (std.mem.containsAtLeast(u8, rel.version, 1, "dev")) {
                return rel;
            }
        }
    } else {
        for (releases) |rel| {
            if (std.mem.eql(u8, rel.version, version)) {
                return rel;
            }
        }
    }
    return null;
}

fn setDefaultZig(allocator: std.mem.Allocator, version: []const u8) !void {
    const home = try getHomeDir(allocator);
    const zigup_dir = try std.fs.path.join(allocator, &.{ home, ".zigup" });

    const zig_binary = try std.fs.path.join(allocator, &.{ zigup_dir, "dist", version, PLATFORM, "zig" });

    if (!fileExists(zig_binary)) {
        return error.FileNotFound;
    }

    const bin_dir = try std.fs.path.join(allocator, &.{ zigup_dir, "bin" });
    try ensureDir(bin_dir);

    const shim_path = try std.fs.path.join(allocator, &.{ bin_dir, "zig" });

    std.fs.cwd().deleteFile(shim_path) catch {};
    try std.posix.symlink(zig_binary, shim_path);

    const current_file = try std.fs.path.join(allocator, &.{ zigup_dir, "current" });
    const file = try std.fs.cwd().createFile(current_file, .{});
    defer file.close();
    try file.writeAll(version);
}

fn downloadFile(allocator: std.mem.Allocator, url: []const u8, dest_path: []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "curl", "-L", "-o", dest_path, url },
    });

    if (result.term != .Exited or result.term.Exited != 0) {
        return error.DownloadFailed;
    }
}

fn extractTarXz(allocator: std.mem.Allocator, archive_path: []const u8, dest_dir: []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "tar", "-xJf", archive_path, "-C", dest_dir, "--strip-components=1" },
    });

    if (result.term != .Exited or result.term.Exited != 0) {
        return error.ExtractFailed;
    }
}

fn verifyChecksum(_: std.mem.Allocator, file_path: []const u8, expected_hash: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [8192]u8 = undefined;
    while (true) {
        const n = try file.read(&buffer);
        if (n == 0) break;
        hasher.update(buffer[0..n]);
    }

    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    var hash_hex: [64]u8 = undefined;
    for (hash, 0..) |byte, i| {
        _ = try std.fmt.bufPrint(hash_hex[i * 2 ..][0..2], "{x:0>2}", .{byte});
    }

    if (!std.mem.eql(u8, &hash_hex, expected_hash)) {
        return error.HashMismatch;
    }
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(path, allocator, std.Io.Limit.limited(1024 * 1024));
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn ensureDir(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn getHomeDir(allocator: std.mem.Allocator) ![]u8 {
    return std.process.getEnvVarOwned(allocator, "HOME") catch {
        return error.NoHomeDir;
    };
}

fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn releaseCompare(_: void, a: Release, b: Release) bool {
    return std.mem.lessThan(u8, b.version, a.version);
}

fn printToFile(allocator: std.mem.Allocator, file: std.fs.File, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    try file.writeAll(text);
}
