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
