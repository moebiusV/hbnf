// The walk and the dump of tests/ast/ast.hbnf's tree in Rust: the same lines C's node_walk and
// node_dump print (the first three sections of tests/ast/expected.txt).
mod ast;
use ast::*;

struct Show { depth: usize, skip_blocks: bool }
impl Walker for Show {
    fn enter(&mut self, n: Node) -> Walk {
        let alt = node_alt(n);
        print!("{}{}", "  ".repeat(self.depth), node_kind_name(n));
        if alt != 0 { print!("[{}]", node_alt_name(n, alt)); }
        println!();
        if self.skip_blocks && node_kind_name(n) == "block" { return Walk::Skip; }
        self.depth += 1;
        Walk::Continue
    }
    fn leave(&mut self, _n: Node) -> Walk { self.depth -= 1; Walk::Continue }
}

fn main() {
    let text = "set a 1; run b; { set c \"x\"; set d e; }";
    let tree = parse_text(text).unwrap();
    println!("== all");
    walk_config(&tree, &mut Show { depth: 0, skip_blocks: false });
    println!("== blocks skipped");
    walk_config(&tree, &mut Show { depth: 0, skip_blocks: true });
    println!("== dump");
    println!("{}", dump_config(&tree));
    let other = parse_text("set a 2; run b; { set c \"x\"; set d e; }").unwrap();
    println!("== equal");
    println!("same text: {}", node_equal(Node::Config(&tree[0]), Node::Config(&parse_text(text).unwrap()[0])));
    println!("other text: {}", node_equal(Node::Config(&tree[0]), Node::Config(&other[0])));
}
