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

const ShiftDir = enum {
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

// MEMPTR
wz: u16,

// special purpose registers
pc: u16,
sp: u16,

// interrupt flip-flops
iff1: bool,
iff2: bool,

// interrupt mode
imode: enum { mode0, mode1, mode2 },

is_halted: bool,

memRead: memReadFnPtr,
memWrite: memWriteFnPtr,

ioRead: ioReadFnPtr,
ioWrite: ioWriteFnPtr,

// ********** public functions ********** //

pub fn init(config: Z80Config) Z80 {
    var z: Z80 = undefined;

    z.reset();

    z.memRead = config.memRead;
    z.memWrite = config.memWrite;

    z.ioRead = config.ioRead;
    z.ioWrite = config.ioWrite;

    return z;
}

pub fn reset(z: *Z80) void {
    z.a = 0xff;
    z.f = @bitCast(@as(u8, 0xff));
    z.b = 0;
    z.c = 0;
    z.d = 0;
    z.e = 0;
    z.h = 0;
    z.l = 0;

    z.af_ = 0;
    z.bc_ = 0;
    z.de_ = 0;
    z.hl_ = 0;

    z.ix = 0;
    z.iy = 0;

    z.i = 0;
    z.r = 0;

    z.q = .{ .val = 0, .changed = false };

    z.wz = 0;

    z.pc = 0;
    z.sp = 0xffff;

    z.iff1 = false;
    z.iff2 = false;

    z.imode = .mode0;

    z.is_halted = false;
}

pub fn step(z: *Z80) Z80Error!void {
    if (z.is_halted) {
        return;
    }

    const opcode = z.nextb();

    try z.exec_opcode(opcode);

    if (!z.q.changed) {
        z.q.reset();
    } else {
        z.q.changed = false;
    }
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

// used for ldWordAddr
fn setSP(z: *Z80, val: u16) void {
    z.sp = val;
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

fn setBit(bit: u3, val: u8) u8 {
    return val | (@as(u8, 1) << bit);
}

fn resetBit(bit: u3, val: u8) u8 {
    return val & ~(@as(u8, 1) << bit);
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

fn ldAAddr(z: *Z80, addr: u16) void {
    const val = z.rb(addr);

    z.a = val;

    z.wz = addr +% 1;
}

fn ldAddrA(z: *Z80, addr: u16) void {
    z.wb(addr, z.a);

    z.wz = (@as(u16, z.a) << 8) | ((addr +% 1) & 0xff);
}

fn ldWordAddr(z: *Z80, setReg: fn (*Z80, u16) void, addr: u16) void {
    const val = z.rw(addr);

    setReg(z, val);

    z.wz = addr +% 1;
}

fn ldAddrWord(z: *Z80, addr: u16, val: u16) void {
    z.ww(addr, val);

    z.wz = addr +% 1;
}

fn inc_r(z: *Z80) void {
    z.r = (z.r & 0x80) | ((z.r +% 1) & 0x7f);
}

fn dec_r(z: *Z80) void {
    z.r = (z.r & 0x80) | ((z.r -% 1) & 0x7f);
}

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

    z.wz = a +% 1;

    return res;
}

fn adcw(z: *Z80, a: u16, b: u16) u16 {
    const carry_in = @intFromBool(z.f.c);
    const res = a +% b +% carry_in;

    z.f.c = carry(16, a, b, carry_in);
    z.f.n = false;
    z.f.pv = (a & 0x8000 == b & 0x8000) and (a & 0x8000 != res & 0x8000);
    z.f.x = getBit(11, res) == 1;
    z.f.h = carry(12, a, b, carry_in);
    z.f.y = getBit(13, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 15) == 1;

    z.q.set(z.f.getF());

    z.wz = a +% 1;

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

fn sbcw(z: *Z80, a: u16, b: u16) u16 {
    const carry_in = @intFromBool(z.f.c);
    const res = a -% b -% carry_in;

    z.f.c = @as(u17, a) < @as(u17, b) + carry_in;
    z.f.n = true;
    z.f.pv = (a & 0x8000 != b & 0x8000) and (a & 0x8000 != res & 0x8000);
    z.f.x = getBit(11, res) == 1;
    z.f.h = @as(u17, a & 0xfff) < @as(u17, b & 0xfff) + carry_in;
    z.f.y = getBit(13, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 15) == 1;

    z.q.set(z.f.getF());

    z.wz = a +% 1;

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
    z.f.pv = parity(res);
    z.f.x = getBit(3, res) == 1;
    z.f.h = false;
    z.f.y = getBit(5, res) == 1;
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    z.q.set(z.f.getF());

    return res;
}

fn rotateA(z: *Z80, dir: RotateDir, loop: bool) u8 {
    const old_f = z.f;

    const res = z.rotate(z.a, dir, loop);

    z.f.pv = old_f.pv;
    z.f.z = old_f.z;
    z.f.s = old_f.s;

    z.q.set(z.f.getF());

    return res;
}

fn shift(z: *Z80, val: u8, dir: ShiftDir, fill: bool) u8 {
    var res: u8 = switch (dir) {
        .left => val << 1,
        .right => val >> 1,
    };

    switch (dir) {
        .left => res |= if (fill) 1 else 0,
        .right => res |= if (fill) val & 0x80 else 0 << 7,
    }

    const new_cf: u8 = switch (dir) {
        .left => val >> 7,
        .right => val & 1,
    };

    z.f.c = new_cf == 1;
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

fn rrd(z: *Z80) void {
    const val = z.rb(z.getHL());
    var res: u8 = 0;

    const a_low_nibble: u4 = @truncate(z.a & 0xf);
    const val_low_nibble: u4 = @truncate(val & 0xf);
    const val_high_nibble: u4 = @truncate((val & 0xf0) >> 4);

    z.a = (z.a & 0xf0) | val_low_nibble;
    res |= val_high_nibble;
    res |= @as(u8, a_low_nibble) << 4;

    z.wb(z.getHL(), res);

    z.f.n = false;
    z.f.pv = parity(z.a);
    z.f.x = getBit(3, z.a) == 1;
    z.f.h = false;
    z.f.y = getBit(5, z.a) == 1;
    z.f.z = z.a == 0;
    z.f.s = (z.a >> 7) == 1;

    z.q.set(z.f.getF());

    z.wz = z.getHL() +% 1;
}

fn rld(z: *Z80) void {
    const val = z.rb(z.getHL());
    var res: u8 = 0;

    const a_low_nibble: u4 = @truncate(z.a & 0xf);
    const val_low_nibble: u4 = @truncate(val & 0xf);
    const val_high_nibble: u4 = @truncate((val & 0xf0) >> 4);

    z.a = (z.a & 0xf0) | val_high_nibble;
    res |= a_low_nibble;
    res |= @as(u8, val_low_nibble) << 4;

    z.wb(z.getHL(), res);

    z.f.n = false;
    z.f.pv = parity(z.a);
    z.f.x = getBit(3, z.a) == 1;
    z.f.h = false;
    z.f.y = getBit(5, z.a) == 1;
    z.f.z = z.a == 0;
    z.f.s = (z.a >> 7) == 1;

    z.q.set(z.f.getF());

    z.wz = z.getHL() +% 1;
}

fn bit_test(z: *Z80, bit: u3, val: u8) void {
    z.f.n = false;
    z.f.pv = getBit(bit, val) == 0;
    z.f.x = getBit(3, val) == 1;
    z.f.h = true;
    z.f.y = getBit(5, val) == 1;
    z.f.z = getBit(bit, val) == 0;
    z.f.s = bit == 7 and getBit(7, val) == 1;

    z.q.set(z.f.getF());
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
    z.wz = addr;

    if (!condition) return;

    z.pc = addr;
}

fn jr(z: *Z80, offset: u8, condition: bool) void {
    if (!condition) return;

    const offset_signed: u16 = @bitCast(@as(i16, @as(i8, @bitCast(offset))));

    z.wz = z.pc +% offset_signed;

    z.pc +%= offset_signed;
}

fn djnz(z: *Z80, addr: u8) void {
    z.b -%= 1;

    if (z.b != 0) {
        z.jr(addr, true);
    }
}

fn call(z: *Z80, addr: u16, condition: bool) void {
    z.wz = addr;

    if (!condition) return;

    z.push(z.pc);
    z.pc = addr;
}

fn ret(z: *Z80, condition: bool) void {
    if (!condition) return;

    z.wz = z.rw(z.sp);

    z.pc = z.pop();
}

fn rst(z: *Z80, addr: u8) void {
    z.push(z.pc);

    z.pc = @intCast(addr);

    z.wz = z.pc;
}

fn di(z: *Z80) void {
    z.iff1 = false;
    z.iff2 = false;
}

fn ei(z: *Z80) void {
    z.iff1 = true;
    z.iff2 = true;
}

fn retn(z: *Z80) void {
    z.iff1 = z.iff2;

    z.ret(true);
}

fn out(z: *Z80, high_byte: u8, port: u8, val: u8) void {
    const addr = (@as(u16, high_byte) << 8) | port;

    z.ioWrite(addr, val);

    z.wz = z.getBC() +% 1;
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

    z.wz = z.getBC() +% 1;

    return res;
}

fn ld_a_i(z: *Z80) void {
    z.a = z.i;

    z.f.n = false;
    z.f.pv = z.iff2;
    z.f.x = getBit(3, z.a) == 1;
    z.f.h = false;
    z.f.y = getBit(5, z.a) == 1;
    z.f.z = z.a == 0;
    z.f.s = (z.a >> 7) == 1;

    z.q.set(z.f.getF());
}

fn ld_a_r(z: *Z80) void {
    z.a = z.r;

    z.f.n = false;
    z.f.pv = z.iff2;
    z.f.x = getBit(3, z.a) == 1;
    z.f.h = false;
    z.f.y = getBit(5, z.a) == 1;
    z.f.z = z.a == 0;
    z.f.s = (z.a >> 7) == 1;

    z.q.set(z.f.getF());
}

fn ldi(z: *Z80) void {
    const bc = z.getBC();
    const de = z.getDE();
    const hl = z.getHL();

    const val = z.rb(hl);

    z.wb(de, val);

    z.setBC(bc -% 1);
    z.setDE(de +% 1);
    z.setHL(hl +% 1);

    z.f.n = false;
    z.f.pv = (bc -% 1) != 0;
    z.f.x = getBit(3, z.a +% val) == 1;
    z.f.h = false;
    z.f.y = getBit(1, z.a +% val) == 1;

    z.q.set(z.f.getF());
}

fn ldd(z: *Z80) void {
    z.ldi();

    z.setDE(z.getDE() -% 2);
    z.setHL(z.getHL() -% 2);
}

fn ldir(z: *Z80) void {
    z.ldi();

    if (z.getBC() != 0) {
        z.pc -%= 2;

        z.f.x = getBit(11, z.pc) == 1;
        z.f.y = getBit(13, z.pc) == 1;

        z.q.set(z.f.getF());

        z.wz = z.pc +% 1;
    }
}

fn lddr(z: *Z80) void {
    z.ldd();

    if (z.getBC() != 0) {
        z.pc -%= 2;

        z.f.x = getBit(11, z.pc) == 1;
        z.f.y = getBit(13, z.pc) == 1;

        z.q.set(z.f.getF());

        z.wz = z.pc +% 1;
    }
}

fn cpi(z: *Z80) void {
    const bc = z.getBC();
    const hl = z.getHL();

    const val = z.rb(hl);
    const res = z.a -% val;

    z.setBC(bc -% 1);
    z.setHL(hl +% 1);

    z.f.n = true;
    z.f.pv = (bc -% 1) != 0;
    z.f.h = (z.a & 0xf) < (val & 0xf);
    z.f.z = res == 0;
    z.f.s = (res >> 7) == 1;

    z.f.x = getBit(3, res -% @intFromBool(z.f.h)) == 1;
    z.f.y = getBit(1, res -% @intFromBool(z.f.h)) == 1;

    z.q.set(z.f.getF());

    z.wz +%= 1;
}

fn cpd(z: *Z80) void {
    z.cpi();

    z.setHL(z.getHL() -% 2);

    z.wz -%= 2;
}

fn cpir(z: *Z80) void {
    z.cpi();

    if (z.getBC() != 0 and z.f.z == false) {
        z.pc -%= 2;

        z.f.x = getBit(11, z.pc) == 1;
        z.f.y = getBit(13, z.pc) == 1;

        z.q.set(z.f.getF());

        z.wz = z.pc +% 1;
    }
}

fn cpdr(z: *Z80) void {
    z.cpd();

    if (z.getBC() != 0) {
        z.pc -%= 2;

        z.f.x = getBit(11, z.pc) == 1;
        z.f.y = getBit(13, z.pc) == 1;

        z.q.set(z.f.getF());

        z.wz = z.pc +% 1;
    }
}

fn ini(z: *Z80) void {
    const hl = z.getHL();
    const val = z.in(z.b, z.c, false);

    z.wz = z.getBC() +% 1;

    z.wb(hl, val);

    z.b = z.dec(z.b);
    z.setHL(hl +% 1);

    const val_16 = @as(u16, val);
    const carry_test = (val_16 + ((z.c +% 1) & 255)) > 255;

    z.f.c = carry_test;
    z.f.n = (val >> 7) == 1;
    z.f.pv = parity(((val +% ((z.c +% 1) & 255)) & 7) ^ z.b);
    z.f.h = carry_test;

    z.q.set(z.f.getF());
}

fn ind(z: *Z80) void {
    const hl = z.getHL();
    const val = z.in(z.b, z.c, false);

    z.wz = z.getBC() -% 1;

    z.wb(hl, val);

    z.b = z.dec(z.b);
    z.setHL(hl -% 1);

    const val_16 = @as(u16, val);
    const carry_test = (val_16 +% ((z.c -% 1) & 255)) > 255;

    z.f.c = carry_test;
    z.f.n = (val >> 7) == 1;
    z.f.pv = parity(((val +% ((z.c -% 1) & 255)) & 7) ^ z.b);
    z.f.h = carry_test;

    z.q.set(z.f.getF());
}

fn inir(z: *Z80) void {
    z.ini();

    if (z.b != 0) {
        z.pc -%= 2;

        z.f.x = getBit(11, z.pc) == 1;
        z.f.y = getBit(13, z.pc) == 1;
        if (z.f.c) {
            if (z.in(z.b +% 1, z.c, false) & 0x80 == 0x80) {
                z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity((z.b -% 1) & 0x7)) ^ 1)) == 1;
                z.f.h = (z.b & 0x0F) == 0x00;
            } else {
                z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity((z.b +% 1) & 0x7)) ^ 1)) == 1;
                z.f.h = (z.b & 0x0F) == 0x0F;
            }
        } else {
            z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity(z.b & 0x7)) ^ 1)) == 1;
        }

        z.wz = z.pc +% 1;
    } else {
        z.f.x = false;
        z.f.y = false;
        z.f.z = true;
        z.f.s = false;
    }

    z.q.set(z.f.getF());
}

