// A text element, bit fields and text again, in one rule.
const std = @import("std");
const g = @import("mixed4.zig");

fn show(what: []const u8, text: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var err: [512]u8 = undefined;
    var l: usize = 0;
    var c: usize = 0;
    if (g.parse_text(arena.allocator(), text, &err, &l, &c)) |out| {
        std.debug.print("{s}: len={d} payload={s}\n", .{ what, out.req_2.len, out.req_2.payload });
    } else |_| {
        std.debug.print("{s}: error\n{s}\n", .{ what, std.mem.sliceTo(&err, 0) });
    }
}

pub fn main() void {
    show("hello", "GET \x05hello\r\n");
    show("one", "GET \x01z\r\n");
    show("short", "GET \x09hello\r\n");
    show("no line end", "GET \x05hello");
    show("no verb", "PUT \x05hello\r\n");
}
