pragma Ada_2022;

with Ada.Containers.Vectors;
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
   --  or alternation of Char_Range terminals, plain string literals and
   --  references to other char-level rules, each element matching some number
   --  of code points (Min..Max; Max = -1 unbounded).  Such a rule compiles to
   --  a scanner and a token kind, not a tree node.  A repeated element must be
   --  a character class (one code point): a repetition over a longer sequence
   --  stays a list.  A %i literal or a group is not char-level (Char_DNF
   --  raises for the shapes it cannot yet scan).

   --  A code-point range: one code point of a char rule's match.
   type Cp_Range is record
      Lo, Hi : Natural;
   end record;

   package Cp_Range_Vectors is new Ada.Containers.Vectors (Positive, Cp_Range);
   use type Cp_Range_Vectors.Vector;  --  make "=" visible for the nested instantiation

   --  A flat branch: a sequence of single code points.  This is the body of
   --  one repetition iteration (a repetition never nests another).
   package Cp_Branch_Vectors is new Ada.Containers.Vectors
     (Positive, Cp_Range_Vectors.Vector);
   use type Cp_Branch_Vectors.Vector;  --  "=" visible for Cp_Atom's Sub field

   --  One atom of a char rule's branch: a single code point, or a repetition
   --  (Min .. Max times; Max = 0 means unbounded) of a flat DNF.  A
   --  repetition is always the last atom of its branch, so the scanner can
   --  match it greedily with no backtracking.
   type Cp_Atom_Kind is (Single, Repeat);
   type Cp_Atom (Kind : Cp_Atom_Kind := Single) is record
      Lo, Hi : Natural;
      case Kind is
         when Single => null;
         when Repeat =>
            Min : Natural;                  --  minimum iterations
            Max : Natural;                  --  0 = unbounded
            Sub : Cp_Branch_Vectors.Vector; --  DNF of one iteration
      end case;
   end record;

   package Cp_Atom_Vectors is new Ada.Containers.Vectors (Positive, Cp_Atom);
   use type Cp_Atom_Vectors.Vector;  --  "=" visible for the nested instantiation

   --  A branch is a sequence of atoms (a run ending in at most one
   --  repetition); Char_DNF returns the list of branches.
   package Cp_Branch_Atom_Vectors is new Ada.Containers.Vectors
     (Positive, Cp_Atom_Vectors.Vector);

   function Char_DNF
     (Rules : HBNF_Grammar.Rule_Vectors.Vector; Nm : String)
      return Cp_Branch_Atom_Vectors.Vector;
   --  The disjunctive normal form of a char rule: a list of branches, each a
   --  sequence of atoms.  A Name reference is inlined -- its DNF distributed
   --  over the sequence position.  A string literal becomes one Single atom
   --  per code point; a repeated element becomes one trailing Repeat atom.
   --  The scanner matches the longest branch (maximal munch).

end HBNF_Compilable;
