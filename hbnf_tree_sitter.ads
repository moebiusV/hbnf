pragma Ada_2022;

with HBNF_Grammar;

--  HBNF_Tree_Sitter: the tree-sitter backend (--backend=tree-sitter).  Given a
--  parsed schema, emit the `grammar.js` tree-sitter's generator reads:
--
--    * a phrase rule becomes seq / choice / repeat / optional of the rules and
--      literals it names;
--    * a character rule (a token in hbnf) becomes one regular expression;
--    * the file's `ws` rule becomes `extras`;
--    * a comma list, a left-recursive rule and a repetition `n*m` are written
--      out with the forms tree-sitter has.
--
--  What tree-sitter cannot say is left out, and the file says so in a comment at
--  its head (and as a warning): a lookahead `!x` / `&x`, a context test or
--  binding, an action, a scanner written in C.  Ordered choice has no form in
--  tree-sitter, which is an LR(1) generator with GLR forking: where two
--  alternatives can match alike, `tree-sitter generate` says so and the author
--  decides (a `conflicts` entry or a precedence).  Nothing here guesses.
package HBNF_Tree_Sitter is

   function Emit
     (Rules     : HBNF_Grammar.Rule_Vectors.Vector;
      Language  : String;
      Conflicts : String  := "";
      Ordered   : Boolean := False;
      Scanner   : Boolean := False) return String;
   --  Language is the grammar's name (letters, digits, underscore).
   --  Conflicts: groups of rules tree-sitter may fork between, a group's rules
   --  separated by commas and the groups by semicolons ("a,b;c,d"), as
   --  `conflicts` in grammar.js; `tree-sitter generate` names them one at a time.
   --  Ordered: where a choice has more than one alternative, give each
   --  `prec.dynamic`, the first the most, so that when forked parses both
   --  succeed the one hbnf's ordered choice would have taken wins.

   --  Scanner: write `x %as tag` ... `%same tag` with an external scanner (the
   --  grammar gets `externals`, and Scanner_Source is the scanner.c that goes in
   --  `src/` next to the generated parser) so the closing text must repeat the
   --  opening one, as in hbnf.  The scanner keeps the tags in its state, which
   --  tree-sitter saves and restores for every fork and every re-parse; that state
   --  is 1,024 octets at most, and a tag that does not fit is refused.  Without
   --  Scanner the second is any text of the same kind, and the file says so.
   --  Only a tagged name whose rule is a token the generator can scan as an
   --  automaton is done this way.
   function Scanner_Source return String;
   --  The scanner.c of the last Emit; empty when it needed none.

end HBNF_Tree_Sitter;
