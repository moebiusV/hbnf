// Text after a 3-bit field: read at bit 3, shifted.
mod mixed3;
use mixed3::*;

fn show(what: &str, text: &[u8]) {
    match parse_text(text) {
        Ok(out) => {
            println!("{}: flag={} label={} pad={}", what, out.record.flag, out.record.label, out.record.pad);
        }
        Err(e) => println!("{}: error\n{}", what, e.msg),
    }
}

fn main() {
    // flag 101, "abc", pad 00000: 10101100 00101100 01001100 01100000
    show("abc", b"REC:\xac\x2c\x4c\x60");
    // flag 000, "Z" = 0x5a: 00001011 01000000
    show("Z", b"REC:\x0b\x40");
}
