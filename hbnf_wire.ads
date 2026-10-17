pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Interfaces;

--  HBNF_Wire: the wire layer (RFCPLAN.md, step 7b).  A file that says `binary`
--  describes octets, not text: a field is `name:N`, N bits, packed the way an
--  RFC's packet diagram reads (first field in the most significant bits,
--  big-endian), and a rule is read by shift-and-mask code.  This unit reads such
--  a file into a small tree and checks it; HBNF_Wire.C (and the other
--  backends' children) turn the tree into a parser over a byte buffer.
--
--  The notation is the one RFCPLAN.md settles for 7b:
--
--    name:N  name:16le  name:8s  name:N@K   N bits (little-endian, signed),
--                                           which must start at bit K
--    name:[expr]  name:*u8                  octets: a count, or the rest
--    name:bits(expr)                        a bit count read from a field
--    0x0800  0b101                          a constant, as wide as its digits
--    name:rule  name:*rule  name:(expr)*rule  a nested record, any number,
--                                           exactly expr
--    ?(expr)                                a condition on what has been read
--    name:( ?(expr) a | ?(expr) b | c )     a choice, by guard
--
--  `align` is the number of bits to the next unit boundary (see `units`),
--  0 when the file has no units.
--
--  An expression is C's integer arithmetic over the fields read before it,
--  `remaining`, the number of bits left in the input, and `len (field)`, the
--  number of octets in a field read as `name:[...]` or `name:*u8`.
package HBNF_Wire is

   use Ada.Strings.Unbounded;

   Wire_Error : exception;
   --  The message is a complete, readable diagnostic: where, what is wrong, and
   --  what the author probably meant.

   --  True when Text has a line that says only `binary` (a comment after it
   --  is allowed): the file is a wire grammar, not a text one.
   function Is_Binary (Text : String) return Boolean;

   ---------------------------------------------------------------------------
   --  Expressions
   ---------------------------------------------------------------------------

   type Expr_Kind is (E_Num, E_Var, E_Unary, E_Binary, E_Call);

   type Expr;
   type Expr_Access is access Expr;
   type Expr (Kind : Expr_Kind := E_Num) is record
      case Kind is
         when E_Num    => Value : Long_Long_Integer := 0;
         when E_Var    => Name  : Unbounded_String;
         when E_Unary  => Un_Op : Unbounded_String;
                          Operand : Expr_Access;
         when E_Binary => Bin_Op : Unbounded_String;
                          Left, Right : Expr_Access;
         when E_Call   => Fn  : Unbounded_String;   --  `len (field)`
                          Arg : Unbounded_String;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  The tree
   ---------------------------------------------------------------------------

   type Item_Kind is
     (S_Bits,       --  N bits (Bits), maybe constrained by the rule Ref
      S_Const,      --  a constant of Bits bits and value Value (no field)
      S_Octets,     --  Count octets
      S_Rest,       --  all the octets that are left
      S_Bit_Expr,   --  Count bits (at most 64)
      S_Ref,        --  a nested record of rule Ref
      S_Array,      --  Min..Max (or Count) records of rule Ref
      S_Choice,     --  one of Alts
      S_Assert);    --  `?(expr)` between fields: the read fails unless it holds

   type Item;
   type Item_Access is access Item;
   package Item_Vectors is new Ada.Containers.Vectors (Positive, Item_Access);

   type Sequence is record
      Guard : Expr_Access := null;     --  `?(expr)`: taken only when non-zero
      Items : Item_Vectors.Vector;
      Line  : Natural := 0;
   end record;
   type Sequence_Access is access Sequence;
   package Seq_Vectors is new Ada.Containers.Vectors (Positive, Sequence_Access);

   type Item is record
      Kind   : Item_Kind := S_Bits;
      Name   : Unbounded_String;        --  the field; "" for a constant
      Bits   : Natural := 0;            --  S_Bits, S_Const
      Value  : Interfaces.Unsigned_64 := 0;
      Signed : Boolean := False;
      Little : Boolean := False;
      At_Bit : Integer := -1;           --  `@K`; -1: none
      Static_Ok : Boolean := False;     --  `@K` proved when the file was read
      Count  : Expr_Access := null;     --  S_Octets, S_Bit_Expr, S_Array
      Ref    : Unbounded_String;        --  S_Ref, S_Array, S_Bits (a value set)
      Min    : Natural := 0;            --  S_Array
      Max    : Integer := -1;           --  S_Array; -1 unbounded
      Alts   : Seq_Vectors.Vector;      --  S_Choice
      Line   : Natural := 0;
      Col    : Natural := 0;
   end record;

   type Rule is record
      Name : Unbounded_String;
      Alts : Seq_Vectors.Vector;
      Line : Natural := 0;
      Emit : Unbounded_String;
      --  `%emit{ code }`: C that runs when the record is written, before its
      --  fields are, on a copy of it as `n`; it fills in what is computed (a
      --  checksum).  HBNF_EMIT_FAIL ("...") fails the write.
      Action : Unbounded_String;
      --  `%action{ code }` at the end of the rule: C that runs on the rule's
      --  record, as `n`, once the whole read has succeeded (children first).
      --  It may call HBNF_WARN ("...") and HBNF_FAIL ("...").  It never runs
      --  during the read, so an alternative that is tried and given up cannot
      --  have run it.
   end record;
   package Rule_Vectors is new Ada.Containers.Vectors (Positive, Rule);

   --  `units W name from "file" [separator name]`: the message is also
   --  written as text, in units of W bits each.  A unit's spelling is a
   --  literal of the enum rule `name` in the text grammar "file", and its value
   --  is the literal's number (the place in the list, or `"x"@7`): a bech32
   --  symbol is 5 bits, a BIP-39 word 11.  The text is a decoding of the bits,
   --  as UTF-8 is.
   type Unit is record
      Spelling : Unbounded_String;
      Value    : Natural := 0;
   end record;
   package Unit_Vectors is new Ada.Containers.Vectors (Positive, Unit);

   type Grammar is record
      Rules  : Rule_Vectors.Vector;
      Prefix : Unbounded_String := To_Unbounded_String ("bnf_");
      Unit_Width : Natural := 0;               --  0: no text form
      Units      : Unit_Vectors.Vector;
      Unit_Sep   : Unbounded_String;           --  "" for none
      Preamble   : Unbounded_String;
      Epilogue   : Unbounded_String;
      --  `{ code }` blocks between the directives and the rules, and after the
      --  rules: C copied as it stands, for includes and prototypes, and for the
      --  functions the actions call.  hbnf never reads it.
   end record;

   --  Read and check a wire grammar.  Raises Wire_Error.
   function Parse (Text : String; File : String := "") return Grammar;

   function Find (G : Grammar; Name : String) return Natural;

   --  A rule whose every alternative is one constant of the same width: a
   --  value set, which a field may be constrained by (`ethertype:16`).
   function Is_Value_Set (R : Rule) return Boolean;
   function Value_Width (R : Rule) return Natural;

   --  The smallest standard width (8, 16, 32, 64) that holds N bits.
   function Storage_Bits (N : Natural) return Positive;

   --  The width in bits of the fields of a sequence when none of them varies,
   --  else -1.
   function Fixed_Bits (G : Grammar; S : Sequence) return Integer;

end HBNF_Wire;
