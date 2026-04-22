// ********** imports ********** //

const Z80 = @import("zig80");

const std = @import("std");

const log = std.log;

const Io = std.Io;
const Allocator = std.mem.Allocator;

// ********** global var ********** //

const start_addr = 0x100;

var z: Z80 = .init(.{
    .memRead = &memRead,
    .memWrite = &memWrite,
    .ioRead = &ioRead,
    .ioWrite = &ioWrite,
});
var memory: [65536]u8 = @splat(0);

const rom_extention = ".com";

// ********** private functions ********** //

fn memRead(addr: u16) u8 {
    return memory[addr];
}

fn memWrite(addr: u16, val: u8) void {
    memory[addr] = val;
}

fn ioRead(_: u16) u8 {
    return 0xff;
}

fn ioWrite(_: u16, _: u8) void {}

fn loadRom(io: Io, allocator: Allocator, rom_name: []const u8) !void {
    const base_path = "./tests/roms/";

    const rom_path = try std.mem.concat(allocator, u8, &[_][]const u8{
        base_path,
        rom_name,
        rom_extention,
    });
    defer allocator.free(rom_path);

    const file = try Io.Dir.cwd().openFile(io, rom_path, .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    const reader = &file_reader.interface;

    const rom_data = try reader.allocRemaining(allocator, .unlimited);
    defer allocator.free(rom_data);

    @memset(memory[0..], 0);
    @memcpy(memory[start_addr .. rom_data.len + start_addr], rom_data);

    memory[0x0000] = 0x76; // halt, and of tests
    memory[0x0005] = 0xC9; // ret, after print
}

fn runTest(io: Io, allocaor: Allocator, stdout: *Io.Writer, rom_name: []const u8) !void {
    z.reset();
    z.pc = start_addr;

    try loadRom(io, allocaor, rom_name);

    log.info("Running {s}{s}\n", .{ rom_name, rom_extention });

    const timer: std.Io.Timestamp = .now(io, .awake);
    var nb_instructions: u64 = 0;

    while (!z.is_halted) {
        z.step();

        nb_instructions += 1;

        if (z.pc == 0x0005) {
            switch (z.c) {
                2 => stdout.print("{c}", .{z.e}) catch {},
                9 => {
                    var addr: u16 = (@as(u16, z.d) << 8) | z.e;

                    while (true) : (addr +%= 1) {
                        const char = memory[addr];

                        if (char == '$') {
                            break;
                        }

                        stdout.print("{c}", .{char}) catch {};
                    }
                },
                else => @panic("Unknown syscal"),
            }

            stdout.flush() catch {};
        }
    }

    const duration = Io.Timestamp.untilNow(timer, io, .awake);
    const test_time: f128 = @as(f128, @floatFromInt(duration.toNanoseconds())) / 1_000_000_000.0;

    try stdout.print("\n\n", .{});
    try stdout.flush();

    log.info("Test {s}{s} took {d} cycles, and ran in {:.2}s", .{ rom_name, rom_extention, z.cycles, test_time });
    log.info("Test {s}{s} ran at {:.2} MHz ({:.2} MIPS)", .{
        rom_name,
        rom_extention,
        @as(f128, @floatFromInt(z.cycles)) / test_time / 1_000_000.0,
        @as(f128, @floatFromInt(nb_instructions)) / test_time / 1_000_000.0,
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

    log.info("{s}Z80 ZEX Tests{s}", .{ "\x1b[1m", "\x1b[0m" });

    if (args.len == 3 and std.mem.eql(u8, args[1], "--run")) {
        if (std.mem.eql(u8, args[2], "prelim")) try runTest(io, alloc, stdout, "prelim");
        if (std.mem.eql(u8, args[2], "zexdod")) try runTest(io, alloc, stdout, "zexdoc");
        if (std.mem.eql(u8, args[2], "zexall")) try runTest(io, alloc, stdout, "zexall");
    } else if (args.len != 1) {
        @panic("unknown arg");
    } else {
        // run all
        try runTest(io, alloc, stdout, "prelim");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(io, alloc, stdout, "zexdoc");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(io, alloc, stdout, "zexall");
    }
}
