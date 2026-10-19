--  A text rule that names a bit rule: both read from one parser.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Mixed;
with Mixed.Parser; use Mixed.Parser;

procedure Mixed_Main is
   use Mixed;

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
      Out_R : Msg_Type;
   begin
      Out_R := Parse_Text (Text);
      Put_Line (What & ": len=" & Img (Long_Long_Integer (Out_R.Frame.Len)) & " body=" & Str (Out_R.Frame.Body_F));
   exception
      when E : Parse_Error =>
         Put_Line (What & ": error" & LF & Ada.Exceptions.Exception_Message (E));
   end Show;

begin
   Show ("hello", "PKT:" & Character'Val (5) & "hello;");
   Show ("one", "PKT:" & Character'Val (1) & "z;");
   Show ("short", "PKT:" & Character'Val (9) & "hello;");
   Show ("no semicolon", "PKT:" & Character'Val (5) & "hello");
   Show ("no tag", Character'Val (5) & "hello;");
end Mixed_Main;
