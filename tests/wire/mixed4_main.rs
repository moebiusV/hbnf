// A text element, bit fields and text again, in one rule.
mod mixed4;
use mixed4::*;

fn show(what: &str, text: &[u8]) {
    match parse_text(text) {
        Ok(out) => {
            println!("{}: len={} payload={}", what, out.req_2.len, String::from_utf8_lossy(&out.req_2.payload));
        }
        Err(e) => println!("{}: error\n{}", what, e.msg),
    }
}

fn main() {
    show("hello", b"GET \x05hello\r\n");
    show("one", b"GET \x01z\r\n");
    show("short", b"GET \x09hello\r\n");
    show("no line end", b"GET \x05hello");
    show("no verb", b"PUT \x05hello\r\n");
}
