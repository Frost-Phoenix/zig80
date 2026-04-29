// ********** imports ********** //

const Z80 = @import("zig80");

const std = @import("std");

const log = std.log;

const Io = std.Io;
const Allocator = std.mem.Allocator;

// ********** global var ********** //

const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

const start_addr = 0x8000;
const rom_extention = ".tap";

var z: Z80 = .init(.{
    .memRead = &memRead,
    .memWrite = &memWrite,
    .ioRead = &ioRead,
    .ioWrite = &ioWrite,
});

var memory: [65536]u8 = @splat(0);

// ********** private functions ********** //

fn memRead(addr: u16) u8 {
    return memory[addr];
}

fn memWrite(addr: u16, val: u8) void {
    memory[addr] = val;
}

fn ioRead(_: u16) u8 {
    return 0xbf;
}

fn ioWrite(_: u16, _: u8) void {}

fn loadRom(io: Io, alloc: Allocator, rom_name: []const u8) !void {
    const base_path = "./tests/roms/z80";

    const rom_path = try std.mem.concat(alloc, u8, &[_][]const u8{
        base_path,
        rom_name,
        rom_extention,
    });
    defer alloc.free(rom_path);

    const file = try std.Io.Dir.cwd().openFile(io, rom_path, .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    const reader = &file_reader.interface;

    const rom_data = try reader.allocRemaining(alloc, .unlimited);
    defer alloc.free(rom_data);

    const skip = 0x5B;

    @memset(memory[0..], 0);
    @memcpy(memory[start_addr .. rom_data.len + start_addr - skip], rom_data[skip..]);

    // Patch to RET
    memory[0x0010] = 0xC9;
    memory[0x1601] = 0xC9;
}

fn handleSyscall(writer: *Io.Writer) !void {
    var char: u8 = z.a;

    if (char == '\r') char = '\n';
    if (char == 23 or char == 26) char = ' ';

    if ((33 <= char and char <= 126) or char == '\n' or char == ' ') {
        try writer.print("{c}", .{char});
        try writer.flush();
    }
}

fn runTest(io: Io, allocaor: Allocator, writer: *Io.Writer, rom_name: []const u8) !void {
    z.reset();
    z.pc = start_addr;

    try loadRom(io, allocaor, rom_name);

    log.info("Running z80{s}{s}\n", .{ rom_name, rom_extention });

    var nb_instructions: u64 = 0;
    const timer: std.Io.Timestamp = .now(io, .awake);

    while (z.pc != 0x0000) {
        z.step();
        nb_instructions += 1;

        if (z.pc == 0x0010) {
            try handleSyscall(writer);
        }
    }

    const duration = Io.Timestamp.untilNow(timer, io, .awake);
    const test_time: f128 = @as(f128, @floatFromInt(duration.toNanoseconds())) / 1_000_000_000.0;

    try writer.print("\n", .{});
    try writer.flush();

    log.info("Test {s}{s} took {d} cycles, and ran in {:.2}s", .{
        rom_name,
        rom_extention,
        z.cycles,
        test_time,
    });
    log.info("Test {s}{s} ran at {:.2} MHz ({:.2} MIPS)", .{
        rom_name,
        rom_extention,
        @as(f128, @floatFromInt(z.cycles)) / test_time / 1_000_000.0,
        @as(f128, @floatFromInt(nb_instructions)) / test_time / 1_000_000.0,
    });
}

// ********** public functions ********** //

pub fn run(io: Io, alloc: Allocator, writer: *Io.Writer, rom: ?[]const u8) !void {
    try writer.print("{s}Z80 z80test Tests{s}\n", .{ BOLD, RESET });

    if (rom) |r| {
        try runTest(io, alloc, writer, r);
    } else {
        const roms = [_][]const u8{ "doc", "full", "docflags", "flags", "ccf", "memptr" };
        for (roms) |r| {
            try runTest(io, alloc, writer, r);
            try writer.flush();
        }
    }
}
