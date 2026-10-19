// A bit rule of a mixed grammar, written: %emit fills in len.
mod mixed6_rust;
use mixed6_rust::*;

fn main() {
    let mut f = Frame { len: 99, body: b"hello".to_vec(), tag: "ab".to_string() }; // %emit replaces len
    match emit_bits_frame(&f) {
        Ok((bytes, nbits)) => {
            print!("{} bits:", nbits);
            for b in &bytes[..(nbits + 7) / 8] {
                print!(" {:02x}", b);
            }
            println!();
        }
        Err(m) => println!("error: {}", m),
    }
    f.tag = String::new(); // a token is text; "" writes nothing
    if let Ok((_, nbits)) = emit_bits_frame(&f) {
        println!("count only: {} bits", nbits);
    }
}
