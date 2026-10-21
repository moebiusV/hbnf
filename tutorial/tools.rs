// The walker and the dump the generator makes (--ast), the same in every language.
mod shopping;
use shopping::*;

struct Show { depth: usize }
impl Walker for Show {
    fn enter(&mut self, n: Node) -> Walk {
        println!("{}{}", "  ".repeat(self.depth), node_kind_name(n));
        self.depth += 1;
        Walk::Continue
    }
    fn leave(&mut self, _n: Node) -> Walk {
        self.depth -= 1;
        Walk::Continue
    }
}

fn main() {
    let text = "buy 2 apples;\nbuy 1 milk from corner-shop;\n";
    let list = parse_text(text).unwrap();
    walk_list(&list, &mut Show { depth: 0 });
    println!("{}", dump_list(&list));
}
