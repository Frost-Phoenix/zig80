const Z80 = @This();

// ********** //

const std = @import("std");

// ********** //

fn RegisterPair(comptime name1: [:0]const u8, comptime name2: [:0]const u8) type {
    return packed union {
        w: u16,
        b: @Type(.{
            .@"struct" = .{
                .layout = .@"packed",
                .fields = &.{
                    .{
                        .name = name2,
                        .type = u8,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = 0,
                    },
                    .{
                        .name = name1,
                        .type = u8,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = 0,
                    },
                },
                .decls = &.{},
                .is_tuple = false,
            },
        }),
    };
}

const Flags = packed union {
    b: u8,
    f: packed struct(u8) {
        s: bool,
        z: bool,
        y: bool,
        h: bool,
        x: bool,
        p: bool,
        n: bool,
        c: bool,
    },
};

memory: [65536]u8,

// main registers
a: u8,
f: Flags,
bc: RegisterPair("b", "c"),
de: RegisterPair("d", "e"),
hl: RegisterPair("h", "l"),

// alternate registers
af_: RegisterPair("a_", "f_"),
bc_: RegisterPair("b_", "c_"),
de_: RegisterPair("d_", "e_"),
hl_: RegisterPair("h_", "l_"),

// index register
ix: u16,
iy: u16,

i: u8,
r: u8,

// special purpose registers
pc: u16,
sp: u16,

// interrupt flip-flops
iff1: bool,
iff2: bool,

// interrupt mode
imode: enum { mode1, mode2, mode3 },

pub fn init() Z80 {
    return .{
        .memory = [_]u8{0} ** (1 << 16),

        .a = 0xff,
        .f = .{ .b = 0xff },

        .bc = .{ .w = 0 },
        .de = .{ .w = 0 },
        .hl = .{ .w = 0 },

        .af_ = .{ .w = 0 },
        .bc_ = .{ .w = 0 },
        .de_ = .{ .w = 0 },
        .hl_ = .{ .w = 0 },

        .ix = 0,
        .iy = 0,

        .i = 0,
        .r = 0,

        .pc = 0,
        .sp = 0xff,

        .iff1 = false,
        .iff2 = false,

        .imode = .mode1,
    };
}

pub fn step(z: *Z80) void {
    const opcode = z.nextb();

    z.exec_opcode(opcode);
}

fn exec_opcode(z: *Z80, opcode: u8) void {
    _ = z;

    switch (opcode) {
        0x00 => {},
        else => {
            @panic("unknown opcode");
        },
    }
}

fn rb(z: *Z80, addr: u16) u8 {
    return z.memory[addr];
}

fn wb(z: *Z80, addr: u16, val: u8) void {
    z.memory[addr] = val;
}

fn rw(z: *Z80, addr: u16) u16 {
    return (z.rb(addr + 1) << 8) | z.rb(addr);
}

fn ww(z: *Z80, addr: u16, val: u16) void {
    z.wb(addr + 1, val >> 8);
    z.wb(addr, val & 0xff);
}

fn nextb(z: *Z80) u8 {
    const val = z.rb(z.pc);

    z.pc += 1;

    return val;
}

fn nextw(z: *Z80, addr: u16) u16 {
    const val = z.rw(addr);

    z.pc += 2;

    return val;
}
