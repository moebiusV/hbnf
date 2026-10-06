// tests/recursive.sh's Rust driver: parse one expression from the command
// line and say whether it was accepted, as recursive_main.adb does.  The
// grammar is tests/abnf/recursive.hbnf, whose tree type contains itself, so
// this is the fixture that proves Rust breaks the cycle with a pointer
// rather than refusing.
mod recursive;
use recursive::*;

struct Walk;
impl Visitor for Walk {}
impl Folder for Walk {}

fn main() {
    let text = std::env::args().nth(1).unwrap_or_default();
    match parse_text(&text) {
        Ok(r) => {
            // The back-edge member is the only field that holds the subtree.
            let held = if r.expr.is_some() { "set" } else { "null" };
            // The walkers must at least compile and run over a boxed tree.
            let mut c = Walk;
            visit_prim(&r, &mut c);
            let _ = fold_prim(r, &mut c);
            println!("OK expr={}", held);
        }
        Err(e) => {
            println!("REJECT line {}: {}", e.line, e.msg);
            std::process::exit(1);
        }
    }
}
