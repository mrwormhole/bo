//! HTML renderer ported from html.c.

const c = @cImport({
    @cInclude("tree.h");
});

extern var flag: c.struct_Flags;

extern var version: [*c]const u8;
extern var charset: [*c]const u8;

extern var host: [*c]u8;
extern var sp: [*c]const u8;
extern var title: [*c]const u8;
extern var Hintro: [*c]const u8;
extern var Houtro: [*c]const u8;

extern var outfile: ?*c.FILE;

// FIXME: Still in C (file.c / tree.c); port later.
extern fn psize(buf: [*c]u8, size: c.off_t) c_int;
extern fn fillinfo(buf: [*c]u8, ent: *const c.struct__info) [*c]u8;
extern fn indent(maxlevel: c_int) void;
extern fn print_version(nl: c_int) void;

export var htmldirlen: usize = 0;

fn classOf(info: *c.struct__info) [*c]const u8 {
    if (info.isdir) return "DIR";
    if (info.isexe) return "EXEC";
    if (info.isfifo) return "FIFO";
    if (info.issok) return "SOCK";
    return "NORM";
}

export fn html_encode(fd: *c.FILE, s_in: [*c]u8) void {
    var s = s_in;
    while (s[0] != 0) : (s += 1) {
        switch (s[0]) {
            '<' => _ = c.fputs("&lt;", fd),
            '>' => _ = c.fputs("&gt;", fd),
            '&' => _ = c.fputs("&amp;", fd),
            '"' => _ = c.fputs("&quot;", fd),
            else => _ = c.fputc(@as(c_int, s[0]), fd),
        }
    }
}

export fn url_encode(fd: *c.FILE, s_in: [*c]u8) bool {
    const unreserved = "/-._~";
    var s = s_in;
    var slash = false;
    while (s[0] != 0) : (s += 1) {
        const ch: u8 = s[0];
        const fmt: [*c]const u8 = if (c.isalnum(@as(c_int, ch)) != 0 or c.strchr(unreserved, @as(c_int, ch)) != null)
            "%c"
        else
            "%%%02X";
        _ = c.fprintf(fd, fmt, @as(c_int, ch));
        slash = (ch == '/');
    }
    return slash;
}

fn fcat(filename: [*c]const u8) void {
    const fp = c.fopen(filename, "r") orelse return;
    defer _ = c.fclose(fp);

    var buf: [c.PATH_MAX]u8 = undefined;
    while (true) {
        const n = c.fread(&buf, 1, buf.len, fp);
        if (n == 0) break;
        _ = c.fwrite(&buf, 1, n, outfile.?);
    }
}

export fn html_intro() void {
    const out = outfile.?;
    if (Hintro != null) {
        fcat(Hintro);
        return;
    }
    const cs: [*c]const u8 = if (charset != null) charset else "iso-8859-1";
    _ = c.fprintf(out,
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\ <meta http-equiv="Content-Type" content="text/html; charset=%s">
        \\ <meta name="Author" content="Made by 'tree'">
        \\ <meta name="GENERATOR" content="
    ++ "", cs);
    print_version(0);
    _ = c.fprintf(out,
        \\">
        \\ <title>%s</title>
        \\ <style type="text/css">
        \\  BODY { font-family : monospace, sans-serif;  color: black;}
        \\  P { font-family : monospace, sans-serif; color: black; margin:0px; padding: 0px;}
        \\  A:visited { text-decoration : none; margin : 0px; padding : 0px;}
        \\  A:link    { text-decoration : none; margin : 0px; padding : 0px;}
        \\  A:hover   { text-decoration: underline; background-color : yellow; margin : 0px; padding : 0px;}
        \\  A:active  { margin : 0px; padding : 0px;}
        \\  .VERSION { font-size: small; font-family : arial, sans-serif; }
        \\  .NORM  { color: black;  }
        \\  .FIFO  { color: purple; }
        \\  .CHAR  { color: yellow; }
        \\  .DIR   { color: blue;   }
        \\  .BLOCK { color: yellow; }
        \\  .LINK  { color: aqua;   }
        \\  .SOCK  { color: fuchsia;}
        \\  .EXEC  { color: green;  }
        \\ </style>
        \\</head>
        \\<body>
        \\
    ++ "\t<h1>%s</h1><p>\n", title, title);
}

export fn html_outtro() void {
    const out = outfile.?;
    if (Houtro != null) {
        fcat(Houtro);
        return;
    }
    _ = c.fprintf(out, "\t<hr>\n");
    _ = c.fprintf(out, "\t<p class=\"VERSION\">\n");
    _ = c.fprintf(out, "\t\t %s <br>\n", version);
    _ = c.fprintf(out, "\t</p>\n");
    _ = c.fprintf(out, "</body>\n");
    _ = c.fprintf(out, "</html>\n");
}

