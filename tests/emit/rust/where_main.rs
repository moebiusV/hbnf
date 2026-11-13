// a driver for tests/emit/where-rust.hbnf: whether the text is read, and what %bind { } added up
mod l;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let ok = l::parse_text(&a[1]).is_ok();
    println!("{} {}", ok, unsafe { l::BOUND });
}
