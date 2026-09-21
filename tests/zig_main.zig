const std = @import("std");
const g = @import("server.zig");

fn run(name: []const u8, text: []const u8) !void {
    var err: [512]u8 = undefined;
    var el: usize = 0;
    var ec: usize = 0;
    const s = g.parse_text(std.heap.page_allocator, text, &err, &el, &ec) catch {
        std.debug.print("{s}: error line {d}:\n{s}\n", .{ name, el, std.mem.sliceTo(&err, 0) });
        return;
    };
    std.debug.print("{s}: OK name={s} port={d}\n", .{ name, s.name, s.listen.port });
}

pub fn main() !void {
    try run("valid", "\"example.com\"\non wg0 port 443\n\"/var/www\"\n\"www\"\nyes\n");
    try run("malformed", "\"example.com\"\non wg0 port oops\n\"/var/www\"\n\"www\"\nyes\n");
}
