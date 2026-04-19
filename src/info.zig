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

const c = @cImport({
    @cInclude("tree.h");
});

extern var outfile: ?*c.FILE;
extern var linedraw: [*c]const c.struct_linedraw;
extern var xpattern: [c.PATH_MAX]u8;

var infostack: ?*c.struct_infofile = null;

fn scopy(s: [*c]const u8) [*c]u8 {
    const len = c.strlen(s);
    const dst: [*c]u8 = @ptrCast(c.xmalloc(len + 1));
    return c.strcpy(dst, s);
}

fn new_comment(phead: ?*c.struct_pattern, line: [*c][*c]u8, lines: c_int) *c.struct_comment {
    const com: *c.struct_comment = @ptrCast(@alignCast(c.xmalloc(@sizeOf(c.struct_comment))));
    com.pattern = phead;
    const lines_u: usize = @intCast(lines);
    com.desc = @ptrCast(@alignCast(c.xmalloc(@sizeOf([*c]u8) * (lines_u + 1))));
    var i: usize = 0;
    while (i < lines_u) : (i += 1) com.desc[i] = line[i];
    com.desc[i] = null;
    com.next = null;
    return com;
}

export fn new_infofile(path: [*c]const u8, checkparents: bool) ?*c.struct_infofile {
    var st: c.struct_stat = undefined;
    var buf: [c.PATH_MAX]u8 = undefined;
    var rpath: [c.PATH_MAX]u8 = undefined;
    var line: [c.PATH_MAX][*c]u8 = undefined;
    var lines: c_int = 0;
    var fp: ?*c.FILE = null;
    var chead: ?*c.struct_comment = null;
    var cend: ?*c.struct_comment = null;
    var phead: ?*c.struct_pattern = null;
    var pend: ?*c.struct_pattern = null;

    const stat_rc = c.stat(path, &st);
    const is_regular = stat_rc >= 0 and (st.st_mode & c.S_IFMT) == c.S_IFREG;
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
        c.gittrim(&buf);
        if (c.strlen(&buf) < 1) continue;

        if (buf[0] == '\t') {
            line[@intCast(lines)] = scopy(&buf[1]);
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
            const p = c.new_pattern(&buf);
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

    const inf: *c.struct_infofile = @ptrCast(@alignCast(c.xmalloc(@sizeOf(c.struct_infofile))));
    inf.comments = chead;
    inf.path = scopy(path);
    inf.next = null;

    return inf;
}

export fn push_infostack(inf: ?*c.struct_infofile) void {
    if (inf == null) return;
    inf.?.next = infostack;
    infostack = inf;
}

export fn pop_infostack() ?*c.struct_infofile {
    const inf = infostack orelse return null;

    infostack = inf.next;

    var cn: ?*c.struct_comment = inf.comments;
    while (cn != null) {
        const cur = cn.?;
        cn = cur.next;

        // Note: original C frees pattern->pattern (the string) but never the
        // pattern struct nodes themselves — preserved verbatim.
        var pp: ?*c.struct_pattern = cur.pattern;
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
export fn infocheck(path: [*c]const u8, name: [*c]const u8, top_in: c_int, isdir: bool) ?*c.struct_comment {
    if (infostack == null) return null;

    var top = top_in;
    var inf: ?*c.struct_infofile = infostack;
    while (inf != null) : (inf = inf.?.next) {
        const cur_inf = inf.?;
        const fpos: usize = @intCast(c.sprintf(&xpattern, "%s/", cur_inf.path));

        var com: ?*c.struct_comment = cur_inf.comments;
        while (com != null) : (com = com.?.next) {
            var p: ?*c.struct_pattern = com.?.pattern;
            while (p != null) : (p = p.?.next) {
                const pat = p.?.pattern;
                if (c.patmatch(path, pat, isdir) == 1) return com;
                if (top != 0 and c.patmatch(name, pat, isdir) == 1) return com;

                _ = c.sprintf(&xpattern[fpos], "%s", pat);
                if (c.patmatch(path, &xpattern, isdir) == 1) return com;
            }
        }
        top = 0;
    }
    return null;
}

export fn printcomment(line: usize, lines: usize, s: [*c]u8) void {
    if (lines == 1) {
        _ = c.fprintf(outfile, "%s ", linedraw.*.csingle);
    } else if (line == 0) {
        _ = c.fprintf(outfile, "%s ", linedraw.*.ctop);
    } else if (line < 2) {
        const drw: [*c]const u8 = if (lines == 2) linedraw.*.cbot else linedraw.*.cmid;
        _ = c.fprintf(outfile, "%s ", drw);
    } else {
        const drw: [*c]const u8 = if (line == lines - 1) linedraw.*.cbot else linedraw.*.cext;
        _ = c.fprintf(outfile, "%s ", drw);
    }
    _ = c.fprintf(outfile, "%s\n", s);
}
