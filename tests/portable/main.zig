// tests/portable.sh's Zig driver: parse each file and print what it holds,
// as main.c, main.rs and portable_main.adb do.  The files are embedded, and
// std.debug.print writes to stderr, which portable.sh reads.
const std = @import("std");
const g = @import("portable.zig");

const cases = [_]struct { name: []const u8, text: []const u8 }{
    .{ .name = "good.conf", .text = @embedFile("good.conf") },
    .{ .name = "lead-comma.bad", .text = @embedFile("lead-comma.bad") },
    .{ .name = "lead-op.bad", .text = @embedFile("lead-op.bad") },
    .{ .name = "pair-four.bad", .text = @embedFile("pair-four.bad") },
    .{ .name = "pair-one.bad", .text = @embedFile("pair-one.bad") },
    .{ .name = "slow-line4.bad", .text = @embedFile("slow-line4.bad") },
    .{ .name = "slow-upper.bad", .text = @embedFile("slow-upper.bad") },
    .{ .name = "trailing-op.bad", .text = @embedFile("trailing-op.bad") },
};

pub fn main() void {
    for (cases) |cs| {
        var err: [512]u8 = undefined;
        var el: usize = 0;
        var ec: usize = 0;
        const c = g.parse_text(std.heap.page_allocator, cs.text, &err, &el, &ec) catch {
            std.debug.print("{s}: rejected at line {d}\n", .{ cs.name, el });
            continue;
        };
        std.debug.print("{s}: hosts", .{cs.name});
        for (c.host_list) |h| std.debug.print(" {s}", .{h.host});
        std.debug.print("; calc", .{});
        var acc: i64 = 0;
        for (c.sum, 0..) |s, k| {
            if (k == 0) { // the base
                acc = s.int;
                std.debug.print(" {d}", .{s.int});
            } else {
                const plus = s.op == .op1;
                acc += if (plus) s.int else -s.int;
                std.debug.print(" {s} {d}", .{ if (plus) "+" else "-", s.int });
            }
        }
        std.debug.print(" = {d}; modes", .{acc});
        for (c.modes) |m| std.debug.print(" {s}", .{if (m.modeset.mode == .fast) "fast" else "slow"});
        std.debug.print("; pair", .{});
        for (c.pair) |p| std.debug.print(" {s}", .{p});
        std.debug.print("\n", .{});
    }
}
