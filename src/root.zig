const std = @import("std");

pub const App = @import("core/app.zig").App;
pub const Paths = @import("core/paths.zig").Paths;
pub const remote = @import("core/remote.zig");
pub const installer = @import("core/install.zig");
pub const list = @import("core/list.zig");

test "paths initialization" {
    var gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer gpa.deinit();
    const allocator = gpa.allocator();

    var paths = try Paths.init(allocator);
    defer paths.deinit();
    try std.testing.expect(paths.root.len > 0);
}
