const std = @import("std");
const zigup = @import("zigup.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try zigup.run(arena.allocator());
}
