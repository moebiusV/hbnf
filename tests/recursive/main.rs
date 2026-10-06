// tests/recursive.sh's Rust driver: parse one expression from the command
// line and say whether it was accepted, as recursive_main.adb does.  The
// grammar is tests/abnf/recursive.hbnf, whose tree type contains itself, so
// this is the fixture that proves Rust breaks the cycle with a pointer
// rather than refusing.
//
// With a second argument it prints how many prim nodes each walker reached
// instead.  The cycle runs through `expr`, a scalar alias, so this is the
// case where a walker has to follow the box by the edge's target rather than
// by the member's own kind.
mod recursive;
use recursive::*;

struct Count(u32);
impl Visitor for Count {
    fn visit_prim(&mut self, _n: &Prim) {
        self.0 += 1;
    }
}
impl Folder for Count {
    fn fold_prim(&mut self, n: Prim) -> Prim {
        self.0 += 1;
        n
    }
}

fn main() {
    let text = std::env::args().nth(1).unwrap_or_default();
    let walk = std::env::args().nth(2).is_some();
    match parse_text(&text) {
        Ok(r) => {
            // The back-edge member is the only field that holds the subtree.
            let held = if r.expr.is_some() { "set" } else { "null" };
            let mut v = Count(0);
            visit_prim(&r, &mut v);
            let mut f = Count(0);
            let _ = fold_prim(r, &mut f);
            if walk {
                println!("OK visited={} folded={}", v.0, f.0);
            } else {
                println!("OK expr={}", held);
            }
        }
        Err(e) => {
            println!("REJECT line {}: {}", e.line, e.msg);
            std::process::exit(1);
        }
    }
}
