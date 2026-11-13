// a driver for tests/emit/run-rust.hbnf: the value of the list, or where the read stopped (`error line:column`)
mod l;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    match l::parse_text(&a[1]) {
        Ok(v) => println!("{}", v),
        Err(e) => println!("error {}:{}", e.line, e.col),
    }
}
