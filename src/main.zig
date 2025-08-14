const std = @import("std");

const Z80 = @import("z80.zig").Z80;

pub fn main() !void {
    std.debug.print("zig80\n", .{});

    const z: Z80 = .init();
    _ = z;
}
