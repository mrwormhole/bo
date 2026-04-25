//! Main tree driver ported from tree.c.

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("tree.h");
});

// ---------------------------------------------------------------------------
// Function-type aliases matching the C typedefs in tree.h
// ---------------------------------------------------------------------------
const GetFullTreeFn = fn ([*c]u8, c.u_long, c.dev_t, [*c]c.off_t, [*c][*c]u8) callconv(.c) [*c][*c]c.struct__info;
const SortFn = fn ([*c][*c]c.struct__info, [*c][*c]c.struct__info) callconv(.c) c_int;

// ---------------------------------------------------------------------------
// Extern from color.zig
// ---------------------------------------------------------------------------
// color.c
extern var linedraw: [*c]const c.struct_linedraw;

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
export var version: [*c]const u8 = "bo (The Bodhi Tree) v0.0.5";

// Globals
export var flag: c.struct_Flags = std.mem.zeroes(c.struct_Flags);
export var lc: c.struct_listingcalls = std.mem.zeroes(c.struct_listingcalls);

export var pattern: c_int = 0;
export var maxpattern: c_int = 0;
export var ipattern: c_int = 0;
export var maxipattern: c_int = 0;
export var patterns: [*c][*c]u8 = null;
export var ipatterns: [*c][*c]u8 = null;

export var host: [*c]u8 = null;
export var title: [*c]const u8 = "Directory Tree";
export var sp: [*c]const u8 = " ";
export var _nl: [*c]const u8 = "\n";
export var Hintro: [*c]const u8 = null;
export var Houtro: [*c]const u8 = null;
export var scheme: [*c]u8 = @constCast("file://");
export var authority: [*c]u8 = null;
export var file_comment: [*c]u8 = @constCast("#");
export var file_pathsep: [*c]u8 = @constCast("/");
export var timefmt: [*c]u8 = null;
export var charset: [*c]const u8 = null;

export var getfulltree: ?*const GetFullTreeFn = &unix_getfulltree;
export var basesort: ?*const SortFn = &alnumsort;
export var topsort: ?*const SortFn = null;

// sLevel is only used within tree_main
var sLevel: [*c]u8 = null;

export var outfile: ?*c.FILE = null;
export var dirs: [*c]c_int = null;
export var Level: isize = 0;
export var maxdirs: usize = 0;
export var errors: c_int = 0;

export var xpattern: [c.PATH_MAX]u8 = std.mem.zeroes([c.PATH_MAX]u8);

export var mb_cur_max: c_int = 0;

// ---------------------------------------------------------------------------
// Platform-conditional ifmt / fmt / ftype  (comptime if on @hasDecl)
// ---------------------------------------------------------------------------
export var ifmt: [if (@hasDecl(c, "S_IFPORT")) 10 else 8]c.mode_t =
    if (@hasDecl(c, "S_IFPORT"))
        .{ c.S_IFREG, c.S_IFDIR, c.S_IFLNK, c.S_IFCHR, c.S_IFBLK, c.S_IFSOCK, c.S_IFIFO, c.S_IFDOOR, c.S_IFPORT, 0 }
    else
        .{ c.S_IFREG, c.S_IFDIR, c.S_IFLNK, c.S_IFCHR, c.S_IFBLK, c.S_IFSOCK, c.S_IFIFO, 0 };

// fmt is only used inside prot(); not needed by any other module
const fmt_str: [*:0]const u8 = if (@hasDecl(c, "S_IFPORT")) "-dlcbspDP?" else "-dlcbsp?";

export var ftype: [if (@hasDecl(c, "S_IFPORT")) 11 else 9][*c]const u8 =
    if (@hasDecl(c, "S_IFPORT"))
        .{ "file", "directory", "link", "char", "block", "socket", "fifo", "door", "port", "unknown", null }
    else
        .{ "file", "directory", "link", "char", "block", "socket", "fifo", "unknown", null };

// ---------------------------------------------------------------------------
// Sort table (module-private, mirrors C's sorts[])
// ---------------------------------------------------------------------------
const SortEntry = struct {
    name: [*c]const u8,
    cmpfunc: ?*const SortFn,
};

const sorts = [_]SortEntry{
    .{ .name = "name", .cmpfunc = &alnumsort },
    .{ .name = "version", .cmpfunc = &versort },
    .{ .name = "size", .cmpfunc = &fsizesort },
    .{ .name = "mtime", .cmpfunc = &mtimesort },
    .{ .name = "ctime", .cmpfunc = &ctimesort },
    .{ .name = "none", .cmpfunc = null },
    .{ .name = null, .cmpfunc = null },
};

// ---------------------------------------------------------------------------
// Platform helpers
// ---------------------------------------------------------------------------

inline fn cStderr() ?*c.FILE {
    return switch (builtin.os.tag) {
        .linux => c.stderr,
        else => c.stderr(),
    };
}

inline fn cStdout() ?*c.FILE {
    return switch (builtin.os.tag) {
        .linux => c.stdout,
        else => c.stdout(),
    };
}

fn getMbCurMax() c_int {
    // MB_CUR_MAX is a runtime locale value.  On glibc-based Linux systems it is
    // exposed via __ctype_get_mb_cur_max; on macOS/__mb_cur_max; elsewhere
    // default to 1 (single-byte) which disables the wide-char printit path.
    switch (builtin.os.tag) {
        .linux => {
            const glibc = struct {
                extern fn __ctype_get_mb_cur_max() usize;
            };
            return @intCast(glibc.__ctype_get_mb_cur_max());
        },
        .macos => {
            const macos_mb = struct {
                extern var __mb_cur_max: c_int;
            };
            return macos_mb.__mb_cur_max;
        },
        else => return 1,
    }
}

// ---------------------------------------------------------------------------
// Module-level state replacing C's static locals
// ---------------------------------------------------------------------------
var prot_buf: [11]u8 = undefined;
var do_date_buf: [256]u8 = undefined;
var getinfo_lbuf: [*c]u8 = null;
var getinfo_lbufsize: usize = 0;
var read_dir_path: [*c]u8 = null;
var read_dir_pathsize: usize = 0;

// SIXMONTHS constant
const SIXMONTHS: c.time_t = 6 * 31 * 24 * 60 * 60;

// ---------------------------------------------------------------------------
// Exported formatting helpers
// ---------------------------------------------------------------------------

export fn prot(m: c.mode_t) [*c]u8 {
    const perms = "rwxrwxrwx";
    var i: c_int = 0;
    while (ifmt[@intCast(i)] != 0 and (m & c.S_IFMT) != ifmt[@intCast(i)]) : (i += 1) {}
    prot_buf[0] = fmt_str[@intCast(i)];

    // Nice, but maybe not so portable, it is should be no less portable than the
    // old code.
    var b: c.mode_t = c.S_IRUSR;
    var j: usize = 0;
    while (j < 9) : ({
        b >>= 1;
        j += 1;
    }) {
        prot_buf[j + 1] = if ((m & b) != 0) perms[j] else '-';
    }
    if ((m & c.S_ISUID) != 0) prot_buf[3] = if (prot_buf[3] == '-') 'S' else 's';
    if ((m & c.S_ISGID) != 0) prot_buf[6] = if (prot_buf[6] == '-') 'S' else 's';
    if ((m & c.S_ISVTX) != 0) prot_buf[9] = if (prot_buf[9] == '-') 'T' else 't';

    prot_buf[10] = 0;
    return &prot_buf;
}

export fn do_date(t: c.time_t) [*c]u8 {
    const tm = c.localtime(&t);

    if (timefmt != null) {
        _ = c.strftime(&do_date_buf, 255, timefmt, tm);
        do_date_buf[255] = 0;
    } else {
        const cur: c.time_t = c.time(null);
        // Use strftime() so that locale is respected:
        if (t > cur or (t + SIXMONTHS) < cur) {
            _ = c.strftime(&do_date_buf, 255, "%b %e  %Y", tm);
        } else {
            _ = c.strftime(&do_date_buf, 255, "%b %e %R", tm);
        }
    }
    return &do_date_buf;
}

// Must fix this someday
export fn printit(s: [*c]const u8) void {
    if (flag.N) {
        if (flag.Q) _ = c.fprintf(outfile, "\"%s\"", s) else _ = c.fprintf(outfile, "%s", s);
        return;
    }
    if (mb_cur_max > 1) {
        const cs: usize = c.strlen(s) + 1;
        const ws: [*c]c.wchar_t = @ptrCast(@alignCast(c.xmalloc(@sizeOf(c.wchar_t) * cs)));
        if (c.mbstowcs(ws, s, cs) != @as(usize, @bitCast(@as(isize, -1)))) {
            if (flag.Q) _ = c.putc('"', outfile);
            var remaining: usize = cs;
            var tp: [*c]c.wchar_t = ws;
            while (tp[0] != 0 and remaining > 1) : ({
                tp += 1;
                remaining -= 1;
            }) {
                if (c.iswprint(@intCast(tp[0])) != 0) {
                    _ = c.fprintf(outfile, "%lc", @as(c.wint_t, @intCast(tp[0])));
                } else {
                    if (flag.q) _ = c.putc('?', outfile) else _ = c.fprintf(outfile, "\\%03o", @as(c_uint, @intCast(tp[0])));
                }
            }
            if (flag.Q) _ = c.putc('"', outfile);
            c.free(ws);
            return;
        }
        c.free(ws);
    }
    if (flag.Q) _ = c.putc('"', outfile);
    var sp2: [*c]const u8 = s;
    while (sp2[0] != 0) : (sp2 += 1) {
        const ch: c_int = @intCast(sp2[0]);
        if ((ch >= 7 and ch <= 13) or ch == '\\' or (ch == '"' and flag.Q) or (ch == ' ' and !flag.Q)) {
            _ = c.putc('\\', outfile);
            if (ch > 13) _ = c.putc(ch, outfile) else _ = c.putc("abtnvfr"[@intCast(ch - 7)], outfile);
        } else if (c.isprint(ch) != 0) {
            _ = c.putc(ch, outfile);
        } else {
            if (flag.q) {
                if (mb_cur_max > 1 and ch > 127) _ = c.putc(ch, outfile) else _ = c.putc('?', outfile);
            } else {
                _ = c.fprintf(outfile, "\\%03o", @as(c_uint, @intCast(ch)));
            }
        }
    }
    if (flag.Q) _ = c.putc('"', outfile);
}