fn indr(z: *Z80) void {
    z.ind();

    if (z.b != 0) {
        z.pc -%= 2;

        z.f.x = getBit(11, z.pc) == 1;
        z.f.y = getBit(13, z.pc) == 1;
        if (z.f.c) {
            if (z.in(z.b +% 1, z.c, false) & 0x80 == 0x80) {
                z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity((z.b -% 1) & 0x7)) ^ 1)) == 1;
                z.f.h = (z.b & 0x0F) == 0x00;
            } else {
                z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity((z.b +% 1) & 0x7)) ^ 1)) == 1;
                z.f.h = (z.b & 0x0F) == 0x0F;
            }
        } else {
            z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity(z.b & 0x7)) ^ 1)) == 1;
        }

        z.wz = z.pc +% 1;
    } else {
        z.f.x = false;
        z.f.y = false;
        z.f.z = true;
        z.f.s = false;
    }

    z.q.set(z.f.getF());
}

fn outi(z: *Z80) void {
    const hl = z.getHL();
    const val = z.rb(hl);

    z.b = z.dec(z.b);
    z.setHL(hl +% 1);

    z.out(z.b, z.c, val);

    const val_16 = @as(u16, val);
    const carry_test = (val_16 +% z.l) > 255;

    z.f.c = carry_test;
    z.f.n = (val >> 7) == 1;
    z.f.pv = parity(@truncate(((val +% z.l) & 7) ^ z.b));
    z.f.h = carry_test;

    z.q.set(z.f.getF());

    z.wz = z.getBC() +% 1;
}

