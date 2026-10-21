--  A mixed grammar written back: read the text, write the tree.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Mixed;
with Mixed.Parser; use Mixed.Parser;

procedure Mixed7_Main is
   use Mixed;

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   procedure Show (I : Natural; Text : String; Want : Natural) is
      Doc  : Msg_Type;
      Out_T : Unbounded_String;
      Ok   : Boolean;
      Msg  : Unbounded_String;
   begin
      Doc := Parse_Text (Text);
      Write_Msg (Doc, Out_T, Ok, Msg);
      if Ok then
         Put_Line ("write " & Img (Long_Long_Integer (I)) & ": ok "
                   & Img (Long_Long_Integer (Length (Out_T))) & " bytes, same as read: "
                   & (if Length (Out_T) = Want and then To_String (Out_T) = Text
                      then "yes" else "no"));
      else
         Put_Line ("write " & Img (Long_Long_Integer (I)) & ": " & To_String (Msg));
      end if;
   exception
      when Parse_Error =>
         Put_Line ("read " & Img (Long_Long_Integer (I)) & ": error");
   end Show;
begin
   Show (0, "PKT:" & Character'Val (5) & "hello;", 11);
   Show (1, "PKT:" & Character'Val (1) & "z;", 7);
end Mixed7_Main;
