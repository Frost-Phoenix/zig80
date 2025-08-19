const Z80 = @This();

// ********** imports ********** //

const std = @import("std");

// ********** types ********** //

const Flags = packed struct(u8) {
    c: bool,
    n: bool,
    pv: bool,
    x: bool,
    h: bool,
    y: bool,
    z: bool,
    s: bool,

    pub fn getF(f: *Flags) u8 {
        return @bitCast(f.*);
    }

    pub fn setF(f: *Flags, val: u8) void {
        f.* = @bitCast(val);
    }
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
        .f = @bitCast(@as(u8, 0xff)),
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

fn getBit(n: u5, val: u32) u1 {
    return @truncate((val >> n) & 1);
}

fn carry(bit: u5, a: u16, b: u16, cf: u1) bool {
    const res: u32 = @as(u32, a) + @as(u32, b) + cf;
    const c: u32 = res ^ a ^ b;

    return getBit(bit, c) == 1;
}

// ********** private functions ********** //

fn inc(z: *Z80, val: u8) u8 {
    const res = val +% 1;

    z.f.n = false;
    z.f.pv = val == 0x7f;
    z.f.x = getBit(3, res) == 1;
    z.f.h = val & 0x0f == 0x0f;
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    return res;
}

fn add(z: *Z80, a: u8, b: u8) u8 {
    const res = a +% b;

    z.f.c = carry(8, a, b, 0);
    z.f.n = false;
    z.f.pv = (a & 0x80 == b & 0x80) and (a & 0x80 != res & 0x80);
    z.f.x = getBit(3, res) == 1;
    z.f.h = carry(4, a, b, 0);
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    return res;
}

fn adc(z: *Z80, a: u8, b: u8) u8 {
    const carry_in = @intFromBool(z.f.c);
    const res = a +% b +% carry_in;

    z.f.c = carry(8, a, b, carry_in);
    z.f.n = false;
    z.f.pv = (a & 0x80 == b & 0x80) and (a & 0x80 != res & 0x80);
    z.f.x = getBit(3, res) == 1;
    z.f.h = carry(4, a, b, carry_in);
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    return res;
}

fn addw(z: *Z80, a: u16, b: u16) u16 {
    const res = a +% b;

    z.f.c = carry(16, a, b, 0);
    z.f.n = false;
    z.f.x = getBit(11, res) == 1;
    z.f.h = carry(12, a, b, 0);
    z.f.y = getBit(13, res) == 1;

    return res;
}

fn dec(z: *Z80, val: u8) u8 {
    const res = val -% 1;

    z.f.n = true;
    z.f.pv = val == 0x80;
    z.f.x = getBit(3, res) == 1;
    z.f.h = val & 0x0f == 0x00;
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    return res;
}

fn sub(z: *Z80, a: u8, b: u8) u8 {
    const res = a -% b;

    z.f.c = a < b;
    z.f.n = true;
    z.f.pv = (a & 0x80 != b & 0x80) and (a & 0x80 != res & 0x80);
    z.f.x = getBit(3, res) == 1;
    z.f.h = (a & 0xf) < (b & 0xf);
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    return res;
}

fn sbc(z: *Z80, a: u8, b: u8) u8 {
    const carry_in = @intFromBool(z.f.c);
    const res = a -% b -% carry_in;

    z.f.c = @as(u9, a) < @as(u9, b) + carry_in;
    z.f.n = true;
    z.f.pv = (a & 0x80 != b & 0x80) and (a & 0x80 != res & 0x80);
    z.f.x = getBit(3, res) == 1;
    z.f.h = @as(u9, a & 0xf) < @as(u9, b & 0xf) + carry_in;
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    return res;
}

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

        0x3c => z.a = z.inc(z.a), // inc a
        0x04 => z.b = z.inc(z.b), // inc b
        0x0c => z.c = z.inc(z.c), // inc c
        0x14 => z.d = z.inc(z.d), // inc d
        0x1c => z.e = z.inc(z.e), // inc e
        0x24 => z.h = z.inc(z.h), // inc h
        0x2c => z.l = z.inc(z.l), // inc l

        0x03 => z.setBC(z.getBC() + 1), // inc bc
        0x13 => z.setDE(z.getDE() + 1), // inc de
        0x23 => z.setHL(z.getHL() + 1), // inc hl
        0x33 => z.sp +%= 1, // inc sp

        0x34 => z.wb(z.getHL(), z.inc(z.rb(z.getHL()))), // inc (hl)

        0x87 => z.a = z.add(z.a, z.a), // add a, a
        0x80 => z.a = z.add(z.a, z.b), // add a, b
        0x81 => z.a = z.add(z.a, z.c), // add a, c
        0x82 => z.a = z.add(z.a, z.d), // add a, d
        0x83 => z.a = z.add(z.a, z.e), // add a, e
        0x84 => z.a = z.add(z.a, z.h), // add a, h
        0x85 => z.a = z.add(z.a, z.l), // add a, l

        0x09 => z.setHL(z.addw(z.getHL(), z.getBC())), // add hl, bc
        0x19 => z.setHL(z.addw(z.getHL(), z.getDE())), // add hl, de
        0x29 => z.setHL(z.addw(z.getHL(), z.getHL())), // add hl, hl
        0x39 => z.setHL(z.addw(z.getHL(), z.sp)), // add hl, sp

        0xc6 => z.a = z.add(z.a, z.nextb()), // add a, n
        0x86 => z.a = z.add(z.a, z.rb(z.getHL())), // add a, (hl)

        0x8f => z.a = z.adc(z.a, z.a), // adc a, a
        0x88 => z.a = z.adc(z.a, z.b), // adc a, b
        0x89 => z.a = z.adc(z.a, z.c), // adc a, c
        0x8a => z.a = z.adc(z.a, z.d), // adc a, d
        0x8b => z.a = z.adc(z.a, z.e), // adc a, e
        0x8c => z.a = z.adc(z.a, z.h), // adc a, h
        0x8d => z.a = z.adc(z.a, z.l), // adc a, l

        0xce => z.a = z.adc(z.a, z.nextb()), // adc a, n
        0x8e => z.a = z.adc(z.a, z.rb(z.getHL())), // adc a, (hl)

        0x3d => z.a = z.dec(z.a), // dec a
        0x05 => z.b = z.dec(z.b), // dec b
        0x0d => z.c = z.dec(z.c), // dec c
        0x15 => z.d = z.dec(z.d), // dec d
        0x1d => z.e = z.dec(z.e), // dec e
        0x25 => z.h = z.dec(z.h), // dec h
        0x2d => z.l = z.dec(z.l), // dec l

        0x0b => z.setBC(z.getBC() - 1), // dec bc
        0x1b => z.setDE(z.getDE() - 1), // dec de
        0x2b => z.setHL(z.getHL() - 1), // dec hl
        0x3b => z.sp -%= 1, // dec sp

        0x35 => z.wb(z.getHL(), z.dec(z.rb(z.getHL()))), // dec (hl)

        0x97 => z.a = z.sub(z.a, z.a), // sub a
        0x90 => z.a = z.sub(z.a, z.b), // sub b
        0x91 => z.a = z.sub(z.a, z.c), // sub c
        0x92 => z.a = z.sub(z.a, z.d), // sub d
        0x93 => z.a = z.sub(z.a, z.e), // sub e
        0x94 => z.a = z.sub(z.a, z.h), // sub h
        0x95 => z.a = z.sub(z.a, z.l), // sub l

        0xd6 => z.a = z.sub(z.a, z.nextb()), // sub n
        0x96 => z.a = z.sub(z.a, z.rb(z.getHL())), // sub (hl)

        0x9f => z.a = z.sbc(z.a, z.a), // sbc a, a
        0x98 => z.a = z.sbc(z.a, z.b), // sbc a, b
        0x99 => z.a = z.sbc(z.a, z.c), // sbc a, c
        0x9a => z.a = z.sbc(z.a, z.d), // sbc a, d
        0x9b => z.a = z.sbc(z.a, z.e), // sbc a, e
        0x9c => z.a = z.sbc(z.a, z.h), // sbc a, h
        0x9d => z.a = z.sbc(z.a, z.l), // sbc a, l

        0xde => z.a = z.sbc(z.a, z.nextb()), // sbc a, n
        0x9e => z.a = z.sbc(z.a, z.rb(z.getHL())), // sbc a, (hl)

        else => return Z80Error.UnknownOpcode,
    }
}
