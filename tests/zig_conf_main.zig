const std = @import("std");
const g = @import("server.zig");

fn myError(line: usize, msg: []const u8) void {
    std.debug.print("callback: line={d} msg=\n{s}\n", .{ line, msg });
}

pub fn main() !void {
    const s = g.parse_config(std.heap.page_allocator, "valid.conf") catch {
        std.debug.print("valid: FAILED\n", .{});
        return;
    };
    std.debug.print("valid: OK name={s} port={d}\n", .{ s.name, s.listen.port });

    g.config_error = myError;
    _ = g.parse_config(std.heap.page_allocator, "bad.conf") catch {
        std.debug.print("bad: handled by callback (returned error)\n", .{});
        return;
    };
    std.debug.print("bad: unexpectedly OK\n", .{});
}
