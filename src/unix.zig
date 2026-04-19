//! Default text-mode listing callbacks ported from unix.c.

const std = @import("std");

const c = @cImport({
    @cInclude("tree.h");
});

extern var flag: c.struct_Flags;
extern var outfile: ?*c.FILE;
extern var dirs: [*c]c_int;

extern var scheme: [*c]u8;
extern var authority: [*c]u8;

extern var realbasepath: [c.PATH_MAX]u8;
extern var dirpathoffset: usize;

// Persists across calls: written by unix_printinfo, re-read by unix_newline
// when computing metafirst comment indentation.
var info_buf: [512]u8 = std.mem.zeroes([512]u8);

export fn unix_printinfo(dirname: [*c]u8, file: ?*c.struct__info, level: c_int) c_int {
    _ = dirname;

    _ = c.fillinfo(&info_buf, file);
    if (flag.metafirst) {
        if (info_buf[0] == '[') _ = c.fprintf(outfile, "%s  ", &info_buf);
        if (!flag.noindent) c.indent(level);
    } else {
        if (!flag.noindent) c.indent(level);
        if (info_buf[0] == '[') _ = c.fprintf(outfile, "%s  ", &info_buf);
    }
    return 0;
}

fn open_hyperlink(dirname: [*c]u8, filename: [*c]u8) void {
    const out = outfile.?;
    _ = c.fprintf(out, "\x1b]8;;%s", scheme);
    _ = c.url_encode(out, authority);
    _ = c.fprintf(out, ":");
    // (optional) Hanging slashes are a real pain to deal with
    var slash = c.url_encode(out, &realbasepath);
    if (dirname[dirpathoffset] != 0) {
        slash = slash or (dirname[dirpathoffset] == '/');
        if (!slash) _ = c.fputc('/', out);
        if (!c.url_encode(out, dirname + dirpathoffset)) _ = c.fputc('/', out);
    } else if (!slash) {
        _ = c.fputc('/', out);
    }
    _ = c.url_encode(out, filename);
    _ = c.fprintf(out, "\x1b\\");
}

fn close_hyperlink() void {
    _ = c.fprintf(outfile, "\x1b]8;;\x1b\\");
}

export fn unix_printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*c.struct__info, descend: c_int) c_int {
    _ = descend;

    var colored: bool = false;

    if (file) |f| {
        if (flag.hyper) open_hyperlink(dirname, f.name);

        if (flag.colorize) {
            if (f.lnk != null and flag.linktargetcolor) {
                colored = c.color(f.lnkmode, f.name, f.orphan, false);
            } else {
                colored = c.color(f.mode, f.name, f.orphan, false);
            }
        }
    }

    c.printit(filename);
    if (colored) c.endcolor();

    if (file) |f| {
        if (flag.hyper) close_hyperlink();

        if (flag.F and f.lnk == null) {
            const ch = c.Ftype(f.mode);
            if (ch != 0) _ = c.fputc(ch, outfile);
        }

        if (f.lnk != null) {
            _ = c.fprintf(outfile, " -> ");
            if (flag.hyper) open_hyperlink(dirname, f.name);
            if (flag.colorize) colored = c.color(f.lnkmode, f.lnk, f.orphan, true);
            c.printit(f.lnk);
            if (colored) c.endcolor();
            if (flag.hyper) close_hyperlink();
            if (flag.F) {
                const ch = c.Ftype(f.lnkmode);
                if (ch != 0) _ = c.fputc(ch, outfile);
            }
        }
    }
    return 0;
}

export fn unix_error(err: [*c]u8) c_int {
    _ = c.fprintf(outfile, "  [%s]", err);
    return 0;
}

export fn unix_newline(file: ?*c.struct__info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = needcomma;

    if (postdir <= 0) _ = c.fprintf(outfile, "\n");
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
                _ = c.printf("%*s", @as(c_int, @intCast(infosize)), "");
            }
            c.indent(level);
            c.printcomment(line, lines, f.comment[line]);
        }
        dirs[@intCast(level + 1)] = 0;
    }
}

export fn unix_report(tot: c.struct_totals) void {
    var buf: [256]u8 = undefined;

    _ = c.fputc('\n', outfile);
    if (flag.du) {
        _ = c.psize(&buf, tot.size);
        const suffix: [*c]const u8 = if (flag.h or flag.si) "" else " bytes";
        _ = c.fprintf(outfile, "%s%s used in ", &buf, suffix);
    }
    if (flag.d) {
        const noun: [*c]const u8 = if (tot.dirs == 1) "y" else "ies";
        _ = c.fprintf(outfile, "%ld director%s\n", @as(c_long, @intCast(tot.dirs)), noun);
    } else {
        const dnoun: [*c]const u8 = if (tot.dirs == 1) "y" else "ies";
        const fnoun: [*c]const u8 = if (tot.files == 1) "" else "s";
        _ = c.fprintf(
            outfile,
            "%ld director%s, %ld file%s\n",
            @as(c_long, @intCast(tot.dirs)),
            dnoun,
            @as(c_long, @intCast(tot.files)),
            fnoun,
        );
    }
}
