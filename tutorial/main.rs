// Read a shopping list with the parser hbnf made, and use the tree.
mod shopping;
use shopping::*;

struct Total(i64);
impl Visitor for Total {
    fn visit_item(&mut self, item: &Item) {
        self.0 += item.qty;
    }
}

fn main() {
    let text = "buy 2 apples;\nbuy 1 milk from corner-shop;\n";
    let list = match parse_text(text) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("{}", e.msg); // the message points at the text
            return;
        }
    };
    for item in &list {
        print!("{} x {}", item.qty, item.name);
        for from in &item.item_1 {
            print!(" (from {})", from.shop); // [ ... ] is 0 or 1
        }
        println!();
    }
    let mut total = Total(0);
    for item in &list {
        visit_item(item, &mut total); // parent before children
    }
    println!("total: {} items", total.0);
}
