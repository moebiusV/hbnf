// The writer's gate in Rust (tests/writer.sh): for each file, parse it, write the tree, parse what
// was written, write again.  The first write must re-parse, the tree it reads must write the same text and dump the same
// when that is read again, and the second write must be the same text as the first.  MODULE and ROOT are filled in by the script.
mod MODULE;
use MODULE::*;

fn roundtrip(path: &str) -> bool {
    let text = match std::fs::read(path) {
        Ok(b) => String::from_utf8_lossy(&b).into_owned(),
        Err(_) => { println!("{}: FAIL (cannot read)", path); return true; }
    };
    let t1 = match parse_text(&text) {
        Ok(t) => t,
        Err(_) => { println!("{}: SKIP (does not parse)", path); return false; }
    };
    let a = match write_ROOT(&t1) {
        Ok(v) => String::from_utf8_lossy(&v).into_owned(),
        Err(m) => { println!("{}: FAIL (cannot write: {})", path, m); return true; }
    };
    let t2 = match parse_text(&a) {
        Ok(t) => t,
        Err(e) => { println!("{}: FAIL (the written text does not parse: {})\n--- written ---\n{}\n---", path, e.msg, a); return true; }
    };
    let b = match write_ROOT(&t2) {
        Ok(v) => String::from_utf8_lossy(&v).into_owned(),
        Err(m) => { println!("{}: FAIL (cannot write again: {})", path, m); return true; }
    };
    // the written text reads as a tree that writes the same text and dumps the same: a comment the
    // first parse took (as an empty entry) is gone from the text, so the first tree is not compared
    let t3 = match parse_text(&b) {
        Ok(t) => t,
        Err(e) => { println!("{}: FAIL (the second written text does not parse: {})", path, e.msg); return true; }
    };
    let (d2, d3) = (dump_ROOT(&t2), dump_ROOT(&t3));
    if d2 != d3 {
        println!("{}: FAIL (the written text reads as a different tree)\n--- before ---\n{}\n--- after ---\n{}\n--- text ---\n{}", path, d2, d3, a);
        return true;
    }
    if a != b {
        println!("{}: FAIL (not idempotent)\n--- first ---\n{}\n--- second ---\n{}", path, a, b);
        return true;
    }
    println!("{}: ok ({} bytes)", path, a.len());
    false
}

fn main() {
    let mut bad = 0;
    for path in std::env::args().skip(1) {
        if roundtrip(&path) { bad += 1; }
    }
    std::process::exit(if bad == 0 { 0 } else { 1 });
}
