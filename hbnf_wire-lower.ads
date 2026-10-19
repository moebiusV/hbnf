pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_Wire.Lower: the rules of the main notation that hold bit fields (set
--  aside by the reader: HBNF_Grammar.Wire_Rules) as the wire layer's tree, which
--  the wire emitters read.  The text rules that `bitsof` names, and the numbered words in them,
--  are read from the rest of the grammar.  Raises Wire_Error, with the rule and where, for what a
--  bit rule cannot hold yet (text interleaved with bit fields).
package HBNF_Wire.Lower is

   function Lower
     (Wire : HBNF_Grammar.Rule_Vectors.Vector;
      Text : HBNF_Grammar.Rule_Vectors.Vector;
      File : String) return Grammar;

end HBNF_Wire.Lower;
