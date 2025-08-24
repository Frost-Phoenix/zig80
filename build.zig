const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig80",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);

    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    const exe_sst = b.addExecutable(.{
        .name = "zig80_test_sst",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_sst.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_step_sst = b.step("test-sst", "Run Single Step Tests");
    const run_cmd_sst = b.addRunArtifact(exe_sst);

    run_step_sst.dependOn(&run_cmd_sst.step);
    run_cmd_sst.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
        run_cmd_sst.addArgs(args);
    }
}
