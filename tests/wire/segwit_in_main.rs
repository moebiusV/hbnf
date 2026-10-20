// The same vectors as segwit_main.c, inside "addr:" ... ";": `bitsof` in a grammar of
// text rules and bit rules together.  A mistake in the bits says at which word.
mod segwit_in;
use segwit_in::*;

const B0: &[u8] = &[0x03,0xa8,0xf3,0xb7,0x40,0xcc,0x8c,0xb6,0xa2,0xa4,0xa0,0xe2,0x2e,0x8d,0x9d,0x19,0x1f,0x8a,0x19,0xde,0xb3,0x0e,0x98,0xae,0xa0];
const B1: &[u8] = &[0x00,0xc3,0x18,0xa1,0xe0,0xa6,0x28,0xb3,0x40,0x25,0xe8,0xc9,0x01,0x9a,0xb6,0xd0,0x9b,0x64,0xc2,0xb3,0xc6,0x6a,0x69,0x3d,0x0d,0xc6,0x31,0x94,0xb0,0x24,0x81,0x93,0x10,0x3e,0x1f,0xa5,0xbc];
const B2: &[u8] = &[0x0b,0xcd,0xf3,0x33,0xf7,0xce,0xe5,0xdd,0x62,0xad,0x03,0x14,0xae,0x74,0x38,0x58,0x38,0x14,0xdf,0xe6,0xd9,0x6e,0x71,0x46,0xca,0xcf,0x94,0x0a,0xd8,0xb7,0xc0,0xbc,0xc0,0x0a,0xd4,0x94,0x9e];
const B3: &[u8] = &[0x83,0xa8,0xf0,0x21,0xa2,0x55,0x24];
const B4: &[u8] = &[0x13,0xa8,0xf3,0xb7,0x40,0xcc,0x8c,0xb6,0xa2,0xa4,0xa0,0xe2,0x2e,0x8d,0x9d,0x19,0x19,0xd3,0x18,0x38,0x80];
const B5: &[u8] = &[0x00,0x00,0x08,0x10,0x18,0x20,0x28,0x30,0x38,0x40,0x48,0x50,0x58,0x60,0x68,0x70,0x78,0x80,0x88,0x90,0x98,0xa0,0x00,0x00,0x00,0x00];
const B6: &[u8] = &[0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00];
const B7: &[u8] = &[0x08,0x08,0x00,0x00,0x00,0x00];
const B8: &[u8] = &[0x08,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00];
const B9: &[u8] = &[0x08,0x08,0x10,0x18,0x20,0x28,0x30,0x38,0x40,0x48,0x50,0x58,0x60,0x68,0x70,0x78,0x80,0x88,0x90,0x98,0xa0,0xaa,0x00,0x00,0x00,0x00];
const B10: &[u8] = &[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00];
const B11: &[u8] = &[0x08,0x08,0x10,0x18,0x20,0x28,0x30,0x38,0x40,0x48,0x50,0x58,0x60,0x68,0x70,0x78,0x80,0x88,0x90,0x98,0xa0,0xa8,0x00,0x00,0x00,0x00];

fn hex(p: &[u8]) -> String {
    p.iter().map(|b| format!("{:02x}", b)).collect()
}

// the first line of a message
fn first(s: &str) -> &str {
    s.lines().next().unwrap_or("")
}

// nbits of bytes, 5 at a time, as bech32 characters
fn symbols(b: &[u8], nbits: usize) -> String {
    let set = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    let mut out = String::new();
    for i in 0..nbits / 5 {
        let mut v = 0usize;
        for k in 0..5 {
            let bit = i * 5 + k;
            v = v * 2 + ((b[bit / 8] >> (7 - bit % 8)) & 1) as usize;
        }
        out.push(set[v] as char);
    }
    out
}

fn vector(name: &str, valid: bool, nbits: usize, b: &[u8], version: i64, program: &str, bad: &mut u32) {
    let text = format!("addr:{};", symbols(b, nbits));
    match parse_text(text.as_bytes()) {
        Ok(doc) => {
            if !valid {
                println!("FAIL accepted: {}", name);
                *bad += 1;
            } else if doc.segwit.version as i64 == version && hex(&doc.segwit.program) == program {
                println!("PASS {}: version {}, {} octets", name, doc.segwit.version, doc.segwit.program.len());
            } else {
                println!("FAIL {}: read as something else", name);
                *bad += 1;
            }
        }
        Err(e) => {
            if valid {
                println!("FAIL {}: {}", name, first(&e.msg));
                *bad += 1;
            } else {
                println!("PASS refused: {} ({})", name, first(&e.msg));
            }
        }
    }
}

fn text_case(i: usize, t: &str, bad: &mut u32) {
    let text = format!("addr:{};", t);
    match parse_text(text.as_bytes()) {
        Ok(doc) => match emit_bits_segwit(&doc.segwit) {
            Ok((back, nbits)) => {
                if nbits / 8 != t.len() || &back[..t.len()] != t.as_bytes() {
                    println!("FAIL text {}: written back as {}", i, String::from_utf8_lossy(&back));
                    *bad += 1;
                } else {
                    println!("PASS text {}: version {}, {} octets, written back", i, doc.segwit.version, doc.segwit.program.len());
                }
            }
            Err(m) => {
                println!("FAIL text {}: emit: {}", i, m);
                *bad += 1;
            }
        },
        Err(e) => {
            println!("FAIL text {}: {}", i, first(&e.msg));
            *bad += 1;
        }
    }
}

fn main() {
    let mut bad = 0u32;
    vector("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", true, 195, B0, 0, "751e76e8199196d454941c45d1b3a323f1433bd6", &mut bad);
    vector("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5", true, 295, B1, 0, "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262", &mut bad);
    vector("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5j", true, 295, B2, 1, "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", &mut bad);
    vector("BC1SW50QGDZ25J", true, 55, B3, 16, "751e", &mut bad);
    vector("bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs", true, 165, B4, 2, "751e76e8199196d454941c45d1b3a323", &mut bad);
    vector("v0 with a 21-octet program", false, 205, B5, -1, "", &mut bad);
    vector("version 17", false, 195, B6, -1, "", &mut bad);
    vector("a 1-octet program", false, 45, B7, -1, "", &mut bad);
    vector("a 41-octet program", false, 365, B8, -1, "", &mut bad);
    vector("padding that is not zero", false, 205, B9, -1, "", &mut bad);
    vector("v0 with a 19-octet program", false, 190, B10, -1, "", &mut bad);
    vector("v1 with a 21-octet program (2 padding bits)", true, 205, B11, 1, "0102030405060708090a0b0c0d0e0f101112131415", &mut bad);
    text_case(0, "qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", &mut bad);
    text_case(1, "qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7", &mut bad);
    text_case(2, "p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0", &mut bad);
    text_case(3, "sw50qgdz25j", &mut bad);
    text_case(4, "zw508d6qejxtdg4y5r3zarvaryvaxxpcs", &mut bad);
    match parse_text(b"addr:qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3tb;") {
        Ok(_) => println!("FAIL b is not a bech32 symbol"),
        Err(_) => println!("PASS refused: b is not a bech32 symbol"),
    }
    std::process::exit(if bad == 0 { 0 } else { 1 });
}
