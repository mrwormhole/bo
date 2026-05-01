//! Tree listing driver ported from list.c.

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("tree.h");
});

const types = @import("types.zig");
const stat = @import("stat.zig");

var lstat_info: types.Info = std.mem.zeroes(types.Info);

fn doLstat(path: [*c]u8, dev_out: *c.dev_t) [*c]types.Info {
    lstat_info = std.mem.zeroes(types.Info);
    if (builtin.os.tag == .linux) {
        var st: std.os.linux.Stat = undefined;
        if (!stat.linuxStat(@ptrCast(path), std.os.linux.AT.SYMLINK_NOFOLLOW, &st)) return null;
        saveino(@intCast(st.ino), @intCast(st.dev));
        dev_out.* = @intCast(st.dev);
        lstat_info.linode = @intCast(st.ino);
        lstat_info.ldev = @intCast(st.dev);
        lstat_info.mode = @intCast(st.mode);
        lstat_info.uid = @intCast(st.uid);
        lstat_info.gid = @intCast(st.gid);
        lstat_info.size = @intCast(st.size);
        lstat_info.atime = @intCast(st.atim.sec);
        lstat_info.ctime = @intCast(st.ctim.sec);
        lstat_info.mtime = @intCast(st.mtim.sec);
    } else {
        var st: c.struct_stat = undefined;
        if (c.lstat(path, &st) < 0) return null;
        saveino(st.st_ino, st.st_dev);
        dev_out.* = st.st_dev;
        lstat_info.linode = st.st_ino;
        lstat_info.ldev = st.st_dev;
        lstat_info.mode = @intCast(st.st_mode);
        lstat_info.uid = st.st_uid;
        lstat_info.gid = st.st_gid;
        lstat_info.size = st.st_size;
        // st_atime/ctime/mtime are C macros, not real struct fields.
        // macOS uses st_atimespec; FreeBSD and other POSIX systems use st_atim.
        if (comptime @hasField(c.struct_stat, "st_atimespec")) {
            lstat_info.atime = st.st_atimespec.tv_sec;
            lstat_info.ctime = st.st_ctimespec.tv_sec;
            lstat_info.mtime = st.st_mtimespec.tv_sec;
        } else {
            lstat_info.atime = st.st_atim.tv_sec;
            lstat_info.ctime = st.st_ctim.tv_sec;
            lstat_info.mtime = st.st_mtim.tv_sec;
        }
    }
    const mode: u32 = @intCast(lstat_info.mode);
    const s_ifmt: u32 = @as(u32, c.S_IFMT);
    lstat_info.isdir = (mode & s_ifmt) == @as(u32, c.S_IFDIR);
    lstat_info.issok = (mode & s_ifmt) == @as(u32, c.S_IFSOCK);
    lstat_info.isfifo = (mode & s_ifmt) == @as(u32, c.S_IFIFO);
    const exec_mask: u32 = @as(u32, c.S_IXUSR | c.S_IXGRP | c.S_IXOTH);
    lstat_info.isexe = (mode & exec_mask) != 0;
    return &lstat_info;
}

extern var flag: types.Flags;
extern var getfulltree: ?*const fn ([*c]u8, c.u_long, c.dev_t, [*c]c.off_t, [*c][*c]u8) callconv(.c) [*c][*c]types.Info;
extern var topsort: ?*const fn ([*c][*c]types.Info, [*c][*c]types.Info) callconv(.c) c_int;

extern var outfile: *std.fs.File;
extern var dirs: [*c]c_int;
extern var errors: c_int;
extern var Level: isize;
extern var htmldirlen: usize;

extern fn saveino(ino: c.ino_t, dev: c.dev_t) void;
extern fn findino(ino: c.ino_t, dev: c.dev_t) bool;
extern fn url_encode(w: *std.Io.Writer, s: [*c]u8) bool;
extern fn push_files(dir: [*c]const u8, ig: [*c]?*types.IgnoreFile, inf: [*c]?*types.InfoFile, top: bool) void;
extern fn read_dir(dir: [*c]u8, n: [*c]isize, infotop: c_int) [*c][*c]types.Info;
extern fn free_dir(d: [*c][*c]types.Info) void;
extern fn flush_filterstack() ?*types.IgnoreFile;
extern fn pop_filterstack() ?*types.IgnoreFile;
extern fn pop_infostack() ?*types.InfoFile;
extern fn xmalloc(size: usize) *anyopaque;
extern fn xrealloc(ptr: ?*anyopaque, size: usize) *anyopaque;

var errbuf: [256]u8 = undefined;
var realbasepath: [c.PATH_MAX]u8 = std.mem.zeroes([c.PATH_MAX]u8);
var dirpathoffset: usize = 0;

export fn emit_hyperlink_path(w: *std.Io.Writer, dirname: [*c]u8) void {
    // (optional) Hanging slashes are a real pain to deal with
    var slash = url_encode(w, &realbasepath);
    if (dirname[dirpathoffset] != 0) {
        slash = slash or (dirname[dirpathoffset] == '/');
        if (!slash) w.writeByte('/') catch {};
        if (!url_encode(w, dirname + dirpathoffset)) w.writeByte('/') catch {};
    } else if (!slash) {
        w.writeByte('/') catch {};
    }
}

