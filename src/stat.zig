const std = @import("std");

/// Calls fstatat(AT.FDCWD, path, out, flags). Only meaningful on Linux;
/// all call sites are already guarded by comptime os.tag checks.
pub fn linuxStat(path: [*:0]const u8, flags: u32, out: *std.os.linux.Stat) bool {
    const rc = std.os.linux.fstatat(std.os.linux.AT.FDCWD, path, out, flags);
    return std.os.linux.E.init(rc) == .SUCCESS;
}
