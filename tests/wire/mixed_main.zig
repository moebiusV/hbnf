// A text rule that names a bit rule: both read from one parser.
const std = @import("std");
const g = @import("mixed.zig");

fn show(what: []const u8, text: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var err: [512]u8 = undefined;
    var l: usize = 0;
    var c: usize = 0;
    if (g.parse_text(arena.allocator(), text, &err, &l, &c)) |out| {
        std.debug.print("{s}: len={d} body={s}\n", .{ what, out.frame.len, out.frame.body });
    } else |_| {
        std.debug.print("{s}: error\n{s}\n", .{ what, std.mem.sliceTo(&err, 0) });
    }
}

pub fn main() void {
    show("hello", "PKT:\x05hello;");
    show("one", "PKT:\x01z;");
    show("short", "PKT:\x09hello;");
    show("no semicolon", "PKT:\x05hello");
    show("no tag", "\x05hello;");
}
