// The Zig interface against the same fixtures as net_main.c, and the same output.
const std = @import("std");
const g = @import("net.zig");

fn cat(a: std.mem.Allocator, parts: []const []const u8) []u8 {
    var v: std.ArrayList(u8) = .empty;
    for (parts) |p| v.appendSlice(a, p) catch unreachable;
    return v.items;
}

fn eth(a: std.mem.Allocator, rest: []const []const u8) []u8 {
    const head = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55";
    var v: std.ArrayList(u8) = .empty;
    v.appendSlice(a, head) catch unreachable;
    for (rest) |r| v.appendSlice(a, r) catch unreachable;
    return v.items;
}

fn kind(p: g.BnfEthernetPayload) i32 {
    return switch (p) {
        .a1 => 1,
        .a2 => 2,
        .a3 => 3,
        .a4 => 4,
    };
}

fn show(a: std.mem.Allocator, what: []const u8, b: []const u8) void {
    var er: g.ParseError = .{};
    const e = g.parse_bytes(a, b, &er) catch {
        std.debug.print("{s}: error at octet {d}: {s}\n", .{ what, er.at, er.message });
        return;
    };
    std.debug.print("{s}: ethertype={x:0>4} kind={d}", .{ what, e.ethertype, kind(e.payload) });
    switch (e.payload) {
        .a1 => |x| {
            const ip = x.ip;
            std.debug.print(" ipv4 ihl={d} len={d} ttl={d} proto={d} src={x:0>8} dst={x:0>8} opts={d}", .{ ip.ihl, ip.total_length, ip.ttl, ip.protocol, ip.src, ip.dst, ip.options.len });
            switch (ip.payload) {
                .a1 => |y| std.debug.print(" tcp {d}>{d} seq={d} syn={d} data={d}", .{ y.t.src_port, y.t.dst_port, y.t.seq_num, y.t.syn, y.t.payload.len }),
                .a2 => |y| std.debug.print(" udp {d}>{d} len={d} data={d}", .{ y.u.src_port, y.u.dst_port, y.u.length, y.u.payload.len }),
                .a3 => |y| std.debug.print(" data={d}", .{y.rest.len}),
            }
        },
        .a2 => |x| std.debug.print(" arp oper={d} spa={x:0>8} tpa={x:0>8}", .{ x.a.oper, x.a.spa, x.a.tpa }),
        .a3 => |x| std.debug.print(" ipv6 flow={x:0>5} next={d} hop={d} data={d}", .{ x.v6.flow_label, x.v6.next_header, x.v6.hop_limit, x.v6.payload.len }),
        .a4 => |x| std.debug.print(" raw={d}", .{x.rest.len}),
    }
    std.debug.print("\n", .{});

    // and back: the bytes read are the bytes written
    var m: []const u8 = "";
    if (g.emit_bytes(a, e, &m)) |out| {
        if (std.mem.eql(u8, out, b)) {
            std.debug.print("  emit: {d} octets, identical\n", .{out.len});
        } else {
            std.debug.print("  emit: DIFFERENT ({d} octets)\n", .{out.len});
        }
    } else |_| {
        std.debug.print("  emit: error: {s}\n", .{m});
    }
}

fn bad_emit(a: std.mem.Allocator, what: []const u8, e: g.BnfEthernet) void {
    var m: []const u8 = "";
    if (g.emit_bytes(a, e, &m)) |out| {
        std.debug.print("{s}: written ({d} octets)\n", .{ what, out.len });
    } else |_| {
        std.debug.print("{s}: {s}\n", .{ what, m });
    }
}

pub fn main() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ip = eth(a, &.{
        "\x08\x00",
        "\x46\x00\x00\x20\x12\x34\x40\x00\x40\x01\xab\xcd",
        "\x0a\x00\x00\x01\x0a\x00\x00\x02",
        "\x01\x01\x01\x00", // options (ihl 6)
        "hi!!",
    });
    const tcp = eth(a, &.{
        "\x08\x00",
        "\x45\x00\x00\x2c\x00\x01\x00\x00\x40\x06\x00\x00",
        "\xc0\xa8\x00\x01\xc0\xa8\x00\x02",
        "\x1f\x90\x00\x50\x00\x00\x00\x01\x00\x00\x00\x00\x50\x02\x20\x00",
        "\x00\x00\x00\x00",
        "ping",
    });
    const udp = eth(a, &.{
        "\x08\x00",
        "\x45\x00\x00\x1f\x00\x02\x00\x00\x40\x11\x00\x00",
        "\x0a\x00\x00\x01\x0a\x00\x00\x02",
        "\x00\x35\x12\x34\x00\x0b\x00\x00",
        "abc",
    });
    const arp = eth(a, &.{
        "\x08\x06",
        "\x00\x01\x08\x00\x06\x04\x00\x01",
        "\x00\x11\x22\x33\x44\x55\xc0\xa8\x00\x01",
        "\x00\x00\x00\x00\x00\x00\xc0\xa8\x00\x02",
    });
    const v6 = eth(a, &.{
        "\x86\xdd",
        "\x60\x01\x23\x45\x00\x04\x11\x40",
        "\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01",
        "\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02",
        "abcd",
    });
    const other = eth(a, &.{"\x88\xcc\x01\x02"}); // LLDP: not listed
    show(a, "ipv4", ip);
    show(a, "tcp", tcp);
    show(a, "udp", udp);
    show(a, "arp", arp);
    show(a, "ipv6", v6);
    show(a, "unlisted ethertype", other);
    show(a, "short", ip[0..10]);

    var er: g.ParseError = .{};
    const e = g.parse_bytes(a, tcp, &er) catch unreachable;
    {
        var c = e;
        var i = c.payload.a1.ip;
        i.ihl = 16;
        c.payload = .{ .a1 = .{ .ip = i } };
        bad_emit(a, "ihl 16", c);
    }
    {
        var c = e;
        var i = c.payload.a1.ip;
        const z = a.alloc(u8, 4) catch unreachable;
        @memset(z, 0);
        i.options = z;
        c.payload = .{ .a1 = .{ .ip = i } };
        bad_emit(a, "options longer than ihl says", c);
    }
    {
        var c = e;
        const ap = g.parse_bytes(a, arp, &er) catch unreachable;
        c.payload = .{ .a2 = .{ .a = ap.payload.a2.a } };
        bad_emit(a, "arp payload for an ipv4 ethertype", c);
    }
    {
        var c = e;
        c.ethertype = 0x1234;
        bad_emit(a, "ethertype not in the list", c);
    }
}
