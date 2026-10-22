// Back-references in Zig: a closing tag repeats the opening one (tests/backref/tags.hbnf); the lines
// tests/backref/expected.txt has for C.
const std = @import("std");
const g = @import("tags.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    const cases = [_][]const u8{ "<a></a>", "<a>text</a>", "<a><b></b></a>", "<a><a></a></a>", "<a></a><b></b>", "x<a>y<b>z</b>w</a>v", "<a></b>", "<a><b></a></b>", "<ab></a>", "<a></ab>", "<a>", "</a>" };
    for (cases) |t| {
        var err: [512]u8 = undefined;
        var line: usize = 0;
        var col: usize = 0;
        if (g.parse_text(a, t, &err, &line, &col)) |_| {
            std.debug.print("{s: <26} accepted\n", .{t});
        } else |_| {
            const m = std.mem.sliceTo(&err, 0);
            std.debug.print("{s: <26} {s}\n", .{ t, m[0 .. std.mem.indexOfScalar(u8, m, '\n') orelse m.len] });
        }
    }
}
