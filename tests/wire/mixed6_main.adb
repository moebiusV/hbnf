--  A bit rule of a mixed grammar, written: %emit fills in len.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;
with Mixed6;
with Mixed6.Parser; use Mixed6.Parser;

procedure Mixed6_Main is
   use Mixed6;

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   function Hx (B : Unsigned_8) return String is
      Digs : constant String := "0123456789abcdef";
   begin
      return [Digs (Natural (B) / 16 + 1), Digs (Natural (B) mod 16 + 1)];
   end Hx;

   F     : Frame_Type;
   Bytes : Octets;
   Nbits : Natural;
   Ok    : Boolean;
   Msg   : Unbounded_String;
begin
   F.Len := 99;                       --  %emit replaces it
   for C of String'("hello") loop
      F.Body_F.Append (Unsigned_8 (Character'Pos (C)));
   end loop;
   F.Tag := To_Unbounded_String ("ab");
   Emit_Bits_Frame (F, Bytes, Nbits, Ok, Msg);
   if not Ok then
      Put_Line ("error: " & To_String (Msg));
   else
      Put (Img (Long_Long_Integer (Nbits)) & " bits:");
      for K in 0 .. (Nbits + 7) / 8 - 1 loop
         Put (" " & Hx (Bytes.Element (K)));
      end loop;
      New_Line;
   end if;
   F.Tag := To_Unbounded_String ("");   --  a token is text; "" writes nothing
   Emit_Bits_Frame (F, Bytes, Nbits, Ok, Msg);
   if Ok then
      Put_Line ("count only:" & Natural'Image (Nbits) & " bits");
   end if;
end Mixed6_Main;
