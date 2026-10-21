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

   --  The name of the procedure that runs the %actions under a bit rule.
   function Walk_Proc (Rule : String) return String;

   --  For a grammar of text rules and bit rules together: the bit rules, read
   --  from the text parser's own state (HBNF_Ada.Set_Hosted).  Types goes in the
   --  package of the types, Spec in the spec of the Parser child, Withs before
   --  its body, and Code (the readers, the writers, and for each bit rule the
   --  Parse_<rule> a text rule calls) in the body after the forward
   --  declarations.
   procedure Emit_Hosted
     (G : Grammar; Package_Name : String;
      Types, Spec, Withs, Code : out Unbounded_String);

end HBNF_Wire.Ada_Lang;
