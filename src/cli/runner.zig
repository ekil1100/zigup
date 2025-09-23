const std = @import("std");
const App = @import("../core/app.zig").App;
const remote = @import("../core/remote.zig");

pub fn run(allocator: std.mem.Allocator) !void {
    const stdout_file = std.fs.File.stdout();
    const stderr_file = std.fs.File.stderr();

    var app = try App.init(allocator);
    defer app.deinit();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len <= 1) {
        try printUsage(app.allocator, stdout_file);
        return;
    }

    const command = std.mem.sliceTo(args[1], 0);
    const rest_raw = args[2..];
    var rest = try allocator.alloc([]const u8, rest_raw.len);
    defer allocator.free(rest);
    for (rest_raw, 0..) |arg, idx| rest[idx] = std.mem.sliceTo(arg, 0);

    if (std.mem.eql(u8, command, "install")) {
        try handleInstall(&app, rest, stdout_file, stderr_file);
    } else if (std.mem.eql(u8, command, "uninstall")) {
        try handleUninstall(&app, rest, stdout_file, stderr_file);
    } else if (std.mem.eql(u8, command, "list")) {
        try handleList(&app, rest, stdout_file, stderr_file);
    } else {
        try printAlloc(app.allocator, stderr_file, "unknown command: {s}\n", .{command});
        try printUsage(app.allocator, stderr_file);
        return error.InvalidCommand;
    }
}

fn handleInstall(app: *App, args: [][]const u8, stdout_file: std.fs.File, stderr_file: std.fs.File) !void {
    var set_default = false;
    var version: []const u8 = "latest";

    if (args.len > 0) {
        version = args[0];
    }

    var idx: usize = if (std.mem.eql(u8, version, "--default")) blk: {
        set_default = true;
        version = "latest";
        break :blk 1;
    } else 1;

    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--default")) {
            set_default = true;
        } else {
            version = arg;
        }
    }

    var index = try app.fetchRemoteIndex();
    defer index.deinit();

    const release = resolveRelease(&index, version) catch {
        try printAlloc(app.allocator, stderr_file, "unknown version: {s}\n", .{version});
        return error.InvalidArguments;
    };

    const result = try app.installZig(release, .{ .set_default = set_default });
    switch (result) {
        .installed => try printAlloc(app.allocator, stdout_file, "installed zig {s}\n", .{release.version}),
        .already_installed => try printAlloc(app.allocator, stdout_file, "zig {s} already installed\n", .{release.version}),
    }

    if (set_default) {
        try printAlloc(app.allocator, stdout_file, "set default zig to {s}\n", .{release.version});
    }
}

fn handleUninstall(app: *App, args: [][]const u8, stdout_file: std.fs.File, stderr_file: std.fs.File) !void {
    if (args.len == 0) {
        try printAlloc(app.allocator, stderr_file, "usage: zigup uninstall <version>\n", .{});
        return error.InvalidArguments;
    }
    const version = args[0];
    try app.uninstallZig(version);
    try printAlloc(app.allocator, stdout_file, "removed zig {s}\n", .{version});
}

fn handleList(app: *App, args: [][]const u8, stdout_file: std.fs.File, stderr_file: std.fs.File) !void {
    var show_installed = true;
    var show_remote = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--remote")) {
            show_remote = true;
            show_installed = false;
        } else if (std.mem.eql(u8, arg, "--installed")) {
            show_installed = true;
        } else {
            try printAlloc(app.allocator, stderr_file, "unknown flag: {s}\n", .{arg});
            return error.InvalidArguments;
        }
    }

    if (!show_installed and !show_remote) show_installed = true;

    if (show_installed) {
        const installed = try app.listInstalled();
        defer {
            for (installed) |item| item.deinit(app.allocator);
            app.allocator.free(installed);
        }
        try printAlloc(app.allocator, stdout_file, "Installed versions:\n", .{});
        if (installed.len == 0) {
            try printAlloc(app.allocator, stdout_file, "  (none)\n", .{});
        } else {
            for (installed) |item| {
                const marker: u8 = if (item.is_default) '*' else ' ';
                try printAlloc(app.allocator, stdout_file, "  {c} {s}\n", .{ marker, item.version });
            }
        }
    }

    if (show_remote) {
        var index = try app.fetchRemoteIndex();
        defer index.deinit();
        try printAlloc(app.allocator, stdout_file, "Available releases:\n", .{});
        for (index.releases) |release| {
            try printAlloc(app.allocator, stdout_file, "  {s:10} ({s}) - {s}\n", .{
                release.version,
                remote.kindName(release.kind),
                release.tarball_url,
            });
        }
    }
}


fn resolveRelease(index: *const remote.Index, version: []const u8) !*const remote.Release {
    if (std.mem.eql(u8, version, "latest") or std.mem.eql(u8, version, "stable")) {
        if (index.latestStable()) |rel| return rel;
        return error.InvalidArguments;
    }
    if (std.mem.eql(u8, version, "master") or std.mem.eql(u8, version, "dev")) {
        if (index.master()) |rel| return rel;
        return error.InvalidArguments;
    }
    if (index.find(version)) |rel| return rel;
    return error.InvalidArguments;
}

fn printUsage(allocator: std.mem.Allocator, file: std.fs.File) !void {
    try printAlloc(
        allocator,
        file,
        "zigup commands:\n" ++
            "  install [version] [--default]   Install a Zig release (default latest).\n" ++
            "  uninstall <version>             Remove an installed Zig release.\n" ++
            "  list [--installed|--remote]     Show installed or remote Zig versions.\n",
        .{},
    );
}

fn printAlloc(allocator: std.mem.Allocator, file: std.fs.File, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try file.writeAll(text);
}
