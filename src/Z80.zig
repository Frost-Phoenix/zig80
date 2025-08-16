const Z80 = @This();

// ********** imports ********** //

const std = @import("std");

// ********** types ********** //

const Flags = packed union {
    b: u8,
    f: packed struct(u8) {
        c: bool,
        n: bool,
        pv: bool,
        x: bool,
        h: bool,
        y: bool,
        z: bool,
        s: bool,
    },
};

pub const Z80Error = error{
    UnknownOpcode,
};

// ********** Z80 ********** //

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

// ********** public functions ********** //

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

pub fn step(z: *Z80) Z80Error!void {
    const opcode = z.nextb();

    try z.exec_opcode(opcode);
}

// ********** register helper functions ********** //

fn getBC(z: *Z80) u16 {
    return (@as(u16, z.b) << 8) | z.c;
}

fn setBC(z: *Z80, val: u16) void {
    z.b = @truncate(val >> 8);
    z.c = @truncate(val & 0xff);
}

fn getDE(z: *Z80) u16 {
    return (@as(u16, z.d) << 8) | z.e;
}

fn setDE(z: *Z80, val: u16) void {
    z.d = @truncate(val >> 8);
    z.e = @truncate(val & 0xff);
}

fn getHL(z: *Z80) u16 {
    return (@as(u16, z.h) << 8) | z.l;
}

fn setHL(z: *Z80, val: u16) void {
    z.h = @truncate(val >> 8);
    z.l = @truncate(val & 0xff);
}

// ********** helper functions ********** //

fn rb(z: *Z80, addr: u16) u8 {
    return z.memory[addr];
}

fn wb(z: *Z80, addr: u16, val: u8) void {
    z.memory[addr] = val;
}

fn rw(z: *Z80, addr: u16) u16 {
    return (@as(u16, z.rb(addr +% 1)) << 8) | z.rb(addr);
}

fn ww(z: *Z80, addr: u16, val: u16) void {
    z.wb(addr +% 1, @truncate(val >> 8));
    z.wb(addr, @truncate(val & 0xff));
}

fn nextb(z: *Z80) u8 {
    const val = z.rb(z.pc);

    z.pc +%= 1;

    return val;
}

fn nextw(z: *Z80) u16 {
    const val = z.rw(z.pc);

    z.pc +%= 2;

    return val;
}

// ********** private functions ********** //

