// The same vectors as segwit_main.c, inside "addr:" ... ";": `bitsof` in a grammar of
// text rules and bit rules together.  A mistake in the bits says at which word.
const std = @import("std");
const g = @import("segwit_in.zig");

const b0 = [_]u8{ 0x03,0xa8,0xf3,0xb7,0x40,0xcc,0x8c,0xb6,0xa2,0xa4,0xa0,0xe2,0x2e,0x8d,0x9d,0x19,0x1f,0x8a,0x19,0xde,0xb3,0x0e,0x98,0xae,0xa0 };
const b1 = [_]u8{ 0x00,0xc3,0x18,0xa1,0xe0,0xa6,0x28,0xb3,0x40,0x25,0xe8,0xc9,0x01,0x9a,0xb6,0xd0,0x9b,0x64,0xc2,0xb3,0xc6,0x6a,0x69,0x3d,0x0d,0xc6,0x31,0x94,0xb0,0x24,0x81,0x93,0x10,0x3e,0x1f,0xa5,0xbc };
const b2 = [_]u8{ 0x0b,0xcd,0xf3,0x33,0xf7,0xce,0xe5,0xdd,0x62,0xad,0x03,0x14,0xae,0x74,0x38,0x58,0x38,0x14,0xdf,0xe6,0xd9,0x6e,0x71,0x46,0xca,0xcf,0x94,0x0a,0xd8,0xb7,0xc0,0xbc,0xc0,0x0a,0xd4,0x94,0x9e };
const b3 = [_]u8{ 0x83,0xa8,0xf0,0x21,0xa2,0x55,0x24 };
const b4 = [_]u8{ 0x13,0xa8,0xf3,0xb7,0x40,0xcc,0x8c,0xb6,0xa2,0xa4,0xa0,0xe2,0x2e,0x8d,0x9d,0x19,0x19,0xd3,0x18,0x38,0x80 };
const b5 = [_]u8{ 0x00,0x00,0x08,0x10,0x18,0x20,0x28,0x30,0x38,0x40,0x48,0x50,0x58,0x60,0x68,0x70,0x78,0x80,0x88,0x90,0x98,0xa0,0x00,0x00,0x00,0x00 };
const b6 = [_]u8{ 0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const b7 = [_]u8{ 0x08,0x08,0x00,0x00,0x00,0x00 };
const b8 = [_]u8{ 0x08,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const b9 = [_]u8{ 0x08,0x08,0x10,0x18,0x20,0x28,0x30,0x38,0x40,0x48,0x50,0x58,0x60,0x68,0x70,0x78,0x80,0x88,0x90,0x98,0xa0,0xaa,0x00,0x00,0x00,0x00 };
const b10 = [_]u8{ 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00 };
const b11 = [_]u8{ 0x08,0x08,0x10,0x18,0x20,0x28,0x30,0x38,0x40,0x48,0x50,0x58,0x60,0x68,0x70,0x78,0x80,0x88,0x90,0x98,0xa0,0xa8,0x00,0x00,0x00,0x00 };

fn wrap(a: std.mem.Allocator, t: []const u8) []u8 {
    return std.fmt.allocPrint(a, "addr:{s};", .{t}) catch unreachable;
}

const Err = struct {
    buf: [512]u8 = undefined,
    line: usize = 0,
    col: usize = 0,

    // the first line of the message
    fn first(self: *const Err) []const u8 {
        const m = std.mem.sliceTo(&self.buf, 0);
        return m[0 .. std.mem.indexOfScalar(u8, m, '\n') orelse m.len];
    }
};

const Vec = struct { name: []const u8, valid: bool, nbits: usize, bytes: []const u8, version: i32, program: []const u8 };

const vecs = [_]Vec{
    .{ .name = "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", .valid = true, .nbits = 195, .bytes = &b0, .version = 0, .program = "751e76e8199196d454941c45d1b3a323f1433bd6" },
    .{ .name = "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5", .valid = true, .nbits = 295, .bytes = &b1, .version = 0, .program = "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262" },
    .{ .name = "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5j", .valid = true, .nbits = 295, .bytes = &b2, .version = 1, .program = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" },
    .{ .name = "BC1SW50QGDZ25J", .valid = true, .nbits = 55, .bytes = &b3, .version = 16, .program = "751e" },
    .{ .name = "bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs", .valid = true, .nbits = 165, .bytes = &b4, .version = 2, .program = "751e76e8199196d454941c45d1b3a323" },
    .{ .name = "v0 with a 21-octet program", .valid = false, .nbits = 205, .bytes = &b5, .version = -1, .program = "" },
    .{ .name = "version 17", .valid = false, .nbits = 195, .bytes = &b6, .version = -1, .program = "" },
    .{ .name = "a 1-octet program", .valid = false, .nbits = 45, .bytes = &b7, .version = -1, .program = "" },
    .{ .name = "a 41-octet program", .valid = false, .nbits = 365, .bytes = &b8, .version = -1, .program = "" },
    .{ .name = "padding that is not zero", .valid = false, .nbits = 205, .bytes = &b9, .version = -1, .program = "" },
    .{ .name = "v0 with a 19-octet program", .valid = false, .nbits = 190, .bytes = &b10, .version = -1, .program = "" },
    .{ .name = "v1 with a 21-octet program (2 padding bits)", .valid = true, .nbits = 205, .bytes = &b11, .version = 1, .program = "0102030405060708090a0b0c0d0e0f101112131415" },
};

fn hex(a: std.mem.Allocator, p: []const u8) []u8 {
    const out = a.alloc(u8, p.len * 2) catch unreachable;
    for (p, 0..) |b, i| _ = std.fmt.bufPrint(out[2 * i .. 2 * i + 2], "{x:0>2}", .{b}) catch unreachable;
    return out;
}

// nbits of bytes, 5 at a time, as bech32 characters
fn symbols(a: std.mem.Allocator, b: []const u8, nbits: usize) []u8 {
    const set = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    const out = a.alloc(u8, nbits / 5) catch unreachable;
    for (out, 0..) |*o, i| {
        var v: usize = 0;
        for (0..5) |k| {
            const bit = i * 5 + k;
            v = (v << 1) | ((b[bit >> 3] >> @intCast(7 - (bit & 7))) & 1);
        }
        o.* = set[v];
    }
    return out;
}

pub fn main() u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var bad: u8 = 0;
    for (vecs) |v| {
        const text = wrap(a, symbols(a, v.bytes, v.nbits));
        var er = Err{};
        if (g.parse_text(a, text, &er.buf, &er.line, &er.col)) |m| {
            const out = m.segwit;
            if (!v.valid) {
                std.debug.print("FAIL accepted: {s}\n", .{v.name});
                bad += 1;
            } else if (out.version == v.version and std.mem.eql(u8, hex(a, out.program), v.program)) {
                std.debug.print("PASS {s}: version {d}, {d} octets\n", .{ v.name, out.version, out.program.len });
            } else {
                std.debug.print("FAIL {s}: read as something else\n", .{v.name});
                bad += 1;
            }
        } else |_| {
            if (v.valid) {
                std.debug.print("FAIL {s}: {s}\n", .{ v.name, er.first() });
                bad += 1;
            } else {
                std.debug.print("PASS refused: {s} ({s})\n", .{ v.name, er.first() });
            }
        }
    }
    // the data parts of real addresses, read and written back as text
    const texts = [_][]const u8{
        "qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
        "qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7",
        "p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0",
        "sw50qgdz25j",
        "zw508d6qejxtdg4y5r3zarvaryvaxxpcs",
    };
    for (texts, 0..) |t0, i| {
        const t = wrap(a, t0);
        var er = Err{};
        const doc = g.parse_text(a, t, &er.buf, &er.line, &er.col) catch {
            std.debug.print("FAIL text {d}: {s}\n", .{ i, er.first() });
            bad += 1;
            continue;
        };
        const out = doc.segwit;
        var m: []const u8 = "";
        const written = g.emit_bits_segwit(a, out, &m) catch {
            std.debug.print("FAIL text {d}: emit: {s}\n", .{ i, m });
            bad += 1;
            continue;
        };
        const back = written.bytes[0 .. written.nbits / 8];
        if (!std.mem.eql(u8, back, t0)) {
            std.debug.print("FAIL text {d}: written back as {s}\n", .{ i, back });
            bad += 1;
        } else {
            std.debug.print("PASS text {d}: version {d}, {d} octets, written back\n", .{ i, out.version, out.program.len });
        }
    }
    var er = Err{};
    if (g.parse_text(a, "addr:qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3tb;", &er.buf, &er.line, &er.col)) |_| {
        std.debug.print("FAIL b is not a bech32 symbol\n", .{});
    } else |_| {
        std.debug.print("PASS refused: b is not a bech32 symbol\n", .{});
    }
    return bad;
}
