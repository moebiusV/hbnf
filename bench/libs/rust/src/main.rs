// serde_json and toml, parsing into their own value types.  Prints "ok BYTES MS RSS_KIB".
use std::time::Instant;

fn rss_kib() -> u64 {
    std::fs::read_to_string("/proc/self/status").ok()
        .and_then(|s| s.lines().find(|l| l.starts_with("VmHWM:")).map(|l| l.to_string()))
        .and_then(|l| l.split_whitespace().nth(1).and_then(|n| n.parse().ok()))
        .unwrap_or(0)
}

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let text = std::fs::read_to_string(&a[2]).expect("read");
    let t0 = Instant::now();
    let ok = match a[1].as_str() {
        "serde_json" => serde_json::from_str::<serde_json::Value>(&text).map(|_| ()).map_err(|e| e.to_string()),
        "toml" => toml::from_str::<toml::Table>(&text).map(|_| ()).map_err(|e| e.to_string()),
        _ => std::process::exit(2),
    };
    let ms = t0.elapsed().as_secs_f64() * 1000.0;
    match ok {
        Ok(()) => println!("ok {} {:.2} {}", text.len(), ms, rss_kib()),
        Err(e) => { eprintln!("{}", e); println!("FAIL {} {:.2} {}", text.len(), ms, rss_kib()); std::process::exit(1); }
    }
}
