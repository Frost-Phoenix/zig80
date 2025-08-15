const std = @import("std");

const Z80 = @import("Z80.zig");

pub fn main() !void {
    std.debug.print("zig80\n", .{});

    const z: Z80 = .init();
    _ = z;
}