//  TODO: Refactor the listing calls / when they are called.  A more thorough
//  analysis of the different outputs is required.  This all is not as clean as I
//  had hoped it to be.

pub fn emit_tree(lc: types.ListingCalls, dirname: [*c][*c]u8, needfulltree: bool) void {
    var tot = types.Totals{ .files = 0, .dirs = 0, .size = 0 };
    var ig: ?*types.IgnoreFile = null;
    var inf: ?*types.InfoFile = null;
    var err: [*c]u8 = null;

    lc.intro.?();

    var i: usize = 0;
    while (dirname[i] != null) : (i += 1) {
        var dir: [*c][*c]types.Info = null;
        var info: [*c]types.Info = null;

        if (flag.hyper) {
            if (c.realpath(dirname[i], &realbasepath) == null) {
                realbasepath[0] = 0;
                dirpathoffset = 0;
            } else {
                dirpathoffset = c.strlen(dirname[i]);
            }
        }

        if (flag.f) {
            var j: usize = c.strlen(dirname[i]);
            while (j > 1 and dirname[i][j - 1] == '/') {
                j -= 1;
                dirname[i][j] = 0;
            }
        }
        if (flag.H) htmldirlen = c.strlen(dirname[i]);

        var st_dev: c.dev_t = 0;
        info = doLstat(dirname[i], &st_dev);
        var n: isize = if (info == null) -1 else 0;

        if (info != null) {
            info.*.name = @constCast(""); //dirname[i];

            if (needfulltree) {
                dir = getfulltree.?(dirname[i], 0, st_dev, &info.*.size, &err);
                n = if (err != null) -1 else 0;
            } else {
                push_files(dirname[i], &ig, &inf, true);
                dir = read_dir(dirname[i], &n, @intFromBool(inf != null));
            }
        } else {
            info = null;
        }
        _ = lc.printinfo.?(dirname[i], info, 0);

        const printfile_arg: c_int = @intFromBool(dir != null or n != 0);
        const needsclosed = lc.printfile.?(dirname[i], dirname[i], info, printfile_arg);
        var subtotal = types.Totals{ .files = 0, .dirs = 0, .size = 0 };

        if (dir == null and n != 0) {
            _ = lc.@"error".?(@constCast("error opening dir"));
            lc.newline.?(info, 0, 0, @intFromBool(dirname[i + 1] != null));
            if (info == null) errors += 1 else subtotal.files += 1;
        } else if (flag.flimit > 0 and n > flag.flimit) {
            _ = c.sprintf(&errbuf, "%ld entries exceeds filelimit, not opening dir", @as(c_long, @intCast(n)));
            _ = lc.@"error".?(&errbuf);
            lc.newline.?(info, 0, 0, @intFromBool(dirname[i + 1] != null));
            subtotal.dirs += 1;
        } else {
            lc.newline.?(info, 0, 0, 0);
            if (dir != null) {
                subtotal = listdir(dirname[i], dir, 1, st_dev, needfulltree);
                subtotal.dirs += 1;
            }
        }
        if (dir != null) {
            free_dir(dir);
            dir = null;
        }
        if (needsclosed != 0) lc.close.?(info, 0, @intFromBool(dirname[i + 1] != null));

        tot.files += subtotal.files;
        tot.dirs += subtotal.dirs;
        // Do not bother to accumulate tot.size in listdir.
        // This is already done in getfulltree()
        if (flag.du) tot.size += if (info != null) info.*.size else 0;

        if (ig != null) ig = flush_filterstack();
        if (inf != null) inf = pop_infostack();
    }

    if (!flag.noreport) lc.report.?(tot);

    lc.outtro.?();
}

