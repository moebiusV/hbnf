pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_Rust: the Rust backend.  Given a parsed schema, emit a compilable
--  Rust module fragment: a type alias for every scalar/flag rule, an enum for
--  every literal-alternation rule, a struct for every struct rule, and a
--  `Vec<T>` alias for every list rule.  Schema comments are carried through
--  as `//` comments.
package HBNF_Rust is

   function Emit (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  Emit the parser half: a recursive-descent parser (a token type plus one
   --  `parse_<rule>()` function per rule) that consumes a token slice and
   --  builds the types `Emit` declares.  On failure it records the deepest
   --  `fail` into the ParseError; the conf wrapper reports it via config_error.
   function Emit_Parser
     (Rules : HBNF_Grammar.Rule_Vectors.Vector)
      return String;

   --  Emit the lexer half: a schema-independent scanner turning text into the
   --  token slice `Emit_Parser` consumes (skipping whitespace and `#` comments),
   --  plus a `parse_text` convenience that lexes, splits lines and parses.
   function Emit_Lexer (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  Emit the OpenBSD conf.h/conf.c-shape wrapper: a `parse_config(path)` that
   --  reads a file and populates a config, plus the overridable `config_error`
   --  handler (default prints + exit(1)).  Appended after Emit_Lexer.
   function Emit_Conf (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

end HBNF_Rust;
