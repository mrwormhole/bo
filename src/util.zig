//! Utilities ported from util.c

const std = @import("std");
const c = @import("cstd.zig");

const types = @import("types.zig");

fn srcStartsWith(s: [*:0]const u8, needle: []const u8) bool {
    if (needle.len == 0) return false;
    for (needle, 0..) |b, i| {
        if (s[i] != b) return false;
    }
    return true;
}

fn dstEndsWith(d: [*]const u8, start: [*]const u8, needle: []const u8) bool {
    if (needle.len == 0) return false;
    if (@intFromPtr(d) < @intFromPtr(start) + needle.len) return false;
    const tail = d - needle.len;
    for (needle, 0..) |b, i| {
        if (tail[i] != b) return false;
    }
    return true;
}

// Copies src into dst up to end, skipping a leading `sep` sequence in the
// remaining src whenever dst already ends with `sep` (deduplicates the
// separator at junctions and within src). Returns pointer to the null
// terminator written.
fn pathnpcatSep(
    dst: [*]u8,
    src: [*:0]const u8,
    start: [*]const u8,
    end: [*]const u8,
    sep: []const u8,
) [*]u8 {
    var d = dst;
    var s = src;
    while (@intFromPtr(d) < @intFromPtr(end) and s[0] != 0) {
        if (srcStartsWith(s, sep) and dstEndsWith(d, start, sep)) {
            s += sep.len;
            continue;
        }
        d[0] = s[0];
        d += 1;
        s += 1;
    }
    d[0] = 0;
    return d;
}

var path_buf: [std.fs.max_path_bytes + 1]u8 = undefined;

const sep_str = std.fs.path.sep_str;

/// Joins n path segments, deduplicating consecutive separators.
pub fn pathconcat(segments: [*c][*c]const u8, n: usize) [*c]u8 {
    const limit: [*]u8 = path_buf[std.fs.max_path_bytes..].ptr;

    if (n == 0) {
        path_buf[0] = 0;
        return &path_buf[0];
    }

    path_buf[0] = 0;
    var p = pathnpcatSep(&path_buf, @ptrCast(segments[0]), &path_buf, limit, sep_str);

    var i: usize = 1;
    while (i < n) : (i += 1) {
        p = pathnpcatSep(p, sep_str.ptr, &path_buf, limit, sep_str);
        p = pathnpcatSep(p, @ptrCast(segments[i]), &path_buf, limit, sep_str);
        if (@intFromPtr(p) == @intFromPtr(limit)) break;
    }

    return &path_buf[0];
}

/// Returns true if dir has exactly one child that is itself a directory.
pub fn is_singleton(dir: *types.Info) bool {
    const child = dir.child;
    if (child == null) return false;
    if (child[0] == null) return false;
    if (child[1] != null) return false;
    return child[0].?.isdir;
}

pub fn xmalloc(size: usize) *anyopaque {
    return std.c.malloc(size) orelse {
        std.debug.print("tree: virtual memory exhausted.\n", .{});
        std.process.exit(1);
    };
}

pub fn xrealloc(ptr: ?*anyopaque, size: usize) *anyopaque {
    return std.c.realloc(ptr, size) orelse {
        std.debug.print("tree: virtual memory exhausted.\n", .{});
        std.process.exit(1);
    };
}

pub fn scopy(s: [*c]const u8) [*c]u8 {
    const len = c.strlen(s);
    const dst: [*c]u8 = @ptrCast(xmalloc(len + 1));
    return c.strcpy(dst, s);
}

pub var io: std.Io = undefined;
pub var file: std.Io.File = undefined;

pub fn init(new_io: std.Io, new_file: std.Io.File) void {
    io = new_io;
    file = new_file;
}

pub fn writer(buffer: []u8) std.Io.File.Writer {
    return file.writer(io, buffer);
}

pub fn gittrim(s: [*c]u8) void {
    var e: isize = @as(isize, @intCast(c.strlen(s))) - 1;
    if (e < 0) return;
    while (e > 0 and (s[@intCast(e)] == '\n' or s[@intCast(e)] == '\r')) e -= 1;

    var i: isize = e;
    while (i >= 0) : (i -= 1) {
        if (s[@intCast(i)] != ' ') break;
        if (i != 0 and s[@intCast(i - 1)] != '\\') e -= 1;
    }
    s[@intCast(e + 1)] = 0;

    var ri: usize = 0;
    var re: usize = 0;
    while (s[ri] != 0) {
        if (s[ri] == '\\') ri += 1;
        s[re] = s[ri];
        re += 1;
        ri += 1;
    }
    s[re] = 0;
}

