// ********** imports ********** //

const Z80 = @import("zig80");

const std = @import("std");

const log = std.log;

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
    return 0xbf;
}

fn ioWrite(_: u16, _: u8) void {}

fn loadRom(allocator: Allocator, rom_name: []const u8) !void {
    const base_path = "./tests/roms/";
    const rom_extention = ".tap";

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

    const skip = 0x5B;

    @memset(memory[0..], 0);
    @memcpy(memory[start_addr .. rom_data.len + start_addr - skip], rom_data[skip..]);

    // Patch to RET
    memory[0x0010] = 0xC9;
    memory[0x1601] = 0xC9;
}

fn runTest(allocaor: Allocator, rom_name: []const u8) !void {
    z.reset();
    z.pc = start_addr;

    try loadRom(allocaor, rom_name);

    log.info("Running {s}.tap\n", .{rom_name});

    test_finished = false;
    while (!test_finished) {
        z.step();

        if (z.is_halted or z.pc == 0x0000) {
            break;
        }

        if (z.pc == 0x0010) {
            var char: u8 = z.a;

            if (char == '\r') char = '\n';
            if (char == 23 or char == 26) char = ' ';

            // stdout.print("({})", .{char}) catch {};
            stdout.print("{c}", .{char}) catch {};
            stdout.flush() catch {};
        }
    }

    try stdout.print("\n", .{});
}

// ********** public functions ********** //

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    log.info("{s}Z80 z80test Tests{s}", .{ "\x1b[1m", "\x1b[0m" });

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 3 and std.mem.eql(u8, args[1], "--run")) {
        if (std.mem.eql(u8, args[2], "z80doc")) try runTest(allocator, "z80doc");
        if (std.mem.eql(u8, args[2], "z80full")) try runTest(allocator, "z80full");
        if (std.mem.eql(u8, args[2], "z80docflags")) try runTest(allocator, "z80docflags");
        if (std.mem.eql(u8, args[2], "z80flags")) try runTest(allocator, "z80flags");
        if (std.mem.eql(u8, args[2], "z80ccf")) try runTest(allocator, "z80ccf");
        if (std.mem.eql(u8, args[2], "z80memptr")) try runTest(allocator, "z80memptr");
    } else if (args.len != 1) {
        @panic("unknown arg");
    } else {
        // run all
        try runTest(allocator, "z80doc");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(allocator, "z80full");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(allocator, "z80docflags");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(allocator, "z80flags");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(allocator, "z80ccf");
        try stdout.print("\n", .{});
        try stdout.flush();
        try runTest(allocator, "z80memptr");
    }

    try stdout.flush();
}
