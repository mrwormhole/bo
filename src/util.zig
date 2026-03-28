//! Utilities ported from util.c

const std = @import("std");
const c = @cImport({
    @cInclude("tree.h");
});

// Copies src into dst up to end, skipping a src separator character when the
// previous character written was also a separator (deduplicates separators at
// junctions). Returns pointer to the null terminator written.
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
        if (@intFromPtr(d) > @intFromPtr(start)) {
            const prev_is_sep = std.mem.indexOfScalar(u8, sep, (d - 1)[0]) != null;
            const cur_is_sep = std.mem.indexOfScalar(u8, sep, s[0]) != null;
            if (prev_is_sep and cur_is_sep) {
                s += 1;
                continue;
            }
        }
        d[0] = s[0];
        d += 1;
        s += 1;
    }
    d[0] = 0;
    return d;
}

var path_buf: [c.PATH_MAX + 1]u8 = undefined;

/// Joins a null-terminated array of path segments using sep, deduplicating
/// consecutive separators. Called via the pathconcat(...) macro in tree.h.
export fn pathconcat_arr(sep: [*:0]const u8, segments: [*c][*c]const u8) [*c]u8 {
    const sep_slice = std.mem.span(sep);
    const limit: [*]u8 = path_buf[c.PATH_MAX..].ptr;

    const first = segments[0] orelse {
        path_buf[0] = 0;
        return &path_buf[0];
    };

    path_buf[0] = 0;
    var p = pathnpcatSep(&path_buf, @ptrCast(first), &path_buf, limit, sep_slice);

    var i: usize = 1;
    while (segments[i] != null) : (i += 1) {
        p = pathnpcatSep(p, sep, &path_buf, limit, sep_slice);
        p = pathnpcatSep(p, @ptrCast(segments[i]), &path_buf, limit, sep_slice);
        if (@intFromPtr(p) == @intFromPtr(limit)) break;
    }

    return &path_buf[0];
}

/// Returns true if dir has exactly one child that is itself a directory.
export fn is_singleton(dir: *c.struct__info) bool {
    const child = dir.child;
    if (child == null) return false;
    if (child[0] == null) return false;
    if (child[1] != null) return false;
    return child[0][0].isdir;
}

export fn xmalloc(size: usize) *anyopaque {
    return std.c.malloc(size) orelse {
        std.debug.print("tree: virtual memory exhausted.\n", .{});
        std.process.exit(1);
    };
}

export fn xrealloc(ptr: ?*anyopaque, size: usize) *anyopaque {
    return std.c.realloc(ptr, size) orelse {
        std.debug.print("tree: virtual memory exhausted.\n", .{});
        std.process.exit(1);
    };
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
