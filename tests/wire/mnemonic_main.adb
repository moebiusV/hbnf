--  BIP-39 mnemonics through the Ada interface: the same entropy, phrases and
--  checksums as mnemonic_main.c.  The grammar's code is Ada (mnemonic_ada.hbnf).
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;
with Mnemonic;

procedure Mnemonic_Main is
   use Mnemonic;
   use type Mnemonic.Octet_Vectors.Vector;

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   Bad : Natural := 0;

   E0 : constant Byte_Array := (16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#);
   E1 : constant Byte_Array := (16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#);
   E2 : constant Byte_Array := (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#);
   E3 : constant Byte_Array := (16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#);
   E4 : constant Byte_Array := (16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#);
   E5 : constant Byte_Array := (16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#);
   E6 : constant Byte_Array := (16#0c#, 16#1e#, 16#24#, 16#e5#, 16#91#, 16#77#, 16#79#, 16#d2#, 16#97#, 16#e1#, 16#4d#, 16#45#, 16#f1#, 16#4e#, 16#1a#, 16#1a#);
   E7 : constant Byte_Array := (16#9e#, 16#88#, 16#5d#, 16#95#, 16#2a#, 16#d3#, 16#62#, 16#ca#, 16#eb#, 16#4e#, 16#fe#, 16#34#, 16#a8#, 16#e9#, 16#1b#, 16#d2#);
   E8 : constant Byte_Array := (16#06#, 16#6d#, 16#ca#, 16#1a#, 16#2b#, 16#b7#, 16#e8#, 16#a1#, 16#db#, 16#28#, 16#32#, 16#14#, 16#8c#, 16#e9#, 16#93#, 16#3e#, 16#ea#, 16#0f#, 16#3a#, 16#c9#, 16#54#, 16#8d#, 16#79#, 16#31#, 16#12#, 16#d9#, 16#a9#, 16#5c#, 16#94#, 16#07#, 16#ef#, 16#ad#);
   E9 : constant Byte_Array := (16#f5#, 16#85#, 16#c1#, 16#1a#, 16#ec#, 16#52#, 16#0d#, 16#b5#, 16#7d#, 16#d3#, 16#53#, 16#c6#, 16#95#, 16#54#, 16#b2#, 16#1a#, 16#89#, 16#b2#, 16#0f#, 16#b0#, 16#65#, 16#09#, 16#66#, 16#fa#, 16#0a#, 16#9d#, 16#6f#, 16#74#, 16#fd#, 16#98#, 16#9d#, 16#8f#);
   E10 : constant Byte_Array := (16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#);
   E11 : constant Byte_Array := (16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#, 16#7f#);
   E12 : constant Byte_Array := (16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#, 16#80#);
   E13 : constant Byte_Array := (16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#);
   E14 : constant Byte_Array := (16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#);
   E15 : constant Byte_Array := (16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#);
   E16 : constant Byte_Array := (16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#, 16#00#);
   E17 : constant Byte_Array := (16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#, 16#ff#);

   function To_Octets (B : Byte_Array) return Octets is
      R : Octets;
   begin
      for X of B loop
         R.Append (X);
      end loop;
      return R;
   end To_Octets;

   procedure Vector (Phrase : String; N : Natural; E : Byte_Array; Cs : Unsigned_64) is
      Words : constant Natural := (N * 8 + N * 8 / 32) / 11;
      Out_R : Mnemonic_T;
      Ok    : Boolean;
      Err   : Parse_Error;
      Back  : Unbounded_String;
      Msg   : Unbounded_String;
      Want_Warn : constant Boolean := N /= 16 and then N /= 32;
   begin
      Parse_Text (Phrase, Out_R, Ok, Err);
      if not Ok then
         Put_Line ("FAIL " & Img (Long_Long_Integer (Words)) & " words: " & To_String (Err.Message));
         Bad := Bad + 1;
         return;
      end if;
      if Out_R.Entropy /= To_Octets (E) or else Out_R.Checksum /= Cs then
         Put_Line ("FAIL " & Img (Long_Long_Integer (Words)) & " words: entropy or checksum differs");
         Bad := Bad + 1;
      elsif (Warning_Count /= 0) /= Want_Warn then
         Put_Line ("FAIL " & Img (Long_Long_Integer (Words)) & " words: "
                   & Img (Long_Long_Integer (Warning_Count)) & " warning(s)");
         Bad := Bad + 1;
      else
         Emit_Text (Out_R, Back, Ok, Msg);
         if not Ok then
            Put_Line ("FAIL " & Img (Long_Long_Integer (Words)) & " words: emit: " & To_String (Msg));
            Bad := Bad + 1;
         elsif To_String (Back) /= Phrase then
            Put_Line ("FAIL " & Img (Long_Long_Integer (Words)) & " words: written back as " & To_String (Back));
            Bad := Bad + 1;
         else
            Put_Line ("PASS " & Img (Long_Long_Integer (Words)) & " words, entropy "
                      & Img (Long_Long_Integer (N)) & " octets, checksum "
                      & Img (Long_Long_Integer (Cs))
                      & (if Warning_Count /= 0 then ", warning: " & Warning (1) else "")
                      & ", written back");
         end if;
      end if;
   end Vector;

   procedure Refuse (Text : String; Why : String) is
      Out_R : Mnemonic_T;
      Ok    : Boolean;
      Err   : Parse_Error;
   begin
      Parse_Text (Text, Out_R, Ok, Err);
      if Ok then
         Put_Line ("FAIL accepted: " & Why);
         Bad := Bad + 1;
      else
         Put_Line ("PASS refused: " & Why & " (" & To_String (Err.Message) & ")");
      end if;
   end Refuse;

   procedure Generate (Phrase : String; N : Natural; E : Byte_Array) is
      T    : constant Mnemonic_T := (Entropy => To_Octets (E), Checksum => 16#55#);  --  wrong on purpose
      Back : Unbounded_String;
      Ok   : Boolean;
      Msg  : Unbounded_String;
   begin
      Emit_Text (T, Back, Ok, Msg);
      if not Ok then
         Put_Line ("FAIL generate: " & To_String (Msg));
         Bad := Bad + 1;
      elsif To_String (Back) /= Phrase then
         Put_Line ("FAIL generate: " & To_String (Back));
         Bad := Bad + 1;
      else
         Put_Line ("PASS generated " & Img (Long_Long_Integer ((N * 8 + N * 8 / 32) / 11))
                   & " words from " & Img (Long_Long_Integer (N)) & " octets of entropy");
      end if;
   end Generate;

begin
   Vector ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", 16, E0, 3);
   Vector ("legal winner thank year wave sausage worth useful legal winner thank yellow", 16, E1, 8);
   Vector ("letter advice cage absurd amount doctor acoustic avoid letter advice cage above", 16, E2, 4);
   Vector ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong", 16, E3, 5);
   Vector ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art", 32, E4, 102);
   Vector ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote", 32, E5, 175);
   Vector ("army van defense carry jealous true garbage claim echo media make crunch", 16, E6, 7);
   Vector ("ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic", 16, E7, 1);
   Vector ("all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform", 32, E8, 162);
   Vector ("void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold", 32, E9, 105);
   Vector ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent", 24, E10, 39);
   Vector ("legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal will", 24, E11, 25);
   Vector ("letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter always", 24, E12, 60);
   Vector ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when", 24, E13, 17);
   Vector ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon address", 20, E14, 27);
   Vector ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrist", 20, E15, 19);
   Vector ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon admit", 28, E16, 29);
   Vector ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo veteran", 28, E17, 25);
   Refuse ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon", "11 words");
   Refuse ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandonn", "a misspelt word");
   Refuse ("abandon  abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", "two blanks");
   Refuse ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about ", "a trailing blank");
   Refuse ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon", "a wrong checksum (all abandon)");
   Refuse ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo", "a wrong checksum (all zoo)");
   Refuse ("", "nothing");
   Generate ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about", 16, E0);
   Generate ("legal winner thank year wave sausage worth useful legal winner thank yellow", 16, E1);
   Generate ("letter advice cage absurd amount doctor acoustic avoid letter advice cage above", 16, E2);
   Generate ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong", 16, E3);
   Generate ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art", 32, E4);
   Generate ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote", 32, E5);
   Generate ("army van defense carry jealous true garbage claim echo media make crunch", 16, E6);
   Generate ("ozone drill grab fiber curtain grace pudding thank cruise elder eight picnic", 16, E7);
   Generate ("all hour make first leader extend hole alien behind guard gospel lava path output census museum junior mass reopen famous sing advance salt reform", 32, E8);
   Generate ("void come effort suffer camp survey warrior heavy shoot primary clutch crush open amazing screen patrol group space point ten exist slush involve unfold", 32, E9);
   Generate ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent", 24, E10);
   Generate ("legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful legal will", 24, E11);
   Generate ("letter advice cage absurd amount doctor acoustic avoid letter advice cage absurd amount doctor acoustic avoid letter always", 24, E12);
   Generate ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo when", 24, E13);
   Generate ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon address", 20, E14);
   Generate ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrist", 20, E15);
   Generate ("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon admit", 28, E16);
   Generate ("zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo veteran", 28, E17);
end Mnemonic_Main;
