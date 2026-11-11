// tree-driver.zig: parses the two texts on the command line with the grammar (root `cond`, module p.zig) and says
// whether their trees are the same (every field alike, strings by content), different, or neither is a sentence.
const std = @import("std");
const g = @import("p.zig");

fn eq(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    switch (@typeInfo(T)) {
        .pointer => |pi| {
            if (pi.size == .slice) {
                if (a.len != b.len) return false;
                if (pi.child == u8) return std.mem.eql(u8, a, b);
                for (a, b) |x, y| if (!eq(x, y)) return false;
                return true;
            }
            return eq(a.*, b.*);
        },
        .@"struct" => |si| {
            inline for (si.fields) |f| if (!eq(@field(a, f.name), @field(b, f.name))) return false;
            return true;
        },
        .optional => {
            if (a == null or b == null) return a == null and b == null;
            return eq(a.?, b.?);
        },
        else => return std.meta.eql(a, b),
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) std.process.exit(2);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const a: ?g.Cond = g.parse_text(arena.allocator(), args[1], &err, &line, &col) catch null;
    const b: ?g.Cond = g.parse_text(arena.allocator(), args[2], &err, &line, &col) catch null;
    const out: []const u8 = if (a == null and b == null) "error\n"
        else if (a != null and b != null and eq(a.?, b.?)) "same\n"
        else "different\n";
    std.debug.print("{s}", .{out});
}
