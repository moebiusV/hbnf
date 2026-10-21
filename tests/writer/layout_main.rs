// A pretty-printer's say in how the tree is written (Layout): a newline before every "buy" but the
// first, "from" in capitals, and a log of the rules entered.
mod shopping;
use shopping::*;

struct Pretty { buys: usize, log: Vec<String> }
impl Layout for Pretty {
    fn before(&mut self, s: &str) -> Option<String> {
        if s == "buy" {
            self.buys += 1;
            if self.buys > 1 { return Some("\n".to_string()); }
        }
        None
    }
    fn replace(&mut self, s: &str) -> Option<String> {
        if s == "from" { Some("FROM".to_string()) } else { None }
    }
    fn enter(&mut self, rule: &str) { self.log.push(rule.to_string()); }
}

fn main() {
    let list = parse_text("buy 2 apples;\nbuy 1 milk from corner-shop;\n").unwrap();
    let mut p = Pretty { buys: 0, log: Vec::new() };
    let out = write_list_with(&list, Some(&mut p)).unwrap();
    println!("{}", String::from_utf8_lossy(&out));
    println!("rules: {}", p.log.join(" "));
}
