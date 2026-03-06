const std = @import("std");

const man = @import("man.zig");
const strverscmp = @import("strverscmp.zig");

const c = @cImport({
    @cDefine("_DEFAULT_SOURCE", "");
    @cInclude("tree.h");
});

// Import C main fn (tree_main still lives in tree.c for now)
extern fn tree_main(argc: c_int, argv: [*][*:0]u8) c_int;

// Include tests from imported modules
test {
    _ = strverscmp;
}

// ----------------------------------------------------------------------------
// Globals migrated from tree.c
//
// All are exported with C linkage so the remaining C files can reference them
// via the existing `extern` declarations.  The function-pointer globals
// (getfulltree, basesort, topsort) and the conditional mode-type tables
// (ifmt/fmt/ftype) stay in tree.c until the functions that own them move here.
// ----------------------------------------------------------------------------

var version_lit = "bo (The Bodhi Tree) v0.0.2".*;
export var version: [*c]u8 = @ptrCast(&version_lit);

// Option flags
export var dflag: bool = false;
export var lflag: bool = false;
export var pflag: bool = false;
export var sflag: bool = false;
export var Fflag: bool = false;
export var aflag: bool = false;
export var fflag: bool = false;
export var uflag: bool = false;
export var gflag: bool = false;

export var qflag: bool = false;
export var Nflag: bool = false;
export var Qflag: bool = false;
export var Dflag: bool = false;
export var inodeflag: bool = false;
export var devflag: bool = false;
export var hflag: bool = false;
export var Rflag: bool = false;

export var Hflag: bool = false;
export var siflag: bool = false;
export var cflag: bool = false;
export var Xflag: bool = false;
export var Jflag: bool = false;
export var duflag: bool = false;
export var pruneflag: bool = false;
export var hyperflag: bool = false;

export var noindent: bool = false;
export var force_color: bool = false;
export var nocolor: bool = false;
export var xdev: bool = false;
export var noreport: bool = false;
export var nolinks: bool = false;

export var ignorecase: bool = false;
export var matchdirs: bool = false;
export var fromfile: bool = false;
export var metafirst: bool = false;
export var gitignore: bool = false;
export var showinfo: bool = false;

export var reverse: bool = false;
export var fflinks: bool = false;
export var htmloffset: bool = false;

export var flimit: c_int = 0;

// Output format dispatch table; tree_main() initialises the fields before use.
export var lc: c.struct_listingcalls = std.mem.zeroes(c.struct_listingcalls);

// Pattern matching state
export var pattern: c_int = 0;
export var maxpattern: c_int = 0;
export var ipattern: c_int = 0;
export var maxipattern: c_int = 0;
export var patterns: [*c][*c]u8 = null;
export var ipatterns: [*c][*c]u8 = null;

// String/pointer options
export var host: [*c]u8 = null;
var title_lit = "Directory Tree".*;
export var title: [*c]u8 = @ptrCast(&title_lit);
var sp_lit = " ".*;
export var sp: [*c]u8 = @ptrCast(&sp_lit);
var nl_lit = "\n".*;
export var _nl: [*c]u8 = @ptrCast(&nl_lit);
export var Hintro: [*c]u8 = null;
export var Houtro: [*c]u8 = null;
var scheme_lit = "file://".*;
export var scheme: [*c]u8 = @ptrCast(&scheme_lit);
export var authority: [*c]u8 = null;
var file_comment_lit = "#".*;
export var file_comment: [*c]u8 = @ptrCast(&file_comment_lit);
var file_pathsep_lit = "/".*;
export var file_pathsep: [*c]u8 = @ptrCast(&file_pathsep_lit);
export var timefmt: [*c]u8 = null;
export var charset: [*c]const u8 = null;

// Directory traversal state
export var sLevel: [*c]u8 = null;
export var curdir: [*c]u8 = null;
export var outfile: ?*c.FILE = null;
export var dirs: [*c]c_int = null;
export var Level: isize = 0;
export var maxdirs: usize = 0;
export var errors: c_int = 0;

// Scratch buffer; 4096 == PATH_MAX on Linux/macOS.
export var xpattern: [4096]u8 = std.mem.zeroes([4096]u8);

