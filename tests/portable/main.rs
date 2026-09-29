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
        print!(" = {}{}; modes", acc, if c.loud.is_empty() { "" } else { " loudly" });
        for m in &c.modes {
            print!(" {}", if matches!(m.modeset.mode, Mode::Mode_Fast) { "fast" } else { "slow" });
        }
        print!("; pair");
        for p in &c.pair {
            print!(" {}", p);
        }
        print!("; words");
        for w in &c.words {
            print!(" {}", w);
        }
        // the optional, the repetition and the alternation inside the
        // sequence, each read into a rule of its own (config_1 .. 3)
        print!("; opts");
        if let Some(l) = c.config_1.first() {
            print!(" log {}", l.word);
        }
        for o in &c.config_2 {
            print!(" {}", o.word);
        }
        println!(" {}", if matches!(c.config_3, Config3::Config3_On) { "on" } else { "off" });
    }
}
