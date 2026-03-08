const std = @import("std");

const man = @import("man.zig");
const c = @cImport({
    @cDefine("_DEFAULT_SOURCE", "");
    @cInclude("tree.h");
});

// tree_main has been migrated to Zig (Phase 8); forward declaration removed.

// strverscmp is compiled as a separate linked object (src/strverscmp.zig)
extern fn strverscmp(s1: [*:0]const u8, s2: [*:0]const u8) c_int;

// Include tests from strverscmp module
test {
    _ = @import("strverscmp.zig");
}

// ----------------------------------------------------------------------------
// Globals migrated from tree.c
//
// All are exported with C linkage so the remaining C files can reference them
// via the existing `extern` declarations.  The function-pointer globals
// (getfulltree, basesort, topsort) and the conditional mode-type tables
// (ifmt/fmt/ftype) stay in tree.c until the functions that own them move here.
// ----------------------------------------------------------------------------

var version_lit = "bo (The Bodhi Tree) v0.0.2".*;
export var version: [*c]u8 = @ptrCast(&version_lit);

// Option flags
export var dflag: bool = false;
export var lflag: bool = false;
export var pflag: bool = false;
export var sflag: bool = false;
export var Fflag: bool = false;
export var aflag: bool = false;
export var fflag: bool = false;
export var uflag: bool = false;
export var gflag: bool = false;

export var qflag: bool = false;
export var Nflag: bool = false;
export var Qflag: bool = false;
export var Dflag: bool = false;
export var inodeflag: bool = false;
export var devflag: bool = false;
export var hflag: bool = false;
export var Rflag: bool = false;

export var Hflag: bool = false;
export var siflag: bool = false;
export var cflag: bool = false;
export var Xflag: bool = false;
export var Jflag: bool = false;
export var duflag: bool = false;
export var pruneflag: bool = false;
export var hyperflag: bool = false;

export var noindent: bool = false;
export var force_color: bool = false;
export var nocolor: bool = false;
export var xdev: bool = false;
export var noreport: bool = false;
export var nolinks: bool = false;

export var ignorecase: bool = false;
export var matchdirs: bool = false;
export var fromfile: bool = false;
export var metafirst: bool = false;
export var gitignore: bool = false;
export var showinfo: bool = false;

export var reverse: bool = false;
export var fflinks: bool = false;
export var htmloffset: bool = false;

export var flimit: c_int = 0;

// Output format dispatch table; tree_main() initialises the fields before use.
export var lc: c.struct_listingcalls = std.mem.zeroes(c.struct_listingcalls);

// Pattern matching state
export var pattern: c_int = 0;
export var maxpattern: c_int = 0;
export var ipattern: c_int = 0;
export var maxipattern: c_int = 0;
export var patterns: [*c][*c]u8 = null;
export var ipatterns: [*c][*c]u8 = null;

// String/pointer options
export var host: [*c]u8 = null;
var title_lit = "Directory Tree".*;
export var title: [*c]u8 = @ptrCast(&title_lit);
var sp_lit = " ".*;
export var sp: [*c]u8 = @ptrCast(&sp_lit);
var nl_lit = "\n".*;
export var _nl: [*c]u8 = @ptrCast(&nl_lit);
export var Hintro: [*c]u8 = null;
export var Houtro: [*c]u8 = null;
var scheme_lit = "file://".*;
export var scheme: [*c]u8 = @ptrCast(&scheme_lit);
export var authority: [*c]u8 = null;
var file_comment_lit = "#".*;
export var file_comment: [*c]u8 = @ptrCast(&file_comment_lit);
var file_pathsep_lit = "/".*;
export var file_pathsep: [*c]u8 = @ptrCast(&file_pathsep_lit);
export var timefmt: [*c]u8 = null;
export var charset: [*c]const u8 = null;

// Directory traversal state
export var sLevel: [*c]u8 = null;
export var curdir: [*c]u8 = null;
export var outfile: ?*c.FILE = null;
export var dirs: [*c]c_int = null;
export var Level: isize = 0;
export var maxdirs: usize = 0;
export var errors: c_int = 0;

// Scratch buffer; 4096 == PATH_MAX on Linux/macOS.
export var xpattern: [4096]u8 = std.mem.zeroes([4096]u8);

export var mb_cur_max: c_int = 0;

// ----------------------------------------------------------------------------
// Memory / directory utility functions migrated from tree.c (Phase 3)
//
// All four are called from other C files, so they keep export + callconv(.C).
// xmalloc/xrealloc mirror the C originals: exit on allocation failure so
// callers never need to handle a null return.
// ----------------------------------------------------------------------------

fn oom() noreturn {
    std.debug.print("tree: virtual memory exhausted.\n", .{});
    std.process.exit(1);
}

export fn xmalloc(size: usize) ?*anyopaque {
    return c.malloc(size) orelse oom();
}

export fn xrealloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    return c.realloc(ptr, size) orelse oom();
}

// Free a null-terminated array of _info pointers (and each entry's strings).
export fn free_dir(d: [*c]?*c.struct__info) void {
    var i: usize = 0;
    while (d[i]) |entry| : (i += 1) {
        c.free(@ptrCast(entry.name));
        if (entry.lnk != null) c.free(@ptrCast(entry.lnk));
        c.free(@ptrCast(entry));
    }
    c.free(@ptrCast(d));
}

// Grow-and-retry wrapper around getcwd(); caller owns the returned buffer.
export fn gnu_getcwd() [*c]u8 {
    var size: usize = 100;
    var buf: [*c]u8 = @ptrCast(xmalloc(size));
    while (true) {
        if (c.getcwd(buf, size) != null) return buf;
        size *= 2;
        c.free(@ptrCast(buf));
        buf = @ptrCast(xmalloc(size));
    }
}

// ----------------------------------------------------------------------------
// Pattern matching functions migrated from tree.c (Phase 4 — idiomatic Zig)
//
// patmatch/patignore/patinclude are all declared in tree.h, so the export
// symbols satisfy any remaining C callers (e.g. filter.c calls patmatch).
// ----------------------------------------------------------------------------

fn condLower(ch: u8) u8 {
    return if (ignorecase) std.ascii.toLower(ch) else ch;
}

