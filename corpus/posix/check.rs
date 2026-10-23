// check.rs -- for the POSIX shell grammar in Rust: read each file named on the command line and
// say whether the generated parser accepts it ("ok FILE" or "bad FILE: MESSAGE").  MODULE is filled in
// by tests/posix.sh.
mod MODULE;
use MODULE::*;

fn main() {
    let mut bad = false;
    for path in std::env::args().skip(1) {
        let text = String::from_utf8_lossy(&std::fs::read(&path).unwrap_or_default()).into_owned();
        match parse_text(&text) {
            Ok(_) => println!("ok {}", path),
            Err(e) => { println!("bad {}: {}", path, e.msg.lines().next().unwrap_or("")); bad = true; }
        }
    }
    std::process::exit(if bad { 1 } else { 0 });
}
