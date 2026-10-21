// Spans and parents (--spans --parents) in Zig: where each node of tests/ast/ast.hbnf's tree is
// in the text, and which node holds it; the lines C prints (tests/spans/expected.txt).
const std = @import("std");
const g = @import("ast.zig");

const text = "set a 1;\nrun b;\n{ set c \"x\"; }\n";

const Show = struct {
    parents: *const g.Parents,
    pub fn enter(self: *Show, n: g.Node) g.Walk {
        if (g.node_span(n)) |se| {
            const lc = g.node_where(text, se[0]);
            const up: []const u8 = if (self.parents.parent(n)) |p| g.node_kind_name(p) else "-";
            std.debug.print("{s: <6} {d: >2}..{d: <2} {d}:{d} in {s: <6} \"{s}\"\n", .{ g.node_kind_name(n), se[0], se[1], lc[0], lc[1], up, text[se[0]..se[1]] });
        }
        return .cont;
    }
    pub fn leave(_: *Show, _: g.Node) g.Walk {
        return .cont;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const tree = try g.parse_text(a, text, &err, &line, &col);
    const parents = try g.link_config(tree, a);
    var show = Show{ .parents = &parents };
    _ = try g.walk_config(tree, &show, a);
}
