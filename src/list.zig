//! Tree listing driver ported from list.c.

const std = @import("std");
const builtin = @import("builtin");

const c = @import("cstd.zig");

const types = @import("types.zig");
const hash = @import("hash.zig");
const html = @import("html.zig");
const util = @import("util.zig");
const filter = @import("filter.zig");
const info_mod = @import("info.zig");
const linux = @import("linux.zig");

pub const GetFullTreeFn = fn ([*c]u8, c_ulong, c.dev_t, *c.off_t, [*c][*c]u8) [*c]?*types.Info;
pub const SortFn = fn (*types.Info, *types.Info) c_int;

pub var getfulltree: *const GetFullTreeFn = undefined;
pub var basesort: ?*const SortFn = null;
pub var topsort: ?*const SortFn = null;

pub fn infoLessThan(cmp: *const SortFn, a: ?*types.Info, b: ?*types.Info) bool {
    return cmp(a.?, b.?) < 0;
}

var lstat_info: types.Info = std.mem.zeroes(types.Info);

fn doLstat(path: [*c]u8, dev_out: *c.dev_t) [*c]types.Info {
    lstat_info = std.mem.zeroes(types.Info);
    if (builtin.os.tag == .linux) {
        var st: std.os.linux.Statx = undefined;
        if (!linux.stat(@ptrCast(path), std.os.linux.AT.SYMLINK_NOFOLLOW, &st)) return null;
        const dev = linux.devId(&st);
        hash.saveino(@intCast(st.ino), @intCast(dev));
        dev_out.* = @intCast(dev);
        lstat_info.linode = @intCast(st.ino);
        lstat_info.ldev = @intCast(dev);
        lstat_info.mode = @intCast(st.mode);
        lstat_info.uid = @intCast(st.uid);
        lstat_info.gid = @intCast(st.gid);
        lstat_info.size = @intCast(st.size);
        lstat_info.atime = @intCast(st.atime.sec);
        lstat_info.ctime = @intCast(st.ctime.sec);
        lstat_info.mtime = @intCast(st.mtime.sec);
    } else {
        var st: c.struct_stat = undefined;
        if (c.lstat(path, &st) < 0) return null;
        hash.saveino(st.ino, st.dev);
        dev_out.* = st.dev;
        lstat_info.linode = st.ino;
        lstat_info.ldev = st.dev;
        lstat_info.mode = @intCast(st.mode);
        lstat_info.uid = st.uid;
        lstat_info.gid = st.gid;
        lstat_info.size = st.size;
        lstat_info.atime = st.atime().sec;
        lstat_info.ctime = st.ctime().sec;
        lstat_info.mtime = st.mtime().sec;
    }
    const mode: u32 = @intCast(lstat_info.mode);
    const s_ifmt: u32 = @as(u32, std.posix.S.IFMT);
    lstat_info.isdir = (mode & s_ifmt) == @as(u32, std.posix.S.IFDIR);
    lstat_info.issok = (mode & s_ifmt) == @as(u32, std.posix.S.IFSOCK);
    lstat_info.isfifo = (mode & s_ifmt) == @as(u32, std.posix.S.IFIFO);
    const exec_mask: u32 = @as(u32, std.posix.S.IXUSR | std.posix.S.IXGRP | std.posix.S.IXOTH);
    lstat_info.isexe = (mode & exec_mask) != 0;
    return &lstat_info;
}

extern var flag: types.Flags;

extern var dirs: [*c]c_int;
extern var errors: c_int;
extern var Level: isize;
extern var htmldirlen: usize;

extern fn read_dir(dir: [*c]u8, n: [*c]isize, infotop: c_int) [*c]?*types.Info;
extern fn free_dir(d: [*c]?*types.Info) void;

var errbuf: [256]u8 = undefined;
var realbasepath: [std.fs.max_path_bytes]u8 = std.mem.zeroes([std.fs.max_path_bytes]u8);
var dirpathoffset: usize = 0;

