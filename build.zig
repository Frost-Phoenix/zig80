const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod_zig80 = b.addModule("zig80", .{
        .root_source_file = b.path("lib/Z80.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_sst = b.addExecutable(.{
        .name = "zig80_test_sst",

        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sst.zig"),

            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "zig80", .module = mod_zig80 },
            },
        }),
    });

    const run_step_sst = b.step("test-sst", "Run Single Step Tests");
    const run_cmd_sst = b.addRunArtifact(test_sst);

    run_step_sst.dependOn(&run_cmd_sst.step);
    run_cmd_sst.step.dependOn(b.getInstallStep());

    const test_zex = b.addExecutable(.{
        .name = "zig80_test_zex",

        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/zex.zig"),

            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "zig80", .module = mod_zig80 },
            },
        }),
    });

    const run_step_zex = b.step("test-zex", "Run Single Step Tests");
    const run_cmd_zex = b.addRunArtifact(test_zex);

    run_step_zex.dependOn(&run_cmd_zex.step);
    run_cmd_zex.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd_sst.addArgs(args);
        run_cmd_zex.addArgs(args);
    }

    // "check" step used by ZLS for Build-On-Save.
    const exe_check = b.addExecutable(.{
        .name = "check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sst.zig"),

            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "zig80", .module = mod_zig80 },
            },
        }),
    });
    const check = b.step("check", "Check if zig80 compiles");
    check.dependOn(&exe_check.step);
}
