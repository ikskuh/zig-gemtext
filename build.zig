const std = @import("std");

const example_list = [_][]const u8{
    "gem2html",
    "gem2md",
    "streaming-parser",
};

pub fn build(b: *std.build.Builder) void {
    const gemtext = b.createModule(.{
        .source_file = .{ .path = "src/gemtext.zig" },
    });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zig-gemtext",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(.{ .path = "include" }); // Import the C types via translate-c
    lib.linkLibC();
    b.installArtifact(lib);

    var main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });

    var lib_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    //lib_tests.linkLibrary(lib);
    lib_tests.linkLibC();
    lib_tests.addIncludePath(.{ .path = "include" });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(main_tests).step);
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);

    const examples = b.step("examples", "Builds all examples");

    inline for (example_list) |example_name| {
        {
            const example = b.addExecutable(.{
                .name = example_name ++ "-zig",
                .root_source_file = .{ .path = "examples/" ++ example_name ++ ".zig" },
            });

            example.addModule("gemtext", gemtext);

            examples.dependOn(&b.addInstallArtifact(example, .{}).step);
        }
        {
            const example = b.addExecutable(.{
                .name = example_name ++ "-c",
            });
            example.addCSourceFile(.{
                .file = .{ .path = "examples/" ++ example_name ++ ".c" },
                .flags = &[_][]const u8{
                    "-std=c11",
                    "-Weverything",
                },
            });

            example.linkLibrary(lib);
            example.addIncludePath(.{ .path = "include" });
            example.linkLibC();

            examples.dependOn(&b.addInstallArtifact(example, .{}).step);
        }
    }
}
