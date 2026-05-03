//! Pattern matching functions ported from tree.c.

const std = @import("std");

const c = @import("cstd.zig");

const types = @import("types.zig");
const util = @import("util.zig");

fn lower(ch: u8, ignore_case: bool) u8 {
    return if (ignore_case) @intCast(c.tolower(ch)) else ch;
}

pub fn new_pattern(pattern: [*c]u8) *types.Pattern {
    const p: *types.Pattern = @ptrCast(@alignCast(util.xmalloc(@sizeOf(types.Pattern))));
    const offset: usize = if (pattern[0] == std.fs.path.sep) 1 else 0;
    p.pattern = util.copy(pattern + offset);
    const sl = std.mem.findScalar(u8, c.strSpan(pattern), std.fs.path.sep);
    p.relative = @intFromBool(sl == null or pattern[sl.? + 1] == 0);
    p.next = null;
    return p;
}

// Patmatch() code courtesy of Thomas Moore (dark@mama.indstate.edu)
// '|' support added by David MacMahon (davidm@astron.Berkeley.EDU)
// Case insensitive support added by Jason A. Donenfeld (Jason@zx2c4.com)
// returns:
//    1 on a match
//    0 on a mismatch
//   -1 on a syntax error in the pattern
pub fn match(buf_in: [*c]const u8, pat_in: [*c]u8, isdir: bool, ignore_case: bool) c_int {
    var m: c_int = 1;
    var pprev: u8 = 0;
    var buf = buf_in;
    var pat = pat_in;

    const bar: [*c]u8 = if (std.mem.findScalar(u8, c.strSpan(pat), '|')) |idx| pat + idx else null;

    if (bar != null) {
        if (bar == pat or bar[1] == 0) return -1;
        bar[0] = 0;
        m = match(buf, pat, isdir, ignore_case);
        if (m == 0) m = match(buf, bar + 1, isdir, ignore_case);
        bar[0] = '|';
        return m;
    }

    while (pat[0] != 0 and m != 0) {
        switch (pat[0]) {
            '[' => {
                pat += 1;
                var n: c_int = undefined;
                if (pat[0] != '^') {
                    n = 1;
                    m = 0;
                } else {
                    pat += 1;
                    n = 0;
                }
                while (pat[0] != ']') {
                    if (pat[0] == '\\') pat += 1;
                    if (pat[0] == 0) return -1; // || *pat == '/'
                    if (pat[1] == '-') {
                        const lo: u8 = pat[0];
                        pat += 2;
                        if (pat[0] == '\\' and pat[0] != 0) pat += 1;
                        if (lower(buf[0], ignore_case) >= lower(lo, ignore_case) and
                            lower(buf[0], ignore_case) <= lower(pat[0], ignore_case)) m = n;
                        if (pat[0] == 0) pat -= 1;
                    } else if (lower(buf[0], ignore_case) == lower(pat[0], ignore_case)) {
                        m = n;
                    }
                    pat += 1;
                }
                buf += 1;
            },
            '*' => {
                pat += 1;
                if (pat[0] == 0) {
                    return @intFromBool(std.mem.findScalar(u8, c.strSpan(buf), std.fs.path.sep) == null);
                }
                m = 0;
                if (pat[0] == '*') {
                    pat += 1;
                    if (pat[0] == 0) return 1;
                    while (buf[0] != 0) {
                        m = match(buf, pat, isdir, ignore_case);
                        if (m != 0) break;
                        // ** between two /'s is allowed to match a null /:
                        if (pprev == std.fs.path.sep and pat[0] == std.fs.path.sep and pat[1] != 0) {
                            m = match(buf, pat + 1, isdir, ignore_case);
                            if (m != 0) return m;
                        }
                        buf += 1;
                        while (buf[0] != 0 and buf[0] != std.fs.path.sep) : (buf += 1) {}
                    }
                } else {
                    while (buf[0] != 0) {
                        const old = buf;
                        buf += 1;
                        m = match(old, pat, isdir, ignore_case);
                        if (m != 0) break;
                        if (buf[0] == std.fs.path.sep) break;
                    }
                }
                if (m == 0 and (buf[0] == 0 or buf[0] == std.fs.path.sep)) m = match(buf, pat, isdir, ignore_case);
                return m;
            },
            '?' => {
                if (buf[0] == 0) return 0;
                buf += 1;
            },
            std.fs.path.sep => {
                if (pat[1] == 0 and buf[0] == 0) return @intFromBool(isdir);
                m = @intFromBool(buf[0] == pat[0]);
                buf += 1;
            },
            '\\' => {
                if (pat[0] != 0) pat += 1;
                // Falls through
                m = @intFromBool(lower(buf[0], ignore_case) == lower(pat[0], ignore_case));
                buf += 1;
            },
            else => {
                m = @intFromBool(lower(buf[0], ignore_case) == lower(pat[0], ignore_case));
                buf += 1;
            },
        }
        pprev = pat[0];
        pat += 1;
        if (m < 1) return m;
    }
    if (buf[0] == 0) return m;
    return 0;
}

// True if file matches an -I pattern
pub fn ignore(name: [*c]const u8, ipatterns: []const [*c]u8, isdir: bool, checkpaths: bool, ignore_case: bool, path_sep: u8) c_int {
    for (ipatterns) |p| {
        if (match(name, p, isdir, ignore_case) != 0) return 1;
        if (checkpaths) {
            var pc: [*c]const u8 = if (std.mem.findScalar(u8, c.strSpan(name), path_sep)) |idx| name + idx else null;
            while (pc != null and pc[0] != 0) {
                if (match(pc + 1, p, isdir, ignore_case) != 0) return 1;
                pc = if (std.mem.findScalar(u8, c.strSpan(pc + 1), path_sep)) |idx| pc + 1 + idx else null;
            }
        }
    }
    return 0;
}

// True if name matches a -P pattern
pub fn include(name: [*c]const u8, patterns: []const [*c]u8, isdir: bool, checkpaths: bool, ignore_case: bool, path_sep: u8) c_int {
    for (patterns) |p| {
        if (match(name, p, isdir, ignore_case) != 0) return 1;
        if (checkpaths) {
            var pc: [*c]const u8 = if (std.mem.findScalar(u8, c.strSpan(name), path_sep)) |idx| name + idx else null;
            while (pc != null and pc[0] != 0) {
                if (match(pc + 1, p, isdir, ignore_case) != 0) return 1;
                pc = if (std.mem.findScalar(u8, c.strSpan(pc + 1), path_sep)) |idx| pc + 1 + idx else null;
            }
        }
    }
    return 0;
}
