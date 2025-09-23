const std = @import("std");

const join = std.fs.path.join;

pub const platform_tag = "linux-x86_64";

pub const Paths = struct {
    allocator: std.mem.Allocator,
    root: []u8,
    bin: []u8,
    dist: []u8,
    cache: []u8,
    downloads: []u8,

    pub fn init(allocator: std.mem.Allocator) !Paths {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);

        var cleanup = Cleanup{ .allocator = allocator };
        errdefer cleanup.deinit();

        const root_value = try join(allocator, &.{ home, ".zigup" });
        const root = try cleanup.capture(root_value);
        const bin_value = try join(allocator, &.{ root, "bin" });
        const bin = try cleanup.capture(bin_value);
        const dist_value = try join(allocator, &.{ root, "dist" });
        const dist = try cleanup.capture(dist_value);
        const cache_value = try join(allocator, &.{ root, "cache" });
        const cache = try cleanup.capture(cache_value);
        const downloads_value = try join(allocator, &.{ cache, "downloads" });
        const downloads = try cleanup.capture(downloads_value);

        cleanup.disable();
        return .{
            .allocator = allocator,
            .root = root,
            .bin = bin,
            .dist = dist,
            .cache = cache,
            .downloads = downloads,
        };
    }

    pub fn deinit(self: *Paths) void {
        const allocator = self.allocator;
        allocator.free(self.root);
        allocator.free(self.bin);
        allocator.free(self.dist);
        allocator.free(self.cache);
        allocator.free(self.downloads);
        self.* = undefined;
    }

    pub fn ensure(self: *const Paths) !void {
        const cwd = std.fs.cwd();
        try cwd.makePath(self.root);
        try cwd.makePath(self.bin);
        try cwd.makePath(self.dist);
        try cwd.makePath(self.cache);
        try cwd.makePath(self.downloads);
    }

    pub fn joinOwned(self: *const Paths, allocator: std.mem.Allocator, components: []const []const u8) ![]u8 {
        _ = self;
        return join(allocator, components);
    }

    pub fn distVersionDir(self: *const Paths, allocator: std.mem.Allocator, version: []const u8) ![]u8 {
        return self.joinOwned(allocator, &.{ self.dist, version });
    }

    pub fn distPlatformDir(self: *const Paths, allocator: std.mem.Allocator, version: []const u8) ![]u8 {
        return self.joinOwned(allocator, &.{ self.dist, version, platform_tag });
    }

    pub fn zigBinaryPath(self: *const Paths, allocator: std.mem.Allocator, version: []const u8) ![]u8 {
        return self.joinOwned(allocator, &.{ self.dist, version, platform_tag, "zig" });
    }

    pub fn shimZigPath(self: *const Paths, allocator: std.mem.Allocator) ![]u8 {
        return self.joinOwned(allocator, &.{ self.bin, "zig" });
    }

    pub fn currentVersionFile(self: *const Paths, allocator: std.mem.Allocator) ![]u8 {
        return self.joinOwned(allocator, &.{ self.root, "current" });
    }

    pub fn archiveCachePath(self: *const Paths, allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
        return self.joinOwned(allocator, &.{ self.downloads, filename });
    }
};

const Cleanup = struct {
    allocator: std.mem.Allocator,
    allocations: std.ArrayListUnmanaged([]u8) = .empty,
    active: bool = true,

    fn capture(self: *Cleanup, slice: []u8) ![]u8 {
        if (!self.active) return slice;
        errdefer self.allocator.free(slice);
        try self.allocations.append(self.allocator, slice);
        return slice;
    }

    fn disable(self: *Cleanup) void {
        self.active = false;
        self.allocations.deinit(self.allocator);
    }

    fn deinit(self: *Cleanup) void {
        if (!self.active) return;
        for (self.allocations.items) |item| {
            self.allocator.free(item);
        }
        self.allocations.deinit(self.allocator);
    }
};
