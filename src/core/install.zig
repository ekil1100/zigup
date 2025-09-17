const std = @import("std");
const Paths = @import("paths.zig").Paths;
const remote = @import("remote.zig");
const archive = @import("../fs/archive.zig");
const download = @import("../net/download.zig");

const Sha256 = std.crypto.hash.sha2.Sha256;

pub const InstallResult = enum { installed, already_installed };

pub const InstallOptions = struct {
    set_default: bool = false,
};

pub const InstallError = error{
    HashMismatch,
    FileNotFound,
    StreamTooLong,
} || download.DownloadError || archive.ExtractError || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.Dir.DeleteTreeError || std.fs.Dir.MakeError || std.fs.Dir.StatFileError || std.fs.Dir.DeleteFileError || std.posix.SymLinkError || std.mem.Allocator.Error;

pub const UninstallError = error{ FileTooBig, StreamTooLong } || std.fs.Dir.DeleteTreeError || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.Dir.DeleteFileError || std.mem.Allocator.Error;

pub fn installVersion(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    paths: *const Paths,
    release: *const remote.Release,
    options: InstallOptions,
) InstallError!InstallResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const zig_binary_path = try paths.zigBinaryPath(a, release.version);
    if (fileExists(zig_binary_path)) {
        if (options.set_default) try setDefault(allocator, paths, release.version);
        return .already_installed;
    }

    const archive_path = try paths.archiveCachePath(a, release.tarball_filename);
    try ensureArchive(allocator, client, archive_path, release);

    try extractRelease(allocator, paths, release.version, archive_path);

    if (options.set_default) {
        try setDefault(allocator, paths, release.version);
    }

    return .installed;
}

pub fn uninstallVersion(
    allocator: std.mem.Allocator,
    paths: *const Paths,
    version: []const u8,
) UninstallError!void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const version_dir = try paths.distVersionDir(a, version);
    std.fs.cwd().deleteTree(version_dir) catch |err| switch (err) {
        error.FileSystem => {},
        else => return err,
    };

    const current_file = try paths.currentVersionFile(a);
    const shim_path = try paths.shimZigPath(a);

    const current = try readCurrentVersion(allocator, current_file);
    defer if (current) |slice| allocator.free(slice);

    if (current) |slice| {
        if (std.mem.eql(u8, slice, version)) {
            std.fs.cwd().deleteFile(shim_path) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
            std.fs.cwd().deleteFile(current_file) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }
    }
}

pub fn setDefault(
    allocator: std.mem.Allocator,
    paths: *const Paths,
    version: []const u8,
) InstallError!void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const zig_binary_path = try paths.zigBinaryPath(a, version);
    if (!fileExists(zig_binary_path)) {
        return error.FileNotFound;
    }

    const shim_path = try paths.shimZigPath(a);
    std.fs.cwd().deleteFile(shim_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    try std.fs.cwd().symLink(zig_binary_path, shim_path, .{});

    const current_file = try paths.currentVersionFile(a);
    {
        var file = try std.fs.cwd().createFile(current_file, .{ .truncate = true });
        defer file.close();
        try file.writeAll(version);
        try file.writeAll("\n");
    }
}

fn ensureArchive(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    archive_path: []const u8,
    release: *const remote.Release,
) InstallError!void {
    var needs_download = true;
    if (fileExists(archive_path)) {
        if (release.sha256) |expected| {
            if (verifyHash(archive_path, expected)) {
                needs_download = false;
            } else {
                std.fs.cwd().deleteFile(archive_path) catch |err| switch (err) {
                    error.FileNotFound => {},
                    else => return err,
                };
            }
        } else {
            needs_download = false;
        }
    }

    if (needs_download) {
        try download.fetchToFile(allocator, client, release.tarball_url, archive_path);
    }

    if (release.sha256) |expected| {
        if (!verifyHash(archive_path, expected)) {
            return error.HashMismatch;
        }
    }
}

fn extractRelease(
    allocator: std.mem.Allocator,
    paths: *const Paths,
    version: []const u8,
    archive_path: []const u8,
) InstallError!void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const version_dir = try paths.distVersionDir(a, version);
    const platform_dir = try paths.distPlatformDir(a, version);

    std.fs.cwd().deleteTree(version_dir) catch |err| switch (err) {
        error.FileSystem => {},
        else => return err,
    };
    try std.fs.cwd().makePath(platform_dir);
    try archive.extractTarXz(allocator, archive_path, platform_dir, 1);
}

fn verifyHash(
    archive_path: []const u8,
    expected_hash: []const u8,
) bool {
    var expected_buf: [Sha256.digest_length * 2]u8 = undefined;
    const normalized = normalizeHashInto(expected_hash, &expected_buf) catch return false;

    const actual_hex = computeSha256Hex(archive_path) catch return false;
    if (normalized.len != actual_hex.len) return false;
    return std.mem.eql(u8, normalized, actual_hex[0..normalized.len]);
}

fn normalizeHashInto(raw: []const u8, buf: *[Sha256.digest_length * 2]u8) ![]const u8 {
    var trimmed = std.mem.trim(u8, raw, " \t\n\r");
    if (std.mem.startsWith(u8, trimmed, "sha256:")) {
        trimmed = trimmed[7..];
    } else if (std.mem.startsWith(u8, trimmed, "SHA256:")) {
        trimmed = trimmed[7..];
    }
    if (trimmed.len > buf.len) return error.HashMismatch;
    var idx: usize = 0;
    while (idx < trimmed.len) : (idx += 1) {
        buf[idx] = std.ascii.toLower(trimmed[idx]);
    }
    return buf[0..trimmed.len];
}

fn computeSha256Hex(path: []const u8) ![Sha256.digest_length * 2]u8 {
    var file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    var hasher = Sha256.init(.{});
    var buffer: [64 * 1024]u8 = undefined;
    while (true) {
        const read = try file.read(&buffer);
        if (read == 0) break;
        hasher.update(buffer[0..read]);
    }
    var digest: [Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);

    var hex: [Sha256.digest_length * 2]u8 = undefined;
    const hex_slice = std.fmt.bytesToHex(digest, .lower);
    @memcpy(&hex, &hex_slice);
    return hex;
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn readCurrentVersion(
    allocator: std.mem.Allocator,
    current_file: []const u8,
) !?[]u8 {
    const data = std.fs.cwd().readFileAlloc(current_file, allocator, std.Io.Limit.limited(4096)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(data);

    const trimmed = std.mem.trim(u8, data, " \t\n\r");
    if (trimmed.len == 0) return null;
    return try allocator.dupe(u8, trimmed);
}
