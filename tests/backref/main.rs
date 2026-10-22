// Back-references in Rust: a closing tag repeats the opening one (tests/backref/tags.hbnf); the lines
// tests/backref/expected.txt has for C.
mod tags;
use tags::*;

fn main() {
    let cases = ["<a></a>", "<a>text</a>", "<a><b></b></a>", "<a><a></a></a>", "<a></a><b></b>",
                 "x<a>y<b>z</b>w</a>v", "<a></b>", "<a><b></a></b>", "<ab></a>", "<a></ab>", "<a>", "</a>"];
    for t in cases {
        match parse_text(t) {
            Ok(_) => println!("{:<26} accepted", t),
            Err(e) => println!("{:<26} {}", t, e.msg.lines().next().unwrap_or("")),
        }
    }
}
