pragma Ada_2022;

with Ada.Strings.Unbounded;
with HBNF_Wire;

--  HBNF_Layout: the layout targets (LAYOUT.md).  The same bit rules the C, Rust, Zig and Ada backends turn into a
--  reader and a writer are turned here into a MODEL of charts (one per way the record can be laid out: ordered
--  rows of ordered pieces, each with its width, its place, its role and its label), and a target (a directory of
--  transforms, targets/NAME/*.tmpl) turns the model into text: SVG bit-layout charts, an HTML index, C tables,
--  Markdown.  Nothing here knows SVG or C: the model is the interface, the target is the language.
package HBNF_Layout is

   Layout_Error : exception;

   type Options is record
      Target_Dir : Ada.Strings.Unbounded.Unbounded_String;  --  targets/NAME
      Out_Dir    : Ada.Strings.Unbounded.Unbounded_String;  --  "" : standard output
      Root       : Ada.Strings.Unbounded.Unbounded_String;  --  "" : every top-level bit rule
      Unit       : Positive := 16;                          --  bits to a row of the drawing
      Unit_Name  : Ada.Strings.Unbounded.Unbounded_String;  --  "parcel"
      Source     : Ada.Strings.Unbounded.Unbounded_String;  --  the grammar's file name
   end record;

   --  Expand the bit rules into charts, build the model, render every transform of the target.
   --  Raises Layout_Error, with a message that says what is wrong.
   procedure Run (G : HBNF_Wire.Grammar; O : Options);

end HBNF_Layout;
