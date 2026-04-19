//! .gitignore-style filtering ported from filter.c.

const std = @import("std");

const c = @cImport({
    @cInclude("tree.h");
});

extern var xpattern: [c.PATH_MAX]u8;

var filterstack: ?*c.struct_ignorefile = null;

fn scopy(s: [*c]const u8) [*c]u8 {
    const len = c.strlen(s);
    const dst: [*c]u8 = @ptrCast(c.xmalloc(len + 1));
    return c.strcpy(dst, s);
}

fn is_file(path: [*c]const u8) bool {
    var st: c.struct_stat = undefined;
    if (c.stat(path, &st) < 0) return false;
    return (st.st_mode & c.S_IFMT) == c.S_IFREG;
}

fn is_dir(path: [*c]const u8) bool {
    var st: c.struct_stat = undefined;
    if (c.stat(path, &st) < 0) return false;
    return (st.st_mode & c.S_IFMT) == c.S_IFDIR;
}

export fn gittrim(s: [*c]u8) void {
    var e: isize = @as(isize, @intCast(c.strlen(s))) - 1;
    if (e < 0) return;
    while (e > 0 and (s[@intCast(e)] == '\n' or s[@intCast(e)] == '\r')) e -= 1;

    var i: isize = e;
    while (i >= 0) : (i -= 1) {
        if (s[@intCast(i)] != ' ') break;
        if (i != 0 and s[@intCast(i - 1)] != '\\') e -= 1;
    }
    s[@intCast(e + 1)] = 0;

    var ri: usize = 0;
    var re: usize = 0;
    while (s[ri] != 0) {
        if (s[ri] == '\\') ri += 1;
        s[re] = s[ri];
        re += 1;
        ri += 1;
    }
    s[re] = 0;
}

export fn new_pattern(pattern: [*c]u8) *c.struct_pattern {
    const p: *c.struct_pattern = @ptrCast(@alignCast(c.xmalloc(@sizeOf(c.struct_pattern))));
    const offset: usize = if (pattern[0] == '/') 1 else 0;
    p.pattern = scopy(pattern + offset);
    const sl = c.strchr(pattern, '/');
    p.relative = @intFromBool(sl == null or sl[1] == 0);
    p.next = null;
    return p;
}

/// Search up the directory tree for .gitignore files, stopping at a directory
/// that contains a .git directory, or at /, whichever occurs first. The depth
/// parameter is just a sanity check to insure we can't get into a loop somehow,
/// even though that should be impossible.
export fn gitignore_search(startpath: [*c]const u8, depth: c_int) ?*c.struct_ignorefile {
    var pign: ?*c.struct_ignorefile = null;
    var ign: ?*c.struct_ignorefile = null;
    var path: [c.PATH_MAX + 1]u8 = undefined;

    // strcpy(rpath, startpath);

    // Stop when we hit a directory with a .git directory. we'll assume it's the
    // git root:
    _ = c.snprintf(&path, c.PATH_MAX, "%.*s/.git", @as(c_int, c.PATH_MAX - 6), startpath);
    if (is_dir(&path)) {
        // Add it's .git/config/exclude
        _ = c.snprintf(&path, c.PATH_MAX, "%.*s/.git/info/exclude", @as(c_int, c.PATH_MAX - 21), startpath);
        if (is_file(&path)) {
            pign = new_ignorefile(startpath, &path, false);
            push_filterstack(pign);
        }
    } else {
        if (c.realpath(startpath, &path) == null) return null;
        if (c.strcmp(&path, "/") != 0 and depth < 2048) {
            // Otherwise if we haven't reached /, then keep searching upward:
            _ = c.snprintf(&path, c.PATH_MAX, "%.*s/..", @as(c_int, c.PATH_MAX - 4), startpath);
            pign = gitignore_search(&path, depth + 1);
        }
    }

    _ = c.snprintf(&path, c.PATH_MAX, "%.*s/.gitignore", @as(c_int, c.PATH_MAX - 12), startpath);
    if (is_file(&path)) {
        ign = new_ignorefile(startpath, &path, false);
        push_filterstack(ign);
    }

    return if (ign == null) pign else ign;
}

