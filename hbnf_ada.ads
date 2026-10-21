pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_Ada: the Ada "pretty printer" backend.  Given a parsed schema, emit
--  a compilable package spec: a subtype for every scalar/flag rule, a type
--  (enumeration or record) for every enum/struct rule, and a vector subtype
--  for every list rule.  Schema comments are carried through as Ada comments.
package HBNF_Ada is

   function Emit
     (Rules : HBNF_Grammar.Rule_Vectors.Vector; Package_Name : String) return String;

   --  A grammar with bit rules (HBNF_Wire.Ada_Lang.Emit_Hosted): Types are added
   --  to the types, Spec to the specification of the Parser child, Withs before
   --  its body and Code to the body, after the forward declarations of the
   --  rules.  The parser then has a bit offset in its octet, and a text rule
   --  calls a bit rule as it calls a text rule, Parse_<rule> (P).
   --  --writer: also emit Write_<root>, the tree written back as text.
   procedure Set_Writer (On : Boolean);

   --  --ast: also emit the walker and the dump (Node_Walk, Node_Dump, ...).
   procedure Set_Ast (On : Boolean);

   --  --spans and --parents: also where each node is in the text (Node_Span,
   --  Node_Where) and which node holds it (Parents, Link_<Root>).
   procedure Set_Spans (On : Boolean);
   procedure Set_Parents (On : Boolean);

   procedure Set_Hosted (Types, Spec, Withs, Code : String; Walks : String := "");
   --  Walks: "rule=Walk_Proc" for each bit rule that holds an %action, space-separated;
   --  the text parser runs them after the whole text is read.

   --  The names the text backend gives a rule's type, its parser and its scanner.
   function Ident (Rule : String) return String;
   function Type_Name (Rule : String) return String;
   function Parse_Fn (Rule : String) return String;
   function Scan_Fn (Rule : String) return String;

   --  Emit the parser half: a self-contained recursive-descent parser (a
   --  token type plus one `Parse_<rule>` function per rule) that consumes a
   --  token array and populates the records `Emit` declares.  When Conf is
   --  true, also emit `Parse_Config (Filename)` — read a file, parse it — so
   --  the child package has the OpenBSD conf.h/conf.c-shape entry point
   --  (parse_tokens / parse_text / parse_config).
   function Emit_Parser
     (Rules      : HBNF_Grammar.Rule_Vectors.Vector;
      Package_Name : String;
      Conf       : Boolean := False) return String;

end HBNF_Ada;
