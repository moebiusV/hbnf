pragma Ada_2022;

with Ada.Containers;

package body HBNF is

   --  Lexer ----------------------------------------------------------------

   type Token_Kind is
     (Word, Str, Int, Dec, Comment, Eol_Comment,
      LBrace, RBrace, Semicolon, Newline, Eof);

   type Token is record
      Kind : Token_Kind;
      Line : Positive;
      Col  : Positive;
      Text : Unbounded_String;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors (Positive, Token);

   type Lex_Result (Success : Boolean := True) is record
      case Success is
         when True =>
            Tokens : Token_Vectors.Vector;
         when False =>
            Line : Positive;
            Col  : Positive;
            Msg  : Unbounded_String;
      end case;
   end record;

   function Lex_Error (L, C : Positive; M : String) return Lex_Result is
   begin
      return (Success => False, Line => L, Col => C,
              Msg => To_Unbounded_String (M));
   end Lex_Error;

   function Is_Integer (S : String) return Boolean is
      J : Natural := S'First;
   begin
      if S'Length = 0 then
         return False;
      end if;
      if S (J) = '+' or else S (J) = '-' then
         J := J + 1;
         if J > S'Last then
            return False;
         end if;
      end if;
      for K in J .. S'Last loop
         if S (K) not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Integer;

   function Is_Decimal (S : String) return Boolean is
      J         : Natural := S'First;
      Has_Digit : Boolean := False;
      Has_Dot   : Boolean := False;
      Has_Exp   : Boolean := False;
   begin
      if S'Length = 0 then
         return False;
      end if;
      if S (J) = '+' or else S (J) = '-' then
         J := J + 1;
         if J > S'Last then
            return False;
         end if;
      end if;
      while J <= S'Last and then S (J) in '0' .. '9' loop
         Has_Digit := True;
         J := J + 1;
      end loop;
      if J <= S'Last and then S (J) = '.' then
         Has_Dot := True;
         J := J + 1;
         while J <= S'Last and then S (J) in '0' .. '9' loop
            Has_Digit := True;
            J := J + 1;
         end loop;
      end if;
      if J <= S'Last and then (S (J) = 'e' or else S (J) = 'E') then
         Has_Exp := True;
         J := J + 1;
         if J <= S'Last and then (S (J) = '+' or else S (J) = '-') then
            J := J + 1;
         end if;
         if J > S'Last or else S (J) not in '0' .. '9' then
            return False;
         end if;
         while J <= S'Last and then S (J) in '0' .. '9' loop
            Has_Digit := True;
            J := J + 1;
         end loop;
      end if;
      return J > S'Last and then Has_Digit and then (Has_Dot or Has_Exp);
   end Is_Decimal;

   function Trim (S : String) return String is
      First : Natural := S'First;
      Last  : Natural := S'Last;
   begin
      while First <= Last
        and then (S (First) = ' ' or else S (First) = Character'Val (9))
      loop
         First := First + 1;
      end loop;
      while Last >= First
        and then (S (Last) = ' ' or else S (Last) = Character'Val (9))
      loop
         Last := Last - 1;
      end loop;
      if First > Last then
         return "";
      end if;
      return S (First .. Last);
   end Trim;

   --  The value of a hexadecimal digit, or -1 when C is not one.
   function Hex_Digit (C : Character) return Integer is
   begin
      if C in '0' .. '9' then
         return Character'Pos (C) - Character'Pos ('0');
      elsif C in 'a' .. 'f' then
         return Character'Pos (C) - Character'Pos ('a') + 10;
      elsif C in 'A' .. 'F' then
         return Character'Pos (C) - Character'Pos ('A') + 10;
      else
         return -1;
      end if;
   end Hex_Digit;

   --  The hexadecimal digit for N in 0 .. 15.
   function Hex_Char (N : Natural) return Character is
      H : constant String := "0123456789ABCDEF";
   begin
      return H (N + 1);
   end Hex_Char;

   --  Append Code as UTF-8 bytes (the C23 universal-character-name encoding).
   procedure Put_Utf8 (B : in out Unbounded_String; Code : Natural) is
   begin
      if Code <= 16#7F# then
         Append (B, Character'Val (Code));
      elsif Code <= 16#7FF# then
         Append (B, Character'Val (16#C0# + Code / 64));
         Append (B, Character'Val (16#80# + Code mod 64));
      elsif Code <= 16#FFFF# then
         Append (B, Character'Val (16#E0# + Code / 4096));
         Append (B, Character'Val (16#80# + (Code / 64) mod 64));
         Append (B, Character'Val (16#80# + Code mod 64));
      else
         Append (B, Character'Val (16#F0# + Code / 262144));
         Append (B, Character'Val (16#80# + (Code / 4096) mod 64));
         Append (B, Character'Val (16#80# + (Code / 64) mod 64));
         Append (B, Character'Val (16#80# + Code mod 64));
      end if;
   end Put_Utf8;

   function Tokenize (Text : String) return Lex_Result is
      Tokens : Token_Vectors.Vector := Token_Vectors.Empty_Vector;
      I      : Natural := Text'First;
      Line   : Positive := 1;
      Col    : Positive := 1;
      C      : Character;
      On_Line : Boolean := False;
   begin
      while I <= Text'Last loop
         C := Text (I);
         if C = ' ' or else C = Character'Val (9) then
            I := I + 1;
            Col := Col + 1;
         elsif C = Character'Val (10) then
            Tokens.Append (Token'(Newline, Line, Col, Null_Unbounded_String));
            I := I + 1;
            Line := Line + 1;
            Col := 1;
            On_Line := False;
         elsif C = Character'Val (13) then
            I := I + 1;
            Col := Col + 1;
         elsif C = '#' then
            declare
               Start_Line : constant Positive := Line;
               Start_Col  : constant Positive := Col;
               Buf        : Unbounded_String := Null_Unbounded_String;
               Kind       : constant Token_Kind :=
                 (if On_Line then Eol_Comment else Comment);
            begin
               I := I + 1;
               Col := Col + 1;
               while I <= Text'Last
                 and then Text (I) /= Character'Val (10)
               loop
                  Append (Buf, Text (I));
                  I := I + 1;
                  Col := Col + 1;
               end loop;
               Tokens.Append
                 (Token'(Kind, Start_Line, Start_Col,
                         To_Unbounded_String (Trim (To_String (Buf)))));
            end;
         elsif C = '{' then
            Tokens.Append (Token'(LBrace, Line, Col, Null_Unbounded_String));
            I := I + 1;
            Col := Col + 1;
            On_Line := True;
         elsif C = '}' then
            Tokens.Append (Token'(RBrace, Line, Col, Null_Unbounded_String));
            I := I + 1;
            Col := Col + 1;
            On_Line := True;
         elsif C = ';' then
            Tokens.Append
              (Token'(Semicolon, Line, Col, Null_Unbounded_String));
            I := I + 1;
            Col := Col + 1;
            On_Line := True;
         elsif C = '"' then
            declare
               Start_Col : constant Positive := Col;
               Buf       : Unbounded_String := Null_Unbounded_String;
               Closed    : Boolean := False;
            begin
               I := I + 1;
               Col := Col + 1;
               while I <= Text'Last loop
                  C := Text (I);
                  if C = '"' then
                     I := I + 1;
                     Col := Col + 1;
                     Closed := True;
                     exit;
                  elsif C = '\' then
                     I := I + 1;
                     Col := Col + 1;
                     if I > Text'Last then
                        return Lex_Error (Line, Col, "escape at end of file");
                     end if;
                     --  Decode one C23 escape sequence (I indexes its first
                     --  character).  The multi-character branches advance I
                     --  and Col past the whole sequence themselves.
                     case Text (I) is
                        when 'x' =>
                           declare
                              Val : Natural := 0;
                              N   : Natural := 0;
                           begin
                              I := I + 1;
                              Col := Col + 1;
                              while I <= Text'Last
                                and then Hex_Digit (Text (I)) >= 0
                              loop
                                 Val := Val * 16 + Hex_Digit (Text (I));
                                 N := N + 1;
                                 I := I + 1;
                                 Col := Col + 1;
                              end loop;
                              if N = 0 then
                                 return Lex_Error
                                   (Line, Col, "hex escape needs a digit");
                              end if;
                              if Val > 255 then
                                 return Lex_Error
                                   (Line, Col, "hex escape out of range");
                              end if;
                              Append (Buf, Character'Val (Val));
                           end;
                        when 'u' | 'U' =>
                           declare
                              Hex_Len : constant Natural :=
                                (if Text (I) = 'u' then 4 else 8);
                              Code : Natural := 0;
                           begin
                              I := I + 1;
                              Col := Col + 1;
                              for K in 1 .. Hex_Len loop
                                 if I > Text'Last
                                   or else Hex_Digit (Text (I)) < 0
                                 then
                                    return Lex_Error
                                      (Line, Col, "bad unicode escape");
                                 end if;
                                 Code := Code * 16 + Hex_Digit (Text (I));
                                 I := I + 1;
                                 Col := Col + 1;
                              end loop;
                              if Code > 16#10FFFF# then
                                 return Lex_Error
                                   (Line, Col, "unicode escape out of range");
                              end if;
                              Put_Utf8 (Buf, Code);
                           end;
                        when '0' .. '7' =>
                           declare
                              Val : Natural := 0;
                              N   : Natural := 0;
                           begin
                              while I <= Text'Last and then N < 3
                                and then Text (I) in '0' .. '7'
                              loop
                                 Val := Val * 8
                                   + Character'Pos (Text (I))
                                   - Character'Pos ('0');
                                 N := N + 1;
                                 I := I + 1;
                                 Col := Col + 1;
                              end loop;
                              if Val > 255 then
                                 return Lex_Error
                                   (Line, Col, "octal escape out of range");
                              end if;
                              Append (Buf, Character'Val (Val));
                           end;
                        when others =>
                           --  A one-character escape (or an error).
                           declare
                              Ch : Character;
                           begin
                              case Text (I) is
                                 when 'a' => Ch := Character'Val (7);
                                 when 'b' => Ch := Character'Val (8);
                                 when 'f' => Ch := Character'Val (12);
                                 when 'n' => Ch := Character'Val (10);
                                 when 'r' => Ch := Character'Val (13);
                                 when 't' => Ch := Character'Val (9);
                                 when 'v' => Ch := Character'Val (11);
                                 when ''' => Ch := ''';
                                 when '"' => Ch := '"';
                                 when '?' => Ch := '?';
                                 when '\' => Ch := '\';
                                 when others =>
                                    return Lex_Error
                                      (Line, Col,
                                       "unknown escape in string");
                              end case;
                              Append (Buf, Ch);
                              I := I + 1;
                              Col := Col + 1;
                           end;
                     end case;
                  elsif C = Character'Val (10) then
                     return Lex_Error (Line, Col, "newline in string literal");
                  else
                     Append (Buf, C);
                     I := I + 1;
                     Col := Col + 1;
                  end if;
               end loop;
               if not Closed then
                  return Lex_Error (Line, Col, "unterminated string literal");
               end if;
               Tokens.Append (Token'(Str, Line, Start_Col, Buf));
               On_Line := True;
            end;
         elsif C = '\' then
            --  Backslash outside a string: backslash-newline is a line
            --  continuation (parse.y's lgetc); a backslash before any other
            --  character is consumed and dropped.
            I := I + 1;
            Col := Col + 1;
            if I <= Text'Last and then Text (I) = Character'Val (10) then
               I := I + 1;
               Line := Line + 1;
               Col := 1;
            end if;
         else
            declare
               Start_Col : constant Positive := Col;
               Buf       : Unbounded_String := Null_Unbounded_String;
            begin
               while I <= Text'Last loop
                  C := Text (I);
                  exit when C = ' ' or else C = Character'Val (9)
                    or else C = Character'Val (10)
                    or else C = Character'Val (13)
                    or else C = '{' or else C = '}'
                    or else C = '"' or else C = '#';
                  if C = '\' then
                     --  backslash-newline continues the word across the
                     --  line; a backslash before any other char is dropped.
                     I := I + 1;
                     Col := Col + 1;
                     if I <= Text'Last
                       and then Text (I) = Character'Val (10)
                     then
                        I := I + 1;
                        Line := Line + 1;
                        Col := 1;
                     end if;
                  else
                     Append (Buf, C);
                     I := I + 1;
                     Col := Col + 1;
                  end if;
               end loop;
               declare
                  W : constant String := To_String (Buf);
               begin
                  if Is_Integer (W) then
                     Tokens.Append (Token'(Int, Line, Start_Col, Buf));
                  elsif Is_Decimal (W) then
                     Tokens.Append (Token'(Dec, Line, Start_Col, Buf));
                  else
                     Tokens.Append (Token'(Word, Line, Start_Col, Buf));
                  end if;
                  On_Line := True;
               end;
            end;
         end if;
      end loop;
      Tokens.Append (Token'(Eof, Line, Col, Null_Unbounded_String));
      return (Success => True, Tokens => Tokens);
   end Tokenize;

   --  Parser ---------------------------------------------------------------

   function Parse (Text : String) return Parse_Result is

      Parse_Error : exception;

      L      : constant Lex_Result := Tokenize (Text);
      Err_L  : Positive := 1;
      Err_C  : Positive := 1;
      Err_M  : Unbounded_String := Null_Unbounded_String;
      Tokens : Token_Vectors.Vector := Token_Vectors.Empty_Vector;

      procedure Fail (L, C : Positive; M : String) with No_Return is
      begin
         Err_L := L;
         Err_C := C;
         Err_M := To_Unbounded_String (M);
         raise Parse_Error;
      end Fail;

      function Parse_Value (T : Token) return HBNF.Value is
         V : HBNF.Value;
      begin
         V.Line := T.Line;
         V.Col  := T.Col;
         case T.Kind is
            when Word =>
               V.Kind := Word;
               V.Text := T.Text;
            when Str =>
               V.Kind := Str;
               V.Text := T.Text;
            when Int =>
               V.Kind := Int;
               V.Num := Long_Long_Integer'Value (To_String (T.Text));
            when Dec =>
               V.Kind := Dec;
               V.Text := T.Text;
               begin
                  V.Dec := Decimal'Value (To_String (T.Text));
               exception
                  when Constraint_Error =>
                     Fail (T.Line, T.Col, "decimal out of range");
               end;
            when others =>
               Fail (T.Line, T.Col, "internal: unexpected value token");
         end case;
         return V;
      end Parse_Value;

      procedure Parse_Entry
        (Parent : Node_Access; I : in out Positive;
         Leading : Unbounded_String);
      procedure Parse_Children
        (Parent : Node_Access; I : in out Positive; At_Top : Boolean);
      procedure Parse_Comment
        (Parent : Node_Access; Text : String; L, C : Positive);

      procedure Parse_Entry
        (Parent : Node_Access; I : in out Positive;
         Leading : Unbounded_String) is
         N : constant Node_Access := new Node;
      begin
         N.Leading_Comment := Leading;
         N.Kind := Directive;
         N.Name := Tokens (I).Text;
         N.Line := Tokens (I).Line;
         N.Col  := Tokens (I).Col;
         I := I + 1;
         loop
            exit when I > Tokens.Last_Index;
            case Tokens (I).Kind is
               when Word | Str | Int | Dec =>
                  N.Values.Append (Parse_Value (Tokens (I)));
                  I := I + 1;
               when LBrace =>
                  N.Kind := Block;
                  if not N.Values.Is_Empty
                    and then (N.Values.First_Element.Kind = Word
                              or else N.Values.First_Element.Kind = Str)
                  then
                     N.Qualifier := N.Values.First_Element.Text;
                  end if;
                  I := I + 1;
                  Parse_Children (N, I, False);
                  exit;
               when others =>
                  exit;
            end case;
         end loop;
         --  A `;` terminates the entry (vs the newline the caller skips); an
         --  end-of-line comment may still follow the terminator.
         if I <= Tokens.Last_Index and then Tokens (I).Kind = Semicolon then
            N.Semicolon_After := True;
            I := I + 1;
         end if;
         if I <= Tokens.Last_Index and then Tokens (I).Kind = Eol_Comment then
            N.Trailing_Comment := Tokens (I).Text;
            I := I + 1;
         end if;
         Parent.Children.Append (N);
      end Parse_Entry;

      procedure Parse_Comment
        (Parent : Node_Access; Text : String; L, C : Positive) is
         N : constant Node_Access := new Node;
      begin
         N.Kind := Comment;
         N.Name := To_Unbounded_String (Text);
         N.Line := L;
         N.Col  := C;
         Parent.Children.Append (N);
      end Parse_Comment;

      procedure Parse_Children
        (Parent : Node_Access; I : in out Positive; At_Top : Boolean) is
         Leading    : Unbounded_String := Null_Unbounded_String;
         Seen_Entry : Boolean := False;

         procedure Flush_Leading is
            Txt   : constant String := To_String (Leading);
            Start : Natural := Txt'First;
         begin
            if Leading /= Null_Unbounded_String then
               for K in Txt'Range loop
                  if Txt (K) = Character'Val (10) then
                     Parse_Comment (Parent, Txt (Start .. K - 1),
                                    Tokens (I).Line, Tokens (I).Col);
                     Start := K + 1;
                  end if;
               end loop;
               Parse_Comment (Parent, Txt (Start .. Txt'Last),
                              Tokens (I).Line, Tokens (I).Col);
               Leading := Null_Unbounded_String;
            end if;
         end Flush_Leading;
      begin
         loop
            exit when I > Tokens.Last_Index;
            if Tokens (I).Kind = Newline then
               --  Newlines separate entries but never detach a comment block
               --  from the entry that follows it (whitespace is fine).
               I := I + 1;
            elsif Tokens (I).Kind = RBrace then
               Flush_Leading;
               if At_Top then
                  Fail (Tokens (I).Line, Tokens (I).Col, "unexpected '}'");
               end if;
               I := I + 1;
               exit;
            elsif Tokens (I).Kind = Eof then
               Flush_Leading;
               if At_Top then
                  exit;
               end if;
               Fail (Tokens (I).Line, Tokens (I).Col, "unterminated block");
            elsif Tokens (I).Kind = Comment
              or else Tokens (I).Kind = Eol_Comment
            then
               if Leading /= Null_Unbounded_String then
                  Append (Leading, Character'Val (10));
               end if;
               Append (Leading, Tokens (I).Text);
               I := I + 1;
            elsif Tokens (I).Kind = Word then
               if At_Top and then not Seen_Entry
                 and then Leading /= Null_Unbounded_String
               then
                  --  A comment block before the first directive is the file
                  --  header: it applies to the whole file, so keep it as a
                  --  standalone comment rather than the first entry's leader.
                  Flush_Leading;
               end if;
               Parse_Entry (Parent, I, Leading);
               Seen_Entry := True;
               Leading := Null_Unbounded_String;
            else
               Fail (Tokens (I).Line, Tokens (I).Col,
                     "expected directive name, found '" &
                     To_String (Tokens (I).Text) & "'");
            end if;
         end loop;
      end Parse_Children;

      Root : constant Node_Access := new Node;
      Idx  : Positive := 1;
   begin
      if not L.Success then
         return (Success => False, Line => L.Line, Col => L.Col, Msg => L.Msg);
      end if;
      Tokens := L.Tokens;
      Root.Kind := Block;
      Root.Line := 1;
      Root.Col  := 1;
      Parse_Children (Root, Idx, True);
      return (Success => True, Root => Root);
   exception
      when Parse_Error =>
         return (Success => False, Line => Err_L, Col => Err_C, Msg => Err_M);
   end Parse;

   --  Accessors ------------------------------------------------------------

   function Children (N : Node) return Node_Vectors.Vector is (N.Children);

   function Find (N : Node; Name : String) return Node_Access is
   begin
      for C of N.Children loop
         if C /= null and then C.Kind /= Comment
           and then To_String (C.Name) = Name
         then
            return C;
         end if;
      end loop;
      return null;
   end Find;

   function Find_All (N : Node; Name : String) return Node_Vectors.Vector is
      R : Node_Vectors.Vector := Node_Vectors.Empty_Vector;
   begin
      for C of N.Children loop
         if C /= null and then C.Kind /= Comment
           and then To_String (C.Name) = Name
         then
            R.Append (C);
         end if;
      end loop;
      return R;
   end Find_All;

   function Value_Count (N : Node) return Natural is
     (Natural (N.Values.Length));

   function Value_At (N : Node; Index : Positive) return HBNF.Value is
     (N.Values.Element (Index));

   function As_Text (V : Value) return String is (To_String (V.Text));

   function As_Integer (V : Value) return Long_Long_Integer is (V.Num);

   function As_Decimal (V : Value) return Decimal is (V.Dec);

   function Print (Root : Node_Access) return String is

      Indent_Step : constant := 3;

      function Spaces (N : Natural) return String is
         S : constant String (1 .. N) := [others => ' '];
      begin
         return S;
      end Spaces;

      function Escape (S : String) return String is
         Buf : Unbounded_String := Null_Unbounded_String;
      begin
         for C of S loop
            case C is
               when '"' => Append (Buf, "\""");
               when '\' => Append (Buf, "\\");
               when Character'Val (7)  => Append (Buf, "\a");
               when Character'Val (8)  => Append (Buf, "\b");
               when Character'Val (9)  => Append (Buf, "\t");
               when Character'Val (10) => Append (Buf, "\n");
               when Character'Val (11) => Append (Buf, "\v");
               when Character'Val (12) => Append (Buf, "\f");
               when Character'Val (13) => Append (Buf, "\r");
               when others =>
                  if C < Character'Val (32)
                    or else C = Character'Val (127)
                  then
                     Append (Buf, "\x");
                     Append (Buf, Hex_Char (Character'Pos (C) / 16));
                     Append (Buf, Hex_Char (Character'Pos (C) mod 16));
                  else
                     Append (Buf, C);
                  end if;
            end case;
         end loop;
         return To_String (Buf);
      end Escape;

      function Value_Text (V : Value) return String is
      begin
         case V.Kind is
            when Word => return To_String (V.Text);
            when Str  => return '"' & Escape (To_String (V.Text)) & '"';
            when Int  =>
               declare
                  S : constant String := Long_Long_Integer'Image (V.Num);
               begin
                  if S (S'First) = ' ' then
                     return S (S'First + 1 .. S'Last);
                  else
                     return S;
                  end if;
               end;
            when Dec  => return To_String (V.Text);
         end case;
      end Value_Text;

      function Comment_Block (Indent : Natural; Text : String) return String is
         Buf   : Unbounded_String := Null_Unbounded_String;
         Start : Natural := Text'First;
      begin
         for K in Text'Range loop
            if Text (K) = Character'Val (10) then
               Append (Buf, Spaces (Indent));
               Append (Buf, '#');
               if K - 1 >= Start then
                  Append (Buf, ' ');
                  Append (Buf, Text (Start .. K - 1));
               end if;
               Append (Buf, Character'Val (10));
               Start := K + 1;
            end if;
         end loop;
         Append (Buf, Spaces (Indent));
         Append (Buf, '#');
         if Start <= Text'Last then
            Append (Buf, ' ');
            Append (Buf, Text (Start .. Text'Last));
         end if;
         Append (Buf, Character'Val (10));
         return To_String (Buf);
      end Comment_Block;

      function Node_Text (N : Node; Indent : Natural) return String is
         Buf : Unbounded_String := To_Unbounded_String (Spaces (Indent));
      begin
         if N.Kind = Comment then
            Append (Buf, '#');
            if To_String (N.Name) /= "" then
               Append (Buf, ' ');
               Append (Buf, To_String (N.Name));
            end if;
            Append (Buf, Character'Val (10));
            return To_String (Buf);
         end if;
         if N.Leading_Comment /= Null_Unbounded_String then
            Append (Buf,
                    Comment_Block (Indent, To_String (N.Leading_Comment)));
         end if;
         Append (Buf, To_String (N.Name));
         for V of N.Values loop
            Append (Buf, ' ');
            Append (Buf, Value_Text (V));
         end loop;
         if N.Kind = Block then
            Append (Buf, " {");
            Append (Buf, Character'Val (10));
            for C of N.Children loop
               Append (Buf, Node_Text (C.all, Indent + Indent_Step));
            end loop;
            Append (Buf, Spaces (Indent));
            Append (Buf, '}');
         end if;
         if N.Semicolon_After then
            Append (Buf, ";");
         end if;
         if N.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " #");
            if To_String (N.Trailing_Comment) /= "" then
               Append (Buf, ' ');
               Append (Buf, To_String (N.Trailing_Comment));
            end if;
         end if;
         Append (Buf, Character'Val (10));
         return To_String (Buf);
      end Node_Text;

      Buf : Unbounded_String := Null_Unbounded_String;
   begin
      if Root /= null then
         for C of Root.Children loop
            Append (Buf, Node_Text (C.all, 0));
         end loop;
      end if;
      return To_String (Buf);
   end Print;

end HBNF;
