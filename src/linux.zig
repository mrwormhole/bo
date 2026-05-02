const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("tree.h");
});

const util = @import("util.zig");

/// Calls fstatat(AT.FDCWD, path, out, flags). Only meaningful on Linux;
/// all call sites are already guarded by comptime os.tag checks.
pub fn stat(path: [*:0]const u8, flags: u32, out: *std.os.linux.Stat) bool {
    const rc = std.os.linux.fstatat(std.os.linux.AT.FDCWD, path, out, flags);
    return std.os.linux.E.init(rc) == .SUCCESS;
}

pub fn has_acl(path: [*c]const u8) bool {
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

pub fn selinux_context(path: [*c]const u8) [*c]u8 {
    if (comptime builtin.os.tag != .linux) return null;
    var buf: [c.PATH_MAX]u8 = undefined;

    const len: isize = c.getxattr(path, "security.selinux", &buf, c.PATH_MAX - 1);
    buf[@intCast(if (len < 0) 0 else len)] = 0;
    return util.scopy(&buf);
}
