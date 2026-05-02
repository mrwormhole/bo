const std = @import("std");

const man = @import("man.zig");
const tree = @import("tree.zig");

pub fn printStdout(content: []const u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(content);
    try stdout.flush();
}

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "man")) {
        try printStdout(man.content);
        return;
    }

    try tree.run(allocator, args);
}
