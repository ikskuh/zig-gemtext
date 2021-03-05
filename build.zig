const std = @import("std");

const pkgs = struct {
    const gemtext = std.build.Pkg{
        .name = "gemtext",
        .path = "src/gemtext.zig",
    };
};

const example_list = [_][]const u8{
    "gem2html",
    "gem2md",
};

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("zig-gemtext", "src/lib.zig");
    lib.setBuildMode(mode);
    lib.setTarget(target);
    lib.install();

    var main_tests = b.addTest("src/tests.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const examples = b.step("examples", "Builds all examples");

    inline for (example_list) |example_name| {
        const example = b.addExecutable(example_name, "examples/" ++ example_name ++ ".zig");

        example.setBuildMode(mode);
        example.setTarget(target);
        example.addPackage(pkgs.gemtext);

        examples.dependOn(&b.addInstallArtifact(example).step);
    }
}
