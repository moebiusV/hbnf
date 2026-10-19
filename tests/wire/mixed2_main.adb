--  A bit rule that holds a text token.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Mixed2;
with Mixed2.Parser; use Mixed2.Parser;

procedure Mixed2_Main is
   use Mixed2;

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   function Str (O : Octets) return String is
      R : String (1 .. Natural (O.Length));
   begin
      for K in R'Range loop
         R (K) := Character'Val (O.Element (K - 1));
      end loop;
      return R;
   end Str;

   LF : constant Character := Character'Val (10);

   procedure Show (What : String; Text : String) is
      Out_R : Doc_Type;
   begin
      Out_R := Parse_Text (Text);
      Put_Line (What & ": kind=" & Img (Long_Long_Integer (Out_R.Record_F.Kind)) & " label=" & To_String (Out_R.Record_F.Label));
   exception
      when E : Parse_Error =>
         Put_Line (What & ": error" & LF & Ada.Exceptions.Exception_Message (E));
   end Show;

begin
   Show ("abc", "REC:" & Character'Val (7) & "abc");
   Show ("a letter as the kind", "REC:abc");
   Show ("no label", "REC:" & Character'Val (7));
   Show ("digits", "REC:" & Character'Val (7) & "123");
end Mixed2_Main;
