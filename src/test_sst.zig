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
    initial: CPUState,
    final: CPUState,
    // cycles

    const CPUState = struct {
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
        // ei
        wz: u16,
        ix: u16,
        iy: u16,
        af_: u16,
        bc_: u16,
        de_: u16,
        hl_: u16,
        // im
        // p
        q: u8,
        iff1: u1,
        iff2: u1,
        ram: [][2]u16,
    };
};

const TestStatus = enum {
    passed,
    skipped,
    failed,
};

// ********** private functions ********** //

fn sst_log(comptime status: TestStatus, test_name: []const u8) void {
    const status_txt, const logFn = switch (status) {
        .passed => .{ "\x1b[32m" ++ @tagName(status) ++ "\x1b[0m", log.info },
        .skipped => .{ "\x1b[33m" ++ @tagName(status) ++ "\x1b[0m", log.warn },
        .failed => .{ "\x1b[31m" ++ @tagName(status) ++ "\x1b[0m", log.err },
    };

    logFn(status_txt ++ ": \"{s}\"", .{test_name});
}

fn parseTestConfig(allocator: Allocator, path: []const u8) !json.Parsed([]TestConfig) {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(&buffer);
    var json_reader = std.json.Reader.init(allocator, &file_reader.interface);
    defer json_reader.deinit();

    const parsed = try std.json.parseFromTokenSource(
        []TestConfig,
        allocator,
        &json_reader,
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
    z.f.setF(init.f);

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

    z.q.val = init.q;

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
    try expectEqual(fin.f, z.f.getF());
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

    try expectEqual(fin.q, z.q.val);

    try expectEqual(fin.iff1 == 1, z.iff1);
    try expectEqual(fin.iff2 == 1, z.iff2);

    for (fin.ram) |pair| {
        const addr = pair[0];
        const val = pair[1];

        try expectEqual(@as(u8, @truncate(val)), z.memory[addr]);
    }
}

fn runTest(configs: []TestConfig, test_name: []const u8) !void {
    var z: Z80 = .init();

    for (configs) |config| {
        setZ80State(&z, config);

        z.step() catch |err| switch (err) {
            Z80.Z80Error.UnknownOpcode => {
                if (!ignore_unknown_opcodes_warnig) {
                    sst_log(.skipped, test_name);
                }

                return;
            },
            else => return err,
        };

        expectState(&z, config) catch |err| {
            sst_log(.failed, config.name);

            return err;
        };
    }

    sst_log(.passed, test_name);
}

fn processFile(allocator: Allocator, file_path: []const u8) !void {
    const base_name = std.fs.path.basename(file_path);
    const ext = ".json";
    const test_name = base_name[0 .. base_name.len - ext.len];

    const parsed_configs = try parseTestConfig(allocator, file_path);
    defer parsed_configs.deinit();
    const configs = parsed_configs.value;

    try runTest(configs, test_name);
}

fn runAll(allocator: Allocator) !void {
    const base_path = "./tests/sst/";

    const dir = std.fs.cwd().openDir(base_path, .{
        .access_sub_paths = false,
        .iterate = true,
    }) catch |err| {
        if (err == error.FileNotFound) {
            log.err("failed to open tests dir: \"{s}\"", .{base_path});
        }

        return err;
    };

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |file| {
        const file_name = file.basename;
        const file_path = try std.mem.concat(allocator, u8, &[_][]const u8{
            base_path,
            file_name,
        });
        defer allocator.free(file_path);

        try processFile(allocator, file_path);
    }
}

// ********** public functions ********** //

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    log.info("Z80 Single Step Tests", .{});

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "--ignore-unknown")) {
        ignore_unknown_opcodes_warnig = true;
    }

    if (args.len == 3 and std.mem.eql(u8, args[1], "--run")) {
        try processFile(allocator, args[2]);
    } else {
        try runAll(allocator);
    }
}
