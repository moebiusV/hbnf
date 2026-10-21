// A pretty-printer's say in how the tree is written (Layout): a newline before every "buy" but the
// first, "from" in capitals, and a log of the rules entered.
const std = @import("std");
const g = @import("shopping.zig");

const Pretty = struct {
    buys: usize = 0,
    log: std.ArrayList(u8) = .empty,
    al: std.mem.Allocator,

    fn before(ctx: ?*anyopaque, s: []const u8) ?[]const u8 {
        const self: *Pretty = @ptrCast(@alignCast(ctx));
        if (std.mem.eql(u8, s, "buy")) {
            self.buys += 1;
            if (self.buys > 1) return "\n";
        }
        return null;
    }
    fn replace(_: ?*anyopaque, s: []const u8) ?[]const u8 {
        return if (std.mem.eql(u8, s, "from")) "FROM" else null;
    }
    fn enter(ctx: ?*anyopaque, rule: []const u8) void {
        const self: *Pretty = @ptrCast(@alignCast(ctx));
        self.log.appendSlice(self.al, " ") catch {};
        self.log.appendSlice(self.al, rule) catch {};
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const list = try g.parse_text(a, "buy 2 apples;\nbuy 1 milk from corner-shop;\n", &err, &line, &col);
    var p = Pretty{ .al = a };
    var msg: []const u8 = "";
    const out = try g.write_list_with(a, &list, .{ .ctx = &p, .before = Pretty.before, .replace = Pretty.replace, .enter = Pretty.enter }, &msg);
    std.debug.print("{s}\nrules:{s}\n", .{ out, p.log.items });
}
