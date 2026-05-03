const std = @import("std");
const builtin = @import("builtin");

const c = @import("cstd.zig");

const util = @import("util.zig");

pub const ENV_STDDATA_FD: [*:0]const u8 = "STDDATA_FD";
pub const STDDATA_FILENO: c_int = 3;

const xattr = if (builtin.os.tag == .linux) struct {
    extern "c" fn listxattr(path: [*c]const u8, list: [*c]u8, size: usize) isize;
    extern "c" fn getxattr(path: [*c]const u8, name: [*c]const u8, value: [*c]u8, size: usize) isize;
} else 0;

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

// glibc makedev encoding: 32-bit major + 32-bit minor packed into a 64-bit dev_t.
const major_lo_mask: u64 = 0xfff;
const major_hi_mask: u64 = 0xffff_f000;
const minor_lo_mask: u64 = 0xff;
const minor_hi_mask: u64 = 0xffff_ff00;
const major_lo_shift = 8;
const major_hi_shift = 32;
const minor_hi_shift = 12;

pub fn devId(st: *const std.os.linux.Statx) u64 {
    const major: u64 = st.dev_major;
    const minor: u64 = st.dev_minor;
    return (minor & minor_lo_mask) |
        ((major & major_lo_mask) << major_lo_shift) |
        ((minor & minor_hi_mask) << minor_hi_shift) |
        ((major & major_hi_mask) << major_hi_shift);
}

pub fn has_acl(path: [*c]const u8) bool {
    if (comptime builtin.os.tag != .linux) return false;
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n: isize = xattr.listxattr(path, &buf, std.fs.max_path_bytes);
    if (n <= 0) return false;

    var key: [*c]u8 = &buf;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) {
        const len = c.strLen(key);
        if (std.mem.eql(u8, c.strSpan(key), "system.posix_acl_access")) return true;
        i += len + 1;
        key += len + 1;
    }
    return false;
}

pub fn selinux_context(path: [*c]const u8) [*c]u8 {
    if (comptime builtin.os.tag != .linux) return null;
    var buf: [std.fs.max_path_bytes]u8 = undefined;

    const len: isize = xattr.getxattr(path, "security.selinux", &buf, std.fs.max_path_bytes - 1);
    buf[@intCast(if (len < 0) 0 else len)] = 0;
    return util.copy(&buf);
}
