//! Color and charset support ported from color.c.

const std = @import("std");

const c = @import("cstd.zig");

const types = @import("types.zig");
const util = @import("util.zig");

extern var flag: types.Flags;
extern var charset: [*c]const u8;

// Enum values from the original color.c
const ERROR = -1;
const CMD_COLOR = 0;
const CMD_OPTIONS = 1;
const CMD_TERM = 2;
const CMD_EIGHTBIT = 3;
const COL_RESET = 4;
const COL_NORMAL = 5;
const COL_FILE = 6;
const COL_DIR = 7;
const COL_LINK = 8;
const COL_FIFO = 9;
const COL_DOOR = 10;
const COL_BLK = 11;
const COL_CHR = 12;
const COL_ORPHAN = 13;
const COL_SOCK = 14;
const COL_SETUID = 15;
const COL_SETGID = 16;
const COL_STICKY_OTHER_WRITABLE = 17;
const COL_OTHER_WRITABLE = 18;
const COL_STICKY = 19;
const COL_EXEC = 20;
const COL_MISSING = 21;
const COL_LEFTCODE = 22;
const COL_RIGHTCODE = 23;
const COL_ENDCODE = 24;
const COL_BOLD = 25;
const COL_ITALIC = 26;
// Keep this one last, sets the size of the color_code array:
const DOT_EXTENSION = 27;

// Module-private globals
var color_code: [DOT_EXTENSION + 1][*c]u8 = @splat(null);
var ext: ?*types.Extensions = null;

// Default charset array - moved to module level so it can initialize linedraw
const ansi: [2][*c]const u8 = .{ "ANSI", null };
const latin1_3: [15][*c]const u8 = .{ "ISO-8859-1", "ISO-8859-1:1987", "ISO_8859-1", "latin1", "l1", "IBM819", "CP819", "csISOLatin1", "ISO-8859-3", "ISO_8859-3:1988", "ISO_8859-3", "latin3", "ls", "csISOLatin3", null };
const iso8859_789: [22][*c]const u8 = .{ "ISO-8859-7", "ISO_8859-7:1987", "ISO_8859-7", "ELOT_928", "ECMA-118", "greek", "greek8", "csISOLatinGreek", "ISO-8859-8", "ISO_8859-8:1988", "iso-ir-138", "ISO_8859-8", "hebrew", "csISOLatinHebrew", "ISO-8859-9", "ISO_8859-9:1989", "iso-ir-148", "ISO_8859-9", "latin5", "l5", "csISOLatin5", null };
const shift_jis: [4][*c]const u8 = .{ "Shift_JIS", "MS_Kanji", "csShiftJIS", null };
const euc_jp: [4][*c]const u8 = .{ "EUC-JP", "Extended_UNIX_Code_Packed_Format_for_Japanese", "csEUCPkdFmtJapanese", null };
const euc_kr: [3][*c]const u8 = .{ "EUC-KR", "csEUCKR", null };
const iso2022jp: [5][*c]const u8 = .{ "ISO-2022-JP", "csISO2022JP", "ISO-2022-JP-2", "csISO2022JP2", null };
const ibm_pc: [25][*c]const u8 = .{ "IBM437", "cp437", "437", "csPC8CodePage437", "IBM852", "cp852", "852", "csPCp852", "IBM863", "cp863", "863", "csIBM863", "IBM855", "cp855", "855", "csIBM855", "IBM865", "cp865", "865", "csIBM865", "IBM866", "cp866", "866", "csIBM866", null };
const ibm_ps2: [9][*c]const u8 = .{ "IBM850", "cp850", "850", "csPC850Multilingual", "IBM00858", "CCSID00858", "CP00858", "PC-Multilingual-850+euro", null };
const ibm_gr: [6][*c]const u8 = .{ "IBM869", "cp869", "869", "cp-gr", "csIBM869", null };
const gb: [3][*c]const u8 = .{ "GB2312", "csGB2312", null };
const utf8: [3][*c]const u8 = .{ "UTF-8", "utf8", null };
const big5: [3][*c]const u8 = .{ "Big5", "csBig5", null };
const viscii: [3][*c]const u8 = .{ "VISCII", "csVISCII", null };
const koi8ru: [4][*c]const u8 = .{ "KOI8-R", "csKOI8R", "KOI8-U", null };
const windows: [13][*c]const u8 = .{ "ISO-8859-1-Windows-3.1-Latin-1", "csWindows31Latin1", "ISO-8859-2-Windows-Latin-2", "csWindows31Latin2", "windows-1250", "windows-1251", "windows-1253", "windows-1254", "windows-1255", "windows-1256", "windows-1256", "windows-1257", null };

