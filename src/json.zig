//! JSON renderer ported from json.c.

const std = @import("std");

// [
//   {"type": "directory", "name": "name", "mode": "0777", "user": "user", "group": "group", "inode": ###, "dev": ####, "time": "00:00 00-00-0000", "info": "<file comment>", "contents": [
//     {"type": "link", "name": "name", "target": "name", "info": "...", "contents": [... if link is followed, otherwise this is empty.]}
//     {"type": "file", "name": "name", "mode": "0777", "size": ###, "group": "group", "inode": ###, "dev": ###, "time": "00:00 00-00-0000", "info": "..."}
//     {"type": "socket", "name": "", "info": "...", "error": "some error" ...}
//     {"type": "block", "name": "" ...},
//     {"type": "char", "name": "" ...},
//     {"type": "fifo", "name": "" ...},
//     {"type": "door", "name": "" ...},
//     {"type": "port", "name": "" ...}
//   ]},
//   {"type": "report", "size": ###, "files": ###, "directories": ###}
// ]

const c = @import("cstd.zig");

const types = @import("types.zig");
const hash = @import("hash.zig");
const util = @import("util.zig");

extern var flag: types.Flags;

const ifmt = @extern([*]const c.mode_t, .{ .name = "ifmt" });
const ftype = @extern([*]const [*c]const u8, .{ .name = "ftype" });

// Still in tree.zig
extern fn prot(mode: c.mode_t) [*c]u8;
extern fn psize(buf: [*c]u8, size: c.off_t) c_int;
extern fn do_date(t: c.time_t) [*c]u8;

// RFC 8259 escape map: index 0..31 → '-' means \uXXXX, otherwise the letter after '\'.
const ctrl_map: *const [32]u8 = "0-------btn-fr------------------";

fn encode(w: *std.Io.Writer, s_in: [*c]const u8) void { // FIXME: Still not UTF-8
    var s = s_in;
    while (s[0] != 0) : (s += 1) {
        const ch: u8 = s[0];
        if (ch < 32) {
            if (ctrl_map[ch] != '-') {
                w.print("\\{c}", .{ctrl_map[ch]}) catch {};
            } else {
                w.print("\\u{x:0>4}", .{ch}) catch {};
            }
        } else if (ch == '"' or ch == '\\') {
            w.print("\\{c}", .{ch}) catch {};
        } else {
            w.writeByte(ch) catch {};
        }
    }
}

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
    if (flag.inode) w.print(",\"inode\":{d}", .{ent.inode}) catch {};
    if (flag.dev) w.print(",\"dev\":{d}", .{ent.dev}) catch {};
    if (flag.p) {
        const mask: c.mode_t = std.posix.S.IRWXU | std.posix.S.IRWXG | std.posix.S.IRWXO | std.posix.S.ISUID | std.posix.S.ISGID | std.posix.S.ISVTX;
        w.print(",\"mode\":\"{o:0>4}\",\"prot\":\"{s}\"", .{
            ent.mode & @as(@TypeOf(ent.mode), @intCast(mask)),
            std.mem.span(prot(@intCast(ent.mode))),
        }) catch {};
    }
    if (flag.u) w.print(",\"user\":\"{s}\"", .{std.mem.span(hash.uidtoname(@intCast(ent.uid)))}) catch {};
    if (flag.g) w.print(",\"group\":\"{s}\"", .{std.mem.span(hash.gidtoname(@intCast(ent.gid)))}) catch {};
    if (flag.s) {
        if (flag.h or flag.si) {
            var nbuf: [64]u8 = undefined;
            _ = psize(&nbuf, @intCast(ent.size));
            var i: usize = 0;
            while (c.isspace(@as(c_int, nbuf[i])) != 0) : (i += 1) {}
            w.print(",\"size\":\"{s}\"", .{std.mem.sliceTo(nbuf[i..], 0)}) catch {};
        } else {
            w.print(",\"size\":{d}", .{ent.size}) catch {};
        }
    }
    if (flag.D) w.print(",\"time\":\"{s}\"", .{std.mem.span(do_date(@intCast(if (flag.c) ent.ctime else ent.mtime)))}) catch {};
}

pub fn intro() void {
    var buf: [64]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("[{s}", .{nl()}) catch {};
}

pub fn outtro() void {
    var buf: [64]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("{s}]\n", .{nl()}) catch {};
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
    fw.interface.print("{{\"type\":\"{s}\"", .{std.mem.span(ftype[t])}) catch {};

    return 0;
}

pub fn printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*types.Info, descend: c_int) c_int {
    _ = dirname;

    var buf: [4096]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    var direrr = false;

    fw.interface.writeAll(",\"name\":\"") catch {};
    encode(&fw.interface, filename);
    fw.interface.writeByte('"') catch {};

    if (file) |f| {
        if (f.comment != null) {
            fw.interface.writeAll(",\"info\":\"") catch {};
            var i: usize = 0;
            while (f.comment[i] != null) : (i += 1) {
                encode(&fw.interface, f.comment[i]);
                if (f.comment[i + 1] != null) fw.interface.writeAll("\\n") catch {};
            }
            fw.interface.writeByte('"') catch {};
        }

        if (f.lnk != null) {
            fw.interface.writeAll(",\"target\":\"") catch {};
            encode(&fw.interface, f.lnk);
            fw.interface.writeByte('"') catch {};
        }
        fillinfo(&fw.interface, f);
        direrr = f.isdir and f.err != null;
    }

    if (descend != 0 or direrr) {
        fw.interface.writeAll(",\"contents\":[") catch {};
    } else {
        fw.interface.writeByte('}') catch {};
    }

    return if (descend != 0 or direrr) 1 else 0;
}

pub fn printerror(err: [*c]u8) c_int {
    var buf: [512]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("{{\"error\": \"{s}\"}}", .{std.mem.span(err)}) catch {};
    return 0;
}

pub fn newline(file: ?*types.Info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = file;
    _ = level;
    _ = postdir;
    var buf: [64]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    const comma: []const u8 = if (needcomma != 0) "," else "";
    fw.interface.print("{s}{s}", .{ comma, nl() }) catch {};
}

pub fn close(file: ?*types.Info, level: c_int, needcomma: c_int) void {
    _ = file;

    var buf: [256]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    if (!flag.noindent) indent(&fw.interface, level);
    const comma: []const u8 = if (needcomma != 0) "," else "";
    fw.interface.print("]}}{s}{s}", .{ comma, nl() }) catch {};
}

pub fn report(tot: types.Totals) void {
    var buf: [256]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    fw.interface.writeByte(',') catch {};
    indent(&fw.interface, 0);
    fw.interface.writeAll("{\"type\":\"report\"") catch {};
    if (flag.du) fw.interface.print(",\"size\":{d}", .{tot.size}) catch {};
    fw.interface.print(",\"directories\":{d}", .{tot.dirs}) catch {};
    if (!flag.d) fw.interface.print(",\"files\":{d}", .{tot.files}) catch {};
    fw.interface.writeByte('}') catch {};
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
