// ********** imports ********** //

const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const eql = std.mem.eql;

const sst = @import("sst.zig");
const zex = @import("zex.zig");
const z80test = @import("z80test.zig");

// ********** global var ********** //

const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";
const YELLOW = "\x1b[33m";

// ********** private functions ********** //

fn printUsage(writer: *Io.Writer) noreturn {
    const usage =
        \\{s}Usage{s}: zig80_test [COMMAND] <OPTION>
        \\
        \\
    ;
    const commands =
        \\{s}Commands{s}:
        \\    {s}sst{s}         Run the Json Single Step Tests
        \\    {s}zex{s}         Run the Z80 instruction set exerciser test suite
        \\    {s}z80test{s}     Run the Zilog Z80 CPU test suite
        \\    
        \\    {s}sst{s}:
        \\        {s}-s{s}, {s}--summary{s}
        \\                Only show the tests summary
        \\        {s}-r{s}, {s}--run{s} <FILE>
        \\                Run tests for one opcode
        \\
        \\    {s}zex{s}:
        \\        {s}-r{s}, {s}--run{s} [zexall|zexdoc|prelim]
        \\                Run the specified test rom
        \\    
        \\    {s}z80test{s}:
        \\        {s}-r{s}, {s}--run{s} [ccf|doc|docflags|flags|full|memptr]
        \\                Run the specified test rom
        \\
        \\
    ;
    const options =
        \\{s}Options{s}:
        \\    {s}-h{s}, {s}--help{s}
        \\                Show this help message
        \\
    ;

    writer.print(usage, .{
        BOLD, RESET,
    }) catch {};

    writer.print(commands, .{
        BOLD,   RESET,
        YELLOW, RESET,
        YELLOW, RESET,
        YELLOW, RESET,
        BOLD,   RESET,
        YELLOW, RESET,
        YELLOW, RESET,
        YELLOW, RESET,
        YELLOW, RESET,
        BOLD,   RESET,
        YELLOW, RESET,
        YELLOW, RESET,
        BOLD,   RESET,
        YELLOW, RESET,
        YELLOW, RESET,
    }) catch {};

    writer.print(options, .{
        BOLD,   RESET,
        YELLOW, RESET,
        YELLOW, RESET,
    }) catch {};

    writer.flush() catch {};

    std.process.exit(1);
}

fn runSST(io: Io, alloc: Allocator, writer: *Io.Writer, args: []const []const u8) !void {
    var config: sst.RunnerConfig = .{
        .file_to_run = null,
        .summary_only = false,
    };

    if (args.len == 3 and eql(u8, args[2], "-s") or eql(u8, args[2], "--summary")) {
        config.summary_only = true;
    } else if (args.len == 4 and eql(u8, args[2], "-r") or eql(u8, args[2], "--run")) {
        config.file_to_run = args[3];
    } else if (args.len != 2) {
        printUsage(writer);
    }

    try sst.run(io, alloc, writer, config);
}

fn runZEX(io: Io, alloc: Allocator, writer: *Io.Writer, args: []const []const u8) !void {
    var rom: ?[]const u8 = null;

    if (args.len == 4 and eql(u8, args[2], "-r") or eql(u8, args[2], "--run")) {
        rom = args[3];
    } else if (args.len != 2) {
        printUsage(writer);
    }

    try zex.run(io, alloc, writer, rom);
}

fn runZ80test(io: Io, alloc: Allocator, writer: *Io.Writer, args: []const []const u8) !void {
    var rom: ?[]const u8 = null;

    if (args.len == 4 and eql(u8, args[2], "-r") or eql(u8, args[2], "--run")) {
        rom = args[3];
    } else if (args.len != 2) {
        printUsage(writer);
    }

    try z80test.run(io, alloc, writer, rom);
}

// ********** public functions ********** //

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2 or args.len > 4) {
        printUsage(stdout);
    }

    const command = args[1];

    if (eql(u8, command, "sst")) {
        try runSST(io, alloc, stdout, args);
    } else if (eql(u8, command, "zex")) {
        try runZEX(io, alloc, stdout, args);
    } else if (eql(u8, command, "z80test")) {
        try runZ80test(io, alloc, stdout, args);
    } else {
        printUsage(stdout);
    }
}
