pragma Ada_2022;

with ASTBNF;

--  ASTBNF_Rust: the Rust backend.  Given a parsed schema, emit a compilable
--  Rust module fragment: a type alias for every scalar/flag rule, an enum for
--  every literal-alternation rule, a struct for every struct rule, and a
--  `Vec<T>` alias for every list rule.  Schema comments are carried through
--  as `//` comments.
package ASTBNF_Rust is

   function Emit (Rules : ASTBNF.Rule_Vectors.Vector) return String;

end ASTBNF_Rust;
