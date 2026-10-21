// A mixed grammar written back: read the text, write the tree.
mod mixed;
use mixed::*;

fn main() {
    let ins: [&[u8]; 2] = [b"PKT:\x05hello;", b"PKT:\x01z;"];
    let want = [11usize, 7];
    for (i, text) in ins.iter().enumerate() {
        let out = match parse_text(text) {
            Ok(o) => o,
            Err(e) => {
                println!("read {}: {}", i, e.msg);
                continue;
            }
        };
        match write_msg(&out) {
            Ok(bytes) => println!("write {}: ok {} bytes, same as read: {}", i, bytes.len(),
                                  if bytes.len() == want[i] && &bytes[..] == *text { "yes" } else { "no" }),
            Err(m) => println!("write {}: {}", i, m),
        }
    }
}