/// Glob pattern match — idiomatic Zig core (slices, no pointer arithmetic).
/// Returns 1 on match, 0 on mismatch, -1 on pattern syntax error.
fn patMatchSlice(buf_in: []const u8, pat_in: []const u8, isdir: bool) c_int {
    // '|' alternation: try left side, then right side.
    if (std.mem.indexOfScalar(u8, pat_in, '|')) |bar| {
        if (bar == 0 or bar == pat_in.len - 1) return -1;
        const left = patMatchSlice(buf_in, pat_in[0..bar], isdir);
        if (left != 0) return left;
        return patMatchSlice(buf_in, pat_in[bar + 1 ..], isdir);
    }

    var buf = buf_in;
    var pat = pat_in;
    var match: c_int = 1;
    var pprev: u8 = 0;

    while (pat.len > 0 and match > 0) {
        switch (pat[0]) {
            '[' => {
                pat = pat[1..]; // consume '['
                // Negated class [^...]: hit value 0 means "found → no match".
                // Normal class  [...]:  hit value 1 means "found → match".
                const hit: c_int = if (pat.len > 0 and pat[0] == '^') blk: {
                    pat = pat[1..]; // consume '^'
                    break :blk 0;
                } else blk: {
                    match = 0; // unmatched until we find a class member
                    break :blk 1;
                };
                inner: while (pat.len > 0 and pat[0] != ']') {
                    if (pat[0] == '\\') pat = pat[1..];
                    if (pat.len == 0) return -1; // unterminated escape
                    if (pat.len > 1 and pat[1] == '-') {
                        const lo = pat[0];
                        pat = pat[2..]; // consume lo and '-'
                        if (pat.len > 0 and pat[0] == '\\') pat = pat[1..];
                        if (buf.len > 0 and
                            condLower(buf[0]) >= condLower(lo) and
                            condLower(buf[0]) <= condLower(pat[0]))
                        {
                            match = hit;
                        }
                        if (pat.len == 0) break :inner; // range end was last char
                    } else {
                        if (buf.len > 0 and condLower(buf[0]) == condLower(pat[0]))
                            match = hit;
                    }
                    pat = pat[1..];
                }
                if (pat.len == 0) return -1; // unterminated '['
                // pat[0] is ']'; outer loop will advance past it.
                if (buf.len > 0) buf = buf[1..];
            },
            '*' => {
                pat = pat[1..]; // consume first '*'
                if (pat.len == 0) {
                    // Trailing '*' matches any name without a '/'.
                    return @intFromBool(std.mem.indexOfScalar(u8, buf, '/') == null);
                }
                match = 0;
                if (pat[0] == '*') {
                    pat = pat[1..]; // consume second '*'
                    if (pat.len == 0) return 1; // trailing '**' matches everything
                    while (buf.len > 0) {
                        const m = patMatchSlice(buf, pat, isdir);
                        match = m;
                        if (m != 0) break;
                        // '**' between two '/'s may match an empty path component.
                        if (pprev == '/' and pat[0] == '/' and pat.len > 1) {
                            const m2 = patMatchSlice(buf, pat[1..], isdir);
                            if (m2 != 0) return m2;
                        }
                        buf = buf[1..];
                        while (buf.len > 0 and buf[0] != '/') buf = buf[1..];
                    }
                } else {
                    // Single '*': match any sequence not containing '/'.
                    while (buf.len > 0) {
                        const m = patMatchSlice(buf, pat, isdir);
                        buf = buf[1..]; // mirrors C's buf++ in loop condition
                        if (m != 0) {
                            match = m;
                            break;
                        }
                        if (buf.len > 0 and buf[0] == '/') break;
                    }
                }
                if (match == 0 and (buf.len == 0 or buf[0] == '/'))
                    match = patMatchSlice(buf, pat, isdir);
                return match;
            },
            '?' => {
                if (buf.len == 0) return 0;
                buf = buf[1..];
            },
            '/' => {
                // Trailing '/' matches empty buf only when path is a directory.
                if (pat.len == 1 and buf.len == 0) return @intFromBool(isdir);
                match = @intFromBool(buf.len > 0 and buf[0] == pat[0]);
                if (buf.len > 0) buf = buf[1..];
            },
            '\\' => {
                pat = pat[1..]; // consume backslash; next char is literal
                if (pat.len == 0) break;
                match = @intFromBool(buf.len > 0 and condLower(buf[0]) == condLower(pat[0]));
                if (buf.len > 0) buf = buf[1..];
            },
            else => {
                match = @intFromBool(buf.len > 0 and condLower(buf[0]) == condLower(pat[0]));
                if (buf.len > 0) buf = buf[1..];
            },
        }
        pprev = pat[0];
        pat = pat[1..];
        if (match < 1) return match;
    }
    return if (buf.len == 0) match else 0;
}

/// C-exported entry point: converts C strings to slices and delegates.
export fn patmatch(buf_ptr: [*c]const u8, pat_ptr: [*c]const u8, isdir: bool) c_int {
    return patMatchSlice(std.mem.span(buf_ptr), std.mem.span(pat_ptr), isdir);
}

/// Returns non-zero if name matches any -I (ignore) pattern.
export fn patignore(name: [*c]const u8, isdir: bool) c_int {
    for (0..@as(usize, @intCast(ipattern))) |i| {
        if (patmatch(name, ipatterns[i], isdir) != 0) return 1;
    }
    return 0;
}

/// Returns non-zero if name matches any -P (include) pattern.
export fn patinclude(name: [*c]const u8, isdir: bool) c_int {
    for (0..@as(usize, @intCast(pattern))) |i| {
        if (patmatch(name, patterns[i], isdir) != 0) return 1;
    }
    return 0;
}

// ----------------------------------------------------------------------------
// Sort functions migrated from tree.c (Phase 5 — idiomatic Zig)
//
// filesfirst/dirsfirst call the `basesort` function-pointer global which is
// still in tree.c; they move in Phase 8 along with tree_main.
// All others are self-contained comparators over struct _info fields.
// ----------------------------------------------------------------------------

/// Raw size comparator used by fsizesort (descending: larger files first).
export fn sizecmp(a: c.off_t, b: c.off_t) c_int {
    if (a == b) return 0;
    return if (a < b) 1 else -1;
}

export fn alnumsort(a: [*c]?*c.struct__info, b: [*c]?*c.struct__info) c_int {
    const v = c.strcoll(a[0].?.name, b[0].?.name);
    return if (reverse) -v else v;
}

export fn versort(a: [*c]?*c.struct__info, b: [*c]?*c.struct__info) c_int {
    const v = strverscmp(
        @ptrCast(a[0].?.name),
        @ptrCast(b[0].?.name),
    );
    return if (reverse) -v else v;
}

export fn mtimesort(a: [*c]?*c.struct__info, b: [*c]?*c.struct__info) c_int {
    const ai = a[0].?;
    const bi = b[0].?;
    if (ai.mtime == bi.mtime) {
        const v = c.strcoll(ai.name, bi.name);
        return if (reverse) -v else v;
    }
    const v: c_int = if (ai.mtime < bi.mtime) -1 else 1;
    return if (reverse) -v else v;
}

export fn ctimesort(a: [*c]?*c.struct__info, b: [*c]?*c.struct__info) c_int {
    const ai = a[0].?;
    const bi = b[0].?;
    if (ai.ctime == bi.ctime) {
        const v = c.strcoll(ai.name, bi.name);
        return if (reverse) -v else v;
    }
    const v: c_int = if (ai.ctime < bi.ctime) -1 else 1;
    return if (reverse) -v else v;
}

export fn fsizesort(a: [*c]?*c.struct__info, b: [*c]?*c.struct__info) c_int {
    const ai = a[0].?;
    const bi = b[0].?;
    var v = sizecmp(ai.size, bi.size);
    if (v == 0) v = c.strcoll(ai.name, bi.name);
    return if (reverse) -v else v;
}

// ----------------------------------------------------------------------------
// Phase 6: format utilities migrated from tree.c

// Variables defined in color.c
extern var ansilines: bool;
extern var linedraw: ?*const c.struct_linedraw;

// Platform-specific file-type lookup tables (also used by json.c and xml.c)
fn makeIfmt() [if (@hasDecl(c, "S_IFPORT")) 10 else 8]c.mode_t {
    if (comptime @hasDecl(c, "S_IFPORT")) {
        return .{ c.S_IFREG, c.S_IFDIR, c.S_IFLNK, c.S_IFCHR, c.S_IFBLK, c.S_IFSOCK, c.S_IFIFO, c.S_IFDOOR, c.S_IFPORT, 0 };
    } else {
        return .{ c.S_IFREG, c.S_IFDIR, c.S_IFLNK, c.S_IFCHR, c.S_IFBLK, c.S_IFSOCK, c.S_IFIFO, 0 };
    }
}
export const ifmt = makeIfmt();

const fmt_arr: [*]const u8 = if (@hasDecl(c, "S_IFPORT")) "-dlcbspDP?" else "-dlcbsp?";

fn makeFtype() [if (@hasDecl(c, "S_IFPORT")) 11 else 9][*c]const u8 {
    if (comptime @hasDecl(c, "S_IFPORT")) {
        return .{ "file", "directory", "link", "char", "block", "socket", "fifo", "door", "port", "unknown", null };
    } else {
        return .{ "file", "directory", "link", "char", "block", "socket", "fifo", "unknown", null };
    }
}
export const ftype = makeFtype();

export fn print_version(nl: c_int) void {
    _ = c.fprintf(outfile, "%s%s", version, @as([*c]const u8, if (nl != 0) "\n" else ""));
}

export fn setoutput(filename: [*c]const u8) void {
    if (filename == null) {
        if (outfile == null) outfile = c.stdout;
    } else {
        outfile = c.fopen(filename, "w");
        if (outfile == null) {
            _ = c.fprintf(c.stderr, "tree: invalid filename '%s'\n", filename);
            c.exit(1);
        }
    }
}

