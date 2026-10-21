// The walk and the dump of tests/ast/ast.hbnf's tree in Zig: the same lines C's node_walk and
// node_dump print (the first three sections of tests/ast/expected.txt).
const std = @import("std");
const g = @import("ast.zig");

const Show = struct {
    depth: usize = 0,
    skip_blocks: bool = false,
    al: std.mem.Allocator,

    pub fn enter(self: *Show, n: g.Node) g.Walk {
        const alt = g.node_alt(n);
        for (0..self.depth) |_| std.debug.print("  ", .{});
        std.debug.print("{s}", .{g.node_kind_name(n)});
        if (alt != 0) std.debug.print("[{s}]", .{g.node_alt_name(n, alt)});
        std.debug.print("\n", .{});
        if (self.skip_blocks and std.mem.eql(u8, g.node_kind_name(n), "block")) return .skip;
        self.depth += 1;
        return .cont;
    }
    pub fn leave(self: *Show, _: g.Node) g.Walk {
        self.depth -= 1;
        return .cont;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const text = "set a 1; run b; { set c \"x\"; set d e; }";
    const tree = try g.parse_text(a, text, &err, &line, &col);
    std.debug.print("== all\n", .{});
    var s1 = Show{ .al = a };
    _ = try g.walk_config(tree, &s1, a);
    std.debug.print("== blocks skipped\n", .{});
    var s2 = Show{ .al = a, .skip_blocks = true };
    _ = try g.walk_config(tree, &s2, a);
    std.debug.print("== dump\n", .{});
    std.debug.print("{s}\n", .{try g.dump_config(tree, a)});
    const other = try g.parse_text(a, "set a 2; run b; { set c \"x\"; set d e; }", &err, &line, &col);
    const same = try g.parse_text(a, text, &err, &line, &col);
    std.debug.print("== equal\n", .{});
    std.debug.print("same text: {}\n", .{try g.node_equal(.{ .config = &tree[0] }, .{ .config = &same[0] }, a)});
    std.debug.print("other text: {}\n", .{try g.node_equal(.{ .config = &tree[0] }, .{ .config = &other[0] }, a)});
}
