pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with HBNF_Grammar;

--  HBNF_Compilable: schema shapes the compiled backends cannot yet express.
--
--  The emitters flatten a group inside a sequence into plain concatenation,
--  so an alternation, an optional or a repetition there used to compile into
--  a parser for a different language, with no diagnostic.  Check turns those
--  into generation-time errors until the emitters implement them.
--
--  Backend is the --backend= value; repetition bounds other than `*` are
--  enforced by the C backend only, so the other backends get a warning.
package HBNF_Compilable is

   procedure Check
     (Rules   : HBNF_Grammar.Rule_Vectors.Vector;
      Backend : String);
   --  Raises HBNF_Grammar.Parse_Error naming the first offending rule.

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

   --  ----  the tree-type graph, and the one cycle detector  ----
   --
   --  A rule's value is a struct by value, so a rule that contains itself --
   --  `prim = '(' expr ')' | int` with `expr = prim`, which is every
   --  expression language -- has no finite size.  Each backend used to carry
   --  its own way of finding that (C and Ada by a topological sort that
   --  stalled; Rust and Zig by a three-colour DFS); this is the one detector,
   --  so the four agree on which schemas they take by construction rather
   --  than by four hand-kept copies.
   --
   --  The graph is handed in, not derived here: what counts as "by value"
   --  differs per backend (a member whose rule is a record is a C struct by
   --  value but an Ada access type), and each backend already knows its own
   --  answer.

   type By_Value_Edge is record
      Owner  : Natural := 0;
      --  The rule whose field this is.
      Member : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      --  The field's name, or "" for an edge that is not a field at all: a
      --  scalar alias (`expr = prim`) has no field to make indirect.
      Target : Natural := 0;
      --  The rule the field holds by value.
   end record;

   package Edge_Vectors is new Ada.Containers.Vectors (Positive, By_Value_Edge);

   --  True when what a repetition repeats can match nothing, so one
   --  iteration may not advance the input.  A loop over it must stop when an
   --  iteration does not advance, or it never ends (RFCPLAN decision 9).  E is
   --  the repeated element: a rule reference, or a group.
   function Repeated_Body_Nullable
     (Rules : HBNF_Grammar.Rule_Vectors.Vector;
      E     : HBNF_Grammar.Element_Access) return Boolean;

   function Back_Edges (N : Natural; Edges : Edge_Vectors.Vector)
     return Edge_Vectors.Vector;
   --  One field per cycle to make indirect, chosen deterministically so
   --  output stays byte-stable: the field edge on the cycle whose owner has
   --  the lowest rule index (then the lowest member name).  A member name
   --  is unique within its owner, so that pair names one edge and the choice
   --  never depends on iteration order.
   --  Raises Parse_Error when a cycle has no field edge to break -- an
   --  all-alias cycle (`a = b`, `b = a`) has nothing to point at.

end HBNF_Compilable;
