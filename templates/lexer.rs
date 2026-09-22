fn lx_digit(c: u8) -> bool { c.is_ascii_digit() }
fn lx_word_start(c: u8) -> bool { c.is_ascii_alphabetic() || c == b'_' || c == b'-' }
fn lx_word_char(c: u8) -> bool { lx_word_start(c) || lx_digit(c) || c == b'.' }

pub fn lex(text: &str) -> Vec<Token> {
    let b = text.as_bytes();
    let mut toks = Vec::new();
    let mut i = 0usize; let mut line = 1usize; let mut col = 1usize;
    while i < b.len() {
        let c = b[i];
        // Hand-written jet scanners (schema `{ }` blocks) win first.
        let (jl, jk) = jet_dispatch(b, i, b.len());
        if jl > 0 {
            toks.push(Token { kind: jk, text: text[i..i + jl].to_string(), line, col });
            i += jl; col += jl;
            continue;
        }
        if c == b' ' || c == b'\t' || c == b'\r' { i += 1; col += 1; }
        else if c == b'\n' { i += 1; line += 1; col = 1; }
        else if c == b'#' { while i < b.len() && b[i] != b'\n' { i += 1; } }
        else if c == b'"' {
            let sc = col; let mut s = String::new();
            i += 1; col += 1;
            while i < b.len() && b[i] != b'"' {
                if b[i] == b'\\' && i + 1 < b.len() { i += 1; col += 1; }
                s.push(b[i] as char); i += 1; col += 1;
            }
            if i < b.len() && b[i] == b'"' { i += 1; col += 1; }
            toks.push(Token { kind: Kind::Str, text: s, line, col: sc });
        }
        else if lx_digit(c) {
            let s = i; let sc = col;
            while i < b.len() && lx_digit(b[i]) { i += 1; col += 1; }
            if i < b.len() && lx_word_char(b[i]) {
                // dotted/alphanumeric run (1.2.3.4, 123abc) is one word
                i = s; col = sc;
                while i < b.len() && lx_word_char(b[i]) { i += 1; col += 1; }
                toks.push(Token { kind: Kind::Atom, text: text[s..i].to_string(), line, col: sc });
            } else {
                toks.push(Token { kind: Kind::Int, text: text[s..i].to_string(), line, col: sc });
            }
        }
        else if lx_word_start(c) {
            let s = i; let sc = col;
            while i < b.len() && lx_word_char(b[i]) { i += 1; col += 1; }
            toks.push(Token { kind: Kind::Atom, text: text[s..i].to_string(), line, col: sc });
        }
        else {
            toks.push(Token { kind: Kind::Punct, text: (c as char).to_string(), line, col });
            i += 1; col += 1;
        }
    }
    toks.push(Token { kind: Kind::Eof, text: String::new(), line, col });
    toks
}

pub fn parse_text(text: &str) -> Result<@ROOT_TYPE@, ParseError> {
    let toks = lex(text);
    let lines: Vec<&str> = text.split('\n').collect();
    parse_tokens(&toks, &lines)
}
