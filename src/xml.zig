//! XML renderer ported from xml.c.

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

extern var flag: c.struct_Flags;
extern var outfile: ?*c.FILE;
extern var _nl: [*c]const u8;
extern var charset: [*c]const u8;

const ifmt = @extern([*]const c.mode_t, .{ .name = "ifmt" });
const ftype = @extern([*]const [*c]const u8, .{ .name = "ftype" });

// Already ported in hash.zig — link against the exported C symbols.
extern fn uidtoname(uid: c.uid_t) [*c]const u8;
extern fn gidtoname(gid: c.gid_t) [*c]const u8;

// Still in C (file.c); port later.
extern fn prot(mode: c.mode_t) [*c]u8;
extern fn do_date(t: c.time_t) [*c]u8;

// XML reuses the HTML encoder for attribute escaping (&, <, >, ").
extern fn html_encode(fd: *c.FILE, s: [*c]u8) void;

export fn xml_indent(maxlevel: c_int) void {
    const spaces = [_][*:0]const u8{ "    ", "   ", "  ", " ", "" };
    if (flag.noindent) return;

    const extra: c_int = if (flag.remove_space) 1 else 0;
    const clvl: usize = @intCast(flag.compress_indent + extra);
    const out = outfile.?;

    _ = c.fprintf(out, "%s", spaces[clvl]);
    var i: c_int = 0;
    while (i < maxlevel) : (i += 1) {
        _ = c.fprintf(out, "%s", spaces[clvl]);
    }
}

export fn xml_fillinfo(ent: *c.struct__info) void {
    const out = outfile.?;

    if (flag.inode) _ = c.fprintf(out, " inode=\"%lld\"", @as(c_longlong, @intCast(ent.inode)));
    if (flag.dev) _ = c.fprintf(out, " dev=\"%d\"", @as(c_int, @intCast(ent.dev)));
    if (flag.p) {
        const mask: c.mode_t = c.S_IRWXU | c.S_IRWXG | c.S_IRWXO | c.S_ISUID | c.S_ISGID | c.S_ISVTX;
        _ = c.fprintf(out, " mode=\"%04o\" prot=\"%s\"", @as(c_uint, @intCast(ent.mode & mask)), prot(ent.mode));
    }
    if (flag.u) _ = c.fprintf(out, " user=\"%s\"", uidtoname(ent.uid));
    if (flag.g) _ = c.fprintf(out, " group=\"%s\"", gidtoname(ent.gid));
    if (flag.s) _ = c.fprintf(out, " size=\"%lld\"", @as(c_longlong, @intCast(ent.size)));
    if (flag.D) _ = c.fprintf(out, " time=\"%s\"", do_date(if (flag.c) ent.ctime else ent.mtime));
}

export fn xml_intro() void {
    const out = outfile.?;
    _ = c.fprintf(out, "<?xml version=\"1.0\"");
    if (charset != null) _ = c.fprintf(out, " encoding=\"%s\"", charset);
    _ = c.fprintf(out, "?>%s<tree>%s", _nl, _nl);
}

export fn xml_outtro() void {
    _ = c.fprintf(outfile.?, "</tree>%s", _nl);
}

export fn xml_printinfo(dirname: [*c]u8, file: ?*c.struct__info, level: c_int) c_int {
    _ = dirname;

    if (!flag.noindent) xml_indent(level);

    const mt: c.mode_t = if (file) |f| f.mode & c.S_IFMT else 0;

    var t: usize = 0;
    while (ifmt[t] != 0) : (t += 1) {
        if (ifmt[t] == mt) break;
    }
    if (file) |f| f.tag = ftype[t];
    _ = c.fprintf(outfile.?, "<%s", ftype[t]);

    return 0;
}

export fn xml_printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*c.struct__info, descend: c_int) c_int {
    _ = dirname;
    _ = descend;
    const out = outfile.?;

    _ = c.fprintf(out, " name=\"");
    html_encode(out, filename);
    _ = c.fputc('"', out);

    if (file) |f| {
        if (f.comment != null) {
            _ = c.fprintf(out, " info=\"");
            var i: usize = 0;
            while (f.comment[i] != null) : (i += 1) {
                html_encode(out, f.comment[i]);
                if (f.comment[i + 1] != null) _ = c.fprintf(out, "%s", _nl);
            }
            _ = c.fputc('"', out);
        }
        if (f.lnk != null) {
            _ = c.fprintf(out, " target=\"");
            html_encode(out, f.lnk);
            _ = c.fputc('"', out);
        }
        xml_fillinfo(f);
    }
    _ = c.fputc('>', out);

    return 1;
}

export fn xml_error(err: [*c]u8) c_int {
    _ = c.fprintf(outfile.?, "<error>%s</error>", err);
    return 0;
}

export fn xml_newline(file: ?*c.struct__info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = file;
    _ = level;
    _ = needcomma;
    if (postdir >= 0) _ = c.fprintf(outfile.?, "%s", _nl);
}

export fn xml_close(file: ?*c.struct__info, level: c_int, needcomma: c_int) void {
    _ = needcomma;
    if (!flag.noindent and level >= 0) xml_indent(level);

    const tag: [*c]const u8 = if (file) |f| f.tag else "unknown";
    const trailer: [*c]const u8 = if (flag.noindent) "" else _nl;
    _ = c.fprintf(outfile.?, "</%s>%s", tag, trailer);
}

export fn xml_report(tot: c.struct_totals) void {
    const out = outfile.?;

    xml_indent(0);
    _ = c.fprintf(out, "<report>%s", _nl);
    if (flag.du) {
        xml_indent(1);
        _ = c.fprintf(out, "<size>%lld</size>%s", @as(c_longlong, @intCast(tot.size)), _nl);
    }
    xml_indent(1);
    _ = c.fprintf(out, "<directories>%ld</directories>%s", @as(c_long, @intCast(tot.dirs)), _nl);
    if (!flag.d) {
        xml_indent(1);
        _ = c.fprintf(out, "<files>%ld</files>%s", @as(c_long, @intCast(tot.files)), _nl);
    }
    xml_indent(0);
    _ = c.fprintf(out, "</report>%s", _nl);
}
