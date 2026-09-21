pragma Ada_2022;

with ASTBNF;

--  ASTBNF_C: the C "pretty printer" backend.  Given a parsed schema (a flat
--  list of rules), emit a compilable C header fragment: a `typedef enum` for
--  every literal-alternation rule, a `typedef struct` for every struct and
--  list rule, and nothing for scalar/flag aliases (they inline).  Schema
--  comments are carried through as C comments above each declaration.
package ASTBNF_C is

   function Emit (Rules : ASTBNF.Rule_Vectors.Vector) return String;

   --  Emit the parser half: a self-contained recursive-descent parser (a
   --  token type plus one `parse_<rule>()` function per rule) that consumes
   --  a token stream and allocates/populates the structs `Emit` declares.
   function Emit_Parser (Rules : ASTBNF.Rule_Vectors.Vector) return String;

   --  Emit the lexer half: a schema-independent scanner that turns text into
   --  the token stream `Emit_Parser` consumes (word/string/number/punctuation
   --  tokens, skipping whitespace and `#` comments), plus a `parse_text`
   --  convenience that lexes, splits lines and parses in one call.
   function Emit_Lexer (Rules : ASTBNF.Rule_Vectors.Vector) return String;

end ASTBNF_C;
