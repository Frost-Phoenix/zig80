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

var test_finished: bool = undefined;

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

    return 0xff;
}

fn ioWrite(_: u16, _: u8) void {
    test_finished = true;
}

fn loadRom(allocator: Allocator, rom_name: []const u8) !void {
    const base_path = "./tests/roms/";
    const rom_extention = ".com";

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

    // inject "out 1,a" at 0x0000 (signal to stop the test)
    memory[0x0000] = 0xD3;
    memory[0x0001] = 0x00;

    // inject "in a,0" at 0x0005 (signal to output characters)
    memory[0x0005] = 0xDB;
    memory[0x0006] = 0x00;
    memory[0x0007] = 0xC9;
}

fn runTest(allocaor: Allocator, rom_name: []const u8) !void {
    z.reset();
    z.pc = start_addr;

    try loadRom(allocaor, rom_name);

    log.info("Running {s}.com\n", .{rom_name});

    test_finished = false;
    while (!test_finished) {
        try z.step();
    }

    try stdout.print("\n", .{});
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

    try stdout.flush();
}