fn htmlPrint(s_in: [*c]const u8) void {
    const out = outfile.?;
    var i: usize = 0;
    while (s_in[i] != 0) : (i += 1) {
        if (s_in[i] == ' ') {
            _ = c.fprintf(out, "%s", sp);
        } else {
            _ = c.fprintf(out, "%c", @as(c_int, s_in[i]));
        }
    }
    _ = c.fprintf(out, "%s%s", sp, sp);
}

export fn html_printinfo(dirname: [*c]u8, file: *c.struct__info, level: c_int) c_int {
    _ = dirname;

    var info: [512]u8 = undefined;
    _ = fillinfo(&info, file);

    if (flag.metafirst) {
        if (info[0] == '[') {
            htmlPrint(&info);
            _ = c.fprintf(outfile.?, "%s%s", sp, sp);
        }
        if (!flag.noindent) indent(level);
    } else {
        if (!flag.noindent) indent(level);
        if (info[0] == '[') {
            htmlPrint(&info);
            _ = c.fprintf(outfile.?, "%s%s", sp, sp);
        }
    }

    return 0;
}

export fn html_printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*c.struct__info, descend: c_int) c_int {
    const out = outfile.?;

    _ = c.fprintf(out, "<a");
    if (file) |f| {
        if (flag.force_color) _ = c.fprintf(out, " class=\"%s\"", classOf(f));
        if (f.comment != null) {
            _ = c.fprintf(out, " title=\"");
            var i: usize = 0;
            while (f.comment[i] != null) : (i += 1) {
                html_encode(out, f.comment[i]);
                if (f.comment[i + 1] != null) _ = c.fprintf(out, "\n");
            }
            _ = c.fprintf(out, "\"");
        }

        if (!flag.nolinks) {
            _ = c.fprintf(out, " href=\"%s", host);
            if (dirname != null) {
                const len = c.strlen(dirname);
                const off: usize = if (len >= htmldirlen) htmldirlen else 0;
                const url_start = if (flag.htmloffset) dirname + off else dirname;
                _ = url_encode(out, url_start);
                if (c.strcmp(dirname, filename) != 0) {
                    if (dirname[c.strlen(dirname) - 1] != '/') _ = c.fputc('/', out);
                    _ = url_encode(out, filename);
                }
                const tree_suffix: [*c]const u8 = if (descend > 1) "/00Tree.html" else "";
                const slash_suffix: [*c]const u8 = if (f.isdir and descend < 2) "/" else "";
                _ = c.fprintf(out, "%s%s\"", tree_suffix, slash_suffix);
            } else {
                if (host[c.strlen(host) - 1] != '/') _ = c.fputc('/', out);
                _ = url_encode(out, filename);
                const tree_suffix: [*c]const u8 = if (descend > 1) "/00Tree.html" else "";
                _ = c.fprintf(out, "%s\"", tree_suffix);
            }
        }
    }
    _ = c.fprintf(out, ">");

    if (dirname != null) {
        html_encode(out, filename);
    } else {
        html_encode(out, host);
    }

    _ = c.fprintf(out, "</a>");
    return 0;
}

export fn html_error(err: [*c]u8) c_int {
    _ = c.fprintf(outfile.?, "  [%s]", err);
    return 0;
}

export fn html_newline(file: ?*c.struct__info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = file;
    _ = level;
    _ = postdir;
    _ = needcomma;
    _ = c.fprintf(outfile.?, "<br>\n");
}

export fn html_close(file: *c.struct__info, level: c_int, needcomma: c_int) void {
    _ = level;
    _ = needcomma;
    _ = c.fprintf(outfile.?, "</%s><br>\n", file.tag);
}

export fn html_report(tot: c.struct_totals) void {
    const out = outfile.?;
    var buf: [256]u8 = undefined;

    _ = c.fprintf(out, "<br><br><p>\n\n");

    if (flag.du) {
        _ = psize(&buf, tot.size);
        const unit: [*c]const u8 = if (flag.h or flag.si) "" else " bytes";
        _ = c.fprintf(out, "%s%s used in ", @as([*c]const u8, &buf), unit);
    }
    if (flag.d) {
        const suffix: [*c]const u8 = if (tot.dirs == 1) "y" else "ies";
        _ = c.fprintf(out, "%ld director%s\n", @as(c_long, @intCast(tot.dirs)), suffix);
    } else {
        const dsuffix: [*c]const u8 = if (tot.dirs == 1) "y" else "ies";
        const fsuffix: [*c]const u8 = if (tot.files == 1) "" else "s";
        _ = c.fprintf(out, "%ld director%s, %ld file%s\n", @as(c_long, @intCast(tot.dirs)), dsuffix, @as(c_long, @intCast(tot.files)), fsuffix);
    }

    _ = c.fprintf(out, "\n</p>\n");
}