fn outd(z: *Z80) void {
    const hl = z.getHL();
    const val = z.rb(hl);

    z.b = z.dec(z.b);
    z.setHL(hl -% 1);

    z.out(z.b, z.c, val);

    const val_16 = @as(u16, val);
    const carry_test = (val_16 +% z.l) > 255;

    z.f.c = carry_test;
    z.f.n = (val >> 7) == 1;
    z.f.pv = parity(@truncate(((val +% z.l) & 7) ^ z.b));
    z.f.h = carry_test;

    z.q.set(z.f.getF());

    z.wz = z.getBC() -% 1;
}

fn otir(z: *Z80) void {
    z.outi();

    if (z.b != 0) {
        z.pc -%= 2;

        z.f.x = getBit(11, z.pc) == 1;
        z.f.y = getBit(13, z.pc) == 1;
        if (z.f.c) {
            if (z.rb(z.getHL() -% 1) & 0x80 == 0x80) {
                z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity((z.b -% 1) & 0x7)) ^ 1)) == 1;
                z.f.h = (z.b & 0x0F) == 0x00;
            } else {
                z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity((z.b +% 1) & 0x7)) ^ 1)) == 1;
                z.f.h = (z.b & 0x0F) == 0x0F;
            }
        } else {
            z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity(z.b & 0x7)) ^ 1)) == 1;
        }

        z.wz = z.pc +% 1;
    } else {
        z.f.x = false;
        z.f.y = false;
        z.f.z = true;
        z.f.s = false;
    }

    z.q.set(z.f.getF());
}

