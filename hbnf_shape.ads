pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with HBNF_Grammar;

--  HBNF_Shape: what the code generators share.  The shape a rule takes in the tree (which of its
--  elements are members, which of those repeat, which are literals), the names a member and an
--  alternative have in a dump, and the small helpers these need.  The four backends (C, Rust,
--  Zig, Ada) read the same shape from the same rules, so it is worked out here once.
package HBNF_Shape is

   subtype U is Ada.Strings.Unbounded.Unbounded_String;
   use type Ada.Strings.Unbounded.Unbounded_String;

   package String_Vectors is new Ada.Containers.Vectors (Positive, U);
   package Natural_Vectors is new Ada.Containers.Vectors (Positive, Natural);

   --  Natural'Image with the leading blank stripped ("1", not " 1").
   function Img (N : Natural) return String;

   --  True when every `|`-alternative is exactly one Literal: the shape an enum can hold.
   function Is_Pure_Literal_Alt
     (Els : HBNF_Grammar.Element_Vectors.Vector) return Boolean;

   --  A valid identifier from a rule name ('-' -> '_', with the grammar's prefix), and a struct
   --  member name kept clear of C's keywords.
   function C_Name (S : String) return String;
   function C_Field (S : String) return String;

   --  The members of a rule's elements: each rule it names once, marked when it repeats; the
   --  literal strings; and whether the elements have alternatives.  A hidden rule is a member of
   --  nothing: it is matched, and kept nowhere.
   type Member is record
      Name    : U;
      Is_List : Boolean;
   end record;
   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

   function Contains (V : Member_Vectors.Vector; S : U) return Boolean;

   procedure Collect
     (Els     : HBNF_Grammar.Element_Vectors.Vector;
      Members : in out Member_Vectors.Vector;
      Lits    : in out String_Vectors.Vector;
      Has_Alt : in out Boolean);

   --  The names of the alternatives of a flat list of elements (Alt separators): a branch's
   --  first word-like literal, else its first rule name, else ALT<n>.  They are what a dump
   --  prints, so a dump reads the same in every language.
   function Alt_Labels (Els : HBNF_Grammar.Element_Vectors.Vector)
      return String_Vectors.Vector;

   --  The name a member has in a dump (its C field name), and that of the Branch-th alternative.
   function Member_Label (Name : String) return String;

   function Alt_Label
     (Els : HBNF_Grammar.Element_Vectors.Vector; Branch : Positive)
      return String;

end HBNF_Shape;