const cstable = [_]types.LineDraw{
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&ansi))),
        .vert = .{ "\x1B(0x  \x1B(B", "\x1B(0x \x1B(B", "\x1B(0x\x1B(B" },
        .vert_left = .{ "\x1B(0tqq\x1B(B", "\x1B(0tq\x1B(B", "\x1B(0t\x1B(B" },
        .corner = .{ "\x1B(0mqq\x1B(B", "\x1B(0mq\x1B(B", "\x1B(0m\x1B(B" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&latin1_3))),
        .vert = .{ "|  ", "| ", "|" },
        .vert_left = .{ "|--", "|-", "+" },
        .corner = .{ "&middot;--", "&middot;-", "&middot;" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&iso8859_789))),
        .vert = .{ "|  ", "| ", "|" },
        .vert_left = .{ "|--", "|-", "+" },
        .corner = .{ "&middot;--", "&middot;-", "&middot;" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&shift_jis))),
        .vert = .{ "\x84\xA0  ", "\x84\xA0 ", "\x84\xA0" },
        .vert_left = .{ "\x84\xA5\x84\x9F\x84\x9F", "\x84\xA5\x84\x9F", "\x84\xA5" },
        .corner = .{ "\x84\xA4\x84\x9F\x84\x9F", "\x84\xA4\x84\x9F", "\x84\xA4" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&euc_jp))),
        .vert = .{ "\xA8\xA2  ", "\xA8\xA2 ", "\xA8\xA2" },
        .vert_left = .{ "\xA8\xA7\xA8\xA1\xA8\xA1", "\xA8\xA7\xA8\xA1", "\xA8\xA7" },
        .corner = .{ "\xA8\xA6\xA8\xA1\xA8\xA1", "\xA8\xA6\xA8\xA1", "\xA8\xA6" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&euc_kr))),
        .vert = .{ "\xA6\xA2  ", "\xA6\xA2 ", "\xA6\xA2" },
        .vert_left = .{ "\xA6\xA7\xA6\xA1\xA6\xA1", "\xA6\xA7\xA6\xA1", "\xA6\xA7" },
        .corner = .{ "\xA6\xA6\xA6\xA1\xA6\xA1", "\xA6\xA6\xA6\xA1", "\xA6\xA6" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&iso2022jp))),
        .vert = .{ "\x1B$B(\"\x1B(B  ", "\x1B$B(\"\x1B(B ", "\x1B$B(\"\x1B(B" },
        .vert_left = .{ "\x1B$B('\x1B$B(!\x1B$B(!\x1B(B", "\x1B$B('\x1B$B(!\x1B(B", "\x1B$B('\x1B(B" },
        .corner = .{ "\x1B$B(&\x1B$B(!\x1B$B(!\x1B(B", "\x1B$B(&\x1B$B(!\x1B(B", "\x1B$B(&\x1B(B" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&ibm_pc))),
        .vert = .{ "\xB3  ", "\xB3 ", "\xB3" },
        .vert_left = .{ "\xC3\xC4\xC4", "\xC3\xC4", "\xC3" },
        .corner = .{ "\xC0\xC4\xC4", "\xC0\xC4", "\xC0" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&ibm_ps2))),
        .vert = .{ "\xB3  ", "\xB3 ", "\xB3" },
        .vert_left = .{ "\xC3\xC4\xC4", "\xC3\xC4", "\xC3" },
        .corner = .{ "\xC0\xC4\xC4", "\xC0\xC4", "\xC0" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&ibm_gr))),
        .vert = .{ "\xB3  ", "\xB3 ", "\xB3" },
        .vert_left = .{ "\xC3\xC4\xC4", "\xC3\xC4", "\xC3" },
        .corner = .{ "\xC0\xC4\xC4", "\xC0\xC4", "\xC0" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&gb))),
        .vert = .{ "\xA9\xA6  ", "\xA9\xA6 ", "\xA9\xA6" },
        .vert_left = .{ "\xA9\xC0\xA9\xA4\xA9\xA4", "\xA9\xC0\xA9\xA4", "\xA9\xC0" },
        .corner = .{ "\xA9\xB8\xA9\xA4\xA9\xA4", "\xA9\xB8\xA9\xA4", "\xA9\xB8" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&utf8))),
        .vert = .{ "\xE2\x94\x82\xC2\xA0\xC2\xA0", "\xE2\x94\x82\xC2\xA0", "\xE2\x94\x82" },
        .vert_left = .{ "\xE2\x94\x9C\xE2\x94\x80\xE2\x94\x80", "\xE2\x94\x9C\xE2\x94\x80", "\xE2\x94\x9C" },
        .corner = .{ "\xE2\x94\x94\xE2\x94\x80\xE2\x94\x80", "\xE2\x94\x94\xE2\x94\x80", "\xE2\x94\x94" },
        .ctop = " \xE2\x8E\xA7",
        .cbot = " \xE2\x8E\xA9",
        .cmid = " \xE2\x8E\xA8",
        .cext = " \xE2\x8E\xAA",
        .csingle = " {",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&big5))),
        .vert = .{ "\xA2x  ", "\xA2x ", "\xA2x" },
        .vert_left = .{ "\xA2u\xA2w\xA2w", "\xA2u\xA2w", "\xA2u" },
        .corner = .{ "\xA2|\xA2w\xA2w", "\xA2|\xA2w", "\xA2|" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&viscii))),
        .vert = .{ "|  ", "| ", "|" },
        .vert_left = .{ "|--", "|-", "+" },
        .corner = .{ "`--", "`-", "`" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&koi8ru))),
        .vert = .{ "\x81  ", "\x81 ", "\x81" },
        .vert_left = .{ "\x86\x80\x80", "\x86\x80", "\x86" },
        .corner = .{ "\x84\x80\x80", "\x84\x80", "\x84" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = @as([*c][*c]const u8, @ptrCast(@constCast(&windows))),
        .vert = .{ "|  ", "| ", "|" },
        .vert_left = .{ "|--", "|-", "+" },
        .corner = .{ "`--", "`-", "`" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
    .{
        .name = null,
        .vert = .{ "|  ", "| ", "|" },
        .vert_left = .{ "|--", "|-", "+" },
        .corner = .{ "`--", "`-", "`" },
        .ctop = " [",
        .cbot = " [",
        .cmid = " [",
        .cext = " [",
        .csingle = " [",
    },
};

// Exported for use by tree.c and info.zig (mutable, set by initlinedraw)
export var linedraw: [*c]const types.LineDraw = null;

// Hacked in DIR_COLORS support for linux. ------------------------------
//
//  If someone asked me, I'd extend dircolors, to provide more generic
// color support so that more programs could take advantage of it.  This
// is really just hacked in support.  The dircolors program should:
// 1) Put the valid terms in a environment var, like:
//    COLOR_TERMS=linux:console:xterm:vt100...
// 2) Put the COLOR and OPTIONS directives in a env var too.
// 3) Have an option to dircolors to silently ignore directives that it
//    doesn't understand (directives that other programs would
//    understand).
// 4) Perhaps even make those unknown directives environment variables.
//
// The environment is the place for cryptic crap no one looks at, but
// programs.  No one is going to care if it takes 30 variables to do
// something.

//
// char *vgacolor[] = {
//   "black", "red", "green", "yellow", "blue", "fuchsia", "aqua", "white",
//   NULL, NULL,
//   "transparent", "red", "green", "yellow", "blue", "fuchsia", "aqua", "black"
// };
// struct colortable {
//   char *term_flg, *CSS_name, *font_fg, *font_bg;
// } colortable[11];

fn split(str: [*c]u8, delim: [*c]const u8, nwrds: *usize) [*c][*c]u8 {
    var n: usize = 128;
    var w: [*c][*c]u8 = @as([*c][*c]u8, @ptrCast(@alignCast(util.xmalloc(@sizeOf([*c]u8) * n))));

    nwrds.* = 0;
    w[0] = c.strtok(str, delim);

    while (w[nwrds.*] != null) {
        if (nwrds.* == (n - 2)) {
            n += 256;
            w = @as([*c][*c]u8, @ptrCast(@alignCast(util.xrealloc(@as(?*anyopaque, @ptrCast(w)), @sizeOf([*c]u8) * n))));
        }
        nwrds.* += 1;
        w[nwrds.*] = c.strtok(null, delim);
    }

    return w;
}

fn cmd(s: [*c]u8) c_int {
    const cmds = [_]struct { cmd: [*c]const u8, cmdnum: u8 }{
        .{ .cmd = "rs", .cmdnum = COL_RESET },
        .{ .cmd = "no", .cmdnum = COL_NORMAL },
        .{ .cmd = "fi", .cmdnum = COL_FILE },
        .{ .cmd = "di", .cmdnum = COL_DIR },
        .{ .cmd = "ln", .cmdnum = COL_LINK },
        .{ .cmd = "pi", .cmdnum = COL_FIFO },
        .{ .cmd = "do", .cmdnum = COL_DOOR },
        .{ .cmd = "bd", .cmdnum = COL_BLK },
        .{ .cmd = "cd", .cmdnum = COL_CHR },
        .{ .cmd = "or", .cmdnum = COL_ORPHAN },
        .{ .cmd = "so", .cmdnum = COL_SOCK },
        .{ .cmd = "su", .cmdnum = COL_SETUID },
        .{ .cmd = "sg", .cmdnum = COL_SETGID },
        .{ .cmd = "tw", .cmdnum = COL_STICKY_OTHER_WRITABLE },
        .{ .cmd = "ow", .cmdnum = COL_OTHER_WRITABLE },
        .{ .cmd = "st", .cmdnum = COL_STICKY },
        .{ .cmd = "ex", .cmdnum = COL_EXEC },
        .{ .cmd = "mi", .cmdnum = COL_MISSING },
        .{ .cmd = "lc", .cmdnum = COL_LEFTCODE },
        .{ .cmd = "rc", .cmdnum = COL_RIGHTCODE },
        .{ .cmd = "ec", .cmdnum = COL_ENDCODE },
    };

    if (s == null) return ERROR; // Probably can't happen

    if (s[0] == '*') return DOT_EXTENSION;

    for (cmds) |cmd_entry| {
        if (std.mem.eql(u8, c.strSpan(cmd_entry.cmd), c.strSpan(s))) {
            return @as(c_int, cmd_entry.cmdnum);
        }
    }
    return ERROR;
}

pub fn parse_dir_colors() void {
    var arg: [*c][*c]u8 = undefined;
    var c_ptr: [*c][*c]u8 = undefined;
    var colors: [*c]u8 = undefined;
    var s: [*c]const u8 = undefined;
    var i: c_int = 0;
    var col: c_int = 0;
    var cc: c_int = 0;
    var n: usize = 0;
    var e: ?*types.Extensions = undefined;

    if (flag.H) return;

    s = c.getenv("NO_COLOR");
    if (s != null and s[0] != 0) flag.nocolor = true;

    if (c.getenv("TERM") == null) {
        flag.colorize = false;
        return;
    }

    cc = if (c.getenv("CLICOLOR") != null) @as(c_int, 1) else 0;
    if (c.getenv("CLICOLOR_FORCE") != null and !flag.nocolor) flag.force_color = true;
    s = c.getenv("TREE_COLORS");
    if (s == null) s = c.getenv("LS_COLORS");
    if ((s == null or c.strLen(s) == 0) and (flag.force_color or cc != 0)) {
        s = ":no=00:rs=0:fi=00:di=01;34:ln=01;36:pi=40;33:so=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.bat=01;32:*.BAT=01;32:*.btm=01;32:*.BTM=01;32:*.cmd=01;32:*.CMD=01;32:*.com=01;32:*.COM=01;32:*.dll=01;32:*.DLL=01;32:*.exe=01;32:*.EXE=01;32:*.arj=01;31:*.bz2=01;31:*.deb=01;31:*.gz=01;31:*.lzh=01;31:*.rpm=01;31:*.tar=01;31:*.taz=01;31:*.tb2=01;31:*.tbz2=01;31:*.tbz=01;31:*.tgz=01;31:*.tz2=01;31:*.z=01;31:*.Z=01;31:*.zip=01;31:*.ZIP=01;31:*.zoo=01;31:*.asf=01;35:*.ASF=01;35:*.avi=01;35:*.AVI=01;35:*.bmp=01;35:*.BMP=01;35:*.flac=01;35:*.FLAC=01;35:*.gif=01;35:*.GIF=01;35:*.jpg=01;35:*.JPG=01;35:*.jpeg=01;35:*.JPEG=01;35:*.m2a=01;35:*.M2a=01;35:*.m2v=01;35:*.M2V=01;35:*.mov=01;35:*.MOV=01;35:*.mp3=01;35:*.MP3=01;35:*.mpeg=01;35:*.MPEG=01;35:*.mpg=01;35:*.MPG=01;35:*.ogg=01;35:*.OGG=01;35:*.ppm=01;35:*.rm=01;35:*.RM=01;35:*.tga=01;35:*.TGA=01;35:*.tif=01;35:*.TIF=01;35:*.wav=01;35:*.WAV=01;35:*.wmv=01;35:*.WMV=01;35:*.xbm=01;35:*.xpm=01;35:";
    }

    if (s == null or (!flag.force_color and (flag.nocolor or c.isatty(1) == 0))) {
        flag.colorize = false;
        return;
    }

    flag.colorize = true;

    i = 0;
    while (i < DOT_EXTENSION) : (i += 1) {
        color_code[@as(usize, @intCast(i))] = null;
    }

    colors = util.copy(s);

    arg = split(colors, ":", &n);

    i = 0;
    while (arg[@as(usize, @intCast(i))] != null) : (i += 1) {
        c_ptr = split(arg[@as(usize, @intCast(i))], "=", &n);

        col = cmd(c_ptr[0]);
        switch (col) {
            ERROR => {},
            DOT_EXTENSION => {
                if (c_ptr[1] != null) {
                    e = @as(?*types.Extensions, @ptrCast(@alignCast(util.xmalloc(@sizeOf(types.Extensions)))));
                    if (e) |e_val| {
                        e_val.ext = util.copy(c_ptr[0] + 1);
                        e_val.term_flg = util.copy(c_ptr[1]);
                        e_val.nxt = ext;
                        ext = e_val;
                    }
                }
            },
            COL_LINK => {
                if (c_ptr[1] != null and std.ascii.eqlIgnoreCase(c.strSpan(c_ptr[1]), "target")) {
                    flag.linktargetcolor = true;
                    color_code[@as(usize, @intCast(COL_LINK))] = @constCast("01;36"); // Should never actually be used
                } else {
                    // Falls through (matches C default case below)
                    if (c_ptr[1] != null) color_code[@as(usize, @intCast(col))] = util.copy(c_ptr[1]);
                }
            },
            else => {
                if (c_ptr[1] != null) color_code[@as(usize, @intCast(col))] = util.copy(c_ptr[1]);
            },
        }

        c.free(@as(?*anyopaque, @ptrCast(c_ptr)));
    }
    c.free(@as(?*anyopaque, @ptrCast(arg)));

    // Make sure at least reset (not normal) is defined. We're going to assume ANSI/vt100 support:
    if (color_code[@as(usize, @intCast(COL_LEFTCODE))] == null) {
        color_code[@as(usize, @intCast(COL_LEFTCODE))] = util.copy("\x1B[");
    }
    if (color_code[@as(usize, @intCast(COL_RIGHTCODE))] == null) {
        color_code[@as(usize, @intCast(COL_RIGHTCODE))] = util.copy("m");
    }
    if (color_code[@as(usize, @intCast(COL_RESET))] == null) {
        color_code[@as(usize, @intCast(COL_RESET))] = util.copy("0");
    }
    if (color_code[@as(usize, @intCast(COL_BOLD))] == null) {
        const lcode_len = c.strLen(color_code[@as(usize, @intCast(COL_LEFTCODE))]);
        const rcode_len = c.strLen(color_code[@as(usize, @intCast(COL_RIGHTCODE))]);
        color_code[@as(usize, @intCast(COL_BOLD))] = @as([*c]u8, @ptrCast(@alignCast(util.xmalloc(lcode_len + rcode_len + 2))));
        _ = c.sprintf(color_code[@as(usize, @intCast(COL_BOLD))], "%s1%s", color_code[@as(usize, @intCast(COL_LEFTCODE))], color_code[@as(usize, @intCast(COL_RIGHTCODE))]);
    }
    if (color_code[@as(usize, @intCast(COL_ITALIC))] == null) {
        const lcode_len = c.strLen(color_code[@as(usize, @intCast(COL_LEFTCODE))]);
        const rcode_len = c.strLen(color_code[@as(usize, @intCast(COL_RIGHTCODE))]);
        color_code[@as(usize, @intCast(COL_ITALIC))] = @as([*c]u8, @ptrCast(@alignCast(util.xmalloc(lcode_len + rcode_len + 2))));
        _ = c.sprintf(color_code[@as(usize, @intCast(COL_ITALIC))], "%s3%s", color_code[@as(usize, @intCast(COL_LEFTCODE))], color_code[@as(usize, @intCast(COL_RIGHTCODE))]);
    }
    if (color_code[@as(usize, @intCast(COL_ENDCODE))] == null) {
        const lcode_len = c.strLen(color_code[@as(usize, @intCast(COL_LEFTCODE))]);
        const reset_len = c.strLen(color_code[@as(usize, @intCast(COL_RESET))]);
        const rcode_len = c.strLen(color_code[@as(usize, @intCast(COL_RIGHTCODE))]);
        color_code[@as(usize, @intCast(COL_ENDCODE))] = @as([*c]u8, @ptrCast(@alignCast(util.xmalloc(lcode_len + reset_len + rcode_len + 1))));
        _ = c.sprintf(color_code[@as(usize, @intCast(COL_ENDCODE))], "%s%s%s", color_code[@as(usize, @intCast(COL_LEFTCODE))], color_code[@as(usize, @intCast(COL_RESET))], color_code[@as(usize, @intCast(COL_RIGHTCODE))]);
    }

    c.free(@as(?*anyopaque, @ptrCast(colors)));
}

fn print_color(w: *std.Io.Writer, col: c_int) bool {
    const color_u = @as(usize, @intCast(col));
    if (color_code[color_u] == null) return false;
    if (color_code[@as(usize, @intCast(COL_LEFTCODE))]) |p| w.writeAll(std.mem.span(p)) catch {};
    if (color_code[color_u]) |p| w.writeAll(std.mem.span(p)) catch {};
    if (color_code[@as(usize, @intCast(COL_RIGHTCODE))]) |p| w.writeAll(std.mem.span(p)) catch {};
    return true;
}

pub fn endcolor(w: *std.Io.Writer) void {
    if (color_code[@as(usize, @intCast(COL_ENDCODE))]) |p| {
        w.writeAll(std.mem.span(p)) catch {};
    }
}

pub fn fancy(w: *std.Io.Writer, s_in: [*c]u8) void {
    var s = s_in;
    while (s[0] != 0) : (s += 1) {
        switch (s[0]) {
            '\x08' => {
                if (flag.colorize) if (color_code[@as(usize, @intCast(COL_BOLD))]) |p|
                    w.writeAll(std.mem.span(p)) catch {};
            },
            '\x0C' => {
                if (flag.colorize) if (color_code[@as(usize, @intCast(COL_ITALIC))]) |p|
                    w.writeAll(std.mem.span(p)) catch {};
            },
            '\r' => {
                if (flag.colorize) if (color_code[@as(usize, @intCast(COL_ENDCODE))]) |p|
                    w.writeAll(std.mem.span(p)) catch {};
            },
            else => w.writeByte(s[0]) catch {},
        }
    }
}

pub fn colorize(w: *std.Io.Writer, mode: c.mode_t, name: [*c]const u8, orphan: bool, islink: bool) bool {
    var e: ?*types.Extensions = ext;
    var l: usize = 0;
    var xl: usize = 0;

    if (orphan) {
        if (islink) {
            if (print_color(w, COL_MISSING)) return true;
        } else {
            if (print_color(w, COL_ORPHAN)) return true;
        }
    }

    // It's probably safe to assume short-circuit evaluation, but we'll do it this way:
    switch (mode & std.posix.S.IFMT) {
        std.posix.S.IFIFO => return print_color(w, COL_FIFO),
        std.posix.S.IFCHR => return print_color(w, COL_CHR),
        std.posix.S.IFDIR => {
            if ((mode & std.posix.S.ISVTX) != 0) {
                if ((mode & std.posix.S.IWOTH) != 0) {
                    if (print_color(w, COL_STICKY_OTHER_WRITABLE)) return true;
                }
                if ((mode & std.posix.S.IWOTH) == 0) {
                    if (print_color(w, COL_STICKY)) return true;
                }
            }
            if ((mode & std.posix.S.IWOTH) != 0) {
                if (print_color(w, COL_OTHER_WRITABLE)) return true;
            }
            return print_color(w, COL_DIR);
        },
        std.posix.S.IFBLK => return print_color(w, COL_BLK),
        std.posix.S.IFLNK => return print_color(w, COL_LINK),
        else => {},
    }

    // S_IFDOOR is only defined on Solaris/illumos
    if (@hasDecl(std.posix.S, "IFDOOR")) {
        if ((mode & std.posix.S.IFMT) == std.posix.S.IFDOOR) {
            return print_color(w, COL_DOOR);
        }
    }

    if ((mode & std.posix.S.IFMT) == std.posix.S.IFSOCK) {
        return print_color(w, COL_SOCK);
    }

    if ((mode & std.posix.S.IFMT) == std.posix.S.IFREG) {
        if ((mode & std.posix.S.ISUID) != 0) {
            if (print_color(w, COL_SETUID)) return true;
        }
        if ((mode & std.posix.S.ISGID) != 0) {
            if (print_color(w, COL_SETGID)) return true;
        }
        if ((mode & (std.posix.S.IXUSR | std.posix.S.IXGRP | std.posix.S.IXOTH)) != 0) {
            if (print_color(w, COL_EXEC)) return true;
        }

        // not a directory, link, special device, etc, so check for extension match
        l = c.strLen(name);
        while (e != null) : (e = e.?.nxt) {
            xl = c.strLen(e.?.ext);
            const name_ptr: [*c]const u8 = if (l > xl) name + (l - xl) else name;
            if (std.mem.eql(u8, c.strSpan(name_ptr), c.strSpan(e.?.ext))) {
                if (color_code[@as(usize, @intCast(COL_LEFTCODE))]) |p| w.writeAll(std.mem.span(p)) catch {};
                if (e.?.term_flg) |p| w.writeAll(std.mem.span(p)) catch {};
                if (color_code[@as(usize, @intCast(COL_RIGHTCODE))]) |p| w.writeAll(std.mem.span(p)) catch {};
                return true;
            }
        }
        // colorize just normal files too
        return print_color(w, COL_FILE);
    }

    return print_color(w, COL_NORMAL);
}

pub fn initlinedraw(help: bool) void {
    if (help) {
        var i: usize = 0;
        _ = c.fprintf(c.Stderr(), "Valid charsets include:\n");
        while (i < cstable.len) : (i += 1) {
            if (cstable[i].name == null) break;
            var j: usize = 0;
            while (cstable[i].name[j] != null) : (j += 1) {
                _ = c.fprintf(c.Stderr(), "  %s\n", cstable[i].name[j]);
            }
        }
        return;
    }

    // Assume if they need ansilines, then they're probably stuck with a vt100:
    if (flag.ansilines) {
        linedraw = &cstable[0];
        return;
    }

    if (charset != null) {
        var i: usize = 0;
        while (i < cstable.len) : (i += 1) {
            if (cstable[i].name == null) break;
            var j: usize = 0;
            while (cstable[i].name[j] != null) : (j += 1) {
                if (std.ascii.eqlIgnoreCase(c.strSpan(charset), c.strSpan(cstable[i].name[j]))) {
                    linedraw = &cstable[i];
                    return;
                }
            }
        }
    }
    linedraw = &cstable[cstable.len - 1];
}
