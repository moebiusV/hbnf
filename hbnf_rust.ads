pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_Rust: the Rust backend.  Given a parsed schema, emit a compilable
--  Rust module fragment: a type alias for every scalar/flag rule, an enum for
--  every literal-alternation rule, a struct for every struct rule, and a
--  `Vec<T>` alias for every list rule.  Schema comments are carried through
--  as `//` comments.
package HBNF_Rust is

   function Emit (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  A grammar with bit rules (HBNF_Wire.Rust.Emit_Hosted): Types, the structs
   --  of the bit rules, are added to the types and Code, their readers and
   --  writers, to the parser.  The text is then bytes (`parse_text` takes
   --  `&[u8]`): a bit rule reads any octet, and the text rules see it as text
   --  where they read.  A text rule calls a bit rule as it calls a text rule,
   --  parse_<rule> (p).
   procedure Set_Hosted (Types, Code : String; Walks : String := "");
   --  Walks: the bit rules that have a walk_<rule> (they hold an %action),
   --  space-separated; the text parser runs them after the whole text is read.

   --  The names the text backend gives a rule's type, its parser and its scanner.
   function Type_Name (Rule : String) return String;
   function Parse_Fn (Rule : String) return String;
   function Scan_Fn (Rule : String) return String;

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
