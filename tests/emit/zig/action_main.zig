// a driver for tests/emit/action-zig.hbnf: whether the text is read, the line and message of the error, and how many actions ran
const std = @import("std");
const l = @import("l.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    const t = try std.mem.replaceOwned(u8, alloc, args[1], "\\n", "\n");
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    if (l.parse_text(alloc, t, &err, &line, &col)) |_| {
        std.debug.print("ok {d}\n", .{l.seen});
    } else |_| {
        std.debug.print("error {d} {s} {d}\n", .{ line, std.mem.sliceTo(&err, 0), l.seen });
    }
}
