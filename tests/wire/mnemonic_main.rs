// BIP-39 mnemonics through the Rust interface: the same entropy, phrases and
// checksums as mnemonic_main.c.  The grammar's code is Rust (mnemonic_rust.hbnf).
mod mnemonic_rust;
use mnemonic_rust::*;

const E0: &[u8] = &[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00];
const E1: &[u8] = &[0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f];
const E2: &[u8] = &[0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80];
const E3: &[u8] = &[0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff];
const E4: &[u8] = &[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00];
const E5: &[u8] = &[0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff];
const E6: &[u8] = &[0x0c,0x1e,0x24,0xe5,0x91,0x77,0x79,0xd2,0x97,0xe1,0x4d,0x45,0xf1,0x4e,0x1a,0x1a];
const E7: &[u8] = &[0x9e,0x88,0x5d,0x95,0x2a,0xd3,0x62,0xca,0xeb,0x4e,0xfe,0x34,0xa8,0xe9,0x1b,0xd2];
const E8: &[u8] = &[0x06,0x6d,0xca,0x1a,0x2b,0xb7,0xe8,0xa1,0xdb,0x28,0x32,0x14,0x8c,0xe9,0x93,0x3e,0xea,0x0f,0x3a,0xc9,0x54,0x8d,0x79,0x31,0x12,0xd9,0xa9,0x5c,0x94,0x07,0xef,0xad];
const E9: &[u8] = &[0xf5,0x85,0xc1,0x1a,0xec,0x52,0x0d,0xb5,0x7d,0xd3,0x53,0xc6,0x95,0x54,0xb2,0x1a,0x89,0xb2,0x0f,0xb0,0x65,0x09,0x66,0xfa,0x0a,0x9d,0x6f,0x74,0xfd,0x98,0x9d,0x8f];
const E10: &[u8] = &[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00];
const E11: &[u8] = &[0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f,0x7f];
const E12: &[u8] = &[0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80,0x80];
const E13: &[u8] = &[0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff];
const E14: &[u8] = &[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00];
const E15: &[u8] = &[0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff];
const E16: &[u8] = &[0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00];
const E17: &[u8] = &[0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff];

struct Vec_ {
    phrase: &'static str,
    n: usize,
    entropy: &'static [u8],
    cs: u64,
}

const VECS: &[Vec_] = &[
    Vec_ { phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", n: 16, entropy: E0, cs: 3 },
    Vec_ { phrase: "legal winner thank year wave sausage worth useful legal winner thank yellow", n: 16, entropy: E1, cs: 8 },
    Vec_ { phrase: "letter advice cage absurd amount doctor acoustic avoid letter advice cage above", n: 16, entropy: E2, cs: 4 },
    Vec_ { phrase: "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong", n: 16, entropy: E3, cs: 5 },
    Vec_ { phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art", n: 32, entropy: E4, cs: 102 },
    Vec_ { phrase: "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote", n: 32, entropy: E5, cs: 175 },
    Vec_ { phrase: "army van defense carry jealous true garbage claim echo media make crunch", n: 16, entropy: E6, cs: 7 },
    Vec_ { phrase: "ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic", n: 16, entropy: E7, cs: 1 },
    Vec_ { phrase: "all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform", n: 32, entropy: E8, cs: 162 },
    Vec_ { phrase: "void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold", n: 32, entropy: E9, cs: 105 },
    Vec_ { phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent", n: 24, entropy: E10, cs: 39 },
    Vec_ { phrase: "legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal will", n: 24, entropy: E11, cs: 25 },
    Vec_ { phrase: "letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter always", n: 24, entropy: E12, cs: 60 },
    Vec_ { phrase: "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when", n: 24, entropy: E13, cs: 17 },
    Vec_ { phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon address", n: 20, entropy: E14, cs: 27 },
    Vec_ { phrase: "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrist", n: 20, entropy: E15, cs: 19 },
    Vec_ { phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon admit", n: 28, entropy: E16, cs: 29 },
    Vec_ { phrase: "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo veteran", n: 28, entropy: E17, cs: 25 },
];

fn main() {
    let mut bad = 0;
    for v in VECS {
        let words = (v.n * 8 + v.n * 8 / 32) / 11;
        let want_warn = v.n != 16 && v.n != 32;
        let out = match parse_text(v.phrase) {
            Ok(o) => o,
            Err(e) => {
                println!("FAIL {} words: {}", words, e.message);
                bad += 1;
                continue;
            }
        };
        let warns = hbnf_warnings();
        if out.entropy != v.entropy || out.checksum != v.cs {
            println!("FAIL {} words: entropy or checksum differs", words);
            bad += 1;
        } else if warns.len() != want_warn as usize {
            println!("FAIL {} words: {} warning(s)", words, warns.len());
            bad += 1;
        } else {
            match emit_text(&out) {
                Err(m) => {
                    println!("FAIL {} words: emit: {}", words, m);
                    bad += 1;
                }
                Ok(back) if back != v.phrase => {
                    println!("FAIL {} words: written back as {}", words, back);
                    bad += 1;
                }
                Ok(_) => println!(
                    "PASS {} words, entropy {} octets, checksum {}{}{}, written back",
                    words,
                    v.n,
                    v.cs,
                    if warns.is_empty() { "" } else { ", warning: " },
                    warns.first().map(|s| s.as_str()).unwrap_or("")
                ),
            }
        }
    }
    let no: &[(&str, &str)] = &[
        ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon", "11 words"),
        ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandonn", "a misspelt word"),
        ("abandon  abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", "two blanks"),
        ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about ", "a trailing blank"),
        ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon", "a wrong checksum (all abandon)"),
        ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo", "a wrong checksum (all zoo)"),
        ("", "nothing"),
    ];
    for (text, why) in no {
        match parse_text(text) {
            Ok(_) => {
                println!("FAIL accepted: {}", why);
                bad += 1;
            }
            Err(e) => println!("PASS refused: {} ({})", why, e.message),
        }
    }
    // writing: only the entropy is set, and %emit works out the checksum
    for v in VECS {
        let t = Mnemonic { entropy: v.entropy.to_vec(), checksum: 0x55 }; // wrong on purpose
        match emit_text(&t) {
            Err(m) => {
                println!("FAIL generate: {}", m);
                bad += 1;
            }
            Ok(back) if back != v.phrase => {
                println!("FAIL generate: {}", back);
                bad += 1;
            }
            Ok(_) => println!("PASS generated {} words from {} octets of entropy", (v.n * 8 + v.n * 8 / 32) / 11, v.n),
        }
    }
    if bad != 0 {
        std::process::exit(1);
    }
}
