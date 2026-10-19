// BIP-39 mnemonics through the Zig interface: the same entropy, phrases and
// checksums as mnemonic_main.c.  The grammar's code is Zig (mnemonic_zig.hbnf).
const std = @import("std");
const g = @import("mnemonic_zig.zig");

const e0 = [_]u8{ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const e1 = [_]u8{ 0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f };
const e2 = [_]u8{ 0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80 };
const e3 = [_]u8{ 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff };
const e4 = [_]u8{ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const e5 = [_]u8{ 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff };
const e6 = [_]u8{ 0x0c,0x1e,0x24,0xe5,0x91,0x77,0x79,0xd2,0x97,0xe1,0x4d,0x45,0xf1,0x4e,0x1a,0x1a };
const e7 = [_]u8{ 0x9e,0x88,0x5d,0x95,0x2a,0xd3,0x62,0xca,0xeb,0x4e,0xfe,0x34,0xa8,0xe9,0x1b,0xd2 };
const e8 = [_]u8{ 0x06,0x6d,0xca,0x1a,0x2b,0xb7,0xe8,0xa1,0xdb,0x28,0x32,0x14,0x8c,0xe9,0x93,0x3e,0xea,0x0f,0x3a,0xc9,0x54,0x8d,0x79,0x31,0x12,0xd9,0xa9,0x5c,0x94,0x07,0xef,0xad };
const e9 = [_]u8{ 0xf5,0x85,0xc1,0x1a,0xec,0x52,0x0d,0xb5,0x7d,0xd3,0x53,0xc6,0x95,0x54,0xb2,0x1a,0x89,0xb2,0x0f,0xb0,0x65,0x09,0x66,0xfa,0x0a,0x9d,0x6f,0x74,0xfd,0x98,0x9d,0x8f };
const e10 = [_]u8{ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const e11 = [_]u8{ 0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f };
const e12 = [_]u8{ 0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80 };
const e13 = [_]u8{ 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff };
const e14 = [_]u8{ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const e15 = [_]u8{ 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff };
const e16 = [_]u8{ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const e17 = [_]u8{ 0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff };

const Vec = struct { phrase: []const u8, n: usize, entropy: []const u8, cs: u64 };

const vecs = [_]Vec{
    .{ .phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", .n = 16, .entropy = &e0, .cs = 3 },
    .{ .phrase = "legal winner thank year wave sausage worth useful legal winner thank yellow", .n = 16, .entropy = &e1, .cs = 8 },
    .{ .phrase = "letter advice cage absurd amount doctor acoustic avoid letter advice cage above", .n = 16, .entropy = &e2, .cs = 4 },
    .{ .phrase = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong", .n = 16, .entropy = &e3, .cs = 5 },
    .{ .phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art", .n = 32, .entropy = &e4, .cs = 102 },
    .{ .phrase = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote", .n = 32, .entropy = &e5, .cs = 175 },
    .{ .phrase = "army van defense carry jealous true garbage claim echo media make crunch", .n = 16, .entropy = &e6, .cs = 7 },
    .{ .phrase = "ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic", .n = 16, .entropy = &e7, .cs = 1 },
    .{ .phrase = "all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform", .n = 32, .entropy = &e8, .cs = 162 },
    .{ .phrase = "void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold", .n = 32, .entropy = &e9, .cs = 105 },
    .{ .phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent", .n = 24, .entropy = &e10, .cs = 39 },
    .{ .phrase = "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal will", .n = 24, .entropy = &e11, .cs = 25 },
    .{ .phrase = "letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter always", .n = 24, .entropy = &e12, .cs = 60 },
    .{ .phrase = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when", .n = 24, .entropy = &e13, .cs = 17 },
    .{ .phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon address", .n = 20, .entropy = &e14, .cs = 27 },
    .{ .phrase = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrist", .n = 20, .entropy = &e15, .cs = 19 },
    .{ .phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon admit", .n = 28, .entropy = &e16, .cs = 29 },
    .{ .phrase = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo veteran", .n = 28, .entropy = &e17, .cs = 25 },
};

pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var bad: u8 = 0;
    for (vecs) |v| {
        const words = (v.n * 8 + v.n * 8 / 32) / 11;
        const want_warn = v.n != 16 and v.n != 32;
        var er: g.ParseError = .{};
        const out = g.parse_text(a, v.phrase, &er) catch {
            std.debug.print("FAIL {d} words: {s}\n", .{ words, er.message });
            bad += 1;
            continue;
        };
        const warns = g.hbnf_warnings();
        if (!std.mem.eql(u8, out.entropy, v.entropy) or out.checksum != v.cs) {
            std.debug.print("FAIL {d} words: entropy or checksum differs\n", .{words});
            bad += 1;
        } else if ((warns.len != 0) != want_warn) {
            std.debug.print("FAIL {d} words: {d} warning(s)\n", .{ words, warns.len });
            bad += 1;
        } else {
            var m: []const u8 = "";
            if (g.emit_text(a, out, &m)) |back| {
                if (!std.mem.eql(u8, back, v.phrase)) {
                    std.debug.print("FAIL {d} words: written back as {s}\n", .{ words, back });
                    bad += 1;
                } else {
                    std.debug.print("PASS {d} words, entropy {d} octets, checksum {d}{s}{s}, written back\n", .{
                        words,                                v.n, v.cs,
                        if (warns.len != 0) ", warning: " else "", if (warns.len != 0) warns[0] else "",
                    });
                }
            } else |_| {
                std.debug.print("FAIL {d} words: emit: {s}\n", .{ words, m });
                bad += 1;
            }
        }
    }
    const no = [_][2][]const u8{
        .{ "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon", "11 words" },
        .{ "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandonn", "a misspelt word" },
        .{ "abandon  abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", "two blanks" },
        .{ "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about ", "a trailing blank" },
        .{ "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon", "a wrong checksum (all abandon)" },
        .{ "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo", "a wrong checksum (all zoo)" },
        .{ "", "nothing" },
    };
    for (no) |c| {
        var er: g.ParseError = .{};
        if (g.parse_text(a, c[0], &er)) |_| {
            std.debug.print("FAIL accepted: {s}\n", .{c[1]});
            bad += 1;
        } else |_| {
            std.debug.print("PASS refused: {s} ({s})\n", .{ c[1], er.message });
        }
    }
    // writing: only the entropy is set, and %emit works out the checksum
    for (vecs) |v| {
        const t = g.Mnemonic{ .entropy = a.dupe(u8, v.entropy) catch unreachable, .checksum = 0x55 }; // wrong on purpose
        var m: []const u8 = "";
        if (g.emit_text(a, t, &m)) |back| {
            if (!std.mem.eql(u8, back, v.phrase)) {
                std.debug.print("FAIL generate: {s}\n", .{back});
                bad += 1;
            } else {
                std.debug.print("PASS generated {d} words from {d} octets of entropy\n", .{ (v.n * 8 + v.n * 8 / 32) / 11, v.n });
            }
        } else |_| {
            std.debug.print("FAIL generate: {s}\n", .{m});
            bad += 1;
        }
    }
    return bad;
}
