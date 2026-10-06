pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with HBNF_Grammar;

--  HBNF_Lookahead: can a union be compiled as an ordered choice?
--
--  ABNF's `/` is a union: every alternative is legal, with backtracking into
--  the rest of the rule.  hbnf's generated parsers choose in order and commit
--  (PEG).  A union is compiled as an ordered choice, in some order of its
--  alternatives, whenever that accepts the same language (RFCPLAN.md decision
--  1): the reader finds the order, and the author writes `/` as the RFC does.
--
--  Whether an order exists is decided on the alternatives' text, not on how
--  many code points of lookahead tell them apart.  An alternative tried first
--  takes input a later one needed when the two can match text one of which is
--  a prefix of the other: the earlier one matches the shorter text, and
--  commits, where the later one needed the longer.  Each alternative is built
--  into an automaton and the pair is searched for such text.  Matching nothing
--  is text like any other: an alternative that can match nothing shadows every
--  other, so it goes last, and is refused if what follows the choice could
--  begin another.
--
--  A jet, a built-in scanner, a name that is no rule, or a rule that refers to
--  itself is taken to match any text, which only ever makes the answer "no".
package HBNF_Lookahead is
   use HBNF_Grammar;

   --  A set of code points, perhaps with "end of input" (what may follow the
   --  root) or "anything" (a first code point hbnf cannot see).
   type Cp_Set is private;

   Empty : constant Cp_Set;

   function Is_Empty (S : Cp_Set) return Boolean;
   function "or" (A, B : Cp_Set) return Cp_Set;
   function Meet (A, B : Cp_Set) return Cp_Set;
   --  The code points both sets hold.  Anything meets every non-empty set.

   function Image (S : Cp_Set) return String;
   --  `0`-`9` `_` ... : for a message.

   type Flags is array (Positive range <>) of Boolean;
   type Set_Array is array (Positive range <>) of Cp_Set;

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

   function First_Of
     (A : Analysis; Rules : Rule_Vectors.Vector; E : Element_Access)
      return Cp_Set;
   --  What an element can begin with.

   package Order_Vectors is new Ada.Containers.Vectors (Positive, Positive);

   procedure Check_Choice
     (A : Analysis; Rules : Rule_Vectors.Vector; Owner : Natural;
      V : Element_Vectors.Vector; Follow_Here : Cp_Set;
      Ok : out Boolean;
      Message : out Ada.Strings.Unbounded.Unbounded_String;
      Order : out Order_Vectors.Vector);
   --  V is a flat alternation, written as a union, in the rule Owner (0: none).
   --  Ok when some order of its alternatives makes ordered choice (take the
   --  first that matches) accept the same language: no alternative may be able
   --  to match text that a later one matches more of, or (when it is followed
   --  by what the choice is followed by) less of; at most one can match
   --  nothing, and it goes last, and Follow_Here (what comes after the choice)
   --  cannot begin any other.  Order is that order, as branch numbers.
   --  Otherwise Message says which two cannot be told apart, and on what text.

   procedure Greedy_Overlap
     (Rules : Rule_Vectors.Vector; Owner : Natural; E : Element_Access;
      V : Element_Vectors.Vector; From, To : Natural;
      Found : out Boolean;
      Witness : out Ada.Strings.Unbounded.Unbounded_String);
   --  E repeats a variable number of times (`*x`, `[ x ]`, `1*4x`) and V
   --  (From .. To) is what follows it in its sequence.  The generated parser
   --  takes as many repetitions as match and does not give one back, where
   --  ABNF would if the rest needed it.  Found when some text begins with a
   --  repetition and is also the start of the rest, so the two differ;
   --  Witness is that text.  A jet, a recursive rule or a built-in scanner is
   --  taken to match nothing here, so this never refuses a grammar on a guess.

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


end HBNF_Lookahead;
