// a driver for tests/emit/where-zig.hbnf: whether the text is read, and what %bind { } added up
const std = @import("std");
const l = @import("l.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const ok = if (l.parse_text(alloc, args[1], &err, &line, &col)) |_| true else |_| false;
    std.debug.print("{} {d}\n", .{ ok, l.bound });
}