fn otdr(z: *Z80) void {
    z.outd();

    if (z.b != 0) {
        z.pc -%= 2;

        z.f.x = getBit(11, z.pc) == 1;
        z.f.y = getBit(13, z.pc) == 1;
        if (z.f.c) {
            if (z.rb(z.getHL() +% 1) & 0x80 == 0x80) {
                z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity((z.b -% 1) & 0x7)) ^ 1)) == 1;
                z.f.h = (z.b & 0x0F) == 0x00;
            } else {
                z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity((z.b +% 1) & 0x7)) ^ 1)) == 1;
                z.f.h = (z.b & 0x0F) == 0x0F;
            }
        } else {
            z.f.pv = (@intFromBool(z.f.pv) ^ (@intFromBool(parity(z.b & 0x7)) ^ 1)) == 1;
        }

        z.wz = z.pc +% 1;
    } else {
        z.f.x = false;
        z.f.y = false;
        z.f.z = true;
        z.f.s = false;
    }

    z.q.set(z.f.getF());
}

fn exec_opcode(z: *Z80, opcode: u8) Z80Error!void {
    z.inc_r();

    switch (opcode) {
        0x00 => {}, // nop

        0x76 => z.is_halted = true, // halt

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

        0x0a => z.ldAAddr(z.getBC()), // ld a, (bc)
        0x1a => z.ldAAddr(z.getDE()), // ld a, (de)

        0x02 => z.ldAddrA(z.getBC()), // ld (bc), a
        0x12 => z.ldAddrA(z.getDE()), // ld (de), a

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

        0x32 => z.ldAddrA(z.nextw()), // ld (nn), a
        0x22 => z.ldAddrWord(z.nextw(), z.getHL()), // ld (nn), hl

        0x3a => z.ldAAddr(z.nextw()), // ld a, (nn)
        0x2a => z.ldWordAddr(setHL, z.nextw()), // ld hl, (nn)

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

        0x17 => z.a = z.rotateA(.left, false), // rla
        0x07 => z.a = z.rotateA(.left, true), // rlca

        0x1f => z.a = z.rotateA(.right, false), // rra
        0x0f => z.a = z.rotateA(.right, true), // rrca

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

            z.wz = val;

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
        0xe9 => {
            const wz = z.wz;

            z.jump(z.getHL(), true);
            z.wz = wz;
        }, // jp (hl)

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

        0xd3 => {
            const port = z.nextb();
            const wz = (@as(u16, z.a) << 8) | (port +% 1);

            z.out(z.a, port, z.a);
            z.wz = wz;
        }, // out (n), a
        0xdb => {
            const port = z.nextb();
            const wz = ((@as(u16, z.a) << 8) | port) +% 1;

            z.a = z.in(z.a, port, false);
            z.wz = wz;
        }, // in a, (n)

        0xcb => z.exec_opcode_cb(z.nextb()), // cb prefixed opcodes
        0xed => try z.exec_opcode_ed(z.nextb()), // ed prefixed opcodes
        0xdd => try z.exec_opcode_xy(z.nextb(), &z.ix), // dd prefixed opcodes
        0xfd => try z.exec_opcode_xy(z.nextb(), &z.iy), // fd prefixed opcodes
    }
}

