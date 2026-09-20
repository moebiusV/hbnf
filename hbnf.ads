pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  HBNF: an OpenBSD-style ("parse.y style") configuration parser.
--
--  A declarative, block-structured grammar — keyword arguments, `{ }`
--  blocks, double-quoted strings with a fixed escape set, `#` comments, no
--  shell interpolation, no include/macro, no evaluation.  Parse returns a
--  tree of directives and blocks; the accessors below walk it.  Values are
--  typed (word / string / integer / decimal); a decimal keeps both its exact
--  text (for perfect round-tripping) and a fixed-point value (so callers need
--  not convert).
package HBNF is

   use Ada.Strings.Unbounded;

   --  A fixed-point decimal: 8 fractional digits, 38 total — exact for money
   --  (2dp), rates (e.g. 3.7e-5) and contract multipliers (0.001).  The
   --  accompanying text preserves any finer literal exactly.
   type Decimal is delta 10.0 ** (-8) digits 38;

   type Value_Kind is (Word, Str, Int, Dec);

   --  A scalar value.  For Word/Str only Text is set; for Int only Num is
   --  set (integers round-trip via Num); for Dec both Text (exact literal)
   --  and Num (fixed-point) are set.
   type Value is record
      Kind : Value_Kind := Word;
      Line : Positive   := 1;
      Col  : Positive   := 1;
      Text : Unbounded_String;     -- Word/Str/Dec literal
      Num  : Long_Long_Integer;    -- Int value
      Dec  : Decimal;              -- Dec fixed-point value
   end record;

   package Value_Vectors is new Ada.Containers.Vectors (Positive, Value);

   type Node_Kind is (Directive, Block);

   type Node;
   type Node_Access is access Node;

   package Node_Vectors is new Ada.Containers.Vectors (Positive, Node_Access);

   --  A directive (name + values) or a block (name + optional qualifier +
   --  children).  Every node carries its source position.
   type Node is record
      Kind      : Node_Kind := Directive;
      Name      : Unbounded_String := Null_Unbounded_String;
      Line      : Positive := 1;
      Col       : Positive := 1;
      Values    : Value_Vectors.Vector := Value_Vectors.Empty_Vector;
      Qualifier : Unbounded_String := Null_Unbounded_String;
      Children  : Node_Vectors.Vector := Node_Vectors.Empty_Vector;
   end record;

   type Parse_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            Root : Node_Access;
         when False =>
            Line : Positive;
            Col  : Positive;
            Msg  : Unbounded_String;
      end case;
   end record;

   --  Parse plaintext into a tree.  On failure Success is False and
   --  Line/Col/Msg describe the first error.
   function Parse (Text : String) return Parse_Result;

   --  Accessors ----------------------------------------------------------

   --  The direct children of a block, in source order (empty for a directive).
   function Children (N : Node) return Node_Vectors.Vector;

   --  The first child named Name, or null.
   function Find (N : Node; Name : String) return Node_Access;

   --  All children named Name, in source order (for repeated directives).
   function Find_All (N : Node; Name : String) return Node_Vectors.Vector;

   --  The number of values and the Index'th value of a directive.
   function Value_Count (N : Node) return Natural;
   function Value_At (N : Node; Index : Positive) return HBNF.Value;

   --  Scalar extraction --------------------------------------------------

   function As_Text (V : Value) return String;            -- Word/Str/Dec
   function As_Integer (V : Value) return Long_Long_Integer;  -- Int
   function As_Decimal (V : Value) return Decimal;        -- Dec

end HBNF;
