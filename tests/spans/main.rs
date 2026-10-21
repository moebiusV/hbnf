// Spans and parents (--spans --parents) in Rust: where each node of tests/ast/ast.hbnf's tree is
// in the text, and which node holds it; the lines C prints (tests/spans/expected.txt).
mod ast;
use ast::*;

const TEXT: &str = "set a 1;\nrun b;\n{ set c \"x\"; }\n";

struct Show<'a> { parents: &'a Parents<'a> }
impl<'a> Walker for Show<'a> {
    fn enter(&mut self, n: Node) -> Walk {
        if let Some((s, e)) = node_span(n) {
            let (line, col) = node_where(TEXT, s);
            let up = match self.parents.parent(n) { Some(p) => node_kind_name(p), None => "-" };
            println!("{:<6} {:>2}..{:<2} {}:{} in {:<6} \"{}\"", node_kind_name(n), s, e, line, col, up, &TEXT[s..e]);
        }
        Walk::Continue
    }
}

fn main() {
    let tree = parse_text(TEXT).unwrap();
    let parents = link_config(&tree);
    walk_config(&tree, &mut Show { parents: &parents });
}
