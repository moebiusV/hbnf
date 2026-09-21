pragma Ada_2022;

with ASTBNF;

--  ASTBNF_Ada: the Ada "pretty printer" backend.  Given a parsed schema, emit
--  a compilable package spec: a subtype for every scalar/flag rule, a type
--  (enumeration or record) for every enum/struct rule, and a vector subtype
--  for every list rule.  Schema comments are carried through as Ada comments.
package ASTBNF_Ada is

   function Emit
     (Rules : ASTBNF.Rule_Vectors.Vector; Package_Name : String) return String;

end ASTBNF_Ada;
