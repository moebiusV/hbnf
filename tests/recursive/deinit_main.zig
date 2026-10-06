// tests/recursive.sh's third Zig driver: deinit_<root> on a real tree, one
// with list slices and entries (tests/portable/portable.hbnf), under the
// leak-checking allocator.  A deinit that missed something shows as a leak
// made by a parse_<rule> function; one that freed what it should not own
// shows as an invalid or double free.
const std = @import("std");
const g = @import("portable.zig");

pub fn main() void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    const alloc = da.allocator();
    const texts = [_][]const u8{ @embedFile("good.conf"), @embedFile("quiet.conf") };
    for (texts) |t| {
        var err: [512]u8 = undefined;
        var el: usize = 0;
        var ec: usize = 0;
        var c = g.parse_text(alloc, t, &err, &el, &ec) catch {
            std.debug.print("REJECT\n", .{});
            continue;
        };
        std.debug.print("OK hosts={d}\n", .{c.host_list.len});
        g.deinit_config(&c, alloc);
    }
    // parse_text's own token and line arrays are reported; the tree's are not.
    _ = da.deinit();
}
