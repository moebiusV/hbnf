--  BIP-173 and BIP-350 segwit data parts through the Ada interface: the same
--  vectors as segwit_main.c, the same output.  The text is the bech32 symbols.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;
with Segwit; use Segwit;

procedure Segwit_Main is

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   Bad : Natural := 0;

   B0 : constant Byte_Array := (16#03#, 16#a8#, 16#f3#, 16#b7#, 16#40#, 16#cc#, 16#8c#, 16#b6#, 16#a2#, 16#a4#, 16#a0#, 16#e2#, 16#2e#, 16#8d#, 16#9d#, 16#19#, 16#1f#, 16#8a#, 16#19#, 16#de#, 16#b3#, 16#0e#, 16#98#, 16#ae#, 16#a0#);
   B1 : constant Byte_Array := (16#00#, 16#c3#, 16#18#, 16#a1#, 16#e0#, 16#a6#, 16#28#, 16#b3#, 16#40#, 16#25#, 16#e8#, 16#c9#, 16#01#, 16#9a#, 16#b6#, 16#d0#, 16#9b#, 16#64#, 16#c2#, 16#b3#, 16#c6#, 16#6a#, 16#69#, 16#3d#, 16#0d#, 16#c6#, 16#31#, 16#94#, 16#b0#, 16#24#, 16#81#, 16#93#, 16#10#, 16#3e#, 16#1f#, 16#a5#, 16#bc#);
   B2 : constant Byte_Array := (16#0b#, 16#cd#, 16#f3#, 16#33#, 16#f7#, 16#ce#, 16#e5#, 16#dd#, 16#62#, 16#ad#, 16#03#, 16#14#, 16#ae#, 16#74#, 16#38#, 16#58#, 16#38#, 16#14#, 16#df#, 16#e6#, 16#d9#, 16#6e#, 16#71#, 16#46#, 16#ca#, 16#cf#, 16#94#, 16#0a#, 16#d8#, 16#b7#, 16#c0#, 16#bc#, 16#c0#, 16#0a#, 16#d4#, 16#94#, 16#9e#);
   B3 : constant Byte_Array := (16#83#, 16#a8#, 16#f0#, 16#21#, 16#a2#, 16#55#, 16#24#);
   B4 : constant Byte_Array := (16#13#, 16#a8#, 16#f3#, 16#b7#, 16#40#, 16#cc#, 16#8c#, 16#b6#, 16#a2#, 16#a4#, 16#a0#, 16#e2#, 16#2e#, 16#8d#, 16#9d#, 16#19#, 16#19#, 16#d3#, 16#18#, 16#38#, 16#80#);
   B5 : constant Byte_Array := (16#00#, 16#00#, 16#08#, 16#10#, 16#18#, 16#20#, 16#28#, 16#30#, 16#38#, 16#40#, 16#48#, 16#50#, 16#58#, 16#60#, 16#68#, 16#70#, 16#78#, 16#80#, 16#88#, 16#90#, 16#98#, 16#a0#, 16#00#, 16#00#, 16#00#, 16#00#);
   B6 : constant Byte_Array := (16#88#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#);
   B7 : constant Byte_Array := (16#08#, 16#08#, 16#00#, 16#00#, 16#00#, 16#00#);
   B8 : constant Byte_Array := (16#08#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#);
   B9 : constant Byte_Array := (16#08#, 16#08#, 16#10#, 16#18#, 16#20#, 16#28#, 16#30#, 16#38#, 16#40#, 16#48#, 16#50#, 16#58#, 16#60#, 16#68#, 16#70#, 16#78#, 16#80#, 16#88#, 16#90#, 16#98#, 16#a0#, 16#aa#, 16#00#, 16#00#, 16#00#, 16#00#);
   B10 : constant Byte_Array := (16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#);
   B11 : constant Byte_Array := (16#08#, 16#08#, 16#10#, 16#18#, 16#20#, 16#28#, 16#30#, 16#38#, 16#40#, 16#48#, 16#50#, 16#58#, 16#60#, 16#68#, 16#70#, 16#78#, 16#80#, 16#88#, 16#90#, 16#98#, 16#a0#, 16#a8#, 16#00#, 16#00#, 16#00#, 16#00#);

   function Hex (P : Octets) return String is
      Digs : constant String := "0123456789abcdef";
      R    : String (1 .. 2 * Natural (P.Length));
   begin
      for K in 0 .. Natural (P.Length) - 1 loop
         R (2 * K + 1) := Digs (Natural (P.Element (K)) / 16 + 1);
         R (2 * K + 2) := Digs (Natural (P.Element (K)) mod 16 + 1);
      end loop;
      return R;
   end Hex;

   --  nbits of bytes, 5 at a time, as bech32 characters
   function Symbols (B : Byte_Array; Nbits : Natural) return String is
      Set : constant String := "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
      R   : String (1 .. Nbits / 5);
   begin
      for I in R'Range loop
         declare
            V : Natural := 0;
         begin
            for K in 0 .. 4 loop
               declare
                  Bit : constant Natural := (I - 1) * 5 + K;
               begin
                  V := V * 2 + Natural (Shift_Right (B (B'First + Bit / 8), 7 - Bit mod 8) and 1);
               end;
            end loop;
            R (I) := Set (V + 1);
         end;
      end loop;
      return R;
   end Symbols;

   procedure Vector (Name : String; Valid : Boolean; Nbits : Natural;
                     B : Byte_Array; Version : Integer; Program : String) is
      Out_R : Segwit_T;
      Ok    : Boolean;
      Err   : Parse_Error;
   begin
      Parse_Text (Symbols (B, Nbits), Out_R, Ok, Err);
      if Ok and then Valid then
         if Integer (Out_R.Version) = Version and then Hex (Out_R.Program) = Program then
            Put_Line ("PASS " & Name & ": version " & Img (Long_Long_Integer (Out_R.Version))
                      & ", " & Img (Long_Long_Integer (Out_R.Program.Length)) & " octets");
         else
            Put_Line ("FAIL " & Name & ": read as something else");
            Bad := Bad + 1;
         end if;
      elsif Ok then
         Put_Line ("FAIL accepted: " & Name);
         Bad := Bad + 1;
      elsif Valid then
         Put_Line ("FAIL " & Name & ": " & To_String (Err.Message));
         Bad := Bad + 1;
      else
         Put_Line ("PASS refused: " & Name & " (" & To_String (Err.Message) & ")");
      end if;
   end Vector;

   procedure Text_Case (I : Natural; T : String) is
      Out_R : Segwit_T;
      Ok    : Boolean;
      Err   : Parse_Error;
      Back  : Unbounded_String;
      Msg   : Unbounded_String;
   begin
      Parse_Text (T, Out_R, Ok, Err);
      if not Ok then
         Put_Line ("FAIL text " & Img (Long_Long_Integer (I)) & ": " & To_String (Err.Message));
         Bad := Bad + 1;
         return;
      end if;
      Emit_Text (Out_R, Back, Ok, Msg);
      if not Ok then
         Put_Line ("FAIL text " & Img (Long_Long_Integer (I)) & ": emit: " & To_String (Msg));
         Bad := Bad + 1;
      elsif To_String (Back) /= T then
         Put_Line ("FAIL text " & Img (Long_Long_Integer (I)) & ": written back as " & To_String (Back));
         Bad := Bad + 1;
      else
         Put_Line ("PASS text " & Img (Long_Long_Integer (I)) & ": version "
                   & Img (Long_Long_Integer (Out_R.Version)) & ", "
                   & Img (Long_Long_Integer (Out_R.Program.Length)) & " octets, written back");
      end if;
   end Text_Case;

   Out_B : Segwit_T;
   Ok    : Boolean;
   Err   : Parse_Error;
begin
   Vector ("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4", True, 195, B0, 0, "751e76e8199196d454941c45d1b3a323f1433bd6");
   Vector ("tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5", True, 295, B1, 0, "1863143c14c5166804bd19203356da136c985678cd4d27a1b8c6329604903262");
   Vector ("bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5j", True, 295, B2, 1, "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798");
   Vector ("BC1SW50QGDZ25J", True, 55, B3, 16, "751e");
   Vector ("bc1zw508d6qejxtdg4y5r3zarvaryvaxxpcs", True, 165, B4, 2, "751e76e8199196d454941c45d1b3a323");
   Vector ("v0 with a 21-octet program", False, 205, B5, -1, "");
   Vector ("version 17", False, 195, B6, -1, "");
   Vector ("a 1-octet program", False, 45, B7, -1, "");
   Vector ("a 41-octet program", False, 365, B8, -1, "");
   Vector ("padding that is not zero", False, 205, B9, -1, "");
   Vector ("v0 with a 19-octet program", False, 190, B10, -1, "");
   Vector ("v1 with a 21-octet program (2 padding bits)", True, 205, B11, 1, "0102030405060708090a0b0c0d0e0f101112131415");
   Text_Case (0, "qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");
   Text_Case (1, "qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7");
   Text_Case (2, "p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0");
   Text_Case (3, "sw50qgdz25j");
   Text_Case (4, "zw508d6qejxtdg4y5r3zarvaryvaxxpcs");
   Parse_Text ("qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3tb", Out_B, Ok, Err);
   Put_Line (if Ok then "FAIL b is not a bech32 symbol"
             else "PASS refused: b is not a bech32 symbol");
end Segwit_Main;
