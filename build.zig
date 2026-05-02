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
    exe.addAfterIncludePath(b.path("."));
    addPreprocessorDefines(exe, target);

    return exe;
}

// TODO: Remove these C feature macros once the remaining C-imported file and
// platform types/macros are migrated to Zig stdlib types:
// - types/handles: c.off_t, c.dev_t, c.ino_t, c.mode_t, c.time_t, c.uid_t,
//   c.gid_t, c.u_long, c.struct_stat, c.struct_dirent, c.DIR, c.FILE
// - filesystem constants: c.PATH_MAX, c.S_IF*, c.S_IR*, c.S_IW*, c.S_IX*,
//   c.S_ISUID, c.S_ISGID, c.S_ISVTX
// - Linux/project macros: c.ENV_STDDATA_FD, c.STDDATA_FILENO, c.F_GETFD,
//   c.INFO_PATH, c.MINIT, c.MINC
// - locale macros: c.LC_CTYPE, c.LC_COLLATE, c.LC_TIME, c.CODESET
fn addPreprocessorDefines(exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    // Universal defines for large file support
    exe.root_module.addCMacro("_LARGEFILE_SOURCE", "");

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
            .root_source_file = b.path("src/tests.zig"),
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
