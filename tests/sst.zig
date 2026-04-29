// ********** imports ********** //

const Z80 = @import("zig80");

const std = @import("std");

const log = std.log;
const json = std.json;

const Io = std.Io;
const Allocator = std.mem.Allocator;

const expectEqual = std.testing.expectEqual;

// ********** global var ********** //

const BOLD = "\x1b[1m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const RED = "\x1b[31m";
const RESET = "\x1b[0m";

var memory: [65536]u8 = @splat(0);
var ports: [65536]u8 = @splat(0);

var summary_only: bool = false;

var results: TestResult = .init();
var category_results: std.EnumArray(TestCategory, TestResult) = .initFill(.init());

// ********** types ********** //

pub const RunnerConfig = struct {
    summary_only: bool,
    file_to_run: ?[]const u8,
};

const TestConfig = struct {
    name: []const u8,
    initial: Z80State,
    final: Z80State,
    cycles: [][3]json.Value,
    ports: ?[][3]json.Value = null,

    const Z80State = struct {
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
        im: u2,
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

        const startsWith = std.mem.startsWith;

        if (startsWith(u8, test_name, "dd cb")) return .ix_bit;
        if (startsWith(u8, test_name, "fd cb")) return .iy_bit;
        if (startsWith(u8, test_name, "ed")) return .misc;
        if (startsWith(u8, test_name, "cb")) return .bit;
        if (startsWith(u8, test_name, "dd")) return .ix;
        if (startsWith(u8, test_name, "fd")) return .iy;

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

fn sstLog(writer: *Io.Writer, comptime status: TestStatus, test_name: []const u8) !void {
    if (summary_only and status != .failed) {
        return;
    }

    const status_txt = switch (status) {
        .passed => GREEN ++ @tagName(status) ++ RESET,
        .skipped => YELLOW ++ @tagName(status) ++ RESET,
        .failed => RED ++ @tagName(status) ++ RESET,
    };

    try writer.print("{s}: \"{s}\"\n", .{ status_txt, test_name });
    try writer.flush();
}

fn printSummary(writer: *Io.Writer) !void {
    const res = category_results;

    const summary =
        \\{s}Summary{s}
        \\├─ Ran {d} tests
        \\│  ├─ Passed        {s}{d:>4}{s}/{d}
        \\│  ├─ Skipped       {s}{d:>4}{s}/{d}
        \\│  └─ Failed        {s}{d:>4}{s}/{d}
        \\└─ Detail
        \\   ├─ Main            {d:>3}/{d:>3}
        \\   ├─ (ED) Misc       {d:>3}/{d:>3}
        \\   ├─ (CB) Bit        {d:>3}/{d:>3}
        \\   ├─ (DD) IX         {d:>3}/{d:>3}
        \\   ├─ (FD) IY         {d:>3}/{d:>3}
        \\   ├─ (DDCB) IX Bit   {d:>3}/{d:>3}
        \\   └─ (FDCB) IY Bit   {d:>3}/{d:>3}
        \\
    ;

    if (!summary_only) {
        try writer.print("\n", .{});
    }

    // zig fmt: off
    try writer.print(summary, .{
        BOLD, RESET,
        results.total(),
        GREEN,  results.passed,  RESET, results.total(),
        YELLOW, results.skipped, RESET, results.total(),
        RED,    results.failed,  RESET, results.total(),
        res.get(.main).passed,   res.get(.main).total(),
        res.get(.misc).passed,   res.get(.misc).total(),
        res.get(.bit).passed,    res.get(.bit).total(),
        res.get(.ix).passed,     res.get(.ix).total(),     
        res.get(.iy).passed,     res.get(.iy).total(),
        res.get(.ix_bit).passed, res.get(.ix_bit).total(),
        res.get(.iy_bit).passed, res.get(.iy_bit).total(),
    });
    // zig fmt: on

    try writer.flush();
}

fn parseTestConfig(io: Io, alloc: Allocator, path: []const u8) !json.Parsed([]TestConfig) {
    const cwd = Io.Dir.cwd();
    const file = try cwd.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    var json_reader = std.json.Reader.init(alloc, &file_reader.interface);
    defer json_reader.deinit();

    const parsed = try std.json.parseFromTokenSource(
        []TestConfig,
        alloc,
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

    z.imode = @enumFromInt(init.im);

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

    try expectEqual(fin.im, @intFromEnum(z.imode));

    try expectEqual(fin.ix, z.ix);
    try expectEqual(fin.iy, z.iy);

    try expectEqual(fin.i, z.i);
    try expectEqual(fin.r, z.r);

    try expectEqual(fin.q, z.q.val);

    try expectEqual(fin.wz, z.wz);

    try expectEqual(fin.iff1 == 1, z.iff1);
    try expectEqual(fin.iff2 == 1, z.iff2);

    try expectEqual(config.cycles.len, z.cycles);

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

fn runTest(writer: *Io.Writer, configs: []TestConfig, test_name: []const u8) !void {
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

        z.step();

        expectZ80State(&z, config) catch |err| {
            results.failed += 1;
            test_results.failed += 1;

            try sstLog(writer, .failed, config.name);

            if (summary_only) {
                return;
            }

            return err;
        };

        z.reset();
    }

    results.passed += 1;
    test_results.passed += 1;

    try sstLog(writer, .passed, test_name);
}

fn processFile(io: Io, alloc: Allocator, writer: *Io.Writer, file_path: []const u8) !void {
    const base_name = std.fs.path.basename(file_path);
    const ext = ".json";
    const test_name = base_name[0 .. base_name.len - ext.len];

    const parsed_configs = try parseTestConfig(io, alloc, file_path);
    defer parsed_configs.deinit();
    const configs = parsed_configs.value;

    try runTest(writer, configs, test_name);
}

fn runAll(io: Io, alloc: Allocator, writer: *Io.Writer) !void {
    const base_path = "./tests/sst/";

    const dir = Io.Dir.cwd().openDir(io, base_path, .{
        .access_sub_paths = false,
        .iterate = true,
    }) catch |err| {
        if (err == error.FileNotFound) {
            log.err("failed to open tests dir: \"{s}\"", .{base_path});
        }

        return err;
    };

    var walker = try dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next(io)) |file| {
        const file_name = file.basename;
        const file_path = try std.mem.concat(alloc, u8, &[_][]const u8{
            base_path,
            file_name,
        });
        defer alloc.free(file_path);

        try processFile(io, alloc, writer, file_path);
    }

    try printSummary(writer);
}

// ********** public functions ********** //

pub fn run(io: Io, alloc: Allocator, writer: *Io.Writer, config: RunnerConfig) !void {
    try writer.print("{s}Z80 Single Step Tests{s}\n\n", .{ BOLD, RESET });
    try writer.flush();

    if (config.summary_only) {
        summary_only = true;
    }

    if (config.file_to_run) |file| {
        try processFile(io, alloc, writer, file);
    } else {
        try runAll(io, alloc, writer);
    }
}
