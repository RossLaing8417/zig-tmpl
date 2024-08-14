const std = @import("std");

pub const tmpl_build = @import("tools/build.zig").build;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-tmpl",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    tmpl_build(b, exe, .{
        .search_paths = &[_][]const u8{
            "templates",
        },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const check_exe = b.addExecutable(.{
        .name = exe.name,
        .root_source_file = exe.root_module.root_source_file,
        .target = target,
        .optimize = optimize,
    });
    tmpl_build(b, check_exe, .{
        .search_paths = &[_][]const u8{
            "templates",
        },
        .target = target,
        .optimize = optimize,
    });
    const check_step = b.step("check", "Syntax check");
    check_step.dependOn(&check_exe.step);
}
