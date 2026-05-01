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

const c = @cImport({
    @cInclude("tree.h");
});

const types = @import("types.zig");

extern var flag: types.Flags;
extern var outfile: *std.fs.File;
extern var _nl: [*c]const u8;

const ifmt = @extern([*]const c.mode_t, .{ .name = "ifmt" });
const ftype = @extern([*]const [*c]const u8, .{ .name = "ftype" });

// Already ported in hash.zig — link against the exported C symbols.
extern fn uidtoname(uid: c.uid_t) [*c]const u8;
extern fn gidtoname(gid: c.gid_t) [*c]const u8;

// Still in tree.zig
extern fn prot(mode: c.mode_t) [*c]u8;
extern fn psize(buf: [*c]u8, size: c.off_t) c_int;
extern fn do_date(t: c.time_t) [*c]u8;

// RFC 8259 escape map: index 0..31 → '-' means \uXXXX, otherwise the letter after '\'.
const ctrl_map: *const [32]u8 = "0-------btn-fr------------------";

fn jsonEncode(w: *std.Io.Writer, s_in: [*c]const u8) void { // FIXME: Still not UTF-8
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

fn json_indent(w: *std.Io.Writer, maxlevel: c_int) void {
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

fn json_fillinfo(w: *std.Io.Writer, ent: *types.Info) void {
    if (flag.inode) w.print(",\"inode\":{d}", .{ent.inode}) catch {};
    if (flag.dev) w.print(",\"dev\":{d}", .{ent.dev}) catch {};
    if (flag.p) {
        const mask: c.mode_t = c.S_IRWXU | c.S_IRWXG | c.S_IRWXO | c.S_ISUID | c.S_ISGID | c.S_ISVTX;
        w.print(",\"mode\":\"{o:0>4}\",\"prot\":\"{s}\"", .{
            ent.mode & @as(@TypeOf(ent.mode), @intCast(mask)),
            std.mem.span(prot(@intCast(ent.mode))),
        }) catch {};
    }
    if (flag.u) w.print(",\"user\":\"{s}\"", .{std.mem.span(uidtoname(@intCast(ent.uid)))}) catch {};
    if (flag.g) w.print(",\"group\":\"{s}\"", .{std.mem.span(gidtoname(@intCast(ent.gid)))}) catch {};
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

export fn json_intro() void {
    var buf: [64]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    const nl: []const u8 = if (flag.noindent) "" else std.mem.span(_nl);
    fw.interface.print("[{s}", .{nl}) catch {};
}

export fn json_outtro() void {
    var buf: [64]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    const nl: []const u8 = if (flag.noindent) "" else std.mem.span(_nl);
    fw.interface.print("{s}]\n", .{nl}) catch {};
}

export fn json_printinfo(dirname: [*c]u8, file: ?*types.Info, level: c_int) c_int {
    _ = dirname;

    var buf: [256]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};

    if (!flag.noindent) json_indent(&fw.interface, level);

    const mt: c.mode_t = if (file) |f| @intCast(f.mode & @as(@TypeOf(f.mode), @intCast(c.S_IFMT))) else 0;

    var t: usize = 0;
    while (ifmt[t] != 0) : (t += 1) {
        if (ifmt[t] == mt) break;
    }
    fw.interface.print("{{\"type\":\"{s}\"", .{std.mem.span(ftype[t])}) catch {};

    return 0;
}

export fn json_printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*types.Info, descend: c_int) c_int {
    _ = dirname;

    var buf: [4096]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    var direrr = false;

    fw.interface.writeAll(",\"name\":\"") catch {};
    jsonEncode(&fw.interface, filename);
    fw.interface.writeByte('"') catch {};

    if (file) |f| {
        if (f.comment != null) {
            fw.interface.writeAll(",\"info\":\"") catch {};
            var i: usize = 0;
            while (f.comment[i] != null) : (i += 1) {
                jsonEncode(&fw.interface, f.comment[i]);
                if (f.comment[i + 1] != null) fw.interface.writeAll("\\n") catch {};
            }
            fw.interface.writeByte('"') catch {};
        }

        if (f.lnk != null) {
            fw.interface.writeAll(",\"target\":\"") catch {};
            jsonEncode(&fw.interface, f.lnk);
            fw.interface.writeByte('"') catch {};
        }
        json_fillinfo(&fw.interface, f);
        direrr = f.isdir and f.err != null;
    }

    if (descend != 0 or direrr) {
        fw.interface.writeAll(",\"contents\":[") catch {};
    } else {
        fw.interface.writeByte('}') catch {};
    }

    return if (descend != 0 or direrr) 1 else 0;
}

export fn json_error(err: [*c]u8) c_int {
    var buf: [512]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("{{\"error\": \"{s}\"}}", .{std.mem.span(err)}) catch {};
    return 0;
}

export fn json_newline(file: ?*types.Info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = file;
    _ = level;
    _ = postdir;
    var buf: [64]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    const comma: []const u8 = if (needcomma != 0) "," else "";
    fw.interface.print("{s}{s}", .{ comma, std.mem.span(_nl) }) catch {};
}

export fn json_close(file: ?*types.Info, level: c_int, needcomma: c_int) void {
    _ = file;

    var buf: [256]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};

    if (!flag.noindent) json_indent(&fw.interface, level);
    const comma: []const u8 = if (needcomma != 0) "," else "";
    const nl: []const u8 = if (flag.noindent) "" else "\n";
    fw.interface.print("]}}{s}{s}", .{ comma, nl }) catch {};
}

export fn json_report(tot: types.Totals) void {
    var buf: [256]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};

    fw.interface.writeByte(',') catch {};
    json_indent(&fw.interface, 0);
    fw.interface.writeAll("{\"type\":\"report\"") catch {};
    if (flag.du) fw.interface.print(",\"size\":{d}", .{tot.size}) catch {};
    fw.interface.print(",\"directories\":{d}", .{tot.dirs}) catch {};
    if (!flag.d) fw.interface.print(",\"files\":{d}", .{tot.files}) catch {};
    fw.interface.writeByte('}') catch {};
}
