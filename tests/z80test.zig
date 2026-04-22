// ********** imports ********** //

const Z80 = @import("zig80");

const std = @import("std");

const log = std.log;

const Io = std.Io;
const Allocator = std.mem.Allocator;

// ********** global var ********** //

const start_addr = 0x8000;

var z: Z80 = .init(.{
    .memRead = &memRead,
    .memWrite = &memWrite,
    .ioRead = &ioRead,
    .ioWrite = &ioWrite,
});
var memory: [65536]u8 = @splat(0);

const rom_extention = ".tap";

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
    const base_path = "./tests/roms/";

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

fn runTest(io: Io, allocaor: Allocator, stdout: *Io.Writer, rom_name: []const u8) !void {
    z.reset();
    z.pc = start_addr;

    try loadRom(io, allocaor, rom_name);

    log.info("Running {s}{s}\n", .{ rom_name, rom_extention });

    const timer: std.Io.Timestamp = .now(io, .awake);

    while (z.pc != 0x0000) {
        z.step();

        if (z.pc == 0x0010) {
            var char: u8 = z.a;

            if (char == '\r') char = '\n';
            if (char == 23 or char == 26) char = ' ';

            if ((33 <= char and char <= 126) or char == '\n' or char == ' ') {
                stdout.print("{c}", .{char}) catch {};
                stdout.flush() catch {};
            }
        }
    }

    const duration = Io.Timestamp.untilNow(timer, io, .awake);
    const test_time: f128 = @as(f128, @floatFromInt(duration.toNanoseconds())) / 1_000_000_000.0;

    try stdout.print("\n", .{});
    try stdout.flush();

    log.info("Test {s}{s} took {d} cycles, and ran in {:.2}s", .{ rom_name, rom_extention, z.cycles, test_time });
    log.info("Test {s}{s} ran at {:.2} MHz", .{
        rom_name,
        rom_extention,
        @as(f128, @floatFromInt(z.cycles)) / test_time / 1_000_000.0,
    });
}

// ********** public functions ********** //

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    log.info("{s}Z80 z80test Tests{s}", .{ "\x1b[1m", "\x1b[0m" });

    if (args.len == 3 and std.mem.eql(u8, args[1], "--run")) {
        if (std.mem.eql(u8, args[2], "z80doc")) try runTest(io, alloc, stdout, "z80doc");
        if (std.mem.eql(u8, args[2], "z80full")) try runTest(io, alloc, stdout, "z80full");
        if (std.mem.eql(u8, args[2], "z80docflags")) try runTest(io, alloc, stdout, "z80docflags");
        if (std.mem.eql(u8, args[2], "z80flags")) try runTest(io, alloc, stdout, "z80flags");
        if (std.mem.eql(u8, args[2], "z80ccf")) try runTest(io, alloc, stdout, "z80ccf");
        if (std.mem.eql(u8, args[2], "z80memptr")) try runTest(io, alloc, stdout, "z80memptr");
    } else if (args.len != 1) {
        @panic("unknown arg");
    } else {
        // run all
        try runTest(io, alloc, stdout, "z80doc");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(io, alloc, stdout, "z80full");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(io, alloc, stdout, "z80docflags");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(io, alloc, stdout, "z80flags");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(io, alloc, stdout, "z80ccf");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(io, alloc, stdout, "z80memptr");
    }
}
