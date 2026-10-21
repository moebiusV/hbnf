// The writer's gate in Zig (tests/writer.sh): for each file, parse it, write the tree, parse what
// was written, write again.  The first write must re-parse to the same tree (the same dump), and the
// second write must be the same text as the first.  MODULE and ROOT are filled in by the script, and
// the files are embedded (FILES).
const std = @import("std");
const g = @import("MODULE");

const File = struct { name: []const u8, data: []const u8 };
const files = [_]File{
FILES
};

fn dumpOf(al: std.mem.Allocator, tree: anytype) ![]u8 {
    const P = @typeInfo(@TypeOf(g.dump_ROOT)).@"fn".params[0].type.?;
    if (@typeInfo(P) == .pointer and @typeInfo(P).pointer.size == .one) return g.dump_ROOT(&tree, al);
    return g.dump_ROOT(tree, al);
}

fn roundtrip(al: std.mem.Allocator, f: File) !bool {
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    const t1 = g.parse_text(al, f.data, &err, &line, &col) catch {
        std.debug.print("{s}: SKIP (does not parse)\n", .{f.name});
        return false;
    };
    var msg: []const u8 = "";
    const a = g.write_ROOT(al, &t1, &msg) catch {
        std.debug.print("{s}: FAIL (cannot write: {s})\n", .{ f.name, msg });
        return true;
    };
    const t2 = g.parse_text(al, a, &err, &line, &col) catch {
        std.debug.print("{s}: FAIL (the written text does not parse: {s})\n--- written ---\n{s}\n---\n", .{ f.name, std.mem.sliceTo(&err, 0), a });
        return true;
    };
    const b = g.write_ROOT(al, &t2, &msg) catch {
        std.debug.print("{s}: FAIL (cannot write again: {s})\n", .{ f.name, msg });
        return true;
    };
    const d1 = try dumpOf(al, t1);
    const d2 = try dumpOf(al, t2);
    if (!std.mem.eql(u8, d1, d2)) {
        std.debug.print("{s}: FAIL (the written text reads as a different tree)\n--- before ---\n{s}\n--- after ---\n{s}\n--- text ---\n{s}\n", .{ f.name, d1, d2, a });
        return true;
    }
    if (!std.mem.eql(u8, a, b)) {
        std.debug.print("{s}: FAIL (not idempotent)\n--- first ---\n{s}\n--- second ---\n{s}\n", .{ f.name, a, b });
        return true;
    }
    std.debug.print("{s}: ok ({d} bytes)\n", .{ f.name, a.len });
    return false;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var bad: usize = 0;
    for (files) |f| {
        if (try roundtrip(arena.allocator(), f)) bad += 1;
    }
    if (bad != 0) std.process.exit(1);
}
