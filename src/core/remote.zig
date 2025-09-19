const std = @import("std");
const download = @import("../net/download.zig");
const Paths = @import("paths.zig").Paths;

pub const index_url = "https://ziglang.org/download/index.json";
const cache_filename = "index.json";
const max_index_size: usize = 16 * 1024 * 1024;
const cache_ttl_ns: i128 = (@as(i128, std.time.ns_per_hour) * 6);

pub const ReleaseKind = enum { stable, dev, master };

pub const Release = struct {
    tag: []u8,
    version: []u8,
    kind: ReleaseKind,
    tarball_url: []u8,
    tarball_filename: []u8,
    sha256: ?[]u8,
    size: ?u64,
};

pub const Index = struct {
    allocator: std.mem.Allocator,
    releases: []Release,
    latest_stable_idx: ?usize,
    master_idx: ?usize,

    pub fn deinit(self: *Index) void {
        const allocator = self.allocator;
        for (self.releases) |release| {
            allocator.free(release.tag);
            allocator.free(release.version);
            allocator.free(release.tarball_url);
            allocator.free(release.tarball_filename);
            if (release.sha256) |hash| allocator.free(hash);
        }
        allocator.free(self.releases);
        self.* = undefined;
    }

    pub fn find(self: *const Index, version: []const u8) ?*const Release {
        for (self.releases) |*rel| {
            if (std.mem.eql(u8, rel.version, version) or std.mem.eql(u8, rel.tag, version)) {
                return rel;
            }
        }
        return null;
    }

    pub fn latestStable(self: *const Index) ?*const Release {
        return if (self.latest_stable_idx) |idx| &self.releases[idx] else null;
    }

    pub fn master(self: *const Index) ?*const Release {
        return if (self.master_idx) |idx| &self.releases[idx] else null;
    }
};

pub const FetchIndexError = error{
    InvalidIndex,
    FileTooBig,
} || download.DownloadError || std.json.ParseError(std.json.Scanner) || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.Dir.StatFileError || std.mem.Allocator.Error;

