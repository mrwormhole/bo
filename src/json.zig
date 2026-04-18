//! JSON renderer ported from json.c.

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

extern var flag: c.struct_Flags;
extern var outfile: ?*c.FILE;
extern var _nl: [*c]const u8;

const ifmt = @extern([*]const c.mode_t, .{ .name = "ifmt" });
const ftype = @extern([*]const [*c]const u8, .{ .name = "ftype" });

// Already ported in hash.zig — link against the exported C symbols.
extern fn uidtoname(uid: c.uid_t) [*c]const u8;
extern fn gidtoname(gid: c.gid_t) [*c]const u8;

// Still in C (file.c); port later.
extern fn prot(mode: c.mode_t) [*c]u8;
extern fn psize(buf: [*c]u8, size: c.off_t) c_int;
extern fn do_date(t: c.time_t) [*c]u8;

// RFC 8259 escape map: index 0..31 → '-' means \uXXXX, otherwise the letter after '\'.
const ctrl_map: *const [32]u8 = "0-------btn-fr------------------";

fn jsonEncode(fd: *c.FILE, s_in: [*c]const u8) void { // FIXME: Still not UTF-8
    var s = s_in;
    while (s[0] != 0) : (s += 1) {
        const ch: u8 = s[0];
        if (ch < 32) {
            if (ctrl_map[ch] != '-') {
                _ = c.fprintf(fd, "\\%c", @as(c_int, ctrl_map[ch]));
            } else {
                _ = c.fprintf(fd, "\\u%04x", @as(c_uint, ch));
            }
        } else if (ch == '"' or ch == '\\') {
            _ = c.fprintf(fd, "\\%c", @as(c_int, ch));
        } else {
            _ = c.fprintf(fd, "%c", @as(c_int, ch));
        }
    }
}

export fn json_indent(maxlevel: c_int) void {
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

export fn json_fillinfo(ent: *c.struct__info) void {
    const out = outfile.?;

    if (flag.inode) _ = c.fprintf(out, ",\"inode\":%lld", @as(c_longlong, @intCast(ent.inode)));
    if (flag.dev) _ = c.fprintf(out, ",\"dev\":%d", @as(c_int, @intCast(ent.dev)));
    if (flag.p) {
        const mask: c.mode_t = c.S_IRWXU | c.S_IRWXG | c.S_IRWXO | c.S_ISUID | c.S_ISGID | c.S_ISVTX;
        _ = c.fprintf(out, ",\"mode\":\"%04o\",\"prot\":\"%s\"", @as(c_uint, @intCast(ent.mode & mask)), prot(ent.mode));
    }
    if (flag.u) _ = c.fprintf(out, ",\"user\":\"%s\"", uidtoname(ent.uid));
    if (flag.g) _ = c.fprintf(out, ",\"group\":\"%s\"", gidtoname(ent.gid));
    if (flag.s) {
        if (flag.h or flag.si) {
            var nbuf: [64]u8 = undefined;
            _ = psize(&nbuf, ent.size);
            var i: usize = 0;
            while (c.isspace(@as(c_int, nbuf[i])) != 0) : (i += 1) {}
            _ = c.fprintf(out, ",\"size\":\"%s\"", @as([*c]const u8, @ptrCast(&nbuf[i])));
        } else {
            _ = c.fprintf(out, ",\"size\":%lld", @as(c_longlong, @intCast(ent.size)));
        }
    }
    if (flag.D) _ = c.fprintf(out, ",\"time\":\"%s\"", do_date(if (flag.c) ent.ctime else ent.mtime));
}

export fn json_intro() void {
    _ = c.fprintf(outfile.?, "[%s", if (flag.noindent) @as([*c]const u8, "") else _nl);
}

export fn json_outtro() void {
    _ = c.fprintf(outfile.?, "%s]\n", if (flag.noindent) @as([*c]const u8, "") else _nl);
}

export fn json_printinfo(dirname: [*c]u8, file: ?*c.struct__info, level: c_int) c_int {
    _ = dirname;

    if (!flag.noindent) json_indent(level);

    const mt: c.mode_t = if (file) |f| f.mode & c.S_IFMT else 0;

    var t: usize = 0;
    while (ifmt[t] != 0) : (t += 1) {
        if (ifmt[t] == mt) break;
    }
    _ = c.fprintf(outfile.?, "{\"type\":\"%s\"", ftype[t]);

    return 0;
}

export fn json_printfile(dirname: [*c]u8, filename: [*c]u8, file: ?*c.struct__info, descend: c_int) c_int {
    _ = dirname;
    const out = outfile.?;
    var direrr = false;

    _ = c.fprintf(out, ",\"name\":\"");
    jsonEncode(out, filename);
    _ = c.fputc('"', out);

    if (file) |f| {
        if (f.comment != null) {
            _ = c.fprintf(out, ",\"info\":\"");
            var i: usize = 0;
            while (f.comment[i] != null) : (i += 1) {
                jsonEncode(out, f.comment[i]);
                if (f.comment[i + 1] != null) _ = c.fprintf(out, "\\n");
            }
            _ = c.fprintf(out, "\"");
        }

        if (f.lnk != null) {
            _ = c.fprintf(out, ",\"target\":\"");
            jsonEncode(out, f.lnk);
            _ = c.fputc('"', out);
        }
        json_fillinfo(f);
        direrr = f.isdir and f.err != null;
    }

    if (descend != 0 or direrr) {
        _ = c.fprintf(out, ",\"contents\":[");
    } else {
        _ = c.fputc('}', out);
    }

    return if (descend != 0 or direrr) 1 else 0;
}

export fn json_error(err: [*c]u8) c_int {
    _ = c.fprintf(outfile.?, "{\"error\": \"%s\"}%s", err, @as([*c]const u8, ""));
    return 0;
}

export fn json_newline(file: ?*c.struct__info, level: c_int, postdir: c_int, needcomma: c_int) void {
    _ = file;
    _ = level;
    _ = postdir;
    _ = c.fprintf(outfile.?, "%s%s", if (needcomma != 0) @as([*c]const u8, ",") else @as([*c]const u8, ""), _nl);
}

export fn json_close(file: ?*c.struct__info, level: c_int, needcomma: c_int) void {
    _ = file;
    if (!flag.noindent) json_indent(level);
    _ = c.fprintf(
        outfile.?,
        "]}%s%s",
        if (needcomma != 0) @as([*c]const u8, ",") else @as([*c]const u8, ""),
        if (flag.noindent) @as([*c]const u8, "") else @as([*c]const u8, "\n"),
    );
}

export fn json_report(tot: c.struct_totals) void {
    const out = outfile.?;
    _ = c.fputc(',', out);
    json_indent(0);
    _ = c.fprintf(out, "{\"type\":\"report\"");
    if (flag.du) _ = c.fprintf(out, ",\"size\":%lld", @as(c_longlong, @intCast(tot.size)));
    _ = c.fprintf(out, ",\"directories\":%ld", @as(c_long, @intCast(tot.dirs)));
    if (!flag.d) _ = c.fprintf(out, ",\"files\":%ld", @as(c_long, @intCast(tot.files)));
    _ = c.fprintf(out, "}");
}
