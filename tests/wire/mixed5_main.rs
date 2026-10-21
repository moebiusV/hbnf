// %action on a bit rule inside a text grammar: failure and warnings.
mod mixed5_rust;
use mixed5_rust::*;

fn show(what: &str, text: &[u8]) {
    match parse_text(text) {
        Ok(out) => println!("{}: kind={} len={}", what, out.rec.kind, out.rec.len),
        Err(e) => println!("{}: error\n{}", what, e.msg),
    }
    for w in hbnf_warnings() {
        println!("  warning: {}", w);
    }
}

fn main() {
    show("plain", b"REC:\x07\x03;");
    show("long", b"REC:\x07\x20;");
    show("reserved", b"REC:\xff\x01;");
}
