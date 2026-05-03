//! XML renderer ported from xml.c.

const std = @import("std");

// <tree>
//   <directory name="name" mode=0777 size=### user="user" group="group" inode=### dev=### time="00:00 00-00-0000">
//     <link name="name" target="name" ...>
//       ... if link is followed, otherwise this is empty.
//     </link>
//     <file name="name" mode=0777 size=### user="user" group="group" inode=### dev=### time="00:00 00-00-0000"></file>
//     <socket name="" ...><error>some error</error></socket>
//     <block name="" ...></block>
//     <char name="" ...></char>
//     <fifo name="" ...></fifo>
//     <door name="" ...></door>
//     <port name="" ...></port>
//     ...
//   </directory>
//   <report>
//     <size>#</size>
//     <files>#</files>
//     <directories>#</directories>
//   </report>
// </tree>

const c = @import("cstd.zig");

const types = @import("types.zig");
const hash = @import("hash.zig");
const html = @import("html.zig");
const util = @import("util.zig");

extern var flag: types.Flags;
extern var charset: [*c]const u8;

const ifmt = @extern([*]const c.mode_t, .{ .name = "ifmt" });
const ftype = @extern([*]const [*c]const u8, .{ .name = "ftype" });

// Still in tree.zig
extern fn prot(mode: c.mode_t) [*c]u8;
extern fn do_date(t: c.time_t) [*c]u8;

fn indent(w: *std.Io.Writer, maxlevel: c_int) void {
    const spaces = [_][]const u8{ "    ", "   ", "  ", " ", "" };
    if (flag.noindent) return;

    const extra: c_int = if (flag.remove_space) 1 else 0;
    const clvl: usize = @intCast(flag.compress_indent + extra);

    w.writeAll(spaces[clvl]) catch {};
    var i: c_int = 0;
    while (i < maxlevel) : (i += 1) {
        w.writeAll(spaces[clvl]) catch {};
    }
}

fn nl() []const u8 {
    return if (flag.noindent) "" else "\n";
}

fn fillinfo(w: *std.Io.Writer, ent: *types.Info) void {
    if (flag.inode) w.print(" inode=\"{d}\"", .{ent.inode}) catch {};
    if (flag.dev) w.print(" dev=\"{d}\"", .{ent.dev}) catch {};
    if (flag.p) {
        const mask: c.mode_t = std.posix.S.IRWXU | std.posix.S.IRWXG | std.posix.S.IRWXO | std.posix.S.ISUID | std.posix.S.ISGID | std.posix.S.ISVTX;
        w.print(" mode=\"{o:0>4}\" prot=\"{s}\"", .{
            ent.mode & @as(@TypeOf(ent.mode), @intCast(mask)),
            std.mem.span(prot(@intCast(ent.mode))),
        }) catch {};
    }
    if (flag.u) w.print(" user=\"{s}\"", .{std.mem.span(hash.uidtoname(@intCast(ent.uid)))}) catch {};
    if (flag.g) w.print(" group=\"{s}\"", .{std.mem.span(hash.gidtoname(@intCast(ent.gid)))}) catch {};
    if (flag.s) w.print(" size=\"{d}\"", .{ent.size}) catch {};
    if (flag.D) w.print(" time=\"{s}\"", .{std.mem.span(do_date(@intCast(if (flag.c) ent.ctime else ent.mtime)))}) catch {};
}

pub fn intro() void {
    var buf: [256]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.writeAll("<?xml version=\"1.0\"") catch {};
    if (charset != null) fw.interface.print(" encoding=\"{s}\"", .{std.mem.span(charset)}) catch {};
    fw.interface.print("?>{s}<tree>{s}", .{ nl(), nl() }) catch {};
}

pub fn outtro() void {
    var buf: [64]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("</tree>{s}", .{nl()}) catch {};
}

pub fn printinfo(dirname: [*c]u8, file: ?*types.Info, level: c_int) c_int {
    _ = dirname;

    var buf: [256]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    if (!flag.noindent) indent(&fw.interface, level);

    const mt: c.mode_t = if (file) |f| @intCast(f.mode & @as(@TypeOf(f.mode), @intCast(std.posix.S.IFMT))) else 0;

    var t: usize = 0;
    while (ifmt[t] != 0) : (t += 1) {
        if (ifmt[t] == mt) break;
    }
    if (file) |f| f.tag = ftype[t];
    fw.interface.print("<{s}", .{std.mem.span(ftype[t])}) catch {};

    return 0;
}

pub fn printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*types.Info, descend: c_int) c_int {
    _ = dirname;
    _ = descend;

    var buf: [4096]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    fw.interface.writeAll(" name=\"") catch {};
    html.encode(&fw.interface, filename);
    fw.interface.writeByte('"') catch {};

    if (file) |f| {
        if (f.comment != null) {
            fw.interface.writeAll(" info=\"") catch {};
            var i: usize = 0;
            while (f.comment[i] != null) : (i += 1) {
                html.encode(&fw.interface, f.comment[i]);
                if (f.comment[i + 1] != null) fw.interface.writeAll(nl()) catch {};
            }
            fw.interface.writeByte('"') catch {};
        }
        if (f.lnk != null) {
            fw.interface.writeAll(" target=\"") catch {};
            html.encode(&fw.interface, f.lnk);
            fw.interface.writeByte('"') catch {};
        }
        fillinfo(&fw.interface, f);
    }
    fw.interface.writeByte('>') catch {};

    return 1;
}

pub fn printerror(err: [*c]u8) c_int {
    var buf: [512]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("<error>{s}</error>", .{std.mem.span(err)}) catch {};
    return 0;
}

pub fn newline(file: ?*types.Info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = file;
    _ = level;
    _ = needcomma;
    if (postdir >= 0) {
        var buf: [16]u8 = undefined;
        var fw = util.writer(&buf);
        defer fw.interface.flush() catch {};
        fw.interface.writeAll(nl()) catch {};
    }
}

pub fn close(file: ?*types.Info, level: c_int, needcomma: c_int) void {
    _ = needcomma;

    var buf: [256]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    if (!flag.noindent and level >= 0) indent(&fw.interface, level);

    const tag: []const u8 = if (file) |f| (if (f.tag != null) std.mem.span(f.tag) else "unknown") else "unknown";
    const trailer = nl();
    fw.interface.print("</{s}>{s}", .{ tag, trailer }) catch {};
}

pub fn report(tot: types.Totals) void {
    var buf: [512]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    indent(&fw.interface, 0);
    fw.interface.print("<report>{s}", .{nl()}) catch {};
    if (flag.du) {
        indent(&fw.interface, 1);
        fw.interface.print("<size>{d}</size>{s}", .{ tot.size, nl() }) catch {};
    }
    indent(&fw.interface, 1);
    fw.interface.print("<directories>{d}</directories>{s}", .{ tot.dirs, nl() }) catch {};
    if (!flag.d) {
        indent(&fw.interface, 1);
        fw.interface.print("<files>{d}</files>{s}", .{ tot.files, nl() }) catch {};
    }
    indent(&fw.interface, 0);
    fw.interface.print("</report>{s}", .{nl()}) catch {};
}

pub fn ListingCalls() types.ListingCalls {
    return .{
        .intro = &intro,
        .outtro = &outtro,
        .printinfo = &printinfo,
        .printfile = &printfile,
        .@"error" = &printerror,
        .newline = &newline,
        .close = &close,
        .report = &report,
    };
}
