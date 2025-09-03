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
    b.installArtifact(test_sst);

    const run_step_sst = b.step("test-sst", "Run Single Step Tests");
    const run_cmd_sst = b.addRunArtifact(test_sst);

    run_step_sst.dependOn(&run_cmd_sst.step);

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
    b.installArtifact(test_zex);

    const run_step_zex = b.step("test-zex", "Run Single Step Tests");
    const run_cmd_zex = b.addRunArtifact(test_zex);

    run_step_zex.dependOn(&run_cmd_zex.step);

    const test_z80test = b.addExecutable(.{
        .name = "zig80_test_z80test",

        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/z80test.zig"),

            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "zig80", .module = mod_zig80 },
            },
        }),
    });
    b.installArtifact(test_z80test);

    const run_step_z80test = b.step("test-z80test", "Run Single Step Tests");
    const run_cmd_z80test = b.addRunArtifact(test_z80test);

    run_step_z80test.dependOn(&run_cmd_z80test.step);

    if (b.args) |args| {
        run_cmd_sst.addArgs(args);
        run_cmd_zex.addArgs(args);
        run_cmd_z80test.addArgs(args);
    }

    // "check" step used by ZLS for Build-On-Save.
    const check = b.step("check", "Check if all code compile");

    const exe_check_sst = b.addExecutable(.{
        .name = "check_sst",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sst.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig80", .module = mod_zig80 },
            },
        }),
    });
    check.dependOn(&exe_check_sst.step);

    const exe_check_zex = b.addExecutable(.{
        .name = "check_zex",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/zex.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig80", .module = mod_zig80 },
            },
        }),
    });
    check.dependOn(&exe_check_zex.step);

    const exe_check_z80test = b.addExecutable(.{
        .name = "check_z80test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/z80test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig80", .module = mod_zig80 },
            },
        }),
    });
    check.dependOn(&exe_check_z80test.step);
}
