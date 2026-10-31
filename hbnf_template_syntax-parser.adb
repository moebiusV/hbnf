
with Interfaces;
with Ada.Unchecked_Deallocation;

package body HBNF_Template_Syntax.Parser is

   use Ada.Strings.Unbounded;
   use Interfaces;   function Scan_Word (S : String; Pos, Len : Natural) return Natural is
      I : Natural := Pos;
   begin
      if I > Len
        or else S (I) not in 'a' .. 'z' | 'A' .. 'Z' | '_' | '-'
      then
         return 0;
      end if;
      I := I + 1;
      while I <= Len
        and then S (I) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '.'
      loop
         I := I + 1;
      end loop;
      return I - Pos;
   end Scan_Word;

   function Scan_Int (S : String; Pos, Len : Natural) return Natural is
      I     : Natural := Pos;
      Start : Natural;
   begin
      if I < Len and then S (I) = '-' and then S (I + 1) in '0' .. '9' then
         I := I + 1;
      end if;
      Start := I;
      while I <= Len and then S (I) in '0' .. '9' loop
         I := I + 1;
      end loop;
      return (if I > Start then I - Pos else 0);
   end Scan_Int;

   function Scan_Str (S : String; Pos, Len : Natural) return Natural is
      I : Natural;
   begin
      if Pos > Len or else S (Pos) /= '"' then
         return 0;
      end if;
      I := Pos + 1;
      while I <= Len and then S (I) /= '"' loop
         if S (I) = '\' and then I < Len then
            I := I + 1;
         end if;
         I := I + 1;
      end loop;
      if I > Len then
         return 0;
      end if;
      return I + 1 - Pos;
   end Scan_Str;

   function Scan_Ws (S : String; Pos, Len : Natural) return Natural is
   begin
      if Pos <= Len
        and then S (Pos) in ' ' | ASCII.HT | ASCII.CR | ASCII.LF
      then
         return 1;
      end if;
      return 0;
   end Scan_Ws;

   function Decode_Utf8 (S : String; Pos, Len : Natural; Cp : out Natural) return Natural is
      B0 : Unsigned_32;
      N  : Natural := 0;
      C  : Unsigned_32 := 0;
      B  : Unsigned_32;
   begin
      Cp := 0;
      if Pos > Len then return 0; end if;
      B0 := Unsigned_32 (Character'Pos (S (Pos)));
      if B0 < 16#80# then
         Cp := Natural (B0); return 1;
      elsif (B0 and 16#E0#) = 16#C0# then N := 2; C := B0 and 16#1F#;
      elsif (B0 and 16#F0#) = 16#E0# then N := 3; C := B0 and 16#0F#;
      elsif (B0 and 16#F8#) = 16#F0# then N := 4; C := B0 and 16#07#;
      else return 0;
      end if;
      if Pos + N - 1 > Len then return 0; end if;
      for J in 1 .. N - 1 loop
         B := Unsigned_32 (Character'Pos (S (Pos + J)));
         if (B and 16#C0#) /= 16#80# then return 0; end if;
         C := C * 16#40# or (B and 16#3F#);
      end loop;
      Cp := Natural (C); return N;
   end Decode_Utf8;

   function Scan_Open (S : String; Pos, Len : Natural) return Natural is
      type Table is array (Natural range <>) of Natural;
      Lo    : constant Table := (123, 123, 9, 13, 32, 35, 94, 0, 9, 11, 13, 14, 32, 33, 126, 0, 9, 11, 13, 14, 32, 33, 125, 126, 9, 13, 32, 125, 125, 1, 1);
      Hi    : constant Table := (123, 123, 10, 13, 32, 35, 94, 8, 10, 12, 13, 31, 32, 124, 1114111, 8, 10, 12, 13, 31, 32, 124, 125, 1114111, 10, 13, 32, 125, 125, 0, 0);
      To    : constant Table := (1, 2, 2, 2, 2, 3, 3, 4, 3, 4, 3, 4, 3, 4, 4, 4, 5, 4, 5, 4, 5, 4, 6, 4, 5, 5, 5, 6, 7, 0, 0);
      First : constant Table := (0, 1, 2, 7, 15, 24, 28, 29, 29);
      Acc   : constant Table := (0, 0, 0, 0, 0, 0, 0, 1, 0);
      I     : Natural := Pos;
      Best  : Natural := 0;
      St    : Natural := 0;
      Cp, N, K : Natural;
   begin
      loop
         if Acc (St) /= 0 then Best := I - Pos; end if;
         exit when I > Len;
         N := Decode_Utf8 (S, I, Len, Cp);
         exit when N = 0;
         K := First (St);
         while K < First (St + 1)
           and then not (Cp >= Lo (K) and then Cp <= Hi (K))
         loop
            K := K + 1;
         end loop;
         exit when K = First (St + 1);
         St := To (K);
         I := I + N;
      end loop;
      return Best;
   end Scan_Open;

   function Scan_Close (S : String; Pos, Len : Natural) return Natural is
      type Table is array (Natural range <>) of Natural;
      Lo    : constant Table := (123, 123, 9, 13, 32, 47, 0, 9, 11, 13, 14, 32, 33, 126, 0, 9, 11, 13, 14, 32, 33, 125, 126, 9, 13, 32, 125, 125, 1, 1);
      Hi    : constant Table := (123, 123, 10, 13, 32, 47, 8, 10, 12, 13, 31, 32, 124, 1114111, 8, 10, 12, 13, 31, 32, 124, 125, 1114111, 10, 13, 32, 125, 125, 0, 0);
      To    : constant Table := (1, 2, 2, 2, 2, 3, 4, 3, 4, 3, 4, 3, 4, 4, 4, 5, 4, 5, 4, 5, 4, 6, 4, 5, 5, 5, 6, 7, 0, 0);
      First : constant Table := (0, 1, 2, 6, 14, 23, 27, 28, 28);
      Acc   : constant Table := (0, 0, 0, 0, 0, 0, 0, 1, 0);
      I     : Natural := Pos;
      Best  : Natural := 0;
      St    : Natural := 0;
      Cp, N, K : Natural;
   begin
      loop
         if Acc (St) /= 0 then Best := I - Pos; end if;
         exit when I > Len;
         N := Decode_Utf8 (S, I, Len, Cp);
         exit when N = 0;
         K := First (St);
         while K < First (St + 1)
           and then not (Cp >= Lo (K) and then Cp <= Hi (K))
         loop
            K := K + 1;
         end loop;
         exit when K = First (St + 1);
         St := To (K);
         I := I + N;
      end loop;
      return Best;
   end Scan_Close;

   function Scan_Tag (S : String; Pos, Len : Natural) return Natural is
      type Table is array (Natural range <>) of Natural;
      Lo    : constant Table := (123, 123, 0, 9, 11, 13, 14, 32, 33, 34, 36, 38, 39, 48, 61, 63, 95, 123, 124, 126, 0, 9, 11, 13, 14, 32, 33, 125, 126, 0, 9, 11, 13, 14, 32, 33, 34, 36, 38, 39, 48, 61, 63, 95, 126, 0, 125, 126, 0, 9, 11, 13, 14, 32, 33, 126, 0, 9, 11, 13, 14, 32, 33, 125, 126, 9, 13, 32, 125, 125, 0, 125, 126, 0, 9, 11, 13, 14, 32, 33, 125, 126, 0, 9, 11, 13, 14, 32, 33, 125, 126, 9, 13, 32, 125, 125, 0, 9, 11, 13, 14, 32, 33, 125, 126, 125, 9, 13, 32, 125, 125, 1, 1);
      Hi    : constant Table := (123, 123, 8, 10, 12, 13, 31, 32, 33, 34, 37, 38, 46, 60, 62, 93, 122, 123, 124, 1114111, 8, 10, 12, 13, 31, 32, 124, 125, 1114111, 8, 10, 12, 13, 31, 32, 33, 34, 37, 38, 46, 60, 62, 93, 124, 1114111, 124, 125, 1114111, 8, 10, 12, 13, 31, 32, 124, 1114111, 8, 10, 12, 13, 31, 32, 124, 125, 1114111, 10, 13, 32, 125, 125, 124, 125, 1114111, 8, 10, 12, 13, 31, 32, 124, 125, 1114111, 8, 10, 12, 13, 31, 32, 124, 125, 1114111, 10, 13, 32, 125, 125, 8, 10, 12, 13, 31, 32, 124, 125, 1114111, 125, 10, 13, 32, 125, 125, 0, 0);
      To    : constant Table := (1, 2, 3, 4, 3, 4, 3, 4, 5, 3, 3, 6, 3, 3, 5, 3, 3, 7, 3, 3, 3, 8, 3, 8, 3, 8, 3, 9, 3, 3, 4, 3, 4, 3, 4, 5, 3, 3, 6, 3, 3, 5, 3, 3, 3, 5, 10, 5, 3, 6, 3, 6, 3, 6, 3, 3, 11, 12, 11, 12, 11, 12, 11, 9, 11, 8, 8, 8, 9, 13, 5, 13, 5, 11, 14, 11, 14, 11, 14, 11, 15, 11, 16, 12, 16, 12, 16, 12, 16, 9, 16, 14, 14, 14, 15, 17, 16, 18, 16, 18, 16, 18, 16, 19, 16, 13, 18, 18, 18, 19, 9, 0, 0);
      First : constant Table := (0, 1, 2, 20, 29, 45, 48, 56, 65, 69, 70, 73, 82, 91, 91, 95, 96, 105, 106, 110, 111);
      Acc   : constant Table := (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0);
      I     : Natural := Pos;
      Best  : Natural := 0;
      St    : Natural := 0;
      Cp, N, K : Natural;
   begin
      loop
         if Acc (St) /= 0 then Best := I - Pos; end if;
         exit when I > Len;
         N := Decode_Utf8 (S, I, Len, Cp);
         exit when N = 0;
         K := First (St);
         while K < First (St + 1)
           and then not (Cp >= Lo (K) and then Cp <= Hi (K))
         loop
            K := K + 1;
         end loop;
         exit when K = First (St + 1);
         St := To (K);
         I := I + N;
      end loop;
      return Best;
   end Scan_Tag;

   function Scan_Text (S : String; Pos, Len : Natural) return Natural is
      type Table is array (Natural range <>) of Natural;
      Lo    : constant Table := (0, 123, 124, 0, 123, 124, 0, 124, 1, 1);
      Hi    : constant Table := (122, 123, 1114111, 122, 123, 1114111, 122, 1114111, 0, 0);
      To    : constant Table := (1, 2, 1, 1, 2, 1, 1, 1, 0, 0);
      First : constant Table := (0, 3, 6, 8);
      Acc   : constant Table := (0, 1, 0, 0);
      I     : Natural := Pos;
      Best  : Natural := 0;
      St    : Natural := 0;
      Cp, N, K : Natural;
   begin
      loop
         if Acc (St) /= 0 then Best := I - Pos; end if;
         exit when I > Len;
         N := Decode_Utf8 (S, I, Len, Cp);
         exit when N = 0;
         K := First (St);
         while K < First (St + 1)
           and then not (Cp >= Lo (K) and then Cp <= Hi (K))
         loop
            K := K + 1;
         end loop;
         exit when K = First (St + 1);
         St := To (K);
         I := I + N;
      end loop;
      return Best;
   end Scan_Text;

   function Scan_Any (S : String; Pos, Len : Natural) return Natural is
      Cp  : Natural;
      N   : Natural;
      Off : Natural := 0;
   begin
      N := Decode_Utf8 (S, Pos + Off, Len, Cp);
      if N = 0 or else not (Cp <= 1114111) then return 0; end if;
      Off := Off + N;
      return Off;
   end Scan_Any;

   type Text_Access is access constant String;

   type Alt_List is array (1 .. 16) of Unbounded_String;
   type Rule_Stack is array (1 .. 24) of Natural;

   --  The parser reads the text itself: a position in it, no token array.
   type Parser is record
      Text : Text_Access;
      Pos  : Natural := 1;
      Last : Natural := Natural'Last;   --  the input is cut here for a trial parse (`a - b`)
      Failed : Boolean := False;        --  a parse that failed returns at once, up to whoever tries the next way
      --  The farthest failure (Err_Pos, 0 while there is none): what could have stood
      --  there, each told once, and the rules being read then and where each began.
      Err_Pos    : Natural := 0;
      Alt_N      : Natural := 0;
      Alts       : Alt_List;
      More       : Boolean := False;
      Depth      : Natural := 0;
      Stk        : Rule_Stack := (others => 0);
      Stkpos     : Rule_Stack := (others => 0);
      Err_Depth  : Natural := 0;
      Err_Stk    : Rule_Stack := (others => 0);
      Err_Stkpos : Rule_Stack := (others => 0);
   end record;

   --  A rule is being read from here (and not any more, when it returns).
   procedure Enter (P : in out Parser; Rule : Positive) is
   begin
      if P.Depth < 24 then
         P.Stk (P.Depth + 1) := Rule;
         P.Stkpos (P.Depth + 1) := P.Pos;
      end if;
      P.Depth := P.Depth + 1;
   end Enter;

   function Limit (P : Parser) return Natural is
     (Natural'Min (P.Last, P.Text'Last));

   Spaces : constant String :=
     "                                                                ";

   --  What stands at the position, for an error message: the bareword that
   --  starts there, else the one character, else the end of the text.
   function Found (P : Parser; At_Pos : Natural) return String is
      Last : constant Natural := P.Text'Last;
      I    : Natural := At_Pos;

      function Word_Char (C : Character) return Boolean is
        (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '.');
   begin
      if At_Pos > Last then
         return "end of input";
      end if;
      if Word_Char (P.Text (I)) then
         while I <= Last and then Word_Char (P.Text (I)) loop
            I := I + 1;
         end loop;
         return P.Text (At_Pos .. I - 1);
      end if;
      return P.Text (At_Pos .. At_Pos);
   end Found;

   --  Keep the farthest failure, and at the same place what else could have stood
   --  there; the message is made of them when the whole parse has failed (Render).
   procedure Fail (P : in out Parser; Expected : String) is
   begin
      if P.Err_Pos = 0 or else P.Pos > P.Err_Pos then
         P.Err_Pos := P.Pos;
         P.Alt_N := 1;
         P.Alts (1) := To_Unbounded_String (Expected);
         P.More := False;
         P.Err_Depth := Natural'Min (P.Depth, 24);
         P.Err_Stk := P.Stk;
         P.Err_Stkpos := P.Stkpos;
      elsif P.Pos = P.Err_Pos then
         declare
            Seen : Boolean := P.Alt_N >= 16 and then P.More;   --  a full list that has said "and more" cannot change
         begin
            for I in 1 .. P.Alt_N loop
               exit when Seen;
               if P.Alts (I) = Expected then   --  no string is made to compare
                  Seen := True;
               end if;
            end loop;
            if not Seen then
               if P.Alt_N < 16 then
                  P.Alt_N := P.Alt_N + 1;
                  P.Alts (P.Alt_N) := To_Unbounded_String (Expected);
               else
                  P.More := True;
               end if;
            end if;
         end;
      end if;
      P.Failed := True;   --  not raised: GNAT unwinds in microseconds, and a parse fails more often than it succeeds
   end Fail;

   --  A punctuation- or digit-led literal: compare bytes at the position (a
   --  prefix is correct there, e.g. "-" in "-5", "0x" in "0x1F").
   procedure Expect_Lit (P : in out Parser; Lit : String) is
   begin
      if P.Pos + Lit'Length - 1 <= Limit (P)
        and then P.Text (P.Pos .. P.Pos + Lit'Length - 1) = Lit
      then
         P.Pos := P.Pos + Lit'Length;
      else
         Fail (P, "`" & Lit & "`");
      end if;
   end Expect_Lit;

   --  A keyword: the whole bareword at the position must be the literal, so
   --  `in` does not match the front of `input`.
   procedure Expect_Word (P : in out Parser; Lit : String) is
      N : constant Natural := Scan_Word (P.Text.all, P.Pos, Limit (P));
   begin
      if N = Lit'Length and then P.Text (P.Pos .. P.Pos + N - 1) = Lit then
         P.Pos := P.Pos + N;
      else
         Fail (P, "`" & Lit & "`");
      end if;
   end Expect_Word;

   --  Skip what the grammar calls whitespace, one match at a time.
   procedure Skip_Ws (P : in out Parser) is
   begin
      null;
   end Skip_Ws;

   --  The content of a quoted string: strip the quotes, and drop a backslash
   --  (keeping the character after it) or a backslash-newline.
   function Str_Value (S : String) return Unbounded_String is
      R : Unbounded_String;
      I : Natural := S'First + 1;
   begin
      while I < S'Last loop
         if S (I) = '\' and then I + 1 < S'Last then
            I := I + 1;
            if S (I) /= ASCII.LF then
               Append (R, S (I));
            end if;
         else
            Append (R, S (I));
         end if;
         I := I + 1;
      end loop;
      return R;
   end Str_Value;

   function Is_Keyword (S : String) return Boolean is
   begin
      pragma Unreferenced (S);
      return False;
   end Is_Keyword;

   procedure Dealloc_Part is new Ada.Unchecked_Deallocation (Part_Type, Part_Access);
   procedure Dealloc_Block is new Ada.Unchecked_Deallocation (Block_Type, Block_Access);
   procedure Dealloc_Lone is new Ada.Unchecked_Deallocation (Lone_Type, Lone_Access);

   procedure Free_Template (V : in out Template_Type) is
   begin
   for K in V.First_Index .. V.Last_Index loop
      declare
         E : Part_Access := V (K);
      begin
         if E /= null then
            Free_Part (E.all);
            V.Replace_Element (K, null);
            Dealloc_Part (E);
         end if;
      end;
   end loop;
   end Free_Template;

   procedure Free_Part (V : in out Part_Type) is
   begin
   if V.Block /= null then
      Free_Block (V.Block.all);
      Dealloc_Block (V.Block);
   end if;
   if V.Lone /= null then
      Free_Lone (V.Lone.all);
      Dealloc_Lone (V.Lone);
   end if;
   end Free_Part;

   procedure Free_Block (V : in out Block_Type) is
   begin
   Free_Template (V.Template);
   end Free_Block;

   procedure Free_Lone (V : in out Lone_Type) is
      pragma Unreferenced (V);
   begin
      null;
   end Free_Lone;

   function Parse_Template (P : in out Parser) return Template_Type;
   function Parse_Part (P : in out Parser) return Part_Type;
   function Parse_Block (P : in out Parser) return Block_Type;
   function Parse_Open (P : in out Parser) return Open_Type;
   function Parse_Close (P : in out Parser) return Close_Type;
   function Parse_Tag (P : in out Parser) return Tag_Type;
   function Parse_Text (P : in out Parser) return Text_Type;
   function Parse_Lone (P : in out Parser) return Lone_Type;
   function Parse_Any (P : in out Parser) return Any_Type;
   function Parse_Word (P : in out Parser) return Word_Type;
   function Parse_Int (P : in out Parser) return Int_Type;
   function Parse_Str (P : in out Parser) return Str_Type;
   function Parse_Ws (P : in out Parser) return Ws_Type;

   function Body_Of_Template (P : in out Parser) return Template_Type is
   R : Template_Type;
   begin
      loop
         declare
            Start : constant Natural := P.Pos;
         begin
            if P.Pos > Limit (P) then P.Pos := Start; exit; end if;
            declare V : Part_Type := Parse_Part (P); begin if P.Failed then P.Failed := False; P.Pos := Start; exit; end if; R.Append (new Part_Type'(V)); end;
         end;
      end loop;
      return R;
   end Body_Of_Template;

   function Parse_Template (P : in out Parser) return Template_Type is
   begin
      Enter (P, 1);
      declare
         R : constant Template_Type := Body_Of_Template (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Template;

   function Body_Of_Part (P : in out Parser) return Part_Type is
   R : Part_Type;
   begin
      declare
         Save : constant Natural := P.Pos;
      begin
         declare
            R : Part_Type;
         begin
            declare V : Block_Type := Parse_Block (P); begin if P.Failed then goto Alt_Fail_1; end if; R.Block := new Block_Type'(V); end;
            return R;
            <<Alt_Fail_1>> null;
         end;
         P.Failed := False; P.Pos := Save;
         declare
            R : Part_Type;
         begin
            declare
               N : constant Natural := Scan_Tag (P.Text.all, P.Pos, Limit (P));
            begin
               if N = 0 then Fail (P, "tag"); goto Alt_Fail_2; end if;
               R.Tag := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1)); P.Pos := P.Pos + N;
            end;
            return R;
            <<Alt_Fail_2>> null;
         end;
         P.Failed := False; P.Pos := Save;
         declare
            R : Part_Type;
         begin
            declare
               N : constant Natural := Scan_Text (P.Text.all, P.Pos, Limit (P));
            begin
               if N = 0 then Fail (P, "text"); goto Alt_Fail_3; end if;
               R.Text := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1)); P.Pos := P.Pos + N;
            end;
            return R;
            <<Alt_Fail_3>> null;
         end;
         P.Failed := False; P.Pos := Save;
         declare
            R : Part_Type;
         begin
            declare V : Lone_Type := Parse_Lone (P); begin if P.Failed then goto Alt_Fail_4; end if; R.Lone := new Lone_Type'(V); end;
            return R;
            <<Alt_Fail_4>> null;
         end;
         P.Failed := False; P.Pos := Save;
         P.Pos := Save;
         Fail (P, "a part");
         return R;
      end;
   end Body_Of_Part;

   function Parse_Part (P : in out Parser) return Part_Type is
   begin
      Enter (P, 2);
      declare
         R : constant Part_Type := Body_Of_Part (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Part;

   function Body_Of_Block (P : in out Parser) return Block_Type is
   R : Block_Type;
   begin
      declare
         N : constant Natural := Scan_Open (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "open"); return R; end if;
         R.Open := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1)); P.Pos := P.Pos + N;
      end;
      R.Template := Parse_Template (P); if P.Failed then return R; end if;
      declare
         N : constant Natural := Scan_Close (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "close"); return R; end if;
         R.Close := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1)); P.Pos := P.Pos + N;
      end;
      return R;
   end Body_Of_Block;

   function Parse_Block (P : in out Parser) return Block_Type is
   begin
      Enter (P, 3);
      declare
         R : constant Block_Type := Body_Of_Block (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Block;

   function Body_Of_Open (P : in out Parser) return Open_Type is
   R : Open_Type;
   begin
      declare
         N : constant Natural := Scan_Open (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "open"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Open;

   function Parse_Open (P : in out Parser) return Open_Type is
   begin
      Enter (P, 4);
      declare
         R : constant Open_Type := Body_Of_Open (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Open;

   function Body_Of_Close (P : in out Parser) return Close_Type is
   R : Close_Type;
   begin
      declare
         N : constant Natural := Scan_Close (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "close"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Close;

   function Parse_Close (P : in out Parser) return Close_Type is
   begin
      Enter (P, 5);
      declare
         R : constant Close_Type := Body_Of_Close (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Close;

   function Body_Of_Tag (P : in out Parser) return Tag_Type is
   R : Tag_Type;
   begin
      declare
         N : constant Natural := Scan_Tag (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "tag"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Tag;

   function Parse_Tag (P : in out Parser) return Tag_Type is
   begin
      Enter (P, 6);
      declare
         R : constant Tag_Type := Body_Of_Tag (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Tag;

   function Body_Of_Text (P : in out Parser) return Text_Type is
   R : Text_Type;
   Save : Natural;
   begin
      declare
         N : constant Natural := Scan_Text (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "text"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Text;

   function Parse_Text (P : in out Parser) return Text_Type is
   begin
      Enter (P, 16);
      declare
         R : constant Text_Type := Body_Of_Text (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Text;

   function Body_Of_Lone (P : in out Parser) return Lone_Type is
   R : Lone_Type;
   begin
      Expect_Lit (P, "{"); if P.Failed then return R; end if;
      declare
         Sv  : constant Parser := P;
         Hit : Boolean := False;
         Ok  : Boolean;
      begin
         if not Hit then
            Ok := True;  P.Pos := Sv.Pos;
            if Ok then declare N : constant Natural := Scan_Any (P.Text.all, P.Pos, Limit (P)); begin if N > 0 then P.Pos := P.Pos + N; else Ok := False; end if; end; end if;
            if Ok then Hit := True; end if;
         end if;
         P := Sv;
         if Hit then Fail (P, "something other than any"); return R; end if;
      end;
      return R;
   end Body_Of_Lone;

   function Parse_Lone (P : in out Parser) return Lone_Type is
   begin
      Enter (P, 17);
      declare
         R : constant Lone_Type := Body_Of_Lone (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Lone;

   function Body_Of_Any (P : in out Parser) return Any_Type is
   R : Any_Type;
   begin
      declare
         N : constant Natural := Scan_Any (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "any"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Any;

   function Parse_Any (P : in out Parser) return Any_Type is
   begin
      Enter (P, 18);
      declare
         R : constant Any_Type := Body_Of_Any (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Any;

   function Body_Of_Word (P : in out Parser) return Word_Type is
   R : Word_Type;
   begin
      declare
         N : constant Natural := Scan_Word (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "a word"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Word;

   function Parse_Word (P : in out Parser) return Word_Type is
   begin
      Enter (P, 23);
      declare
         R : constant Word_Type := Body_Of_Word (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Word;

   function Body_Of_Int (P : in out Parser) return Int_Type is
   R : Int_Type;
   begin
      declare
         N : constant Natural := Scan_Int (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "a int"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Int;

   function Parse_Int (P : in out Parser) return Int_Type is
   begin
      Enter (P, 24);
      declare
         R : constant Int_Type := Body_Of_Int (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Int;

   function Body_Of_Str (P : in out Parser) return Str_Type is
   R : Str_Type;
   begin
      declare
         N : constant Natural := Scan_Str (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "a str"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Str;

   function Parse_Str (P : in out Parser) return Str_Type is
   begin
      Enter (P, 25);
      declare
         R : constant Str_Type := Body_Of_Str (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Str;

   function Body_Of_Ws (P : in out Parser) return Ws_Type is
   R : Ws_Type;
   begin
      declare
         N : constant Natural := Scan_Ws (P.Text.all, P.Pos, Limit (P));
      begin
         if N = 0 then Fail (P, "a ws"); return R; end if;
         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));
         P.Pos := P.Pos + N;
         return R;
      end;
   end Body_Of_Ws;

   function Parse_Ws (P : in out Parser) return Ws_Type is
   begin
      Enter (P, 26);
      declare
         R : constant Ws_Type := Body_Of_Ws (P);
      begin
         P.Depth := P.Depth - 1;
         return R;
      end;
   end Parse_Ws;

   function Rule_Name (I : Natural) return String is
     (case I is
        when 1 => "template",
        when 2 => "part",
        when 3 => "block",
        when 4 => "open",
        when 5 => "close",
        when 6 => "tag",
        when 7 => "note",
        when 8 => "unsupported",
        when 9 => "raw",
        when 10 => "triple",
        when 11 => "variable",
        when 12 => "name",
        when 13 => "plain",
        when 14 => "blank",
        when 15 => "body",
        when 16 => "text",
        when 17 => "lone",
        when 18 => "any",
        when 19 => "not-x0-8_B-C_E-1F_21-7C_7E-10FFFF",
        when 20 => "not-x0-8_B-C_E-1F_22_24-25_27-2E_30-3C_3F-5D_5F-7C_7E-10FFFF",
        when 21 => "not-x0-7C_7E-10FFFF",
        when 22 => "not-x0-7A_7C-10FFFF",
        when 23 => "word",
        when 24 => "int",
        when 25 => "str",
        when 26 => "ws",
        when others => "");
   
   function Render (P : Parser) return String is
      At_Pos : constant Natural := P.Err_Pos;
      Last   : constant Natural := P.Text'Last;
      At_End : constant Boolean := At_Pos > Last;
      Line   : Natural := 1;
      Col    : Natural := 1;
      Start  : Natural := 1;
      Msg    : Unbounded_String;
   
      function Img (N : Natural) return String is
         S : constant String := Natural'Image (N);
      begin
         return S (S'First + 1 .. S'Last);
      end Img;
   begin
      for I in 1 .. Natural'Min (At_Pos, Last + 1) - 1 loop
         if P.Text (I) = ASCII.LF then
            Line := Line + 1;
            Col := 1;
            Start := I + 1;
         else
            Col := Col + 1;
         end if;
      end loop;
      Append (Msg, Img (Line) & ":" & Img (Col) & ":" & Img (At_Pos - 1) & ": expected ");
      if P.Alt_N > 1 then
         Append (Msg, "one of ");
      end if;
      for I in 1 .. P.Alt_N loop
         if I > 1 then
            Append (Msg, ", ");
         end if;
         Append (Msg, P.Alts (I));
      end loop;
      if P.More then
         Append (Msg, ", ...");
      end if;
      Append (Msg, ", found " & Found (P, At_Pos));
      declare
         Stop : Natural := Start;
      begin
         while Stop <= Last and then P.Text (Stop) /= ASCII.LF loop
            Stop := Stop + 1;
         end loop;
         declare
            W   : constant Natural := Col - 1;
            Pad : constant String :=
              (if W <= Spaces'Length then Spaces (1 .. W) else Spaces);
         begin
            Append (Msg, ASCII.LF & "  " & P.Text (Start .. Stop - 1)
              & ASCII.LF & "  " & Pad & "^");
         end;
      end;
      for K in reverse 1 .. P.Err_Depth loop
         declare
            Nm : constant String := Rule_Name (P.Err_Stk (K));
            Sp : Natural := P.Err_Stkpos (K);
            L  : Natural := 1;
            Ls : Natural := 1;
            Le : Natural;
         begin
            if Nm'Length > 0 then
               while Sp <= Last and then P.Text (Sp) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR loop
                  Sp := Sp + 1;
               end loop;
               for I in 1 .. Natural'Min (Sp, Last + 1) - 1 loop
                  if P.Text (I) = ASCII.LF then
                     L := L + 1;
                     Ls := I + 1;
                  end if;
               end loop;
               if L + (if At_End then 1 else 3) <= Line then
                  Le := Ls;
                  while Le <= Last and then P.Text (Le) /= ASCII.LF loop
                     Le := Le + 1;
                  end loop;
                  Append (Msg, ASCII.LF & "  " & Img (L) & ":" & Img (Sp - Ls + 1)
                    & ":" & Img (Sp - 1) & ": "
                    & (if At_End then "the " else "inside the ") & Nm
                    & " that begins here" & (if At_End then " is not finished:" else ":")
                    & ASCII.LF & "  " & P.Text (Ls .. Le - 1) & ASCII.LF & "  "
                    & (if Sp - Ls <= Spaces'Length then Spaces (1 .. Sp - Ls) else Spaces)
                    & "^");
                  exit;
               end if;
            end if;
         end;
      end loop;
      return To_String (Msg);
   end Render;
   
   function Parse_Text (Text : String) return Template_Type is
      --  A 1-based copy: positions are indexes into it, wherever the
      --  caller's string starts.
      function Rebase (S : String) return String is
         R : String (1 .. S'Length);
      begin
         R := S;
         return R;
      end Rebase;

      T : aliased constant String := Rebase (Text);
      P : Parser := (Text => T'Unchecked_Access, Pos => 1, Last => Natural'Last, others => <>);
      R : Template_Type;
   begin
      begin
         R := Parse_Template (P);
         if P.Failed then
            raise Parse_Error with Render (P);
         end if;
         if P.Pos <= T'Last then
            Fail (P, "end of config");
            raise Parse_Error with Render (P);
         end if;
      end;
      return R;
   end Parse_Text;

end HBNF_Template_Syntax.Parser;

