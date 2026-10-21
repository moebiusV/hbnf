--  Alternatives in a mixed grammar, written back: read the text, write the tree.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Mixed8;
with Mixed8.Parser; use Mixed8.Parser;

procedure Mixed8_Main is
   use Mixed8;

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   procedure Show (I : Natural; Text : String) is
      Doc   : Doc_Type;
      Out_T : Unbounded_String;
      Ok    : Boolean;
      Msg   : Unbounded_String;
   begin
      Doc := Parse_Text (Text);
      Write_Doc (Doc, Out_T, Ok, Msg);
      if Ok then
         Put_Line ("write " & Img (Long_Long_Integer (I)) & ": ok "
                   & Img (Long_Long_Integer (Length (Out_T))) & " bytes, same as read: "
                   & (if To_String (Out_T) = Text then "yes" else "no"));
      else
         Put_Line ("write " & Img (Long_Long_Integer (I)) & ": " & To_String (Msg));
      end if;
   exception
      when Parse_Error =>
         Put_Line ("read " & Img (Long_Long_Integer (I)) & ": error");
   end Show;
begin
   Show (0, "A:" & Character'Val (7) & Character'Val (3) & ";");
   Show (1, "B:abc;");
   Show (2, "L:x" & Character'Val (1) & Character'Val (2) & "yfoo,x"
         & Character'Val (3) & Character'Val (4) & ";");
end Mixed8_Main;
