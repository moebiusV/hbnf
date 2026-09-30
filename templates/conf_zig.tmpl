pub var conf_file: ?[]const u8 = null;

// yyerror-style handler: the parser calls config_error() at the point of
// failure with the caret message.  Default prints "file:line: msg" (file from
// conf_file) and exits; assign config_error to take the message yourself, in
// which case parse_config returns the error instead of exiting.
pub var config_error: *const fn(usize, []const u8) void = defaultConfigError;

fn defaultConfigError(line: usize, msg: []const u8) void {
    if (conf_file) |f| {
        if (line > 0) {
            std.debug.print("{s}:{d}: {s}\n", .{ f, line, msg });
        } else {
            std.debug.print("{s}: {s}\n", .{ f, msg });
        }
    } else if (line > 0) {
        std.debug.print("{d}: {s}\n", .{ line, msg });
    } else {
        std.debug.print("{s}\n", .{msg});
    }
    std.process.exit(1);
}

pub fn parse_config(alloc: std.mem.Allocator, path: []const u8) ParseError!@ROOT_TYPE@ {
    conf_file = path;
    var threaded = std.Io.Threaded.init(alloc, .{});
    const text = std.Io.Dir.cwd().readFileAlloc(
        threaded.io(), path, alloc, .limited(1 << 20)) catch {
        config_error(0, "cannot open file");
        return error.Invalid;
    };
    var err: [512]u8 = undefined;
    var el: usize = 0;
    var ec: usize = 0;
    return parse_text(alloc, text, &err, &el, &ec) catch |e| {
        config_error(el, std.mem.sliceTo(&err, 0));
        return e;
    };
}
