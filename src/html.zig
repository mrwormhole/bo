//! HTML renderer ported from html.c.

const std = @import("std");

const c = @import("cstd.zig");

const types = @import("types.zig");
const util = @import("util.zig");

extern var flag: types.Flags;

extern var version: [*c]const u8;
extern var charset: [*c]const u8;

extern var host: [*c]u8;
extern var sp: [*c]const u8;
extern var title: [*c]const u8;
extern var Hintro: [*c]const u8;
extern var Houtro: [*c]const u8;

// Still in tree.zig
extern fn psize(buf: [*c]u8, size: c.off_t) c_int;
extern fn fillinfo(buf: [*c]u8, ent: ?*const types.Info) [*c]u8;
extern fn indent(w: *std.Io.Writer, maxlevel: c_int) void;

export var htmldirlen: usize = 0;

fn classOf(info: *types.Info) [*c]const u8 {
    if (info.isdir) return "DIR";
    if (info.isexe) return "EXEC";
    if (info.isfifo) return "FIFO";
    if (info.issok) return "SOCK";
    return "NORM";
}

pub fn encode(w: *std.Io.Writer, s_in: [*c]u8) void {
    var s = s_in;
    while (s[0] != 0) : (s += 1) {
        switch (s[0]) {
            '<' => w.writeAll("&lt;") catch {},
            '>' => w.writeAll("&gt;") catch {},
            '&' => w.writeAll("&amp;") catch {},
            '"' => w.writeAll("&quot;") catch {},
            else => w.writeByte(s[0]) catch {},
        }
    }
}

pub fn url_encode(w: *std.Io.Writer, s_in: [*c]u8) bool {
    const unreserved = "/-._~";
    var s = s_in;
    var slash = false;
    while (s[0] != 0) : (s += 1) {
        const ch: u8 = s[0];
        if (c.isalnum(@as(c_int, ch)) != 0 or c.strchr(unreserved, @as(c_int, ch)) != null) {
            w.writeByte(ch) catch {};
        } else {
            w.print("%{X:0>2}", .{ch}) catch {};
        }
        slash = (ch == '/');
    }
    return slash;
}

fn fcat(w: *std.Io.Writer, filename: [*c]const u8) void {
    const fp = c.fopen(filename, "r") orelse return;
    defer _ = c.fclose(fp);

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    while (true) {
        const n = c.fread(&buf, 1, buf.len, fp);
        if (n == 0) break;
        w.writeAll(buf[0..n]) catch {};
    }
}

pub fn intro() void {
    var buf: [4096]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    if (Hintro != null) {
        fcat(&fw.interface, Hintro);
        return;
    }
    const cs = if (charset != null) std.mem.span(charset) else "iso-8859-1";
    fw.interface.print(
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\ <meta http-equiv="Content-Type" content="text/html; charset={s}">
        \\ <meta name="Author" content="Made by 'tree'">
        \\ <meta name="GENERATOR" content="
    , .{cs}) catch {};
    fw.interface.print("{s}", .{std.mem.span(version)}) catch {};
    const ttl = std.mem.span(title);
    fw.interface.print(
        \\">
        \\ <title>{s}</title>
        \\ <style type="text/css">
        \\  BODY {{ font-family : monospace, sans-serif;  color: black;}}
        \\  P {{ font-family : monospace, sans-serif; color: black; margin:0px; padding: 0px;}}
        \\  A:visited {{ text-decoration : none; margin : 0px; padding : 0px;}}
        \\  A:link    {{ text-decoration : none; margin : 0px; padding : 0px;}}
        \\  A:hover   {{ text-decoration: underline; background-color : yellow; margin : 0px; padding : 0px;}}
        \\  A:active  {{ margin : 0px; padding : 0px;}}
        \\  .VERSION {{ font-size: small; font-family : arial, sans-serif; }}
        \\  .NORM  {{ color: black;  }}
        \\  .FIFO  {{ color: purple; }}
        \\  .CHAR  {{ color: yellow; }}
        \\  .DIR   {{ color: blue;   }}
        \\  .BLOCK {{ color: yellow; }}
        \\  .LINK  {{ color: aqua;   }}
        \\  .SOCK  {{ color: fuchsia;}}
        \\  .EXEC  {{ color: green;  }}
        \\ </style>
        \\</head>
        \\<body>
        \\
    ++ "\t<h1>{s}</h1><p>\n", .{ ttl, ttl }) catch {};
}

pub fn outtro() void {
    var buf: [256]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    if (Houtro != null) {
        fcat(&fw.interface, Houtro);
        return;
    }
    fw.interface.print("\t<hr>\n\t<p class=\"VERSION\">\n\t\t {s} <br>\n\t</p>\n</body>\n</html>\n", .{std.mem.span(version)}) catch {};
}

fn htmlPrint(w: *std.Io.Writer, s_in: [*c]const u8) void {
    var i: usize = 0;
    while (s_in[i] != 0) : (i += 1) {
        if (s_in[i] == ' ') {
            w.writeAll(std.mem.span(sp)) catch {};
        } else {
            w.writeByte(s_in[i]) catch {};
        }
    }
    const sp_s = std.mem.span(sp);
    w.writeAll(sp_s) catch {};
    w.writeAll(sp_s) catch {};
}

