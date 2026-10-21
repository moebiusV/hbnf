// Alternatives in a mixed grammar, written back: read the text, write the tree.
mod mixed8;
use mixed8::*;

fn main() {
    let ins: [&[u8]; 3] = [b"A:\x07\x03;", b"B:abc;", b"L:x\x01\x02yfoo,x\x03\x04;"];
    for (i, text) in ins.iter().enumerate() {
        let out = match parse_text(text) {
            Ok(o) => o,
            Err(e) => {
                println!("read {}: {}", i, e.msg);
                continue;
            }
        };
        match write_doc(&out) {
            Ok(bytes) => println!("write {}: ok {} bytes, same as read: {}", i, bytes.len(),
                                  if &bytes[..] == *text { "yes" } else { "no" }),
            Err(m) => println!("write {}: {}", i, m),
        }
    }
}
