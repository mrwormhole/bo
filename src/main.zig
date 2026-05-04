const std = @import("std");

const man = @import("man.zig");
const tree = @import("tree.zig");

pub fn printStdout(io: std.Io, content: []const u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(content);
    try stdout.flush();
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len == 2 and (std.mem.eql(u8, args[1], "man") or std.mem.eql(u8, args[1], "--man"))) {
        try printStdout(init.io, man.content);
        return;
    }

    try tree.run(init, args);
}
