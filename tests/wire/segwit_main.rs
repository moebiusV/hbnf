// BIP-173 and BIP-350 segwit data parts through the Rust interface: the same
// vectors as segwit_main.c, the same output.  The text is the bech32 symbols.
mod segwit;
use segwit::*;

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

struct Vec_ {
    name: &'static str,
    valid: bool,
    nbits: usize,
    bytes: &'static [u8],
    version: i32,
    program: &'static str,
}

const VECS: &[Vec_] = &[
    Vec_ { name: "bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", valid: true, nbits: 195, bytes: B0, version: 0, program: "751e76e8199196d454941c45d1b3a323f1433bd6" },
    Vec_ { name: "tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5", valid: true, nbits: 295, bytes: B1, version: 0, program: "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262" },
    Vec_ { name: "bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5j", valid: true, nbits: 295, bytes: B2, version: 1, program: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" },
    Vec_ { name: "BC1SW50QGDZ25J", valid: true, nbits: 55, bytes: B3, version: 16, program: "751e" },
    Vec_ { name: "bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs", valid: true, nbits: 165, bytes: B4, version: 2, program: "751e76e8199196d454941c45d1b3a323" },
    Vec_ { name: "v0 with a 21-octet program", valid: false, nbits: 205, bytes: B5, version: -1, program: "" },
    Vec_ { name: "version 17", valid: false, nbits: 195, bytes: B6, version: -1, program: "" },
    Vec_ { name: "a 1-octet program", valid: false, nbits: 45, bytes: B7, version: -1, program: "" },
    Vec_ { name: "a 41-octet program", valid: false, nbits: 365, bytes: B8, version: -1, program: "" },
    Vec_ { name: "padding that is not zero", valid: false, nbits: 205, bytes: B9, version: -1, program: "" },
    Vec_ { name: "v0 with a 19-octet program", valid: false, nbits: 190, bytes: B10, version: -1, program: "" },
    Vec_ { name: "v1 with a 21-octet program (2 padding bits)", valid: true, nbits: 205, bytes: B11, version: 1, program: "0102030405060708090a0b0c0d0e0f101112131415" },
];

fn hex(p: &[u8]) -> String {
    p.iter().map(|b| format!("{:02x}", b)).collect()
}

// nbits of bytes, 5 at a time, as bech32 characters
fn symbols(b: &[u8], nbits: usize) -> String {
    let set = b"qpzry9x8gf2tvdw0s3jn54khce6mua7l";
    let mut out = String::new();
    for i in 0..nbits / 5 {
        let mut v = 0usize;
        for k in 0..5 {
            let bit = i * 5 + k;
            v = (v << 1) | ((b[bit >> 3] >> (7 - (bit & 7))) & 1) as usize;
        }
        out.push(set[v] as char);
    }
    out
}

fn main() {
    let mut bad = 0;
    for v in VECS {
        let text = symbols(v.bytes, v.nbits);
        match parse_text(&text) {
            Ok(out) if v.valid => {
                if out.version as i32 == v.version && hex(&out.program) == v.program {
                    println!("PASS {}: version {}, {} octets", v.name, out.version, out.program.len());
                } else {
                    println!("FAIL {}: read as something else", v.name);
                    bad += 1;
                }
            }
            Ok(_) => {
                println!("FAIL accepted: {}", v.name);
                bad += 1;
            }
            Err(e) if v.valid => {
                println!("FAIL {}: {}", v.name, e.message);
                bad += 1;
            }
            Err(e) => println!("PASS refused: {} ({})", v.name, e.message),
        }
    }
    // the data parts of real addresses, read and written back as text
    let texts = [
        "qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4",
        "qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7",
        "p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0",
        "sw50qgdz25j",
        "zw508d6qejxtdg4y5r3zarvaryvaxxpcs",
    ];
    for (i, t) in texts.iter().enumerate() {
        match parse_text(t) {
            Err(e) => {
                println!("FAIL text {}: {}", i, e.message);
                bad += 1;
            }
            Ok(out) => match emit_text(&out) {
                Err(m) => {
                    println!("FAIL text {}: emit: {}", i, m);
                    bad += 1;
                }
                Ok(back) if back != *t => {
                    println!("FAIL text {}: written back as {}", i, back);
                    bad += 1;
                }
                Ok(_) => println!("PASS text {}: version {}, {} octets, written back", i, out.version, out.program.len()),
            },
        }
    }
    println!(
        "{}",
        if parse_text("qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3tb").is_ok() {
            "FAIL b is not a bech32 symbol"
        } else {
            "PASS refused: b is not a bech32 symbol"
        }
    );
    if bad != 0 {
        std::process::exit(1);
    }
}
