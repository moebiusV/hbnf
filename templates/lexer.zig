fn lxDigit(c: u8) bool { return c >= '0' and c <= '9'; }
fn lxWordStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')
        or c == '_' or c == '-';
}
fn lxWordChar(c: u8) bool { return lxWordStart(c) or lxDigit(c) or c == '.'; }

pub fn lex(alloc: std.mem.Allocator, text: []const u8) ![]Token {
    var toks = std.ArrayList(Token).empty;
    var i: usize = 0; var line: usize = 1; var col: usize = 1;
    while (i < text.len) {
        const c = text[i];
        {
            // Hand-written jet scanners (schema `{ }` blocks) win first.
            var jk: Kind = .eof;
            const jl = jet_dispatch(text, i, text.len, &jk);
            if (jl > 0) {
                try toks.append(alloc, .{ .kind = jk, .text = text[i..i + jl], .line = line, .col = col });
                i += jl; col += jl;
                continue;
            }
        }
        if (c == ' ' or c == '\t' or c == '\r') { i += 1; col += 1; }
        else if (c == '\n') { i += 1; line += 1; col = 1; }
        else if (c == '#') { while (i < text.len and text[i] != '\n') i += 1; }
        else if (c == '"') {
            const sc = col;
            var s = std.ArrayList(u8).empty;
            i += 1; col += 1;
            while (i < text.len and text[i] != '"') {
                if (text[i] == '\\' and i + 1 < text.len) { i += 1; col += 1; }
                try s.append(alloc, text[i]);
                i += 1; col += 1;
            }
            if (i < text.len and text[i] == '"') { i += 1; col += 1; }
            try toks.append(alloc, .{ .kind = .str, .text = try s.toOwnedSlice(alloc), .line = line, .col = sc });
        }
        else if (lxDigit(c) or (c == '-' and i + 1 < text.len and lxDigit(text[i + 1]))) {
            // -N is a number too, as in parse.y's lexers
            const s = i; const sc = col;
            if (c == '-') { i += 1; col += 1; }
            while (i < text.len and lxDigit(text[i])) { i += 1; col += 1; }
            if (i < text.len and lxWordChar(text[i])) {
                // dotted/alphanumeric run (1.2.3.4, 123abc) is one word
                i = s; col = sc;
                while (i < text.len and lxWordChar(text[i])) { i += 1; col += 1; }
                try toks.append(alloc, .{ .kind = .atom, .text = text[s..i], .line = line, .col = sc });
            } else {
                try toks.append(alloc, .{ .kind = .int, .text = text[s..i], .line = line, .col = sc });
            }
        }
        else if (lxWordStart(c)) {
            const s = i; const sc = col;
            while (i < text.len and lxWordChar(text[i])) { i += 1; col += 1; }
            try toks.append(alloc, .{ .kind = .atom, .text = text[s..i], .line = line, .col = sc });
        }
        else {
            try toks.append(alloc, .{ .kind = .punct, .text = text[i..i + 1], .line = line, .col = col });
            i += 1; col += 1;
        }
    }
    try toks.append(alloc, .{ .kind = .eof, .text = "", .line = line, .col = col });
    return toks.toOwnedSlice(alloc);
}

pub fn parse_text(alloc: std.mem.Allocator, text: []const u8,
                  err: *[512]u8, err_line: *usize, err_col: *usize) ParseError!@ROOT_TYPE@ {
    const toks = try lex(alloc, text);
    var lines = std.ArrayList([]const u8).empty;
    var s: usize = 0;
    for (text, 0..) |ch, idx| {
        if (ch == '\n') {
            try lines.append(alloc, text[s..idx]);
            s = idx + 1;
        }
    }
    try lines.append(alloc, text[s..]);
    return parse_tokens(alloc, toks, lines.items, err, err_line, err_col);
}