export fn emit_hyperlink_path(w: *std.Io.Writer, dirname: [*c]u8) void {
    // (optional) Hanging slashes are a real pain to deal with
    var slash = html.url_encode(w, &realbasepath);
    if (dirname[dirpathoffset] != 0) {
        slash = slash or (dirname[dirpathoffset] == std.fs.path.sep);
        if (!slash) w.writeByte('/') catch {};
        if (!html.url_encode(w, dirname + dirpathoffset)) w.writeByte('/') catch {};
    } else if (!slash) {
        w.writeByte('/') catch {};
    }
}

//  TODO: Refactor the listing calls / when they are called.  A more thorough
//  analysis of the different outputs is required.  This all is not as clean as I
//  had hoped it to be.

pub fn emit_tree(lc: types.ListingCalls, dirname: [*c][*c]u8, needfulltree: bool) std.mem.Allocator.Error!void {
    var tot = types.Totals{ .files = 0, .dirs = 0, .size = 0 };
    var ig: ?*types.IgnoreFile = null;
    var inf: ?*types.InfoFile = null;
    var err: [*c]u8 = null;

    lc.intro.?();

    var i: usize = 0;
    while (dirname[i] != null) : (i += 1) {
        var dir: [*c]?*types.Info = null;
        var info: [*c]types.Info = null;

        if (flag.hyper) {
            if (c.realpath(dirname[i], &realbasepath) == null) {
                realbasepath[0] = 0;
                dirpathoffset = 0;
            } else {
                dirpathoffset = c.strLen(dirname[i]);
            }
        }

        if (flag.f) {
            var j: usize = c.strLen(dirname[i]);
            while (j > 1 and dirname[i][j - 1] == std.fs.path.sep) {
                j -= 1;
                dirname[i][j] = 0;
            }
        }
        if (flag.H) htmldirlen = c.strLen(dirname[i]);

        var st_dev: c.dev_t = 0;
        info = doLstat(dirname[i], &st_dev);
        var n: isize = if (info == null) -1 else 0;

        if (info != null) {
            info.*.name = @constCast(""); //dirname[i];

            if (needfulltree) {
                dir = getfulltree(dirname[i], 0, st_dev, &info.*.size, &err);
                n = if (err != null) -1 else 0;
            } else {
                filter.pushFiles(dirname[i], &ig, &inf, true);
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
                subtotal = try listdir(lc, dirname[i], dir, 1, st_dev, needfulltree);
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

        if (ig != null) ig = filter.flush_filterstack();
        if (inf != null) inf = info_mod.pop_infostack();
    }

    if (!flag.noreport) lc.report.?(tot);

    lc.outtro.?();
}

pub fn listdir(
    lc: types.ListingCalls,
    dirname: [*c]u8,
    dir_in: [*c]?*types.Info,
    lev: c_int,
    dev: c.dev_t,
    hasfulltree: bool,
) std.mem.Allocator.Error!types.Totals {
    var tot = types.Totals{ .files = 0, .dirs = 0, .size = 0 };
    var subtotal: types.Totals = undefined;
    var ig: ?*types.IgnoreFile = null;
    var inf: ?*types.InfoFile = null;
    var subdir: [*c]?*types.Info = null;
    var namemax: usize = 257;
    var htmldescend: c_int = 0;
    var n: isize = undefined;
    const dirname_len: usize = c.strLen(dirname);
    const dirlen: usize = dirname_len + 2;
    var pathlen: usize = dirlen + 257;
    var err: [*c]u8 = null;

    const es: bool = (dirname[dirname_len - 1] == std.fs.path.sep);

    // Sanity check on dir, may or may not be necessary when using --fromfile:
    if (dir_in == null or dir_in[0] == null) return tot;

    n = 0;
    while (dir_in[@as(usize, @intCast(n))] != null) : (n += 1) {}
    if (topsort != null) {
        std.mem.sort(?*types.Info, dir_in[0..@intCast(n)], topsort.?, infoLessThan);
    }

    var cursor = dir_in;
    dirs[@intCast(lev)] = if (cursor[1] != null) 1 else 2;

    var path: []u8 = try util.gpa.alloc(u8, pathlen);
    defer util.gpa.free(path);

    while (cursor[0]) |entry| : (cursor += 1) {
        _ = lc.printinfo.?(dirname, entry, lev);

        const namelen: usize = c.strLen(entry.name) + 1;
        if (namemax < namelen) {
            namemax = namelen;
            pathlen = dirlen + namemax;
            path = try util.gpa.realloc(path, pathlen);
        }
        if (es) {
            _ = c.sprintf(path.ptr, "%s%s", dirname, entry.name);
        } else {
            _ = c.sprintf(path.ptr, "%s/%s", dirname, entry.name);
        }
        const filename: [*c]u8 = if (flag.f) path.ptr else entry.name;

        var descend: c_int = 0;
        err = null;
        const newpath: [*c]u8 = path.ptr;

        if (entry.isdir) {
            tot.dirs += 1;
            if (flag.condense_singletons) tot.dirs += entry.condensed;

            var found: bool = false;
            if (!hasfulltree) {
                found = hash.findino(entry.inode, entry.dev);
                if (!found) hash.saveino(entry.inode, entry.dev);
            }

            const xdev_block = flag.xdev and dev != entry.dev;
            const link_block = entry.lnk != null and !flag.l;
            if (!xdev_block and !link_block) {
                descend = 1;

                // if ((*dir)->lnk) {
                //   if (*(*dir)->lnk == '/') newpath = (*dir)->lnk;
                //   else {
                //     if (flag.f && !strcmp(dirname,"/")) sprintf(path,"%s%s",dirname,(*dir)->lnk);
                //     else sprintf(path,"%s/%s",dirname,(*dir)->lnk);
                //   }
                //   if (found) {
                //     err = "recursive, not followed";
                //     /* Not actually a problem if we weren't going to descend anyway: */
                //     if (Level >= 0 && lev > Level) err = NULL;
                //     descend = -1;
                //   }
                // }

                if (entry.lnk != null and found) {
                    err = @constCast("recursive, not followed");
                    // Not actually a problem if we weren't going to descend anyway:
                    if (Level >= 0 and lev > Level) err = null;
                    descend = -1;
                }

                if (Level >= 0 and lev > Level) {
                    if (flag.R) {
                        const outsave = util.file;
                        var paths = [_][*c]u8{ newpath, null };
                        const output: []u8 = try util.gpa.alloc(u8, c.strLen(newpath) + 13);
                        defer util.gpa.free(output);
                        const dirsave: []c_int = try util.gpa.alloc(c_int, @as(usize, @intCast(lev + 2)));
                        defer util.gpa.free(dirsave);

                        const copy_len: usize = @intCast(lev + 1);
                        @memcpy(dirsave[0..copy_len], dirs[0..copy_len]);
                        _ = c.sprintf(output.ptr, "%s/00Tree.html", newpath);
                        const output_name = std.mem.span(@as([*:0]const u8, @ptrCast(output.ptr)));
                        util.file = std.Io.Dir.cwd().createFile(util.io, output_name, .{}) catch {
                            std.debug.print("tree: invalid filename '{s}'\n", .{output_name});
                            c.exit(c.EXIT_FAILURE);
                            unreachable;
                        };
                        try emit_tree(lc, &paths, hasfulltree);

                        util.file.close(util.io);
                        util.file = outsave;

                        @memcpy(dirs[0..copy_len], dirsave[0..copy_len]);
                        htmldescend = 10;
                    } else {
                        htmldescend = 0;
                    }
                    descend = 0;
                }

                if (descend > 0) {
                    if (hasfulltree) {
                        subdir = entry.child;
                        err = entry.err;
                    } else {
                        filter.pushFiles(newpath, &ig, &inf, false);
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

            subtotal = try listdir(lc, newpath, subdir, lev + 1, dev, hasfulltree);
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

        if (ig != null) ig = filter.pop_filterstack();
        if (inf != null) inf = info_mod.pop_infostack();
    }

    dirs[@intCast(lev)] = 0;
    return tot;
}