pub fn printinfo(dirname: [*c]u8, file: ?*types.Info, level: c_int) c_int {
    _ = dirname;

    var info: [512]u8 = undefined;
    _ = fillinfo(&info, file);

    var buf: [1024]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    const sp_s = std.mem.span(sp);

    if (flag.metafirst) {
        if (info[0] == '[') {
            htmlPrint(&fw.interface, &info);
            fw.interface.writeAll(sp_s) catch {};
            fw.interface.writeAll(sp_s) catch {};
        }
        if (!flag.noindent) indent(&fw.interface, level);
    } else {
        if (!flag.noindent) indent(&fw.interface, level);
        if (info[0] == '[') {
            htmlPrint(&fw.interface, &info);
            fw.interface.writeAll(sp_s) catch {};
            fw.interface.writeAll(sp_s) catch {};
        }
    }

    return 0;
}

pub fn printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*types.Info, descend: c_int) c_int {
    var buf: [4096]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};

    fw.interface.writeAll("<a") catch {};
    if (file) |f| {
        if (flag.force_color) fw.interface.print(" class=\"{s}\"", .{std.mem.span(classOf(f))}) catch {};
        if (f.comment != null) {
            fw.interface.writeAll(" title=\"") catch {};
            var i: usize = 0;
            while (f.comment[i] != null) : (i += 1) {
                encode(&fw.interface, f.comment[i]);
                if (f.comment[i + 1] != null) fw.interface.writeByte('\n') catch {};
            }
            fw.interface.writeByte('"') catch {};
        }

        if (!flag.nolinks) {
            fw.interface.print(" href=\"{s}", .{std.mem.span(host)}) catch {};
            if (dirname != null) {
                const len = c.strlen(dirname);
                const off: usize = if (len >= htmldirlen) htmldirlen else 0;
                const url_start = if (flag.htmloffset) dirname + off else dirname;
                _ = url_encode(&fw.interface, url_start);
                if (c.strcmp(dirname, filename) != 0) {
                    if (dirname[c.strlen(dirname) - 1] != '/') fw.interface.writeByte('/') catch {};
                    _ = url_encode(&fw.interface, filename);
                }
                const tree_suffix: []const u8 = if (descend > 1) "/00Tree.html" else "";
                const slash_suffix: []const u8 = if (f.isdir and descend < 2) "/" else "";
                fw.interface.print("{s}{s}\"", .{ tree_suffix, slash_suffix }) catch {};
            } else {
                if (host[c.strlen(host) - 1] != '/') fw.interface.writeByte('/') catch {};
                _ = url_encode(&fw.interface, filename);
                const tree_suffix: []const u8 = if (descend > 1) "/00Tree.html" else "";
                fw.interface.print("{s}\"", .{tree_suffix}) catch {};
            }
        }
    }
    fw.interface.writeByte('>') catch {};

    if (dirname != null) {
        encode(&fw.interface, filename);
    } else {
        encode(&fw.interface, host);
    }

    fw.interface.writeAll("</a>") catch {};
    return 0;
}

pub fn printerror(err: [*c]u8) c_int {
    var buf: [512]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("  [{s}]", .{std.mem.span(err)}) catch {};
    return 0;
}

pub fn newline(file: ?*types.Info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = file;
    _ = level;
    _ = postdir;
    _ = needcomma;
    var buf: [16]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.writeAll("<br>\n") catch {};
}

pub fn close(file: ?*types.Info, level: c_int, needcomma: c_int) void {
    _ = level;
    _ = needcomma;
    if (file) |f| {
        var buf: [256]u8 = undefined;
        var fw = util.writer(&buf);
        defer fw.interface.flush() catch {};
        fw.interface.print("</{s}><br>\n", .{std.mem.span(f.tag)}) catch {};
    }
}

pub fn report(tot: types.Totals) void {
    var buf: [512]u8 = undefined;
    var fw = util.writer(&buf);
    defer fw.interface.flush() catch {};
    var pbuf: [256]u8 = undefined;

    fw.interface.writeAll("<br><br><p>\n\n") catch {};

    if (flag.du) {
        _ = psize(&pbuf, @intCast(tot.size));
        const unit: []const u8 = if (flag.h or flag.si) "" else " bytes";
        const sz = std.mem.sliceTo(&pbuf, 0);
        fw.interface.print("{s}{s} used in ", .{ sz, unit }) catch {};
    }
    if (flag.d) {
        const suffix: []const u8 = if (tot.dirs == 1) "y" else "ies";
        fw.interface.print("{d} director{s}\n", .{ tot.dirs, suffix }) catch {};
    } else {
        const dsuffix: []const u8 = if (tot.dirs == 1) "y" else "ies";
        const fsuffix: []const u8 = if (tot.files == 1) "" else "s";
        fw.interface.print("{d} director{s}, {d} file{s}\n", .{ tot.dirs, dsuffix, tot.files, fsuffix }) catch {};
    }

    fw.interface.writeAll("\n</p>\n") catch {};
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
