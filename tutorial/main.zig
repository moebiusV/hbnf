// Read a shopping list with the parser hbnf made, and use the tree.
const std = @import("std");
const shopping = @import("shopping.zig");

const Total = struct {
    n: i64 = 0,
    pub fn visit_item(self: *Total, item: *const shopping.Item) void {
        self.n += item.qty;
    }
    pub fn visit_item_1_entry(_: *Total, _: *const shopping.Item1Entry) void {}
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = "buy 2 apples;\nbuy 1 milk from corner-shop;\n";
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const list = shopping.parse_text(a, text, &err, &line, &col) catch {
        std.debug.print("{s}\n", .{std.mem.sliceTo(&err, 0)}); // the message points at the text
        return;
    };
    for (list) |*item| {
        std.debug.print("{d} x {s}", .{ item.qty, item.name });
        for (item.item_1) |*from| std.debug.print(" (from {s})", .{from.shop}); // [ ... ] is 0 or 1
        std.debug.print("\n", .{});
    }
    var total = Total{};
    for (list) |*item| shopping.visit_item(item, &total); // parent before children
    std.debug.print("total: {d} items\n", .{total.n});
}