fn exec_opcode_ed(z: *Z80, opcode: u8) Z80Error!void {
    z.inc_r();

    switch (opcode) {
        0x77, 0x7f => {}, // nop

        0x47 => z.i = z.a, // ld i, a
        0x4f => z.r = z.a, // ld r, a
        0x57 => z.ld_a_i(), // ld a, i
        0x5f => z.ld_a_r(), // ld a, r

        0x4b => z.ldWordAddr(setBC, z.nextw()), // ld bc, (nn)
        0x5b => z.ldWordAddr(setDE, z.nextw()), // ld de, (nn)
        0x6b => z.ldWordAddr(setHL, z.nextw()), // ld hl, (nn)
        0x7b => z.ldWordAddr(setSP, z.nextw()), // ld sp, (nn)

        0x43 => z.ldAddrWord(z.nextw(), z.getBC()), // ld (nn), bc
        0x53 => z.ldAddrWord(z.nextw(), z.getDE()), // ld (nn), de
        0x63 => z.ldAddrWord(z.nextw(), z.getHL()), // ld (nn), hl
        0x73 => z.ldAddrWord(z.nextw(), z.sp), // ld (nn), sp

        0x4a => z.setHL(z.adcw(z.getHL(), z.getBC())), // adc hl, bc
        0x5a => z.setHL(z.adcw(z.getHL(), z.getDE())), // adc hl, de
        0x6a => z.setHL(z.adcw(z.getHL(), z.getHL())), // adc hl, hl
        0x7a => z.setHL(z.adcw(z.getHL(), z.sp)), // adc hl, sp

        0x42 => z.setHL(z.sbcw(z.getHL(), z.getBC())), // sbc hl, bc
        0x52 => z.setHL(z.sbcw(z.getHL(), z.getDE())), // sbc hl, de
        0x62 => z.setHL(z.sbcw(z.getHL(), z.getHL())), // sbc hl, hl
        0x72 => z.setHL(z.sbcw(z.getHL(), z.sp)), // sbc hl, sp

        0x44, 0x4c, 0x54, 0x5c, 0x64, 0x6c, 0x74, 0x7c => z.a = z.sub(0, z.a), // neg

        0x46, 0x4e, 0x66, 0x6e => z.imode = .mode0, // im 0
        0x56, 0x76 => z.imode = .mode1, // im 1
        0x5e, 0x7e => z.imode = .mode2, // im 2

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

        0xa0 => z.ldi(), // ldi
        0xa8 => z.ldd(), // ldd
        0xb0 => z.ldir(), // ldir
        0xb8 => z.lddr(), // lddr

        0xa1 => z.cpi(), // cpi
        0xa9 => z.cpd(), // cpd
        0xb1 => z.cpir(), // cpir
        0xb9 => z.cpdr(), // cpdr

        0xa2 => z.ini(), // ini
        0xaa => z.ind(), // ind
        0xb2 => z.inir(), // inir
        0xba => z.indr(), // indr

        0xa3 => z.outi(), // outi
        0xab => z.outd(), // outd
        0xb3 => z.otir(), // otir
        0xbb => z.otdr(), // otdr

        0x45, 0x55, 0x5d, 0x65, 0x6d, 0x75, 0x7d => z.retn(), // retn
        0x4d => z.retn(), // reti

        0x67 => z.rrd(), // rrd
        0x6f => z.rld(), // rld

        else => return Z80Error.UnknownOpcode,
    }
}

