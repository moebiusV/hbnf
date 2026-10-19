pragma Ada_2022;

--  HBNF_Wire.Ada_Lang: a parser over a byte buffer, in Ada, for a wire grammar.
--
--  One file holding the package specification and then its body (gnatchop
--  splits it): the types (a record for a rule, a record with a variant part for
--  a choice, Ada.Containers.Vectors for octets and for entries), then
--
--      procedure Parse_Bits  (Buf : Byte_Array; Nbits : Natural;
--                             Result : out Root; Ok : out Boolean;
--                             Err : out Parse_Error);
--      procedure Parse_Bytes (Buf : Byte_Array; Result : out Root;
--                             Ok : out Boolean; Err : out Parse_Error);
--      procedure Emit_Bits   (V : Root; Bytes : out Octets;
--                             Nbits : out Natural; Ok : out Boolean;
--                             Message : out Unbounded_String);
--      procedure Emit_Bytes  (V : Root; Bytes : out Octets;
--                             Ok : out Boolean; Message : out Unbounded_String);
--
--  The same grammar the C backend reads, with the same checks and messages (but
--  not `name:bitsof(rule)`, which only C has so far).
package HBNF_Wire.Ada_Lang is

   function Emit (G : Grammar; Package_Name : String) return String;

end HBNF_Wire.Ada_Lang;
