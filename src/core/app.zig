const std = @import("std");
const Paths = @import("paths.zig").Paths;
const remote = @import("remote.zig");
const installer = @import("install.zig");
const list_mod = @import("list.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    paths: Paths,
    http_client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) !App {
        var paths = try Paths.init(allocator);
        errdefer paths.deinit();
        try paths.ensure();

        const client = std.http.Client{ .allocator = allocator };
        return .{ .allocator = allocator, .paths = paths, .http_client = client };
    }

    pub fn deinit(self: *App) void {
        self.http_client.deinit();
        self.paths.deinit();
        self.* = undefined;
    }

    pub fn installZig(self: *App, release: *const remote.Release, options: installer.InstallOptions) !installer.InstallResult {
        return installer.installVersion(self.allocator, &self.http_client, &self.paths, release, options);
    }

    pub fn uninstallZig(self: *App, version: []const u8) !void {
        try installer.uninstallVersion(self.allocator, &self.paths, version);
    }

    pub fn listInstalled(self: *App) ![]list_mod.InstalledVersion {
        return list_mod.loadInstalled(self.allocator, &self.paths);
    }

    pub fn fetchRemoteIndex(self: *App) !remote.Index {
        return remote.fetchIndex(self.allocator, &self.http_client, &self.paths);
    }

};