test "pathnpcatSep basic copy" {
    var buf: [64]u8 = undefined;
    const limit: [*]u8 = buf[63..].ptr;
    _ = pathnpcatSep(&buf, "hello", &buf, limit, "/");
    try std.testing.expectEqualStrings("hello", std.mem.sliceTo(&buf, 0));
}

test "pathnpcatSep deduplicates consecutive separators within src" {
    var buf: [64]u8 = undefined;
    const limit: [*]u8 = buf[63..].ptr;
    _ = pathnpcatSep(&buf, "foo//bar", &buf, limit, "/");
    try std.testing.expectEqualStrings("foo/bar", std.mem.sliceTo(&buf, 0));
}

test "pathnpcatSep deduplicates separator at junction" {
    var buf: [64]u8 = undefined;
    const limit: [*]u8 = buf[63..].ptr;
    const p = pathnpcatSep(&buf, "foo/", &buf, limit, "/");
    _ = pathnpcatSep(p, "/bar", &buf, limit, "/");
    try std.testing.expectEqualStrings("foo/bar", std.mem.sliceTo(&buf, 0));
}

test "pathnpcatSep respects end boundary" {
    var buf: [8]u8 = undefined;
    const limit: [*]u8 = buf[4..].ptr;
    _ = pathnpcatSep(&buf, "hello world", &buf, limit, "/");
    try std.testing.expectEqualStrings("hell", std.mem.sliceTo(&buf, 0));
}

test "pathnpcatSep deduplicates multi-byte separator" {
    var buf: [64]u8 = undefined;
    const limit: [*]u8 = buf[63..].ptr;
    const p = pathnpcatSep(&buf, "foo::", &buf, limit, "::");
    _ = pathnpcatSep(p, "::bar", &buf, limit, "::");
    try std.testing.expectEqualStrings("foo::bar", std.mem.sliceTo(&buf, 0));
}

test "pathnpcatSep multi-byte separator does not dedup partial overlap" {
    var buf: [64]u8 = undefined;
    const limit: [*]u8 = buf[63..].ptr;
    _ = pathnpcatSep(&buf, "a:b:c", &buf, limit, "::");
    try std.testing.expectEqualStrings("a:b:c", std.mem.sliceTo(&buf, 0));
}

test "pathnpcatSep with empty src writes only null terminator" {
    var buf: [64]u8 = undefined;
    buf[0] = 'x';
    const limit: [*]u8 = buf[63..].ptr;
    const end = pathnpcatSep(&buf, "", &buf, limit, "/");
    try std.testing.expectEqual(@intFromPtr(&buf[0]), @intFromPtr(end));
    try std.testing.expectEqualStrings("", std.mem.sliceTo(&buf, 0));
}

test "pathconcat with zero segments returns empty string" {
    const result = pathconcat(null, 0);
    try std.testing.expectEqualStrings("", std.mem.sliceTo(result, 0));
}

test "pathconcat with single segment" {
    var segs = [_][*c]const u8{"foo"};
    const result = pathconcat(&segs, 1);
    try std.testing.expectEqualStrings("foo", std.mem.sliceTo(result, 0));
}

test "pathconcat joins two segments" {
    var segs = [_][*c]const u8{ "foo", "bar" };
    const result = pathconcat(&segs, 2);
    try std.testing.expectEqualStrings("foo" ++ sep_str ++ "bar", std.mem.sliceTo(result, 0));
}

test "pathconcat joins three segments" {
    var segs = [_][*c]const u8{ "a", "b", "c" };
    const result = pathconcat(&segs, 3);
    try std.testing.expectEqualStrings("a" ++ sep_str ++ "b" ++ sep_str ++ "c", std.mem.sliceTo(result, 0));
}

test "pathconcat dedups separator at segment junction" {
    var segs = [_][*c]const u8{ "foo" ++ sep_str, sep_str ++ "bar" };
    const result = pathconcat(&segs, 2);
    try std.testing.expectEqualStrings("foo" ++ sep_str ++ "bar", std.mem.sliceTo(result, 0));
}

test "scopy duplicates a null-terminated string" {
    const src: [*c]const u8 = "hello";
    const dst = scopy(src);
    defer std.c.free(dst);
    try std.testing.expectEqualStrings("hello", std.mem.sliceTo(dst, 0));
    try std.testing.expect(@intFromPtr(dst) != @intFromPtr(src));
}

test "scopy handles empty string" {
    const dst = scopy("");
    defer std.c.free(dst);
    try std.testing.expectEqualStrings("", std.mem.sliceTo(dst, 0));
}
