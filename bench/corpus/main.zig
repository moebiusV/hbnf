// main.zig -- time a generated Zig parser over a corpus's own good files (bench/stage-zigada.sh).  MODULE,
// REPS and FILES are filled in by the stage (the files are embedded).  Every file is parsed REPS times
// into one arena that is never freed, so the memory is the trees'.  Prints ok BYTES COUNT SUM MS RSS_KIB
// on stderr (SUM is the number of files read); the time is the process's CPU time (std.time has no clock to read here).
const std = @import("std");
const g = @import("MODULE");

const File = struct { name: []const u8, data: []const u8 };
const files = [_]File{
FILES
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = arena.allocator();
    var err: [512]u8 = undefined;
    var line: usize = 0;
    var col: usize = 0;
    var ok: usize = 0;
    var bytes: usize = 0;
    var r: usize = 0;
    // the files this parser reads (the daemons' C-coded scanners are not read in Zig): one trial parse each
    var reads: [files.len]bool = undefined;
    var nread: usize = 0;
    for (files, 0..) |f, i| {
        reads[i] = if (g.parse_text(al, f.data, &err, &line, &col)) |_| true else |_| false;
        if (reads[i]) nread += 1;
    }
    while (r < REPS) : (r += 1) {
        for (files, 0..) |f, i| {
            if (!reads[i]) continue;
            bytes += f.data.len;
            if (g.parse_text(al, f.data, &err, &line, &col)) |_| {
                ok += 1;
            } else |_| {}
        }
    }
    const ru = std.posix.getrusage(std.posix.rusage.SELF);
    const us: i64 = (@as(i64, ru.utime.sec) + @as(i64, ru.stime.sec)) * 1000000 + @as(i64, ru.utime.usec) + @as(i64, ru.stime.usec);
    const good = nread > 0 and ok == REPS * nread;
    std.debug.print("{s} {d} {d} {d} {d}.{d:0>2} {d}\n", .{ if (good) "ok" else "FAIL", bytes, ok, nread, @as(u64, @intCast(@divTrunc(us, 1000))), @as(u64, @intCast(@divTrunc(@mod(us, 1000), 10))), @as(u64, @intCast(ru.maxrss)) });
    if (!good) std.process.exit(1);
}
