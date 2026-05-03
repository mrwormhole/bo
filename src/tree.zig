//! Main tree driver ported from tree.c.

const std = @import("std");
const builtin = @import("builtin");

const c = @import("cstd.zig");

const pat = @import("pattern.zig");
const types = @import("types.zig");
const strverscmp = @import("strverscmp.zig").strverscmp;
const initlinedraw = @import("color.zig").initlinedraw;
const parsedircolors = @import("color.zig").parse_dir_colors;
const json = @import("json.zig");
const xml = @import("xml.zig");
const html = @import("html.zig");
const filter = @import("filter.zig");
const info_mod = @import("info.zig");
const file_mod = @import("file.zig");
const util = @import("util.zig");
const hash = @import("hash.zig");
const help = @import("help.zig");
const linux = @import("linux.zig");
const list = @import("list.zig");
const constants = @import("constants.zig");

// ---------------------------------------------------------------------------
// Extern from color.zig
// ---------------------------------------------------------------------------
extern var linedraw: [*c]const types.LineDraw;

const emit_tree = list.emit_tree;

// unix.zig
const unix = @import("unix.zig");

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
export var version: [*c]const u8 = "bo (The Bodhi Tree) v0.0.5";

export var flag: types.Flags = std.mem.zeroes(types.Flags);

export var pattern: c_int = 0;
export var ipattern: c_int = 0;
export var patterns: [*c][*c]u8 = null;
export var ipatterns: [*c][*c]u8 = null;

export var host: [*c]u8 = null;
export var title: [*c]const u8 = "Directory Tree";
export var sp: [*c]const u8 = " ";
export var Hintro: [*c]const u8 = null;
export var Houtro: [*c]const u8 = null;
export var scheme: [*c]u8 = @constCast("file://");
export var authority: [*c]u8 = null;
export var file_comment: [*c]u8 = @constCast("#");
export var file_pathsep: [*c]u8 = @constCast("/");
export var timefmt: [*c]u8 = null;
export var charset: [*c]const u8 = null;

const SortFn = list.SortFn;

var sLevel: [*c]u8 = null;
var locale_ignores_dot_for_sort: bool = false;

export var dirs: [*c]c_int = null;
export var Level: isize = 0;
export var maxdirs: usize = 0;
export var errors: c_int = 0;

export var xpattern: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);

export var mb_cur_max: c_int = 0;

// ---------------------------------------------------------------------------
// Platform-conditional ifmt / ftype
// ---------------------------------------------------------------------------
export var ifmt: [if (@hasDecl(std.posix.S, "IFPORT")) 10 else 8]c.mode_t =
    if (@hasDecl(std.posix.S, "IFPORT"))
        .{ std.posix.S.IFREG, std.posix.S.IFDIR, std.posix.S.IFLNK, std.posix.S.IFCHR, std.posix.S.IFBLK, std.posix.S.IFSOCK, std.posix.S.IFIFO, std.posix.S.IFDOOR, std.posix.S.IFPORT, 0 }
    else
        .{ std.posix.S.IFREG, std.posix.S.IFDIR, std.posix.S.IFLNK, std.posix.S.IFCHR, std.posix.S.IFBLK, std.posix.S.IFSOCK, std.posix.S.IFIFO, 0 };

export var ftype: [if (@hasDecl(std.posix.S, "IFPORT")) 11 else 9][*c]const u8 =
    if (@hasDecl(std.posix.S, "IFPORT"))
        .{ "file", "directory", "link", "char", "block", "socket", "fifo", "door", "port", "unknown", null }
    else
        .{ "file", "directory", "link", "char", "block", "socket", "fifo", "unknown", null };

// ---------------------------------------------------------------------------
// Sort table
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
    return c.cStderr();
}

