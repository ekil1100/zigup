const std = @import("std");

pub const ExtractError = error{
    TarExtractionFailed,
    NotXzStream,
    ReadFailed,
    EndOfStream,
    WrongChecksum,
    WriteFailed,
    Overflow,
    StreamTooLong,
    InvalidCharacter,
    UnexpectedEndOfStream,
    TarHeader,
    TarHeaderChksum,
    TarNumericValueNegative,
    TarNumericValueTooBig,
    TarInsufficientBuffer,
    PaxNullInKeyword,
    PaxInvalidAttributeEnd,
    PaxSizeAttrOverflow,
    PaxNullInValue,
    TarHeadersTooBig,
    TarUnsupportedHeader,
    TarComponentsOutsideStrippedPrefix,
    UnableToCreateSymLink,
} || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.Dir.MakeError || std.fs.Dir.OpenError || std.mem.Allocator.Error;

pub fn extractTarXz(
    allocator: std.mem.Allocator,
    archive_path: []const u8,
    dest_dir: []const u8,
    strip_components: u32,
) ExtractError!void {
    var file = try std.fs.cwd().openFile(archive_path, .{ .mode = .read_only });
    defer file.close();

    const read_buffer = try allocator.alloc(u8, 64 * 1024);
    defer allocator.free(read_buffer);

    var file_reader = file.reader(read_buffer);
    
    const decompress_buffer = try allocator.alloc(u8, 64 * 1024);
    errdefer allocator.free(decompress_buffer);
    
    var decompress = try std.compress.xz.Decompress.init(&file_reader.interface, allocator, decompress_buffer);
    defer decompress.deinit();

    const tar_reader = &decompress.reader;

    var destination = try std.fs.cwd().makeOpenPath(dest_dir, .{});
    defer destination.close();

    var diagnostics = std.tar.Diagnostics{ .allocator = allocator };
    defer diagnostics.deinit();

    try std.tar.pipeToFileSystem(destination, tar_reader, .{
        .strip_components = strip_components,
        .diagnostics = &diagnostics,
    });

    if (diagnostics.errors.items.len > 0) {
        return error.TarExtractionFailed;
    }
}
