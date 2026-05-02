//! File-input tree building, ported from file.c.

const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("tree.h");
});

const types = @import("types.zig");
const pat = @import("pattern.zig");
const util = @import("util.zig");
const filter = @import("filter.zig");
const info_mod = @import("info.zig");

extern var flag: types.Flags;
extern var pattern: c_int;
extern var ipattern: c_int;
extern var topsort: ?*const fn (
    [*c][*c]types.Info,
    [*c][*c]types.Info,
) callconv(.c) c_int;
extern var file_comment: [*c]u8;
extern var file_pathsep: [*c]u8;
extern var patterns: [*c][*c]u8;
extern var ipatterns: [*c][*c]u8;

extern fn push_files(dir: [*c]const u8, ig: [*c]?*types.IgnoreFile, inf: [*c]?*types.InfoFile, top: bool) void;
extern fn free_dir(d: [*c][*c]types.Info) void;

const MAXPATH = 64 * 1024; // 64KB paths maximum

// On macOS and BSD, the `stdin` C macro expands to `__stdinp`. cImport
// translates it as a function pointer rather than a FILE*. Declare the
// underlying global directly and use it via dead-branch elimination.
extern var __stdinp: ?*c.FILE;

fn cStdin() ?*c.FILE {
    // builtin.os.tag is comptime-known; the dead branch is not emitted.
    if (builtin.os.tag == .linux) return c.stdin;
    return __stdinp;
}

const Ftok = enum(c_int) {
    T_PATHSEP = 0,
    T_DIR = 1,
    T_FILE = 2,
    T_EOP = 3,
};

// Persists across calls (mirrors C's `static char prev`).
var nextpc_prev: u8 = 0;

fn nextpc(p: *[*c]u8, tok: *c_int) [*c]u8 {
    const s: [*c]u8 = p.*;
    if (p.*[0] == 0) {
        tok.* = @intFromEnum(Ftok.T_EOP); // Shouldn't happen.
        return null;
    }
    if (nextpc_prev != 0) {
        nextpc_prev = 0;
        tok.* = @intFromEnum(Ftok.T_PATHSEP);
        return null;
    }
    if (c.strchr(file_pathsep, p.*[0]) != null) {
        p.* += 1;
        tok.* = @intFromEnum(Ftok.T_PATHSEP);
        return null;
    }
    while (p.*[0] != 0 and c.strchr(file_pathsep, p.*[0]) == null) : (p.* += 1) {}
    if (p.*[0] != 0) {
        tok.* = @intFromEnum(Ftok.T_DIR);
        nextpc_prev = p.*[0];
        p.*[0] = 0;
        p.* += 1;
    } else {
        tok.* = @intFromEnum(Ftok.T_FILE);
    }
    return s;
}

fn newent(name: [*c]const u8) *types.Info {
    const n: *types.Info = @ptrCast(@alignCast(util.xmalloc(@sizeOf(types.Info))));
    @memset(@as([*]u8, @ptrCast(n))[0..@sizeOf(types.Info)], 0);
    n.name = util.scopy(name);
    n.child = null;
    n.tchild = null;
    n.next = null;
    return n;
}

// Don't insertion sort, let fprune() do the sort if necessary
fn search(dir: *[*c]types.Info, name: [*c]const u8) *types.Info {
    if (dir.* == null) {
        const n = newent(name);
        dir.* = n;
        return n;
    }
    var prev: [*c]types.Info = dir.*;
    var ptr: [*c]types.Info = dir.*;
    while (ptr != null) : (ptr = ptr[0].next) {
        if (c.strcmp(ptr[0].name, name) == 0) return @ptrCast(ptr);
        prev = ptr;
    }
    const n = newent(name);
    n.next = ptr; // null
    prev[0].next = n;
    return n;
}

fn freefiletree(ent: [*c]types.Info) void {
    var ptr: [*c]types.Info = ent;
    while (ptr != null) {
        if (ptr[0].tchild != null) freefiletree(ptr[0].tchild);
        const t = ptr;
        ptr = ptr[0].next;
        std.c.free(@ptrCast(t));
    }
}

