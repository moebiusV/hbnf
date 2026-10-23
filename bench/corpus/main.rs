// main.rs -- time a generated Rust parser over a corpus's own good files (bench/stage-corpus.sh).  MODULE is
// filled in by the stage.  Every file is parsed REPS times and every tree is kept, so the memory is the
// trees'.  Prints ok BYTES COUNT SUM MS RSS_KIB, as the C driver does.
mod MODULE;
use MODULE::*;
use std::time::Instant;

fn rss_kib() -> u64 {
    let s = std::fs::read_to_string("/proc/self/status").unwrap_or_default();
    for l in s.lines() {
        if let Some(v) = l.strip_prefix("VmHWM:") {
            return v.trim().trim_end_matches("kB").trim().parse().unwrap_or(0);
        }
    }
    0
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 { std::process::exit(2); }
    let reps: usize = args[1].parse().unwrap_or(1);
    let texts: Vec<String> = args[2..].iter()
        .map(|p| String::from_utf8_lossy(&std::fs::read(p).unwrap()).into_owned()).collect();
    let total: usize = texts.iter().map(|t| t.len()).sum();
    let mut keep = Vec::with_capacity(reps * texts.len());
    let mut ok = 0usize;
    let t0 = Instant::now();
    for _ in 0..reps {
        for t in &texts {
            if let Ok(tree) = parse_text(t) { ok += 1; keep.push(tree); }
        }
    }
    let ms = t0.elapsed().as_secs_f64() * 1000.0;
    let all = ok == reps * texts.len();
    println!("{} {} {} 0 {:.2} {}", if all { "ok" } else { "FAIL" }, total * reps, ok, ms, rss_kib());
    std::process::exit(if all { 0 } else { 1 });
}
