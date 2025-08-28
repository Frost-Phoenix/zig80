// ********** imports ********** //

const Z80 = @import("zig80");

const std = @import("std");

const log = std.log;
const json = std.json;

const Allocator = std.mem.Allocator;

const expectEqual = std.testing.expectEqual;

// ********** global var ********** //

var memory: [65536]u8 = @splat(0);
var ports: [65536]u8 = @splat(0);

var only_show_summary: bool = false;
var ignore_unknown_opcodes_warnig: bool = false;

var results: TestResult = .init();
var category_results: std.EnumArray(TestCategory, TestResult) = .initFill(.init());

// ********** types ********** //

const TestConfig = struct {
    name: []const u8,
    initial: CPUState,
    final: CPUState,
    // cycles
    ports: ?[][3]json.Value = null,

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

const TestCategory = enum {
    main,
    misc,
    bit,
    ix,
    iy,
    ix_bit,
    iy_bit,

    pub fn getCategory(test_name: []const u8) TestCategory {
        if (test_name.len == 2) return .main;

        if (std.mem.startsWith(u8, test_name, "dd cb")) return .ix_bit;
        if (std.mem.startsWith(u8, test_name, "fd cb")) return .iy_bit;
        if (std.mem.startsWith(u8, test_name, "ed")) return .misc;
        if (std.mem.startsWith(u8, test_name, "cb")) return .bit;
        if (std.mem.startsWith(u8, test_name, "dd")) return .ix;
        if (std.mem.startsWith(u8, test_name, "fd")) return .iy;

        log.err("Unknown category for test: {s}", .{test_name});

        unreachable;
    }
};

const TestResult = struct {
    passed: u32,
    skipped: u32,
    failed: u32,

    pub fn init() TestResult {
        return .{
            .passed = 0,
            .skipped = 0,
            .failed = 0,
        };
    }

    pub fn total(self: *const TestResult) u32 {
        return self.passed + self.skipped + self.failed;
    }
};

// ********** private functions ********** //

fn memRead(addr: u16) u8 {
    return memory[addr];
}

fn memWrite(addr: u16, val: u8) void {
    memory[addr] = val;
}

fn ioRead(addr: u16) u8 {
    return ports[addr];
}

fn ioWrite(addr: u16, val: u8) void {
    ports[addr] = val;
}

fn sstLog(comptime status: TestStatus, test_name: []const u8) void {
    if (only_show_summary) return;

    const status_txt = switch (status) {
        .passed => "\x1b[32m" ++ @tagName(status) ++ "\x1b[0m",
        .skipped => "\x1b[33m" ++ @tagName(status) ++ "\x1b[0m",
        .failed => "\x1b[31m" ++ @tagName(status) ++ "\x1b[0m",
    };

    const logFn = switch (status) {
        .passed => log.info,
        .skipped => log.warn,
        .failed => log.err,
    };

    logFn("{s}: \"{s}\"", .{ status_txt, test_name });
}

fn printSummary() void {
    const bold = "\x1b[1m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const red = "\x1b[31m";
    const reset = "\x1b[0m";

    const res = category_results;

    log.info("", .{});
    log.info("{s}Summary{s}", .{ bold, reset });
    log.info("├─ Ran {d} tests", .{results.total()});
    log.info("│  ├─ Passed\t{s}{d:>4}{s}/{d}", .{ green, results.passed, reset, results.total() });
    log.info("│  ├─ Skipped\t{s}{d:>4}{s}/{d}", .{ yellow, results.skipped, reset, results.total() });
    log.info("│  └─ Failed\t{s}{d:>4}{s}/{d}", .{ red, results.failed, reset, results.total() });
    log.info("└─ Detail", .{});
    log.info("   ├─ Main\t    {d:>3}/{d:>3}", .{ res.get(.main).passed, res.get(.main).total() });
    log.info("   ├─ (ED) Misc\t    {d:>3}/{d:>3}", .{ res.get(.misc).passed, res.get(.misc).total() });
    log.info("   ├─ (CB) Bit\t    {d:>3}/{d:>3}", .{ res.get(.bit).passed, res.get(.bit).total() });
    log.info("   ├─ (DD) IX\t    {d:>3}/{d:>3}", .{ res.get(.ix).passed, res.get(.ix).total() });
    log.info("   ├─ (FD) IY\t    {d:>3}/{d:>3}", .{ res.get(.iy).passed, res.get(.iy).total() });
    log.info("   ├─ (DDCB) IX Bit   {d:>3}/{d:>3}", .{ res.get(.ix_bit).passed, res.get(.ix_bit).total() });
    log.info("   └─ (FDCB) IY Bit   {d:>3}/{d:>3}", .{ res.get(.iy_bit).passed, res.get(.iy_bit).total() });
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

    z.wz = init.wz;

    z.iff1 = init.iff1 == 1;
    z.iff2 = init.iff2 == 1;

    for (init.ram) |pair| {
        const addr = pair[0];
        const val = pair[1];

        memory[addr] = @truncate(val);
    }

    if (config.ports) |_ports| {
        for (_ports) |port| {
            if (port[2].string[0] != 'r') continue;

            const addr: u16 = @intCast(port[0].integer);
            const val: u8 = @intCast(port[1].integer);

            ports[addr] = val;
        }
    }
}

fn expectZ80State(z: *Z80, config: TestConfig) !void {
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
    try expectEqual(fin.r, z.r);

    try expectEqual(fin.q, z.q.val);

    try expectEqual(fin.wz, z.wz);

    try expectEqual(fin.iff1 == 1, z.iff1);
    try expectEqual(fin.iff2 == 1, z.iff2);

    for (fin.ram) |pair| {
        const addr = pair[0];
        const val = pair[1];

        try expectEqual(@as(u8, @truncate(val)), memory[addr]);
    }

    if (config.ports) |_ports| {
        for (_ports) |port| {
            if (port[2].string[0] != 'w') continue;

            const addr: u16 = @intCast(port[0].integer);
            const val: u8 = @intCast(port[1].integer);

            try expectEqual(val, ports[addr]);
        }
    }
}

fn runTest(configs: []TestConfig, test_name: []const u8) !void {
    var z: Z80 = .init(.{
        .memRead = &memRead,
        .memWrite = &memWrite,
        .ioRead = &ioRead,
        .ioWrite = &ioWrite,
    });

    const test_category = TestCategory.getCategory(test_name);
    const test_results = category_results.getPtr(test_category);

    for (configs) |config| {
        setZ80State(&z, config);

        z.step() catch |err| switch (err) {
            Z80.Z80Error.UnknownOpcode => {
                results.skipped += 1;
                test_results.skipped += 1;

                if (!ignore_unknown_opcodes_warnig) {
                    sstLog(.skipped, test_name);
                }

                return;
            },
            else => return err,
        };

        expectZ80State(&z, config) catch |err| {
            results.failed += 1;
            test_results.failed += 1;

            sstLog(.failed, config.name);

            return err;
        };
    }

    results.passed += 1;
    test_results.passed += 1;

    sstLog(.passed, test_name);
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

    printSummary();
}

// ********** public functions ********** //

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    log.info("{s}Z80 Single Step Tests{s}", .{ "\x1b[1m", "\x1b[0m" });

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 2 and std.mem.eql(u8, args[1], "--ignore-unknown")) {
        ignore_unknown_opcodes_warnig = true;
    } else if (args.len == 2 and std.mem.eql(u8, args[1], "--summary-only")) {
        only_show_summary = true;
    }

    if (args.len == 3 and std.mem.eql(u8, args[1], "--run")) {
        try processFile(allocator, args[2]);
    } else {
        try runAll(allocator);
    }
}
