// A text rule that names a bit rule: both read from one parser.
mod mixed;
use mixed::*;

fn show(what: &str, text: &[u8]) {
    match parse_text(text) {
        Ok(out) => {
            println!("{}: len={} body={}", what, out.frame.len, String::from_utf8_lossy(&out.frame.body));
        }
        Err(e) => println!("{}: error\n{}", what, e.msg),
    }
}

fn main() {
    show("hello", b"PKT:\x05hello;");
    show("one", b"PKT:\x01z;");
    show("short", b"PKT:\x09hello;");
    show("no semicolon", b"PKT:\x05hello");
    show("no tag", b"\x05hello;");
}
