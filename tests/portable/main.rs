// tests/portable.sh's Rust driver: parse each file and print what it holds,
// as main.c, main.zig and portable_main.adb do.
mod portable;
use portable::*;

fn main() {
    for path in std::env::args().skip(1) {
        let text = std::fs::read_to_string(&path).expect("read");
        let c = match parse_text(&text) {
            Ok(c) => c,
            Err(e) => {
                println!("{}: rejected at line {}", path, e.line);
                continue;
            }
        };
        print!("{}: hosts", path);
        for h in &c.host_list {
            print!(" {}", h.host);
        }
        print!("; calc");
        let mut acc = 0;
        for (k, s) in c.sum.iter().enumerate() {
            if k == 0 {
                // the base
                acc = s.int;
                print!(" {}", s.int);
            } else {
                let plus = matches!(s.op, Op::Op_Op1);
                acc += if plus { s.int } else { -s.int };
                print!(" {} {}", if plus { "+" } else { "-" }, s.int);
            }
        }
        print!(" = {}; modes", acc);
        for m in &c.modes {
            print!(" {}", if matches!(m.modeset.mode, Mode::Mode_Fast) { "fast" } else { "slow" });
        }
        print!("; pair");
        for p in &c.pair {
            print!(" {}", p);
        }
        println!();
    }
}
