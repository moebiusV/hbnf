// tests/recursive.sh's second Zig driver: the same cycle through a DIRECT
// struct member (tests/abnf/recursive-direct.hbnf), which visit_x and fold_x
// walk through the pointer.  Prints how many x nodes each walker saw, under
// the leak-checking allocator.
const std = @import("std");
const g = @import("recursive_direct.zig");

const Count = struct {
    n: u32 = 0,
    pub fn visit_x(self: *Count, _: *const g.X) void {
        self.n += 1;
    }
    pub fn fold_x(self: *Count, _: *g.X) void {
        self.n += 1;
    }
};

pub fn main() void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    const alloc = da.allocator();
    const cases = [_][]const u8{ "(((5)))", "((5)" };
    for (cases) |text| {
        var err: [512]u8 = undefined;
        var el: usize = 0;
        var ec: usize = 0;
        var r = g.parse_text(alloc, text, &err, &el, &ec) catch {
            std.debug.print("{s}: REJECT\n", .{text});
            continue;
        };
        var v = Count{};
        g.visit_x(&r, &v);
        var f = Count{};
        g.fold_x(&r, &f);
        std.debug.print("{s}: OK visited={d} folded={d}\n", .{ text, v.n, f.n });
        g.deinit_x(&r, alloc);
    }
    // The token and line arrays parse_text makes are not freed by it, so the
    // report is not empty; recursive.sh looks for the tree's own boxes in it.
    _ = da.deinit();
}
