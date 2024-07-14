const std = @import("std");

const example_list = [_][]const u8{
    "gem2html",
    "gem2md",
    "streaming-parser",
};

pub fn build(b: *std.Build) void {
    const gemtext = b.addModule("gemtext", .{
        .root_source_file = b.path("src/gemtext.zig"),
    });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zig-gemtext",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(b.path("include")); // Import the C types via translate-c
    lib.linkLibC();
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    var lib_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    //lib_tests.linkLibrary(lib);
    lib_tests.linkLibC();
    lib_tests.addIncludePath(b.path("include"));

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(main_tests).step);
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);

    const examples = b.step("examples", "Builds all examples");

    inline for (example_list) |example_name| {
        {
            const example = b.addExecutable(.{
                .name = example_name ++ "-zig",
                .root_source_file = b.path("examples/" ++ example_name ++ ".zig"),
                .target = target,
            });

            example.root_module.addImport("gemtext", gemtext);
            examples.dependOn(&b.addInstallArtifact(example, .{}).step);
        }
        {
            const example = b.addExecutable(.{
                .name = example_name ++ "-c",
                .target = target,
            });
            example.addCSourceFile(.{
                .file = b.path("examples/" ++ example_name ++ ".c"),
                .flags = &[_][]const u8{
                    "-std=c11",
                    "-Weverything",
                },
            });

            example.linkLibrary(lib);
            example.addIncludePath(b.path("include"));
            example.linkLibC();

            examples.dependOn(&b.addInstallArtifact(example, .{}).step);
        }
    }
}