export fn indent(maxlevel: c_int) void {
    if (maxlevel <= 0) return;
    const max: usize = @intCast(maxlevel);
    if (ansilines) {
        if (dirs[1] != 0) _ = c.fprintf(outfile, "\x1b(0");
        var i: usize = 1;
        while (i <= max and dirs[i] != 0) : (i += 1) {
            if (dirs[i + 1] != 0) {
                if (dirs[i] == 1) _ = c.fprintf(outfile, "\x78   ") else _ = c.printf("    ");
            } else {
                if (dirs[i] == 1) _ = c.fprintf(outfile, "\x74\x71\x71 ") else _ = c.fprintf(outfile, "\x6d\x71\x71 ");
            }
        }
        if (dirs[1] != 0) _ = c.fprintf(outfile, "\x1b(B");
    } else {
        if (Hflag) _ = c.fprintf(outfile, "\t");
        const ld = linedraw.?.*;
        var i: usize = 1;
        while (i <= max and dirs[i] != 0) : (i += 1) {
            _ = c.fprintf(outfile, "%s ", if (dirs[i + 1] != 0)
                (if (dirs[i] == 1) ld.vert else if (Hflag) @as([*c]const u8, "&nbsp;&nbsp;&nbsp;") else @as([*c]const u8, "   "))
            else
                (if (dirs[i] == 1) ld.vert_left else ld.corner));
        }
    }
}

var prot_buf: [11]u8 = undefined;

