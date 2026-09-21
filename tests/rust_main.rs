mod server;
use server::*;

fn main() {
    let valid = "\"example.com\"\non wg0 port 443\n\"/var/www\"\n\"www\"\nyes\n";
    let bad = "\"example.com\"\non wg0 port oops\n\"/var/www\"\n\"www\"\nyes\n";

    match parse_text(valid) {
        Ok(s) => println!("valid: OK name={} port={}", s.name, s.listen.port),
        Err(e) => println!("valid: ERR {}", e.msg),
    }
    match parse_text(bad) {
        Ok(_) => println!("malformed: OK"),
        Err(e) => println!("malformed: line {}: {}", e.line, e.msg),
    }
}
