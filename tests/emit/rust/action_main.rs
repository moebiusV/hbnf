// a driver for tests/emit/action-rust.hbnf: whether the text is read, the line and message of the error, and how many actions ran
mod l;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let t = a[1].replace("\\n", "\n");
    match l::parse_text(&t) {
        Ok(_) => println!("ok {}", unsafe { l::SEEN }),
        Err(e) => println!("error {} {} {}", e.line, e.msg, unsafe { l::SEEN }),
    }
}
