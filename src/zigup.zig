const std = @import("std");

const INDEX_URL = "https://ziglang.org/download/index.json";

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

    if (std.mem.eql(u8, command, "install") or std.mem.eql(u8, command, "i")) {
        try handleInstall(allocator, rest);
    } else if (std.mem.eql(u8, command, "uninstall") or std.mem.eql(u8, command, "rm")) {
        try handleUninstall(allocator, rest);
    } else if (std.mem.eql(u8, command, "list") or std.mem.eql(u8, command, "ls")) {
        try handleList(allocator, rest);
    } else if (std.mem.eql(u8, command, "use")) {
        try handleUse(allocator, rest);
    } else {
        std.debug.print("unknown command: {s}\n", .{command});
        try printUsage(stderr);
        return error.InvalidCommand;
    }
}

fn handleInstall(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var set_default = false;
    var version: []const u8 = "latest";

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--default") or std.mem.eql(u8, arg, "-d")) {
            set_default = true;
        } else {
            version = arg;
        }
    }

    const releases = try fetchReleases(allocator);

    const release = try findRelease(allocator, releases, version) orelse {
        std.debug.print("unknown version: {s}\n", .{version});
        return error.InvalidArguments;
    };

    const result = try installZig(allocator, release, version, set_default);
    switch (result) {
        .installed => std.debug.print("installed zig {s}\n", .{version}),
        .already_installed => std.debug.print("zig {s} already installed\n", .{version}),
    }

    if (set_default) {
        std.debug.print("set default zig to {s}\n", .{version});
    }
}

fn handleUninstall(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("usage: zigup uninstall <version>\n", .{});
        return error.InvalidArguments;
    }
    const version = args[0];
    try uninstallZig(allocator, version);
    std.debug.print("removed zig {s}\n", .{version});
}

fn handleUse(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len == 0) {
        std.debug.print("usage: zigup use <version>\n", .{});
        return error.InvalidArguments;
    }
    const version = args[0];
    try setDefaultZig(allocator, version);
    std.debug.print("set default zig to {s}\n", .{version});
}

fn handleList(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var show_installed = true;
    var show_remote = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--remote") or std.mem.eql(u8, arg, "-r")) {
            show_remote = true;
            show_installed = false;
        } else {
            std.debug.print("unknown flag: {s}\n", .{arg});
            return error.InvalidArguments;
        }
    }

    if (show_installed) {
        const installed = try listInstalled(allocator);
        if (installed.versions.len == 0) {
            std.debug.print("  (none)\n", .{});
        } else {
            for (installed.versions) |version| {
                const is_default = if (installed.default) |d| std.mem.eql(u8, d, version) else false;
                const marker: u8 = if (is_default) '*' else ' ';
                std.debug.print("  {c} {s}\n", .{ marker, version });
            }
        }
    }

    if (show_remote) {
        const releases = try fetchReleases(allocator);
        const sorted_versions = try getSortedVersionNames(allocator, releases);

        for (sorted_versions.items) |version_name| {
            std.debug.print("  {s}\n", .{version_name});
        }
    }
}

fn printUsage(file: std.fs.File) !void {
    try file.writeAll(
        \\zigup - Zig version manager
        \\
        \\Usage:
        \\  zigup <command> [options]
        \\
        \\Commands:
        \\  install [version] [-d|--default]  Install a Zig version (default: latest)
        \\                                     Versions: latest, master, stable, or specific (e.g., 0.13.0)
        \\  uninstall <version>                Remove an installed Zig version
        \\  use <version>                      Set a version as default
        \\  list [-r|--remote]                 List installed versions (or available with -r)
        \\
        \\Aliases:
        \\  i = install, rm = uninstall, ls = list
        \\
        \\Examples:
        \\  zigup install latest --default     Install latest and set as default
        \\  zigup install 0.13.0               Install specific version
        \\  zigup use 0.13.0                   Switch to version 0.13.0
        \\  zigup list                         Show installed versions
        \\  zigup list -r                      Show all available versions
        \\
    );
}

const InstallResult = enum { installed, already_installed };