pub fn listdir(
    lc: types.ListingCalls,
    dirname: [*c]u8,
    dir_in: [*c][*c]types.Info,
    lev: c_int,
    dev: c.dev_t,
    hasfulltree: bool,
) types.Totals {
    var tot = types.Totals{ .files = 0, .dirs = 0, .size = 0 };
    var subtotal: types.Totals = undefined;
    var ig: ?*types.IgnoreFile = null;
    var inf: ?*types.InfoFile = null;
    var subdir: [*c][*c]types.Info = null;
    var namemax: usize = 257;
    var htmldescend: c_int = 0;
    var n: isize = undefined;
    const dirname_len: usize = c.strlen(dirname);
    const dirlen: usize = dirname_len + 2;
    var pathlen: usize = dirlen + 257;
    var err: [*c]u8 = null;

    const es: bool = (dirname[dirname_len - 1] == '/');

    // Sanity check on dir, may or may not be necessary when using --fromfile:
    if (dir_in == null or dir_in[0] == null) return tot;

    n = 0;
    while (dir_in[@as(usize, @intCast(n))] != null) : (n += 1) {}
    if (topsort != null) {
        const cmp: ?*const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int = @ptrCast(topsort.?);
        c.qsort(@ptrCast(dir_in), @as(usize, @intCast(n)), @sizeOf([*c]types.Info), cmp);
    }

    var cursor = dir_in;
    dirs[@intCast(lev)] = if (cursor[1] != null) 1 else 2;

    var path: [*c]u8 = @ptrCast(xmalloc(@sizeOf(u8) * pathlen));

    while (cursor[0] != null) : (cursor += 1) {
        const entry = cursor[0];
        _ = lc.printinfo.?(dirname, entry, lev);

        const namelen: usize = c.strlen(entry.*.name) + 1;
        if (namemax < namelen) {
            namemax = namelen;
            pathlen = dirlen + namemax;
            path = @ptrCast(xrealloc(path, pathlen));
        }
        if (es) {
            _ = c.sprintf(path, "%s%s", dirname, entry.*.name);
        } else {
            _ = c.sprintf(path, "%s/%s", dirname, entry.*.name);
        }
        const filename: [*c]u8 = if (flag.f) path else entry.*.name;

        var descend: c_int = 0;
        err = null;
        const newpath: [*c]u8 = path;

        if (entry.*.isdir) {
            tot.dirs += 1;
            if (flag.condense_singletons) tot.dirs += entry.*.condensed;

            var found: bool = false;
            if (!hasfulltree) {
                found = findino(entry.*.inode, entry.*.dev);
                if (!found) saveino(entry.*.inode, entry.*.dev);
            }

            const xdev_block = flag.xdev and dev != entry.*.dev;
            const link_block = entry.*.lnk != null and !flag.l;
            if (!xdev_block and !link_block) {
                descend = 1;

                if (entry.*.lnk != null and found) {
                    err = @constCast("recursive, not followed");
                    // Not actually a problem if we weren't going to descend anyway:
                    if (Level >= 0 and lev > Level) err = null;
                    descend = -1;
                }

                if (Level >= 0 and lev > Level) {
                    if (flag.R) {
                        const outsave = outfile.*;
                        var paths = [_][*c]u8{ newpath, null };
                        const output: [*c]u8 = @ptrCast(xmalloc(c.strlen(newpath) + 13));
                        const dirsave: [*c]c_int = @ptrCast(@alignCast(xmalloc(@sizeOf(c_int) * @as(usize, @intCast(lev + 2)))));

                        const copy_bytes: usize = @sizeOf(c_int) * @as(usize, @intCast(lev + 1));
                        _ = c.memcpy(dirsave, dirs, copy_bytes);
                        _ = c.sprintf(output, "%s/00Tree.html", newpath);
                        const output_name = std.mem.span(@as([*:0]const u8, @ptrCast(output)));
                        outfile.* = std.fs.cwd().createFile(output_name, .{}) catch {
                            std.debug.print("tree: invalid filename '{s}'\n", .{output_name});
                            c.exit(c.EXIT_FAILURE);
                            unreachable;
                        };
                        emit_tree(lc, &paths, hasfulltree);

                        c.free(output);
                        outfile.close();
                        outfile.* = outsave;

                        _ = c.memcpy(dirs, dirsave, copy_bytes);
                        c.free(dirsave);
                        htmldescend = 10;
                    } else {
                        htmldescend = 0;
                    }
                    descend = 0;
                }

                if (descend > 0) {
                    if (hasfulltree) {
                        subdir = entry.*.child;
                        err = entry.*.err;
                    } else {
                        push_files(newpath, &ig, &inf, false);
                        subdir = read_dir(newpath, &n, @intFromBool(inf != null));
                        if (subdir == null and n != 0) {
                            err = @constCast("error opening dir");
                            errors += 1;
                        }
                        if (flag.flimit > 0 and n > flag.flimit) {
                            _ = c.sprintf(&errbuf, "%ld entries exceeds filelimit, not opening dir", @as(c_long, @intCast(n)));
                            err = &errbuf;
                            errors += 1;
                            free_dir(subdir);
                            subdir = null;
                        }
                    }
                    if (subdir == null) descend = 0;
                }
            }
        } else {
            tot.files += 1;
        }

        const printfile_arg: c_int = descend + htmldescend + @intFromBool(flag.J and errors != 0);
        const needsclosed = lc.printfile.?(dirname, filename, entry, printfile_arg);
        if (err != null) _ = lc.@"error".?(err);

        if (descend > 0) {
            lc.newline.?(entry, lev, 0, 0);

            subtotal = listdir(lc, newpath, subdir, lev + 1, dev, hasfulltree);
            tot.dirs += subtotal.dirs;
            tot.files += subtotal.files;
        } else if (needsclosed == 0) {
            lc.newline.?(entry, lev, 0, @intFromBool(cursor[1] != null));
        }

        if (subdir != null) {
            free_dir(subdir);
            subdir = null;
        }
        if (needsclosed != 0) {
            const close_lev: c_int = if (descend != 0) lev else -1;
            lc.close.?(entry, close_lev, @intFromBool(cursor[1] != null));
        }

        if (cursor[1] != null and cursor[2] == null) dirs[@intCast(lev)] = 2;

        if (ig != null) ig = pop_filterstack();
        if (inf != null) inf = pop_infostack();
    }

    dirs[@intCast(lev)] = 0;
    c.free(path);
    return tot;
}
