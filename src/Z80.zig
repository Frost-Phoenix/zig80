const Z80 = @This();

// ********** //

const std = @import("std");

// ********** //


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
b: u8,
c: u8,
d: u8,
e: u8,
h: u8,
l: u8,

// alternate registers
af_: u16,
bc_: u16,
de_: u16,
hl_: u16,

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
        .b = 0,
        .c = 0,
        .d = 0,
        .e = 0,
        .h = 0,
        .l = 0,

        .af_ = 0,
        .bc_ = 0,
        .de_ = 0,
        .hl_ = 0,

        .ix = 0,
        .iy = 0,

        .i = 0,
        .r = 0,

        .pc = 0,
        .sp = 0xffff,

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
