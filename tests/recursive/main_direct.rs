// tests/recursive.sh's second Rust driver: the same cycle, but through a
// DIRECT struct member (tests/abnf/recursive-direct.hbnf, `x = '(' x ')' | ..`)
// rather than an alias, which is the case visit_x and fold_x have to walk
// through the box.  Prints how many x nodes each walker saw.
mod recursive_direct;
use recursive_direct::*;

struct Count(u32);
impl Visitor for Count {
    fn visit_x(&mut self, _n: &X) {
        self.0 += 1;
    }
}
impl Folder for Count {
    fn fold_x(&mut self, n: X) -> X {
        self.0 += 1;
        n
    }
}

fn main() {
    let text = std::env::args().nth(1).unwrap_or_default();
    match parse_text(&text) {
        Ok(r) => {
            let mut v = Count(0);
            visit_x(&r, &mut v);
            let mut f = Count(0);
            let _ = fold_x(r, &mut f);
            println!("OK visited={} folded={}", v.0, f.0);
        }
        Err(e) => {
            println!("REJECT line {}: {}", e.line, e.msg);
            std::process::exit(1);
        }
    }
}