fn installZig(allocator: std.mem.Allocator, version_entry: VersionEntry, version_name: []const u8, set_default: bool) !InstallResult {
    const home = try getHomeDir(allocator);
    const zigup_dir = try std.fs.path.join(allocator, &.{ home, ".zigup" });

    // 获取当前平台字符串
    const platform_str = try getPlatformString(allocator);
    std.debug.print("Platform: {s}\n", .{platform_str});

    // 获取当前平台的信息
    const platform = version_entry.platforms.get(platform_str) orelse {
        std.debug.print("Error: Platform {s} not supported for version {s}\n", .{ platform_str, version_name });
        return error.PlatformNotSupported;
    };

    const version_dir = try std.fs.path.join(allocator, &.{ zigup_dir, "versions", version_name });
    const zig_binary_path = try std.fs.path.join(allocator, &.{ version_dir, "zig" });

    if (fileExists(zig_binary_path)) {
        if (set_default) try setDefaultZig(allocator, version_name);
        return .already_installed;
    }

    const archive_filename = try std.fmt.allocPrint(allocator, "zig-{s}-{s}.tar.xz", .{ platform_str, version_name });
    const cache_dir = try std.fs.path.join(allocator, &.{ zigup_dir, "cache" });
    const archive_path = try std.fs.path.join(allocator, &.{ cache_dir, archive_filename });

    try ensureDir(zigup_dir);
    try ensureDir(cache_dir);

    if (!fileExists(archive_path)) {
        std.debug.print("Downloading {s}...\n", .{platform.tarball});
        try downloadFile(allocator, platform.tarball, archive_path);
        std.debug.print("Verifying checksum...\n", .{});
        try verifyChecksum(allocator, archive_path, platform.shasum);
    } else {
        std.debug.print("Using cached archive: {s}\n", .{archive_path});
    }

    try ensureDir(version_dir);
    std.debug.print("Extracting to {s}...\n", .{version_dir});
    try extractTarXz(allocator, archive_path, version_dir);

    if (set_default) {
        try setDefaultZig(allocator, version_name);
    }

    return .installed;
}

