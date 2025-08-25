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

const RotateDir = enum {
    left,
    right,
};

pub const Z80Error = error{
    UnknownOpcode,
};

const memReadFnPtr = *const fn (addr: u16) u8;
const memWriteFnPtr = *const fn (addr: u16, val: u8) void;
const ioReadFnPtr = *const fn (addr: u16) u8;
const ioWriteFnPtr = *const fn (addr: u16, val: u8) void;

pub const Z80Config = struct {
    memRead: memReadFnPtr,
    memWrite: memWriteFnPtr,

    ioRead: ioReadFnPtr,
    ioWrite: ioWriteFnPtr,
};

// ********** Z80 ********** //

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
imode: enum { mode0, mode1, mode2 },

// Simulate Q register, used in scf/ccf flags calculation
// If the last instruction changed the flags, Q = F, else Q = 0
q: struct {
    val: u8,
    changed: bool,

    const Self = @This();

    pub fn set(self: *Self, val: u8) void {
        self.val = val;
        self.changed = true;
    }

    pub fn reset(self: *Self) void {
        self.val = 0;
    }
},

memRead: memReadFnPtr,
memWrite: memWriteFnPtr,

ioRead: ioReadFnPtr,
ioWrite: ioWriteFnPtr,

// ********** public functions ********** //

