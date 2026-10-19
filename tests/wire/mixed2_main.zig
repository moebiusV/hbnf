// A bit rule that holds a text token.
const std = @import("std");
const g = @import("mixed2.zig");

fn show(what: []const u8, text: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var err: [512]u8 = undefined;
    var l: usize = 0;
    var c: usize = 0;
    if (g.parse_text(arena.allocator(), text, &err, &l, &c)) |out| {
        std.debug.print("{s}: kind={d} label={s}\n", .{ what, out.record.kind, out.record.label });
    } else |_| {
        std.debug.print("{s}: error\n{s}\n", .{ what, std.mem.sliceTo(&err, 0) });
    }
}

pub fn main() void {
    show("abc", "REC:\x07abc");
    show("a letter as the kind", "REC:abc");
    show("no label", "REC:\x07");
    show("digits", "REC:\x07123");
}
