// tests/recursive.sh's Zig driver: parse a few expressions and say whether
// each was accepted, as recursive_main.adb and main.rs do.  The grammar is
// tests/abnf/recursive.hbnf, whose tree type contains itself, so this is the
// fixture that proves Zig breaks the cycle with a pointer rather than
// refusing.  std.debug.print writes to stderr, which recursive.sh reads.
//
// The allocator is the leak-checking one on purpose: a failed branch must
// release the box it set, and deinit_prim must release the ones that stay, so
// any leak in the generated code shows here.
const std = @import("std");
const g = @import("recursive.zig");

const Walk = struct {
    pub fn visit_prim(_: *Walk, _: *const g.Prim) void {}
    pub fn fold_prim(_: *Walk, _: *g.Prim) void {}
};

pub fn main() void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    const alloc = da.allocator();
    const cases = [_][]const u8{ "(1)", "1)", "((1))", "(1" };
    for (cases) |text| {
        var err: [512]u8 = undefined;
        var el: usize = 0;
        var ec: usize = 0;
        var r = g.parse_text(alloc, text, &err, &el, &ec) catch {
            std.debug.print("{s}: REJECT\n", .{text});
            continue;
        };
        std.debug.print("{s}: OK expr={s}\n", .{ text, if (r.expr != null) "set" else "null" });
        // The walkers must at least compile and run over a boxed tree.
        var w = Walk{};
        g.visit_prim(&r, &w);
        g.fold_prim(&r, &w);
        g.deinit_prim(&r, alloc);
    }
    // Nothing may be left: the tree is released by deinit_ and parse_text
    // frees its own scaffolding.
    if (da.deinit() == .leak) std.debug.print("LEAK\n", .{});
}
