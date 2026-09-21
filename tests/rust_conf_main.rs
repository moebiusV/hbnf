mod server;
use server::*;

fn my_error(line: usize, msg: &str) {
    println!("callback: line={} msg=\n{}", line, msg);
}

fn main() {
    match parse_config("valid.conf") {
        Ok(s) => println!("valid: OK name={} port={}", s.name, s.listen.port),
        Err(e) => println!("valid: ERR {}", e.msg),
    }
    set_config_error(my_error);
    match parse_config("bad.conf") {
        Ok(_) => println!("bad: unexpectedly OK"),
        Err(e) => println!("bad: handled by callback (returned Err, line {})", e.line),
    }
}
