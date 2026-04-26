const std = @import("std");

const man = @import("man.zig");
const strverscmp = @import("strverscmp.zig");
const hash = @import("hash.zig");
const util = @import("util.zig");

const tree = @import("tree.zig");

pub fn printStdout(content: []const u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(content);
    try stdout.flush();
}

pub fn main() !u8 {
    const allocator = std.heap.c_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "man")) {
        try printStdout(man.content);
        return 0;
    }

    // Otherwise call C, must convert [:0]const u8 slice to [*:0]u8 for C
    var c_args = try allocator.alloc([*:0]u8, args.len);
    defer allocator.free(c_args);

    for (args, 0..) |arg, i| {
        c_args[i] = arg.ptr;
    }

    const result = tree.run(allocator, @intCast(args.len), @ptrCast(c_args.ptr));
    return if (result >= 0) @intCast(result) else 1;
}
