const std = @import("std");
const builtin = @import("builtin");

pub const FILE = std.c.FILE;
pub const DIR = std.c.DIR;

pub const off_t = std.c.off_t;
pub const dev_t = std.c.dev_t;
pub const ino_t = std.c.ino_t;
pub const mode_t = std.c.mode_t;
pub const time_t = std.c.time_t;
pub const uid_t = std.c.uid_t;
pub const gid_t = std.c.gid_t;
pub const u_long = c_ulong;

pub const struct_stat = std.c.Stat;

pub const struct_dirent = switch (builtin.os.tag) {
    .linux => extern struct {
        d_ino: ino_t,
        d_off: off_t,
        d_reclen: c_ushort,
        d_type: u8,
        d_name: [256]u8,
    },
    .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => extern struct {
        d_ino: u64,
        d_seekoff: u64,
        d_reclen: u16,
        d_namlen: u16,
        d_type: u8,
        d_name: [1024]u8,
    },
    .freebsd => extern struct {
        d_fileno: ino_t,
        d_off: off_t,
        d_reclen: u16,
        d_type: u8,
        d_pad0: u8 = 0,
        d_namlen: u16,
        d_pad1: u16 = 0,
        d_name: [255:0]u8,
    },
    .illumos => extern struct {
        d_ino: ino_t,
        d_off: off_t,
        d_reclen: u16,
        d_name: [std.c.MAXNAMLEN:0]u8,
    },
    .netbsd => extern struct {
        d_fileno: ino_t,
        d_reclen: u16,
        d_namlen: u16,
        d_type: u8,
        d_name: [std.c.MAXNAMLEN:0]u8,
    },
    .dragonfly => extern struct {
        d_fileno: c_ulong,
        d_namlen: u16,
        d_type: u8,
        d_unused1: u8,
        d_unused2: u32,
        d_name: [256]u8,
    },
    .openbsd => extern struct {
        d_fileno: ino_t,
        d_off: off_t,
        d_reclen: u16,
        d_type: u8,
        d_namlen: u8,
        _: u32 align(1) = 0,
        d_name: [std.c.MAXNAMLEN:0]u8,
    },
    else => std.c.dirent,
};

pub const LC_CTYPE: c_int = switch (builtin.os.tag) {
    .linux, .emscripten => 0,
    .freebsd, .netbsd, .openbsd, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => 2,
    else => 0,
};
pub const LC_TIME: c_int = switch (builtin.os.tag) {
    .linux, .emscripten => 2,
    .freebsd, .netbsd, .openbsd, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => 5,
    else => 2,
};
pub const LC_COLLATE: c_int = switch (builtin.os.tag) {
    .linux, .emscripten => 3,
    .freebsd, .netbsd, .openbsd, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => 1,
    else => 3,
};
pub const CODESET: c_int = switch (builtin.os.tag) {
    .freebsd, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => 0,
    .netbsd, .openbsd => 51,
    else => 14,
};

pub const EXIT_FAILURE: c_int = 1;

pub const MINIT: usize = 30; // Initial dir entry allocation
pub const MINC: usize = 20; // Allocation increment
pub const INFO_PATH: [*:0]const u8 = "/usr/share/finfo/global_info";

const tm = opaque {};