inline fn cStdout() ?*c.FILE {
    return c.cStdout();
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
// Module-level state
// ---------------------------------------------------------------------------
var prot_buf: [11]u8 = undefined;
var do_date_buf: [256]u8 = undefined;
var getinfo_lbuf: [*c]u8 = null;
var getinfo_lbufsize: usize = 0;
var read_dir_path: [*c]u8 = null;
var read_dir_pathsize: usize = 0;

// ---------------------------------------------------------------------------
// Exported formatting helpers
// ---------------------------------------------------------------------------

export fn prot(m: c.mode_t) [*c]u8 {
    const fmt_str: [*:0]const u8 = if (@hasDecl(std.posix.S, "IFPORT")) "-dlcbspDP?" else "-dlcbsp?";

    var i: c_int = 0;
    while (ifmt[@intCast(i)] != 0 and (m & std.posix.S.IFMT) != ifmt[@intCast(i)]) : (i += 1) {}
    prot_buf[0] = fmt_str[@intCast(i)];

    // Nice, but maybe not so portable, it is should be no less portable than the
    // old code.
    const perms = "rwxrwxrwx";
    var b: c.mode_t = std.posix.S.IRUSR;
    var j: usize = 0;
    while (j < 9) : ({
        b >>= 1;
        j += 1;
    }) {
        prot_buf[j + 1] = if ((m & b) != 0) perms[j] else '-';
    }
    if ((m & std.posix.S.ISUID) != 0) prot_buf[3] = if (prot_buf[3] == '-') 'S' else 's';
    if ((m & std.posix.S.ISGID) != 0) prot_buf[6] = if (prot_buf[6] == '-') 'S' else 's';
    if ((m & std.posix.S.ISVTX) != 0) prot_buf[9] = if (prot_buf[9] == '-') 'T' else 't';

    prot_buf[10] = 0;
    return &prot_buf;
}

export fn do_date(t: c.time_t) [*c]u8 {
    const tm = c.localtime(&t);
    const six_months: c.time_t = 6 * 31 * 24 * 60 * 60;

    if (timefmt != null) {
        _ = c.strftime(&do_date_buf, 255, timefmt, tm);
        do_date_buf[255] = 0;
    } else {
        const cur: c.time_t = c.time(null);
        // Use strftime() so that locale is respected:
        if (t > cur or (t + six_months) < cur) {
            _ = c.strftime(&do_date_buf, 255, "%b %e  %Y", tm);
        } else {
            _ = c.strftime(&do_date_buf, 255, "%b %e %R", tm);
        }
    }
    return &do_date_buf;
}

// Must fix this someday
export fn printit(w: *std.Io.Writer, s: [*c]const u8) void {
    if (flag.N) {
        if (flag.Q) w.print("\"{s}\"", .{std.mem.span(s)}) catch {} else w.writeAll(std.mem.span(s)) catch {};
        return;
    }
    if (mb_cur_max > 1) {
        const cs: usize = c.strlen(s) + 1;
        const ws: [*c]c.wchar_t = @ptrCast(@alignCast(util.xmalloc(@sizeOf(c.wchar_t) * cs)));
        if (c.mbstowcs(ws, s, cs) != @as(usize, @bitCast(@as(isize, -1)))) {
            if (flag.Q) w.writeByte('"') catch {};
            var remaining: usize = cs;
            var tp: [*c]c.wchar_t = ws;
            while (tp[0] != 0 and remaining > 1) : ({
                tp += 1;
                remaining -= 1;
            }) {
                if (c.iswprint(@intCast(tp[0])) != 0) {
                    const wc: u32 = @bitCast(tp[0]);
                    if (wc <= 0x10FFFF) {
                        var utf8buf: [4]u8 = undefined;
                        if (std.unicode.utf8Encode(@intCast(wc), &utf8buf)) |len| {
                            w.writeAll(utf8buf[0..len]) catch {};
                        } else |_| {
                            w.writeByte('?') catch {};
                        }
                    } else {
                        w.writeByte('?') catch {};
                    }
                } else {
                    if (flag.q) w.writeByte('?') catch {} else w.print("\\{o:0>3}", .{@as(u32, @bitCast(tp[0]))}) catch {};
                }
            }
            if (flag.Q) w.writeByte('"') catch {};
            c.free(ws);
            return;
        }
        c.free(ws);
    }
    if (flag.Q) w.writeByte('"') catch {};
    var sp2: [*c]const u8 = s;
    while (sp2[0] != 0) : (sp2 += 1) {
        const ch: c_int = @intCast(sp2[0]);
        if ((ch >= 7 and ch <= 13) or ch == '\\' or (ch == '"' and flag.Q) or (ch == ' ' and !flag.Q)) {
            w.writeByte('\\') catch {};
            if (ch > 13) w.writeByte(@intCast(ch)) catch {} else w.writeByte("abtnvfr"[@intCast(ch - 7)]) catch {};
        } else if (c.isprint(ch) != 0) {
            w.writeByte(@intCast(ch)) catch {};
        } else {
            if (flag.q) {
                if (mb_cur_max > 1 and ch > 127) w.writeByte(@intCast(ch)) catch {} else w.writeByte('?') catch {};
            } else {
                w.print("\\{o:0>3}", .{@as(c_uint, @intCast(ch))}) catch {};
            }
        }
    }
    if (flag.Q) w.writeByte('"') catch {};
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
    const m: c_int = @intCast(mode & std.posix.S.IFMT);
    if (!flag.d and m == std.posix.S.IFDIR) return '/';
    if (m == std.posix.S.IFSOCK) return '=';
    if (m == std.posix.S.IFIFO) return '|';
    if (m == std.posix.S.IFLNK) return '@'; // Here, but never actually used though.
    if (@hasDecl(std.posix.S, "IFDOOR")) {
        if (m == std.posix.S.IFDOOR) return '>';
    }
    if (m == std.posix.S.IFREG and (mode & (std.posix.S.IXUSR | std.posix.S.IXGRP | std.posix.S.IXOTH)) != 0) return '*';
    return 0;
}

export fn fillinfo(buf: [*c]u8, ent: ?*const types.Info) [*c]u8 {
    var n: c_int = 0;
    buf[@intCast(n)] = 0;
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
    if (flag.p) n += c.sprintf(buf + @as(usize, @intCast(n)), " %s", prot(@intCast(e.mode)));
    if (comptime builtin.os.tag == .linux) {
        if (flag.acl) n += c.sprintf(buf + @as(usize, @intCast(n)), "%c", @as(c_int, if (e.hasacl) '+' else ' '));
    }
    if (flag.u) n += c.sprintf(buf + @as(usize, @intCast(n)), " %-8.32s", hash.uidtoname(@intCast(e.uid)));
    if (flag.g) n += c.sprintf(buf + @as(usize, @intCast(n)), " %-8.32s", hash.gidtoname(@intCast(e.gid)));
    if (flag.s) n += psize(buf + @as(usize, @intCast(n)), @intCast(e.size));
    if (flag.D) n += c.sprintf(buf + @as(usize, @intCast(n)), " %s", do_date(@intCast(if (flag.c) e.ctime else e.mtime)));
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
export fn indent(w: *std.Io.Writer, maxlevel: c_int) void {
    const spaces = [3][]const u8{ "   ", "  ", " " };
    const htmlspaces = [3][]const u8{ "&nbsp;&nbsp;&nbsp;", "&nbsp;&nbsp;", "&nbsp;" };
    const space: []const u8 = if (flag.H) "&nbsp;" else " ";
    const clvl: usize = @intCast(flag.compress_indent);

    if (flag.H) w.writeByte('\t') catch {};
    var i: c_int = 1;
    while (i <= maxlevel and dirs[@intCast(i)] != 0) : (i += 1) {
        const has_next: bool = dirs[@intCast(i + 1)] != 0;
        const bar_here: bool = dirs[@intCast(i)] == 1;
        const seg: []const u8 = if (has_next)
            (if (bar_here) std.mem.span(linedraw[0].vert[clvl]) else (if (flag.H) htmlspaces[clvl] else spaces[clvl]))
        else
            (if (bar_here) std.mem.span(linedraw[0].vert_left[clvl]) else std.mem.span(linedraw[0].corner[clvl]));
        w.writeAll(seg) catch {};
        if (flag.remove_space != true) w.writeAll(space) catch {};
    }
}

// ---------------------------------------------------------------------------
// Sort functions
// ---------------------------------------------------------------------------

// filesfirst and dirsfirst are now top-level meta-sorts.
fn filesfirst(a: *types.Info, b: *types.Info) c_int {
    if (a.isdir != b.isdir) {
        return if (a.isdir) 1 else -1;
    }
    return list.basesort.?(a, b);
}

fn dirsfirst(a: *types.Info, b: *types.Info) c_int {
    if (a.isdir != b.isdir) {
        return if (a.isdir) -1 else 1;
    }
    return list.basesort.?(a, b);
}

fn sortName(name: [*c]u8) [*c]u8 {
    if (!locale_ignores_dot_for_sort) return name;
    if (name[0] == '.' and name[1] != 0) return name + 1;
    return name;
}

fn isCLocale(value: []const u8) bool {
    return std.mem.eql(u8, value, "C") or
        std.mem.eql(u8, value, "POSIX") or
        std.mem.startsWith(u8, value, "C.");
}

fn localeIgnoresDotForSort(environ: *std.process.Environ.Map) bool {
    const locale = environ.get("LC_ALL") orelse
        environ.get("LC_COLLATE") orelse
        environ.get("LANG") orelse
        return false;
    return locale.len != 0 and !isCLocale(locale);
}

fn namecoll(a: [*c]u8, b: [*c]u8) c_int {
    const v = c.strcoll(sortName(a), sortName(b));
    if (v != 0) return v;
    return c.strcoll(a, b);
}

fn alnumsort(a: *types.Info, b: *types.Info) c_int {
    const v = namecoll(a.name, b.name);
    return if (flag.reverse) -v else v;
}

fn versort(a: *types.Info, b: *types.Info) c_int {
    const v = strverscmp(a.name, b.name);
    return if (flag.reverse) -v else v;
}

fn mtimesort(a: *types.Info, b: *types.Info) c_int {
    if (a.mtime == b.mtime) {
        const v = namecoll(a.name, b.name);
        return if (flag.reverse) -v else v;
    }
    const v: c_int = if (a.mtime < b.mtime) -1 else 1;
    return if (flag.reverse) -v else v;
}

fn ctimesort(a: *types.Info, b: *types.Info) c_int {
    if (a.ctime == b.ctime) {
        const v = namecoll(a.name, b.name);
        return if (flag.reverse) -v else v;
    }
    const v: c_int = if (a.ctime < b.ctime) -1 else 1;
    return if (flag.reverse) -v else v;
}

fn sizecmp(a: c.off_t, b: c.off_t) c_int {
    return if (a == b) 0 else if (a < b) 1 else -1;
}

fn fsizesort(a: *types.Info, b: *types.Info) c_int {
    var v = sizecmp(@intCast(a.size), @intCast(b.size));
    if (v == 0) v = namecoll(a.name, b.name);
    return if (flag.reverse) -v else v;
}

// ---------------------------------------------------------------------------
// Filesystem functions
// ---------------------------------------------------------------------------

fn doLstatInfo(path: [*c]const u8, ent: *types.Info) bool {
    if (comptime builtin.os.tag == .linux) {
        var lst: std.os.linux.Statx = undefined;
        if (!linux.stat(@ptrCast(path), std.os.linux.AT.SYMLINK_NOFOLLOW, &lst)) return false;
        ent.mode = @intCast(lst.mode);
        ent.uid = @intCast(lst.uid);
        ent.gid = @intCast(lst.gid);
        ent.size = @intCast(lst.size);
        ent.ldev = @intCast(linux.devId(&lst));
        ent.linode = @intCast(lst.ino);
        ent.atime = @intCast(lst.atime.sec);
        ent.ctime = @intCast(lst.ctime.sec);
        ent.mtime = @intCast(lst.mtime.sec);
        return true;
    } else {
        var lst: c.struct_stat = undefined;
        if (c.lstat(path, &lst) < 0) return false;
        ent.mode = @intCast(lst.mode);
        ent.uid = @intCast(lst.uid);
        ent.gid = @intCast(lst.gid);
        ent.size = @intCast(lst.size);
        ent.ldev = @intCast(lst.dev);
        ent.linode = @intCast(lst.ino);
        ent.atime = @intCast(lst.atime().sec);
        ent.ctime = @intCast(lst.ctime().sec);
        ent.mtime = @intCast(lst.mtime().sec);
        return true;
    }
}

// Split out stat portion from read_dir as prelude to just using stat structure directly.
fn getinfo(name: [*c]const u8, path: [*c]u8) ?*types.Info {
    if (getinfo_lbuf == null) {
        getinfo_lbufsize = std.fs.max_path_bytes;
        getinfo_lbuf = @ptrCast(util.xmalloc(getinfo_lbufsize));
    }

    var ent_storage: types.Info = std.mem.zeroes(types.Info);

    if (!doLstatInfo(path, &ent_storage)) return null;

    // Determine if it's a symlink
    const lst_mode: c.mode_t = @intCast(ent_storage.mode);
    var st_mode: c.mode_t = lst_mode;
    var st_dev: c.dev_t = @intCast(ent_storage.ldev);
    var st_ino: c.ino_t = @intCast(ent_storage.linode);
    var rs: c_int = 0;

    if ((lst_mode & std.posix.S.IFMT) == @as(c.mode_t, std.posix.S.IFLNK)) {
        if (comptime builtin.os.tag == .linux) {
            var lxst: std.os.linux.Statx = undefined;
            if (linux.stat(@ptrCast(path), 0, &lxst)) {
                st_mode = @intCast(lxst.mode);
                st_dev = @intCast(linux.devId(&lxst));
                st_ino = @intCast(lxst.ino);
            } else {
                rs = -1;
            }
        } else {
            var st: c.struct_stat = std.mem.zeroes(c.struct_stat);
            rs = c.stat(path, &st);
            if (rs >= 0) {
                st_mode = st.mode;
                st_dev = st.dev;
                st_ino = st.ino;
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

    const isdir: bool = (st_mode & std.posix.S.IFMT) == @as(c.mode_t, std.posix.S.IFDIR);

    if (flag.gitignore and filter.filtercheck(path, name, @intFromBool(isdir), flag.ignorecase)) return null;

    if ((lst_mode & std.posix.S.IFMT) != @as(c.mode_t, std.posix.S.IFDIR) and !(flag.l and ((st_mode & std.posix.S.IFMT) == @as(c.mode_t, std.posix.S.IFDIR)))) {
        if (pattern != 0 and pat.include(name, patterns[0..@intCast(pattern)], isdir, false, flag.ignorecase, file_pathsep[0]) == 0 and pat.include(path, patterns[0..@intCast(pattern)], isdir, true, flag.ignorecase, file_pathsep[0]) == 0) return null;
    }
    if (ipattern != 0 and (pat.ignore(name, ipatterns[0..@intCast(ipattern)], isdir, false, flag.ignorecase, file_pathsep[0]) != 0 or pat.ignore(path, ipatterns[0..@intCast(ipattern)], isdir, true, flag.ignorecase, file_pathsep[0]) != 0)) return null;

    if (flag.d and ((st_mode & std.posix.S.IFMT) != @as(c.mode_t, std.posix.S.IFDIR))) return null;

    // if (pattern && ((lst.st_mode & S_IFMT) == S_IFLNK) && !lflag) continue;
    const ent: *types.Info = @ptrCast(@alignCast(util.xmalloc(@sizeOf(types.Info))));
    @memset(@as([*]u8, @ptrCast(ent))[0..@sizeOf(types.Info)], 0);

    ent.name = util.scopy(name);
    ent.mode = ent_storage.mode;
    ent.uid = ent_storage.uid;
    ent.gid = ent_storage.gid;
    ent.size = ent_storage.size;
    ent.dev = @intCast(st_dev);
    ent.inode = @intCast(st_ino);
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
        if (flag.acl) ent.hasacl = linux.has_acl(path);
        if (flag.selinux) ent.secontext = linux.selinux_context(path) else ent.secontext = null;
    }

    ent.isdir = isdir;

    // These should perhaps be eliminated, as they're barely used:
    ent.issok = ((st_mode & std.posix.S.IFMT) == @as(c.mode_t, std.posix.S.IFSOCK));
    ent.isfifo = ((st_mode & std.posix.S.IFMT) == @as(c.mode_t, std.posix.S.IFIFO));
    ent.isexe = (st_mode & (std.posix.S.IXUSR | std.posix.S.IXGRP | std.posix.S.IXOTH)) != 0;

    if ((lst_mode & std.posix.S.IFMT) == @as(c.mode_t, std.posix.S.IFLNK)) {
        const lst_size: usize = @intCast(ent_storage.size);
        if (lst_size + 1 > getinfo_lbufsize) {
            getinfo_lbufsize = lst_size + 8192;
            getinfo_lbuf = @ptrCast(util.xrealloc(getinfo_lbuf, getinfo_lbufsize));
        }
        const len: isize = c.readlink(path, getinfo_lbuf, getinfo_lbufsize - 1);
        if (len < 0) {
            ent.lnk = util.scopy("[Error reading symbolic link information]");
            ent.isdir = false;
            ent.lnkmode = @intCast(st_mode);
        } else {
            getinfo_lbuf[@intCast(len)] = 0;
            ent.lnk = util.scopy(getinfo_lbuf);
            if (rs < 0) ent.orphan = true;
            ent.lnkmode = @intCast(st_mode);
        }
    }

    ent.comment = null;

    return ent;
}

export fn free_dir(d: [*c]?*types.Info) void {
    var i: usize = 0;
    while (d[i]) |entry| : (i += 1) {
        c.free(entry.name);
        if (entry.lnk != null) c.free(entry.lnk);
        if (comptime builtin.os.tag == .linux) {
            if (entry.secontext != null) c.free(entry.secontext);
        }
        if (entry.comment != null) {
            var j: usize = 0;
            while (entry.comment[j] != null) : (j += 1) c.free(entry.comment[j]);
        }
        if (entry.err != null) c.free(entry.err);
        c.free(@ptrCast(entry));
    }
    c.free(@ptrCast(d));
}

export fn read_dir(dir: [*c]u8, n: [*c]isize, infotop: c_int) [*c]?*types.Info {
    if (read_dir_path == null) {
        read_dir_pathsize = c.strlen(dir) + std.fs.max_path_bytes;
        read_dir_path = @ptrCast(util.xmalloc(read_dir_pathsize));
    }

    const es: bool = dir[c.strlen(dir) - 1] == '/';
    n.* = -1;
    const d: ?*c.DIR = c.opendir(dir);
    if (d == null) return null;

    var ne: usize = constants.MINIT;
    var dl: [*c]?*types.Info = @ptrCast(@alignCast(util.xmalloc(@sizeOf(?*types.Info) * ne)));
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
            read_dir_pathsize = dlen + elen + std.fs.max_path_bytes;
            read_dir_path = @ptrCast(util.xrealloc(read_dir_path, read_dir_pathsize));
        }
        if (es) {
            _ = c.sprintf(read_dir_path, "%s%s", dir, dname);
        } else {
            _ = c.sprintf(read_dir_path, "%s/%s", dir, dname);
        }

        const info = getinfo(dname, read_dir_path);
        if (info) |inf| {
            var com: ?*types.Comment = null;
            if (flag.showinfo) {
                com = info_mod.infocheck(read_dir_path, dname, infotop, inf.isdir, flag.ignorecase);
            }
            if (com != null) {
                var cnt: usize = 0;
                while (com.?.desc[cnt] != null) : (cnt += 1) {}
                inf.comment = @ptrCast(@alignCast(util.xmalloc(@sizeOf([*c]u8) * (cnt + 1))));
                var ci: usize = 0;
                while (ci < cnt) : (ci += 1) inf.comment[ci] = util.scopy(com.?.desc[ci]);
                inf.comment[cnt] = null;
            }
            if (p == (ne - 1)) {
                dl = @ptrCast(@alignCast(util.xrealloc(@ptrCast(dl), @sizeOf(?*types.Info) * (ne + constants.MINC))));
                ne += constants.MINC;
            }
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

// This is for all the impossible things people wanted the old tree to do.
// This can and will use a large amount of memory for large directory trees
// and also take some time.
fn unix_getfulltree(d: [*c]u8, lev: c_ulong, dev_in: c.dev_t, size: *c.off_t, err: [*c][*c]u8) [*c]?*types.Info {
    var dev: c.dev_t = dev_in;
    var path: [*c]u8 = undefined;
    var pathsize: usize = 0;
    var ig: ?*types.IgnoreFile = null;
    var inf: ?*types.InfoFile = null;
    var sav: [*c]?*types.Info = undefined;
    var dir_ptr: [*c]?*types.Info = undefined;
    var n: isize = undefined;
    var tmp_pattern: c_int = 0;

    err.* = null;
    if (Level >= 0 and lev > @as(c_ulong, @intCast(Level))) return null;
    if (flag.xdev and lev == 0) {
        if (comptime builtin.os.tag == .linux) {
            var lst: std.os.linux.Statx = undefined;
            if (linux.stat(@ptrCast(d), 0, &lst)) {
                dev = @intCast(linux.devId(&lst));
            }
        } else {
            var sb: c.struct_stat = undefined;
            if (c.stat(d, &sb) == 0) dev = sb.dev;
        }
    }
    // if the directory name matches, turn off pattern matching for contents
    const last_name: [*c]const u8 = c.strrchr(d, file_pathsep[0]);
    if (pattern != 0 and (pat.include(d, patterns[0..@intCast(pattern)], true, true, flag.ignorecase, file_pathsep[0]) != 0 or (last_name != null and pat.include(last_name.? + 1, patterns[0..@intCast(pattern)], true, false, flag.ignorecase, file_pathsep[0]) != 0))) {
        tmp_pattern = pattern;
        pattern = 0;
    }

    filter.pushFiles(d, @ptrCast(&ig), @ptrCast(&inf), lev == 0);

    sav = read_dir(d, &n, @intFromBool(inf != null));
    dir_ptr = sav;

    if (dir_ptr == null and n != 0) {
        err.* = util.scopy("error opening dir");
        if (tmp_pattern != 0) pattern = tmp_pattern;
        return null;
    }
    if (n == 0) {
        if (sav != null) free_dir(sav);
        if (tmp_pattern != 0) pattern = tmp_pattern;
        return null;
    }
    pathsize = std.fs.max_path_bytes;
    path = @ptrCast(util.xmalloc(pathsize));

    if (flag.flimit > 0 and n > flag.flimit) {
        _ = c.sprintf(path, "%ld entries exceeds filelimit, not opening dir", @as(c_long, @intCast(n)));
        err.* = util.scopy(path);
        free_dir(sav);
        c.free(path);
        if (tmp_pattern != 0) pattern = tmp_pattern;
        return null;
    }

    if (lev >= maxdirs - 1) {
        dirs = @ptrCast(@alignCast(util.xrealloc(@ptrCast(dirs), @sizeOf(c_int) * (maxdirs + 1024))));
        maxdirs += 1024;
    }

    while (dir_ptr.*) |entry| {
        if (entry.isdir and !(flag.xdev and dev != @as(c.dev_t, @intCast(entry.dev)))) {
            if (entry.lnk != null) {
                if (flag.l) {
                    if (hash.findino(@intCast(entry.inode), @intCast(entry.dev))) {
                        entry.err = util.scopy("recursive, not followed");
                    } else {
                        hash.saveino(@intCast(entry.inode), @intCast(entry.dev));
                        if (entry.lnk[0] == '/') {
                            entry.child = unix_getfulltree(entry.lnk, lev + 1, dev, @ptrCast(&entry.size), &(entry.err));
                        } else {
                            const dlen = c.strlen(d);
                            const llen = c.strlen(entry.lnk);
                            if (dlen + llen + 2 > pathsize) {
                                pathsize = dlen + llen + 1024;
                                path = @ptrCast(util.xrealloc(path, pathsize));
                            }
                            if (flag.f and c.strcmp(d, "/") == 0) {
                                _ = c.sprintf(path, "%s%s", d, entry.lnk);
                            } else {
                                _ = c.sprintf(path, "%s/%s", d, entry.lnk);
                            }
                            entry.child = unix_getfulltree(path, lev + 1, dev, @ptrCast(&entry.size), &(entry.err));
                        }
                    }
                }
            } else {
                const dlen = c.strlen(d);
                const nlen = c.strlen(entry.name);
                if (dlen + nlen + 2 > pathsize) {
                    pathsize = dlen + nlen + 1024;
                    path = @ptrCast(util.xrealloc(path, pathsize));
                }

                if (flag.f and c.strcmp(d, "/") == 0) {
                    _ = c.sprintf(path, "%s%s", d, entry.name);
                } else {
                    _ = c.sprintf(path, "%s/%s", d, entry.name);
                }

                hash.saveino(@intCast(entry.inode), @intCast(entry.dev));
                entry.child = unix_getfulltree(path, lev + 1, dev, @ptrCast(&entry.size), &(entry.err));

                if (flag.condense_singletons) {
                    while (util.is_singleton(entry)) {
                        const child = entry.child;
                        var segs = [_][*c]u8{ entry.name, child[0].?.name };
                        const new_name = util.pathconcat(@ptrCast(&segs), 2);
                        c.free(entry.name);
                        entry.name = util.scopy(new_name);
                        entry.child = child[0].?.child;
                        entry.condensed = entry.condensed + 1 + child[0].?.condensed;
                        free_dir(child);
                    }
                }
            }
            // prune empty folders, unless they match the requested pattern
            if (flag.prune and entry.child == null and
                !(flag.matchdirs and pattern != 0 and pat.include(entry.name, patterns[0..@intCast(pattern)], entry.isdir, false, flag.ignorecase, file_pathsep[0]) != 0))
            {
                const xp = entry;
                var p: [*c]?*types.Info = dir_ptr;
                while (p.* != null) : (p += 1) p.* = (p + 1).*;
                n -= 1;
                c.free(xp.name);
                if (xp.lnk != null) c.free(xp.lnk);
                c.free(@ptrCast(xp));
                continue;
            }
        }
        if (flag.du) size.* += @intCast(entry.size);
        dir_ptr += 1;
    }

    if (tmp_pattern != 0) {
        pattern = tmp_pattern;
        tmp_pattern = 0;
    }

    // sorting needs to be deferred for --du:
    if (list.topsort != null) {
        std.mem.sort(?*types.Info, sav[0..@intCast(n)], list.topsort.?, list.infoLessThan);
    }

    c.free(path);
    if (n == 0) {
        free_dir(sav);
        return null;
    }
    if (ig != null) _ = filter.pop_filterstack();
    if (inf != null) _ = info_mod.pop_infostack();
    return sav;
}

// ---------------------------------------------------------------------------
// CLI helpers
// ---------------------------------------------------------------------------

// Time to switch to getopt()?
fn longArg(argv: [*c][*c]u8, i: usize, j: *usize, n: *usize, prefix: [*c]const u8) RunError![*c]u8 {
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
                if (c.strcmp(prefix, "--charset=") == 0) initlinedraw(true);
                return error.InvalidArgument;
            }
        } else if (argv[n.*] != null) {
            ret = argv[n.*];
            n.* += 1;
            j.* = c.strlen(argv[i]) - 1;
        } else {
            _ = c.fprintf(cStderr(), "tree: Missing argument to %s\n", prefix);
            if (c.strcmp(prefix, "--charset") == 0) initlinedraw(true);
            return error.InvalidArgument;
        }
    }
    return ret;
}

pub const RunError = std.mem.Allocator.Error || error{
    InvalidArgument,
    InvalidOutputFile,
    TreeHadErrors,
};

pub fn run(gpa: std.mem.Allocator, args: []const [:0]const u8, io: std.Io, environ: *std.process.Environ.Map) RunError!void {
    var argv_buf = try gpa.alloc([*c]u8, args.len + 1);
    defer gpa.free(argv_buf);

    for (args, 0..) |arg, arg_i| {
        argv_buf[arg_i] = @constCast(arg.ptr);
    }
    argv_buf[args.len] = null;

    try runWithArgv(gpa, argv_buf[0..args.len :null], io, environ);
}

fn runWithArgv(gpa: std.mem.Allocator, argv_slice: [:null][*c]u8, io: std.Io, environ: *std.process.Environ.Map) RunError!void {
    const argc = argv_slice.len;
    const argv: [*c][*c]u8 = argv_slice.ptr;

    list.getfulltree = &unix_getfulltree;
    list.basesort = &alnumsort;
    list.topsort = null;
    util.init(io, std.Io.File.stdout());
    var dirname: [*c][*c]u8 = null;

    var patterns_list = try std.ArrayList([*c]u8).initCapacity(gpa, 16);
    var ipatterns_list = try std.ArrayList([*c]u8).initCapacity(gpa, 16);

    defer patterns_list.deinit(gpa);
    defer ipatterns_list.deinit(gpa);

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

    @memset(@as([*]u8, @ptrCast(&flag))[0..@sizeOf(types.Flags)], 0);

    maxdirs = std.fs.max_path_bytes;
    dirs = @ptrCast(@alignCast(util.xmalloc(@sizeOf(c_int) * maxdirs)));
    @memset(@as([*]u8, @ptrCast(dirs))[0 .. @sizeOf(c_int) * maxdirs], 0);
    dirs[0] = 0;
    Level = -1;

    _ = c.setlocale(c.LC_CTYPE, "");
    _ = c.setlocale(c.LC_COLLATE, "");
    locale_ignores_dot_for_sort = localeIgnoresDotForSort(environ);

    if (environ.get("TREE_CHARSET")) |env_charset| {
        charset = @ptrCast(env_charset.ptr);
    } else {
        const codeset = c.nl_langinfo(c.CODESET);
        if (c.strcmp(codeset, "UTF-8") == 0 or c.strcmp(codeset, "utf8") == 0) {
            charset = "UTF-8";
        }
    }

    var lc: types.ListingCalls = unix.ListingCalls();

    // Still a hack, but assume that if the macro is defined, we can use it:
    mb_cur_max = getMbCurMax();

    if (comptime builtin.os.tag == .linux) {
        // Output JSON automatically to "stddata" if present:
        const stddata_fd_str = c.getenv(constants.ENV_STDDATA_FD);
        if (stddata_fd_str != null) {
            var std_fd: c_int = c.atoi(stddata_fd_str);
            if (std_fd <= 0) std_fd = constants.STDDATA_FILENO;
            if (c.fcntl(std_fd, c.F_GETFD) >= 0) {
                flag.J = true;
                flag.noindent = true;
                lc = json.ListingCalls();
                util.file = .{ .handle = @intCast(std_fd), .flags = .{ .nonblocking = false } };
            }
        }
    }

    n = 1;
    i = 1;
    while (i < argc) : (i = n) {
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
                    },
                    'C' => flag.force_color = if (opt_toggle) !flag.force_color else true,
                    'n' => flag.nocolor = if (opt_toggle) !flag.nocolor else true,
                    'x' => flag.xdev = if (opt_toggle) !flag.xdev else true,
                    'P' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -P option.\n");
                            return error.InvalidArgument;
                        }
                        try patterns_list.append(gpa, argv[n]);
                        n += 1;
                    },
                    'I' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -I option.\n");
                            return error.InvalidArgument;
                        }
                        try ipatterns_list.append(gpa, argv[n]);
                        n += 1;
                    },
                    'A' => flag.ansilines = if (opt_toggle) !flag.ansilines else true,
                    'S' => charset = "IBM437",
                    'D' => flag.D = if (opt_toggle) !flag.D else true,
                    't' => list.basesort = &mtimesort,
                    'c' => {
                        list.basesort = &ctimesort;
                        flag.c = true;
                    },
                    'r' => flag.reverse = if (opt_toggle) !flag.reverse else true,
                    'v' => list.basesort = &versort,
                    'U' => list.basesort = null,
                    'X' => {
                        flag.X = true;
                        flag.H = false;
                        flag.J = false;
                        lc = xml.ListingCalls();
                    },
                    'J' => {
                        flag.J = true;
                        flag.X = false;
                        flag.H = false;
                        lc = json.ListingCalls();
                    },
                    'H' => {
                        flag.H = true;
                        flag.X = false;
                        flag.J = false;
                        lc = html.ListingCalls();
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -H option.\n");
                            return error.InvalidArgument;
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
                            return error.InvalidArgument;
                        }
                        title = argv[n];
                        n += 1;
                    },
                    'R' => flag.R = if (opt_toggle) !flag.R else true,
                    'L' => {
                        if (c.isdigit(argv[i][j + 1]) != 0) {
                            k = 0;
                            while (argv[i][j + 1 + k] != 0 and c.isdigit(argv[i][j + 1 + k]) != 0 and k < std.fs.max_path_bytes - 1) : (k += 1) {
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
                                return error.InvalidArgument;
                            }
                        }
                        Level = @intCast(c.strtoul(sLevel, null, 0));
                        Level -= 1;
                        if (Level < 0) {
                            _ = c.fprintf(cStderr(), "tree: Invalid level, must be greater than 0.\n");
                            return error.InvalidArgument;
                        }
                    },
                    'o' => {
                        if (argv[n] == null) {
                            _ = c.fprintf(cStderr(), "tree: Missing argument to -o option.\n");
                            return error.InvalidArgument;
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
                                help.print();
                                return;
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
                                list.topsort = &dirsfirst;
                                break;
                            }
                            if (c.strcmp("--filesfirst", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                list.topsort = &filesfirst;
                                break;
                            }
                            arg = try longArg(argv, i, &j, &n, "--filelimit");
                            if (arg != null) {
                                flag.flimit = c.atoi(arg);
                                break;
                            }
                            arg = try longArg(argv, i, &j, &n, "--charset");
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
                            arg = try longArg(argv, i, &j, &n, "--timefmt");
                            if (arg != null) {
                                timefmt = util.scopy(arg);
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
                            arg = try longArg(argv, i, &j, &n, "--sort");
                            if (arg != null) {
                                list.basesort = null;
                                k = 0;
                                while (sorts[k].name != null) : (k += 1) {
                                    if (c.strcasecmp(sorts[k].name, arg) == 0) {
                                        list.basesort = sorts[k].cmpfunc;
                                        break;
                                    }
                                }
                                if (sorts[k].name == null) {
                                    _ = c.fprintf(cStderr(), "tree: Sort type '%s' not valid, should be one of: ", arg);
                                    k = 0;
                                    while (sorts[k].name != null) : (k += 1) {
                                        _ = c.printf("%s%c", sorts[k].name, @as(c_int, if (sorts[k + 1].name != null) ',' else '\n'));
                                    }
                                    return error.InvalidArgument;
                                }
                                break;
                            }
                            if (c.strcmp("--fromtabfile", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.fromfile = true;
                                list.getfulltree = &file_mod.tabedfile_getfulltree;
                                break;
                            }
                            if (c.strcmp("--fromfile", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.fromfile = true;
                                list.getfulltree = &file_mod.file_getfulltree;
                                break;
                            }
                            if (c.strcmp("--metafirst", argv[i]) == 0) {
                                j = c.strlen(argv[i]) - 1;
                                flag.metafirst = if (opt_toggle) !flag.metafirst else true;
                                break;
                            }
                            arg = try longArg(argv, i, &j, &n, "--gitfile");
                            if (arg != null) {
                                flag.gitignore = true;
                                const new_ig = filter.new_ignorefile(util.io, arg, arg, false);
                                if (new_ig != null) filter.push_filterstack(new_ig) else {
                                    _ = c.fprintf(cStderr(), "tree: Could not load gitignore file\n");
                                    return error.InvalidArgument;
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
                            arg = try longArg(argv, i, &j, &n, "--infofile");
                            if (arg != null) {
                                flag.showinfo = true;
                                const new_inf = info_mod.new_infofile(arg, false);
                                if (new_inf != null) info_mod.push_infostack(new_inf) else {
                                    _ = c.fprintf(cStderr(), "tree: Could not load infofile\n");
                                    return error.InvalidArgument;
                                }
                                break;
                            }
                            arg = try longArg(argv, i, &j, &n, "--hintro");
                            if (arg != null) {
                                Hintro = util.scopy(arg);
                                break;
                            }
                            arg = try longArg(argv, i, &j, &n, "--houtro");
                            if (arg != null) {
                                Houtro = util.scopy(arg);
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
                            arg = try longArg(argv, i, &j, &n, "--scheme");
                            if (arg != null) {
                                if (c.strchr(arg, ':') == null) {
                                    _ = c.sprintf(&xpattern, "%s://", arg);
                                    arg = util.scopy(&xpattern);
                                } else {
                                    scheme = util.scopy(arg);
                                }
                                break;
                            }
                            arg = try longArg(argv, i, &j, &n, "--authority");
                            if (arg != null) {
                                // I don't believe that . by itself can be a valid hostname,
                                // so it will do as a null authority.
                                if (c.strcmp(arg, ".") == 0) authority = util.scopy("") else authority = util.scopy(arg);
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
                            arg = try longArg(argv, i, &j, &n, "--compress");
                            if (arg != null) {
                                flag.compress_indent = c.atoi(arg);
                                flag.remove_space = flag.compress_indent < 0;
                                if (flag.compress_indent < 0) {
                                    flag.compress_indent = -flag.compress_indent;
                                }
                                if (flag.compress_indent > 3) {
                                    flag.compress_indent = 0;
                                    flag.noindent = true;
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
                            help.print_all();
                            return error.InvalidArgument;
                        }
                        _ = c.fprintf(cStderr(), "tree: Invalid argument -`%c'.\n", @as(c_int, argv[i][j]));
                        help.print_all();
                        return error.InvalidArgument;
                    },
                    else => {
                        _ = c.fprintf(cStderr(), "tree: Invalid argument -`%c'.\n", @as(c_int, argv[i][j]));
                        help.print_all();
                        return error.InvalidArgument;
                    },
                }
            }
        } else {
            if (dirname == null) {
                dirname = @ptrCast(@alignCast(util.xmalloc(@sizeOf([*c]u8) * (q + constants.MINIT))));
                q = constants.MINIT;
            } else if (p == (q - 1)) {
                dirname = @ptrCast(@alignCast(util.xrealloc(@ptrCast(dirname), @sizeOf([*c]u8) * (q + constants.MINC))));
                q += constants.MINC;
            }
            dirname[p] = util.scopy(argv[i]);
            p += 1;
        }
    }
    if (p != 0) dirname[p] = null;

    patterns = patterns_list.items.ptr;
    pattern = @intCast(patterns_list.items.len);
    ipatterns = ipatterns_list.items.ptr;
    ipattern = @intCast(ipatterns_list.items.len);

    if (outfilename != null) {
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(outfilename.?)));
        util.file = std.Io.Dir.cwd().createFile(util.io, name, .{}) catch {
            _ = c.fprintf(cStderr(), "tree: invalid filename '%s'\n", outfilename);
            return error.InvalidOutputFile;
        };
    }

    parsedircolors();
    initlinedraw(false);

    if (showversion) {
        var vbuf: [256]u8 = undefined;
        var vfw = util.writer(&vbuf);
        vfw.interface.print("{s}\n", .{std.mem.span(version)}) catch {};
        vfw.interface.flush() catch {};
        return;
    }

    if (dirname == null) {
        dirname = @ptrCast(@alignCast(util.xmalloc(@sizeOf([*c]u8) * 2)));
        dirname[0] = util.scopy(".");
        dirname[1] = null;
    }
    if (list.topsort == null) list.topsort = list.basesort;
    if (list.basesort == null) list.topsort = null;
    if (timefmt != null) _ = c.setlocale(c.LC_TIME, "");
    if (flag.d) flag.prune = false;
    if (flag.R and Level == -1) flag.R = false;

    if (flag.hyper and authority == null) {
        // If the hostname is longer than PATH_MAX, maybe it's just as well we don't
        // try to use it.
        if (c.gethostname(&xpattern, std.fs.max_path_bytes) < 0) {
            _ = c.fprintf(cStderr(), "Unable to get hostname, using 'localhost'.\n");
            authority = @constCast("localhost");
        } else {
            authority = util.scopy(&xpattern);
        }
    }

    if (flag.showinfo) {
        info_mod.push_infostack(info_mod.new_infofile(constants.INFO_PATH, false));
    }

    needfulltree = flag.du or flag.prune or flag.matchdirs or flag.fromfile or flag.condense_singletons;

    emit_tree(lc, dirname, needfulltree);

    if (outfilename != null) util.file.close(util.io);

    if (errors != 0) return error.TreeHadErrors;
}
