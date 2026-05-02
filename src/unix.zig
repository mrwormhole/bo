//! Default text-mode listing callbacks ported from unix.c.

const std = @import("std");

const c = @cImport({
    @cInclude("tree.h");
});

const types = @import("types.zig");
const html = @import("html.zig");
const info = @import("info.zig");
extern var flag: types.Flags;
extern var outfile: *std.fs.File;
extern var dirs: [*c]c_int;

extern var scheme: [*c]u8;
extern var authority: [*c]u8;

extern fn fillinfo(buf: [*c]u8, ent: ?*const types.Info) [*c]u8;
extern fn indent(w: *std.Io.Writer, maxlevel: c_int) void;
extern fn emit_hyperlink_path(w: *std.Io.Writer, dirname: [*c]u8) void;
extern fn printit(w: *std.Io.Writer, s: [*c]const u8) void;
extern fn Ftype(mode: c.mode_t) u8;
extern fn psize(buf: [*c]u8, size: c.off_t) c_int;
// extern fn colorize(w: *std.Io.Writer, mode: c.mode_t, name: [*c]const u8, orphan: bool, islink: bool) bool;
//extern fn endcolor(w: *std.Io.Writer) void;

const colorize = @import("color.zig").colorize;
const endcolor = @import("color.zig").endcolor;

// Persists across calls: written by printinfo, re-read by newline
// when computing metafirst comment indentation.
var info_buf: [512]u8 = std.mem.zeroes([512]u8);

pub fn printinfo(dirname: [*c]u8, file: ?*types.Info, level: c_int) c_int {
    _ = dirname;

    _ = fillinfo(&info_buf, file);
    var buf: [1024]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    if (flag.metafirst) {
        if (info_buf[0] == '[') fw.interface.print("{s}  ", .{std.mem.sliceTo(&info_buf, 0)}) catch {};
        if (!flag.noindent) indent(&fw.interface, level);
    } else {
        if (!flag.noindent) indent(&fw.interface, level);
        if (info_buf[0] == '[') fw.interface.print("{s}  ", .{std.mem.sliceTo(&info_buf, 0)}) catch {};
    }
    return 0;
}

fn open_hyperlink(w: *std.Io.Writer, dirname: [*c]u8, filename: [*c]u8) void {
    w.print("\x1b]8;;{s}", .{std.mem.span(scheme)}) catch {};
    _ = html.url_encode(w, authority);
    w.writeByte(':') catch {};
    emit_hyperlink_path(w, dirname);
    _ = html.url_encode(w, filename);
    w.writeAll("\x1b\\") catch {};
}

fn close_hyperlink(w: *std.Io.Writer) void {
    w.writeAll("\x1b]8;;\x1b\\") catch {};
}

pub fn printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*types.Info, descend: c_int) c_int {
    _ = descend;

    var buf: [4096]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    var colored: bool = false;

    if (file) |f| {
        if (flag.hyper) open_hyperlink(&fw.interface, dirname, f.name);

        if (flag.colorize) {
            if (f.lnk != null and flag.linktargetcolor) {
                colored = colorize(&fw.interface, @intCast(f.lnkmode), f.name, f.orphan, false);
            } else {
                colored = colorize(&fw.interface, @intCast(f.mode), f.name, f.orphan, false);
            }
        }
    }

    printit(&fw.interface, filename);
    if (colored) endcolor(&fw.interface);

    if (file) |f| {
        if (flag.hyper) close_hyperlink(&fw.interface);

        if (flag.F and f.lnk == null) {
            const ch = Ftype(@intCast(f.mode));
            if (ch != 0) fw.interface.writeByte(ch) catch {};
        }

        if (f.lnk != null) {
            fw.interface.writeAll(" -> ") catch {};
            if (flag.hyper) open_hyperlink(&fw.interface, dirname, f.name);
            if (flag.colorize) colored = colorize(&fw.interface, @intCast(f.lnkmode), f.lnk, f.orphan, true);
            printit(&fw.interface, f.lnk);
            if (colored) endcolor(&fw.interface);
            if (flag.hyper) close_hyperlink(&fw.interface);
            if (flag.F) {
                const ch = Ftype(@intCast(f.lnkmode));
                if (ch != 0) fw.interface.writeByte(ch) catch {};
            }
        }
    }
    return 0;
}

pub fn printerror(err: [*c]u8) c_int {
    var buf: [512]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};
    fw.interface.print("  [{s}]", .{std.mem.span(err)}) catch {};
    return 0;
}

pub fn newline(file: ?*types.Info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = needcomma;

    var buf: [4096]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};

    if (postdir <= 0) fw.interface.writeByte('\n') catch {};
    if (file) |f| {
        if (f.comment == null) return;

        var infosize: usize = 0;
        if (flag.metafirst) {
            infosize = if (info_buf[0] == '[') c.strlen(&info_buf) + 2 else 0;
        }

        var lines: usize = 0;
        while (f.comment[lines] != null) : (lines += 1) {}
        dirs[@intCast(level + 1)] = 1;
        var line: usize = 0;
        while (line < lines) : (line += 1) {
            if (flag.metafirst) {
                fw.interface.splatByteAll(' ', infosize) catch {};
            }
            indent(&fw.interface, level);
            info.printcomment(&fw.interface, line, lines, f.comment[line]);
        }
        dirs[@intCast(level + 1)] = 0;
    }
}

pub fn report(tot: types.Totals) void {
    var pbuf: [256]u8 = undefined;
    var buf: [512]u8 = undefined;
    var fw = outfile.writer(&buf);
    defer fw.interface.flush() catch {};

    fw.interface.writeByte('\n') catch {};
    if (flag.du) {
        _ = psize(&pbuf, @intCast(tot.size));
        const suffix: []const u8 = if (flag.h or flag.si) "" else " bytes";
        const sz = std.mem.sliceTo(&pbuf, 0);
        fw.interface.print("{s}{s} used in ", .{ sz, suffix }) catch {};
    }
    if (flag.d) {
        const noun: []const u8 = if (tot.dirs == 1) "y" else "ies";
        fw.interface.print("{d} director{s}\n", .{ tot.dirs, noun }) catch {};
    } else {
        const dnoun: []const u8 = if (tot.dirs == 1) "y" else "ies";
        const fnoun: []const u8 = if (tot.files == 1) "" else "s";
        fw.interface.print("{d} director{s}, {d} file{s}\n", .{ tot.dirs, dnoun, tot.files, fnoun }) catch {};
    }
}

const noop = struct {
    fn intro() void {}
    fn close(_: ?*types.Info, _: c_int, _: c_int) void {}
};

pub fn ListingCalls() types.ListingCalls {
    return .{
        .intro = &noop.intro,
        .outtro = &noop.intro,
        .printinfo = &printinfo,
        .printfile = &printfile,
        .@"error" = &printerror,
        .newline = &newline,
        .close = &noop.close,
        .report = &report,
    };
}