pub fn init(config: Z80Config) Z80 {
    return .{
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

        .q = .{ .val = 0, .changed = false },

        .pc = 0,
        .sp = 0xffff,

        .iff1 = false,
        .iff2 = false,

        .imode = .mode0,

        .memRead = config.memRead,
        .memWrite = config.memWrite,

        .ioRead = config.ioRead,
        .ioWrite = config.ioWrite,
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

fn getAF(z: *Z80) u16 {
    return (@as(u16, z.a) << 8) | z.f.getF();
}

fn setAF(z: *Z80, val: u16) void {
    z.a = @truncate(val >> 8);
    z.f.setF(@truncate(val & 0xff));
}

// ********** helper functions ********** //

fn rb(z: *Z80, addr: u16) u8 {
    return z.memRead(addr);
}

fn wb(z: *Z80, addr: u16, val: u8) void {
    z.memWrite(addr, val);
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

fn parity(val: u8) bool {
    var nb: u8 = 0;

    for (0..8) |i| {
        const bit: u3 = @intCast(i);

        nb += (val >> bit) & 1;
    }

    return nb % 2 == 0;
}

fn swap(a: *u16, b: *u16) void {
    const tmp = a.*;

    a.* = b.*;
    b.* = tmp;
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

    z.q.set(z.f.getF());

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

    z.q.set(z.f.getF());

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

    z.q.set(z.f.getF());

    return res;
}

fn addw(z: *Z80, a: u16, b: u16) u16 {
    const res = a +% b;

    z.f.c = carry(16, a, b, 0);
    z.f.n = false;
    z.f.x = getBit(11, res) == 1;
    z.f.h = carry(12, a, b, 0);
    z.f.y = getBit(13, res) == 1;

    z.q.set(z.f.getF());

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

    z.q.set(z.f.getF());

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

    z.q.set(z.f.getF());

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

    z.q.set(z.f.getF());

    return res;
}

/// DAA corrects the value of the accumulator back to BCD (Binary-Coded Decimal)
///
/// Depending on the NF flag, the ‘diff’ from this table must be added (NF is reset)
/// or subtracted (NF is set) to A.
///
/// | CF | high_nibble | HF | low_nibble | diff |
/// |:--:|:-----------:|:--:|:----------:|:----:|
/// | 0  |     0-9     | 0  |    0-9     |  00  |
/// | 0  |     0-9     | 1  |    0-9     |  06  |
/// | 0  |     0-8     | *  |    a-f     |  06  |
/// | 0  |     a-f     | 0  |    0-9     |  60  |
/// | 1  |      *      | 0  |    0-9     |  60  |
/// | 1  |      *      | 1  |    0-9     |  66  |
/// | 1  |      *      | *  |    a-f     |  66  |
/// | 0  |     9-f     | *  |    a-f     |  66  |
/// | 0  |     a-f     | 1  |    0-9     |  66  |
///
/// The CF flag is affected as follows:
///
/// | CF | high_nibble | low_nibble | CF' |
/// |:--:|:-----------:|:----------:|:---:|
/// | 0  |     0-9     |     0-9    |  0  |
/// | 0  |     0-8     |     a-f    |  0  |
/// | 0  |     9-f     |     a-f    |  1  |
/// | 0  |     a-f     |     0-9    |  1  |
/// | 1  |      *      |      *     |  1  |
///
/// The HF flags is affected as follows:
///
/// | NF | HF | low nibble | HF' |
/// |:--:|:--:|:----------:|:---:|
/// | 0  | *  |    0-9     |  0  |
/// | 0  | *  |    a-f     |  1  |
/// | 1  | 0  |     *      |  0  |
/// | 1  | 1  |    6-f     |  0  |
/// | 1  | 1  |    0-5     |  1  |
///
/// (from: http://www.z80.info/zip/z80-documented.pdf)
fn daa(z: *Z80) u8 {
    var diff: u8 = 0;

    const n_h: u4 = @truncate(z.a >> 4); // nibble high
    const n_l: u4 = @truncate(z.a & 0xf); // nibble low

    // diff
    if (z.f.c == false) {
        if ((z.f.h == true and n_h <= 0x9 and n_l <= 0x9) or (n_h <= 0x8 and n_l >= 0xa)) {
            diff = 0x06;
        } else if (z.f.h == false and n_h >= 0xa and n_l <= 0x9) {
            diff = 0x60;
        } else if ((n_h >= 0x9 and n_l >= 0xa) or (z.f.h == true and n_h >= 0xa and n_l <= 0x9)) {
            diff = 0x66;
        }
    } else {
        if (z.f.h == false and n_l <= 0x9) {
            diff = 0x60;
        } else {
            diff = 0x66;
        }
    }

    // CF
    if (z.f.c == false) {
        if ((n_h <= 0x9 and n_l <= 0x9) or (n_h <= 0x8 and n_l >= 0xa)) {
            z.f.c = false;
        } else {
            z.f.c = true;
        }
    }

    // NF
    if (z.f.n == false) {
        z.f.h = !(n_l <= 0x9);
    } else {
        z.f.h = z.f.h == true and n_l <= 0x5;
    }

    const res = switch (z.f.n) {
        true => z.a -% diff,
        false => z.a +% diff,
    };

    z.f.pv = parity(res);
    z.f.x = getBit(3, res) == 1;
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    z.q.set(z.f.getF());

    return res;
}

fn land(z: *Z80, val: u8) u8 {
    const res = z.a & val;

    z.f.c = false;
    z.f.n = false;
    z.f.pv = parity(res);
    z.f.x = getBit(3, res) == 1;
    z.f.h = true;
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    z.q.set(z.f.getF());

    return res;
}

fn lxor(z: *Z80, val: u8) u8 {
    const res = z.a ^ val;

    z.f.c = false;
    z.f.n = false;
    z.f.pv = parity(res);
    z.f.x = getBit(3, res) == 1;
    z.f.h = false;
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    z.q.set(z.f.getF());

    return res;
}

fn lor(z: *Z80, val: u8) u8 {
    const res = z.a | val;

    z.f.c = false;
    z.f.n = false;
    z.f.pv = parity(res);
    z.f.x = getBit(3, res) == 1;
    z.f.h = false;
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    z.q.set(z.f.getF());

    return res;
}

fn scf(z: *Z80) void {
    z.f.c = true;
    z.f.n = false;
    z.f.h = false;

    if (z.q.val != 0) {
        z.f.x = getBit(3, z.a) == 1;
        z.f.y = getBit(5, z.a) == 1;
    } else {
        z.f.x = z.f.x or getBit(3, z.a) == 1;
        z.f.y = z.f.y or getBit(5, z.a) == 1;
    }

    z.q.set(z.f.getF());
}

fn ccf(z: *Z80) void {
    const old_cf = z.f.c;

    z.f.c = !z.f.c;
    z.f.n = false;
    z.f.h = old_cf;

    if (z.q.val != 0) {
        z.f.x = getBit(3, z.a) == 1;
        z.f.y = getBit(5, z.a) == 1;
    } else {
        z.f.x = z.f.x or getBit(3, z.a) == 1;
        z.f.y = z.f.y or getBit(5, z.a) == 1;
    }

    z.q.set(z.f.getF());
}

fn cpl(z: *Z80) void {
    z.a = ~z.a;

    z.f.n = true;
    z.f.x = getBit(3, z.a) == 1;
    z.f.h = true;
    z.f.y = getBit(5, z.a) == 1;

    z.q.set(z.f.getF());
}

fn rotate(z: *Z80, val: u8, dir: RotateDir, loop: bool) u8 {
    var res: u8 = switch (dir) {
        .left => val << 1,
        .right => val >> 1,
    };

    const old_cf: u8 = @intFromBool(z.f.c);
    const new_cf: u8 = switch (dir) {
        .left => val >> 7,
        .right => val & 1,
    };

    switch (dir) {
        .left => res |= if (loop) new_cf else old_cf,
        .right => res |= if (loop) new_cf << 7 else old_cf << 7,
    }

    z.f.c = new_cf == 1;
    z.f.n = false;
    z.f.x = getBit(3, res) == 1;
    z.f.h = false;
    z.f.y = getBit(5, res) == 1;

    z.q.set(z.f.getF());

    return res;
}

fn cp(z: *Z80, val: u8) void {
    const res = z.a -% val;

    z.f.c = z.a < val;
    z.f.n = true;
    z.f.pv = (z.a & 0x80 != val & 0x80) and (z.a & 0x80 != res & 0x80);
    z.f.x = getBit(3, val) == 1;
    z.f.h = (z.a & 0xf) < (val & 0xf);
    z.f.y = getBit(5, val) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    z.q.set(z.f.getF());
}

fn push(z: *Z80, val: u16) void {
    z.sp -%= 2;
    z.ww(z.sp, val);
}

fn pop(z: *Z80) u16 {
    const res = z.rw(z.sp);

    z.sp +%= 2;

    return res;
}

fn jump(z: *Z80, addr: u16, condition: bool) void {
    if (!condition) return;

    z.pc = addr;
}

fn jr(z: *Z80, offset: u8, condition: bool) void {
    if (!condition) return;

    const offset_signed: i8 = @bitCast(offset);

    z.pc +%= @as(u16, @bitCast(@as(i16, offset_signed)));
}

fn djnz(z: *Z80, addr: u8) void {
    z.b -%= 1;

    if (z.b != 0) {
        z.jr(addr, true);
    }
}

fn call(z: *Z80, addr: u16, condition: bool) void {
    if (!condition) return;

    z.push(z.pc);
    z.pc = addr;
}

fn ret(z: *Z80, condition: bool) void {
    if (!condition) return;

    z.pc = z.pop();
}

fn rst(z: *Z80, addr: u8) void {
    z.push(z.pc);

    z.pc = @intCast(addr);
}

fn di(z: *Z80) void {
    z.iff1 = false;
    z.iff2 = false;
}

fn ei(z: *Z80) void {
    z.iff1 = true;
    z.iff2 = true;
}

fn out(z: *Z80, high_byte: u8, port: u8, val: u8) void {
    const addr = (@as(u16, high_byte) << 8) | port;

    z.ioWrite(addr, val);
}

fn in(z: *Z80, high_byte: u8, port: u8, update_flags: bool) u8 {
    const addr = (@as(u16, high_byte) << 8) | port;
    const res = z.ioRead(addr);

    if (update_flags) {
        z.f.n = false;
        z.f.pv = parity(res);
        z.f.x = getBit(3, res) == 1;
        z.f.h = false;
        z.f.y = getBit(5, res) == 1;
        z.f.z = res == 0;
        z.f.s = (res >> 7) == 1;

        z.q.set(z.f.getF());
    }

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

        0x27 => z.a = z.daa(), // daa

        0xa7 => z.a = z.land(z.a), // and a
        0xa0 => z.a = z.land(z.b), // and b
        0xa1 => z.a = z.land(z.c), // and c
        0xa2 => z.a = z.land(z.d), // and d
        0xa3 => z.a = z.land(z.e), // and e
        0xa4 => z.a = z.land(z.h), // and h
        0xa5 => z.a = z.land(z.l), // and l

        0xe6 => z.a = z.land(z.nextb()), // and n
        0xa6 => z.a = z.land(z.rb(z.getHL())), // and (hl)

        0xa8 => z.a = z.lxor(z.b), // xor b
        0xaf => z.a = z.lxor(z.a), // xor a
        0xa9 => z.a = z.lxor(z.c), // xor c
        0xaa => z.a = z.lxor(z.d), // xor d
        0xab => z.a = z.lxor(z.e), // xor e
        0xac => z.a = z.lxor(z.h), // xor h
        0xad => z.a = z.lxor(z.l), // xor l

        0xee => z.a = z.lxor(z.nextb()), // xor n
        0xae => z.a = z.lxor(z.rb(z.getHL())), // xor (hl)

        0xb7 => z.a = z.lor(z.a), // or a
        0xb0 => z.a = z.lor(z.b), // or b
        0xb1 => z.a = z.lor(z.c), // or c
        0xb2 => z.a = z.lor(z.d), // or d
        0xb3 => z.a = z.lor(z.e), // or e
        0xb4 => z.a = z.lor(z.h), // or h
        0xb5 => z.a = z.lor(z.l), // or l

        0xf6 => z.a = z.lor(z.nextb()), // or n
        0xb6 => z.a = z.lor(z.rb(z.getHL())), // or (hl)

        0x37 => z.scf(), // scf
        0x3f => z.ccf(), // ccf

        0x2f => z.cpl(), // cpl

        0x17 => z.a = z.rotate(z.a, .left, false), // rla
        0x07 => z.a = z.rotate(z.a, .left, true), // rlca

        0x1f => z.a = z.rotate(z.a, .right, false), // rra
        0x0f => z.a = z.rotate(z.a, .right, true), // rrca

        0xd9 => {
            var bc: u16 = z.getBC();
            var de: u16 = z.getDE();
            var hl: u16 = z.getHL();

            swap(&bc, &z.bc_);
            swap(&de, &z.de_);
            swap(&hl, &z.hl_);

            z.setBC(bc);
            z.setDE(de);
            z.setHL(hl);
        }, // exx
        0xeb => {
            var de: u16 = z.getDE();
            var hl: u16 = z.getHL();

            swap(&de, &hl);

            z.setDE(de);
            z.setHL(hl);
        }, // ex de, hl
        0x08 => {
            var af: u16 = z.getAF();

            swap(&af, &z.af_);

            z.f.setF(@truncate(af));
            z.a = @truncate(af >> 8);
        }, // ex af, af'
        0xe3 => {
            var val: u16 = z.rw(z.sp);
            var hl: u16 = z.getHL();

            swap(&val, &hl);

            z.ww(z.sp, val);
            z.setHL(hl);
        }, // ex (sp), hl

        0xbf => z.cp(z.a), // cp a
        0xb8 => z.cp(z.b), // cp b
        0xb9 => z.cp(z.c), // cp c
        0xba => z.cp(z.d), // cp d
        0xbb => z.cp(z.e), // cp e
        0xbc => z.cp(z.h), // cp h
        0xbd => z.cp(z.l), // cp l

        0xfe => z.cp(z.nextb()), // cp n
        0xbe => z.cp(z.rb(z.getHL())), // cp (hl)

        0xc5 => z.push(z.getBC()), // push bc
        0xd5 => z.push(z.getDE()), // push de
        0xe5 => z.push(z.getHL()), // push hl
        0xf5 => z.push(z.getAF()), // push af

        0xc1 => z.setBC(z.pop()), // pop bc
        0xd1 => z.setDE(z.pop()), // pop de
        0xe1 => z.setHL(z.pop()), // pop hl
        0xf1 => z.setAF(z.pop()), // pop af

        0xc3 => z.jump(z.nextw(), true), // jp nn
        0xe9 => z.jump(z.getHL(), true), // jp (hl)

        0xca => z.jump(z.nextw(), z.f.z), // jp z, nn
        0xda => z.jump(z.nextw(), z.f.c), // jp c, nn
        0xea => z.jump(z.nextw(), z.f.pv), // jp pe, nn
        0xfa => z.jump(z.nextw(), z.f.s), // jp m, nn

        0xc2 => z.jump(z.nextw(), !z.f.z), // jp nz, nn
        0xd2 => z.jump(z.nextw(), !z.f.c), // jp nc, nn
        0xe2 => z.jump(z.nextw(), !z.f.pv), // jp po, nn
        0xf2 => z.jump(z.nextw(), !z.f.s), // jp p, nn

        0x18 => z.jr(z.nextb(), true), // jr d

        0x28 => z.jr(z.nextb(), z.f.z), // jr z, d
        0x38 => z.jr(z.nextb(), z.f.c), // jr c, d

        0x20 => z.jr(z.nextb(), !z.f.z), // jr nz, d
        0x30 => z.jr(z.nextb(), !z.f.c), // jr nc, d

        0x10 => z.djnz(z.nextb()), // djnz d

        0xcd => z.call(z.nextw(), true), // call nn

        0xcc => z.call(z.nextw(), z.f.z), // call z, nn
        0xdc => z.call(z.nextw(), z.f.c), // call c, nn
        0xec => z.call(z.nextw(), z.f.pv), // call pe, nn
        0xfc => z.call(z.nextw(), z.f.s), // call m, nn

        0xc4 => z.call(z.nextw(), !z.f.z), // call nz, nn
        0xd4 => z.call(z.nextw(), !z.f.c), // call nc, nn
        0xe4 => z.call(z.nextw(), !z.f.pv), // call po, nn
        0xf4 => z.call(z.nextw(), !z.f.s), // call p, nn

        0xc9 => z.ret(true), // ret

        0xc8 => z.ret(z.f.z), // ret z
        0xd8 => z.ret(z.f.c), // ret c
        0xe8 => z.ret(z.f.pv), // ret pe
        0xf8 => z.ret(z.f.s), // ret m

        0xc0 => z.ret(!z.f.z), // ret nz
        0xd0 => z.ret(!z.f.c), // ret nc
        0xe0 => z.ret(!z.f.pv), // ret po
        0xf0 => z.ret(!z.f.s), // ret p

        0xc7 => z.rst(0x00), // rst 00h
        0xd7 => z.rst(0x10), // rst 10h
        0xe7 => z.rst(0x20), // rst 20h
        0xf7 => z.rst(0x30), // rst 30h
        0xcf => z.rst(0x08), // rst 08h
        0xdf => z.rst(0x18), // rst 18h
        0xef => z.rst(0x28), // rst 28h
        0xff => z.rst(0x38), // rst 38h

        0xf3 => z.di(), // di
        0xfb => z.ei(), // ei

        0xd3 => z.out(z.a, z.nextb(), z.a), // out (n), a
        0xdb => z.a = z.in(z.a, z.nextb(), false), // in a, (n)

        0xed => try z.exec_opcode_ed(z.nextb()), // ed prefixed opcodes

        else => return Z80Error.UnknownOpcode,
    }

    if (!z.q.changed) {
        z.q.reset();
    } else {
        z.q.changed = false;
    }
}

fn exec_opcode_ed(z: *Z80, opcode: u8) Z80Error!void {
    switch (opcode) {
        0x4b => z.setBC(z.rw(z.nextw())), // ld bc, (nn)
        0x5b => z.setDE(z.rw(z.nextw())), // ld de, (nn)
        0x6b => z.setHL(z.rw(z.nextw())), // ld hl, (nn)
        0x7b => z.sp = z.rw(z.nextw()), // ld sp, (nn)

        0x43 => z.ww(z.nextw(), z.getBC()), // ld (nn), bc
        0x53 => z.ww(z.nextw(), z.getDE()), // ld (nn), de
        0x63 => z.ww(z.nextw(), z.getHL()), // ld (nn), hl
        0x73 => z.ww(z.nextw(), z.sp), // ld (nn), sp

        0x44 => z.a = z.sub(0, z.a), // neg

        0x46 => z.imode = .mode0, // im 0
        0x56 => z.imode = .mode1, // im 1
        0x5e => z.imode = .mode2, // im 2

        0x78 => z.a = z.in(z.b, z.c, true), // in a, (c)
        0x40 => z.b = z.in(z.b, z.c, true), // in b, (c)
        0x48 => z.c = z.in(z.b, z.c, true), // in c, (c)
        0x50 => z.d = z.in(z.b, z.c, true), // in d, (c)
        0x58 => z.e = z.in(z.b, z.c, true), // in e, (c)
        0x60 => z.h = z.in(z.b, z.c, true), // in h, (c)
        0x68 => z.l = z.in(z.b, z.c, true), // in l, (c)

        0x79 => z.out(z.b, z.c, z.a), // out (c), a
        0x41 => z.out(z.b, z.c, z.b), // out (c), b
        0x49 => z.out(z.b, z.c, z.c), // out (c), c
        0x51 => z.out(z.b, z.c, z.d), // out (c), d
        0x59 => z.out(z.b, z.c, z.e), // out (c), e
        0x61 => z.out(z.b, z.c, z.h), // out (c), h
        0x69 => z.out(z.b, z.c, z.l), // out (c), l

        0x70 => _ = z.in(z.b, z.c, true), // in (c)
        0x71 => z.out(z.b, z.c, 0), // out (c), 0

        else => return Z80Error.UnknownOpcode,
    }
}
