pragma Ada_2022;

with ASTBNF;

--  ASTBNF_Rust: the Rust backend.  Given a parsed schema, emit a compilable
--  Rust module fragment: a type alias for every scalar/flag rule, an enum for
--  every literal-alternation rule, a struct for every struct rule, and a
--  `Vec<T>` alias for every list rule.  Schema comments are carried through
--  as `//` comments.
package ASTBNF_Rust is

   function Emit (Rules : ASTBNF.Rule_Vectors.Vector) return String;

   --  Emit the parser half: a recursive-descent parser (a token type plus one
   --  `parse_<rule>()` function per rule) that consumes a token slice and
   --  builds the types `Emit` declares.
   function Emit_Parser (Rules : ASTBNF.Rule_Vectors.Vector) return String;

   --  Emit the lexer half: a schema-independent scanner turning text into the
   --  token slice `Emit_Parser` consumes (skipping whitespace and `#` comments),
   --  plus a `parse_text` convenience that lexes, splits lines and parses.
   function Emit_Lexer (Rules : ASTBNF.Rule_Vectors.Vector) return String;

end ASTBNF_Rust;