export var mb_cur_max: c_int = 0;

// ----------------------------------------------------------------------------
// Memory / directory utility functions migrated from tree.c (Phase 3)
//
// All four are called from other C files, so they keep export + callconv(.C).
// xmalloc/xrealloc mirror the C originals: exit on allocation failure so
// callers never need to handle a null return.
// ----------------------------------------------------------------------------

fn oom() noreturn {
    std.debug.print("tree: virtual memory exhausted.\n", .{});
    std.process.exit(1);
}

export fn xmalloc(size: usize) ?*anyopaque {
    return c.malloc(size) orelse oom();
}

export fn xrealloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    return c.realloc(ptr, size) orelse oom();
}

// Free a null-terminated array of _info pointers (and each entry's strings).
export fn free_dir(d: [*c]?*c.struct__info) void {
    var i: usize = 0;
    while (d[i]) |entry| : (i += 1) {
        c.free(@ptrCast(entry.name));
        if (entry.lnk != null) c.free(@ptrCast(entry.lnk));
        c.free(@ptrCast(entry));
    }
    c.free(@ptrCast(d));
}

// Grow-and-retry wrapper around getcwd(); caller owns the returned buffer.
export fn gnu_getcwd() [*c]u8 {
    var size: usize = 100;
    var buf: [*c]u8 = @ptrCast(xmalloc(size));
    while (true) {
        if (c.getcwd(buf, size) != null) return buf;
        size *= 2;
        c.free(@ptrCast(buf));
        buf = @ptrCast(xmalloc(size));
    }
}

// ----------------------------------------------------------------------------
// Pattern matching functions migrated from tree.c (Phase 4 — idiomatic Zig)
//
// patmatch/patignore/patinclude are all declared in tree.h, so the export
// symbols satisfy any remaining C callers (e.g. filter.c calls patmatch).
// ----------------------------------------------------------------------------

fn condLower(ch: u8) u8 {
    return if (ignorecase) std.ascii.toLower(ch) else ch;
}

