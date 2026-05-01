const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

pub const Flags = extern struct {
    a: bool,
    c: bool,
    d: bool,
    f: bool,
    g: bool,
    h: bool,
    l: bool,
    p: bool,
    q: bool,
    s: bool,
    u: bool,
    D: bool,
    F: bool,
    H: bool,
    J: bool,
    N: bool,
    Q: bool,
    R: bool,
    X: bool,
    inode: bool,
    dev: bool,
    si: bool,
    du: bool,
    prune: bool,
    hyper: bool,
    noindent: bool,
    force_color: bool,
    nocolor: bool,
    xdev: bool,
    noreport: bool,
    nolinks: bool,
    ignorecase: bool,
    matchdirs: bool,
    fromfile: bool,
    metafirst: bool,
    gitignore: bool,
    showinfo: bool,
    reverse: bool,
    fflinks: bool,
    htmloffset: bool,
    acl: bool,
    selinux: bool,
    condense_singletons: bool,
    colorize: bool,
    ansilines: bool,
    linktargetcolor: bool,
    remove_space: bool,
    flimit: i32,
    compress_indent: i32,
};

const InfoLinux = extern struct {
    name: [*c]u8,
    lnk: [*c]u8,
    isdir: bool,
    issok: bool,
    isfifo: bool,
    isexe: bool,
    orphan: bool,
    hasacl: bool,
    secontext: [*c]u8,
    mode: posix.mode_t,
    lnkmode: posix.mode_t,
    uid: std.c.uid_t,
    gid: std.c.gid_t,
    size: posix.off_t,
    atime: posix.time_t,
    ctime: posix.time_t,
    mtime: posix.time_t,
    dev: posix.dev_t,
    ldev: posix.dev_t,
    inode: posix.ino_t,
    linode: posix.ino_t,
    err: [*c]u8,
    tag: [*c]const u8,
    condensed: usize,
    comment: [*c][*c]u8,
    child: [*c][*c]InfoLinux,
    next: ?*InfoLinux,
    tchild: ?*InfoLinux,
};

const InfoOther = extern struct {
    name: [*c]u8,
    lnk: [*c]u8,
    isdir: bool,
    issok: bool,
    isfifo: bool,
    isexe: bool,
    orphan: bool,
    mode: posix.mode_t,
    lnkmode: posix.mode_t,
    uid: std.c.uid_t,
    gid: std.c.gid_t,
    size: posix.off_t,
    atime: posix.time_t,
    ctime: posix.time_t,
    mtime: posix.time_t,
    dev: posix.dev_t,
    ldev: posix.dev_t,
    inode: posix.ino_t,
    linode: posix.ino_t,
    err: [*c]u8,
    tag: [*c]const u8,
    condensed: usize,
    comment: [*c][*c]u8,
    child: [*c][*c]InfoOther,
    next: ?*InfoOther,
    tchild: ?*InfoOther,
};

pub const Info = if (builtin.os.tag == .linux) InfoLinux else InfoOther;

pub const Extensions = extern struct {
    ext: [*c]u8,
    term_flg: [*c]u8,
    nxt: ?*Extensions,
};

pub const LineDraw = extern struct {
    name: [*c][*c]const u8,
    vert: [3][*c]const u8,
    vert_left: [3][*c]const u8,
    corner: [3][*c]const u8,
    ctop: [*c]const u8,
    cbot: [*c]const u8,
    cmid: [*c]const u8,
    cext: [*c]const u8,
    csingle: [*c]const u8,
};

pub const MetaIds = extern struct {
    name: [*c]u8,
    term_flg: [*c]u8,
};

pub const Pattern = extern struct {
    pattern: [*c]u8,
    relative: c_int,
    next: ?*Pattern,
};

pub const IgnoreFile = extern struct {
    path: [*c]u8,
    remove: ?*Pattern,
    reverse: ?*Pattern,
    next: ?*IgnoreFile,
};

pub const Comment = extern struct {
    pattern: ?*Pattern,
    desc: [*c][*c]u8,
    next: ?*Comment,
};

pub const InfoFile = extern struct {
    path: [*c]u8,
    comments: ?*Comment,
    next: ?*InfoFile,
};

pub const Totals = extern struct {
    files: usize,
    dirs: usize,
    size: posix.off_t,
};

pub const ListingCalls = struct {
    intro: *const fn () void,
    outtro: *const fn () void,
    printinfo: *const fn ([*c]u8, ?*Info, c_int) c_int,
    printfile: *const fn ([*c]u8, [*c]u8, ?*Info, c_int) c_int,
    @"error": *const fn ([*c]u8) c_int,
    newline: *const fn (?*Info, c_int, c_int, c_int) void,
    close: *const fn (?*Info, c_int, c_int) void,
    report: *const fn (Totals) void,
};
