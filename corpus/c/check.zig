// check.zig -- say whether the generated parser accepts each of the embedded files ("ok FILE" or
// "bad FILE: MESSAGE" on stderr).  MODULE and FILES are filled in by the test script.
const std = @import("std");
const g = @import("MODULE");

const File = struct { name: []const u8, data: []const u8 };
const files = [_]File{
FILES
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var bad = false;
    for (files) |f| {
        var err: [512]u8 = undefined;
        var line: usize = 0;
        var col: usize = 0;
        if (g.parse_text(arena.allocator(), f.data, &err, &line, &col)) |_| {
            std.debug.print("ok {s}\n", .{f.name});
        } else |_| {
            const m = std.mem.sliceTo(&err, 0);
            const first = if (std.mem.indexOfScalar(u8, m, '\n')) |i| m[0..i] else m;
            std.debug.print("bad {s}: {s}\n", .{ f.name, first });
            bad = true;
        }
    }
    if (bad) std.process.exit(1);
}