/// Glob pattern match — idiomatic Zig core (slices, no pointer arithmetic).
/// Returns 1 on match, 0 on mismatch, -1 on pattern syntax error.
fn patMatchSlice(buf_in: []const u8, pat_in: []const u8, isdir: bool) c_int {
    // '|' alternation: try left side, then right side.
    if (std.mem.indexOfScalar(u8, pat_in, '|')) |bar| {
        if (bar == 0 or bar == pat_in.len - 1) return -1;
        const left = patMatchSlice(buf_in, pat_in[0..bar], isdir);
        if (left != 0) return left;
        return patMatchSlice(buf_in, pat_in[bar + 1 ..], isdir);
    }

    var buf = buf_in;
    var pat = pat_in;
    var match: c_int = 1;
    var pprev: u8 = 0;

    while (pat.len > 0 and match > 0) {
        switch (pat[0]) {
            '[' => {
                pat = pat[1..]; // consume '['
                // Negated class [^...]: hit value 0 means "found → no match".
                // Normal class  [...]:  hit value 1 means "found → match".
                const hit: c_int = if (pat.len > 0 and pat[0] == '^') blk: {
                    pat = pat[1..]; // consume '^'
                    break :blk 0;
                } else blk: {
                    match = 0; // unmatched until we find a class member
                    break :blk 1;
                };
                inner: while (pat.len > 0 and pat[0] != ']') {
                    if (pat[0] == '\\') pat = pat[1..];
                    if (pat.len == 0) return -1; // unterminated escape
                    if (pat.len > 1 and pat[1] == '-') {
                        const lo = pat[0];
                        pat = pat[2..]; // consume lo and '-'
                        if (pat.len > 0 and pat[0] == '\\') pat = pat[1..];
                        if (buf.len > 0 and
                            condLower(buf[0]) >= condLower(lo) and
                            condLower(buf[0]) <= condLower(pat[0]))
                        {
                            match = hit;
                        }
                        if (pat.len == 0) break :inner; // range end was last char
                    } else {
                        if (buf.len > 0 and condLower(buf[0]) == condLower(pat[0]))
                            match = hit;
                    }
                    pat = pat[1..];
                }
                if (pat.len == 0) return -1; // unterminated '['
                // pat[0] is ']'; outer loop will advance past it.
                if (buf.len > 0) buf = buf[1..];
            },
            '*' => {
                pat = pat[1..]; // consume first '*'
                if (pat.len == 0) {
                    // Trailing '*' matches any name without a '/'.
                    return @intFromBool(std.mem.indexOfScalar(u8, buf, '/') == null);
                }
                match = 0;
                if (pat[0] == '*') {
                    pat = pat[1..]; // consume second '*'
                    if (pat.len == 0) return 1; // trailing '**' matches everything
                    while (buf.len > 0) {
                        const m = patMatchSlice(buf, pat, isdir);
                        match = m;
                        if (m != 0) break;
                        // '**' between two '/'s may match an empty path component.
                        if (pprev == '/' and pat[0] == '/' and pat.len > 1) {
                            const m2 = patMatchSlice(buf, pat[1..], isdir);
                            if (m2 != 0) return m2;
                        }
                        buf = buf[1..];
                        while (buf.len > 0 and buf[0] != '/') buf = buf[1..];
                    }
                } else {
                    // Single '*': match any sequence not containing '/'.
                    while (buf.len > 0) {
                        const m = patMatchSlice(buf, pat, isdir);
                        buf = buf[1..]; // mirrors C's buf++ in loop condition
                        if (m != 0) { match = m; break; }
                        if (buf.len > 0 and buf[0] == '/') break;
                    }
                }
                if (match == 0 and (buf.len == 0 or buf[0] == '/'))
                    match = patMatchSlice(buf, pat, isdir);
                return match;
            },
            '?' => {
                if (buf.len == 0) return 0;
                buf = buf[1..];
            },
            '/' => {
                // Trailing '/' matches empty buf only when path is a directory.
                if (pat.len == 1 and buf.len == 0) return @intFromBool(isdir);
                match = @intFromBool(buf.len > 0 and buf[0] == pat[0]);
                if (buf.len > 0) buf = buf[1..];
            },
            '\\' => {
                pat = pat[1..]; // consume backslash; next char is literal
                if (pat.len == 0) break;
                match = @intFromBool(buf.len > 0 and condLower(buf[0]) == condLower(pat[0]));
                if (buf.len > 0) buf = buf[1..];
            },
            else => {
                match = @intFromBool(buf.len > 0 and condLower(buf[0]) == condLower(pat[0]));
                if (buf.len > 0) buf = buf[1..];
            },
        }
        pprev = pat[0];
        pat = pat[1..];
        if (match < 1) return match;
    }
    return if (buf.len == 0) match else 0;
}

/// C-exported entry point: converts C strings to slices and delegates.
export fn patmatch(buf_ptr: [*c]const u8, pat_ptr: [*c]const u8, isdir: bool) c_int {
    return patMatchSlice(std.mem.span(buf_ptr), std.mem.span(pat_ptr), isdir);
}

/// Returns non-zero if name matches any -I (ignore) pattern.
export fn patignore(name: [*c]const u8, isdir: bool) c_int {
    for (0..@as(usize, @intCast(ipattern))) |i| {
        if (patmatch(name, ipatterns[i], isdir) != 0) return 1;
    }
    return 0;
}

/// Returns non-zero if name matches any -P (include) pattern.
export fn patinclude(name: [*c]const u8, isdir: bool) c_int {
    for (0..@as(usize, @intCast(pattern))) |i| {
        if (patmatch(name, patterns[i], isdir) != 0) return 1;
    }
    return 0;
}

// ----------------------------------------------------------------------------

pub fn printStdout(content: []const u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(content);
    try stdout.flush();
}

pub fn main() !u8 {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "man")) {
        try printStdout(man.content);
        return 0;
    }

    // Otherwise call C, must convert [:0]const u8 slice to [*:0]u8 for C
    var c_args = try allocator.alloc([*:0]u8, args.len);
    defer allocator.free(c_args);

    for (args, 0..) |arg, i| {
        c_args[i] = arg.ptr;
    }

    const c_argc: c_int = @intCast(args.len);
    const result = tree_main(c_argc, c_args.ptr);

    return if (result >= 0) @intCast(result) else 1;
}
