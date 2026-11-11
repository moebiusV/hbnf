// tree-driver.rs: appended to the Rust parser generated from tree.hbnf (root `cond`).  Parses the two texts on the
// command line and says whether their trees are the same, different, or whether neither is a sentence.
fn dump(c: &Cond) -> String {
    format!("name={} num={} num_2={} rel={} rel_2={}", c.name, c.num, c.num_2, c.rel, c.rel_2)
}

fn one(t: &str) -> Option<String> {
    match parse_text(t) { Ok(v) => Some(dump(&v)), Err(_) => None }
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    if a.len() < 3 { std::process::exit(2); }
    let (x, y) = (one(&a[1]), one(&a[2]));
    match (x, y) {
        (None, None) => println!("error"),
        (Some(p), Some(q)) if p == q => println!("same"),
        (p, q) => println!("different: {} | {}", p.unwrap_or("error".into()), q.unwrap_or("error".into())),
    }
}
