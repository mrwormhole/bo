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

const c = @cImport({
    @cInclude("tree.h");
});

const types = @import("types.zig");

extern var flag: types.Flags;
extern var outfile: *std.fs.File;
extern var _nl: [*c]const u8;
extern var charset: [*c]const u8;

const ifmt = @extern([*]const c.mode_t, .{ .name = "ifmt" });
const ftype = @extern([*]const [*c]const u8, .{ .name = "ftype" });

// Already ported in hash.zig — link against the exported C symbols.
extern fn uidtoname(uid: c.uid_t) [*c]const u8;
extern fn gidtoname(gid: c.gid_t) [*c]const u8;

// Still in tree.zig
extern fn prot(mode: c.mode_t) [*c]u8;
extern fn do_date(t: c.time_t) [*c]u8;

// XML reuses the HTML encoder for attribute escaping (&, <, >, ").
extern fn html_encode(w: *std.Io.Writer, s: [*c]u8) void;

fn xml_indent(w: *std.Io.Writer, maxlevel: c_int) void {
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

fn xml_fillinfo(w: *std.Io.Writer, ent: *types.Info) void {
    if (flag.inode) w.print(" inode=\"{d}\"", .{ent.inode}) catch {};
    if (flag.dev) w.print(" dev=\"{d}\"", .{ent.dev}) catch {};
    if (flag.p) {
        const mask: c.mode_t = c.S_IRWXU | c.S_IRWXG | c.S_IRWXO | c.S_ISUID | c.S_ISGID | c.S_ISVTX;
        w.print(" mode=\"{o:0>4}\" prot=\"{s}\"", .{
            ent.mode & @as(@TypeOf(ent.mode), @intCast(mask)),
            std.mem.span(prot(@intCast(ent.mode))),
        }) catch {};
    }
    if (flag.u) w.print(" user=\"{s}\"", .{std.mem.span(uidtoname(@intCast(ent.uid)))}) catch {};
    if (flag.g) w.print(" group=\"{s}\"", .{std.mem.span(gidtoname(@intCast(ent.gid)))}) catch {};
    if (flag.s) w.print(" size=\"{d}\"", .{ent.size}) catch {};
    if (flag.D) w.print(" time=\"{s}\"", .{std.mem.span(do_date(@intCast(if (flag.c) ent.ctime else ent.mtime)))}) catch {};
}

export fn xml_intro() void {
    var buf: [256]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.writeAll("<?xml version=\"1.0\"") catch {};
    if (charset != null) fw.interface.print(" encoding=\"{s}\"", .{std.mem.span(charset)}) catch {};
    fw.interface.print("?>{s}<tree>{s}", .{ std.mem.span(_nl), std.mem.span(_nl) }) catch {};
}

export fn xml_outtro() void {
    var buf: [64]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("</tree>{s}", .{std.mem.span(_nl)}) catch {};
}

export fn xml_printinfo(dirname: [*c]u8, file: ?*types.Info, level: c_int) c_int {
    _ = dirname;

    var buf: [256]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};

    if (!flag.noindent) xml_indent(&fw.interface, level);

    const mt: c.mode_t = if (file) |f| @intCast(f.mode & @as(@TypeOf(f.mode), @intCast(c.S_IFMT))) else 0;

    var t: usize = 0;
    while (ifmt[t] != 0) : (t += 1) {
        if (ifmt[t] == mt) break;
    }
    if (file) |f| f.tag = ftype[t];
    fw.interface.print("<{s}", .{std.mem.span(ftype[t])}) catch {};

    return 0;
}

export fn xml_printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*types.Info, descend: c_int) c_int {
    _ = dirname;
    _ = descend;

    var buf: [4096]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};

    fw.interface.writeAll(" name=\"") catch {};
    html_encode(&fw.interface, filename);
    fw.interface.writeByte('"') catch {};

    if (file) |f| {
        if (f.comment != null) {
            fw.interface.writeAll(" info=\"") catch {};
            var i: usize = 0;
            while (f.comment[i] != null) : (i += 1) {
                html_encode(&fw.interface, f.comment[i]);
                if (f.comment[i + 1] != null) fw.interface.writeAll(std.mem.span(_nl)) catch {};
            }
            fw.interface.writeByte('"') catch {};
        }
        if (f.lnk != null) {
            fw.interface.writeAll(" target=\"") catch {};
            html_encode(&fw.interface, f.lnk);
            fw.interface.writeByte('"') catch {};
        }
        xml_fillinfo(&fw.interface, f);
    }
    fw.interface.writeByte('>') catch {};

    return 1;
}

export fn xml_error(err: [*c]u8) c_int {
    var buf: [512]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("<error>{s}</error>", .{std.mem.span(err)}) catch {};
    return 0;
}

export fn xml_newline(file: ?*types.Info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = file;
    _ = level;
    _ = needcomma;
    if (postdir >= 0) {
        var buf: [16]u8 = undefined;
        var fw = outfile.writer(&buf);
        defer fw.interface.flush() catch {};
        fw.interface.writeAll(std.mem.span(_nl)) catch {};
    }
}

export fn xml_close(file: ?*types.Info, level: c_int, needcomma: c_int) void {
    _ = needcomma;

    var buf: [256]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};

    if (!flag.noindent and level >= 0) xml_indent(&fw.interface, level);

    const tag: []const u8 = if (file) |f| std.mem.span(f.tag) else "unknown";
    const trailer: []const u8 = if (flag.noindent) "" else std.mem.span(_nl);
    fw.interface.print("</{s}>{s}", .{ tag, trailer }) catch {};
}

export fn xml_report(tot: types.Totals) void {
    var buf: [512]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    const nl = std.mem.span(_nl);

    xml_indent(&fw.interface, 0);
    fw.interface.print("<report>{s}", .{nl}) catch {};
    if (flag.du) {
        xml_indent(&fw.interface, 1);
        fw.interface.print("<size>{d}</size>{s}", .{ tot.size, nl }) catch {};
    }
    xml_indent(&fw.interface, 1);
    fw.interface.print("<directories>{d}</directories>{s}", .{ tot.dirs, nl }) catch {};
    if (!flag.d) {
        xml_indent(&fw.interface, 1);
        fw.interface.print("<files>{d}</files>{s}", .{ tot.files, nl }) catch {};
    }
    xml_indent(&fw.interface, 0);
    fw.interface.print("</report>{s}", .{nl}) catch {};
}
