const std = @import("std");

const man = @import("man.zig");
const c = @cImport({
    @cDefine("_DEFAULT_SOURCE", "");
    @cInclude("tree.h");
});

// Import C main fn (tree_main still lives in tree.c for now)
extern fn tree_main(argc: c_int, argv: [*][*:0]u8) c_int;

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
                        if (m != 0) { match = m; break; }
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

// topsort is a function-pointer global still in tree.c (moves in Phase 8)
extern var topsort: ?*const fn ([*c]?*c.struct__info, [*c]?*c.struct__info) callconv(.c) c_int;

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
    stat2info_buf.ldev   = s.st_dev;
    stat2info_buf.mode   = s.st_mode;
    stat2info_buf.uid    = s.st_uid;
    stat2info_buf.gid    = s.st_gid;
    stat2info_buf.size   = s.st_size;
    stat2info_buf.atime  = statAtime(s);
    stat2info_buf.ctime  = statCtime(s);
    stat2info_buf.mtime  = statMtime(s);
    stat2info_buf.isdir  = (s.st_mode & c.S_IFMT) == c.S_IFDIR;
    stat2info_buf.issok  = (s.st_mode & c.S_IFMT) == c.S_IFSOCK;
    stat2info_buf.isfifo = (s.st_mode & c.S_IFMT) == c.S_IFIFO;
    stat2info_buf.isexe  = (s.st_mode & (c.S_IXUSR | c.S_IXGRP | c.S_IXOTH)) != 0;
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
        st.st_dev  = lst.st_dev;
        st.st_ino  = lst.st_ino;
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

    ent.name   = scopy(name);
    ent.mode   = lst.st_mode;
    ent.uid    = lst.st_uid;
    ent.gid    = lst.st_gid;
    ent.size   = lst.st_size;
    ent.dev    = st.st_dev;
    ent.inode  = st.st_ino;
    ent.ldev   = lst.st_dev;
    ent.linode = lst.st_ino;
    ent.lnk    = null;
    ent.orphan = false;
    ent.err    = null;
    ent.child  = null;
    ent.atime  = statAtime(&lst);
    ent.ctime  = statCtime(&lst);
    ent.mtime  = statMtime(&lst);
    ent.isdir  = isdir;
    ent.issok  = (st.st_mode & c.S_IFMT) == c.S_IFSOCK;
    ent.isfifo = (st.st_mode & c.S_IFMT) == c.S_IFIFO;
    ent.isexe  = (st.st_mode & (c.S_IXUSR | c.S_IXGRP | c.S_IXOTH)) != 0;

    if ((lst.st_mode & c.S_IFMT) == c.S_IFLNK) {
        const lsz: usize = @intCast(lst.st_size);
        if (lsz + 1 > getinfo_lbufsize) {
            getinfo_lbufsize = lsz + 8192;
            getinfo_lbuf = @ptrCast(xrealloc(getinfo_lbuf, getinfo_lbufsize).?);
        }
        const len: isize = c.readlink(path, getinfo_lbuf, getinfo_lbufsize - 1);
        if (len < 0) {
            ent.lnk    = scopy("[Error reading symbolic link information]");
            ent.isdir  = false;
            ent.lnkmode = st.st_mode;
        } else {
            getinfo_lbuf[@intCast(len)] = 0;
            ent.lnk     = scopy(getinfo_lbuf);
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

    // Otherwise call C, must convert [:0]const u8 slice to [*:0]u8 for C
    var c_args = try allocator.alloc([*:0]u8, args.len);
    defer allocator.free(c_args);

    for (args, 0..) |arg, i| {
        c_args[i] = arg.ptr;
    }

    const c_argc: c_int = @intCast(args.len);
    const result = tree_main(c_argc, c_args.ptr);

    return if (result >= 0) @intCast(result) else 1;
}
