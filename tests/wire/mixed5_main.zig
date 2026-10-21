// %action on a bit rule inside a text grammar: failure and warnings.
const std = @import("std");
const g = @import("mixed5_zig.zig");

fn show(a: std.mem.Allocator, what: []const u8, text: []const u8) void {
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    if (g.parse_text(a, text, &err, &line, &col)) |out| {
        std.debug.print("{s}: kind={d} len={d}\n", .{ what, out.rec.kind, out.rec.len });
    } else |_| {
        std.debug.print("{s}: error\n{s}\n", .{ what, std.mem.sliceTo(&err, 0) });
    }
    for (g.hbnf_warnings()) |w| std.debug.print("  warning: {s}\n", .{w});
}

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    show(a, "plain", "REC:\x07\x03;");
    show(a, "long", "REC:\x07\x20;");
    show(a, "reserved", "REC:\xff\x01;");
}