export fn psize(buf: [*c]u8, size: c.off_t) c_int {
    const iec_unit = "BKMGTPEZY";
    const si_unit = "dkMGTPEZY";
    const unit: [*c]const u8 = if (flag.si) si_unit else iec_unit;
    const usize_val: c.off_t = if (flag.si) 1000 else 1024;
    var idx: c_int = if (size < usize_val) 0 else 1;
    var sz: c.off_t = size;

    if (flag.h or flag.si) {
        while (sz >= (usize_val * usize_val)) : ({
            idx += 1;
            sz = @divTrunc(sz, usize_val);
        }) {}
        if (idx == 0) return c.sprintf(buf, " %4d", @as(c_int, @intCast(sz)));
        const fmt2: [*c]const u8 = if (@divTrunc(sz + 52, usize_val) >= 10) " %3.0f%c" else " %3.1f%c";
        return c.sprintf(buf, fmt2, @as(f64, @floatFromInt(sz)) / @as(f64, @floatFromInt(usize_val)), @as(c_int, @intCast(unit[@intCast(idx)])));
    } else {
        if (comptime @sizeOf(c.off_t) == 8) {
            return c.sprintf(buf, " %11lld", @as(c_longlong, @intCast(size)));
        } else {
            return c.sprintf(buf, " %9lld", @as(c_longlong, @intCast(size)));
        }
    }
}

export fn Ftype(mode: c.mode_t) u8 {
    const m: c_int = @intCast(mode & c.S_IFMT);
    if (!flag.d and m == c.S_IFDIR) return '/';
    if (m == c.S_IFSOCK) return '=';
    if (m == c.S_IFIFO) return '|';
    if (m == c.S_IFLNK) return '@'; // Here, but never actually used though.
    if (@hasDecl(c, "S_IFDOOR")) {
        if (m == c.S_IFDOOR) return '>';
    }
    if (m == c.S_IFREG and (mode & (c.S_IXUSR | c.S_IXGRP | c.S_IXOTH)) != 0) return '*';
    return 0;
}

export fn fillinfo(buf: [*c]u8, ent: ?*const c.struct__info) [*c]u8 {
    var n: c_int = 0;
    buf[@intCast(n)] = 0;
    // Not sure why this should happen, but just in case:
    if (ent == null) return buf;
    const e = ent.?;

    if (flag.inode) {
        if (@sizeOf(c.ino_t) == @sizeOf(c_longlong)) {
            n += c.sprintf(buf, " %7lld", @as(c_longlong, @intCast(e.linode)));
        } else {
            n += c.sprintf(buf, " %7ld", @as(c_long, @intCast(e.linode)));
        }
    }
    if (flag.dev) n += c.sprintf(buf + @as(usize, @intCast(n)), " %3d", @as(c_int, @intCast(e.ldev)));
    if (flag.p) n += c.sprintf(buf + @as(usize, @intCast(n)), " %s", prot(e.mode));
    if (comptime builtin.os.tag == .linux) {
        if (flag.acl) n += c.sprintf(buf + @as(usize, @intCast(n)), "%c", @as(c_int, if (e.hasacl) '+' else ' '));
    }
    if (flag.u) n += c.sprintf(buf + @as(usize, @intCast(n)), " %-8.32s", c.uidtoname(e.uid));
    if (flag.g) n += c.sprintf(buf + @as(usize, @intCast(n)), " %-8.32s", c.gidtoname(e.gid));
    if (flag.s) n += psize(buf + @as(usize, @intCast(n)), e.size);
    if (flag.D) n += c.sprintf(buf + @as(usize, @intCast(n)), " %s", do_date(if (flag.c) e.ctime else e.mtime));
    if (comptime builtin.os.tag == .linux) {
        if (flag.selinux) n += c.sprintf(buf + @as(usize, @intCast(n)), " %s", e.secontext);
    }

    if (buf[0] == ' ') {
        buf[0] = '[';
        _ = c.sprintf(buf + @as(usize, @intCast(n)), "]");
    }

    return buf;
}

// They cried out for ANSI-lines (not really), but here they are, as an option
// for the xterm and console capable among you, as a run-time option.
export fn indent(maxlevel: c_int) void {
    const spaces = [3][*c]const u8{ "   ", "  ", " " };
    const htmlspaces = [3][*c]const u8{ "&nbsp;&nbsp;&nbsp;", "&nbsp;&nbsp;", "&nbsp;" };
    const space: [*c]const u8 = if (flag.H) "&nbsp;" else " ";
    const clvl: usize = @intCast(flag.compress_indent);

    if (flag.H) _ = c.fprintf(outfile, "\t");
    var i: c_int = 1;
    while (i <= maxlevel and dirs[@intCast(i)] != 0) : (i += 1) {
        const has_next: bool = dirs[@intCast(i + 1)] != 0;
        const bar_here: bool = dirs[@intCast(i)] == 1;
        const seg: [*c]const u8 = if (has_next)
            (if (bar_here) linedraw.*.vert[clvl] else (if (flag.H) htmlspaces[clvl] else spaces[clvl]))
        else
            (if (bar_here) linedraw.*.vert_left[clvl] else linedraw.*.corner[clvl]);
        _ = c.fprintf(outfile, "%s", seg);
        if (flag.remove_space != true) _ = c.fprintf(outfile, "%s", space);
    }
}

// ---------------------------------------------------------------------------
// Sort functions
// ---------------------------------------------------------------------------

// filesfirst and dirsfirst are now top-level meta-sorts.
export fn filesfirst(a: [*c][*c]c.struct__info, b: [*c][*c]c.struct__info) c_int {
    if (a[0].*.isdir != b[0].*.isdir) {
        return if (a[0].*.isdir) 1 else -1;
    }
    return basesort.?(a, b);
}

export fn dirsfirst(a: [*c][*c]c.struct__info, b: [*c][*c]c.struct__info) c_int {
    if (a[0].*.isdir != b[0].*.isdir) {
        return if (a[0].*.isdir) -1 else 1;
    }
    return basesort.?(a, b);
}

// Sorting functions
export fn alnumsort(a: [*c][*c]c.struct__info, b: [*c][*c]c.struct__info) c_int {
    const v = c.strcoll(a[0].*.name, b[0].*.name);
    return if (flag.reverse) -v else v;
}

export fn versort(a: [*c][*c]c.struct__info, b: [*c][*c]c.struct__info) c_int {
    const v = c.strverscmp(a[0].*.name, b[0].*.name);
    return if (flag.reverse) -v else v;
}

export fn mtimesort(a: [*c][*c]c.struct__info, b: [*c][*c]c.struct__info) c_int {
    if (a[0].*.mtime == b[0].*.mtime) {
        const v = c.strcoll(a[0].*.name, b[0].*.name);
        return if (flag.reverse) -v else v;
    }
    const v: c_int = if (a[0].*.mtime < b[0].*.mtime) -1 else 1;
    return if (flag.reverse) -v else v;
}

export fn ctimesort(a: [*c][*c]c.struct__info, b: [*c][*c]c.struct__info) c_int {
    if (a[0].*.ctime == b[0].*.ctime) {
        const v = c.strcoll(a[0].*.name, b[0].*.name);
        return if (flag.reverse) -v else v;
    }
    const v: c_int = if (a[0].*.ctime < b[0].*.ctime) -1 else 1;
    return if (flag.reverse) -v else v;
}

export fn sizecmp(a: c.off_t, b: c.off_t) c_int {
    return if (a == b) 0 else if (a < b) 1 else -1;
}

export fn fsizesort(a: [*c][*c]c.struct__info, b: [*c][*c]c.struct__info) c_int {
    var v = sizecmp(a[0].*.size, b[0].*.size);
    if (v == 0) v = c.strcoll(a[0].*.name, b[0].*.name);
    return if (flag.reverse) -v else v;
}

// ---------------------------------------------------------------------------
// Pattern matching
// ---------------------------------------------------------------------------

fn condLower(ch: u8) u8 {
    return if (flag.ignorecase) @intCast(c.tolower(ch)) else ch;
}

