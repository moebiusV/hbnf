mod server;
use server::*;

fn t(kind: Kind, text: &str, line: usize, col: usize) -> Token {
    Token { kind, text: text.to_string(), line, col }
}

fn main() {
    let lines = ["example.com", "on wg0 port oops", "/var/www", "www", "yes"];

    let valid = vec![
        t(Kind::Str, "example.com", 1, 1),
        t(Kind::Atom, "on", 2, 1),
        t(Kind::Atom, "wg0", 2, 4),
        t(Kind::Atom, "port", 2, 8),
        t(Kind::Int, "443", 2, 13),
        t(Kind::Str, "/var/www", 3, 1),
        t(Kind::Str, "www", 4, 1),
        t(Kind::Atom, "yes", 5, 1),
        t(Kind::Eof, "", 5, 1),
    ];
    match parse_config(&valid, &lines) {
        Ok(s) => println!("valid: OK name={} port={}", s.name, s.listen.port),
        Err(e) => println!("valid: ERR {}", e.msg),
    }

    let bad = vec![
        t(Kind::Str, "example.com", 1, 1),
        t(Kind::Atom, "on", 2, 1),
        t(Kind::Atom, "wg0", 2, 4),
        t(Kind::Atom, "port", 2, 8),
        t(Kind::Atom, "oops", 2, 13),
        t(Kind::Eof, "", 5, 1),
    ];
    match parse_config(&bad, &lines) {
        Ok(_) => println!("malformed: OK"),
        Err(e) => println!("malformed: line {}: {}", e.line, e.msg),
    }
}
