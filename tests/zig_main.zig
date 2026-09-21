const std = @import("std");
const g = @import("server.zig");

fn run(name: []const u8, toks: []const g.Token, lines: []const []const u8) !void {
    var err: [512]u8 = undefined;
    var el: usize = 0;
    var ec: usize = 0;
    const s = g.parse_config(std.heap.page_allocator, toks, lines, &err, &el, &ec) catch {
        std.debug.print("{s}: error line {d}:\n{s}\n", .{ name, el, std.mem.sliceTo(&err, 0) });
        return;
    };
    std.debug.print("{s}: OK name={s} port={d}\n", .{ name, s.name, s.listen.port });
}

pub fn main() !void {
    const lines = [_][]const u8{ "example.com", "on wg0 port oops", "/var/www", "www", "yes" };

    const valid = [_]g.Token{
        .{ .kind = .str, .text = "example.com", .line = 1, .col = 1 },
        .{ .kind = .atom, .text = "on", .line = 2, .col = 1 },
        .{ .kind = .atom, .text = "wg0", .line = 2, .col = 4 },
        .{ .kind = .atom, .text = "port", .line = 2, .col = 8 },
        .{ .kind = .int, .text = "443", .line = 2, .col = 13 },
        .{ .kind = .str, .text = "/var/www", .line = 3, .col = 1 },
        .{ .kind = .str, .text = "www", .line = 4, .col = 1 },
        .{ .kind = .atom, .text = "yes", .line = 5, .col = 1 },
        .{ .kind = .eof, .text = "", .line = 5, .col = 1 },
    };
    try run("valid", &valid, &lines);

    const bad = [_]g.Token{
        .{ .kind = .str, .text = "example.com", .line = 1, .col = 1 },
        .{ .kind = .atom, .text = "on", .line = 2, .col = 1 },
        .{ .kind = .atom, .text = "wg0", .line = 2, .col = 4 },
        .{ .kind = .atom, .text = "port", .line = 2, .col = 8 },
        .{ .kind = .atom, .text = "oops", .line = 2, .col = 13 },
        .{ .kind = .eof, .text = "", .line = 5, .col = 1 },
    };
    try run("malformed", &bad, &lines);
}
