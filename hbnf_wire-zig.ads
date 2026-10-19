pragma Ada_2022;

--  HBNF_Wire.Zig: a parser over a byte buffer, in Zig, for a wire grammar.
--
--  One file: the types (a struct for a rule, a tagged union for a choice, a
--  slice of the input's octets, copied, for a run of them), then
--
--      pub fn parse_bits  (alloc, buf, nbits, err: *ParseError) error{Parse}!Root
--      pub fn parse_bytes (alloc, buf, err: *ParseError)        error{Parse}!Root
--      pub fn emit_bits   (alloc, v: Root, msg: *[]const u8)    error{Emit}!Emitted
--      pub fn emit_bytes  (alloc, v: Root, msg: *[]const u8)    error{Emit}![]u8
--
--  Zig errors carry no message, so the message and the octet are filled in
--  through the pointer.  What the parser allocates (the octets, the entries,
--  the messages) comes from alloc and is not freed one by one: give it an arena.
--  The same grammar the C backend reads, with the same checks and messages (but
--  not `name:bitsof(rule)`, which only C has so far).
package HBNF_Wire.Zig is

   function Emit (G : Grammar) return String;

   --  For a grammar of text rules and bit rules together: the bit rules, read
   --  from the text parser's own state (HBNF_Zig.Set_Hosted).  Types is the
   --  declarations (a struct for each bit rule), Code the readers, the writers
   --  (`emit_bits_<rule>`) and, for each bit rule, the parse_<rule> a text rule
   --  calls.  A character rule a bit rule names is read by its scanner; a
   --  text rule with structure there is C's alone.
   procedure Emit_Hosted (G : Grammar; Types, Code : out Unbounded_String);

end HBNF_Wire.Zig;
