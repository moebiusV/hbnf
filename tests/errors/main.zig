// Parse each file and print what the parser says (the files sit beside this one).
const std = @import("std");
const g = @import("GRAMMAR");

fn show(a: std.mem.Allocator, name: []const u8, text: []const u8) void {
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    std.debug.print("== {s}\n", .{name});
    if (g.parse_text(a, text, &err, &line, &col)) |_| {
        std.debug.print("ok\n", .{});
    } else |_| {
        std.debug.print("{s}\n", .{std.mem.sliceTo(&err, 0)});
    }
}

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    show(a, "open.blk", @embedFile("open.blk"));
    show(a, "stray.blk", @embedFile("stray.blk"));
}
