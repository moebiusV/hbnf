pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_Zig: the Zig backend.  Given a parsed schema, emit a compilable
--  Zig fragment: a type alias for every scalar/flag rule, an enum for every
--  literal-alternation rule, a struct for every struct rule, and a `[]T`
--  slice alias for every list rule.  Schema comments are carried through as
--  `//` comments.
package HBNF_Zig is

   function Emit (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  A grammar with bit rules (HBNF_Wire.Zig.Emit_Hosted): Types, the structs
   --  of the bit rules, are added to the types, and Code, their readers and
   --  writers, to the parser, which then has a bit offset in its octet.  The
   --  text rules call a bit rule as they call a text rule, parse_<rule> (p).
   procedure Set_Hosted (Types, Code : String; Walks : String := "");
   --  Walks: the bit rules that have a walk_<rule> (they hold an %action),
   --  space-separated; the text parser runs them after the whole text is read.

   --  The name of the scanner a character rule is compiled to (scan_<rule>),
   --  which a bit rule that names the rule calls.
   function Scan_Fn (Rule : String) return String;

   --  parse_<rule>, the function a text rule calls to read a rule; a bit rule
   --  gets one of that name from the hosted code.
   function Parse_Fn (Rule : String) return String;

   --  Emit the parser half: a recursive-descent parser (a token type plus one
   --  `parse_<rule>()` function per rule) that consumes a token slice and
   --  builds the types `Emit` declares.  On failure it records the deepest
   --  `set_err` into the err buffer; the conf wrapper reports it via config_error.
   function Emit_Parser
     (Rules : HBNF_Grammar.Rule_Vectors.Vector)
      return String;

   --  Emit the lexer half: a schema-independent scanner turning text into the
   --  token slice `Emit_Parser` consumes (skipping whitespace and `#` comments),
   --  plus a `parseText` convenience that lexes, splits lines and parses.
   function Emit_Lexer (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  Emit the OpenBSD conf.h/conf.c-shape wrapper: a `parse_config(path)` that
   --  reads a file and populates a config, plus the overridable `config_error`
   --  handler (default prints + exit(1)).  Appended after Emit_Lexer.
   function Emit_Conf (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

end HBNF_Zig;
