// a driver for tests/emit/run-zig.hbnf: the value of the list, or where the read stopped (`error line:column`)
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
        std.debug.print("{d}\n", .{v});
    } else |_| {
        std.debug.print("error {d}:{d}\n", .{ line, col });
    }
}
