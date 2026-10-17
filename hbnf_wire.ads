pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Interfaces;

--  HBNF_Wire: the wire layer (RFCPLAN.md step 7b, WIRE.md).  The main reader
--  (HBNF_Grammar) reads the bit forms as ordinary elements of the notation; a
--  rule that holds one is a bit rule, and HBNF_Wire.Lower turns the bit rules
--  into the tree declared here, which Check examines and the emitters
--  (HBNF_Wire.C, HBNF_Wire.Rust) turn into a parser and a writer over a buffer
--  of bits.  Nothing here reads a file.
--
--  The forms, as the main reader gives them:
--
--    name:N  name:16le  name:8s  name@K:N   N bits (little-endian, signed),
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

   package Name_Vectors is new Ada.Containers.Vectors
     (Positive, Unbounded_String);

   type Grammar is record
      Externals : Name_Vectors.Vector;
      External_Tokens : Name_Vectors.Vector;
      --  Those of the text rules that are tokens (read by a scanner, with no
      --  reader of their own, and a string for a value).
      --  The text rules of the grammar the bit rules may name (a field holding
      --  a string, or an enum, or a text token); the text emitter makes them.
      Rules  : Rule_Vectors.Vector;
      Prefix : Unbounded_String := To_Unbounded_String ("bnf_");
      Unit_Width : Natural := 0;               --  0: no text form
      Units      : Unit_Vectors.Vector;
      Unit_Sep   : Unbounded_String;           --  "" for none
      Language   : Unbounded_String := To_Unbounded_String ("C");
      --  `language Rust`: the language the file's code (preamble, epilogue,
      --  %action, %emit) is written in; C unless it says.
      Preamble   : Unbounded_String;
      Epilogue   : Unbounded_String;
      --  `{ code }` blocks between the directives and the rules, and after the
      --  rules: C copied as it stands, for includes and prototypes, and for the
      --  functions the actions call.  hbnf never reads it.
   end record;

   --  A grammar with code in it can be emitted in the language the code is
   --  written in.  Raises Wire_Error, saying what to do, when Backend (C, Rust,
   --  Zig or Ada) is not it.  A grammar without code goes to any.
   procedure Check_Code_Language (G : Grammar; Backend : String);

   --  The checks of a wire grammar: that what it names is defined, that an
   --  expression uses only what is read before it, that a field starts where
   --  it says, that a record does not hold itself.  Raises Wire_Error.
   procedure Check (G : in out Grammar; File : String);

   --  `u8`, `i32`, `u16le`: a width spelled as a type.
   procedure Fixed_Type
     (S : String; Is_Fixed : out Boolean; Bits : out Natural;
      Signed, Little : out Boolean);

   --  `s`, `le`, `be`, `sle`, `sbe`: what may follow a width.
   function Is_Modifier (S : String) return Boolean;

   --  An expression as written in a bit field (`ihl*4 - 20`), read.  Where is
   --  for the message.  Raises Wire_Error.
   function Parse_Expression (Text : String; Where : String) return Expr_Access;


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