fn exec_opcode_cb(z: *Z80, opcode: u8) void {
    z.inc_r();

    const registers: [8]?*u8 = .{ &z.b, &z.c, &z.d, &z.e, &z.h, &z.l, null, &z.a };

    const _x: u2 = @truncate(opcode >> 6);
    const _y: u3 = @truncate((opcode >> 3) & 0b111);
    const _z: u3 = @truncate(opcode & 0b111);

    if (registers[_z]) |r| {
        switch (_x) {
            0 => r.* = switch (_y) {
                0 => z.rotate(r.*, .left, true),
                1 => z.rotate(r.*, .right, true),
                2 => z.rotate(r.*, .left, false),
                3 => z.rotate(r.*, .right, false),
                4 => z.shift(r.*, .left, false),
                5 => z.shift(r.*, .right, true),
                6 => z.shift(r.*, .left, true),
                7 => z.shift(r.*, .right, false),
            },
            1 => z.bit_test(_y, r.*),
            2 => r.* = resetBit(_y, r.*),
            3 => r.* = setBit(_y, r.*),
        }
    } else {
        const hl = z.getHL();
        const val = z.rb(hl);

        switch (_x) {
            0 => z.wb(hl, switch (_y) {
                0 => z.rotate(val, .left, true),
                1 => z.rotate(val, .right, true),
                2 => z.rotate(val, .left, false),
                3 => z.rotate(val, .right, false),
                4 => z.shift(val, .left, false),
                5 => z.shift(val, .right, true),
                6 => z.shift(val, .left, true),
                7 => z.shift(val, .right, false),
            }),
            1 => {
                z.bit_test(_y, val);

                z.f.x = getBit(11, z.wz) == 1;
                z.f.y = getBit(13, z.wz) == 1;

                z.q.set(z.f.getF());
            },
            2 => z.wb(hl, resetBit(_y, val)),
            3 => z.wb(hl, setBit(_y, val)),
        }
    }
}

