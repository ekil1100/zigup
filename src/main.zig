const std = @import("std");
const zigup = @import("zigup.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();

    try zigup.run(gpa_state.allocator());
}