pub fn fetchIndex(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    paths: *const Paths,
) FetchIndexError!Index {
    const index_path = try paths.joinOwned(allocator, &.{ paths.cache, cache_filename });
    defer allocator.free(index_path);

    var use_cached = false;
    if (std.fs.cwd().statFile(index_path)) |stat| {
        const now = std.time.nanoTimestamp();
        if (now != 0) {
            const age = now - stat.mtime;
            if (age >= 0 and age <= cache_ttl_ns) {
                use_cached = true;
            }
        } else {
            use_cached = true;
        }
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    if (!use_cached) {
        try download.fetchToFile(allocator, client, index_url, index_path);
    }

    const data = try std.fs.cwd().readFileAlloc(index_path, allocator, std.Io.Limit.limited(max_index_size));
    defer allocator.free(data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, data, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidIndex;

    var releases = std.array_list.AlignedManaged(Release, null).init(allocator);
    errdefer {
        for (releases.items) |release| {
            allocator.free(release.tag);
            allocator.free(release.version);
            allocator.free(release.tarball_url);
            allocator.free(release.tarball_filename);
            if (release.sha256) |hash| allocator.free(hash);
        }
        releases.deinit();
    }

    var latest_stable_idx: ?usize = null;
    var latest_stable_version: ?std.SemanticVersion = null;
    var master_idx: ?usize = null;

    var iter = parsed.value.object.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        if (value != .object) continue;
        const release_object = value.object;

        const version_value = release_object.get("version") orelse continue;
        if (version_value != .string) continue;
        const version_str = version_value.string;

        const platform_object = findPreferredPlatformObject(release_object) orelse continue;

        const tarball_value = platform_object.get("tarball") orelse continue;
        if (tarball_value != .string) continue;
        const tarball_url = tarball_value.string;

        const sha256_value = platform_object.get("sha256") orelse platform_object.get("shasum") orelse platform_object.get("hash") orelse platform_object.get("tarball_hash");
        const size_value = platform_object.get("size");

        const release = try createRelease(allocator, key, version_str, tarball_url, sha256_value, size_value);
        try releases.append(release);
        const idx = releases.items.len - 1;

        switch (release.kind) {
            .master => master_idx = idx,
            .stable => {
                const parsed_semver = std.SemanticVersion.parse(release.version) catch null;
                if (parsed_semver) |sem| {
                    if (latest_stable_version) |current| {
                        if (sem.order(current) == .gt) {
                            latest_stable_version = sem;
                            latest_stable_idx = idx;
                        }
                    } else {
                        latest_stable_version = sem;
                        latest_stable_idx = idx;
                    }
                }
            },
            .dev => {},
        }
    }

    const owned_releases = try releases.toOwnedSlice();
    releases.deinit();
    return .{
        .allocator = allocator,
        .releases = owned_releases,
        .latest_stable_idx = latest_stable_idx,
        .master_idx = master_idx,
    };
}

fn createRelease(
    allocator: std.mem.Allocator,
    tag: []const u8,
    version: []const u8,
    tarball_url: []const u8,
    sha256_value: ?std.json.Value,
    size_value: ?std.json.Value,
) !Release {
    const tag_copy = try allocator.dupe(u8, tag);
    errdefer allocator.free(tag_copy);

    const version_copy = try allocator.dupe(u8, version);
    errdefer allocator.free(version_copy);

    const url_copy = try allocator.dupe(u8, tarball_url);
    errdefer allocator.free(url_copy);

    const filename = std.fs.path.basename(tarball_url);
    const filename_copy = try allocator.dupe(u8, filename);
    errdefer allocator.free(filename_copy);

    var sha_copy: ?[]u8 = null;
    if (sha256_value) |sv| {
        if (sv == .string) {
            const hash_copy = try allocator.dupe(u8, sv.string);
            errdefer allocator.free(hash_copy);
            sha_copy = hash_copy;
        }
    }

    var size_copy: ?u64 = null;
    if (size_value) |sv| {
        switch (sv) {
            .string => size_copy = std.fmt.parseInt(u64, sv.string, 10) catch null,
            .integer => {
                if (sv.integer >= 0) {
                    size_copy = @as(u64, @intCast(sv.integer));
                }
            },
            .float => {
                if (sv.float >= 0) {
                    size_copy = @as(u64, @intFromFloat(sv.float));
                }
            },
            else => {},
        }
    }

    const kind = detectKind(tag, version);
    return Release{
        .tag = tag_copy,
        .version = version_copy,
        .kind = kind,
        .tarball_url = url_copy,
        .tarball_filename = filename_copy,
        .sha256 = sha_copy,
        .size = size_copy,
    };
}

pub fn kindName(kind: ReleaseKind) []const u8 {
    return switch (kind) {
        .stable => "stable",
        .dev => "dev",
        .master => "master",
    };
}

fn detectKind(tag: []const u8, version: []const u8) ReleaseKind {
    if (std.mem.eql(u8, tag, "master")) return .master;
    if (std.mem.indexOf(u8, version, "-") != null) return .dev;
    return .stable;
}

fn findPreferredPlatformObject(release_object: std.json.ObjectMap) ?std.json.ObjectMap {
    const platform_keys = platformKeyCandidates();

    for (platform_keys) |key| {
        const platform_value = release_object.get(key) orelse continue;
        if (platform_value == .object) {
            return platform_value.object;
        }
    }

    return null;
}

fn platformKeyCandidates() []const []const u8 {
    const builtin = @import("builtin");
    return switch (builtin.target.os.tag) {
        .linux => linuxPlatformKeys(builtin.target.cpu.arch, builtin.target.abi),
        .macos => macosPlatformKeys(builtin.target.cpu.arch),
        .windows => windowsPlatformKeys(builtin.target.cpu.arch),
        else => empty_platform_keys[0..],
    };
}

fn linuxPlatformKeys(comptime arch: std.Target.Cpu.Arch, comptime abi: std.Target.Abi) []const []const u8 {
    return switch (arch) {
        .x86_64 => if (abi == .musl)
            linux_x86_64_musl_first_keys[0..]
        else
            linux_x86_64_preferred_keys[0..],
        .aarch64 => if (abi == .musl)
            linux_aarch64_musl_first_keys[0..]
        else
            linux_aarch64_preferred_keys[0..],
        else => empty_platform_keys[0..],
    };
}

fn macosPlatformKeys(comptime arch: std.Target.Cpu.Arch) []const []const u8 {
    return switch (arch) {
        .aarch64 => macos_aarch64_keys[0..],
        .x86_64 => macos_x86_64_keys[0..],
        else => empty_platform_keys[0..],
    };
}

fn windowsPlatformKeys(comptime arch: std.Target.Cpu.Arch) []const []const u8 {
    return switch (arch) {
        .aarch64 => windows_aarch64_keys[0..],
        .x86_64 => windows_x86_64_keys[0..],
        else => empty_platform_keys[0..],
    };
}

const linux_x86_64_preferred_keys = [_][]const u8{
    "x86_64-linux-gnu",
    "x86_64-linux-musl",
    "x86_64-linux",
};

const linux_x86_64_musl_first_keys = [_][]const u8{
    "x86_64-linux-musl",
    "x86_64-linux-gnu",
    "x86_64-linux",
};

const linux_aarch64_preferred_keys = [_][]const u8{
    "aarch64-linux-gnu",
    "aarch64-linux-musl",
    "aarch64-linux",
};

const linux_aarch64_musl_first_keys = [_][]const u8{
    "aarch64-linux-musl",
    "aarch64-linux-gnu",
    "aarch64-linux",
};

const macos_x86_64_keys = [_][]const u8{
    "x86_64-macos",
    "universal-macos",
};

const macos_aarch64_keys = [_][]const u8{
    "aarch64-macos",
    "universal-macos",
};

const windows_x86_64_keys = [_][]const u8{
    "x86_64-windows",
    "x86_64-windows-gnu",
};

const windows_aarch64_keys = [_][]const u8{
    "aarch64-windows",
};

const empty_platform_keys = [_][]const u8{};
