--  Text after a 3-bit field: read at bit 3, shifted.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Mixed3;
with Mixed3.Parser; use Mixed3.Parser;

procedure Mixed3_Main is
   use Mixed3;

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
      Put_Line (What & ": flag=" & Img (Long_Long_Integer (Out_R.Record_F.Flag)) & " label=" & To_String (Out_R.Record_F.Label) & " pad=" & Img (Long_Long_Integer (Out_R.Record_F.Pad)));
   exception
      when E : Parse_Error =>
         Put_Line (What & ": error" & LF & Ada.Exceptions.Exception_Message (E));
   end Show;

begin
   --  flag 101, "abc", pad 00000: 10101100 00101100 01001100 01100000
   Show ("abc", "REC:" & Character'Val (16#AC#) & Character'Val (16#2C#) & Character'Val (16#4C#) & Character'Val (16#60#));
   --  flag 000, "Z" = 0x5a: 00001011 01000000
   Show ("Z", "REC:" & Character'Val (16#0B#) & Character'Val (16#40#));
end Mixed3_Main;
