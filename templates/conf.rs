// yyerror-style error handling: the parser calls config_error() at the point
// of failure with the caret message.  The default handler prints
// "file:line: msg" (file from CONF_FILE) and exit(1)s; override with
// set_config_error to take the message yourself, in which case parse_config
// returns the Err instead of exiting.
static CONFIG_ERROR: std::sync::OnceLock<fn(usize, &str)> = std::sync::OnceLock::new();
static CONF_FILE: std::sync::Mutex<String> = std::sync::Mutex::new(String::new());

fn default_config_error(line: usize, msg: &str) {
    let file = CONF_FILE.lock().unwrap();
    if !file.is_empty() {
        if line > 0 {
            eprintln!("{}:{}: {}", file, line, msg);
        } else {
            eprintln!("{}: {}", file, msg);
        }
    } else if line > 0 {
        eprintln!("{}: {}", line, msg);
    } else {
        eprintln!("{}", msg);
    }
    std::process::exit(1);
}

pub fn set_config_error(f: fn(usize, &str)) {
    let _ = CONFIG_ERROR.set(f);
}

fn config_error(line: usize, msg: &str) {
    CONFIG_ERROR.get().copied().unwrap_or(default_config_error)(line, msg);
}

pub fn parse_config(path: &str) -> Result<@ROOT_TYPE@, ParseError> {
    *CONF_FILE.lock().unwrap() = path.to_string();
    let text = match std::fs::read_to_string(path) {
        Ok(t) => t,
        Err(e) => {
            let m = format!("cannot open file: {}", e);
            config_error(0, &m);
            return Err(ParseError { line: 0, col: 0, msg: m });
        }
    };
    match parse_text(&text) {
        Ok(r) => Ok(r),
        Err(e) => {
            config_error(e.line, &e.msg);
            Err(e)
        }
    }
}
