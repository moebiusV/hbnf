// Text after a 3-bit field: read at bit 3, shifted.
const std = @import("std");
const g = @import("mixed3.zig");

fn show(what: []const u8, text: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var err: [512]u8 = undefined;
    var l: usize = 0;
    var c: usize = 0;
    if (g.parse_text(arena.allocator(), text, &err, &l, &c)) |out| {
        std.debug.print("{s}: flag={d} label={s} pad={d}\n", .{ what, out.record.flag, out.record.label, out.record.pad });
    } else |_| {
        std.debug.print("{s}: error\n{s}\n", .{ what, std.mem.sliceTo(&err, 0) });
    }
}

pub fn main() void {
    // flag 101, "abc", pad 00000: 10101100 00101100 01001100 01100000
    show("abc", "REC:\xac\x2c\x4c\x60");
    // flag 000, "Z" = 0x5a: 00001011 01000000
    show("Z", "REC:\x0b\x40");
}
