const std = @import("std");

// Note: Windows native is not supported (tree.c requires POSIX).
// Use Cygwin for Windows builds.

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = createExecutable(b, target, optimize);
    b.installArtifact(exe);

    makeRunStep(b, exe);
}

fn createExecutable(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const common_sources = [_][]const u8{
        "tree.c",
        "list.c",
        "hash.c",
        "color.c",
        "file.c",
        "filter.c",
        "info.c",
        "unix.c",
        "xml.c",
        "json.c",
        "html.c",
    };

    var sources_buf: [12][]const u8 = undefined;
    var num_sources: usize = 0;

    for (common_sources) |src| {
        sources_buf[num_sources] = src;
        num_sources += 1;
    }

    // Conditionally include strverscmp.c
    // Only include strverscmp.c if not Linux or if Android
    const needs_strverscmp = target.result.os.tag != .linux or target.result.abi == .android;
    if (needs_strverscmp) {
        sources_buf[num_sources] = "strverscmp.c";
        num_sources += 1;
    }

    const exe = b.addExecutable(.{
        .name = "bo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const sources = sources_buf[0..num_sources];
    const cflags = &[_][]const u8{
        "-std=c11",
        "-Wpedantic",
        "-Wall",
        "-Wextra",
        "-Wstrict-prototypes",
        "-Wshadow",
        "-Wconversion",
    };
    exe.addCSourceFiles(.{
        .files = sources,
        .flags = cflags,
    });
    addPreprocessorDefines(exe, target);
    exe.linkLibC();
    return exe;
}

fn addPreprocessorDefines(exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    // Universal defines for large file support
    exe.root_module.addCMacro("LARGEFILE_SOURCE", "");
    exe.root_module.addCMacro("_FILE_OFFSET_BITS", "64");

    const os_tag = target.result.os.tag;
    switch (os_tag) {
        .linux => {
            exe.root_module.addCMacro("_GNU_SOURCE", "");
        },
        .solaris, .illumos => {
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
