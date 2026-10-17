pragma Ada_2022;

--  HBNF_Wire.C: a parser over a byte buffer, in C, for a wire grammar.
--
--  The output is one self-contained file: the types (a struct per rule, an
--  integer per value set, a slice of the input per run of octets), then
--  `parse_bytes (buf, len, &root, err, sizeof err, &at)`, which reads the whole
--  buffer as the first rule or says where and why not, and `free_arena ()`.
--  Bits are read by shift and mask, first field in the most significant bits,
--  so no C bit-field layout is relied on.
package HBNF_Wire.C is

   function Emit (G : Grammar) return String;

   --  For a grammar of text rules and bit rules together: the bit rules, read
   --  from the text parser's own state (its input, its position and bit offset,
   --  its error record, its arena) by functions with the signature of the text
   --  rules', so a rule of either kind calls one of the other.  Types is the
   --  declarations (the octets type, a struct for each bit rule); Code is
   --  the helpers and the readers, to go after the text parser's own helpers.
   --  There is no writer in this form yet.
   procedure Emit_Hosted
     (G : Grammar; Types, Code : out Unbounded_String);

end HBNF_Wire.C;
