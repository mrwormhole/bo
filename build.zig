const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = createExecutable(b, target, optimize);
    b.installArtifact(exe);

    makeRunStep(b, exe);
    makeTestStep(b, target, optimize);
}

fn createExecutable(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "bo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();
    // Add a dedicated include dir that only exposes tree.h to the C importer.
    exe.addIncludePath(b.path("c_include"));

    // strverscmp is linked as a separate object so the symbol is always
    // available to the Zig code, on every platform.
    addZigObject(b, exe, target, optimize, "strverscmp", .{ .link_libc = false, .include_root = false, .defines = false });
    addZigObject(b, exe, target, optimize, "hash", .{ .include_root = false, .defines = false });
    addZigObject(b, exe, target, optimize, "util", .{});
    addZigObject(b, exe, target, optimize, "json", .{});
    addZigObject(b, exe, target, optimize, "xml", .{});
    addZigObject(b, exe, target, optimize, "html", .{});
    addZigObject(b, exe, target, optimize, "list", .{});
    addZigObject(b, exe, target, optimize, "unix", .{});
    addZigObject(b, exe, target, optimize, "info", .{});
    addZigObject(b, exe, target, optimize, "filter", .{});
    addZigObject(b, exe, target, optimize, "file", .{});
    addZigObject(b, exe, target, optimize, "color", .{});

    return exe;
}

const ZigObjectOpts = struct {
    link_libc: bool = true,
    include_root: bool = true,
    defines: bool = true,
};

fn addZigObject(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    opts: ZigObjectOpts,
) void {
    const obj = b.addObject(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/{s}.zig", .{name})),
            .target = target,
            .optimize = optimize,
        }),
    });
    if (opts.link_libc) obj.linkLibC();
    if (opts.include_root) obj.addIncludePath(b.path("."));
    if (opts.defines) addPreprocessorDefines(obj, target);
    exe.addObject(obj);
}

fn addPreprocessorDefines(exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    // Universal defines for large file support
    exe.root_module.addCMacro("LARGEFILE_SOURCE", "");

    const os_tag = target.result.os.tag;
    switch (os_tag) {
        .linux => {
            exe.root_module.addCMacro("_DEFAULT_SOURCE", "");
        },
        .illumos => {
            exe.root_module.addCMacro("_XOPEN_SOURCE", "500");
            exe.root_module.addCMacro("_POSIX_C_SOURCE", "200112");
        },
        else => {},
    }

    if (target.result.abi == .android) {
        exe.root_module.addCMacro("_LARGEFILE64_SOURCE", "");
    }
}

fn makeRunStep(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Allow passing arguments
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the tree command");
    run_step.dependOn(&run_cmd.step);
}

fn makeTestStep(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.linkLibC();
    tests.addIncludePath(b.path("."));
    addPreprocessorDefines(tests, target);

    const test_cmd = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_cmd.step);
}
