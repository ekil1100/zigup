const std = @import("std");
const Paths = @import("paths.zig").Paths;
const install = @import("install.zig");
const remote = @import("remote.zig");

pub const InstalledVersion = struct {
    version: []u8,
    is_default: bool,

    pub fn deinit(self: InstalledVersion, allocator: std.mem.Allocator) void {
        allocator.free(self.version);
    }
};

pub const LoadInstalledError = error{ FileTooBig, StreamTooLong } || std.fs.Dir.OpenError || std.fs.Dir.Iterator.Error || std.fs.Dir.StatFileError || std.mem.Allocator.Error || std.fs.File.OpenError || std.fs.File.ReadError;

pub fn loadInstalled(
    allocator: std.mem.Allocator,
    paths: *const Paths,
) LoadInstalledError![]InstalledVersion {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const current_file = try paths.currentVersionFile(a);
    const current_version_opt = try install.readCurrentVersion(allocator, current_file);
    defer if (current_version_opt) |slice| allocator.free(slice);

    var list = std.array_list.AlignedManaged(InstalledVersion, null).init(allocator);
    errdefer {
        for (list.items) |item| item.deinit(allocator);
        list.deinit();
    }

    var dist_dir = try std.fs.cwd().openDir(paths.dist, .{ .iterate = true });
    defer dist_dir.close();

    var iterator = dist_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .directory) continue;
        if (entry.name.len == 0) continue;

        const platform_dir = try paths.joinOwned(a, &.{ paths.dist, entry.name, @import("paths.zig").platform_tag });
        if (!dirExists(platform_dir)) continue;

        const version_copy = try allocator.dupe(u8, entry.name);
        var version_retained = false;
        defer if (!version_retained) allocator.free(version_copy);

        const is_default = if (current_version_opt) |current| std.mem.eql(u8, current, entry.name) else false;
        try list.append(.{ .version = version_copy, .is_default = is_default });
        version_retained = true;
    }

    std.mem.sort(InstalledVersion, list.items, {}, installedLessThan);

    const owned = try list.toOwnedSlice();
    list.deinit();
    return owned;
}

fn dirExists(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

fn installedLessThan(_: void, lhs: InstalledVersion, rhs: InstalledVersion) bool {
    return std.mem.lessThan(u8, lhs.version, rhs.version);
}
