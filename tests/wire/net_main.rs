// The Rust interface against the same fixtures as net_main.c, and the same output.
mod net;
use net::*;

fn eth(rest: &[&[u8]]) -> Vec<u8> {
    let mut v = vec![0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55];
    for r in rest {
        v.extend_from_slice(r);
    }
    v
}

fn kind(p: &BnfEthernetPayload) -> i32 {
    match p {
        BnfEthernetPayload::A1 { .. } => 1,
        BnfEthernetPayload::A2 { .. } => 2,
        BnfEthernetPayload::A3 { .. } => 3,
        BnfEthernetPayload::A4 { .. } => 4,
    }
}

fn show(what: &str, b: &[u8]) {
    let e = match parse_bytes(b) {
        Ok(e) => e,
        Err(er) => {
            println!("{}: error at octet {}: {}", what, er.at, er.message);
            return;
        }
    };
    print!("{}: ethertype={:04x} kind={}", what, e.ethertype, kind(&e.payload));
    match &e.payload {
        BnfEthernetPayload::A1 { ip } => {
            print!(
                " ipv4 ihl={} len={} ttl={} proto={} src={:08x} dst={:08x} opts={}",
                ip.ihl, ip.total_length, ip.ttl, ip.protocol, ip.src, ip.dst, ip.options.len()
            );
            match &ip.payload {
                BnfIpv4Payload::A1 { t } => print!(
                    " tcp {}>{} seq={} syn={} data={}",
                    t.src_port, t.dst_port, t.seq_num, t.syn, t.payload.len()
                ),
                BnfIpv4Payload::A2 { u } => print!(
                    " udp {}>{} len={} data={}",
                    u.src_port, u.dst_port, u.length, u.payload.len()
                ),
                BnfIpv4Payload::A3 { rest } => print!(" data={}", rest.len()),
            }
        }
        BnfEthernetPayload::A2 { a } => {
            print!(" arp oper={} spa={:08x} tpa={:08x}", a.oper, a.spa, a.tpa)
        }
        BnfEthernetPayload::A3 { v6 } => print!(
            " ipv6 flow={:05x} next={} hop={} data={}",
            v6.flow_label, v6.next_header, v6.hop_limit, v6.payload.len()
        ),
        BnfEthernetPayload::A4 { rest } => print!(" raw={}", rest.len()),
    }
    println!();

    // and back: the bytes read are the bytes written
    match emit_bytes(&e) {
        Err(m) => println!("  emit: error: {}", m),
        Ok(out) if out == b => println!("  emit: {} octets, identical", out.len()),
        Ok(out) => println!("  emit: DIFFERENT ({} octets)", out.len()),
    }
}

fn bad_emit(what: &str, e: &BnfEthernet) {
    match emit_bytes(e) {
        Ok(out) => println!("{}: written ({} octets)", what, out.len()),
        Err(m) => println!("{}: {}", what, m),
    }
}

fn main() {
    let ip = eth(&[
        b"\x08\x00",
        b"\x46\x00\x00\x20\x12\x34\x40\x00\x40\x01\xab\xcd",
        b"\x0a\x00\x00\x01\x0a\x00\x00\x02",
        b"\x01\x01\x01\x00", // options (ihl 6)
        b"hi!!",
    ]);
    let tcp = eth(&[
        b"\x08\x00",
        b"\x45\x00\x00\x2c\x00\x01\x00\x00\x40\x06\x00\x00",
        b"\xc0\xa8\x00\x01\xc0\xa8\x00\x02",
        b"\x1f\x90\x00\x50\x00\x00\x00\x01\x00\x00\x00\x00\x50\x02\x20\x00",
        b"\x00\x00\x00\x00",
        b"ping",
    ]);
    let udp = eth(&[
        b"\x08\x00",
        b"\x45\x00\x00\x1f\x00\x02\x00\x00\x40\x11\x00\x00",
        b"\x0a\x00\x00\x01\x0a\x00\x00\x02",
        b"\x00\x35\x12\x34\x00\x0b\x00\x00",
        b"abc",
    ]);
    let arp = eth(&[
        b"\x08\x06",
        b"\x00\x01\x08\x00\x06\x04\x00\x01",
        b"\x00\x11\x22\x33\x44\x55\xc0\xa8\x00\x01",
        b"\x00\x00\x00\x00\x00\x00\xc0\xa8\x00\x02",
    ]);
    let v6 = eth(&[
        b"\x86\xdd",
        b"\x60\x01\x23\x45\x00\x04\x11\x40",
        b"\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01",
        b"\x20\x01\x0d\xb8\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02",
        b"abcd",
    ]);
    let other = eth(&[b"\x88\xcc\x01\x02"]); // LLDP: not listed
    show("ipv4", &ip);
    show("tcp", &tcp);
    show("udp", &udp);
    show("arp", &arp);
    show("ipv6", &v6);
    show("unlisted ethertype", &other);
    show("short", &ip[..10]);

    let e = parse_bytes(&tcp).unwrap();
    {
        let mut c = e.clone();
        if let BnfEthernetPayload::A1 { ip } = &mut c.payload {
            ip.ihl = 16;
        }
        bad_emit("ihl 16", &c);
    }
    {
        let mut c = e.clone();
        if let BnfEthernetPayload::A1 { ip } = &mut c.payload {
            ip.options = vec![0; 4];
        }
        bad_emit("options longer than ihl says", &c);
    }
    {
        let mut c = e.clone();
        let a = match parse_bytes(&arp).unwrap().payload {
            BnfEthernetPayload::A2 { a } => a,
            _ => unreachable!(),
        };
        c.payload = BnfEthernetPayload::A2 { a };
        bad_emit("arp payload for an ipv4 ethertype", &c);
    }
    {
        let mut c = e.clone();
        c.ethertype = 0x1234;
        bad_emit("ethertype not in the list", &c);
    }
}
