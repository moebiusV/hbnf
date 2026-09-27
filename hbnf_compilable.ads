pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_Compilable: schema shapes the compiled backends cannot yet express.
--
--  The emitters flatten a group inside a sequence into plain concatenation,
--  so an alternation, an optional or a repetition there used to compile into
--  a parser for a different language, with no diagnostic.  Check turns those
--  into generation-time errors until the emitters implement them; the
--  interpreter (HBNF_Match) handles all of them and does not call this.
--
--  Backend is the --backend= value; repetition bounds other than `*` are
--  enforced by the C backend only, so the other backends get a warning.
package HBNF_Compilable is

   procedure Check
     (Rules   : HBNF_Grammar.Rule_Vectors.Vector;
      Backend : String);
   --  Raises HBNF_Grammar.Parse_Error naming the first offending rule.

   function Is_Char_Rule
     (Rules : HBNF_Grammar.Rule_Vectors.Vector; Nm : String)
      return Boolean;
   --  True when the named rule is character-level: its pattern is a sequence
   --  or alternation of Char_Range terminals and references to other
   --  char-level rules, each element matching one code point (Min = Max = 1).
   --  Such a rule compiles to a scanner and a token kind, not a tree node.

end HBNF_Compilable;
