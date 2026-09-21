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
   --  builds the types `Emit` declares.
   function Emit_Parser (Rules : ASTBNF.Rule_Vectors.Vector) return String;

end ASTBNF_Zig;
