const std = @import("std");
const Paths = @import("../core/paths.zig").Paths;
const archive = @import("../fs/archive.zig");
const download = @import("../net/download.zig");

const Sha256 = std.crypto.hash.sha2.Sha256;

pub const InstallError = error{FileNotFound} || download.DownloadError || archive.ExtractError || std.fs.Dir.DeleteTreeError || std.fs.Dir.MakeError || std.fs.Dir.StatFileError || std.fs.Dir.DeleteFileError || std.posix.SymLinkError || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

pub const UninstallError = std.fs.Dir.DeleteTreeError || std.fs.Dir.DeleteFileError || std.mem.Allocator.Error;

const latest_version = "latest";
const archive_filename = "zls-latest-linux-x86_64.tar.xz";
const download_url = "https://github.com/zigtools/zls/releases/latest/download/zls-x86_64-linux-gnu.tar.xz";

pub fn installLatest(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    paths: *const Paths,
) InstallError!void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const zls_dir = try paths.zlsVersionDir(a, latest_version);
    const shim_path = try paths.shimZlsPath(a);
    const archive_path = try paths.archiveCachePath(a, archive_filename);

    if (try locateExistingBinary(allocator, zls_dir)) |existing| {
        allocator.free(existing);
        try ensureShim(allocator, zls_dir, shim_path);
        return;
    }

    try download.fetchToFile(allocator, client, download_url, archive_path);

    std.fs.cwd().deleteTree(zls_dir) catch |err| switch (err) {
        error.FileSystem => {},
        else => return err,
    };
    try std.fs.cwd().makePath(zls_dir);
    try archive.extractTarXz(allocator, archive_path, zls_dir, 1);

    const binary_path = try locateBinary(allocator, zls_dir);
    defer allocator.free(binary_path);

    try ensureShimWithBinary(shim_path, binary_path);
}

pub fn uninstallLatest(
    allocator: std.mem.Allocator,
    paths: *const Paths,
) UninstallError!void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const zls_dir = try paths.zlsVersionDir(a, latest_version);
    const shim_path = try paths.shimZlsPath(a);

    std.fs.cwd().deleteTree(zls_dir) catch |err| switch (err) {
        error.FileSystem => {},
        else => return err,
    };

    std.fs.cwd().deleteFile(shim_path) catch |err| switch (err) {
        error.FileSystem => {},
        else => return err,
    };
}

fn ensureShim(allocator: std.mem.Allocator, zls_dir: []const u8, shim_path: []const u8) !void {
    const binary_path = try locateBinary(allocator, zls_dir);
    defer allocator.free(binary_path);
    try ensureShimWithBinary(shim_path, binary_path);
}

fn ensureShimWithBinary(shim_path: []const u8, binary_path: []const u8) !void {
    std.fs.cwd().deleteFile(shim_path) catch |err| switch (err) {
        error.FileSystem => {},
        else => return err,
    };
    try std.fs.cwd().symLink(binary_path, shim_path, .{});
}

fn locateExistingBinary(allocator: std.mem.Allocator, zls_dir: []const u8) !?[]u8 {
    if (!dirExists(zls_dir)) return null;
    return locateBinary(allocator, zls_dir) catch |err| switch (err) {
        else => return null,
    };
}

fn locateBinary(allocator: std.mem.Allocator, base_dir: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const candidate_bin = try std.fs.path.join(a, &.{ base_dir, "bin", "zls" });
    if (fileExists(candidate_bin)) {
        return try allocator.dupe(u8, candidate_bin);
    }

    const candidate_root = try std.fs.path.join(a, &.{ base_dir, "zls" });
    if (fileExists(candidate_root)) {
        return try allocator.dupe(u8, candidate_root);
    }

    // Fallback: search for executable named "zls" in directory tree (depth 2)
    var dir = try std.fs.cwd().openDir(base_dir, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.name.len == 0) continue;
        const path = try std.fs.path.join(a, &.{ base_dir, entry.name });
        if (entry.kind == .file and std.mem.eql(u8, entry.name, "zls")) {
            if (fileExists(path)) return try allocator.dupe(u8, path);
        } else if (entry.kind == .directory) {
            var sub = try std.fs.cwd().openDir(path, .{ .iterate = true });
            defer sub.close();
            var sub_it = sub.iterate();
            while (try sub_it.next()) |sub_entry| {
                if (std.mem.eql(u8, sub_entry.name, "zls")) {
                    const sub_path = try std.fs.path.join(a, &.{ path, sub_entry.name });
                    if (fileExists(sub_path)) {
                        return try allocator.dupe(u8, sub_path);
                    }
                }
            }
        }
    }

    return error.FileNotFound;
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn dirExists(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}