// Patmatch() code courtesy of Thomas Moore (dark@mama.indstate.edu)
// '|' support added by David MacMahon (davidm@astron.Berkeley.EDU)
// Case insensitive support added by Jason A. Donenfeld (Jason@zx2c4.com)
// returns:
//    1 on a match
//    0 on a mismatch
//   -1 on a syntax error in the pattern
export fn patmatch(buf_in: [*c]const u8, pat_in: [*c]u8, isdir: bool) c_int {
    var match: c_int = 1;
    var pprev: u8 = 0;
    var buf = buf_in;
    var pat = pat_in;

    const bar: [*c]u8 = c.strchr(pat, '|');

    // If a bar is found, call patmatch recursively on the two sub-patterns
    if (bar != null) {
        // If the bar is the first or last character, it's a syntax error
        if (bar == pat or bar[1] == 0) {
            return -1;
        }
        // Break pattern into two sub-patterns
        bar[0] = 0;
        match = patmatch(buf, pat, isdir);
        if (match == 0) {
            match = patmatch(buf, bar + 1, isdir);
        }
        // Join sub-patterns back into one pattern
        bar[0] = '|';
        return match;
    }

    while (pat[0] != 0 and match != 0) {
        switch (pat[0]) {
            '[' => {
                pat += 1;
                var n: c_int = undefined;
                if (pat[0] != '^') {
                    n = 1;
                    match = 0;
                } else {
                    pat += 1;
                    n = 0;
                }
                while (pat[0] != ']') {
                    if (pat[0] == '\\') pat += 1;
                    if (pat[0] == 0) return -1; // || *pat == '/'
                    if (pat[1] == '-') {
                        const m: u8 = pat[0];
                        pat += 2;
                        if (pat[0] == '\\' and pat[0] != 0) pat += 1;
                        if (condLower(buf[0]) >= condLower(m) and condLower(buf[0]) <= condLower(pat[0]))
                            match = n;
                        if (pat[0] == 0) pat -= 1;
                    } else if (condLower(buf[0]) == condLower(pat[0])) {
                        match = n;
                    }
                    pat += 1;
                }
                buf += 1;
            },
            '*' => {
                pat += 1;
                if (pat[0] == 0) {
                    const f: c_int = @intFromBool(c.strchr(buf, '/') == null);
                    return f;
                }
                match = 0;
                // "Support" ** for .gitignore support, mostly the same as *:
                if (pat[0] == '*') {
                    pat += 1;
                    if (pat[0] == 0) return 1;

                    while (buf[0] != 0) {
                        match = patmatch(buf, pat, isdir);
                        if (match != 0) break;
                        // ** between two /'s is allowed to match a null /:
                        if (pprev == '/' and pat[0] == '/' and pat[1] != 0) {
                            match = patmatch(buf, pat + 1, isdir);
                            if (match != 0) return match;
                        }
                        buf += 1;
                        while (buf[0] != 0 and buf[0] != '/') : (buf += 1) {}
                    }
                } else {
                    while (buf[0] != 0) {
                        match = patmatch(buf, pat, isdir);
                        if (match != 0) break;
                        if (buf[0] == '/') break;
                        buf += 1;
                    }
                }
                if (match == 0 and (buf[0] == 0 or buf[0] == '/')) match = patmatch(buf, pat, isdir);
                return match;
            },
            '?' => {
                if (buf[0] == 0) return 0;
                buf += 1;
            },
            '/' => {
                if (pat[1] == 0 and buf[0] == 0) return @intFromBool(isdir);
                match = @intFromBool(buf[0] == pat[0]);
                buf += 1;
            },
            '\\' => {
                if (pat[0] != 0) pat += 1;
                // Falls through
                match = @intFromBool(condLower(buf[0]) == condLower(pat[0]));
                buf += 1;
            },
            else => {
                match = @intFromBool(condLower(buf[0]) == condLower(pat[0]));
                buf += 1;
            },
        }
        pprev = pat[0];
        pat += 1;
        if (match < 1) return match;
    }
    if (buf[0] == 0) return match;
    return 0;
}

// True if file matches an -I pattern
export fn patignore(name: [*c]const u8, isdir: bool, checkpaths: bool) c_int {
    var i: c_int = 0;
    while (i < ipattern) : (i += 1) {
        if (patmatch(name, ipatterns[@intCast(i)], isdir) != 0) return 1;
        if (checkpaths) {
            var pc: [*c]const u8 = c.strchr(name, file_pathsep[0]);
            while (pc != null and pc.?[0] != 0) {
                if (patmatch(pc.? + 1, ipatterns[@intCast(i)], isdir) != 0) return 1;
                pc = c.strchr(pc.? + 1, file_pathsep[0]);
            }
        }
    }
    return 0;
}

