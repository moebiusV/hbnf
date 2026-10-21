--  %action on a bit rule inside a text grammar: failure and warnings.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Mixed5;
with Mixed5.Parser; use Mixed5.Parser;

procedure Mixed5_Main is
   use Mixed5;

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   procedure Show (What : String; Text : String) is
      Out_R : Doc_Type;
   begin
      Out_R := Parse_Text (Text);
      Put_Line (What & ": kind=" & Img (Long_Long_Integer (Out_R.Rec.Kind))
                & " len=" & Img (Long_Long_Integer (Out_R.Rec.Len)));
      for I in 1 .. Warning_Count loop
         Put_Line ("  warning: " & Warning (I));
      end loop;
   exception
      when E : Parse_Error =>
         Put_Line (What & ": error");
         Put_Line (Ada.Exceptions.Exception_Message (E));
   end Show;

   LF : constant Character := Character'Val (10);
begin
   Show ("plain", "REC:" & Character'Val (7) & Character'Val (3) & ";");
   Show ("long", "REC:" & Character'Val (7) & Character'Val (32) & ";");
   Show ("reserved", "REC:" & Character'Val (255) & Character'Val (1) & ";");
end Mixed5_Main;
