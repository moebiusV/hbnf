pragma Ada_2022;

--  HBNF_Wire.Rust: a parser over a byte buffer, in Rust, for a wire grammar.
--
--  One module: the types (a struct for a rule, an enum for a choice, owned
--  octets as Vec<u8>), then
--
--      pub fn parse_bits  (buf: &[u8], nbits: usize) -> Result<Root, ParseError>
--      pub fn parse_bytes (buf: &[u8])               -> Result<Root, ParseError>
--      pub fn emit_bits   (v: &Root) -> Result<(Vec<u8>, usize), String>
--      pub fn emit_bytes  (v: &Root) -> Result<Vec<u8>, String>
--
--  The same grammar the C backend reads, with the same checks and the same
--  messages (but not `name:bitsof(rule)`, which only C has so far).
package HBNF_Wire.Rust is

   function Emit (G : Grammar) return String;

   --  For a grammar of text rules and bit rules together: the bit rules, read
   --  from the text parser's own input and position (HBNF_Rust.Set_Hosted).
   --  Types is the declarations, Code the readers, the writers
   --  (`emit_bits_<rule>`) and, for each bit rule, the parse_<rule> a text rule
   --  calls.
   procedure Emit_Hosted (G : Grammar; Types, Code : out Unbounded_String);

end HBNF_Wire.Rust;
