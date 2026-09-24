pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_C: the C "pretty printer" backend.  Given a parsed schema (a flat
--  list of rules), emit a compilable C header fragment: a `typedef enum` for
--  every literal-alternation rule, a `typedef struct` for every struct and
--  list rule, and nothing for scalar/flag aliases (they inline).  Schema
--  comments are carried through as C comments above each declaration.
package HBNF_C is

   --  Emit the C declarations.  When Idref is true, every struct and list
   --  node gains leading `objid_t id, parent;` fields (and the `objid_t`
   --  typedef) so the tree can be flattened by Emit_Serializer and rebuilt
   --  by Emit_Rebuild for a privsep (imsg) consumer.  Walkers emits the
   --  visit_/map_ helpers, the tree API for callers; a daemon binding's
   --  conf.c has no caller for them, so it leaves them out.
   function Emit
     (Rules   : HBNF_Grammar.Rule_Vectors.Vector;
      Idref   : Boolean := False;
      Walkers : Boolean := True)
      return String;

   --  Emit the serializer: a pre-order walk of the tree Emit declares that
   --  assigns ids in traversal order and emits one typed, flat record per
   --  object through an abstract `emit` callback.  Cross-references are ids,
   --  never pointers, so the output can cross a process boundary.
   function Emit_Serializer (Rules : HBNF_Grammar.Rule_Vectors.Vector)
      return String;

   --  Emit the rebuild side: a flat id-indexed config table, a `_find(id)`
   --  helper per object type, and a `config_get_<name>()` per type that
   --  allocates, fills scalars, and stores the object keyed by its id.
   function Emit_Rebuild (Rules : HBNF_Grammar.Rule_Vectors.Vector)
      return String;

   --  Emit the parser half: a self-contained recursive-descent parser (a
   --  token type plus one `parse_rule_<rule>()` function per rule) that
   --  consumes a token stream and allocates/populates the structs `Emit`
   --  declares.  On failure it records the deepest `fail` into the err
   --  buffer; the conf wrapper calls the `conf_error` handler with it.
   function Emit_Parser
     (Rules : HBNF_Grammar.Rule_Vectors.Vector)
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
   --
   --  With `conf struct X` (a daemon binding) the pair is a drop-in for the
   --  daemon's parse.y instead: conf.h only declares parse_config(filename,
   --  X *), conf_error and conf_file, and conf.c holds everything else,
   --  with parse_config the only other external function (lex, parse_text
   --  and parse_tokens are static, and the tree walkers are left out).
   function Emit_Conf_Header (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;
   function Emit_Conf_Source (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  Emit the deep-compare walk: one `compare_<rule>` per struct/list plus a
   --  `compare_tree(a, b)` entry, for byte-identity checking.  Two trees are
   --  equal when every scalar compares by value (strings by content, `char[N]`
   --  by memcmp), every enum and kind tag by value, every struct recurses, and
   --  every list matches element by element — never pointer addresses, TAILQ
   --  links, or padding.  Emitted after Emit (needs its types + list macros).
   function Emit_Compare (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

end HBNF_C;