// Recursively prune (unset show flag) files/directories of matches/ignored
// patterns:
// TODO: Perhaps make this the primary prune function and have unix_getfulltree
//       call it the same as the *file_getfulltree functions do.
fn fprune(
    head: [*c]types.Info,
    path: [*c]const u8,
    matched_in: bool,
    root: bool,
) [*c][*c]types.Info {
    var dir: [*c][*c]types.Info = null;
    var new_head: [*c]types.Info = null;
    var end: [*c]types.Info = null;
    var count: usize = 0;
    const defmatched = matched_in;
    var matched = matched_in;
    var tmp_pattern: c_int = 0;

    const fpath: [*c]u8 = @ptrCast(@alignCast(util.xmalloc(MAXPATH)));
    defer std.c.free(fpath);

    const path_len = c.strlen(path);
    if (path_len + 1 >= MAXPATH) {
        std.debug.print("tree: path exceeds maximum length ({d} bytes): {s}\n", .{ MAXPATH, path });
        return null;
    }
    _ = c.strcpy(fpath, path);
    var cur: [*c]u8 = fpath + path_len;
    cur[0] = '/';
    cur += 1;
    const cur_offset = path_len + 1;

    var ig: [*c]types.IgnoreFile = null;
    var inf: [*c]types.InfoFile = null;
    push_files(path, @ptrCast(&ig), @ptrCast(&inf), root);

    var ent: [*c]types.Info = head;
    while (ent != null) {
        const name_len = c.strlen(ent[0].name);
        if (cur_offset + name_len >= MAXPATH) {
            std.debug.print("tree: path exceeds maximum length, skipping: {s}/{s}\n", .{ path, ent[0].name });
            const skipped = ent;
            ent = ent[0].next;
            skipped[0].next = null;
            freefiletree(skipped);
            continue;
        }
        _ = c.strcpy(cur, ent[0].name);
        if (ent[0].tchild != null) ent[0].isdir = true;

        var show = true;
        if (flag.d and !ent[0].isdir) show = false;
        if (!flag.a and ent[0].name[0] == '.') show = false;

        if (show and !matched) {
            if (!ent[0].isdir) {
                if (pattern != 0 and
                    pat.include(ent[0].name, patterns[0..@intCast(pattern)], ent[0].isdir, false, flag.ignorecase, file_pathsep[0]) == 0 and
                    pat.include(fpath, patterns[0..@intCast(pattern)], ent[0].isdir, true, flag.ignorecase, file_pathsep[0]) == 0) show = false;
                if (ipattern != 0 and
                    (pat.ignore(ent[0].name, ipatterns[0..@intCast(ipattern)], ent[0].isdir, false, flag.ignorecase, file_pathsep[0]) != 0 or
                        pat.ignore(fpath, ipatterns[0..@intCast(ipattern)], ent[0].isdir, true, flag.ignorecase, file_pathsep[0]) != 0)) show = false;
            } else {
                if (pattern != 0 and
                    (pat.include(ent[0].name, patterns[0..@intCast(pattern)], ent[0].isdir, false, flag.ignorecase, file_pathsep[0]) != 0 or
                        pat.include(fpath, patterns[0..@intCast(pattern)], ent[0].isdir, true, flag.ignorecase, file_pathsep[0]) != 0))
                {
                    show = true;
                    matched = true;
                    tmp_pattern = pattern;
                    pattern = 0;
                }
                if (ipattern != 0 and
                    (pat.ignore(ent[0].name, ipatterns[0..@intCast(ipattern)], ent[0].isdir, false, flag.ignorecase, file_pathsep[0]) != 0 or
                        pat.ignore(fpath, ipatterns[0..@intCast(ipattern)], ent[0].isdir, true, flag.ignorecase, file_pathsep[0]) != 0)) show = false;
            }
        }

        if (flag.gitignore and filter.filtercheck(path, ent[0].name, @intFromBool(ent[0].isdir), flag.ignorecase)) {
            show = false;
        }

        if (show and flag.showinfo) {
            const com = info_mod.infocheck(path, ent[0].name, @intFromBool(inf != null), ent[0].isdir, flag.ignorecase);
            if (com != null) {
                var i: usize = 0;
                while (com.?.desc[i] != null) : (i += 1) {}
                ent[0].comment = @ptrCast(@alignCast(util.xmalloc(@sizeOf([*c]u8) * (i + 1))));
                var j: usize = 0;
                while (j < i) : (j += 1) ent[0].comment[j] = util.scopy(com.?.desc[j]);
                ent[0].comment[i] = null;
            }
        }

        if (show and ent[0].tchild != null)
            ent[0].child = fprune(ent[0].tchild, fpath, matched, false);

        if (flag.prune and !matched and ent[0].isdir and ent[0].child == null) {
            ent[0].tchild = null;
            show = false;
        }

        if (flag.condense_singletons) {
            while (util.is_singleton(@ptrCast(ent))) {
                const child = ent[0].child;
                var segs = [_][*c]const u8{ ent[0].name, child[0][0].name };
                const name = util.pathconcat(@ptrCast(&segs), 2);
                std.c.free(ent[0].name);
                ent[0].name = util.scopy(name);
                ent[0].child = child[0][0].child;
                ent[0].condensed = ent[0].condensed + 1 + child[0][0].condensed;
                free_dir(@ptrCast(child));
            }
        }

        if (tmp_pattern != 0) {
            pattern = tmp_pattern;
            tmp_pattern = 0;
        }
        matched = defmatched;

        const t: [*c]types.Info = ent;
        ent = ent[0].next;
        if (show) {
            if (end != null) {
                end[0].next = t;
                end = t;
            } else {
                new_head = t;
                end = t;
            }
            count += 1;
        } else {
            t[0].next = null;
            freefiletree(t);
        }
    }
    if (end != null) end[0].next = null;

    if (count > 0) {
        const arr: [*c][*c]types.Info = @ptrCast(@alignCast(util.xmalloc(@sizeOf([*c]types.Info) * (count + 1))));
        var i: usize = 0;
        var e: [*c]types.Info = new_head;
        while (e != null) : (i += 1) {
            arr[i] = e;
            e = e[0].next;
        }
        arr[count] = null;

        if (topsort != null and count > 1) {
            const cmp: ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int = @ptrCast(topsort.?);
            c.qsort(@ptrCast(arr), count, @sizeOf([*c]types.Info), cmp);
        }
        dir = arr;
    }

    if (ig != null) ig = @ptrCast(filter.flush_filterstack());
    if (inf != null) inf = @ptrCast(info_mod.pop_infostack());

    return dir;
}

