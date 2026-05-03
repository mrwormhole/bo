//! .gitignore-style filtering ported from filter.c.

const std = @import("std");
const c = @cImport({
    @cInclude("tree.h");
});

const types = @import("types.zig");
const pat = @import("pattern.zig");
const util = @import("util.zig");
const info_mod = @import("info.zig");

extern var xpattern: [c.PATH_MAX]u8;
extern var flag: types.Flags;

pub fn pushFiles(dir: [*c]const u8, ig: [*c]?*types.IgnoreFile, inf: [*c]?*types.InfoFile, top: bool) void {
    var path_buf: [c.PATH_MAX]u8 = undefined;

    if (flag.gitignore) {
        var tig: ?*types.IgnoreFile = null;
        // Not going to implement git configs so no core.excludesFile support.
        if (top) {
            const stmp = c.getenv("GIT_DIR");
            if (stmp != null) {
                var segs = [_][*c]u8{ &path_buf, stmp, @constCast("info/exclude") };
                push_filterstack(new_ignorefile(util.io, stmp, util.pathconcat(@ptrCast(&segs), 3), false));
                tig = new_ignorefile(util.io, stmp, util.pathconcat(@ptrCast(&segs), 3), false);
            }
        }
        if (top) {
            ig.* = gitignore_search(util.io, dir, 0);
        } else {
            ig.* = new_ignorefile(util.io, dir, dir, top);
            push_filterstack(ig.*);
        }
        if (ig.* == null) ig.* = tig;
    }
    if (flag.showinfo) {
        inf.* = info_mod.new_infofile(dir, top);
        info_mod.push_infostack(inf.*);
    }
}

var filterstack: ?*types.IgnoreFile = null;

fn is_file(io: std.Io, path: [*c]const u8) bool {
    const path_slice = std.mem.span(path);
    const stat = std.Io.Dir.cwd().statFile(io, path_slice, .{}) catch return false;
    return stat.kind == .file;
}

fn is_dir(io: std.Io, path: [*c]const u8) bool {
    const path_slice = std.mem.span(path);
    const stat = std.Io.Dir.cwd().statFile(io, path_slice, .{}) catch return false;
    return stat.kind == .directory;
}

/// Search up the directory tree for .gitignore files, stopping at a directory
/// that contains a .git directory, or at /, whichever occurs first. The depth
/// parameter is just a sanity check to insure we can't get into a loop somehow,
/// even though that should be impossible.
pub fn gitignore_search(io: std.Io, startpath: [*c]const u8, depth: c_int) ?*types.IgnoreFile {
    var pign: ?*types.IgnoreFile = null;
    var ign: ?*types.IgnoreFile = null;
    var path: [c.PATH_MAX + 1]u8 = undefined;

    // strcpy(rpath, startpath);

    // Stop when we hit a directory with a .git directory. we'll assume it's the
    // git root:
    _ = c.snprintf(&path, c.PATH_MAX, "%.*s/.git", @as(c_int, c.PATH_MAX - 6), startpath);
    if (is_dir(io, &path)) {
        // Add it's .git/config/exclude
        _ = c.snprintf(&path, c.PATH_MAX, "%.*s/.git/info/exclude", @as(c_int, c.PATH_MAX - 21), startpath);
        if (is_file(io, &path)) {
            pign = new_ignorefile(io, startpath, &path, false);
            push_filterstack(pign);
        }
    } else {
        if (c.realpath(startpath, &path) == null) return null;
        if (c.strcmp(&path, "/") != 0 and depth < 2048) {
            // Otherwise if we haven't reached /, then keep searching upward:
            _ = c.snprintf(&path, c.PATH_MAX, "%.*s/..", @as(c_int, c.PATH_MAX - 4), startpath);
            pign = gitignore_search(io, &path, depth + 1);
        }
    }

    _ = c.snprintf(&path, c.PATH_MAX, "%.*s/.gitignore", @as(c_int, c.PATH_MAX - 12), startpath);
    if (is_file(io, &path)) {
        ign = new_ignorefile(io, startpath, &path, false);
        push_filterstack(ign);
    }

    return if (ign == null) pign else ign;
}

