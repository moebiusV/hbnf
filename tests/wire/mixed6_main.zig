// A bit rule of a mixed grammar, written: %emit fills in len.
const std = @import("std");
const g = @import("mixed6_zig.zig");

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m: []const u8 = "";
    var f = g.Frame{ .len = 99, .body = a.dupe(u8, "hello") catch unreachable, .tag = "ab" }; // %emit replaces len
    if (g.emit_bits_frame(a, f, &m)) |e| {
        std.debug.print("{d} bits:", .{e.nbits});
        for (e.bytes[0 .. (e.nbits + 7) / 8]) |b| std.debug.print(" {x:0>2}", .{b});
        std.debug.print("\n", .{});
    } else |_| {
        std.debug.print("error: {s}\n", .{m});
    }
    f.tag = ""; // a token is text; "" writes nothing
    if (g.emit_bits_frame(a, f, &m)) |e| {
        std.debug.print("count only: {d} bits\n", .{e.nbits});
    } else |_| {}
}
