// a driver for the emit tests whose answer is the calls the emits made, in order (`error` when the read fails)
mod l;
fn main() {
    let a: Vec<String> = std::env::args().collect();
    match l::parse_text(&a[1]) {
        Ok(_) => unsafe { println!("{}", (*std::ptr::addr_of!(l::TRACE)).as_str()) },
        Err(_) => println!("error"),
    }
}
