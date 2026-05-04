const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = b.option(bool, "use-llvm", "Use LLVM as the codegen backend");
    const use_lld = b.option(bool, "use-lld", "Use LLD as the linker");

    const exe = createExecutable(b, target, optimize, use_llvm, use_lld);
    b.installArtifact(exe);

    makeRunStep(b, exe);
    makeTestStep(b, target, optimize);
}

fn createExecutable(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, use_llvm: ?bool, use_lld: ?bool) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "bo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.use_llvm = use_llvm;
    exe.use_lld = use_lld;
    exe.root_module.linkSystemLibrary("c", .{});

    return exe;
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
    tests.root_module.linkSystemLibrary("c", .{});

    const test_cmd = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_cmd.step);
}
