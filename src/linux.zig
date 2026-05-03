const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("tree.h");
});

const util = @import("util.zig");

/// Calls statx(AT.FDCWD, path, flags, STATX.BASIC_STATS). Only meaningful on Linux;
/// all call sites are already guarded by comptime os.tag checks.
pub fn stat(path: [*:0]const u8, flags: u32, out: *std.os.linux.Statx) bool {
    const rc = std.os.linux.statx(
        std.os.linux.AT.FDCWD,
        path,
        flags,
        std.os.linux.STATX.BASIC_STATS,
        out,
    );
    return std.os.linux.errno(rc) == .SUCCESS;
}

// glibc makedev encoding: 12-bit major + 20-bit minor packed for legacy dev_t layout.
const major_mask: u64 = 0xfff;
const minor_lo_mask: u64 = 0xff;
const minor_hi_mask: u64 = 0xffff_ff00;
const major_shift = 8;
const minor_hi_shift = 12;

pub fn devId(st: *const std.os.linux.Statx) u64 {
    const major: u64 = st.dev_major;
    const minor: u64 = st.dev_minor;
    return ((major & major_mask) << major_shift) |
        (minor & minor_lo_mask) |
        ((minor & minor_hi_mask) << minor_hi_shift);
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
