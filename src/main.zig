const std = @import("std");
const runner = @import("cli/runner.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();

    try runner.run(gpa_state.allocator());
}
