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
   --  visit_/map_ helpers, the tree API for callers; a program that never
   --  walks the tree can leave them out.
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

   --  Emit the rebuild side: a reader over the serializer's records and a
   --  decode_<rule> per struct and list that rebuilds the pointer tree in
   --  pre-order, strings bump-allocated in the arena (so the root's free_
   --  releases them).  No id-indexed table or _find helpers are generated.
   function Emit_Rebuild (Rules : HBNF_Grammar.Rule_Vectors.Vector)
      return String;

   --  Emit the parser half: a self-contained recursive-descent parser (a
   --  token type plus one `parse_rule_<rule>()` function per rule) that
   --  consumes a token stream and allocates/populates the structs `Emit`
   --  declares.  On failure it records the deepest `fail` into the err
   --  buffer; a config grammar's epilogue hands it to the `conf_error` handler.
   function Emit_Parser
     (Rules : HBNF_Grammar.Rule_Vectors.Vector)
      return String;

   --  Emit the lexer half: a schema-independent scanner that turns text into
   --  the token stream `Emit_Parser` consumes (word/string/number/punctuation
   --  tokens, skipping whitespace and `#` comments), plus a `parse_text`
   --  convenience that lexes and parses in one call.  With `statements` the
   --  driver that reads a config one statement at a time comes too (and
   --  `macros`' expansion), with parse_file, which reads a file a block at
   --  a time.
   function Emit_Lexer
     (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  Emit the deep-compare walk: one `compare_<rule>` per struct/list plus a
   --  `compare_tree(a, b)` entry, for byte-identity checking.  Two trees are
   --  equal when every scalar compares by value (strings by content, `char[N]`
   --  by memcmp), every enum and kind tag by value, every struct recurses, and
   --  every list matches element by element — never pointer addresses, TAILQ
   --  links, or padding.  Emitted after Emit (needs its types + list macros).
   function Emit_Compare (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String;

   --  A grammar of text rules and bit rules (RFCPLAN.md step 7b): the types of
   --  the bit rules, and their readers, which HBNF_Wire.C makes to read the text
   --  parser's own state.  Emit puts the types before the struct bodies of the
   --  text rules, and Emit_Parser puts the readers after the forward
   --  declarations, so a rule of either kind can name one of the other.
   procedure Set_Hosted (Types, Code : String; Actions : Boolean := False);

   --  What a hosted reader needs to parse a text rule only to look at the
   --  result (`bitsof`): the C type of the rule's value, and the statement
   --  that frees one, `@` standing for its address.
   function Value_Type
     (Rules : HBNF_Grammar.Rule_Vectors.Vector; Name : String) return String;
   function Value_Free
     (Rules : HBNF_Grammar.Rule_Vectors.Vector; Name : String) return String;

   --  --writer: the generated code also has write_<root>, the tree as text
   --  (RFCPLAN.md 7c), and the parser records which alternative it took.
   procedure Set_Writer (On : Boolean);

   --  --ast: record which alternative each node took (`_alt`) and generate
   --  the tables and the walker (node_walk, node_kids, node_dump, ...).
   procedure Set_Ast (On : Boolean);

   --  --ast-tools: also node_kids, node_dump, node_equal and dump_<root>.
   procedure Set_Ast_Tools (On : Boolean);

   --  --paths: an error message says which rules the parser was in.
   procedure Set_Paths (On : Boolean);

   --  --spans: every node has _pos and _end, its place in the text; with --ast,
   --  node_span and node_where.  --parents: every node has _up and _upk, set by
   --  node_link (and link_<root> for a list root); node_parent reads them.
   procedure Set_Spans (On : Boolean);
   --  --forks: a rule whose alternatives can start alike is retried with the
   --  next alternative when something later in the same sequence fails
   --  (RFCPLAN.md decision 14).  Quiet: the forks are not listed on stderr.
   procedure Set_Forks (On : Boolean; Quiet : Boolean := False);
   procedure Set_Parents (On : Boolean);
   --  Compact (the default; --no-compact turns it off): a struct that gathers several rules' fields (a choice of
   --  statements, of options) holds each as a pointer, allocated from the arena
   --  when that alternative is the one taken, so the node costs the one
   --  alternative and not all of them.  Uses the pointer fields that break a
   --  by-value cycle, so every part of the generated code already handles them.
   procedure Set_Compact (On : Boolean);

   --  A ladder of binary operators (`a = b *( op b )`, `b = c *( op c )`, ...) is parsed by looking one byte past
   --  its first operand: if no operator of the ladder can begin there, the rest of every level is empty and
   --  the levels are not entered.  On by default; off for comparing with the plain parse (--no-ladder).
   procedure Set_Ladder (On : Boolean);

   --  Views (--views): a token's value is a pointer and a length into the input, with no
   --  copy (a quoted string with an escape in it is the one copy).  The tree borrows the text,
   --  so the text must outlive it.
   procedure Set_Views (On : Boolean);

   --  True when a tool asked for (--ast, --ast-tools, --writer, --parents) reads the strings of
   --  the tree as C strings, so they cannot be slices.
   function Needs_Copies return Boolean;

   --  Off, a rule that is a choice of other rules keeps a field for each, as it did; on (the
   --  default), it is a union with the number of the alternative taken (`_alt`).
   procedure Set_Choice (On : Boolean);

end HBNF_C;
