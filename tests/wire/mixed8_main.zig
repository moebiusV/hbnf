// Alternatives in a mixed grammar, written back: read the text, write the tree.
const std = @import("std");
const g = @import("mixed8.zig");

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const in = [_][]const u8{ "A:\x07\x03;", "B:abc;", "L:x\x01\x02yfoo,x\x03\x04;" };
    for (in, 0..) |text, i| {
        var err: [512]u8 = undefined;
        var line: usize = 0;
        var col: usize = 0;
        const out = g.parse_text(a, text, &err, &line, &col) catch {
            std.debug.print("read {d}: {s}\n", .{ i, std.mem.sliceTo(&err, 0) });
            continue;
        };
        var msg: []const u8 = "";
        if (g.write_doc(a, &out, &msg)) |bytes| {
            const same = std.mem.eql(u8, bytes, text);
            std.debug.print("write {d}: ok {d} bytes, same as read: {s}\n", .{ i, bytes.len, if (same) "yes" else "no" });
        } else |_| {
            std.debug.print("write {d}: {s}\n", .{ i, msg });
        }
    }
}
