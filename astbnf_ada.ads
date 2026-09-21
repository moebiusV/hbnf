pragma Ada_2022;

with ASTBNF;

--  ASTBNF_Ada: the Ada "pretty printer" backend.  Given a parsed schema, emit
--  a compilable package spec: a subtype for every scalar/flag rule, a type
--  (enumeration or record) for every enum/struct rule, and a vector subtype
--  for every list rule.  Schema comments are carried through as Ada comments.
package ASTBNF_Ada is

   function Emit
     (Rules : ASTBNF.Rule_Vectors.Vector; Package_Name : String) return String;

   --  Emit the parser half: a self-contained recursive-descent parser (a
   --  token type plus one `Parse_<rule>` function per rule) that consumes a
   --  token array and populates the records `Emit` declares.  When Conf is
   --  true, also emit `Parse_Config (Filename)` — read a file, parse it — so
   --  the child package has the OpenBSD conf.h/conf.c-shape entry point
   --  (parse_tokens / parse_text / parse_config).
   function Emit_Parser
     (Rules      : ASTBNF.Rule_Vectors.Vector;
      Package_Name : String;
      Conf       : Boolean := False) return String;

end ASTBNF_Ada;