// True if name matches a -P pattern
export fn patinclude(name: [*c]const u8, isdir: bool, checkpaths: bool) c_int {
    var i: c_int = 0;
    while (i < pattern) : (i += 1) {
        if (patmatch(name, patterns[@intCast(i)], isdir) != 0) return 1;
        if (checkpaths) {
            var pc: [*c]const u8 = c.strchr(name, file_pathsep[0]);
            while (pc != null and pc.?[0] != 0) {
                if (patmatch(pc.? + 1, patterns[@intCast(i)], isdir) != 0) return 1;
                pc = c.strchr(pc.? + 1, file_pathsep[0]);
            }
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Linux-specific helpers
// ---------------------------------------------------------------------------

fn has_acl(path: [*c]const u8) bool {
    if (comptime builtin.os.tag != .linux) return false;
    var buf: [c.PATH_MAX]u8 = undefined;
    const n: isize = c.listxattr(path, &buf, c.PATH_MAX);
    if (n <= 0) return false;

    var key: [*c]u8 = &buf;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) {
        const len = c.strlen(key);
        if (c.strcmp(key, "system.posix_acl_access") == 0) return true;
        i += len + 1;
        key += len + 1;
    }
    return false;
}

// selinux contexts can be up to 4096 bytes, probably not more than 257 though.
// We'll store the strings in a hash table though as there will likely only be
// a handful of actual contexts. It would be more efficient still to compress
// the context by hashing each string between :'s, but that would likely vastly
// increase CPU time, for perhaps not much space savings.
fn selinux_context(path: [*c]const u8) [*c]u8 {
    if (comptime builtin.os.tag != .linux) return null;
    const len: isize = c.getxattr(path, "security.selinux", &xpattern, c.PATH_MAX - 1);
    xpattern[@intCast(if (len < 0) 0 else len)] = 0;
    return c.strhash(&xpattern);
}

// ---------------------------------------------------------------------------
// Filesystem functions
// ---------------------------------------------------------------------------

/// On Linux, musl's struct_timespec uses bitfield padding that Zig's C
fn doLstatInfo(path: [*c]const u8, ent: *c.struct__info) bool {
    if (comptime builtin.os.tag == .linux) {
        var lst: std.os.linux.Stat = undefined;
        const rc = std.os.linux.fstatat(
            std.os.linux.AT.FDCWD,
            @as([*:0]const u8, @ptrCast(path)),
            &lst,
            std.os.linux.AT.SYMLINK_NOFOLLOW,
        );
        if (std.os.linux.E.init(rc) != .SUCCESS) return false;
        ent.mode = @intCast(lst.mode);
        ent.uid = @intCast(lst.uid);
        ent.gid = @intCast(lst.gid);
        ent.size = @intCast(lst.size);
        ent.ldev = @intCast(lst.dev);
        ent.linode = @intCast(lst.ino);
        ent.atime = @intCast(lst.atim.sec);
        ent.ctime = @intCast(lst.ctim.sec);
        ent.mtime = @intCast(lst.mtim.sec);
        return true;
    } else {
        var lst: c.struct_stat = undefined;
        if (c.lstat(path, &lst) < 0) return false;
        ent.mode = lst.st_mode;
        ent.uid = lst.st_uid;
        ent.gid = lst.st_gid;
        ent.size = lst.st_size;
        ent.ldev = lst.st_dev;
        ent.linode = lst.st_ino;
        // st_atime/ctime/mtime are C macros not real fields; access via timespec members.
        // macOS uses st_atimespec; POSIX (FreeBSD etc.) uses st_atim.
        if (comptime @hasField(c.struct_stat, "st_atimespec")) {
            ent.atime = lst.st_atimespec.tv_sec;
            ent.ctime = lst.st_ctimespec.tv_sec;
            ent.mtime = lst.st_mtimespec.tv_sec;
        } else {
            ent.atime = lst.st_atim.tv_sec;
            ent.ctime = lst.st_ctim.tv_sec;
            ent.mtime = lst.st_mtim.tv_sec;
        }
        return true;
    }
}

// Split out stat portion from read_dir as prelude to just using stat structure directly.
fn getinfo(name: [*c]const u8, path: [*c]u8) ?*c.struct__info {
    if (getinfo_lbuf == null) {
        getinfo_lbufsize = c.PATH_MAX;
        getinfo_lbuf = @ptrCast(c.xmalloc(getinfo_lbufsize));
    }

    var ent_storage: c.struct__info = std.mem.zeroes(c.struct__info);

    if (!doLstatInfo(path, &ent_storage)) return null;

    // Determine if it's a symlink
    const lst_mode: c.mode_t = ent_storage.mode;
    var st_mode: c.mode_t = lst_mode;
    var st_dev: c.dev_t = ent_storage.ldev;
    var st_ino: c.ino_t = ent_storage.linode;
    var rs: c_int = 0;

    if ((lst_mode & c.S_IFMT) == @as(c.mode_t, c.S_IFLNK)) {
        if (comptime builtin.os.tag == .linux) {
            // On Linux (musl), c.struct_stat has opaque time fields making it
            // unusable with std.mem.zeroes.  Use the kernel syscall directly.
            var lxst: std.os.linux.Stat = undefined;
            const lxrc = std.os.linux.fstatat(
                std.os.linux.AT.FDCWD,
                @as([*:0]const u8, @ptrCast(path)),
                &lxst,
                0,
            );
            if (std.os.linux.E.init(lxrc) == .SUCCESS) {
                st_mode = @intCast(lxst.mode);
                st_dev = @intCast(lxst.dev);
                st_ino = @intCast(lxst.ino);
            } else {
                rs = -1;
            }
        } else {
            var st: c.struct_stat = std.mem.zeroes(c.struct_stat);
            rs = c.stat(path, &st);
            if (rs >= 0) {
                st_mode = st.st_mode;
                st_dev = st.st_dev;
                st_ino = st.st_ino;
            }
        }
        // Orphan symlink: the target doesn't exist, so "target mode/dev/inode"
        // are undefined. Zero them — downstream code reads st_mode as lnkmode
        // (target type) and st_dev/st_ino as the saveino dedup key. Leaving
        // them at the link's own lst_* values would lie: lnkmode would report
        // S_IFLNK ("target is a symlink", meaningless) and saveino would key
        // on the link itself. C handles this with memset(&st, 0, sizeof(st)).
        if (rs < 0) {
            st_mode = 0;
            st_dev = 0;
            st_ino = 0;
        }
    }

    const isdir: bool = (st_mode & c.S_IFMT) == @as(c.mode_t, c.S_IFDIR);

    if (flag.gitignore and c.filtercheck(path, name, @intFromBool(isdir))) return null;

    if ((lst_mode & c.S_IFMT) != @as(c.mode_t, c.S_IFDIR) and !(flag.l and ((st_mode & c.S_IFMT) == @as(c.mode_t, c.S_IFDIR)))) {
        if (pattern != 0 and c.patinclude(name, isdir, false) == 0 and c.patinclude(path, isdir, true) == 0) return null;
    }
    if (ipattern != 0 and (c.patignore(name, isdir, false) != 0 or c.patignore(path, isdir, true) != 0)) return null;

    if (flag.d and ((st_mode & c.S_IFMT) != @as(c.mode_t, c.S_IFDIR))) return null;

    // if (pattern && ((lst.st_mode & S_IFMT) == S_IFLNK) && !lflag) continue;

    const ent: *c.struct__info = @ptrCast(@alignCast(c.xmalloc(@sizeOf(c.struct__info))));
    @memset(@as([*]u8, @ptrCast(ent))[0..@sizeOf(c.struct__info)], 0);

    ent.name = c.scopy(name);
    // We should just incorporate struct stat into _info, and eliminate this unnecessary copying.
    // Made sense long ago when we had fewer options and didn't need half of stat.
    ent.mode = lst_mode;
    ent.uid = ent_storage.uid;
    ent.gid = ent_storage.gid;
    ent.size = ent_storage.size;
    ent.dev = st_dev;
    ent.inode = st_ino;
    ent.ldev = ent_storage.ldev;
    ent.linode = ent_storage.linode;
    ent.lnk = null;
    ent.orphan = false;
    ent.err = null;
    ent.child = null;

    ent.atime = ent_storage.atime;
    ent.ctime = ent_storage.ctime;
    ent.mtime = ent_storage.mtime;

    if (comptime builtin.os.tag == .linux) {
        if (flag.acl) ent.hasacl = has_acl(path);
        if (flag.selinux) ent.secontext = selinux_context(path) else ent.secontext = null;
    }

    ent.isdir = isdir;

    // These should perhaps be eliminated, as they're barely used:
    ent.issok = ((st_mode & c.S_IFMT) == @as(c.mode_t, c.S_IFSOCK));
    ent.isfifo = ((st_mode & c.S_IFMT) == @as(c.mode_t, c.S_IFIFO));
    ent.isexe = (st_mode & (c.S_IXUSR | c.S_IXGRP | c.S_IXOTH)) != 0;

    if ((lst_mode & c.S_IFMT) == @as(c.mode_t, c.S_IFLNK)) {
        const lst_size: usize = @intCast(ent_storage.size);
        if (lst_size + 1 > getinfo_lbufsize) {
            getinfo_lbufsize = lst_size + 8192;
            getinfo_lbuf = @ptrCast(c.xrealloc(getinfo_lbuf, getinfo_lbufsize));
        }
        const len: isize = c.readlink(path, getinfo_lbuf, getinfo_lbufsize - 1);
        if (len < 0) {
            ent.lnk = c.scopy("[Error reading symbolic link information]");
            ent.isdir = false;
            ent.lnkmode = st_mode;
        } else {
            getinfo_lbuf[@intCast(len)] = 0;
            ent.lnk = c.scopy(getinfo_lbuf);
            if (rs < 0) ent.orphan = true;
            ent.lnkmode = st_mode;
        }
    }

    ent.comment = null;

    return ent;
}

export fn free_dir(d: [*c][*c]c.struct__info) void {
    var i: usize = 0;
    while (d[i] != null) : (i += 1) {
        c.free(d[i].*.name);
        if (d[i].*.lnk != null) c.free(d[i].*.lnk);
        if (d[i].*.comment != null) {
            var j: usize = 0;
            while (d[i].*.comment[j] != null) : (j += 1) c.free(d[i].*.comment[j]);
        }
        if (d[i].*.err != null) c.free(d[i].*.err);
        // d[i]->selinux is a hashed string -- do not free.
        // d[i]->tag is a pointer to a string constant -- do not free.
        c.free(@ptrCast(d[i]));
    }
    c.free(@ptrCast(d));
}

export fn read_dir(dir: [*c]u8, n: [*c]isize, infotop: c_int) [*c][*c]c.struct__info {
    if (read_dir_path == null) {
        read_dir_pathsize = c.strlen(dir) + c.PATH_MAX;
        read_dir_path = @ptrCast(c.xmalloc(read_dir_pathsize));
    }

    const es: bool = dir[c.strlen(dir) - 1] == '/';
    n.* = -1;
    const d: ?*c.DIR = c.opendir(dir);
    if (d == null) return null;

    var ne: usize = c.MINIT;
    var dl: [*c][*c]c.struct__info = @ptrCast(@alignCast(c.xmalloc(@sizeOf([*c]c.struct__info) * ne)));
    var p: usize = 0;

    while (true) {
        const ent: ?*c.struct_dirent = @ptrCast(c.readdir(@ptrCast(d)));
        if (ent == null) break;
        const dname: [*c]const u8 = @ptrCast(&ent.?.d_name);
        if (c.strcmp("..", dname) == 0 or c.strcmp(".", dname) == 0) continue;
        if (flag.H and c.strcmp(dname, "00Tree.html") == 0) continue;
        if (!flag.a and dname[0] == '.') continue;

        const dlen = c.strlen(dir);
        const elen = c.strlen(dname);
        if (dlen + elen + 2 > read_dir_pathsize) {
            read_dir_pathsize = dlen + elen + c.PATH_MAX;
            read_dir_path = @ptrCast(c.xrealloc(read_dir_path, read_dir_pathsize));
        }
        if (es) {
            _ = c.sprintf(read_dir_path, "%s%s", dir, dname);
        } else {
            _ = c.sprintf(read_dir_path, "%s/%s", dir, dname);
        }

        const info = getinfo(dname, read_dir_path);
        if (info) |inf| {
            var com: ?*c.struct_comment = null;
            if (flag.showinfo) {
                com = c.infocheck(read_dir_path, dname, infotop, inf.isdir);
            }
            if (com != null) {
                var cnt: usize = 0;
                while (com.?.desc[cnt] != null) : (cnt += 1) {}
                inf.comment = @ptrCast(@alignCast(c.xmalloc(@sizeOf([*c]u8) * (cnt + 1))));
                var ci: usize = 0;
                while (ci < cnt) : (ci += 1) inf.comment[ci] = c.scopy(com.?.desc[ci]);
                inf.comment[cnt] = null;
            }
            if (p == (ne - 1)) dl = @ptrCast(@alignCast(c.xrealloc(@ptrCast(dl), @sizeOf([*c]c.struct__info) * (ne + c.MINC))));
            ne += if (p == (ne - 1)) c.MINC else 0;
            dl[p] = inf;
            p += 1;
        }
    }
    _ = c.closedir(@ptrCast(d));

    n.* = @intCast(p);
    if (n.* == 0) {
        c.free(@ptrCast(dl));
        return null;
    }

    dl[p] = null;
    return dl;
}

export fn push_files(dir: [*c]const u8, ig: [*c]?*c.struct_ignorefile, inf: [*c]?*c.struct_infofile, top: bool) void {
    var path_buf: [c.PATH_MAX]u8 = undefined;

    if (flag.gitignore) {
        var tig: ?*c.struct_ignorefile = null;
        // Not going to implement git configs so no core.excludesFile support.
        if (top) {
            const stmp = c.getenv("GIT_DIR");
            if (stmp != null) {
                var segs = [_][*c]u8{ &path_buf, stmp, @constCast("info/exclude") };
                c.push_filterstack(c.new_ignorefile(stmp, c.pathconcat(&segs, 3), false));
                tig = c.new_ignorefile(stmp, c.pathconcat(&segs, 3), false);
            }
        }
        if (top) {
            ig.* = c.gitignore_search(dir, 0);
        } else {
            ig.* = c.new_ignorefile(dir, dir, top);
            c.push_filterstack(ig.*);
        }
        if (ig.* == null) ig.* = tig;
    }
    if (flag.showinfo) {
        inf.* = c.new_infofile(dir, top);
        c.push_infostack(inf.*);
    }
}

// This is for all the impossible things people wanted the old tree to do.
// This can and will use a large amount of memory for large directory trees
// and also take some time.
export fn unix_getfulltree(d: [*c]u8, lev: c.u_long, dev_in: c.dev_t, size: [*c]c.off_t, err: [*c][*c]u8) [*c][*c]c.struct__info {
    var dev: c.dev_t = dev_in;
    var path: [*c]u8 = undefined;
    var pathsize: usize = 0;
    var ig: ?*c.struct_ignorefile = null;
    var inf: ?*c.struct_infofile = null;
    var sav: [*c][*c]c.struct__info = undefined;
    var dir_ptr: [*c][*c]c.struct__info = undefined;
    var n: isize = undefined;
    var tmp_pattern: c_int = 0;

    err.* = null;
    if (Level >= 0 and lev > @as(c.u_long, @intCast(Level))) return null;
    if (flag.xdev and lev == 0) {
        if (comptime builtin.os.tag == .linux) {
            // On Linux, c.struct_stat time fields are opaque; use fstatat to get st_dev.
            var lst2: std.os.linux.Stat = undefined;
            if (std.os.linux.E.init(std.os.linux.fstatat(
                std.os.linux.AT.FDCWD,
                @as([*:0]const u8, @ptrCast(d)),
                &lst2,
                0,
            )) == .SUCCESS) {
                dev = @intCast(lst2.dev);
            }
        } else {
            var sb: c.struct_stat = undefined;
            if (c.stat(d, &sb) == 0) dev = sb.st_dev;
        }
    }
    // if the directory name matches, turn off pattern matching for contents
    const last_name: [*c]const u8 = c.strrchr(d, file_pathsep[0]);
    if (pattern != 0 and (c.patinclude(d, true, true) != 0 or (last_name != null and c.patinclude(last_name.? + 1, true, false) != 0))) {
        tmp_pattern = pattern;
        pattern = 0;
    }

    c.push_files(d, @ptrCast(&ig), @ptrCast(&inf), lev == 0);

    sav = c.read_dir(d, &n, @intFromBool(inf != null));
    dir_ptr = sav;
    // We used to restore pattern from tmp_pattern here:

    if (dir_ptr == null and n != 0) {
        err.* = c.scopy("error opening dir");
        if (tmp_pattern != 0) pattern = tmp_pattern;
        return null;
    }
    if (n == 0) {
        if (sav != null) c.free_dir(sav);
        if (tmp_pattern != 0) pattern = tmp_pattern;
        return null;
    }
    pathsize = c.PATH_MAX;
    path = @ptrCast(c.xmalloc(pathsize));

    if (flag.flimit > 0 and n > flag.flimit) {
        _ = c.sprintf(path, "%ld entries exceeds filelimit, not opening dir", @as(c_long, @intCast(n)));
        err.* = c.scopy(path);
        c.free_dir(sav);
        c.free(path);
        if (tmp_pattern != 0) pattern = tmp_pattern;
        return null;
    }

    if (lev >= maxdirs - 1) {
        dirs = @ptrCast(@alignCast(c.xrealloc(@ptrCast(dirs), @sizeOf(c_int) * (maxdirs + 1024))));
        maxdirs += 1024;
    }

    while (dir_ptr.* != null) {
        const entry = dir_ptr.*;
        if (entry.*.isdir and !(flag.xdev and dev != entry.*.dev)) {
            if (entry.*.lnk != null) {
                if (flag.l) {
                    if (c.findino(entry.*.inode, entry.*.dev)) {
                        entry.*.err = c.scopy("recursive, not followed");
                    } else {
                        c.saveino(entry.*.inode, entry.*.dev);
                        if (entry.*.lnk[0] == '/') {
                            entry.*.child = unix_getfulltree(entry.*.lnk, lev + 1, dev, &(entry.*.size), &(entry.*.err));
                        } else {
                            const dlen = c.strlen(d);
                            const llen = c.strlen(entry.*.lnk);
                            if (dlen + llen + 2 > pathsize) {
                                pathsize = dlen + llen + 1024;
                                path = @ptrCast(c.xrealloc(path, pathsize));
                            }
                            if (flag.f and c.strcmp(d, "/") == 0) {
                                _ = c.sprintf(path, "%s%s", d, entry.*.lnk);
                            } else {
                                _ = c.sprintf(path, "%s/%s", d, entry.*.lnk);
                            }
                            entry.*.child = unix_getfulltree(path, lev + 1, dev, &(entry.*.size), &(entry.*.err));
                        }
                    }
                }
            } else {
                const dlen = c.strlen(d);
                const nlen = c.strlen(entry.*.name);
                if (dlen + nlen + 2 > pathsize) {
                    pathsize = dlen + nlen + 1024;
                    path = @ptrCast(c.xrealloc(path, pathsize));
                }

                if (flag.f and c.strcmp(d, "/") == 0) {
                    _ = c.sprintf(path, "%s%s", d, entry.*.name);
                } else {
                    _ = c.sprintf(path, "%s/%s", d, entry.*.name);
                }

                c.saveino(entry.*.inode, entry.*.dev);
                entry.*.child = unix_getfulltree(path, lev + 1, dev, &(entry.*.size), &(entry.*.err));

                if (flag.condense_singletons) {
                    while (c.is_singleton(@ptrCast(entry))) {
                        const child = entry.*.child;
                        var segs = [_][*c]u8{ entry.*.name, child[0].*.name };
                        const new_name = c.pathconcat(&segs, 2);
                        c.free(entry.*.name);
                        entry.*.name = c.scopy(new_name);
                        entry.*.child = child[0].*.child;
                        entry.*.condensed = entry.*.condensed + 1 + child[0].*.condensed;
                        c.free_dir(child);
                    }
                }
            }
            // prune empty folders, unless they match the requested pattern
            if (flag.prune and entry.*.child == null and
                !(flag.matchdirs and pattern != 0 and c.patinclude(entry.*.name, entry.*.isdir, false) != 0))
            {
                const xp = entry;
                var p: [*c][*c]c.struct__info = dir_ptr;
                while (p.* != null) : (p += 1) p.* = (p + 1).*;
                n -= 1;
                c.free(xp.*.name);
                if (xp.*.lnk != null) c.free(xp.*.lnk);
                c.free(@ptrCast(xp));
                continue;
            }
        }
        if (flag.du) size.* += entry.*.size;
        dir_ptr += 1;
    }

    if (tmp_pattern != 0) {
        pattern = tmp_pattern;
        tmp_pattern = 0;
    }

    // sorting needs to be deferred for --du:
    if (topsort != null) {
        const cmp: ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int = @ptrCast(topsort.?);
        c.qsort(@ptrCast(sav), @intCast(n), @sizeOf([*c]c.struct__info), cmp);
    }

    c.free(path);
    if (n == 0) {
        c.free_dir(sav);
        return null;
    }
    if (ig != null) _ = c.pop_filterstack();
    if (inf != null) _ = c.pop_infostack();
    return sav;
}

// ---------------------------------------------------------------------------
// CLI helpers
// ---------------------------------------------------------------------------

// Time to switch to getopt()?
fn longArg(argv: [*c][*c]u8, i: usize, j: *usize, n: *usize, prefix: [*c]const u8) [*c]u8 {
    var ret: [*c]u8 = null;
    const len: usize = c.strlen(prefix);

    if (c.strncmp(prefix, argv[i], len) == 0) {
        j.* = len;
        if (argv[i][j.*] == '=') {
            if (argv[i][j.* + 1] != 0) {
                j.* += 1;
                ret = argv[i] + j.*;
                j.* = c.strlen(argv[i]) - 1;
            } else {
                _ = c.fprintf(cStderr(), "tree: Missing argument to %s=\n", prefix);
                if (c.strcmp(prefix, "--charset=") == 0) c.initlinedraw(true);
                c.exit(c.EXIT_FAILURE);
            }
        } else if (argv[n.*] != null) {
            ret = argv[n.*];
            n.* += 1;
            j.* = c.strlen(argv[i]) - 1;
        } else {
            _ = c.fprintf(cStderr(), "tree: Missing argument to %s\n", prefix);
            if (c.strcmp(prefix, "--charset") == 0) c.initlinedraw(true);
            c.exit(c.EXIT_FAILURE);
        }
    }
    return ret;
}

export fn setoutput(filename: [*c]const u8) void {
    if (filename == null) {
        if (outfile == null) outfile = cStdout();
    } else {
        outfile = c.fopen(filename, "w");
        if (outfile == null) {
            _ = c.fprintf(cStderr(), "tree: invalid filename '%s'\n", filename);
            c.exit(c.EXIT_FAILURE);
        }
    }
}

fn print_usage() void {
    c.parse_dir_colors();
    c.initlinedraw(false);

    c.fancy(cStderr(), @constCast("usage: \x08tree\r [\x08-acdfghilnpqrstuvxACDFJQNSUX\r] [\x08-L\r \x0clevel\r [\x08-R\r]] [\x08-H\r [-]\x0cbaseHREF\r]\n" ++
        "\t[\x08-T\r \x0ctitle\r] [\x08-o\r \x0cfilename\r] [\x08-P\r \x0cpattern\r] [\x08-I\r \x0cpattern\r] [\x08--gitignore\r]\n" ++
        "\t[\x08--gitfile\r[\x08=\r]\x0cfile\r] [\x08--matchdirs\r] [\x08--metafirst\r] [\x08--ignore-case\r]\n" ++
        "\t[\x08--nolinks\r] [\x08--hintro\r[\x08=\r]\x0cfile\r] [\x08--houtro\r[\x08=\r]\x0cfile\r] [\x08--inodes\r] [\x08--device\r]\n" ++
        "\t[\x08--sort\r[\x08=\r]\x0cname\r] [\x08--dirsfirst\r] [\x08--filesfirst\r] [\x08--filelimit\r[\x08=\r]\x0c#\r] [\x08--si\r]\n" ++
        "\t[\x08--du\r] [\x08--prune\r] [\x08--charset\r[\x08=\r]\x0cX\r] [\x08--timefmt\r[\x08=\r]\x0cformat\r] [\x08--fromfile\r]\n" ++
        "\t[\x08--fromtabfile\r] [\x08--fflinks\r] [\x08--info\r] [\x08--infofile\r[\x08=\r]\x0cfile\r] [\x08--noreport\r]\n" ++
        "\t[\x08--hyperlink\r] [\x08--scheme\r[\x08=\r]\x0cschema\r] [\x08--authority\r[\x08=\r]\x0chost\r] [\x08--opt-toggle\r]\n" ++
        "\t[\x08--compress\r[\x08=\r]\x0c#\r] [\x08--condense\r] [\x08--version\r] [\x08--help\r]" ++
        (if (comptime builtin.os.tag == .linux) " [\x08--acl\r] [\x08--selinux\r]\n" else "\n") ++
        "\t[\x08--\r] [\x0cdirectory\r \x08...\r]\n"));
}

fn print_help() void {
    c.parse_dir_colors();
    c.initlinedraw(false);

    c.fancy(cStdout(), @constCast("usage: \x08tree\r [\x08-acdfghilnpqrstuvxACDFJQNSUX\r] [\x08-L\r \x0clevel\r [\x08-R\r]] [\x08-H\r [-]\x0cbaseHREF\r]\n" ++
        "\t[\x08-T\r \x0ctitle\r] [\x08-o\r \x0cfilename\r] [\x08-P\r \x0cpattern\r] [\x08-I\r \x0cpattern\r] [\x08--gitignore\r]\n" ++
        "\t[\x08--gitfile\r[\x08=\r]\x0cfile\r] [\x08--matchdirs\r] [\x08--metafirst\r] [\x08--ignore-case\r]\n" ++
        "\t[\x08--nolinks\r] [\x08--hintro\r[\x08=\r]\x0cfile\r] [\x08--houtro\r[\x08=\r]\x0cfile\r] [\x08--inodes\r] [\x08--device\r]\n" ++
        "\t[\x08--sort\r[\x08=\r]\x0cname\r] [\x08--dirsfirst\r] [\x08--filesfirst\r] [\x08--filelimit\r[\x08=\r]\x0c#\r] [\x08--si\r]\n" ++
        "\t[\x08--du\r] [\x08--prune\r] [\x08--charset\r[\x08=\r]\x0cX\r] [\x08--timefmt\r[\x08=\r]\x0cformat\r] [\x08--fromfile\r]\n" ++
        "\t[\x08--fromtabfile\r] [\x08--fflinks\r] [\x08--info\r] [\x08--infofile\r[\x08=\r]\x0cfile\r] [\x08--noreport\r]\n" ++
        "\t[\x08--hyperlink\r] [\x08--scheme\r[\x08=\r]\x0cschema\r] [\x08--authority\r[\x08=\r]\x0chost\r] [\x08--opt-toggle\r]\n" ++
        "\t[\x08--compress\r[\x08=\r]\x0c#\r] [\x08--condense\r] [\x08--version\r] [\x08--help\r]" ++
        (if (comptime builtin.os.tag == .linux) " [\x08--acl\r] [\x08--selinux\r]\n" else "\n") ++
        "\t[\x08--\r] [\x0cdirectory\r \x08...\r]\n"));

    c.fancy(cStdout(), @constCast("  \x08------- Listing options -------\r\n" ++
        "  \x08-a\r            All files are listed.\n" ++
        "  \x08-d\r            List directories only.\n" ++
        "  \x08-l\r            Follow symbolic links like directories.\n" ++
        "  \x08-f\r            Print the full path prefix for each file.\n" ++
        "  \x08-x\r            Stay on current filesystem only.\n" ++
        "  \x08-L\r \x0clevel\r      Descend only \x0clevel\r directories deep.\n" ++
        "  \x08-R\r            Rerun tree when max dir level reached.\n" ++
        "  \x08-P\r \x0cpattern\r    List only those files that match the pattern given.\n" ++
        "  \x08-I\r \x0cpattern\r    Do not list files that match the given pattern.\n" ++
        "  \x08--gitignore\r   Filter by using \x08.gitignore\r files.\n" ++
        "  \x08--gitfile\r \x0cX\r   Explicitly read a gitignore file.\n" ++
        "  \x08--ignore-case\r Ignore case when pattern matching.\n" ++
        "  \x08--matchdirs\r   Include directory names in \x08-P\r pattern matching.\n" ++
        "  \x08--metafirst\r   Print meta-data at the beginning of each line.\n" ++
        "  \x08--prune\r       Prune empty directories from the output.\n" ++
        "  \x08--info\r        Print information about files found in \x08.info\r files.\n" ++
        "  \x08--infofile\r \x0cX\r  Explicitly read info file.\n" ++
        "  \x08--noreport\r    Turn off file/directory count at end of tree listing.\n" ++
        "  \x08--charset\r \x0cX\r   Use charset \x0cX\r for terminal/HTML and indentation line output.\n" ++
        "  \x08--filelimit\r \x0c#\r Do not descend dirs with more than \x0c#\r files in them.\n" ++
        "  \x08--condense\r    Condense directory singletons to a single line of output.\n" ++
        "  \x08-o\r \x0cfilename\r   Output to file instead of stdout.\n" ++
        "  \x08------- File options -------\r\n" ++
        "  \x08-q\r            Print non-printable characters as '\x08?\r'.\n" ++
        "  \x08-N\r            Print non-printable characters as is.\n" ++
        "  \x08-Q\r            Quote filenames with double quotes.\n" ++
        "  \x08-p\r            Print the protections for each file.\n" ++
        "  \x08-u\r            Displays file owner or UID number.\n" ++
        "  \x08-g\r            Displays file group owner or GID number.\n" ++
        "  \x08-s\r            Print the size in bytes of each file.\n" ++
        "  \x08-h\r            Print the size in a more human readable way.\n" ++
        "  \x08--si\r          Like \x08-h\r, but use in SI units (powers of 1000).\n" ++
        "  \x08--du\r          Compute size of directories by their contents.\n" ++
        "  \x08-D\r            Print the date of last modification or (-c) status change.\n" ++
        "  \x08--timefmt\r \x0cfmt\r Print and format time according to the format \x0cfmt\r.\n" ++
        "  \x08-F\r            Appends '\x08/\r', '\x08=\r', '\x08*\r', '\x08@\r', '\x08|\r' or '\x08>\r' as per \x08ls -F\r.\n" ++
        "  \x08--inodes\r      Print inode number of each file.\n" ++
        "  \x08--device\r      Print device ID number to which each file belongs.\n" ++
        (if (comptime builtin.os.tag == .linux)
            "  \x08--acl\r         Print permissions with a + if an ACL is present.\n" ++
                "  \x08--selinux\r     Print the selinux security label if present.\n"
        else
            "")));

    c.fancy(cStdout(), @constCast("  \x08------- Sorting options -------\r\n" ++
        "  \x08-v\r            Sort files alphanumerically by version.\n" ++
        "  \x08-t\r            Sort files by last modification time.\n" ++
        "  \x08-c\r            Sort files by last status change time.\n" ++
        "  \x08-U\r            Leave files unsorted.\n" ++
        "  \x08-r\r            Reverse the order of the sort.\n" ++
        "  \x08--dirsfirst\r   List directories before files (\x08-U\r disables).\n" ++
        "  \x08--filesfirst\r  List files before directories (\x08-U\r disables).\n" ++
        "  \x08--sort\r \x0cX\r      Select sort: \x08\x0cname\r,\x08\x0cversion\r,\x08\x0csize\r,\x08\x0cmtime\r,\x08\x0cctime\r,\x08\x0cnone\r.\n" ++
        "  \x08------- Graphics options -------\r\n" ++
        "  \x08-i\r            Don't print indentation lines.\n" ++
        "  \x08-A\r            Print ANSI lines graphic indentation lines.\n" ++
        "  \x08-S\r            Print with CP437 (console) graphics indentation lines.\n" ++
        "  \x08-n\r            Turn colorization off always (\x08-C\r overrides).\n" ++
        "  \x08-C\r            Turn colorization on always.\n" ++
        "  \x08--compress\r \x0c#\r  Compress indentation lines.\n" ++
        "  \x08------- XML/HTML/JSON/HYPERLINK options -------\r\n" ++
        "  \x08-X\r            Prints out an XML representation of the tree.\n" ++
        "  \x08-J\r            Prints out an JSON representation of the tree.\n" ++
        "  \x08-H\r \x0cbaseHREF\r   Prints out HTML format with \x0cbaseHREF\r as top directory.\n" ++
        "  \x08-T\r \x0cstring\r     Replace the default HTML title and H1 header with \x0cstring\r.\n" ++
        "  \x08--nolinks\r     Turn off hyperlinks in HTML output.\n" ++
        "  \x08--hintro\r \x0cX\r    Use file \x0cX\r as the HTML intro.\n" ++
        "  \x08--houtro\r \x0cX\r    Use file \x0cX\r as the HTML outro.\n" ++
        "  \x08--hyperlink\r   Turn on OSC 8 terminal hyperlinks.\n" ++
        "  \x08--scheme\r \x0cX\r    Set OSC 8 hyperlink scheme, default \x08\x0cfile://\r\n" ++
        "  \x08--authority\r \x0cX\r Set OSC 8 hyperlink authority/hostname.\n" ++
        "  \x08------- Input options -------\r\n" ++
        "  \x08--fromfile\r    Reads paths from files (\x08.\r=stdin)\n" ++
        "  \x08--fromtabfile\r Reads trees from tab indented files (\x08.\r=stdin)\n" ++
        "  \x08--fflinks\r     Process link information when using \x08--fromfile\r.\n" ++
        "  \x08------- Miscellaneous options -------\r\n" ++
        "  \x08--opt-toggle\r  Enable option toggling.\n" ++
        "  \x08--version\r     Print version and exit.\n" ++
        "  \x08--help\r        Print usage and this help message and exit.\n" ++
        "  \x08--\r            Options processing terminator.\n"));
}

export fn tree_main(argc: c_int, argv: [*c][*c]u8) c_int {
    var dirname: [*c][*c]u8 = null;
    var i: usize = 0;
    var j: usize = 0;
    var k: usize = 0;
    var n: usize = 0;
    var p: usize = 0;
    var q: usize = 0;
    var optf: bool = true;
    var outfilename: [*c]u8 = null;
    var arg: [*c]u8 = undefined;
    var needfulltree: bool = undefined;
    var showversion: bool = false;
    var opt_toggle: bool = false;

    @memset(@as([*]u8, @ptrCast(&flag))[0..@sizeOf(c.struct_Flags)], 0);

    maxdirs = c.PATH_MAX;
    dirs = @ptrCast(@alignCast(c.xmalloc(@sizeOf(c_int) * maxdirs)));
    @memset(@as([*]u8, @ptrCast(dirs))[0 .. @sizeOf(c_int) * maxdirs], 0);
    dirs[0] = 0;
    Level = -1;

    _ = c.setlocale(c.LC_CTYPE, "");
    _ = c.setlocale(c.LC_COLLATE, "");

    charset = c.getcharset();
    if (charset == null) {
        const codeset = c.nl_langinfo(c.CODESET);
        if (c.strcmp(codeset, "UTF-8") == 0 or c.strcmp(codeset, "utf8") == 0) {
            charset = "UTF-8";
        }
    }

    const noop = struct {
        fn noop() callconv(.c) void {}
        fn close(_: [*c]c.struct__info, _: c_int, _: c_int) callconv(.c) void {} // file, level, needcomma
    };

    lc = c.struct_listingcalls{
        .intro = noop.noop,
        .outtro = noop.noop,
        .printinfo = c.unix_printinfo,
        .printfile = c.unix_printfile,
        .@"error" = c.unix_error,
        .newline = c.unix_newline,
        .close = noop.close,
        .report = c.unix_report,
    };

    // Still a hack, but assume that if the macro is defined, we can use it:
    mb_cur_max = getMbCurMax();

    if (comptime builtin.os.tag == .linux) {
        // Output JSON automatically to "stddata" if present:
        const stddata_fd_str = c.getenv(c.ENV_STDDATA_FD);
        if (stddata_fd_str != null) {
            var std_fd: c_int = c.atoi(stddata_fd_str);
            if (std_fd <= 0) std_fd = c.STDDATA_FILENO;
            if (c.fcntl(std_fd, c.F_GETFD) >= 0) {
                flag.J = true;
                flag.noindent = true;
                _nl = "";
                lc = c.struct_listingcalls{
                    .intro = c.json_intro,
                    .outtro = c.json_outtro,
                    .printinfo = c.json_printinfo,
                    .printfile = c.json_printfile,
                    .@"error" = c.json_error,
                    .newline = c.json_newline,
                    .close = c.json_close,
                    .report = c.json_report,
                };
                outfile = c.fdopen(std_fd, "w");
            }
        }
    }

    n = 1;
    i = 1;
    while (i < @as(usize, @intCast(argc))) : (i = n) {
        n += 1;
        if (optf and argv[i][0] == '-' and argv[i][1] != 0) {
            j = 1;
            while (argv[i][j] != 0) : (j += 1) {
                switch (argv[i][j]) {
                    'N' => flag.N = if (opt_toggle) !flag.N else true,
                    'q' => flag.q = if (opt_toggle) !flag.q else true,
                    'Q' => flag.Q = if (opt_toggle) !flag.Q else true,
                    'd' => flag.d = if (opt_toggle) !flag.d else true,
                    'l' => flag.l = if (opt_toggle) !flag.l else true,
                    's' => flag.s = if (opt_toggle) !flag.s else true,
                    'h' => {
                        // Assume they also want -s
                        flag.h = if (opt_toggle) !flag.h else true;
                        flag.s = flag.h;
                    },
                    'u' => flag.u = if (opt_toggle) !flag.u else true,
                    'g' => flag.g = if (opt_toggle) !flag.g else true,
                    'f' => flag.f = if (opt_toggle) !flag.f else true,
                    'F' => flag.F = if (opt_toggle) !flag.F else true,
                    'a' => flag.a = if (opt_toggle) !flag.a else true,
                    'p' => flag.p = if (opt_toggle) !flag.p else true,
                    'i' => {
                        flag.noindent = if (opt_toggle) !flag.noindent else true;
                        _nl = "";
                    },
                    'C' => flag.force_color = if (opt_toggle) !flag.force_color else true,
                    'n' => flag.nocolor = if (opt_toggle) !flag.nocolor else true,
                    'x' => flag.xdev = if (opt_toggle) !flag.xdev else true,
                    'P' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -P option.\n");
                            c.exit(c.EXIT_FAILURE);
                        }
                        if (pattern >= maxpattern - 1)
                            patterns = @ptrCast(@alignCast(c.xrealloc(@ptrCast(patterns), @sizeOf([*c]u8) * @as(usize, @intCast(maxpattern + 10)))));
                        maxpattern += 10;
                        patterns[@intCast(pattern)] = argv[n];
                        pattern += 1;
                        n += 1;
                        patterns[@intCast(pattern)] = null;
                    },
                    'I' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -I option.\n");
                            c.exit(c.EXIT_FAILURE);
                        }
                        if (ipattern >= maxipattern - 1)
                            ipatterns = @ptrCast(@alignCast(c.xrealloc(@ptrCast(ipatterns), @sizeOf([*c]u8) * @as(usize, @intCast(maxipattern + 10)))));
                        maxipattern += 10;
                        ipatterns[@intCast(ipattern)] = argv[n];
                        ipattern += 1;
                        n += 1;
                        ipatterns[@intCast(ipattern)] = null;
                    },
                    'A' => flag.ansilines = if (opt_toggle) !flag.ansilines else true,
                    'S' => charset = "IBM437",
                    'D' => flag.D = if (opt_toggle) !flag.D else true,
                    't' => basesort = &mtimesort,
                    'c' => {
                        basesort = &ctimesort;
                        flag.c = true;
                    },
                    'r' => flag.reverse = if (opt_toggle) !flag.reverse else true,
                    'v' => basesort = &versort,
                    'U' => basesort = null,
                    'X' => {
                        flag.X = true;
                        flag.H = false;
                        flag.J = false;
                        lc = c.struct_listingcalls{
                            .intro = c.xml_intro,
                            .outtro = c.xml_outtro,
                            .printinfo = c.xml_printinfo,
                            .printfile = c.xml_printfile,
                            .@"error" = c.xml_error,
                            .newline = c.xml_newline,
                            .close = c.xml_close,
                            .report = c.xml_report,
                        };
                    },
                    'J' => {
                        flag.J = true;
                        flag.X = false;
                        flag.H = false;
                        lc = c.struct_listingcalls{
                            .intro = c.json_intro,
                            .outtro = c.json_outtro,
                            .printinfo = c.json_printinfo,
                            .printfile = c.json_printfile,
                            .@"error" = c.json_error,
                            .newline = c.json_newline,
                            .close = c.json_close,
                            .report = c.json_report,
                        };
                    },
                    'H' => {
                        flag.H = true;
                        flag.X = false;
                        flag.J = false;
                        lc = c.struct_listingcalls{
                            .intro = c.html_intro,
                            .outtro = c.html_outtro,
                            .printinfo = c.html_printinfo,
                            .printfile = c.html_printfile,
                            .@"error" = c.html_error,
                            .newline = c.html_newline,
                            .close = c.html_close,
                            .report = c.html_report,
                        };
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -H option.\n");
                            c.exit(c.EXIT_FAILURE);
                        }
                        host = argv[n];
                        n += 1;
                        k = c.strlen(host) - 1;
                        if (host[0] == '-') {
                            flag.htmloffset = true;
                            host += 1;
                        }
                        // Allows a / if that is the only character as the 'host':
                        //      if (k && host[k] == '/') host[k] = '\0';
                        sp = "&nbsp;";
                    },
                    'T' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -T option.\n");
                            c.exit(c.EXIT_FAILURE);
                        }
                        title = argv[n];
                        n += 1;
                    },
                    'R' => flag.R = if (opt_toggle) !flag.R else true,
                    'L' => {
                        if (c.isdigit(argv[i][j + 1]) != 0) {
                            k = 0;
                            while (argv[i][j + 1 + k] != 0 and c.isdigit(argv[i][j + 1 + k]) != 0 and k < c.PATH_MAX - 1) : (k += 1) {
                                xpattern[k] = argv[i][j + 1 + k];
                            }
                            xpattern[k] = 0;
                            j += k;
                            sLevel = &xpattern;
                        } else {
                            sLevel = argv[n];
                            n += 1;
                            if (sLevel == null) {
                                _ = c.fprintf(cStderr(), "tree: Missing argument to -L option.\n");
                                c.exit(c.EXIT_FAILURE);
                            }
                        }
                        Level = @intCast(c.strtoul(sLevel, null, 0));
                        Level -= 1;
                        if (Level < 0) {
                            _ = c.fprintf(cStderr(), "tree: Invalid level, must be greater than 0.\n");
                            c.exit(c.EXIT_FAILURE);
                        }
                    },
                    'o' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -o option.\n");
                            c.exit(c.EXIT_FAILURE);
                        }
                        outfilename = argv[n];
                        n += 1;
                    },
                    '-' => {
                        if (j == 1) {
                            if (c.strcmp("--", argv[i]) == 0) {
                                optf = false;
                                break;
                            }
                            // Long options that don't take parameters should just use strcmp:
                            if (c.strcmp("--help", argv[i]) == 0) {
                                print_help();
                                c.exit(c.EXIT_SUCCESS);
                            }
                            if (c.strcmp("--version", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                showversion = true;
                                break;
                            }
                            if (c.strcmp("--inodes", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.inode = if (opt_toggle) !flag.inode else true;
                                break;
                            }
                            if (c.strcmp("--device", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.dev = if (opt_toggle) !flag.dev else true;
                                break;
                            }
                            if (c.strcmp("--noreport", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.noreport = if (opt_toggle) !flag.noreport else true;
                                break;
                            }
                            if (c.strcmp("--nolinks", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.nolinks = if (opt_toggle) !flag.nolinks else true;
                                break;
                            }
                            if (c.strcmp("--dirsfirst", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                topsort = &dirsfirst;
                                break;
                            }
                            if (c.strcmp("--filesfirst", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                topsort = &filesfirst;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--filelimit");
                            if (arg != null) {
                                flag.flimit = c.atoi(arg);
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--charset");
                            if (arg != null) {
                                charset = arg;
                                break;
                            }
                            if (c.strcmp("--si", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.si = if (opt_toggle) !flag.si else true;
                                flag.s = flag.si;
                                flag.h = flag.si;
                                break;
                            }
                            if (c.strcmp("--du", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.du = if (opt_toggle) !flag.du else true;
                                flag.s = flag.du;
                                break;
                            }
                            if (c.strcmp("--prune", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.prune = if (opt_toggle) !flag.prune else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--timefmt");
                            if (arg != null) {
                                timefmt = c.scopy(arg);
                                flag.D = true;
                                break;
                            }
                            if (c.strcmp("--ignore-case", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.ignorecase = if (opt_toggle) !flag.ignorecase else true;
                                break;
                            }
                            if (c.strcmp("--matchdirs", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.matchdirs = if (opt_toggle) !flag.matchdirs else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--sort");
                            if (arg != null) {
                                basesort = null;
                                k = 0;
                                while (sorts[k].name != null) : (k += 1) {
                                    if (c.strcasecmp(sorts[k].name, arg) == 0) {
                                        basesort = sorts[k].cmpfunc;
                                        break;
                                    }
                                }
                                if (sorts[k].name == null) {
                                    _ = c.fprintf(cStderr(), "tree: Sort type '%s' not valid, should be one of: ", arg);
                                    k = 0;
                                    while (sorts[k].name != null) : (k += 1) {
                                        _ = c.printf("%s%c", sorts[k].name, @as(c_int, if (sorts[k + 1].name != null) ',' else '\n'));
                                    }
                                    c.exit(c.EXIT_FAILURE);
                                }
                                break;
                            }
                            if (c.strcmp("--fromtabfile", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.fromfile = true;
                                getfulltree = &c.tabedfile_getfulltree;
                                break;
                            }
                            if (c.strcmp("--fromfile", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.fromfile = true;
                                getfulltree = &c.file_getfulltree;
                                break;
                            }
                            if (c.strcmp("--metafirst", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.metafirst = if (opt_toggle) !flag.metafirst else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--gitfile");
                            if (arg != null) {
                                flag.gitignore = true;
                                const new_ig = c.new_ignorefile(arg, arg, false);
                                if (new_ig != null) c.push_filterstack(new_ig) else {
                                    _ = c.fprintf(cStderr(), "tree: Could not load gitignore file\n");
                                    c.exit(c.EXIT_FAILURE);
                                }
                                break;
                            }
                            if (c.strcmp("--gitignore", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.gitignore = if (opt_toggle) !flag.gitignore else true;
                                break;
                            }
                            if (c.strcmp("--info", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.showinfo = if (opt_toggle) !flag.showinfo else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--infofile");
                            if (arg != null) {
                                flag.showinfo = true;
                                const new_inf = c.new_infofile(arg, false);
                                if (new_inf != null) c.push_infostack(new_inf) else {
                                    _ = c.fprintf(cStderr(), "tree: Could not load infofile\n");
                                    c.exit(c.EXIT_FAILURE);
                                }
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--hintro");
                            if (arg != null) {
                                Hintro = c.scopy(arg);
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--houtro");
                            if (arg != null) {
                                Houtro = c.scopy(arg);
                                break;
                            }
                            if (c.strcmp("--fflinks", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.fflinks = if (opt_toggle) !flag.fflinks else true;
                                break;
                            }
                            if (c.strcmp("--hyperlink", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.hyper = if (opt_toggle) !flag.hyper else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--scheme");
                            if (arg != null) {
                                if (c.strchr(arg, ':') == null) {
                                    _ = c.sprintf(&xpattern, "%s://", arg);
                                    arg = c.scopy(&xpattern);
                                } else {
                                    scheme = c.scopy(arg);
                                }
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--authority");
                            if (arg != null) {
                                // I don't believe that . by itself can be a valid hostname,
                                // so it will do as a null authority.
                                if (c.strcmp(arg, ".") == 0) authority = c.scopy("") else authority = c.scopy(arg);
                                break;
                            }
                            if (c.strcmp("--opt-toggle", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                opt_toggle = !opt_toggle;
                                break;
                            }
                            if (c.strcmp("--condense", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.condense_singletons = if (opt_toggle) !flag.condense_singletons else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--compress");
                            if (arg != null) {
                                flag.compress_indent = c.atoi(arg);
                                flag.remove_space = flag.compress_indent < 0;
                                if (flag.compress_indent < 0) {
                                    flag.compress_indent = -flag.compress_indent;
                                }
                                if (flag.compress_indent > 3) {
                                    flag.compress_indent = 0;
                                    flag.noindent = true;
                                    _nl = "";
                                }
                                if (flag.compress_indent > 0) flag.compress_indent -= 1;
                                break;
                            }
                            if (comptime builtin.os.tag == .linux) {
                                if (c.strcmp("--acl", argv[i]) == 0) {
                                    j = c.strlen(argv[i]) - 1;
                                    flag.acl = if (opt_toggle) !flag.acl else true;
                                    if (flag.acl) flag.p = true;
                                    break;
                                }
                                if (c.strcmp("--selinux", argv[i]) == 0) {
                                    j = c.strlen(argv[i]) - 1;
                                    flag.selinux = if (opt_toggle) !flag.selinux else true;
                                    break;
                                }
                            }
                            _ = c.fprintf(cStderr(), "tree: Invalid argument `%s'.\n", argv[i]);
                            print_usage();
                            c.exit(c.EXIT_FAILURE);
                        }
                        // Falls through
                        _ = c.fprintf(cStderr(), "tree: Invalid argument -`%c'.\n", @as(c_int, argv[i][j]));
                        print_usage();
                        c.exit(c.EXIT_FAILURE);
                    },
                    else => {
                        // printf("here i = %d, n = %d\n", i, n);
                        _ = c.fprintf(cStderr(), "tree: Invalid argument -`%c'.\n", @as(c_int, argv[i][j]));
                        print_usage();
                        c.exit(c.EXIT_FAILURE);
                    },
                }
            }
        } else {
            if (dirname == null) {
                dirname = @ptrCast(@alignCast(c.xmalloc(@sizeOf([*c]u8) * (q + c.MINIT))));
                q = c.MINIT;
            } else if (p == (q - 1)) {
                dirname = @ptrCast(@alignCast(c.xrealloc(@ptrCast(dirname), @sizeOf([*c]u8) * (q + c.MINC))));
                q += c.MINC;
            }
            dirname[p] = c.scopy(argv[i]);
            p += 1;
        }
    }
    if (p != 0) dirname[p] = null;

    setoutput(outfilename);

    c.parse_dir_colors();
    c.initlinedraw(false);

    if (showversion) {
        _ = c.fprintf(outfile, "%s\n", version);
        c.exit(c.EXIT_SUCCESS);
    }

    // Insure sensible defaults and sanity check options:
    if (dirname == null) {
        dirname = @ptrCast(@alignCast(c.xmalloc(@sizeOf([*c]u8) * 2)));
        dirname[0] = c.scopy(".");
        dirname[1] = null;
    }
    if (topsort == null) topsort = basesort;
    if (basesort == null) topsort = null;
    if (timefmt != null) _ = c.setlocale(c.LC_TIME, "");
    if (flag.d) flag.prune = false; // You'll just get nothing otherwise.
    if (flag.R and Level == -1) flag.R = false;

    if (flag.hyper and authority == null) {
        // If the hostname is longer than PATH_MAX, maybe it's just as well we don't
        // try to use it.
        if (c.gethostname(&xpattern, c.PATH_MAX) < 0) {
            _ = c.fprintf(cStderr(), "Unable to get hostname, using 'localhost'.\n");
            authority = @constCast("localhost");
        } else {
            authority = c.scopy(&xpattern);
        }
    }

    if (flag.showinfo) {
        c.push_infostack(c.new_infofile(c.INFO_PATH, false));
    }

    needfulltree = flag.du or flag.prune or flag.matchdirs or flag.fromfile or flag.condense_singletons;

    c.emit_tree(dirname, needfulltree);

    if (outfilename != null) _ = c.fclose(outfile);

    return if (errors != 0) 2 else 0;
}
