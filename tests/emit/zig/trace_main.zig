// a driver for the emit tests whose answer is the calls the emits made, in order (`error` when the read fails)
const std = @import("std");
const l = @import("l.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    if (l.parse_text(alloc, args[1], &err, &line, &col)) |_| {
        std.debug.print("{s}\n", .{l.trace[0..l.trace_len]});
    } else |_| {
        std.debug.print("error\n", .{});
    }
}