pub extern "c" fn malloc(size: usize) ?*anyopaque;
pub extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
pub extern "c" fn free(ptr: ?*anyopaque) void;
pub extern "c" fn memcpy(noalias dest: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;

pub extern "c" fn strlen(s: [*c]const u8) usize;
pub extern "c" fn strcmp(s1: [*c]const u8, s2: [*c]const u8) c_int;
pub extern "c" fn strncmp(s1: [*c]const u8, s2: [*c]const u8, n: usize) c_int;
pub extern "c" fn strcasecmp(s1: [*c]const u8, s2: [*c]const u8) c_int;
pub extern "c" fn strchr(s: [*c]const u8, c: c_int) [*c]u8;
pub extern "c" fn strrchr(s: [*c]const u8, c: c_int) [*c]u8;
pub extern "c" fn strstr(haystack: [*c]const u8, needle: [*c]const u8) [*c]u8;
pub extern "c" fn strcpy(noalias dest: [*c]u8, noalias src: [*c]const u8) [*c]u8;
pub extern "c" fn strtok(noalias str: [*c]u8, noalias delim: [*c]const u8) [*c]u8;
pub extern "c" fn strcoll(s1: [*c]const u8, s2: [*c]const u8) c_int;
pub extern "c" fn strtoul(noalias nptr: [*c]const u8, noalias endptr: ?*[*c]u8, base: c_int) c_ulong;

pub extern "c" fn sprintf(noalias s: [*c]u8, noalias format: [*c]const u8, ...) c_int;
pub extern "c" fn snprintf(noalias s: [*c]u8, maxlen: usize, noalias format: [*c]const u8, ...) c_int;
pub extern "c" fn fprintf(noalias stream: ?*FILE, noalias format: [*c]const u8, ...) c_int;
pub extern "c" fn printf(noalias format: [*c]const u8, ...) c_int;

pub extern "c" fn atoi(nptr: [*c]const u8) c_int;
pub extern "c" fn exit(status: c_int) noreturn;

pub extern "c" fn fopen(noalias filename: [*c]const u8, noalias mode: [*c]const u8) ?*FILE;
pub extern "c" fn fgets(noalias s: [*c]u8, size: c_int, noalias stream: ?*FILE) [*c]u8;
pub extern "c" fn fread(noalias ptr: [*c]u8, size: usize, nmemb: usize, noalias stream: ?*FILE) usize;
pub extern "c" fn fclose(stream: ?*FILE) c_int;

pub extern "c" fn opendir(name: [*c]const u8) ?*DIR;
pub extern "c" fn readdir(dirp: ?*DIR) ?*struct_dirent;
pub extern "c" fn closedir(dirp: ?*DIR) c_int;

pub extern "c" fn lstat(noalias path: [*c]const u8, noalias buf: *struct_stat) c_int;
pub extern "c" fn stat(noalias path: [*c]const u8, noalias buf: *struct_stat) c_int;
pub extern "c" fn readlink(noalias path: [*c]const u8, noalias buf: [*c]u8, bufsiz: usize) isize;
pub extern "c" fn realpath(noalias path: [*c]const u8, noalias resolved_path: [*c]u8) [*c]u8;
pub extern "c" fn gethostname(name: [*c]u8, len: usize) c_int;
pub extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;

pub extern "c" fn getenv(name: [*c]const u8) [*c]u8;
pub extern "c" fn isatty(fd: c_int) c_int;
pub extern "c" fn setlocale(category: c_int, locale: [*c]const u8) [*c]u8;
pub extern "c" fn nl_langinfo(item: c_int) [*c]u8;

pub extern "c" fn time(tloc: ?*time_t) time_t;
pub extern "c" fn localtime(timer: *const time_t) ?*tm;
pub extern "c" fn strftime(noalias s: [*c]u8, maxsize: usize, noalias format: [*c]const u8, noalias timeptr: ?*const tm) usize;

pub extern "c" fn isprint(c: c_int) c_int;
pub extern "c" fn isalnum(c: c_int) c_int;
pub extern "c" fn isdigit(c: c_int) c_int;
pub extern "c" fn isspace(c: c_int) c_int;
pub extern "c" fn tolower(c: c_int) c_int;

extern "c" var stdin: ?*FILE;
extern "c" var stdout: ?*FILE;
extern "c" var stderr: ?*FILE;
extern "c" var __stdinp: ?*FILE;
extern "c" var __stdoutp: ?*FILE;
extern "c" var __stderrp: ?*FILE;

pub fn cStdin() ?*FILE {
    return switch (builtin.os.tag) {
        .linux => stdin,
        else => __stdinp,
    };
}

pub fn Stdout() ?*FILE {
    return switch (builtin.os.tag) {
        .linux => stdout,
        else => __stdoutp,
    };
}

pub fn Stderr() ?*FILE {
    return switch (builtin.os.tag) {
        .linux => stderr,
        else => __stderrp,
    };
}

pub fn strSpan(s: [*c]const u8) [:0]const u8 {
    return std.mem.span(@as([*:0]const u8, @ptrCast(s)));
}

pub fn strLen(s: [*c]const u8) usize {
    return strSpan(s).len;
}
