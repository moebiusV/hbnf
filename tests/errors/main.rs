// Parse each file and print what the parser says (the files sit beside this one).
mod GRAMMAR;

fn show(name: &str, text: &str) {
    println!("== {}", name);
    match GRAMMAR::parse_text(text) {
        Ok(_) => println!("ok"),
        Err(e) => println!("{}", e.msg),
    }
}

fn main() {
    show("open.blk", include_str!("open.blk"));
    show("stray.blk", include_str!("stray.blk"));
}
