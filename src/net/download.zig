const std = @import("std");

pub const DownloadError = error{
    HttpStatusNotOk,
} || std.fs.File.OpenError || std.fs.File.WriteError || std.http.Client.FetchError || std.fs.Dir.DeleteFileError || std.fs.Dir.RenameError || std.mem.Allocator.Error;

pub fn fetchToFile(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    url: []const u8,
    dest_path: []const u8,
) DownloadError!void {
    if (std.fs.path.dirname(dest_path)) |parent| {
        try std.fs.cwd().makePath(parent);
    }

    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.part", .{dest_path});
    defer allocator.free(tmp_path);

    var file = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true });

    const redirect_buffer = try allocator.alloc(u8, 8 * 1024);
    defer allocator.free(redirect_buffer);

    var response_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(&response_buffer);
    const fetch_result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &file_writer.interface,
        .redirect_buffer = redirect_buffer,
    });
    try file_writer.interface.flush();

    if (fetch_result.status != .ok) {
        return error.HttpStatusNotOk;
    }

    file.close();

    std.fs.cwd().deleteFile(dest_path) catch |err| {
        switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    };

    try std.fs.cwd().rename(tmp_path, dest_path);
}
