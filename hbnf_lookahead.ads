pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with HBNF_Grammar;

--  HBNF_Lookahead: what a grammar's alternatives can begin with.
--
--  ABNF's `/` is a union: every alternative is legal, with backtracking into
--  the rest of the rule.  hbnf's generated parsers choose in order and commit
--  (PEG), so a union is compiled as an ordered choice only where that accepts
--  the same language: where the alternatives cannot begin alike, so at most
--  one of them can match at any position (RFCPLAN.md decision 1).  This
--  package finds out which, with the textbook FIRST and FOLLOW sets over code
--  points.
--
--  An alternative that can match nothing is allowed too, if what may follow
--  the choice cannot begin the others; the caller moves it last.
--
--  A jet, a built-in scanner or a name that is no rule has a first code point
--  hbnf cannot see; its set is "anything", which meets every other.
package HBNF_Lookahead is
   use HBNF_Grammar;

   --  A set of code points, perhaps with "end of input" (what may follow the
   --  root) or "anything" (a first code point hbnf cannot see).
   type Cp_Set is private;

   Empty : constant Cp_Set;

   --  What a rule can start with, to two code points: the code points it can
   --  match whole, the pairs it can begin with when it matches more, and
   --  whether it can match nothing.  (One code point of lookahead is not
   --  always enough: `"//" x` and `"/" y` both begin with `/`.)
   type Leading is private;

   function Is_Empty (S : Cp_Set) return Boolean;
   function "or" (A, B : Cp_Set) return Cp_Set;
   function Meet (A, B : Cp_Set) return Cp_Set;
   --  The code points both sets hold.  Anything meets every non-empty set.

   function Image (S : Cp_Set) return String;
   --  `0`-`9` `_` ... : for a message.

   type Flags is array (Positive range <>) of Boolean;
   type Set_Array is array (Positive range <>) of Cp_Set;
   type Leading_Array is array (Positive range <>) of Leading;

   --  Which rules can match nothing, as a fixpoint over the rules.  A rule can
   --  when some branch is all elements that can; an element can when it
   --  repeats from zero, or is a rule that can, or a group with such a branch.
   function Nullable_Set (Rules : Rule_Vectors.Vector) return Flags;

   function El_Nullable
     (Rules : Rule_Vectors.Vector; Nullable : Flags; E : Element_Access)
      return Boolean;

   function Seq_Nullable
     (Rules : Rule_Vectors.Vector; Nullable : Flags;
      V : Element_Vectors.Vector; First, Last : Natural) return Boolean;
   --  True when some branch of V (First .. Last) can match nothing.

   type Analysis (N : Natural) is record
      Nullable : Flags (1 .. N);
      First    : Set_Array (1 .. N);   --  what a rule can begin with
      Follow   : Set_Array (1 .. N);   --  what can come right after it
      Lead     : Leading_Array (1 .. N);
   end record;

   function Analyze (Rules : Rule_Vectors.Vector) return Analysis;
   --  Rules (1) is the root: end of input follows it.

   type Bounds is record
      First, Last : Natural;   --  Last < First: an empty branch
   end record;

   package Bounds_Vectors is new Ada.Containers.Vectors (Positive, Bounds);

   function Branches (V : Element_Vectors.Vector) return Bounds_Vectors.Vector;
   --  The alternatives of a flat vector, split at its Alt elements.

   function Follow_After
     (A : Analysis; Rules : Rule_Vectors.Vector;
      V : Element_Vectors.Vector; B : Bounds; P : Positive;
      Follow_Branch : Cp_Set) return Cp_Set;
   --  What can come right after V (P), an element of the branch B, when
   --  Follow_Branch can come after the branch itself.  A repeated element is
   --  followed by itself as well.

   procedure Check_Choice
     (A : Analysis; Rules : Rule_Vectors.Vector;
      V : Element_Vectors.Vector; Follow_Here : Cp_Set;
      Ok : out Boolean;
      Message : out Ada.Strings.Unbounded.Unbounded_String;
      Nullable_Branch : out Natural);
   --  V is a flat alternation.  Ok when its alternatives cannot begin alike:
   --  their FIRST sets are disjoint; at most one can match nothing, and then
   --  Follow_Here (what comes after the choice) cannot begin any other.
   --  Nullable_Branch is the number of the one that can match nothing, or 0.
   --  Otherwise Message says which two meet, and where.

private

   type Cp_Range is record
      Lo, Hi : Natural;
   end record;

   package Range_Vectors is new Ada.Containers.Vectors (Positive, Cp_Range);

   type Cp_Set is record
      Ranges : Range_Vectors.Vector;   --  sorted, disjoint, not adjacent
      Eoi    : Boolean := False;
      Any    : Boolean := False;
   end record;

   Empty : constant Cp_Set :=
     (Ranges => Range_Vectors.Empty_Vector, Eoi => False, Any => False);

   --  Two code points: the first is in A and the second in B.
   type Pair is record
      A, B : Cp_Set;
   end record;

   package Pair_Vectors is new Ada.Containers.Vectors (Positive, Pair);

   type Leading is record
      Singles : Cp_Set;                       --  matches of one code point
      Pairs   : Pair_Vectors.Vector;          --  begins of longer matches
      Null_Ok : Boolean := False;             --  can match nothing
   end record;

end HBNF_Lookahead;