fn exec_opcode_xy(z: *Z80, opcode: u8, xy_ptr: *u16) Z80Error!void {
    z.inc_r();

    var xy: struct {
        ptr: *u16,

        const Self = @This();

        fn getDisplacement(z_: *Z80) u16 {
            return @bitCast(@as(i16, @as(i8, @bitCast(z_.nextb()))));
        }

        pub fn getLow(self: *Self) u8 {
            return @truncate(self.ptr.* & 0xff);
        }

        pub fn getHigh(self: *Self) u8 {
            return @truncate(self.ptr.* >> 8);
        }

        pub fn setLow(self: *Self, val: u8) void {
            self.ptr.* = (self.ptr.* & 0xff00) | val;
        }

        pub fn setHigh(self: *Self, val: u8) void {
            self.ptr.* = (@as(u16, val) << 8) | (self.ptr.* & 0xff);
        }

        pub fn getAddr(self: *Self, z_: *Z80) u16 {
            const res = self.ptr.* +% getDisplacement(z_);

            z_.wz = res;

            return res;
        }
    } = .{ .ptr = xy_ptr };

    switch (opcode) {
        0x7c => z.a = xy.getHigh(), // ld a, ixh / ld a, iyh
        0x44 => z.b = xy.getHigh(), // ld b, ixh / ld b, iyh
        0x4c => z.c = xy.getHigh(), // ld c, ixh / ld c, iyh
        0x54 => z.d = xy.getHigh(), // ld d, ixh / ld d, iyh
        0x5c => z.e = xy.getHigh(), // ld e, ixh / ld e, iyh

        0x7d => z.a = xy.getLow(), // ld a, ixl / ld a, iyl
        0x45 => z.b = xy.getLow(), // ld b, ixl / ld b, iyl
        0x4d => z.c = xy.getLow(), // ld c, ixl / ld c, iyl
        0x55 => z.d = xy.getLow(), // ld d, ixl / ld d, iyl
        0x5d => z.e = xy.getLow(), // ld e, ixl / ld e, iyl

        0x67 => xy.setHigh(z.a), // ld ixh, a / ld iyh, a
        0x60 => xy.setHigh(z.b), // ld ixh, b / ld iyh, b
        0x61 => xy.setHigh(z.c), // ld ixh, c / ld iyh, c
        0x62 => xy.setHigh(z.d), // ld ixh, d / ld iyh, d
        0x63 => xy.setHigh(z.e), // ld ixh, e / ld iyh, e
        0x64 => xy.setHigh(xy.getHigh()), // ld ixh, ixh / ld iyh, iyh
        0x65 => xy.setHigh(xy.getLow()), // ld ixh, ixl / ld iyh, iyl
        0x26 => xy.setHigh(z.nextb()), // ld ixh, n / ld iyh, n

        0x6f => xy.setLow(z.a), // ld ixl, a / ld iyl, a
        0x68 => xy.setLow(z.b), // ld ixl, b / ld iyl, b
        0x69 => xy.setLow(z.c), // ld ixl, c / ld iyl, c
        0x6a => xy.setLow(z.d), // ld ixl, d / ld iyl, d
        0x6b => xy.setLow(z.e), // ld ixl, e / ld iyl, e
        0x6c => xy.setLow(xy.getHigh()), // ld ixl, ixh / ld iyl, iyh
        0x6d => xy.setLow(xy.getLow()), // ld ixl, ixl / ld iyl, iyl
        0x2e => xy.setLow(z.nextb()), // ld ixl, n / ld iyl, n

        0x77 => z.wb(xy.getAddr(z), z.a), // ld (ix+d), a / ld (iy+d), a
        0x70 => z.wb(xy.getAddr(z), z.b), // ld (ix+d), b / ld (iy+d), b
        0x71 => z.wb(xy.getAddr(z), z.c), // ld (ix+d), c / ld (iy+d), c
        0x72 => z.wb(xy.getAddr(z), z.d), // ld (ix+d), d / ld (iy+d), d
        0x73 => z.wb(xy.getAddr(z), z.e), // ld (ix+d), e / ld (iy+d), e
        0x74 => z.wb(xy.getAddr(z), z.h), // ld (ix+d), h / ld (iy+d), h
        0x75 => z.wb(xy.getAddr(z), z.l), // ld (ix+d), l / ld (iy+d), l
        0x36 => z.wb(xy.getAddr(z), z.nextb()), // ld (ix+d), n / ld (iy+d), n

        0x7e => z.a = z.rb(xy.getAddr(z)), // ld a, (ix+d) / ld a, (iy+d)
        0x46 => z.b = z.rb(xy.getAddr(z)), // ld b, (ix+d) / ld b, (iy+d)
        0x4e => z.c = z.rb(xy.getAddr(z)), // ld c, (ix+d) / ld c, (iy+d)
        0x56 => z.d = z.rb(xy.getAddr(z)), // ld d, (ix+d) / ld d, (iy+d)
        0x5e => z.e = z.rb(xy.getAddr(z)), // ld e, (ix+d) / ld e, (iy+d)
        0x66 => z.h = z.rb(xy.getAddr(z)), // ld h, (ix+d) / ld h, (iy+d)
        0x6e => z.l = z.rb(xy.getAddr(z)), // ld l, (ix+d) / ld l, (iy+d)

        0x21 => xy.ptr.* = z.nextw(), // ld ix, nn / ld iy, nn
        0x2a => {
            const addr = z.nextw();

            xy.ptr.* = z.rw(addr);
            z.wz = addr +% 1;
        }, // ld ix, (nn) / ld iy, (nn)
        0x22 => {
            const addr = z.nextw();

            z.ww(addr, xy.ptr.*);
            z.wz = addr +% 1;
        }, // ld (nn), ix / ld (nn), iy

        0xf9 => z.sp = xy.ptr.*, // ld sp, ix / ld sp, iy

        0x24 => xy.setHigh(z.inc(xy.getHigh())), // inc ixh / inc iyh
        0x2c => xy.setLow(z.inc(xy.getLow())), // inc ixl / inc iyl
        0x23 => xy.ptr.* +%= 1, // inc ix / inc iy

        0x34 => {
            const addr = xy.getAddr(z);

            z.wb(addr, z.inc(z.rb(addr)));
        }, // inc (ix+d) / inc (iy+d)

        0x84 => z.a = z.add(z.a, xy.getHigh()), // add a, ixh / add a, iyh
        0x85 => z.a = z.add(z.a, xy.getLow()), // add a, ixl / add a, iyl
        0x86 => z.a = z.add(z.a, z.rb(xy.getAddr(z))), // add a, (ix+d) / add a, (iy+d)

        0x09 => xy.ptr.* = z.addw(xy.ptr.*, z.getBC()), // add ix, bc / add iy, bc
        0x19 => xy.ptr.* = z.addw(xy.ptr.*, z.getDE()), // add ix, de / add iy, de
        0x29 => xy.ptr.* = z.addw(xy.ptr.*, xy.ptr.*), // add ix, ix / add iy, iy
        0x39 => xy.ptr.* = z.addw(xy.ptr.*, z.sp), // add ix, sp / add iy, sp

        0x8c => z.a = z.adc(z.a, xy.getHigh()), // adc a, ixh / adc a, iyh
        0x8d => z.a = z.adc(z.a, xy.getLow()), // adc a, ixl / adc a, iyl
        0x8e => z.a = z.adc(z.a, z.rb(xy.getAddr(z))), // adc a, (ix+d) / adc a, (iy+d)

        0x25 => xy.setHigh(z.dec(xy.getHigh())), // dec ixh / dec iyh
        0x2d => xy.setLow(z.dec(xy.getLow())), // dec ixl / dec iyl
        0x2b => xy.ptr.* -%= 1, // dec ix / dec iy

        0x35 => {
            const addr = xy.getAddr(z);

            z.wb(addr, z.dec(z.rb(addr)));
        }, // dec (ix+d) / dec (iy+d)

        0x94 => z.a = z.sub(z.a, xy.getHigh()), // sub a, ixh / sub a, iyh
        0x95 => z.a = z.sub(z.a, xy.getLow()), // sub a, ixl / sub a, iyl
        0x96 => z.a = z.sub(z.a, z.rb(xy.getAddr(z))), // sub a, (ix+d) / sub a, (iy+d)

        0x9c => z.a = z.sbc(z.a, xy.getHigh()), // sbc a, ixh / sbc a, iyh
        0x9d => z.a = z.sbc(z.a, xy.getLow()), // sbc a, ixl / sbc a, iyl
        0x9e => z.a = z.sbc(z.a, z.rb(xy.getAddr(z))), // sbc a, (ix+d) / sbc a, (iy+d)

        0xa4 => z.a = z.land(xy.getHigh()), // and ixh / and iyh
        0xa5 => z.a = z.land(xy.getLow()), // and ixl / and iyl
        0xa6 => z.a = z.land(z.rb(xy.getAddr(z))), // and (ix+d) / and (iy+d)

        0xac => z.a = z.lxor(xy.getHigh()), // xor ixh / xor iyh
        0xad => z.a = z.lxor(xy.getLow()), // xor ixl / xor iyl
        0xae => z.a = z.lxor(z.rb(xy.getAddr(z))), // xor (ix+d) / xor (iy+d)

        0xb4 => z.a = z.lor(xy.getHigh()), // or ixh / or iyh
        0xb5 => z.a = z.lor(xy.getLow()), // or ixl / or iyl
        0xb6 => z.a = z.lor(z.rb(xy.getAddr(z))), // or (ix+d) / or (iy+d)

        0xbc => z.cp(xy.getHigh()), // cp ixh / cp iyh
        0xbd => z.cp(xy.getLow()), // cp ixl / cp iyl
        0xbe => z.cp(z.rb(xy.getAddr(z))), // cp (ix+d) / cp (iy+d)

        0xe5 => z.push(xy.ptr.*), // push ix / push iy
        0xe1 => xy.ptr.* = z.pop(), // pop ix / pop iy

        0xe9 => {
            const wz = z.wz;

            z.jump(xy.ptr.*, true);
            z.wz = wz;
        }, // jp (ix) / jp (iy)

        0xe3 => {
            var val: u16 = z.rw(z.sp);

            z.wz = val;

            swap(&val, &xy.ptr.*);

            z.ww(z.sp, val);
        }, // ex (sp), ix / ex (sp), iy

        0xcb => {
            const addr = xy.getAddr(z);

            z.exec_opcode_xy_cb(z.nextb(), addr);
        },

        else => {
            z.dec_r();

            try z.exec_opcode(opcode);
        },
    }
}

fn exec_opcode_xy_cb(z: *Z80, opcode: u8, addr: u16) void {
    const registers: [8]?*u8 = .{ &z.b, &z.c, &z.d, &z.e, &z.h, &z.l, null, &z.a };

    const _x: u2 = @truncate(opcode >> 6);
    const _y: u3 = @truncate((opcode >> 3) & 0b111);
    const _z: u3 = @truncate(opcode & 0b111);

    const val = z.rb(addr);

    const res = switch (_x) {
        0 => switch (_y) {
            0 => z.rotate(val, .left, true),
            1 => z.rotate(val, .right, true),
            2 => z.rotate(val, .left, false),
            3 => z.rotate(val, .right, false),
            4 => z.shift(val, .left, false),
            5 => z.shift(val, .right, true),
            6 => z.shift(val, .left, true),
            7 => z.shift(val, .right, false),
        },
        1 => {
            z.bit_test(_y, val);

            z.f.x = getBit(11, addr) == 1;
            z.f.y = getBit(13, addr) == 1;

            z.q.set(z.f.getF());

            return;
        },
        2 => resetBit(_y, val),
        3 => setBit(_y, val),
    };

    z.wb(addr, res);

    if (registers[_z]) |r| {
        r.* = res;
    }
}
