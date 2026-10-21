// How a walker, a dump and a pretty-printer are made: plain functions over the typed tree.
// Nothing here is generated; it is what you would write.  (The parse is messy on purpose.)
const std = @import("std");
const shopping = @import("shopping.zig");
const print = std.debug.print;

fn indent(depth: usize) void {
    for (0..depth) |_| print("  ", .{});
}

// Walk: one function per rule, children in the order the grammar has them.
fn walkItem(item: *const shopping.Item, depth: usize) void {
    indent(depth);
    print("item\n", .{});
    indent(depth + 1);
    print("qty {d}\n", .{item.qty});
    indent(depth + 1);
    print("name {s}\n", .{item.name});
    for (item.item_1) |*from| {
        indent(depth + 1);
        print("from\n", .{});
        indent(depth + 2);
        print("shop {s}\n", .{from.shop});
    }
}

fn walkList(list: shopping.List) void {
    print("list\n", .{});
    for (list) |*item| walkItem(item, 1);
}

// Dump: the same recursion, but it writes an S-expression.
fn dumpList(list: shopping.List) void {
    print("(list", .{});
    for (list) |*item| {
        print(" (item (qty {d}) (name \"{s}\")", .{ item.qty, item.name });
        for (item.item_1) |*from| print(" (from (shop \"{s}\"))", .{from.shop});
        print(")", .{});
    }
    print(")\n", .{});
}

// Pretty-print: the text the grammar reads, in one canonical layout.
fn printList(list: shopping.List) void {
    for (list) |*item| {
        print("buy {d} {s}", .{ item.qty, item.name });
        for (item.item_1) |*from| print(" from {s}", .{from.shop});
        print(";\n", .{});
    }
}

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const text = "buy  2   apples ;\n  buy 1\n milk from   corner-shop ;";
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const list = shopping.parse_text(arena.allocator(), text, &err, &line, &col) catch {
        print("{s}\n", .{std.mem.sliceTo(&err, 0)});
        return;
    };
    print("== walk\n", .{});
    walkList(list);
    print("== dump\n", .{});
    dumpList(list);
    print("== print\n", .{});
    printList(list);
}
