// a driver for tests/emit/runs-zig.hbnf: the value, the depth of the stack and the sum of what is on it
const std = @import("std");
const l = @import("l.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    if (l.parse_text(alloc, args[1], &err, &line, &col)) |v| {
        var sum: i32 = 0;
        for (l.stack[0..l.depth]) |x| sum += x;
        std.debug.print("{d} {d} {d}\n", .{ v, l.depth, sum });
    } else |_| {
        std.debug.print("error {d}:{d}\n", .{ line, col });
    }
}
