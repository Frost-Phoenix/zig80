const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zig80",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const exe_test_sst = b.addExecutable(.{
        .name = "zig80_test_sst",
        .root_source_file = b.path("src/test_sst.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_cmd_test_sst = b.addRunArtifact(exe_test_sst);

    if (b.args) |args| {
        run_cmd.addArgs(args);
        run_cmd_test_sst.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_step_test_sst = b.step("test-sst", "Run Single Step Tests");
    run_step_test_sst.dependOn(&run_cmd_test_sst.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
