// a driver for tests/emit/runs-rust.hbnf: the value, the depth of the stack and the sum of what is on it
mod l;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    match l::parse_text(&a[1]) {
        Ok(v) => unsafe {
            let mut sum = 0;
            for i in 0..l::DEPTH {
                sum += l::STACK[i];
            }
            println!("{} {} {}", v, l::DEPTH, sum);
        },
        Err(e) => println!("error {}:{}", e.line, e.col),
    }
}
