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

   --  --forks: an alternative the one before it shadows is not an error; a later
   --  failure retries it (RFCPLAN.md decision 14).
   procedure Allow_Shadowing (On : Boolean);

   procedure Check
     (Rules   : HBNF_Grammar.Rule_Vectors.Vector;
      Backend : String);
   --  Raises HBNF_Grammar.Parse_Error naming the first offending rule.

   --  Does some alternative of V run an `%emit` before it has read or tested anything: the emit
   --  is its first effect, directly or through the first thing it names?  Such a part, if it may
   --  be absent, must not be tried blindly (RFCPLAN.md step 15).
   function Leads_With_Emit
     (Rules : HBNF_Grammar.Rule_Vectors.Vector;
      V     : HBNF_Grammar.Element_Vectors.Vector) return Boolean;

   --  A code-point range: one code point of a char rule's match.
   --  One position of a branch: the code points Lo .. Hi, and, when Hi2 >= Lo2, those too.  The second range is
   --  how a letter of a case-insensitive literal is both its cases without a branch for each spelling.
   type Cp_Range is record
      Lo, Hi : Natural;
      Lo2    : Natural := 1;
      Hi2    : Natural := 0;       --  Hi2 < Lo2: there is no second range
   end record;

   package Cp_Range_Vectors is new Ada.Containers.Vectors (Positive, Cp_Range);
   use type Cp_Range_Vectors.Vector;  --  make "=" visible for the nested instantiation

   --  A flat branch: a sequence of single code points.  This is the body of
   --  one repetition iteration (a repetition never nests another).
   package Cp_Branch_Vectors is new Ada.Containers.Vectors
     (Positive, Cp_Range_Vectors.Vector);
   use type Cp_Branch_Vectors.Vector;  --  "=" visible for Cp_Atom's Sub field

   --  One atom of a char rule's branch: a single code point, a repetition
   --  (Min .. Max times; Max = 0 means unbounded) of a flat DNF, or a
   --  lookahead.  A repetition is always the last atom of its branch, so the
   --  scanner can match it greedily with no backtracking.  A lookahead (`!x`,
   --  `&x`) is allowed in the whitespace rule and the rules it reaches: it
   --  matches, or does not, the text x names at the position, and moves
   --  nothing.  x is a branch list of its own, which the backends write as a
   --  function named Fn (see Look_Helpers).
   --  Bol and Eol are the built-in rules of those names: the position is the beginning of a line (the
   --  start of the text, or just after a line feed), or a line feed, a carriage return or the end of the
   --  text follows.  Like a lookahead they move nothing.
   --  Iter is a repetition of what is not one code point a time: a group, or a rule, with a lookahead or
   --  a repetition of its own inside (`*( !"]]>" any )`).  Lo and Hi are the least and the most times
   --  (Hi = 0: no most), Inner is one time's branches, a function named Fn like a lookahead's, which
   --  says how much of the longest branch matches (0: none).  Only the C backend gets one (see
   --  HBNF_Grammar.Set_Scan_Look); like a Repeat it takes as many as match, and does not give any back.
   --  Col_Test is `x where (col = 6)`: Lo numbers the condition (Col_Cond), a C expression on `c_`, the column; it moves nothing.
   type Cp_Atom_Kind is (Single, Repeat, Look, Bol, Eol, Iter, Col_Test);
   type Look_Body;                                   --  completed below
   type Look_Access is access Look_Body;
   type Cp_Atom (Kind : Cp_Atom_Kind := Single) is record
      Lo, Hi : Natural;
      Lo2    : Natural := 1;           --  a second range for a Single, as in Cp_Range (Hi2 < Lo2: none)
      Hi2    : Natural := 0;
      case Kind is
         when Single | Bol | Eol | Col_Test => null;
         when Repeat =>
            Min : Natural;                  --  minimum iterations
            Max : Natural;                  --  0 = unbounded
            Sub : Cp_Branch_Vectors.Vector; --  DNF of one iteration
         when Look | Iter =>
            Negative : Boolean;             --  `!x` (True) or `&x`; False for an Iter
            Fn       : Ada.Strings.Unbounded.Unbounded_String;
            Inner    : Look_Access;         --  the branches of x
      end case;
   end record;

   --  The conditions of the Col_Test atoms, numbered as they are met.
   function Add_Col_Cond (Code : String) return Natural;
   function Col_Cond (N : Natural) return String;

   package Cp_Atom_Vectors is new Ada.Containers.Vectors (Positive, Cp_Atom);
   use type Cp_Atom_Vectors.Vector;  --  "=" visible for the nested instantiation

   --  A branch is a sequence of atoms (a run ending in at most one
   --  repetition); Char_DNF returns the list of branches.
   package Cp_Branch_Atom_Vectors is new Ada.Containers.Vectors
     (Positive, Cp_Atom_Vectors.Vector);

   type Look_Body is record
      Branches : Cp_Branch_Atom_Vectors.Vector;
   end record;

   --  The functions a scanner calls for its lookaheads: for each Look atom of
   --  the branches, nested ones first, the name and the branches of what it
   --  looks at.  A function matches when some branch matches (the empty one
   --  too) and says whether it did.
   type Look_Helper is record
      Name     : Ada.Strings.Unbounded.Unbounded_String;
      Branches : Cp_Branch_Atom_Vectors.Vector;
      Is_Iter  : Boolean := False;     --  one time of an Iter, which says how much matched
   end record;
   package Look_Helper_Vectors is new Ada.Containers.Vectors (Positive, Look_Helper);

   function Look_Helpers (DNF : Cp_Branch_Atom_Vectors.Vector)
      return Look_Helper_Vectors.Vector;

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

   --  Compact nodes (every backend): True when a rule's pattern is a choice
   --  (top-level alternatives) and the field named Nm is held by some of the
   --  alternatives but not all of them.  Such a field is there only when its
   --  alternative was taken, so a backend may hold it behind a pointer; a
   --  field every alternative has, or a rule that is one sequence, is always
   --  there and stays by value.
   function Partly_Held
     (Pattern : HBNF_Grammar.Element_Vectors.Vector; Nm : String)
      return Boolean;

end HBNF_Compilable;