fn exec_opcode(z: *Z80, opcode: u8) Z80Error!void {
    switch (opcode) {
        0x00 => {}, // nop

        0x7f => z.a = z.a, // ld a, a
        0x78 => z.a = z.b, // ld a, b
        0x79 => z.a = z.c, // ld a, c
        0x7a => z.a = z.d, // ld a, d
        0x7b => z.a = z.e, // ld a, e
        0x7c => z.a = z.h, // ld a, h
        0x7d => z.a = z.l, // ld a, l

        0x47 => z.b = z.a, // ld b, a
        0x40 => z.b = z.b, // ld b, b
        0x41 => z.b = z.c, // ld b, c
        0x42 => z.b = z.d, // ld b, d
        0x43 => z.b = z.e, // ld b, e
        0x44 => z.b = z.h, // ld b, h
        0x45 => z.b = z.l, // ld b, l

        0x4f => z.c = z.a, // ld c, a
        0x48 => z.c = z.b, // ld c, b
        0x49 => z.c = z.c, // ld c, c
        0x4a => z.c = z.d, // ld c, d
        0x4b => z.c = z.e, // ld c, e
        0x4c => z.c = z.h, // ld c, h
        0x4d => z.c = z.l, // ld c, l

        0x57 => z.d = z.a, // ld d, a
        0x50 => z.d = z.b, // ld d, b
        0x51 => z.d = z.c, // ld d, c
        0x52 => z.d = z.d, // ld d, d
        0x53 => z.d = z.e, // ld d, e
        0x54 => z.d = z.h, // ld d, h
        0x55 => z.d = z.l, // ld d, l

        0x5f => z.e = z.a, // ld e, a
        0x58 => z.e = z.b, // ld e, b
        0x59 => z.e = z.c, // ld e, c
        0x5a => z.e = z.d, // ld e, d
        0x5b => z.e = z.e, // ld e, e
        0x5c => z.e = z.h, // ld e, h
        0x5d => z.e = z.l, // ld e, l

        0x67 => z.h = z.a, // ld h, a
        0x60 => z.h = z.b, // ld h, b
        0x61 => z.h = z.c, // ld h, c
        0x62 => z.h = z.d, // ld h, d
        0x63 => z.h = z.e, // ld h, e
        0x64 => z.h = z.h, // ld h, h
        0x65 => z.h = z.l, // ld h, l

        0x6f => z.l = z.a, // ld l, a
        0x68 => z.l = z.b, // ld l, b
        0x69 => z.l = z.c, // ld l, c
        0x6a => z.l = z.d, // ld l, d
        0x6b => z.l = z.e, // ld l, e
        0x6c => z.l = z.h, // ld l, h
        0x6d => z.l = z.l, // ld l, l

        0x3e => z.a = z.nextb(), // ld a, n
        0x06 => z.b = z.nextb(), // ld b, n
        0x0e => z.c = z.nextb(), // ld c, n
        0x16 => z.d = z.nextb(), // ld d, n
        0x1e => z.e = z.nextb(), // ld e, n
        0x26 => z.h = z.nextb(), // ld h, n
        0x2e => z.l = z.nextb(), // ld l, n

        0x01 => z.setBC(z.nextw()), // ld bc, nn
        0x11 => z.setDE(z.nextw()), // ld de, nn
        0x21 => z.setHL(z.nextw()), // ld hl, nn

        0x0a => z.a = z.rb(z.getBC()), // ld a, (bc)
        0x1a => z.a = z.rb(z.getDE()), // ld a, (de)

        0x02 => z.wb(z.getBC(), z.a), // ld (bc), a
        0x12 => z.wb(z.getDE(), z.a), // ld (de), a

        0x7e => z.a = z.rb(z.getHL()), // ld a, (hl)
        0x46 => z.b = z.rb(z.getHL()), // ld b, (hl)
        0x4e => z.c = z.rb(z.getHL()), // ld c, (hl)
        0x56 => z.d = z.rb(z.getHL()), // ld d, (hl)
        0x5e => z.e = z.rb(z.getHL()), // ld e, (hl)
        0x66 => z.h = z.rb(z.getHL()), // ld h, (hl)
        0x6e => z.l = z.rb(z.getHL()), // ld l, (hl)

        0x36 => z.wb(z.getHL(), z.nextb()), // ld (hl), n
        0x77 => z.wb(z.getHL(), z.a), // ld (hl), a
        0x70 => z.wb(z.getHL(), z.b), // ld (hl), b
        0x71 => z.wb(z.getHL(), z.c), // ld (hl), c
        0x72 => z.wb(z.getHL(), z.d), // ld (hl), d
        0x73 => z.wb(z.getHL(), z.e), // ld (hl), e
        0x74 => z.wb(z.getHL(), z.h), // ld (hl), h
        0x75 => z.wb(z.getHL(), z.l), // ld (hl), l

        0x32 => z.wb(z.nextw(), z.a), // ld (nn), a
        0x22 => z.ww(z.nextw(), z.getHL()), // ld (nn), hl

        0x3a => z.a = z.rb(z.nextw()), // ld a, (nn)
        0x2a => z.setHL(z.rw(z.nextw())), // ld hl, (nn)

        0x31 => z.sp = z.nextw(), // ld sp, nn
        0xf9 => z.sp = z.getHL(), // ld sp, hl

        else => return Z80Error.UnknownOpcode,
    }
}
