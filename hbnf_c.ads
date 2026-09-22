pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_C: the C "pretty printer" backend.  Given a parsed schema (a flat
--  list of rules), emit a compilable C header fragment: a `typedef enum` for
--  every literal-alternation rule, a `typedef struct` for every struct and
--  list rule, and nothing for scalar/flag aliases (they inline).  Schema
--  comments are carried through as C comments above each declaration.
package HBNF_C is

   function Emit (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  Emit the parser half: a self-contained recursive-descent parser (a
   --  token type plus one `parse_<rule>()` function per rule) that consumes
   --  a token stream and allocates/populates the structs `Emit` declares.
   --  When Conf is true, the parser's `fail` reports to the global
   --  `conf_error` handler at the point of error (yyerror-style) instead of
   --  only filling the err buffer.
   function Emit_Parser
     (Rules : HBNF_Grammar.Rule_Vectors.Vector; Conf : Boolean := False)
      return String;

   --  Emit the lexer half: a schema-independent scanner that turns text into
   --  the token stream `Emit_Parser` consumes (word/string/number/punctuation
   --  tokens, skipping whitespace and `#` comments), plus a `parse_text`
   --  convenience that lexes, splits lines and parses in one call.
   function Emit_Lexer (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  Emit the OpenBSD-daemon shape: a conf.h/conf.c pair.  The header is the
   --  declarations plus a global `conf` root, an overridable `conf_error`
   --  callback (default: print the caret message and exit(1)) and the
   --  parse_config(filename) prototype.  The source is the lexer + parser +
   --  parse_config, which slurps the file, populates `conf`, and reports
   --  errors through the callback.
   function Emit_Conf_Header (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;
   function Emit_Conf_Source (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

end HBNF_C;
