// The walker and the dump the generator makes (--ast), the same in every language.
const std = @import("std");
const shopping = @import("shopping.zig");

const Show = struct {
    depth: usize = 0,
    pub fn enter(self: *Show, n: shopping.Node) shopping.Walk {
        for (0..self.depth) |_| std.debug.print("  ", .{});
        std.debug.print("{s}\n", .{shopping.node_kind_name(n)});
        self.depth += 1;
        return .cont;
    }
    pub fn leave(self: *Show, _: shopping.Node) shopping.Walk {
        self.depth -= 1;
        return .cont;
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    const text = "buy 2 apples;\nbuy 1 milk from corner-shop;\n";
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const list = try shopping.parse_text(a, text, &err, &line, &col);
    var show = Show{};
    _ = try shopping.walk_list(list, &show, a);
    std.debug.print("{s}\n", .{try shopping.dump_list(list, a)});
}