export fn new_ignorefile(basepath: [*c]const u8, path: [*c]const u8, checkparents: bool) ?*c.struct_ignorefile {
    var buf: [c.PATH_MAX]u8 = undefined;
    var fp: ?*c.FILE = null;
    var remove_head: ?*c.struct_pattern = null;
    var remove_end: ?*c.struct_pattern = null;
    var reverse_head: ?*c.struct_pattern = null;
    var reverse_end: ?*c.struct_pattern = null;

    if (!is_file(path)) {
        _ = c.snprintf(&buf, c.PATH_MAX, "%s/.gitignore", path);
        fp = c.fopen(&buf, "r");

        // This probably will never actually happen anymore:
        if (fp == null and checkparents) {
            return gitignore_search(path, 0);
        }
    } else {
        fp = c.fopen(path, "r");
    }
    if (fp == null) return null;

    while (c.fgets(&buf, c.PATH_MAX, fp) != null) {
        if (buf[0] == '#') continue;
        const rev = buf[0] == '!';
        gittrim(&buf);
        if (c.strlen(&buf) == 0) continue;

        const start: [*c]u8 = &buf;
        const offset: usize = if (rev) 1 else 0;
        const p = new_pattern(start + offset);
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

    const ig: *c.struct_ignorefile = @ptrCast(@alignCast(c.xmalloc(@sizeOf(c.struct_ignorefile))));
    ig.remove = remove_head;
    ig.reverse = reverse_head;
    ig.path = scopy(basepath);
    ig.next = null;

    return ig;
}

export fn push_filterstack(ig: ?*c.struct_ignorefile) void {
    if (ig == null) return;
    ig.?.next = filterstack;
    filterstack = ig;
}

export fn pop_filterstack() ?*c.struct_ignorefile {
    const ig = filterstack orelse return null;
    filterstack = ig.next;

    // Note: original C frees pattern->pattern (the string) but never the
    // pattern struct nodes themselves — preserved verbatim.
    var pp: ?*c.struct_pattern = ig.remove;
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

export fn flush_filterstack() ?*c.struct_ignorefile {
    while (filterstack != null) _ = pop_filterstack();
    return null;
}

/// true if remove filter matches and no reverse filter matches.
export fn filtercheck(path: [*c]const u8, name: [*c]const u8, isdir: c_int) bool {
    var filter = false;
    const isdir_b = isdir != 0;

    // printf("Checking [%s / %s %d]\n", path, name, isdir);

    var ig: ?*c.struct_ignorefile = filterstack;
    while (!filter and ig != null) : (ig = ig.?.next) {
        const cur_ig = ig.?;
        const fpos: usize = @intCast(c.sprintf(&xpattern, "%s/", cur_ig.path));

        var p: ?*c.struct_pattern = cur_ig.remove;
        while (p != null) : (p = p.?.next) {
            const cp = p.?;
            if (cp.relative != 0) {
                if (c.patmatch(name, cp.pattern, isdir_b) == 1) {
                    filter = true;
                    // printf(" --r %s %s %d\n", name, p->pattern, filter);
                    break;
                }
            } else {
                _ = c.sprintf(&xpattern[fpos], "%s", cp.pattern);
                if (c.patmatch(path, &xpattern, isdir_b) == 1) {
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

        var p: ?*c.struct_pattern = cur_ig.reverse;
        while (p != null) : (p = p.?.next) {
            const cp = p.?;
            if (cp.relative != 0) {
                if (c.patmatch(name, cp.pattern, isdir_b) == 1) return false;
            } else {
                _ = c.sprintf(&xpattern[fpos], "%s", cp.pattern);
                if (c.patmatch(path, &xpattern, isdir_b) == 1) return false;
            }
        }
    }

    return true;
}
