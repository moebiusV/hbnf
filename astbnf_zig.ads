pragma Ada_2022;

with ASTBNF;

--  ASTBNF_Zig: the Zig backend.  Given a parsed schema, emit a compilable
--  Zig fragment: a type alias for every scalar/flag rule, an enum for every
--  literal-alternation rule, a struct for every struct rule, and a `[]T`
--  slice alias for every list rule.  Schema comments are carried through as
--  `//` comments.
package ASTBNF_Zig is

   function Emit (Rules : ASTBNF.Rule_Vectors.Vector) return String;

   --  Emit the parser half: a recursive-descent parser (a token type plus one
   --  `parse_<rule>()` function per rule) that consumes a token slice and
   --  builds the types `Emit` declares.  When Conf is true, the parser's
   --  `set_err` reports to the global `config_error` handler at the point of
   --  error (yyerror-style) instead of only filling the err buffer.
   function Emit_Parser
     (Rules : ASTBNF.Rule_Vectors.Vector; Conf : Boolean := False)
      return String;

   --  Emit the lexer half: a schema-independent scanner turning text into the
   --  token slice `Emit_Parser` consumes (skipping whitespace and `#` comments),
   --  plus a `parseText` convenience that lexes, splits lines and parses.
   function Emit_Lexer (Rules : ASTBNF.Rule_Vectors.Vector) return String;

   --  Emit the OpenBSD conf.h/conf.c-shape wrapper: a `parse_config(path)` that
   --  reads a file and populates a config, plus the overridable `config_error`
   --  handler (default prints + exit(1)).  Appended after Emit_Lexer.
   function Emit_Conf (Rules : ASTBNF.Rule_Vectors.Vector) return String;

end ASTBNF_Zig;
