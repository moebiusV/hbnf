pragma Ada_2022;

package body ASTBNF is

   --  ====================================================================
   --  Lexer
   --  ====================================================================

   type Tok_Kind is (T_Name, T_String, T_Number, T_Eq, T_Slash, T_LParen,
                     T_RParen, T_LBrack, T_RBrack, T_Star,
                     T_Comment, T_Newline, T_EOF);

   type Token is record
      Kind : Tok_Kind;
      Line : Positive         := 1;
      Col  : Positive         := 1;
      Text : Unbounded_String := Null_Unbounded_String;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors (Positive, Token);

   function Trim (S : String) return String is
      First : Natural := S'First;
      Last  : Natural := S'Last;
   begin
      while First <= Last
        and then (S (First) = ' ' or else S (First) = ASCII.HT)
      loop
         First := First + 1;
      end loop;
      while Last >= First
        and then (S (Last) = ' ' or else S (Last) = ASCII.HT)
      loop
         Last := Last - 1;
      end loop;
      if First > Last then
         return "";
      end if;
      return S (First .. Last);
   end Trim;

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

   function Lex (Text : String) return Token_Vectors.Vector is
      Toks : Token_Vectors.Vector;
      I    : Natural  := Text'First;
      Line : Positive := 1;
      Col  : Positive := 1;

      procedure Emit (K : Tok_Kind; S : String := "") is
      begin
         Token_Vectors.Append
           (Toks, Token'(K, Line, Col, To_Unbounded_String (S)));
      end Emit;

      function Name_Start (C : Character) return Boolean is
         ((C in 'a' .. 'z') or (C in 'A' .. 'Z') or C = '_');

      function Name_Char (C : Character) return Boolean is
         (Name_Start (C) or (C in '0' .. '9') or C = '-');

   begin
      while I <= Text'Last loop
         case Text (I) is
            when ' ' | ASCII.HT =>
               I := I + 1;  Col := Col + 1;
            when ASCII.LF =>
               Emit (T_Newline);  I := I + 1;  Line := Line + 1;  Col := 1;
            when ASCII.CR =>
               I := I + 1;
            when ';' =>
               declare
                  CL    : constant Positive := Line;
                  CC    : constant Positive := Col;
                  Start : constant Positive := I + 1;
               begin
                  I := I + 1;
                  while I <= Text'Last and then Text (I) /= ASCII.LF loop
                     I := I + 1;
                  end loop;
                  Token_Vectors.Append
                    (Toks, Token'(T_Comment, CL, CC,
                                  To_Unbounded_String
                                    (Trim (Text (Start .. I - 1)))));
               end;
            when '"' =>
               declare
                  Buf    : Unbounded_String := Null_Unbounded_String;
                  Closed : Boolean := False;
               begin
                  I := I + 1;
                  Col := Col + 1;
                  while I <= Text'Last loop
                     if Text (I) = '"' then
                        I := I + 1;
                        Col := Col + 1;
                        Closed := True;
                        exit;
                     elsif Text (I) = '\' then
                        --  Decode a C-style escape: "\n" is the newline token
                        --  and "\xHH" any byte.
                        I := I + 1;
                        Col := Col + 1;
                        if I > Text'Last then
                           raise Parse_Error with
                             Integer'Image (Line) & ":" & Integer'Image (Col) &
                             ": escape at end of string";
                        end if;
                        if Text (I) = 'x' then
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
                              if N = 0 or else Val > 255 then
                                 raise Parse_Error with
                                   Integer'Image (Line) & ":" &
                                   Integer'Image (Col) & ": bad hex escape";
                              end if;
                              Append (Buf, Character'Val (Val));
                           end;
                        else
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
                                 when '\' => Ch := '\';
                                 when '"' => Ch := '"';
                                 when ''' => Ch := ''';
                                 when others =>
                                    raise Parse_Error with
                                      Integer'Image (Line) & ":" &
                                      Integer'Image (Col) &
                                      ": unknown escape '" & Text (I) & "'";
                              end case;
                              Append (Buf, Ch);
                              I := I + 1;
                              Col := Col + 1;
                           end;
                        end if;
                     else
                        Append (Buf, Text (I));
                        I := I + 1;
                        Col := Col + 1;
                     end if;
                  end loop;
                  if not Closed then
                     raise Parse_Error with
                       Integer'Image (Line) & ":" & Integer'Image (Col) &
                       ": unterminated string literal";
                  end if;
                  Emit (T_String, To_String (Buf));
               end;
            when '=' => Emit (T_Eq);     I := I + 1;  Col := Col + 1;
            when '/' => Emit (T_Slash);  I := I + 1;  Col := Col + 1;
            when '(' => Emit (T_LParen); I := I + 1;  Col := Col + 1;
            when ')' => Emit (T_RParen); I := I + 1;  Col := Col + 1;
            when '[' => Emit (T_LBrack); I := I + 1;  Col := Col + 1;
            when ']' => Emit (T_RBrack); I := I + 1;  Col := Col + 1;
            when '*' => Emit (T_Star);   I := I + 1;  Col := Col + 1;
            when '0' .. '9' =>
               declare
                  Start : constant Positive := I;
               begin
                  while I <= Text'Last and then Text (I) in '0' .. '9' loop
                     I := I + 1;
                  end loop;
                  Emit (T_Number, Text (Start .. I - 1));
                  Col := Col + (I - Start);
               end;
            when others =>
               if Name_Start (Text (I)) then
                  declare
                     Start : constant Positive := I;
                  begin
                     while I <= Text'Last and then Name_Char (Text (I)) loop
                        I := I + 1;
                     end loop;
                     Emit (T_Name, Text (Start .. I - 1));
                     Col := Col + (I - Start);
                  end;
               else
                  raise Parse_Error with
                    Integer'Image (Line) & ":" & Integer'Image (Col) &
                    ": unexpected character '" & Text (I) & "'";
               end if;
         end case;
      end loop;
      Emit (T_EOF);
      return Toks;
   end Lex;

   --  ====================================================================
   --  Parser
   --  ====================================================================

   type Parser is record
      Toks : Token_Vectors.Vector;
      Pos  : Positive := 1;
   end record;

   function Cur (P : Parser) return Token is (P.Toks (P.Pos));

   procedure Next (P : in out Parser) is
   begin
      P.Pos := P.Pos + 1;
   end Next;

   procedure Expect (P : in out Parser; K : Tok_Kind; What : String) is
      T : constant Token := Cur (P);
   begin
      if T.Kind /= K then
         raise Parse_Error with
           Integer'Image (T.Line) & ":" & Integer'Image (T.Col) &
           ": expected " & What;
      end if;
      Next (P);
   end Expect;

   function Expect_Name (P : in out Parser) return Unbounded_String is
      T : constant Token := Cur (P);
   begin
      if T.Kind /= T_Name then
         raise Parse_Error with
           Integer'Image (T.Line) & ":" & Integer'Image (T.Col) &
           ": expected a name";
      end if;
      Next (P);
      return T.Text;
   end Expect_Name;

   function Parse_Atom (P : in out Parser) return Element_Access;
   function Parse_Element (P : in out Parser) return Element_Access;
   function Parse_Pattern (P : in out Parser) return Element_Vectors.Vector;
   function Parse_Alternation (P : in out Parser)
     return Element_Vectors.Vector;

   procedure Append_All
     (Dst : in out Element_Vectors.Vector; Src : Element_Vectors.Vector) is
   begin
      for E of Src loop
         Element_Vectors.Append (Dst, E);
      end loop;
   end Append_All;

   function Parse_Atom (P : in out Parser) return Element_Access is
   begin
      case Cur (P).Kind is
         when T_String =>
            declare
               Lit : constant Unbounded_String := Cur (P).Text;
            begin
               Next (P);
               return new Element'(Kind => Literal, Min => 1, Max => 1,
                                   Lit => Lit);
            end;
         when T_Name =>
            declare
               N : constant Unbounded_String := Expect_Name (P);
            begin
               return new Element'
                 (Kind => Name, Min => 1, Max => 1, Name => N);
            end;
         when T_LParen =>
            Next (P);
            declare
               Items : constant Element_Vectors.Vector :=
                 Parse_Alternation (P);
            begin
               Expect (P, T_RParen, "')'");
               return new Element'
                 (Kind => Group, Min => 1, Max => 1, Items => Items);
            end;
         when T_LBrack =>
            Next (P);
            declare
               Items : constant Element_Vectors.Vector :=
                 Parse_Alternation (P);
            begin
               Expect (P, T_RBrack, "']'");
               return new Element'
                 (Kind => Group, Min => 0, Max => 1, Items => Items);
            end;
         when others =>
            declare
               T : constant Token := Cur (P);
            begin
               raise Parse_Error with
                 Integer'Image (T.Line) & ":" & Integer'Image (T.Col) &
                 ": expected a literal, name, or group";
            end;
      end case;
   end Parse_Atom;

   function Parse_Element (P : in out Parser) return Element_Access is
      Min        : Natural := 1;
      Max        : Integer := 1;
      Has_Prefix : Boolean := False;
   begin
      --  ABNF prefix repetition:  *elem, 1*elem, n*melem, nelem.
      if Cur (P).Kind = T_Star then
         Min := 0;  Max := -1;  Has_Prefix := True;  Next (P);
      elsif Cur (P).Kind = T_Number then
         Min := Natural'Value (To_String (Cur (P).Text));  Next (P);
         if Cur (P).Kind = T_Star then
            Next (P);
            if Cur (P).Kind = T_Number then
               Max := Integer'Value (To_String (Cur (P).Text));  Next (P);
            else
               Max := -1;
            end if;
         else
            Max := Min;
         end if;
         Has_Prefix := True;
      end if;

      declare
         E : constant Element_Access := Parse_Atom (P);
      begin
         if Has_Prefix then
            E.Min := Min;  E.Max := Max;
         end if;
         return E;
      end;
   end Parse_Element;

   --  Parse a sequence of elements up to any structural token.  The caller
   --  inspects what stopped it.
   function Parse_Pattern (P : in out Parser) return Element_Vectors.Vector is
      V : Element_Vectors.Vector;
   begin
      loop
         exit when Cur (P).Kind in
           T_Newline | T_RParen | T_RBrack | T_Slash | T_Comment | T_EOF;
         Element_Vectors.Append (V, Parse_Element (P));
      end loop;
      return V;
   end Parse_Pattern;

   --  ABNF "alternation": concatenation *( "/" concatenation ), flattened
   --  with Alt separator elements, used for a group/bracket's inside and a
   --  rule's whole RHS; the caller checks the terminating token.
   function Parse_Alternation (P : in out Parser)
     return Element_Vectors.Vector is
      V : Element_Vectors.Vector;
   begin
      Append_All (V, Parse_Pattern (P));
      while Cur (P).Kind = T_Slash loop
         Next (P);
         Element_Vectors.Append
           (V, new Element'(Kind => Alt, Min => 1, Max => 1));
         Append_All (V, Parse_Pattern (P));
      end loop;
      return V;
   end Parse_Alternation;

   function Parse (Text : String) return Rule_Vectors.Vector is
      P     : Parser := (Toks => Lex (Text), Pos => 1);
      Rules : Rule_Vectors.Vector;
      Name  : Unbounded_String;
   begin
      loop
         while Cur (P).Kind = T_Newline loop
            Next (P);
         end loop;
         exit when Cur (P).Kind = T_EOF;

         declare
            Leading  : Unbounded_String := Null_Unbounded_String;
            Trailing : Unbounded_String := Null_Unbounded_String;
         begin
            --  A leading comment block: `;` comment lines before the rule.
            while Cur (P).Kind = T_Comment loop
               if Leading /= Null_Unbounded_String then
                  Append (Leading, ASCII.LF);
               end if;
               Append (Leading, Cur (P).Text);
               Next (P);
               if Cur (P).Kind = T_Newline then
                  Next (P);
               end if;
            end loop;
            while Cur (P).Kind = T_Newline loop
               Next (P);
            end loop;
            exit when Cur (P).Kind = T_EOF;

            Name := Expect_Name (P);
            Expect (P, T_Eq, "'='");

            declare
               Pattern : constant Element_Vectors.Vector :=
                 Parse_Alternation (P);
            begin
               --  A trailing comment sits on the rule's own line, after the
               --  pattern (Parse_Pattern stops at T_Comment).
               if Cur (P).Kind = T_Comment then
                  Trailing := Cur (P).Text;
                  Next (P);
               end if;
               Rule_Vectors.Append
                 (Rules,
                  Rule'(Name            => Name,
                        Pattern         => Pattern,
                        Leading_Comment => Leading,
                        Trailing_Comment => Trailing));
            end;
         end;
      end loop;
      return Rules;
   end Parse;

end ASTBNF;
