const std = @import("std");

// Note: Windows native is not supported (tree.c requires POSIX).

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = createExecutable(b, target, optimize);
    b.installArtifact(exe);

    makeRunStep(b, exe);
    makeTestStep(b, target, optimize);
}

fn createExecutable(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const common_sources = [_][]const u8{
        "tree.c",
        "list.c",
        "color.c",
        "file.c",
        "filter.c",
        "info.c",
        "unix.c",
        "html.c",
    };

    var sources_buf: [8][]const u8 = undefined;
    var num_sources: usize = 0;

    for (common_sources) |src| {
        sources_buf[num_sources] = src;
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

    // Compile our strverscmp implementation as a separate object so the
    // symbol is always available to the C code, on every platform.
    const strverscmp_obj = b.addObject(.{
        .name = "strverscmp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/strverscmp.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.addObject(strverscmp_obj);

    const hash_obj = b.addObject(.{
        .name = "hash",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/hash.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hash_obj.linkLibC();
    exe.addObject(hash_obj);

    const path_obj = b.addObject(.{
        .name = "util",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/util.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    path_obj.linkLibC();
    path_obj.addIncludePath(b.path("."));
    addPreprocessorDefines(path_obj, target);
    exe.addObject(path_obj);

    const json_obj = b.addObject(.{
        .name = "json",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/json.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    json_obj.linkLibC();
    json_obj.addIncludePath(b.path("."));
    addPreprocessorDefines(json_obj, target);
    exe.addObject(json_obj);

    const xml_obj = b.addObject(.{
        .name = "xml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/xml.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    xml_obj.linkLibC();
    xml_obj.addIncludePath(b.path("."));
    addPreprocessorDefines(xml_obj, target);
    exe.addObject(xml_obj);

    return exe;
}

fn addPreprocessorDefines(exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    // Universal defines for large file support
    exe.root_module.addCMacro("LARGEFILE_SOURCE", "");
    exe.root_module.addCMacro("_FILE_OFFSET_BITS", "64");

    const os_tag = target.result.os.tag;
    switch (os_tag) {
        .linux => {
            exe.root_module.addCMacro("_DEFAULT_SOURCE", "");
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
