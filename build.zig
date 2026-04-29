const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod_zig80 = b.addModule("zig80", .{
        .root_source_file = b.path("lib/Z80.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_test = b.createModule(.{
        .root_source_file = b.path("tests/test_runner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig80", .module = mod_zig80 },
        },
    });

    const exe_test = b.addExecutable(.{
        .name = "zig80_test",
        .root_module = mod_test,
    });
    b.installArtifact(exe_test);

    const run_step_test = b.step("test", "Test runner");
    const run_cmd_test = b.addRunArtifact(exe_test);

    run_step_test.dependOn(&run_cmd_test.step);
    run_cmd_test.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd_test.addArgs(args);
    }

    // "check" step used by ZLS for Build-On-Save.
    const check = b.step("check", "Check compilation");

    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = mod_test,
    });
    check.dependOn(&exe_check.step);
}
