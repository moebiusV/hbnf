// tests/schema.sh's Rust driver: read each file named on the command line
// and say whether hbnf_schema.hbnf's generated parser accepts it.
mod schema;

fn main() {
    for path in std::env::args().skip(1) {
        let text = std::fs::read_to_string(&path).expect("read");
        match schema::parse_text(&text) {
            Ok(_) => println!("{}: OK", path),
            Err(_) => println!("{}: REJECT", path),
        }
    }
}
