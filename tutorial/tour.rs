// How a walker, a dump and a pretty-printer are made: plain functions over the typed tree.
// Nothing here is generated; it is what you would write.  (The parse is messy on purpose.)
mod shopping;
use shopping::*;

// Walk: one function per rule, children in the order the grammar has them.
fn walk_item(item: &Item, depth: usize) {
    let pad = |d: usize| "  ".repeat(d);
    println!("{}item", pad(depth));
    println!("{}qty {}", pad(depth + 1), item.qty);
    println!("{}name {}", pad(depth + 1), item.name);
    for from in &item.item_1 {
        println!("{}from", pad(depth + 1));
        println!("{}shop {}", pad(depth + 2), from.shop);
    }
}

fn walk_list(list: &List) {
    println!("list");
    for item in list {
        walk_item(item, 1);
    }
}

// Dump: the same recursion, but it writes an S-expression.
fn dump_list(list: &List) {
    print!("(list");
    for item in list {
        print!(" (item (qty {}) (name \"{}\")", item.qty, item.name);
        for from in &item.item_1 {
            print!(" (from (shop \"{}\"))", from.shop);
        }
        print!(")");
    }
    println!(")");
}

// Pretty-print: the text the grammar reads, in one canonical layout.
fn print_list(list: &List) {
    for item in list {
        print!("buy {} {}", item.qty, item.name);
        for from in &item.item_1 {
            print!(" from {}", from.shop);
        }
        println!(";");
    }
}

fn main() {
    let text = "buy  2   apples ;\n  buy 1\n milk from   corner-shop ;";
    let list = match parse_text(text) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("{}", e.msg);
            return;
        }
    };
    println!("== walk");
    walk_list(&list);
    println!("== dump");
    dump_list(&list);
    println!("== print");
    print_list(&list);
}