fn uninstallZig(allocator: std.mem.Allocator, version: []const u8) !void {
    const home = try getHomeDir(allocator);
    const zigup_dir = try std.fs.path.join(allocator, &.{ home, ".zigup" });

    const version_dir = try std.fs.path.join(allocator, &.{ zigup_dir, "versions", version });

    std.fs.cwd().deleteTree(version_dir) catch |err| switch (err) {
        error.FileSystem => {},
        else => return err,
    };

    const current_file = try std.fs.path.join(allocator, &.{ zigup_dir, "current" });

    const current = readFile(allocator, current_file) catch null;

    if (current) |c| {
        const trimmed = std.mem.trim(u8, c, " \n\r\t");
        if (std.mem.eql(u8, trimmed, version)) {
            const symlink_path = try std.fs.path.join(allocator, &.{ home, ".local", "bin", "zig" });
            std.fs.cwd().deleteFile(symlink_path) catch {};
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
    const versions_dir = try std.fs.path.join(allocator, &.{ zigup_dir, "versions" });

    var versions = std.array_list.AlignedManaged([]const u8, null).init(allocator);

    var dir = std.fs.cwd().openDir(versions_dir, .{ .iterate = true }) catch |err| switch (err) {
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

const PlatformEntry = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: []const u8,
};

const VersionEntry = struct {
    version: []const u8,
    date: []const u8,
    platforms: std.StringHashMap(PlatformEntry),
};

fn fetchReleases(allocator: std.mem.Allocator) !std.StringHashMap(VersionEntry) {
    const home = try getHomeDir(allocator);
    const cache_path = try std.fs.path.join(allocator, &.{ home, ".zigup", "cache", "index.json" });
    try ensureDir(try std.fs.path.join(allocator, &.{ home, ".zigup", "cache" }));
    try downloadFile(allocator, INDEX_URL, cache_path);
    const data = try readFile(allocator, cache_path);
    var versions = std.StringHashMap(VersionEntry).init(allocator);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    const obj = parsed.value.object;
    var it = obj.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (entry.value_ptr.* == .object) {
            const version_obj = entry.value_ptr.*.object;
            var platforms = std.StringHashMap(PlatformEntry).init(allocator);
            var plat_it = version_obj.iterator();
            while (plat_it.next()) |plat_entry| {
                const plat_key = plat_entry.key_ptr.*;
                const plat_info = plat_entry.value_ptr.*;
                if (plat_info != .object) {
                    continue;
                }
                if (plat_info == .object) {
                    const plat_obj = plat_info.object;
                    const platform = PlatformEntry{
                        .tarball = plat_obj.get("tarball").?.string,
                        .shasum = plat_obj.get("shasum").?.string,
                        .size = plat_obj.get("size").?.string,
                    };
                    try platforms.put(plat_key, platform);
                }
            }
            const version = VersionEntry{
                .version = if (version_obj.get("version")) |v| v.string else key,
                .date = version_obj.get("date").?.string,
                .platforms = platforms,
            };
            try versions.put(key, version);
        }
    }
    return versions;
}

fn getSortedVersionNames(allocator: std.mem.Allocator, releases: std.StringHashMap(VersionEntry)) !std.array_list.AlignedManaged([]const u8, null) {
    var version_names = std.array_list.AlignedManaged([]const u8, null).init(allocator);

    var it = releases.keyIterator();
    while (it.next()) |key| {
        try version_names.append(key.*);
    }

    std.mem.sort([]const u8, version_names.items, {}, versionCompare);
    return version_names;
}

fn findRelease(allocator: std.mem.Allocator, releases: std.StringHashMap(VersionEntry), version: []const u8) !?VersionEntry {
    // 处理 master/latest 别名
    if (std.mem.eql(u8, version, "master") or std.mem.eql(u8, version, "latest")) {
        return releases.get("master");
    }

    // 处理 stable - 返回最新的非 master 版本
    if (std.mem.eql(u8, version, "stable")) {
        var sorted = try getSortedVersionNames(allocator, releases);
        while (sorted.pop()) |ver| {
            if (!std.mem.eql(u8, ver, "master")) {
                return releases.get(ver);
            }
        }
    }

    // 精确版本查找
    return releases.get(version);
}

fn setDefaultZig(allocator: std.mem.Allocator, version: []const u8) !void {
    const home = try getHomeDir(allocator);
    const zigup_dir = try std.fs.path.join(allocator, &.{ home, ".zigup" });

    const zig_binary = try std.fs.path.join(allocator, &.{ zigup_dir, "versions", version, "zig" });

    if (!fileExists(zig_binary)) {
        return error.FileNotFound;
    }

    const local_bin = try std.fs.path.join(allocator, &.{ home, ".local", "bin" });
    try ensureDir(local_bin);

    const symlink_path = try std.fs.path.join(allocator, &.{ local_bin, "zig" });

    std.fs.cwd().deleteFile(symlink_path) catch {};
    try std.posix.symlink(zig_binary, symlink_path);

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

fn getPlatformString(allocator: std.mem.Allocator) ![]const u8 {
    const builtin = @import("builtin");
    const arch = @tagName(builtin.cpu.arch);
    const os = @tagName(builtin.os.tag);
    return try std.fmt.allocPrint(allocator, "{s}-{s}", .{ arch, os });
}

fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn versionCompare(_: void, a: []const u8, b: []const u8) bool {
    // master 始终排在最后
    const a_is_master = std.mem.eql(u8, a, "master");
    const b_is_master = std.mem.eql(u8, b, "master");

    if (a_is_master and b_is_master) return false;
    if (a_is_master) return false; // a 是 master，排在 b 后面
    if (b_is_master) return true; // b 是 master，a 排在 b 前面

    // 按版本号比较：分割并逐段比较
    var a_it = std.mem.splitScalar(u8, a, '.');
    var b_it = std.mem.splitScalar(u8, b, '.');

    while (true) {
        const a_part = a_it.next();
        const b_part = b_it.next();

        // 如果其中一个结束了
        if (a_part == null and b_part == null) return false; // 相等
        if (a_part == null) return true; // a 更短，排前面
        if (b_part == null) return false; // b 更短，a 排后面

        // 尝试解析为数字比较
        const a_num = std.fmt.parseInt(u32, a_part.?, 10) catch {
            // 如果不是数字，按字典序比较（处理 dev 等后缀）
            if (std.mem.eql(u8, a_part.?, b_part.?)) continue;
            return std.mem.lessThan(u8, a_part.?, b_part.?);
        };
        const b_num = std.fmt.parseInt(u32, b_part.?, 10) catch {
            return std.mem.lessThan(u8, a_part.?, b_part.?);
        };

        if (a_num < b_num) return true;
        if (a_num > b_num) return false;
        // 相等则继续下一段
    }
}


test "findRelease - exact version" {
    const allocator = std.testing.allocator;

    var releases = std.StringHashMap(VersionEntry).init(allocator);
    defer releases.deinit();

    var platforms = std.StringHashMap(PlatformEntry).init(allocator);
    defer platforms.deinit();

    const entry = VersionEntry{
        .version = "0.13.0",
        .date = "2024-01-01",
        .platforms = platforms,
    };

    try releases.put("0.13.0", entry);

    const result = try findRelease(allocator, releases, "0.13.0");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("0.13.0", result.?.version);
}

test "findRelease - master/latest alias" {
    const allocator = std.testing.allocator;

    var releases = std.StringHashMap(VersionEntry).init(allocator);
    defer releases.deinit();

    var platforms = std.StringHashMap(PlatformEntry).init(allocator);
    defer platforms.deinit();

    const entry = VersionEntry{
        .version = "master",
        .date = "2024-01-01",
        .platforms = platforms,
    };

    try releases.put("master", entry);

    const result1 = try findRelease(allocator, releases, "master");
    try std.testing.expect(result1 != null);

    const result2 = try findRelease(allocator, releases, "latest");
    try std.testing.expect(result2 != null);
}

test "findRelease - stable returns latest non-master" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var releases = std.StringHashMap(VersionEntry).init(allocator);

    const platforms1 = std.StringHashMap(PlatformEntry).init(allocator);
    const platforms2 = std.StringHashMap(PlatformEntry).init(allocator);
    const platforms3 = std.StringHashMap(PlatformEntry).init(allocator);

    try releases.put("0.11.0", VersionEntry{
        .version = "0.11.0",
        .date = "2023-01-01",
        .platforms = platforms1,
    });

    try releases.put("0.13.0", VersionEntry{
        .version = "0.13.0",
        .date = "2024-01-01",
        .platforms = platforms2,
    });

    try releases.put("master", VersionEntry{
        .version = "master",
        .date = "2024-06-01",
        .platforms = platforms3,
    });

    const result = try findRelease(allocator, releases, "stable");
    try std.testing.expect(result != null);
    try std.testing.expect(!std.mem.eql(u8, result.?.version, "master"));
}