pub fn file_getfulltree(
    d: [*c]u8,
    lev: c.u_long,
    dev: c.dev_t,
    size: *c.off_t,
    err: [*c][*c]u8,
) callconv(.c) [*c][*c]types.Info {
    _ = lev;
    _ = dev;
    _ = err;

    const use_stdin = c.strcmp(d, ".") == 0;
    const fp: ?*c.FILE = if (use_stdin) cStdin() else c.fopen(d, "r");
    size.* = 0;

    if (fp == null) {
        std.debug.print("tree: Error opening {s} for reading.\n", .{d});
        return null;
    }

    var root: [*c]types.Info = null;
    const path: [*c]u8 = @ptrCast(@alignCast(util.xmalloc(MAXPATH)));
    defer std.c.free(path);

    while (c.fgets(path, MAXPATH, fp) != null) {
        if (file_comment != null and
            c.strncmp(path, file_comment, c.strlen(file_comment)) == 0) continue;

        var l = c.strlen(path);
        while (l > 0 and (path[l - 1] == '\n' or path[l - 1] == '\r')) {
            l -= 1;
            path[l] = 0;
        }
        if (l == 0) continue;

        var spath: [*c]u8 = path;
        var cwd_ptr: *[*c]types.Info = &root;

        const link: [*c]u8 = if (flag.fflinks) c.strstr(path, " -> ") else null;
        if (link != null) link[0] = 0;

        var tok: c_int = 0;
        var ent: [*c]types.Info = null;
        while (true) {
            const s = nextpc(&spath, &tok);
            const ftok: Ftok = @enumFromInt(tok);
            switch (ftok) {
                .T_PATHSEP => {},
                .T_FILE, .T_DIR => {
                    if (c.strcmp(s, ".") == 0) {
                        if (ftok == .T_FILE) break;
                        continue;
                    }
                    // Assume that '..' shouldn't ever occur.
                    ent = search(cwd_ptr, s);
                    // Might be empty, but should definitely be considered a directory:
                    if (ftok == .T_DIR) {
                        ent[0].isdir = true;
                        ent[0].mode = @intCast(c.S_IFDIR);
                    } else {
                        ent[0].mode = @intCast(c.S_IFREG);
                    }
                    cwd_ptr = &(ent[0].tchild);
                },
                .T_EOP => break,
            }
            if (ftok == .T_FILE) break;
        }

        if (ent != null and link != null) {
            ent[0].isdir = false;
            ent[0].mode = @intCast(c.S_IFLNK);
            ent[0].lnk = util.scopy(link + 4);
        }
    }

    if (!use_stdin) _ = c.fclose(fp);

    // Prune accumulated directory tree:
    return fprune(root, "", false, true);
}

