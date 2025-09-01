// ********** imports ********** //

const Z80 = @import("zig80");

const std = @import("std");

const log = std.log;

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

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

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

fn loadRom(allocator: Allocator, rom_name: []const u8) !void {
    const base_path = "./tests/roms/";

    const rom_path = try std.mem.concat(allocator, u8, &[_][]const u8{
        base_path,
        rom_name,
        rom_extention,
    });
    defer allocator.free(rom_path);

    const file = try std.fs.cwd().openFile(rom_path, .{ .mode = .read_only });
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(&buffer);
    const reader = &file_reader.interface;

    const rom_data = try reader.allocRemaining(allocator, .unlimited);
    defer allocator.free(rom_data);

    @memset(memory[0..], 0);
    @memcpy(memory[start_addr .. rom_data.len + start_addr], rom_data);

    memory[0x0000] = 0x76; // halt, and of tests
    memory[0x0005] = 0xC9; // ret, after print
}

fn runTest(allocaor: Allocator, rom_name: []const u8) !void {
    z.reset();
    z.pc = start_addr;

    try loadRom(allocaor, rom_name);

    log.info("Running {s}{s}\n", .{ rom_name, rom_extention });

    var timer: std.time.Timer = try .start();

    while (!z.is_halted) {
        z.step();

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

    const test_time: f128 = @as(f128, @floatFromInt(timer.read())) / 1_000_000_000.0;

    try stdout.print("\n\n", .{});
    try stdout.flush();

    log.info("Test {s}{s} took {d} cycles, and ran in {:.2}s", .{ rom_name, rom_extention, z.cycles, test_time });
    log.info("Test {s}{s} ran at {:.2} MHz", .{
        rom_name,
        rom_extention,
        @as(f128, @floatFromInt(z.cycles)) / test_time / 1_000_000.0,
    });
}

// ********** public functions ********** //

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    log.info("{s}Z80 ZEX Tests{s}", .{ "\x1b[1m", "\x1b[0m" });

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 3 and std.mem.eql(u8, args[1], "--run")) {
        if (std.mem.eql(u8, args[2], "prelim")) try runTest(allocator, "prelim");
        if (std.mem.eql(u8, args[2], "zexdod")) try runTest(allocator, "zexdoc");
        if (std.mem.eql(u8, args[2], "zexall")) try runTest(allocator, "zexall");
    } else if (args.len != 1) {
        @panic("unknown arg");
    } else {
        // run all
        try runTest(allocator, "prelim");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(allocator, "zexdoc");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(allocator, "zexall");
    }
}