export fn prot(m: c.mode_t) [*c]u8 {
    const perms = "rwxrwxrwx";
    var i: usize = 0;
    while (ifmt[i] != 0 and (m & c.S_IFMT) != ifmt[i]) : (i += 1) {}
    prot_buf[0] = fmt_arr[i];
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

const SIXMONTHS: c.time_t = 6 * 31 * 24 * 60 * 60;
var do_date_buf: [256]u8 = undefined;

export fn do_date(t: c.time_t) [*c]u8 {
    const tm = c.localtime(&t);
    if (timefmt != null) {
        _ = c.strftime(&do_date_buf[0], 255, timefmt, tm);
        do_date_buf[255] = 0;
    } else {
        const cur = c.time(0);
        if (t > cur or (t + SIXMONTHS) < cur) {
            _ = c.strftime(&do_date_buf[0], 255, "%b %e  %Y", tm);
        } else {
            _ = c.strftime(&do_date_buf[0], 255, "%b %e %R", tm);
        }
    }
    return &do_date_buf[0];
}

export fn printit(s: [*c]const u8) void {
    if (Nflag) {
        if (Qflag) _ = c.fprintf(outfile, "\"%s\"", s) else _ = c.fprintf(outfile, "%s", s);
        return;
    }
    if (mb_cur_max > 1) {
        const cs: usize = c.strlen(s) + 1;
        const ws: [*c]c.wchar_t = @ptrCast(@alignCast(xmalloc(@sizeOf(c.wchar_t) * cs)));
        if (c.mbstowcs(ws, s, cs) != std.math.maxInt(usize)) {
            if (Qflag) _ = c.putc('"', outfile);
            var tp = ws;
            var rem = cs;
            while (tp[0] != 0 and rem > 1) : ({
                tp += 1;
                rem -= 1;
            }) {
                if (c.iswprint(@bitCast(@as(i32, tp[0]))) != 0) {
                    _ = c.fprintf(outfile, "%lc", @as(c.wint_t, @bitCast(@as(i32, tp[0]))));
                } else {
                    if (qflag) _ = c.putc('?', outfile) else _ = c.fprintf(outfile, "\\%03o", @as(c_uint, @bitCast(@as(i32, tp[0]))));
                }
            }
            if (Qflag) _ = c.putc('"', outfile);
            c.free(ws);
            return;
        }
        c.free(ws);
    }
    if (Qflag) _ = c.putc('"', outfile);
    var p = s;
    while (p[0] != 0) : (p += 1) {
        const ch: c_int = @as(c_int, p[0]);
        if ((ch >= 7 and ch <= 13) or ch == '\\' or (ch == '"' and Qflag) or (ch == ' ' and !Qflag)) {
            _ = c.putc('\\', outfile);
            if (ch > 13) _ = c.putc(ch, outfile) else _ = c.putc(@as(c_int, "abtnvfr"[@as(usize, @intCast(ch - 7))]), outfile);
        } else if (c.isprint(ch) != 0) {
            _ = c.putc(ch, outfile);
        } else {
            if (qflag) {
                if (mb_cur_max > 1 and ch > 127) _ = c.putc(ch, outfile) else _ = c.putc('?', outfile);
            } else _ = c.fprintf(outfile, "\\%03o", @as(c_uint, @intCast(ch)));
        }
    }
    if (Qflag) _ = c.putc('"', outfile);
}

export fn psize(buf: [*c]u8, size: c.off_t) c_int {
    const iec_unit: [*]const u8 = "BKMGTPEZY";
    const si_unit: [*]const u8 = "dkMGTPEZY";
    const unit: [*]const u8 = if (siflag) si_unit else iec_unit;
    const unit_size: c.off_t = if (siflag) 1000 else 1024;

    if (hflag or siflag) {
        var sz = size;
        var idx: c_int = if (sz < unit_size) 0 else 1;
        while (sz >= unit_size * unit_size) {
            idx += 1;
            sz = @divTrunc(sz, unit_size);
        }
        if (idx == 0) {
            return c.sprintf(buf, " %4d", @as(c_int, @intCast(sz)));
        } else {
            const fmt_str: [*c]const u8 = if (@divTrunc(sz + 52, unit_size) >= 10) " %3.0f%c" else " %3.1f%c";
            return c.sprintf(buf, fmt_str, @as(f64, @floatFromInt(sz)) / @as(f64, @floatFromInt(unit_size)), unit[@intCast(idx)]);
        }
    } else {
        return c.sprintf(buf, if (@sizeOf(c.off_t) == @sizeOf(c_longlong)) " %11lld" else " %9lld", @as(c_longlong, @intCast(size)));
    }
}

export fn Ftype(mode: c.mode_t) u8 {
    const m = mode & c.S_IFMT;
    if (!dflag and m == c.S_IFDIR) return '/';
    if (m == c.S_IFSOCK) return '=';
    if (m == c.S_IFIFO) return '|';
    if (m == c.S_IFLNK) return '@';
    if (comptime @hasDecl(c, "S_IFDOOR")) {
        if (m == c.S_IFDOOR) return '>';
    }
    if (m == c.S_IFREG and (mode & (c.S_IXUSR | c.S_IXGRP | c.S_IXOTH)) != 0) return '*';
    return 0;
}

export fn fillinfo(buf: [*c]u8, ent: ?*const c.struct__info) [*c]u8 {
    var n: c_int = 0;
    buf[0] = 0;
    const e = ent.?;
    if (inodeflag) n += c.sprintf(buf, " %7lld", @as(c_longlong, @intCast(e.linode)));
    if (devflag) n += c.sprintf(buf + @as(usize, @intCast(n)), " %3d", @as(c_int, @intCast(e.ldev)));
    if (pflag) n += c.sprintf(buf + @as(usize, @intCast(n)), " %s", prot(e.mode));
    if (uflag) n += c.sprintf(buf + @as(usize, @intCast(n)), " %-8.32s", c.uidtoname(e.uid));
    if (gflag) n += c.sprintf(buf + @as(usize, @intCast(n)), " %-8.32s", c.gidtoname(e.gid));
    if (sflag) n += psize(buf + @as(usize, @intCast(n)), e.size);
    if (Dflag) n += c.sprintf(buf + @as(usize, @intCast(n)), " %s", do_date(if (cflag) e.ctime else e.mtime));
    if (buf[0] == ' ') {
        buf[0] = '[';
        _ = c.sprintf(buf + @as(usize, @intCast(n)), "]");
    }
    return buf;
}

// ----------------------------------------------------------------------------
// Phase 7: filesystem traversal migrated from tree.c

// Function-pointer globals moved from tree.c (Phase 8)
const SortFn = fn ([*c]?*c.struct__info, [*c]?*c.struct__info) callconv(.c) c_int;
const GetfulltreeFn = fn ([*c]u8, c_ulong, c.dev_t, [*c]c.off_t, [*c][*c]u8) callconv(.c) [*c]?*c.struct__info;

export var basesort: ?*const SortFn = &alnumsort;
export var topsort: ?*const SortFn = null;
export var getfulltree: ?*const GetfulltreeFn = &unix_getfulltree;

// Hash tables defined in hash.c; needed to zero-initialise in treeMain.
extern var gtable: [256]?*c.struct_xtable;
extern var utable: [256]?*c.struct_xtable;
extern var itable: [256]?*c.struct_inotable;

// Platform-portable accessors for struct stat time fields.
// On Linux glibc the fields are st_atim/st_ctim/st_mtim (struct timespec).
// On macOS they are st_atimespec/st_ctimespec/st_mtimespec.
inline fn statAtime(st: *const c.struct_stat) c.time_t {
    if (comptime @hasField(c.struct_stat, "st_atim")) return st.st_atim.tv_sec;
    return st.st_atimespec.tv_sec;
}
inline fn statCtime(st: *const c.struct_stat) c.time_t {
    if (comptime @hasField(c.struct_stat, "st_ctim")) return st.st_ctim.tv_sec;
    return st.st_ctimespec.tv_sec;
}
inline fn statMtime(st: *const c.struct_stat) c.time_t {
    if (comptime @hasField(c.struct_stat, "st_mtim")) return st.st_mtim.tv_sec;
    return st.st_mtimespec.tv_sec;
}

// Zig equivalent of the scopy(x) macro: strcpy(xmalloc(strlen(x)+1), (x))
fn scopy(s: [*c]const u8) [*c]u8 {
    const len = c.strlen(s) + 1;
    return c.strcpy(@ptrCast(xmalloc(len).?), s);
}

var stat2info_buf: c.struct__info = std.mem.zeroes(c.struct__info);

export fn stat2info(st: ?*const c.struct_stat) ?*c.struct__info {
    const s = st.?;
    stat2info_buf.linode = s.st_ino;
    stat2info_buf.ldev = s.st_dev;
    stat2info_buf.mode = s.st_mode;
    stat2info_buf.uid = s.st_uid;
    stat2info_buf.gid = s.st_gid;
    stat2info_buf.size = s.st_size;
    stat2info_buf.atime = statAtime(s);
    stat2info_buf.ctime = statCtime(s);
    stat2info_buf.mtime = statMtime(s);
    stat2info_buf.isdir = (s.st_mode & c.S_IFMT) == c.S_IFDIR;
    stat2info_buf.issok = (s.st_mode & c.S_IFMT) == c.S_IFSOCK;
    stat2info_buf.isfifo = (s.st_mode & c.S_IFMT) == c.S_IFIFO;
    stat2info_buf.isexe = (s.st_mode & (c.S_IXUSR | c.S_IXGRP | c.S_IXOTH)) != 0;
    return &stat2info_buf;
}

var getinfo_lbuf: [*c]u8 = null;
var getinfo_lbufsize: usize = 0;

export fn getinfo(name: [*c]const u8, path: [*c]u8) ?*c.struct__info {
    var st: c.struct_stat = undefined;
    var lst: c.struct_stat = undefined;
    var rs: c_int = 0;

    if (getinfo_lbuf == null) {
        getinfo_lbufsize = @intCast(c.PATH_MAX);
        getinfo_lbuf = @ptrCast(xmalloc(getinfo_lbufsize).?);
    }

    if (c.lstat(path, &lst) < 0) return null;

    if ((lst.st_mode & c.S_IFMT) == c.S_IFLNK) {
        rs = c.stat(path, &st);
        if (rs < 0) _ = c.memset(&st, 0, @sizeOf(c.struct_stat));
    } else {
        rs = 0;
        st.st_mode = lst.st_mode;
        st.st_dev = lst.st_dev;
        st.st_ino = lst.st_ino;
    }

    const isdir: bool = (st.st_mode & c.S_IFMT) == c.S_IFDIR;
    if (gitignore and c.filtercheck(path, name, @intFromBool(isdir))) return null;

    if ((lst.st_mode & c.S_IFMT) != c.S_IFDIR and
        !(lflag and (st.st_mode & c.S_IFMT) == c.S_IFDIR))
    {
        if (pattern != 0 and patinclude(name, isdir) == 0) return null;
    }
    if (ipattern != 0 and patignore(name, isdir) != 0) return null;
    if (dflag and (st.st_mode & c.S_IFMT) != c.S_IFDIR) return null;

    const ent: *c.struct__info = @ptrCast(@alignCast(xmalloc(@sizeOf(c.struct__info)).?));
    _ = c.memset(ent, 0, @sizeOf(c.struct__info));

    ent.name = scopy(name);
    ent.mode = lst.st_mode;
    ent.uid = lst.st_uid;
    ent.gid = lst.st_gid;
    ent.size = lst.st_size;
    ent.dev = st.st_dev;
    ent.inode = st.st_ino;
    ent.ldev = lst.st_dev;
    ent.linode = lst.st_ino;
    ent.lnk = null;
    ent.orphan = false;
    ent.err = null;
    ent.child = null;
    ent.atime = statAtime(&lst);
    ent.ctime = statCtime(&lst);
    ent.mtime = statMtime(&lst);
    ent.isdir = isdir;
    ent.issok = (st.st_mode & c.S_IFMT) == c.S_IFSOCK;
    ent.isfifo = (st.st_mode & c.S_IFMT) == c.S_IFIFO;
    ent.isexe = (st.st_mode & (c.S_IXUSR | c.S_IXGRP | c.S_IXOTH)) != 0;

    if ((lst.st_mode & c.S_IFMT) == c.S_IFLNK) {
        const lsz: usize = @intCast(lst.st_size);
        if (lsz + 1 > getinfo_lbufsize) {
            getinfo_lbufsize = lsz + 8192;
            getinfo_lbuf = @ptrCast(xrealloc(getinfo_lbuf, getinfo_lbufsize).?);
        }
        const len: isize = c.readlink(path, getinfo_lbuf, getinfo_lbufsize - 1);
        if (len < 0) {
            ent.lnk = scopy("[Error reading symbolic link information]");
            ent.isdir = false;
            ent.lnkmode = st.st_mode;
        } else {
            getinfo_lbuf[@intCast(len)] = 0;
            ent.lnk = scopy(getinfo_lbuf);
            if (rs < 0) ent.orphan = true;
            ent.lnkmode = st.st_mode;
        }
    }

    ent.comment = null;
    return ent;
}

var read_dir_path: [*c]u8 = null;
var read_dir_pathsize: usize = 0;

export fn read_dir(dir: [*c]u8, n: [*c]isize, infotop: c_int) [*c]?*c.struct__info {
    const es: bool = dir[c.strlen(dir) - 1] == '/';

    if (read_dir_path == null) {
        read_dir_pathsize = c.strlen(dir) + @as(usize, @intCast(c.PATH_MAX));
        read_dir_path = @ptrCast(xmalloc(read_dir_pathsize).?);
    }

    n.* = -1;
    const d = c.opendir(dir);
    if (d == null) return null;

    var ne: usize = c.MINIT;
    var dl: [*c]?*c.struct__info = @ptrCast(@alignCast(xmalloc(@sizeOf(?*c.struct__info) * ne).?));
    var p: usize = 0;

    while (c.readdir(d)) |ent| {
        const ename: [*c]const u8 = @ptrCast(&ent[0].d_name);
        if (c.strcmp("..", ename) == 0 or c.strcmp(".", ename) == 0) continue;
        if (Hflag and c.strcmp("00Tree.html", ename) == 0) continue;
        if (!aflag and ename[0] == '.') continue;

        const dlen = c.strlen(dir);
        const elen = c.strlen(ename);
        if (dlen + elen + 2 > read_dir_pathsize) {
            read_dir_pathsize = dlen + elen + @as(usize, @intCast(c.PATH_MAX));
            read_dir_path = @ptrCast(xrealloc(read_dir_path, read_dir_pathsize).?);
        }
        if (es) _ = c.sprintf(read_dir_path, "%s%s", dir, ename) else _ = c.sprintf(read_dir_path, "%s/%s", dir, ename);

        if (getinfo(ename, read_dir_path)) |fi| {
            if (showinfo) {
                if (c.infocheck(read_dir_path, ename, infotop, fi.isdir)) |com| {
                    var i: usize = 0;
                    while (com[0].desc[i] != null) : (i += 1) {}
                    fi.comment = @ptrCast(@alignCast(xmalloc(@sizeOf([*c]u8) * (i + 1)).?));
                    i = 0;
                    while (com[0].desc[i] != null) : (i += 1) fi.comment[i] = scopy(com[0].desc[i]);
                    fi.comment[i] = null;
                }
            }
            if (p == ne - 1) {
                ne += c.MINC;
                dl = @ptrCast(@alignCast(xrealloc(@ptrCast(dl), @sizeOf(?*c.struct__info) * ne).?));
            }
            dl[p] = fi;
            p += 1;
        }
    }
    _ = c.closedir(d);

    n.* = @intCast(p);
    if (p == 0) {
        c.free(@ptrCast(dl));
        return null;
    }
    dl[p] = null;
    return dl;
}

export fn push_files(dir: [*c]const u8, ig: [*c]?*c.struct_ignorefile, inf: [*c]?*c.struct_infofile, top: bool) void {
    if (gitignore) {
        ig[0] = c.new_ignorefile(dir, top);
        if (ig[0] != null) c.push_filterstack(ig[0]);
    }
    if (showinfo) {
        inf[0] = c.new_infofile(dir, top);
        if (inf[0] != null) c.push_infostack(inf[0]);
    }
}

export fn unix_getfulltree(d: [*c]u8, lev: c_ulong, dev: c.dev_t, size: [*c]c.off_t, err: [*c][*c]u8) [*c]?*c.struct__info {
    var pathsize: usize = 0;
    var ig: ?*c.struct_ignorefile = null;
    var inf: ?*c.struct_infofile = null;
    var n: isize = 0;

    err[0] = null;
    if (Level >= 0 and lev > @as(c_ulong, @intCast(Level))) return null;

    var dev_cur = dev;
    if (xdev and lev == 0) {
        var sb: c.struct_stat = undefined;
        _ = c.stat(d, &sb);
        dev_cur = sb.st_dev;
    }

    var tmp_pattern: c_int = 0;
    if (matchdirs and pattern != 0) {
        var lev_tmp = lev;
        var start_rel = d + c.strlen(d);
        while (start_rel != d) {
            start_rel -= 1;
            if (start_rel[0] == '/') lev_tmp -%= 1;
            if (lev_tmp == 0) {
                if (start_rel[0] != 0) start_rel += 1;
                break;
            }
        }
        if (start_rel[0] != 0 and patinclude(start_rel, true) != 0) {
            tmp_pattern = pattern;
            pattern = 0;
        }
    }

    push_files(d, @ptrCast(&ig), @ptrCast(&inf), lev == 0);
    const sav = read_dir(d, &n, @intFromBool(inf != null));
    var dir_ptr = sav;

    if (tmp_pattern != 0) {
        pattern = tmp_pattern;
        tmp_pattern = 0;
    }
    if (dir_ptr == null and n != 0) {
        err[0] = scopy("error opening dir");
        return null;
    }
    if (n == 0) {
        if (sav != null) free_dir(sav);
        return null;
    }

    pathsize = @intCast(c.PATH_MAX);
    var path: [*c]u8 = @ptrCast(xmalloc(pathsize).?);

    if (flimit > 0 and n > @as(isize, @intCast(flimit))) {
        _ = c.sprintf(path, "%ld entries exceeds filelimit, not opening dir", n);
        err[0] = scopy(path);
        free_dir(sav);
        c.free(path);
        return null;
    }

    if (lev >= maxdirs - 1) {
        maxdirs += 1024;
        dirs = @ptrCast(@alignCast(xrealloc(dirs, @sizeOf(c_int) * maxdirs).?));
    }

    while (dir_ptr[0] != null) {
        const ep = dir_ptr[0].?;
        if (ep.isdir and !(xdev and dev_cur != ep.dev)) {
            if (ep.lnk != null) {
                if (lflag) {
                    if (c.findino(ep.inode, ep.dev)) {
                        ep.err = scopy("recursive, not followed");
                    } else {
                        c.saveino(ep.inode, ep.dev);
                        if (ep.lnk[0] == '/') {
                            ep.child = unix_getfulltree(ep.lnk, lev + 1, dev_cur, &ep.size, &ep.err);
                        } else {
                            const need = c.strlen(d) + c.strlen(ep.lnk) + 2;
                            if (need > pathsize) {
                                pathsize = c.strlen(d) + c.strlen(ep.name) + 1024;
                                path = @ptrCast(xrealloc(path, pathsize).?);
                            }
                            if (fflag and c.strcmp(d, "/") == 0)
                                _ = c.sprintf(path, "%s%s", d, ep.lnk)
                            else
                                _ = c.sprintf(path, "%s/%s", d, ep.lnk);
                            ep.child = unix_getfulltree(path, lev + 1, dev_cur, &ep.size, &ep.err);
                        }
                    }
                }
            } else {
                const need = c.strlen(d) + c.strlen(ep.name) + 2;
                if (need > pathsize) {
                    pathsize = c.strlen(d) + c.strlen(ep.name) + 1024;
                    path = @ptrCast(xrealloc(path, pathsize).?);
                }
                if (fflag and c.strcmp(d, "/") == 0)
                    _ = c.sprintf(path, "%s%s", d, ep.name)
                else
                    _ = c.sprintf(path, "%s/%s", d, ep.name);
                c.saveino(ep.inode, ep.dev);
                ep.child = unix_getfulltree(path, lev + 1, dev_cur, &ep.size, &ep.err);
            }
            if (pruneflag and ep.child == null and
                !(matchdirs and pattern != 0 and patinclude(ep.name, ep.isdir) != 0))
            {
                const xp = dir_ptr[0];
                var pp = dir_ptr;
                while (pp[0] != null) : (pp += 1) pp[0] = pp[1];
                n -= 1;
                c.free(xp.?.name);
                if (xp.?.lnk != null) c.free(xp.?.lnk);
                c.free(xp);
                continue;
            }
        }
        if (duflag) size.* += ep.size;
        dir_ptr += 1;
    }

    if (topsort) |sort_fn| {
        c.qsort(@ptrCast(sav), @intCast(n), @sizeOf(?*c.struct__info), @ptrCast(sort_fn));
    }

    c.free(path);
    if (n == 0) {
        free_dir(sav);
        return null;
    }
    if (ig != null) _ = c.pop_filterstack();
    if (inf != null) _ = c.pop_infostack();
    return sav;
}

// ----------------------------------------------------------------------------
// Phase 8: filesfirst / dirsfirst / sorts / long_arg / usage / tree_main

export fn filesfirst(a: [*c]?*c.struct__info, b: [*c]?*c.struct__info) c_int {
    if (a[0].?.isdir != b[0].?.isdir) return if (a[0].?.isdir) 1 else -1;
    return basesort.?(a, b);
}

export fn dirsfirst(a: [*c]?*c.struct__info, b: [*c]?*c.struct__info) c_int {
    if (a[0].?.isdir != b[0].?.isdir) return if (a[0].?.isdir) -1 else 1;
    return basesort.?(a, b);
}

const Sort = struct {
    name: [*c]const u8,
    cmpfunc: ?*const SortFn,
};
const sorts = [_]Sort{
    .{ .name = "name", .cmpfunc = &alnumsort },
    .{ .name = "version", .cmpfunc = &versort },
    .{ .name = "size", .cmpfunc = &fsizesort },
    .{ .name = "mtime", .cmpfunc = &mtimesort },
    .{ .name = "ctime", .cmpfunc = &ctimesort },
    .{ .name = "none", .cmpfunc = null },
    .{ .name = null, .cmpfunc = null },
};

fn longArg(argv: [*c][*c]u8, i: usize, j: *usize, n: *usize, prefix: [*:0]const u8) [*c]u8 {
    const len = c.strlen(prefix);
    if (c.strncmp(prefix, @as([*c]const u8, argv[i]), len) != 0) return null;
    j.* = len;
    if (argv[i][j.*] == '=') {
        j.* += 1;
        if (argv[i][j.*] != 0) {
            const ret: [*c]u8 = argv[i] + j.*;
            j.* = c.strlen(argv[i]) - 1;
            return ret;
        }
        _ = c.fprintf(c.stderr, "tree: Missing argument to %s=\n", prefix);
        if (c.strcmp(prefix, "--charset=") == 0) c.initlinedraw(true);
        c.exit(1);
    } else if (argv[n.*] != null) {
        const ret: [*c]u8 = argv[n.*];
        n.* += 1;
        j.* = c.strlen(argv[i]) - 1;
        return ret;
    } else {
        _ = c.fprintf(c.stderr, "tree: Missing argument to %s\n", prefix);
        if (c.strcmp(prefix, "--charset") == 0) c.initlinedraw(true);
        c.exit(1);
    }
    return null;
}

// \x08 = \b (bold-on marker for fancy()), \x0C = \f (italic-on marker for fancy())
export fn usage(n: c_int) void {
    c.parse_dir_colors();
    c.initlinedraw(false);
    c.fancy(if (n < 2) c.stderr else c.stdout, @constCast("usage: \x08tree\r [\x08-acdfghilnpqrstuvxACDFJQNSUX\r] [\x08-L\r \x0Clevel\r [\x08-R\r]] [\x08-H\r [-]\x0CbaseHREF\r]\n" ++
        "\t[\x08-T\r \x0Ctitle\r] [\x08-o\r \x0Cfilename\r] [\x08-P\r \x0Cpattern\r] [\x08-I\r \x0Cpattern\r] [\x08--gitignore\r]\n" ++
        "\t[\x08--gitfile\r[\x08=\r]\x0Cfile\r] [\x08--matchdirs\r] [\x08--metafirst\r] [\x08--ignore-case\r]\n" ++
        "\t[\x08--nolinks\r] [\x08--hintro\r[\x08=\r]\x0Cfile\r] [\x08--houtro\r[\x08=\r]\x0Cfile\r] [\x08--inodes\r] [\x08--device\r]\n" ++
        "\t[\x08--sort\r[\x08=\r]\x0Cname\r] [\x08--dirsfirst\r] [\x08--filesfirst\r] [\x08--filelimit\r[\x08=\r]\x0C#\r] [\x08--si\r]\n" ++
        "\t[\x08--du\r] [\x08--prune\r] [\x08--charset\r[\x08=\r]\x0CX\r] [\x08--timefmt\r[\x08=\r]\x0Cformat\r] [\x08--fromfile\r]\n" ++
        "\t[\x08--fromtabfile\r] [\x08--fflinks\r] [\x08--info\r] [\x08--infofile\r[\x08=\r]\x0Cfile\r] [\x08--noreport\r]\n" ++
        "\t[\x08--hyperlink\r] [\x08--scheme\r[\x08=\r]\x0Cschema\r] [\x08--authority\r[\x08=\r]\x0Chost\r] [\x08--opt-toggle\r]\n" ++
        "\t[\x08--version\r] [\x08--help\r] [\x08--\r] [\x0Cdirectory\r \x08...\r]\n"));
    if (n < 2) return;
    c.fancy(c.stdout, @constCast("  \x08------- Listing options -------\r\n" ++
        "  \x08-a\r            All files are listed.\n" ++
        "  \x08-d\r            List directories only.\n" ++
        "  \x08-l\r            Follow symbolic links like directories.\n" ++
        "  \x08-f\r            Print the full path prefix for each file.\n" ++
        "  \x08-x\r            Stay on current filesystem only.\n" ++
        "  \x08-L\r \x0Clevel\r      Descend only \x0Clevel\r directories deep.\n" ++
        "  \x08-R\r            Rerun tree when max dir level reached.\n" ++
        "  \x08-P\r \x0Cpattern\r    List only those files that match the pattern given.\n" ++
        "  \x08-I\r \x0Cpattern\r    Do not list files that match the given pattern.\n" ++
        "  \x08--gitignore\r   Filter by using \x08.gitignore\r files.\n" ++
        "  \x08--gitfile\r \x0CX\r   Explicitly read a gitignore file.\n" ++
        "  \x08--ignore-case\r Ignore case when pattern matching.\n" ++
        "  \x08--matchdirs\r   Include directory names in \x08-P\r pattern matching.\n" ++
        "  \x08--metafirst\r   Print meta-data at the beginning of each line.\n" ++
        "  \x08--prune\r       Prune empty directories from the output.\n" ++
        "  \x08--info\r        Print information about files found in \x08.info\r files.\n" ++
        "  \x08--infofile\r \x0CX\r  Explicitly read info file.\n" ++
        "  \x08--noreport\r    Turn off file/directory count at end of tree listing.\n" ++
        "  \x08--charset\r \x0CX\r   Use charset \x0CX\r for terminal/HTML and indentation line output.\n" ++
        "  \x08--filelimit\r \x0C#\r Do not descend dirs with more than \x0C#\r files in them.\n" ++
        "  \x08-o\r \x0Cfilename\r   Output to file instead of stdout.\n" ++
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
        "  \x08--timefmt\r \x0Cfmt\r Print and format time according to the format \x0Cfmt\r.\n" ++
        "  \x08-F\r            Appends '\x08/\r', '\x08=\r', '\x08*\r', '\x08@\r', '\x08|\r' or '\x08>\r' as per \x08ls -F\r.\n" ++
        "  \x08--inodes\r      Print inode number of each file.\n" ++
        "  \x08--device\r      Print device ID number to which each file belongs.\n"));
    c.fancy(c.stdout, @constCast("  \x08------- Sorting options -------\r\n" ++
        "  \x08-v\r            Sort files alphanumerically by version.\n" ++
        "  \x08-t\r            Sort files by last modification time.\n" ++
        "  \x08-c\r            Sort files by last status change time.\n" ++
        "  \x08-U\r            Leave files unsorted.\n" ++
        "  \x08-r\r            Reverse the order of the sort.\n" ++
        "  \x08--dirsfirst\r   List directories before files (\x08-U\r disables).\n" ++
        "  \x08--filesfirst\r  List files before directories (\x08-U\r disables).\n" ++
        "  \x08--sort\r \x0CX\r      Select sort: \x08\x0Cname\r,\x08\x0Cversion\r,\x08\x0Csize\r,\x08\x0Cmtime\r,\x08\x0Cctime\r,\x08\x0Cnone\r.\n" ++
        "  \x08------- Graphics options -------\r\n" ++
        "  \x08-i\r            Don't print indentation lines.\n" ++
        "  \x08-A\r            Print ANSI lines graphic indentation lines.\n" ++
        "  \x08-S\r            Print with CP437 (console) graphics indentation lines.\n" ++
        "  \x08-n\r            Turn colorization off always (\x08-C\r overrides).\n" ++
        "  \x08-C\r            Turn colorization on always.\n" ++
        "  \x08------- XML/HTML/JSON/HYPERLINK options -------\r\n" ++
        "  \x08-X\r            Prints out an XML representation of the tree.\n" ++
        "  \x08-J\r            Prints out an JSON representation of the tree.\n" ++
        "  \x08-H\r \x0CbaseHREF\r   Prints out HTML format with \x0CbaseHREF\r as top directory.\n" ++
        "  \x08-T\r \x0Cstring\r     Replace the default HTML title and H1 header with \x0Cstring\r.\n" ++
        "  \x08--nolinks\r     Turn off hyperlinks in HTML output.\n" ++
        "  \x08--hintro\r \x0CX\r    Use file \x0CX\r as the HTML intro.\n" ++
        "  \x08--houtro\r \x0CX\r    Use file \x0CX\r as the HTML outro.\n" ++
        "  \x08--hyperlink\r   Turn on OSC 8 terminal hyperlinks.\n" ++
        "  \x08--scheme\r \x0CX\r    Set OSC 8 hyperlink scheme, default \x08\x0Cfile://\r\n" ++
        "  \x08--authority\r \x0CX\r Set OSC 8 hyperlink authority/hostname.\n" ++
        "  \x08------- Input options -------\r\n" ++
        "  \x08--fromfile\r    Reads paths from files (\x08.\r=stdin)\n" ++
        "  \x08--fromtabfile\r Reads trees from tab indented files (\x08.\r=stdin)\n" ++
        "  \x08--fflinks\r     Process link information when using \x08--fromfile\r.\n" ++
        "  \x08------- Miscellaneous options -------\r\n" ++
        "  \x08--opt-toggle\r  Enable option toggling.\n" ++
        "  \x08--version\r     Print version and exit.\n" ++
        "  \x08--help\r        Print usage and this help message and exit.\n" ++
        "  \x08--\r            Options processing terminator.\n"));
    c.exit(0);
}

// file_getfulltree and tabedfile_getfulltree are defined in file.c
extern fn file_getfulltree(d: [*c]u8, lev: c_ulong, dev: c.dev_t, size: [*c]c.off_t, err: [*c][*c]u8) [*c]?*c.struct__info;
extern fn tabedfile_getfulltree(d: [*c]u8, lev: c_ulong, dev: c.dev_t, size: [*c]c.off_t, err: [*c][*c]u8) [*c]?*c.struct__info;

fn treeMain(argc: c_int, argv: [*c][*c]u8) c_int {
    const builtin = @import("builtin");

    var ig: ?*c.struct_ignorefile = undefined;
    var inf_arg: ?*c.struct_infofile = undefined;
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
    var showversion: bool = false;
    var opt_toggle: bool = false;

    aflag = false;
    dflag = false;
    fflag = false;
    lflag = false;
    pflag = false;
    sflag = false;
    Fflag = false;
    uflag = false;
    gflag = false;
    Dflag = false;
    qflag = false;
    Nflag = false;
    Qflag = false;
    Rflag = false;
    hflag = false;
    Hflag = false;
    siflag = false;
    cflag = false;
    noindent = false;
    force_color = false;
    nocolor = false;
    xdev = false;
    noreport = false;
    nolinks = false;
    reverse = false;
    ignorecase = false;
    matchdirs = false;
    inodeflag = false;
    devflag = false;
    Xflag = false;
    Jflag = false;
    fflinks = false;
    duflag = false;
    pruneflag = false;
    metafirst = false;
    gitignore = false;
    hyperflag = false;
    htmloffset = false;

    flimit = 0;
    dirs = @ptrCast(@alignCast(xmalloc(@sizeOf(c_int) * @as(usize, @intCast(c.PATH_MAX))).?));
    maxdirs = @intCast(c.PATH_MAX);
    _ = c.memset(dirs, 0, @sizeOf(c_int) * maxdirs);
    dirs[0] = 0;
    Level = -1;

    _ = c.setlocale(c.LC_CTYPE, "");
    _ = c.setlocale(c.LC_COLLATE, "");

    charset = c.getcharset();
    if (charset == null and
        (c.strcmp(c.nl_langinfo(c.CODESET), "UTF-8") == 0 or
            c.strcmp(c.nl_langinfo(c.CODESET), "utf8") == 0))
    {
        charset = "UTF-8";
    }

    lc = .{
        .intro = c.null_intro,
        .outtro = c.null_outtro,
        .printinfo = c.unix_printinfo,
        .printfile = c.unix_printfile,
        .@"error" = c.unix_error,
        .newline = c.unix_newline,
        .close = c.null_close,
        .report = c.unix_report,
    };

    mb_cur_max = @intCast(c.__ctype_get_mb_cur_max());

    if (comptime builtin.os.tag == .linux) {
        const stddata_fd_env = c.getenv(c.ENV_STDDATA_FD);
        if (stddata_fd_env != null) {
            var std_fd: c_int = c.atoi(stddata_fd_env);
            if (std_fd <= 0) std_fd = c.STDDATA_FILENO;
            if (c.fcntl(std_fd, c.F_GETFD) >= 0) {
                Jflag = true;
                noindent = true;
                var nl_empty = "".*;
                _nl = @ptrCast(&nl_empty);
                lc = .{
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

    _ = c.memset(@ptrCast(&utable), 0, @sizeOf(@TypeOf(utable)));
    _ = c.memset(@ptrCast(&gtable), 0, @sizeOf(@TypeOf(gtable)));
    _ = c.memset(@ptrCast(&itable), 0, @sizeOf(@TypeOf(itable)));

    n = 1;
    i = 1;
    while (i < @as(usize, @intCast(argc))) : (i = n) {
        n += 1;
        if (optf and argv[i][0] == '-' and argv[i][1] != 0) {
            j = 1;
            while (argv[i][j] != 0) : (j += 1) {
                switch (argv[i][j]) {
                    'N' => Nflag = if (opt_toggle) !Nflag else true,
                    'q' => qflag = if (opt_toggle) !qflag else true,
                    'Q' => Qflag = if (opt_toggle) !Qflag else true,
                    'd' => dflag = if (opt_toggle) !dflag else true,
                    'l' => lflag = if (opt_toggle) !lflag else true,
                    's' => sflag = if (opt_toggle) !sflag else true,
                    'h' => {
                        sflag = if (opt_toggle) !hflag else true;
                        hflag = sflag;
                    },
                    'u' => uflag = if (opt_toggle) !uflag else true,
                    'g' => gflag = if (opt_toggle) !gflag else true,
                    'f' => fflag = if (opt_toggle) !fflag else true,
                    'F' => Fflag = if (opt_toggle) !Fflag else true,
                    'a' => aflag = if (opt_toggle) !aflag else true,
                    'p' => pflag = if (opt_toggle) !pflag else true,
                    'i' => {
                        noindent = if (opt_toggle) !noindent else true;
                        _nl = @constCast("");
                    },
                    'C' => force_color = if (opt_toggle) !force_color else true,
                    'n' => nocolor = if (opt_toggle) !nocolor else true,
                    'x' => xdev = if (opt_toggle) !xdev else true,
                    'P' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(c.stderr, "tree: Missing argument to -P option.\n");
                            c.exit(1);
                        }
                        if (pattern >= maxpattern - 1) patterns = @ptrCast(@alignCast(xrealloc(@ptrCast(patterns), @sizeOf([*c]u8) * @as(usize, @intCast(maxpattern + 10))).?));
                        maxpattern += 10;
                        patterns[@intCast(pattern)] = argv[n];
                        pattern += 1;
                        n += 1;
                        patterns[@intCast(pattern)] = null;
                    },
                    'I' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(c.stderr, "tree: Missing argument to -I option.\n");
                            c.exit(1);
                        }
                        if (ipattern >= maxipattern - 1) ipatterns = @ptrCast(@alignCast(xrealloc(@ptrCast(ipatterns), @sizeOf([*c]u8) * @as(usize, @intCast(maxipattern + 10))).?));
                        maxipattern += 10;
                        ipatterns[@intCast(ipattern)] = argv[n];
                        ipattern += 1;
                        n += 1;
                        ipatterns[@intCast(ipattern)] = null;
                    },
                    'A' => ansilines = if (opt_toggle) !ansilines else true,
                    'S' => charset = "IBM437",
                    'D' => Dflag = if (opt_toggle) !Dflag else true,
                    't' => basesort = &mtimesort,
                    'c' => {
                        basesort = &ctimesort;
                        cflag = true;
                    },
                    'r' => reverse = if (opt_toggle) !reverse else true,
                    'v' => basesort = &versort,
                    'U' => basesort = null,
                    'X' => {
                        Xflag = true;
                        Hflag = false;
                        Jflag = false;
                        lc = .{ .intro = c.xml_intro, .outtro = c.xml_outtro, .printinfo = c.xml_printinfo, .printfile = c.xml_printfile, .@"error" = c.xml_error, .newline = c.xml_newline, .close = c.xml_close, .report = c.xml_report };
                    },
                    'J' => {
                        Jflag = true;
                        Xflag = false;
                        Hflag = false;
                        lc = .{ .intro = c.json_intro, .outtro = c.json_outtro, .printinfo = c.json_printinfo, .printfile = c.json_printfile, .@"error" = c.json_error, .newline = c.json_newline, .close = c.json_close, .report = c.json_report };
                    },
                    'H' => {
                        Hflag = true;
                        Xflag = false;
                        Jflag = false;
                        lc = .{ .intro = c.html_intro, .outtro = c.html_outtro, .printinfo = c.html_printinfo, .printfile = c.html_printfile, .@"error" = c.html_error, .newline = c.html_newline, .close = c.html_close, .report = c.html_report };
                        if (argv[n] == null) {
                            _ = c.fprintf(c.stderr, "tree: Missing argument to -H option.\n");
                            c.exit(1);
                        }
                        host = argv[n];
                        n += 1;
                        if (host[0] == '-') {
                            htmloffset = true;
                            host += 1;
                        }
                        sp = @constCast("&nbsp;");
                    },
                    'T' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(c.stderr, "tree: Missing argument to -T option.\n");
                            c.exit(1);
                        }
                        title = argv[n];
                        n += 1;
                    },
                    'R' => Rflag = if (opt_toggle) !Rflag else true,
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
                                _ = c.fprintf(c.stderr, "tree: Missing argument to -L option.\n");
                                c.exit(1);
                            }
                        }
                        Level = @as(isize, @intCast(c.strtoul(sLevel, null, 0))) - 1;
                        if (Level < 0) {
                            _ = c.fprintf(c.stderr, "tree: Invalid level, must be greater than 0.\n");
                            c.exit(1);
                        }
                    },
                    'o' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(c.stderr, "tree: Missing argument to -o option.\n");
                            c.exit(1);
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
                            if (c.strcmp("--help", argv[i]) == 0) {
                                usage(2);
                                c.exit(0);
                            }
                            if (c.strcmp("--version", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                showversion = true;
                                break;
                            }
                            if (c.strcmp("--inodes", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                inodeflag = if (opt_toggle) !inodeflag else true;
                                break;
                            }
                            if (c.strcmp("--device", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                devflag = if (opt_toggle) !devflag else true;
                                break;
                            }
                            if (c.strcmp("--noreport", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                noreport = if (opt_toggle) !noreport else true;
                                break;
                            }
                            if (c.strcmp("--nolinks", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                nolinks = if (opt_toggle) !nolinks else true;
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
                                flimit = c.atoi(arg);
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--charset");
                            if (arg != null) {
                                charset = arg;
                                break;
                            }
                            if (c.strcmp("--si", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                sflag = if (opt_toggle) !siflag else true;
                                hflag = sflag;
                                siflag = sflag;
                                break;
                            }
                            if (c.strcmp("--du", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                sflag = if (opt_toggle) !duflag else true;
                                duflag = sflag;
                                break;
                            }
                            if (c.strcmp("--prune", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                pruneflag = if (opt_toggle) !pruneflag else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--timefmt");
                            if (arg != null) {
                                timefmt = scopy(arg);
                                Dflag = true;
                                break;
                            }
                            if (c.strcmp("--ignore-case", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                ignorecase = if (opt_toggle) !ignorecase else true;
                                break;
                            }
                            if (c.strcmp("--matchdirs", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                matchdirs = if (opt_toggle) !matchdirs else true;
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
                                    _ = c.fprintf(c.stderr, "tree: Sort type '%s' not valid, should be one of: ", arg);
                                    k = 0;
                                    while (sorts[k].name != null) : (k += 1) {
                                        _ = c.printf("%s%c", sorts[k].name, @as(c_int, if (sorts[k + 1].name != null) ',' else '\n'));
                                    }
                                    c.exit(1);
                                }
                                break;
                            }
                            if (c.strcmp("--fromtabfile", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                fromfile = true;
                                getfulltree = &tabedfile_getfulltree;
                                break;
                            }
                            if (c.strcmp("--fromfile", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                fromfile = true;
                                getfulltree = &file_getfulltree;
                                break;
                            }
                            if (c.strcmp("--metafirst", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                metafirst = if (opt_toggle) !metafirst else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--gitfile");
                            if (arg != null) {
                                gitignore = true;
                                ig = c.new_ignorefile(arg, false);
                                if (ig != null) c.push_filterstack(ig) else {
                                    _ = c.fprintf(c.stderr, "tree: Could not load gitignore file\n");
                                    c.exit(1);
                                }
                                break;
                            }
                            if (c.strcmp("--gitignore", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                gitignore = if (opt_toggle) !gitignore else true;
                                break;
                            }
                            if (c.strcmp("--info", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                showinfo = if (opt_toggle) !showinfo else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--infofile");
                            if (arg != null) {
                                showinfo = true;
                                inf_arg = c.new_infofile(arg, false);
                                if (inf_arg != null) c.push_infostack(inf_arg) else {
                                    _ = c.fprintf(c.stderr, "tree: Could not load infofile\n");
                                    c.exit(1);
                                }
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--hintro");
                            if (arg != null) {
                                Hintro = scopy(arg);
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--houtro");
                            if (arg != null) {
                                Houtro = scopy(arg);
                                break;
                            }
                            if (c.strcmp("--fflinks", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                fflinks = if (opt_toggle) !fflinks else true;
                                break;
                            }
                            if (c.strcmp("--hyperlink", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                hyperflag = if (opt_toggle) !hyperflag else true;
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--scheme");
                            if (arg != null) {
                                if (c.strchr(arg, ':') == null) {
                                    _ = c.sprintf(&xpattern, "%s://", arg);
                                    arg = scopy(&xpattern);
                                } else scheme = scopy(arg);
                                break;
                            }
                            arg = longArg(argv, i, &j, &n, "--authority");
                            if (arg != null) {
                                authority = if (c.strcmp(arg, ".") == 0) scopy("") else scopy(arg);
                                break;
                            }
                            if (c.strcmp("--opt-toggle", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                opt_toggle = !opt_toggle;
                                break;
                            }
                            _ = c.fprintf(c.stderr, "tree: Invalid argument `%s'.\n", argv[i]);
                            usage(1);
                            c.exit(1);
                        }
                        // fall through to default
                        _ = c.fprintf(c.stderr, "tree: Invalid argument -`%c'.\n", @as(c_int, argv[i][j]));
                        usage(1);
                        c.exit(1);
                    },
                    else => {
                        _ = c.fprintf(c.stderr, "tree: Invalid argument -`%c'.\n", @as(c_int, argv[i][j]));
                        usage(1);
                        c.exit(1);
                    },
                }
            }
        } else {
            if (dirname == null) {
                q = c.MINIT;
                dirname = @ptrCast(@alignCast(xmalloc(@sizeOf([*c]u8) * q).?));
            } else if (p == q - 2) {
                q += c.MINC;
                dirname = @ptrCast(@alignCast(xrealloc(@ptrCast(dirname), @sizeOf([*c]u8) * q).?));
            }
            dirname[p] = scopy(argv[i]);
            p += 1;
        }
    }
    if (p > 0) dirname[p] = null;

    setoutput(outfilename);
    c.parse_dir_colors();
    c.initlinedraw(false);

    if (showversion) {
        print_version(1);
        c.exit(0);
    }

    if (dirname == null) {
        dirname = @ptrCast(@alignCast(xmalloc(@sizeOf([*c]u8) * 2).?));
        dirname[0] = scopy(".");
        dirname[1] = null;
    }
    if (topsort == null) topsort = basesort;
    if (basesort == null) topsort = null;
    if (timefmt != null) _ = c.setlocale(c.LC_TIME, "");
    if (dflag) pruneflag = false;
    if (Rflag and Level == -1) Rflag = false;

    if (hyperflag and authority == null) {
        if (c.gethostname(&xpattern, c.PATH_MAX) < 0) {
            _ = c.fprintf(c.stderr, "Unable to get hostname, using 'localhost'.\n");
            authority = @constCast("localhost");
        } else authority = scopy(&xpattern);
    }

    if (gitignore) {
        const git_dir = c.getenv("GIT_DIR");
        if (git_dir != null) {
            const path: [*c]u8 = @ptrCast(xmalloc(@intCast(c.PATH_MAX)).?);
            _ = c.snprintf(path, @intCast(c.PATH_MAX), "%s/info/exclude", git_dir);
            c.push_filterstack(c.new_ignorefile(path, false));
            c.free(path);
        }
    }
    if (showinfo) {
        c.push_infostack(c.new_infofile(c.INFO_PATH, false));
    }

    const needfulltree: bool = duflag or pruneflag or matchdirs or fromfile;
    c.emit_tree(dirname, needfulltree);

    if (outfilename != null) _ = c.fclose(outfile);

    return if (errors != 0) 2 else 0;
}

// ----------------------------------------------------------------------------

pub fn printStdout(content: []const u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(content);
    try stdout.flush();
}

pub fn main() !u8 {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "man")) {
        try printStdout(man.content);
        return 0;
    }

    // Convert [][:0]u8 → null-terminated [*c][*c]u8 (C char**) for treeMain
    var c_args = try allocator.alloc([*c]u8, args.len + 1);
    defer allocator.free(c_args);

    for (args, 0..) |arg, i| c_args[i] = arg.ptr;
    c_args[args.len] = null; // C-style argv sentinel

    const c_argc: c_int = @intCast(args.len);
    const result = treeMain(c_argc, c_args.ptr);

    return if (result >= 0) @intCast(result) else 1;
}