pub fn new_ignorefile(io: std.Io, basepath: [*c]const u8, path: [*c]const u8, checkparents: bool) ?*types.IgnoreFile {
    var buf: [c.PATH_MAX]u8 = undefined;
    var fp: ?*c.FILE = null;
    var remove_head: ?*types.Pattern = null;
    var remove_end: ?*types.Pattern = null;
    var reverse_head: ?*types.Pattern = null;
    var reverse_end: ?*types.Pattern = null;

    if (!is_file(io, path)) {
        _ = c.snprintf(&buf, c.PATH_MAX, "%s/.gitignore", path);
        fp = c.fopen(&buf, "r");

        // This probably will never actually happen anymore:
        if (fp == null and checkparents) {
            return gitignore_search(io, path, 0);
        }
    } else {
        fp = c.fopen(path, "r");
    }
    if (fp == null) return null;

    while (c.fgets(&buf, c.PATH_MAX, fp) != null) {
        if (buf[0] == '#') continue;
        const rev = buf[0] == '!';
        util.gittrim(&buf);
        if (c.strlen(&buf) == 0) continue;

        const start: [*c]u8 = &buf;
        const offset: usize = if (rev) 1 else 0;
        const p = pat.new_pattern(start + offset);
        // printf("Adding pattern: %c%s\n", rev? '!' : ' ', buf);
        if (rev) {
            if (reverse_head == null) {
                reverse_head = p;
                reverse_end = p;
            } else {
                reverse_end.?.next = p;
                reverse_end = p;
            }
        } else {
            if (remove_head == null) {
                remove_head = p;
                remove_end = p;
            } else {
                remove_end.?.next = p;
                remove_end = p;
            }
        }
    }

    _ = c.fclose(fp);

    const ig: *types.IgnoreFile = @ptrCast(@alignCast(util.xmalloc(@sizeOf(types.IgnoreFile))));
    ig.remove = remove_head;
    ig.reverse = reverse_head;
    ig.path = util.scopy(basepath);
    ig.next = null;

    return ig;
}

pub fn push_filterstack(ig: ?*types.IgnoreFile) void {
    if (ig == null) return;
    ig.?.next = filterstack;
    filterstack = ig;
}

pub fn pop_filterstack() ?*types.IgnoreFile {
    const ig = filterstack orelse return null;
    filterstack = ig.next;

    // Note: original C frees pattern->pattern (the string) but never the
    // pattern struct nodes themselves — preserved verbatim.
    var pp: ?*types.Pattern = ig.remove;
    while (pp != null) {
        const cur = pp.?;
        pp = cur.next;
        c.free(cur.pattern);
    }
    pp = ig.reverse;
    while (pp != null) {
        const cur = pp.?;
        pp = cur.next;
        c.free(cur.pattern);
    }
    c.free(ig.path);
    c.free(ig);
    return null;
}

pub fn flush_filterstack() ?*types.IgnoreFile {
    while (filterstack != null) _ = pop_filterstack();
    return null;
}

/// true if remove filter matches and no reverse filter matches.
pub fn filtercheck(path: [*c]const u8, name: [*c]const u8, isdir: c_int, ignore_case: bool) bool {
    var filter = false;
    const isdir_b = isdir != 0;

    // printf("Checking [%s / %s %d]\n", path, name, isdir);

    var ig: ?*types.IgnoreFile = filterstack;
    while (!filter and ig != null) : (ig = ig.?.next) {
        const cur_ig = ig.?;
        const fpos: usize = @intCast(c.sprintf(&xpattern, "%s/", cur_ig.path));

        var p: ?*types.Pattern = cur_ig.remove;
        while (p != null) : (p = p.?.next) {
            const cp = p.?;
            if (cp.relative != 0) {
                if (pat.match(name, cp.pattern, isdir_b, ignore_case) == 1) {
                    filter = true;
                    // printf(" --r %s %s %d\n", name, p->pattern, filter);
                    break;
                }
            } else {
                _ = c.sprintf(&xpattern[fpos], "%s", cp.pattern);
                if (pat.match(path, &xpattern, isdir_b, ignore_case) == 1) {
                    filter = true;
                    // printf(" --a %s %s %d\n", name, xpattern, filter);
                    break;
                }
            }
        }
    }
    if (!filter) return false;

    ig = filterstack;
    while (ig != null) : (ig = ig.?.next) {
        const cur_ig = ig.?;
        const fpos: usize = @intCast(c.sprintf(&xpattern, "%s/", cur_ig.path));

        var p: ?*types.Pattern = cur_ig.reverse;
        while (p != null) : (p = p.?.next) {
            const cp = p.?;
            if (cp.relative != 0) {
                if (pat.match(name, cp.pattern, isdir_b, ignore_case) == 1) return false;
            } else {
                _ = c.sprintf(&xpattern[fpos], "%s", cp.pattern);
                if (pat.match(path, &xpattern, isdir_b, ignore_case) == 1) return false;
            }
        }
    }

    return true;
}
