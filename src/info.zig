//! .info annotation files ported from info.c.
//!
//! TODO: Make a "filenote" command for info comments.
//! maybe TODO: Support language extensions (i.e. .info.en, .info.gr, etc)
//! # comments
//! pattern
//! pattern
//!     info messages
//!     more info

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("tree.h");
});

const types = @import("types.zig");
const pat = @import("pattern.zig");
const util = @import("util.zig");
const linux = @import("linux.zig");

extern var linedraw: [*c]const types.LineDraw;
extern var xpattern: [c.PATH_MAX]u8;

var infostack: ?*types.InfoFile = null;

fn new_comment(phead: ?*types.Pattern, line: [*c][*c]u8, lines: c_int) *types.Comment {
    const com: *types.Comment = @ptrCast(@alignCast(util.xmalloc(@sizeOf(types.Comment))));
    com.pattern = phead;
    const lines_u: usize = @intCast(lines);
    com.desc = @ptrCast(@alignCast(util.xmalloc(@sizeOf([*c]u8) * (lines_u + 1))));
    var i: usize = 0;
    while (i < lines_u) : (i += 1) com.desc[i] = line[i];
    com.desc[i] = null;
    com.next = null;
    return com;
}

pub fn new_infofile(path: [*c]const u8, checkparents: bool) ?*types.InfoFile {
    var buf: [c.PATH_MAX]u8 = undefined;
    var rpath: [c.PATH_MAX]u8 = undefined;
    var line: [c.PATH_MAX][*c]u8 = undefined;
    var lines: c_int = 0;
    var fp: ?*c.FILE = null;
    var chead: ?*types.Comment = null;
    var cend: ?*types.Comment = null;
    var phead: ?*types.Pattern = null;
    var pend: ?*types.Pattern = null;

    const is_regular = if (comptime builtin.os.tag == .linux) blk: {
        var stat_result: std.os.linux.Statx = undefined;
        break :blk linux.stat(@ptrCast(path), 0, &stat_result) and
            (stat_result.mode & c.S_IFMT) == c.S_IFREG;
    } else blk: {
        const path_slice = std.mem.span(path);
        const stat_result = std.fs.cwd().statFile(path_slice) catch null;
        break :blk if (stat_result) |st| st.kind == .file else false;
    };
    if (!is_regular) {
        _ = c.snprintf(&buf, c.PATH_MAX, "%s/.info", path);
        fp = c.fopen(&buf, "r");

        if (fp == null and checkparents) {
            _ = c.strcpy(&rpath, path);
            while (fp == null and c.strcmp(&rpath, "/") != 0) {
                _ = c.snprintf(&buf, c.PATH_MAX, "%.*s/..", @as(c_int, c.PATH_MAX - 4), &rpath);
                if (c.realpath(&buf, &rpath) == null) break;
                _ = c.snprintf(&buf, c.PATH_MAX, "%.*s/.info", @as(c_int, c.PATH_MAX - 7), &rpath);
                fp = c.fopen(&buf, "r");
            }
        }
    } else {
        fp = c.fopen(path, "r");
    }
    if (fp == null) return null;

    while (c.fgets(&buf, c.PATH_MAX, fp) != null) {
        if (buf[0] == '#') continue;
        util.gittrim(&buf);
        if (c.strlen(&buf) < 1) continue;

        if (buf[0] == '\t') {
            line[@intCast(lines)] = util.scopy(&buf[1]);
            lines += 1;
        } else {
            if (lines != 0) {
                // Save previous pattern/message:
                if (phead != null) {
                    const com = new_comment(phead, &line, lines);
                    if (chead == null) {
                        chead = com;
                        cend = com;
                    } else {
                        cend.?.next = com;
                        cend = com;
                    }
                } else {
                    // Accumulated info message lines w/ no associated pattern?
                    var k: usize = 0;
                    while (k < @as(usize, @intCast(lines))) : (k += 1) c.free(line[k]);
                }
                // Reset for next pattern/message:
                phead = null;
                pend = null;
                lines = 0;
            }
            const p = pat.new_pattern(&buf);
            if (phead == null) {
                phead = p;
                pend = p;
            } else {
                pend.?.next = p;
                pend = p;
            }
        }
    }
    if (phead != null) {
        const com = new_comment(phead, &line, lines);
        if (chead == null) {
            chead = com;
        } else {
            cend.?.next = com;
        }
    } else {
        var k: usize = 0;
        while (k < @as(usize, @intCast(lines))) : (k += 1) c.free(line[k]);
    }

    _ = c.fclose(fp);

    const inf: *types.InfoFile = @ptrCast(@alignCast(util.xmalloc(@sizeOf(types.InfoFile))));
    inf.comments = chead;
    inf.path = util.scopy(path);
    inf.next = null;

    return inf;
}

pub fn push_infostack(inf: ?*types.InfoFile) void {
    if (inf == null) return;
    inf.?.next = infostack;
    infostack = inf;
}

pub fn pop_infostack() ?*types.InfoFile {
    const inf = infostack orelse return null;

    infostack = inf.next;

    var cn: ?*types.Comment = inf.comments;
    while (cn != null) {
        const cur = cn.?;
        cn = cur.next;

        // Note: original C frees pattern->pattern (the string) but never the
        // pattern struct nodes themselves — preserved verbatim.
        var pp: ?*types.Pattern = cur.pattern;
        while (pp != null) {
            const pcur = pp.?;
            pp = pcur.next;
            c.free(pcur.pattern);
        }

        var di: usize = 0;
        while (cur.desc[di] != null) : (di += 1) c.free(cur.desc[di]);
        c.free(@ptrCast(cur.desc));
        c.free(cur);
    }
    c.free(inf.path);
    c.free(inf);
    return null;
}

/// Returns an info pointer if a path matches a pattern.
/// top == 1 if called in a directory with a .info file.
pub fn infocheck(path: [*c]const u8, name: [*c]const u8, top_in: c_int, isdir: bool, ignore_case: bool) ?*types.Comment {
    if (infostack == null) return null;

    var top = top_in;
    var inf: ?*types.InfoFile = infostack;
    while (inf != null) : (inf = inf.?.next) {
        const cur_inf = inf.?;
        const fpos: usize = @intCast(c.sprintf(&xpattern, "%s/", cur_inf.path));

        var com: ?*types.Comment = cur_inf.comments;
        while (com != null) : (com = com.?.next) {
            var p: ?*types.Pattern = com.?.pattern;
            while (p != null) : (p = p.?.next) {
                const pattern = p.?.pattern;
                if (pat.match(path, pattern, isdir, ignore_case) == 1) return com;
                if (top != 0 and pat.match(name, pattern, isdir, ignore_case) == 1) return com;

                _ = c.sprintf(&xpattern[fpos], "%s", pattern);
                if (pat.match(path, &xpattern, isdir, ignore_case) == 1) return com;
            }
        }
        top = 0;
    }
    return null;
}

pub fn printcomment(w: *std.Io.Writer, line: usize, lines: usize, s: [*c]u8) void {
    const drw: [*c]const u8 = if (lines == 1)
        linedraw.*.csingle
    else if (line == 0)
        linedraw.*.ctop
    else if (line < 2)
        (if (lines == 2) linedraw.*.cbot else linedraw.*.cmid)
    else
        (if (line == lines - 1) linedraw.*.cbot else linedraw.*.cext);
    w.print("{s} {s}\n", .{ std.mem.span(drw), std.mem.span(s) }) catch {};
}
