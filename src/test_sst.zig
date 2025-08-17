// ********** imports ********** //

const Z80 = @import("Z80.zig");

const std = @import("std");

const log = std.log;
const json = std.json;

const Allocator = std.mem.Allocator;

const expectEqual = std.testing.expectEqual;

// ********** global var ********** //

var ignore_unknown_opcodes_warnig: bool = false;

// ********** types ********** //

const TestConfig = struct {
    name: []const u8,
    initial: struct {
        pc: u16,
        sp: u16,
        a: u8,
        f: u8,
        b: u8,
        c: u8,
        d: u8,
        e: u8,
        h: u8,
        l: u8,
        i: u8,
        r: u8,
        wz: u16,
        ix: u16,
        iy: u16,
        af_: u16,
        bc_: u16,
        de_: u16,
        hl_: u16,
        iff1: u1,
        iff2: u1,
        ram: [][2]u16,
        // ei
        // im
        // p
        // q
    },
    final: struct {
        pc: u16,
        sp: u16,
        a: u8,
        f: u8,
        b: u8,
        c: u8,
        d: u8,
        e: u8,
        h: u8,
        l: u8,
        i: u8,
        r: u8,
        wz: u16,
        ix: u16,
        iy: u16,
        af_: u16,
        bc_: u16,
        de_: u16,
        hl_: u16,
        iff1: u1,
        iff2: u1,
        ram: [][2]u16,
        // ei
        // im
        // p
        // q
    },
    // cycles
};

// ********** private functions ********** //

fn parseTestConfig(allocator: Allocator, path: []const u8) !json.Parsed([]TestConfig) {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    var buffered = std.io.bufferedReader(file.reader());
    var reader = std.json.reader(allocator, buffered.reader());
    defer reader.deinit();

    const parsed = try std.json.parseFromTokenSource(
        []TestConfig,
        allocator,
        &reader,
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );

    return parsed;
}

fn setZ80State(z: *Z80, config: TestConfig) void {
    const init = config.initial;

    z.pc = init.pc;
    z.sp = init.sp;

    z.a = init.a;
    z.f.b = init.f;

    z.b = init.b;
    z.c = init.c;
    z.d = init.d;
    z.e = init.e;
    z.h = init.h;
    z.l = init.l;

    z.af_ = init.af_;
    z.bc_ = init.bc_;
    z.de_ = init.de_;
    z.hl_ = init.hl_;

    z.ix = init.ix;
    z.iy = init.iy;

    z.i = init.i;
    z.r = init.r;

    z.iff1 = init.iff1 == 1;
    z.iff2 = init.iff2 == 1;

    for (init.ram) |pair| {
        const addr = pair[0];
        const val = pair[1];

        z.memory[addr] = @truncate(val);
    }
}

fn expectState(z: *Z80, config: TestConfig) !void {
    const fin = config.final;

    try expectEqual(fin.pc, z.pc);
    try expectEqual(fin.sp, z.sp);

    try expectEqual(fin.a, z.a);
    try expectEqual(fin.f, z.f.b);
    try expectEqual(fin.b, z.b);
    try expectEqual(fin.c, z.c);
    try expectEqual(fin.d, z.d);
    try expectEqual(fin.e, z.e);
    try expectEqual(fin.h, z.h);
    try expectEqual(fin.l, z.l);

    try expectEqual(fin.af_, z.af_);
    try expectEqual(fin.bc_, z.bc_);
    try expectEqual(fin.de_, z.de_);
    try expectEqual(fin.hl_, z.hl_);

    try expectEqual(fin.ix, z.ix);
    try expectEqual(fin.iy, z.iy);

    try expectEqual(fin.i, z.i);
    // try expectEqual(fin.r, z.r); // Not implemented yet

    try expectEqual(fin.iff1 == 1, z.iff1);
    try expectEqual(fin.iff2 == 1, z.iff2);

    for (fin.ram) |pair| {
        const addr = pair[0];
        const val = pair[1];

        try expectEqual(@as(u8, @truncate(val)), z.memory[addr]);
    }
}

fn runTest(z: *Z80, configs: []TestConfig, test_name: []const u8) !void {
    for (configs) |config| {
        setZ80State(z, config);

        z.step() catch |err| switch (err) {
            Z80.Z80Error.UnknownOpcode => {
                if (!ignore_unknown_opcodes_warnig) {
                    log.warn("Test \"{s}\": skipped (unknown opcode)", .{test_name});
                }

                return;
            },
            else => return err,
        };

        expectState(z, config) catch |err| {
            std.log.err("Test \"{s}\": failed", .{config.name});

            return err;
        };
    }

    log.info("Test \"{s}\": passed", .{test_name});
}

fn runAll(allocator: Allocator) !void {
    var z: Z80 = .init();

    const base_path = "./tests/sst/";

    const dir = try std.fs.cwd().openDir(base_path, .{
        .access_sub_paths = false,
        .iterate = true,
    });

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |file| {
        const file_name = file.basename;
        const file_name_no_extention = file_name[0 .. file_name.len - 5];
        const file_path = try std.mem.concat(allocator, u8, &[_][]const u8{
            base_path,
            file_name,
        });
        defer allocator.free(file_path);

        const parsed_configs = try parseTestConfig(allocator, file_path);
        defer parsed_configs.deinit();
        const configs = parsed_configs.value;

        try runTest(&z, configs, file_name_no_extention);
    }
}

// ********** public functions ********** //

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--ignore-unknown-opcodes")) {
        ignore_unknown_opcodes_warnig = true;
    }

    log.info("Z80 Single Step Tests", .{});

    try runAll(allocator);
}
