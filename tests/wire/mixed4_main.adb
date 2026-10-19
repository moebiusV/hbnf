--  A text element, bit fields and text again, in one rule.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Mixed4;
with Mixed4.Parser; use Mixed4.Parser;

procedure Mixed4_Main is
   use Mixed4;

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
      Out_R : Req_Type;
   begin
      Out_R := Parse_Text (Text);
      Put_Line (What & ": len=" & Img (Long_Long_Integer (Out_R.Req_2.Len)) & " payload=" & Str (Out_R.Req_2.Payload));
   exception
      when E : Parse_Error =>
         Put_Line (What & ": error" & LF & Ada.Exceptions.Exception_Message (E));
   end Show;

begin
   Show ("hello", "GET " & Character'Val (5) & "hello" & Character'Val (13) & LF);
   Show ("one", "GET " & Character'Val (1) & "z" & Character'Val (13) & LF);
   Show ("short", "GET " & Character'Val (9) & "hello" & Character'Val (13) & LF);
   Show ("no line end", "GET " & Character'Val (5) & "hello");
   Show ("no verb", "PUT " & Character'Val (5) & "hello" & Character'Val (13) & LF);
end Mixed4_Main;
