pragma Ada_2022;

with ASTBNF;

--  ASTBNF_C: the C "pretty printer" backend.  Given a parsed schema (a flat
--  list of rules), emit a compilable C header fragment: a `typedef enum` for
--  every literal-alternation rule, a `typedef struct` for every struct and
--  list rule, and nothing for scalar/flag aliases (they inline).  Schema
--  comments are carried through as C comments above each declaration.
package ASTBNF_C is

   function Emit (Rules : ASTBNF.Rule_Vectors.Vector) return String;

end ASTBNF_C;
