// A bit rule that holds a text token.
mod mixed2;
use mixed2::*;

fn show(what: &str, text: &[u8]) {
    match parse_text(text) {
        Ok(out) => {
            println!("{}: kind={} label={}", what, out.record.kind, out.record.label);
        }
        Err(e) => println!("{}: error\n{}", what, e.msg),
    }
}

fn main() {
    show("abc", b"REC:\x07abc");
    show("a letter as the kind", b"REC:abc");
    show("no label", b"REC:\x07");
    show("digits", b"REC:\x07123");
}