pub fn tabedfile_getfulltree(
    d: [*c]u8,
    lev: c.u_long,
    dev: c.dev_t,
    size: *c.off_t,
    err: [*c][*c]u8,
) callconv(.c) [*c][*c]types.Info {
    _ = lev;
    _ = dev;
    _ = err;

    const use_stdin = c.strcmp(d, ".") == 0;
    const fp: ?*c.FILE = if (use_stdin) cStdin() else c.fopen(d, "r");
    size.* = 0;

    if (fp == null) {
        std.debug.print("tree: Error opening {s} for reading.\n", .{d});
        return null;
    }

    var root: [*c]types.Info = null;
    const maxstack: usize = 2048;
    const path: [*c]u8 = @ptrCast(@alignCast(util.xmalloc(MAXPATH)));
    defer std.c.free(path);
    const istack: [*c][*c]types.Info = @ptrCast(@alignCast(util.xmalloc(@sizeOf([*c]types.Info) * maxstack)));
    defer std.c.free(@ptrCast(istack));
    @memset(@as([*]u8, @ptrCast(istack))[0 .. @sizeOf([*c]types.Info) * maxstack], 0);

    var line: usize = 0;
    var top: usize = 0;

    while (c.fgets(path, MAXPATH, fp) != null) {
        line += 1;
        if (file_comment != null and
            c.strncmp(path, file_comment, c.strlen(file_comment)) == 0) continue;

        var l = c.strlen(path);
        while (l > 0 and (path[l - 1] == '\n' or path[l - 1] == '\r')) {
            l -= 1;
            path[l] = 0;
        }
        if (l == 0) continue;

        var tabs: usize = 0;
        while (path[tabs] == '\t') : (tabs += 1) {}
        if (tabs >= maxstack) {
            std.debug.print(
                "tree: Tab depth exceeds maximum path depth ({d} >= {d}) on line {d}\n",
                .{ tabs, maxstack, line },
            );
            continue;
        }

        const spath: [*c]u8 = path + tabs;

        const link: [*c]u8 = if (flag.fflinks) c.strstr(spath, " -> ") else null;
        if (link != null) link[0] = 0;

        if (tabs > 0 and (tabs - 1 > top or istack[tabs - 1] == null)) {
            std.debug.print(
                "tree: Orphaned file [{s}] on line {d}, check tab depth in file.\n",
                .{ spath, line },
            );
            continue;
        }

        const dir_ptr: *[*c]types.Info = if (tabs != 0) &(istack[tabs - 1][0].tchild) else &root;
        const ent: [*c]types.Info = search(dir_ptr, spath);
        istack[tabs] = ent;
        ent[0].mode = @intCast(c.S_IFREG);

        if (tabs > 0) {
            istack[tabs - 1][0].isdir = true;
            istack[tabs - 1][0].mode = @intCast(c.S_IFDIR);
        }

        if (link != null) {
            ent[0].isdir = false;
            ent[0].mode = @intCast(c.S_IFLNK);
            ent[0].lnk = util.scopy(link + 4);
        }
        top = tabs;
    }

    if (!use_stdin) _ = c.fclose(fp);

    // Prune accumulated directory tree:
    return fprune(root, "", false, true);
}
