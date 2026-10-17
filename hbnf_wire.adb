pragma Ada_2022;

with Ada.Characters.Handling;
with Ada.Directories;
with Ada.IO_Exceptions;
with HBNF_Grammar;
with Ada.Containers.Vectors;
with Ada.Strings.Fixed;

package body HBNF_Wire is

   use Interfaces;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   ---------------------------------------------------------------------------
   --  Is_Binary
   ---------------------------------------------------------------------------

   function Is_Binary (Text : String) return Boolean is
      K : Natural := Text'First;
   begin
      while K <= Text'Last loop
         declare
            E : Natural := K;
         begin
            while E <= Text'Last and then Text (E) /= ASCII.LF loop
               E := E + 1;
            end loop;
            declare
               Line : constant String := Text (K .. E - 1);
            begin
               if Line'Length >= 6 and then Line (Line'First .. Line'First + 5)
                 = "binary"
               then
                  declare
                     Rest : constant String :=
                       Ada.Strings.Fixed.Trim
                         (Line (Line'First + 6 .. Line'Last),
                          Ada.Strings.Both);
                  begin
                     if Rest = "" or else Rest (Rest'First) = ';'
                       or else (Rest'Length >= 2
                                and then Rest (Rest'First .. Rest'First + 1)
                                  = "/*")
                     then
                        return True;
                     end if;
                  end;
               end if;
            end;
            K := E + 1;
         end;
      end loop;
      return False;
   end Is_Binary;

   ---------------------------------------------------------------------------
   --  Tokens
   ---------------------------------------------------------------------------

   type Tok_Kind is (T_Name, T_Num, T_Str, T_Sym, T_Code, T_EOF);

   type Token is record
      Kind   : Tok_Kind := T_EOF;
      Text   : Unbounded_String;
      Line   : Positive := 1;
      Col    : Positive := 1;
      End_Col : Positive := 1;   --  the column after the token
      Value  : Unsigned_64 := 0;
      Radix  : Positive := 10;
      Ndigits : Natural := 0;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors (Positive, Token);

   function Lex (Text : String; File : String) return Token_Vectors.Vector is
      Toks : Token_Vectors.Vector;
      I    : Natural := Text'First;
      Line : Positive := 1;
      Col  : Positive := 1;

      --  The token just emitted is a name in column 1: a rule's name.  A `:`
      --  right after it is the rule operator (POSIX BNF's); every other `:` is
      --  a width.  A rule's continuation lines are indented, so this is the
      --  only place the operator can be, and no spacing need tell them apart.
      Head : Boolean := False;

      function Where return String is
        ((if File = "" then "" else File & ":") & Img (Line) & ":" & Img (Col));

      function Name_Start (C : Character) return Boolean is
        (C in 'a' .. 'z' | 'A' .. 'Z' | '_');
      function Name_Char (C : Character) return Boolean is
        (Name_Start (C) or else C in '0' .. '9');
      function Digit_Of (C : Character) return Integer is
        (case C is
            when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
            when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
            when 'A' .. 'F' => Character'Pos (C) - Character'Pos ('A') + 10,
            when others     => -1);

      procedure Emit (K : Tok_Kind; S : String; Len : Positive;
                      Value : Unsigned_64 := 0; Radix : Positive := 10;
                      Ndigits : Natural := 0) is
      begin
         Head := K = T_Name and then Col = 1;
         Toks.Append (Token'(Kind => K, Text => To_Unbounded_String (S),
                             Line => Line, Col => Col,
                             End_Col => Col + Len, Value => Value,
                             Radix => Radix, Ndigits => Ndigits));
         I := I + Len;
         Col := Col + Len;
      end Emit;

   begin
      while I <= Text'Last loop
         declare
            C : constant Character := Text (I);
            N : constant Character :=
              (if I < Text'Last then Text (I + 1) else ASCII.NUL);
         begin
            if C = ASCII.LF then
               I := I + 1;  Line := Line + 1;  Col := 1;
            elsif C in ' ' | ASCII.HT | ASCII.CR then
               I := I + 1;  Col := Col + 1;
            elsif C = ';' then
               while I <= Text'Last and then Text (I) /= ASCII.LF loop
                  I := I + 1;
               end loop;
            elsif C = '/' and then N = '*' then
               I := I + 2;  Col := Col + 2;
               loop
                  if I >= Text'Last then
                     raise Wire_Error with
                       Where & ": a `/*` comment is never closed";
                  end if;
                  exit when Text (I) = '*' and then Text (I + 1) = '/';
                  if Text (I) = ASCII.LF then
                     Line := Line + 1;  Col := 1;
                  else
                     Col := Col + 1;
                  end if;
                  I := I + 1;
               end loop;
               I := I + 2;  Col := Col + 2;
            elsif C in '0' .. '9' then
               declare
                  Start : constant Natural := I;
                  Radix : Positive := 10;
                  V     : Unsigned_64 := 0;
                  Ndig  : Natural := 0;
                  J     : Natural := I;
               begin
                  if C = '0' and then N in 'x' | 'X' then
                     Radix := 16;  J := I + 2;
                  elsif C = '0' and then N in 'b' | 'B'
                    and then I + 2 <= Text'Last
                    and then Text (I + 2) in '0' | '1'
                  then
                     Radix := 2;  J := I + 2;
                  end if;
                  while J <= Text'Last
                    and then Digit_Of (Text (J)) in 0 .. Radix - 1
                  loop
                     if V > (Unsigned_64'Last - Unsigned_64 (Digit_Of (Text (J))))
                          / Unsigned_64 (Radix)
                     then
                        raise Wire_Error with
                          Where & ": the number " & Text (Start .. J)
                          & "... does not fit in 64 bits";
                     end if;
                     V := V * Unsigned_64 (Radix)
                       + Unsigned_64 (Digit_Of (Text (J)));
                     Ndig := Ndig + 1;
                     J := J + 1;
                  end loop;
                  if Radix /= 10 and then Ndig = 0 then
                     raise Wire_Error with
                       Where & ": `0x` needs hex digits after it";
                  end if;
                  Emit (T_Num, Text (Start .. J - 1), J - Start, V, Radix,
                        Ndig);
               end;
            elsif Name_Start (C) then
               declare
                  J : Natural := I;
               begin
                  while J <= Text'Last and then Name_Char (Text (J)) loop
                     J := J + 1;
                  end loop;
                  if J <= Text'Last and then Text (J) = '-'
                    and then J < Text'Last and then Name_Start (Text (J + 1))
                    and then Col = 1
                  then
                     raise Wire_Error with
                       Where & ": `" & Text (I .. J) & "...` has a hyphen; "
                       & "a name in a binary grammar is a field in an "
                       & "expression, where `-` subtracts: write it with an "
                       & "underscore (" & Text (I .. J - 1) & "_"
                       & "...)";
                  end if;
                  Emit (T_Name, Text (I .. J - 1), J - I);
               end;
            elsif C = '"' then
               declare
                  J : Natural := I + 1;
               begin
                  while J <= Text'Last and then Text (J) /= '"'
                    and then Text (J) /= ASCII.LF
                  loop
                     J := J + 1;
                  end loop;
                  if J > Text'Last or else Text (J) /= '"' then
                     raise Wire_Error with
                       Where & ": a quoted string is never closed";
                  end if;
                  Emit (T_Str, Text (I + 1 .. J - 1), J - I + 1);
               end;
            elsif C = ':' then
               if N = ':' and then I + 2 <= Text'Last
                 and then Text (I + 2) = '='
               then
                  Emit (T_Sym, "=", 3);
               elsif N = '=' then
                  Emit (T_Sym, "=", 2);
               elsif Head then
                  Emit (T_Sym, "=", 1);
               else
                  Emit (T_Sym, ":", 1);
               end if;
            elsif C = '%' and then I + 6 <= Text'Last
              and then Text (I + 1 .. I + 6) = "action"
            then
               --  `%action{ code }`: C, to the brace that closes it.
               declare
                  Open_Line : constant Positive := Line;
                  Open_Col  : constant Positive := Col;
                  K         : Natural := I + 7;
                  Depth     : Natural := 0;
                  Start     : Natural;
               begin
                  while K <= Text'Last and then Text (K) in ' ' | ASCII.HT
                  loop
                     K := K + 1;
                  end loop;
                  if K > Text'Last or else Text (K) /= '{' then
                     raise Wire_Error with
                       Where & ": `%action` is followed by `{ code }`";
                  end if;
                  Start := K + 1;
                  loop
                     if K > Text'Last then
                        raise Wire_Error with
                          Where & ": the `%action {` is never closed";
                     end if;
                     case Text (K) is
                        when '{' => Depth := Depth + 1;
                        when '}' =>
                           Depth := Depth - 1;
                           exit when Depth = 0;
                        when '"' | ''' =>
                           declare
                              Q : constant Character := Text (K);
                           begin
                              K := K + 1;
                              while K <= Text'Last and then Text (K) /= Q loop
                                 if Text (K) = '\' then
                                    K := K + 1;
                                 end if;
                                 K := K + 1;
                              end loop;
                           end;
                        when '/' =>
                           if K < Text'Last and then Text (K + 1) = '/' then
                              while K <= Text'Last and then Text (K) /= ASCII.LF
                              loop
                                 K := K + 1;
                              end loop;
                              K := K - 1;
                           elsif K < Text'Last and then Text (K + 1) = '*' then
                              K := K + 2;
                              while K < Text'Last
                                and then not (Text (K) = '*'
                                              and then Text (K + 1) = '/')
                              loop
                                 K := K + 1;
                              end loop;
                              K := K + 1;
                           end if;
                        when others => null;
                     end case;
                     K := K + 1;
                  end loop;
                  Toks.Append (Token'(Kind => T_Code, Line => Open_Line,
                                      Col => Open_Col,
                                      Text => To_Unbounded_String
                                                (Text (Start .. K - 1)),
                                      others => <>));
                  for J in I .. K loop
                     if Text (J) = ASCII.LF then
                        Line := Line + 1;
                        Col := 1;
                     else
                        Col := Col + 1;
                     end if;
                  end loop;
                  I := K + 1;
               end;
            elsif (C = '=' and then N = '=')
              or else (C = '!' and then N = '=')
              or else (C = '<' and then N in '=' | '<')
              or else (C = '>' and then N in '=' | '>')
              or else (C = '&' and then N = '&')
              or else (C = '|' and then N = '|')
            then
               Emit (T_Sym, Text (I .. I + 1), 2);
            elsif C in '=' | '|' | '(' | ')' | '[' | ']' | '*' | '@' | '?'
              | '+' | '-' | '/' | '%' | '&' | '^' | '~' | '!' | '<' | '>'
              | ','
            then
               Emit (T_Sym, [1 => C], 1);
            else
               raise Wire_Error with
                 Where & ": unexpected character '" & C & "'";
            end if;
         end;
      end loop;
      Toks.Append (Token'(Kind => T_EOF, Line => Line, Col => 1,
                          others => <>));
      return Toks;
   end Lex;

   ---------------------------------------------------------------------------
   --  The reader
   ---------------------------------------------------------------------------

   type Parser is record
      Toks : Token_Vectors.Vector;
      Pos  : Positive := 1;
      File : Unbounded_String;
      G    : Grammar;
   end record;

   function Cur (P : Parser) return Token is (P.Toks (P.Pos));
   function Peek (P : Parser; K : Positive := 1) return Token is
     (P.Toks (Positive'Min (P.Pos + K, Natural (P.Toks.Length))));

   function Is_Sym (T : Token; S : String) return Boolean is
     (T.Kind = T_Sym and then To_String (T.Text) = S);

   procedure Next (P : in out Parser) is
   begin
      if P.Pos < Natural (P.Toks.Length) then
         P.Pos := P.Pos + 1;
      end if;
   end Next;

   function Where (P : Parser; T : Token) return String is
     ((if P.File = "" then "" else To_String (P.File) & ":")
      & Img (T.Line) & ":" & Img (T.Col));

   procedure Fail (P : Parser; T : Token; Msg : String) is
   begin
      raise Wire_Error with Where (P, T) & ": " & Msg;
   end Fail;

   function Describe (T : Token) return String is
     (case T.Kind is
         when T_EOF  => "the end of the file",
         when T_Name => "`" & To_String (T.Text) & "`",
         when T_Num  => "`" & To_String (T.Text) & "`",
         when T_Str  => """" & To_String (T.Text) & """",
         when T_Sym  => "`" & To_String (T.Text) & "`",
         when T_Code => "an %action block");

   procedure Expect_Sym (P : in out Parser; S : String; Why : String := "") is
   begin
      if not Is_Sym (Cur (P), S) then
         Fail (P, Cur (P),
               "expected `" & S & "`" & Why & ", found " & Describe (Cur (P)));
      end if;
      Next (P);
   end Expect_Sym;

   --  A rule (or a directive) starts at column 1; a continuation is indented.
   function End_Of_Rule (P : Parser) return Boolean is
      T : constant Token := Cur (P);
   begin
      if T.Kind = T_EOF then
         return True;
      elsif T.Col = 1 and then T.Kind = T_Name then
         declare
            S : constant String := To_String (T.Text);
         begin
            return Is_Sym (Peek (P), "=")
              or else S in "binary" | "prefix" | "entry" | "units";
         end;
      end if;
      return False;
   end End_Of_Rule;

   ---------------------------------------------------------------------------
   --  Expressions
   ---------------------------------------------------------------------------

   --  Precedence, C's: * / %, + -, << >>, < <= > >=, == !=, &, ^, |, &&, ||.
   function Prec (Op : String) return Natural is
     (if Op in "*" | "/" | "%" then 10
      elsif Op in "+" | "-" then 9
      elsif Op in "<<" | ">>" then 8
      elsif Op in "<" | "<=" | ">" | ">=" then 7
      elsif Op in "==" | "!=" then 6
      elsif Op = "&" then 5
      elsif Op = "^" then 4
      elsif Op = "|" then 3
      elsif Op = "&&" then 2
      elsif Op = "||" then 1
      else 0);

   function Parse_Expr (P : in out Parser; Min_Prec : Natural := 1)
     return Expr_Access;

   function Parse_Primary (P : in out Parser) return Expr_Access is
      T : constant Token := Cur (P);
   begin
      case T.Kind is
         when T_Num =>
            Next (P);
            if T.Value > Unsigned_64 (Long_Long_Integer'Last) then
               Fail (P, T, "the number " & To_String (T.Text)
                     & " is too large for an expression (63 bits)");
            end if;
            return new Expr'(Kind => E_Num, Value => Long_Long_Integer (T.Value));
         when T_Name =>
            Next (P);
            if Is_Sym (Cur (P), "(") and then Cur (P).Col = T.End_Col then
               --  `len (field)`: a function of one field.
               declare
                  A : Token;
               begin
                  if To_String (T.Text) /= "len" then
                     Fail (P, T, "`" & To_String (T.Text) & "` is not a "
                           & "function an expression can call; the one there "
                           & "is is `len (field)`, the octets in a field");
                  end if;
                  Next (P);
                  A := Cur (P);
                  if A.Kind /= T_Name then
                     Fail (P, A, "`len` takes the name of a field read as "
                           & "octets, found " & Describe (A));
                  end if;
                  Next (P);
                  Expect_Sym (P, ")", " closing len (");
                  return new Expr'(Kind => E_Call, Fn => T.Text, Arg => A.Text);
               end;
            end if;
            return new Expr'(Kind => E_Var, Name => T.Text);
         when T_Sym =>
            if Is_Sym (T, "(") then
               Next (P);
               declare
                  E : constant Expr_Access := Parse_Expr (P);
               begin
                  Expect_Sym (P, ")", " closing the parenthesis");
                  return E;
               end;
            elsif To_String (T.Text) in "-" | "~" | "!" | "+" then
               Next (P);
               declare
                  O : constant Expr_Access := Parse_Primary (P);
               begin
                  if To_String (T.Text) = "+" then
                     return O;
                  end if;
                  return new Expr'(Kind => E_Unary, Un_Op => T.Text,
                                   Operand => O);
               end;
            end if;
         when others => null;
      end case;
      Fail (P, T, "expected a number, a field name or `(` in an expression, "
            & "found " & Describe (T));
      return null;
   end Parse_Primary;

   function Parse_Expr (P : in out Parser; Min_Prec : Natural := 1)
     return Expr_Access
   is
      L : Expr_Access := Parse_Primary (P);
   begin
      loop
         declare
            T  : constant Token := Cur (P);
            Pr : constant Natural :=
              (if T.Kind = T_Sym then Prec (To_String (T.Text)) else 0);
         begin
            exit when Pr = 0 or else Pr < Min_Prec;
            Next (P);
            declare
               R : constant Expr_Access := Parse_Expr (P, Pr + 1);
            begin
               L := new Expr'(Kind => E_Binary, Bin_Op => T.Text,
                              Left => L, Right => R);
            end;
         end;
      end loop;
      return L;
   end Parse_Expr;

   ---------------------------------------------------------------------------
   --  Items
   ---------------------------------------------------------------------------

   function Parse_Alternation (P : in out Parser) return Seq_Vectors.Vector;

   --  `u8`, `i32`, `u16le`: a width in a name, as Rust and the text core
   --  rules spell it.
   procedure Fixed_Type
     (S : String; Is_Fixed : out Boolean; Bits : out Natural;
      Signed, Little : out Boolean)
   is
      K : Natural := S'First + 1;
   begin
      Is_Fixed := False;  Bits := 0;  Signed := False;  Little := False;
      if S'Length < 2 or else S (S'First) not in 'u' | 'i' then
         return;
      end if;
      while K <= S'Last and then S (K) in '0' .. '9' loop
         Bits := Bits * 10 + Character'Pos (S (K)) - Character'Pos ('0');
         K := K + 1;
      end loop;
      if K = S'First + 1 or else Bits not in 8 | 16 | 32 | 64 then
         Bits := 0;
         return;
      end if;
      if K <= S'Last then
         if S (K .. S'Last) = "le" then
            Little := True;
         elsif S (K .. S'Last) /= "be" then
            Bits := 0;
            return;
         end if;
      end if;
      Signed := S (S'First) = 'i';
      Is_Fixed := True;
   end Fixed_Type;

   --  After `name:` -- the width, the count, the rule.
   procedure Parse_Spec (P : in out Parser; It : Item_Access) is
      T : constant Token := Cur (P);

      procedure Modifiers (Adjacent_To : Token) is
         M : constant Token := Cur (P);
      begin
         if M.Kind = T_Name and then M.Col = Adjacent_To.End_Col then
            declare
               S : constant String := To_String (M.Text);
            begin
               if S in "s" | "sle" | "sbe" | "le" | "be" then
                  It.Signed := S (S'First) = 's';
                  It.Little := S'Length >= 2
                    and then S (S'Last - 1 .. S'Last) = "le";
                  Next (P);
               else
                  Fail (P, M, "`" & S & "` after a width: the modifiers are "
                        & "`s` (signed), `le` and `be` (byte order, big the "
                        & "default), as in `ttl:8`, `delta:8s`, `port:16le`");
               end if;
            end;
         end if;
      end Modifiers;

      --  The place comes before the width: `ihl@4:4`.
      procedure Offset is
      begin
         if Is_Sym (Cur (P), "@") then
            Fail (P, Cur (P), "the place comes before the width: write "
                  & "`" & To_String (It.Name) & "@K:W`, `@` the bit it "
                  & "starts at and `:` how many bits");
         end if;
      end Offset;

      --  True when the `(` at the current token closes before a `*`.
      function Count_Then_Star return Boolean is
         D : Natural := 0;
         K : Positive := P.Pos;
      begin
         loop
            declare
               X : constant Token := P.Toks (K);
            begin
               if X.Kind = T_EOF then
                  return False;
               elsif Is_Sym (X, "(") then
                  D := D + 1;
               elsif Is_Sym (X, ")") then
                  D := D - 1;
                  if D = 0 then
                     return K < Natural (P.Toks.Length)
                       and then Is_Sym (P.Toks (K + 1), "*");
                  end if;
               end if;
            end;
            K := K + 1;
         end loop;
      end Count_Then_Star;

      procedure Array_Of is
         Rule_Tok : constant Token := Cur (P);
      begin
         if Rule_Tok.Kind /= T_Name then
            Fail (P, Rule_Tok, "expected a rule name after `*`, found "
                  & Describe (Rule_Tok));
         end if;
         Next (P);
         if To_String (Rule_Tok.Text) = "u8" and then It.Count = null
           and then It.Min = 0 and then It.Max = -1
         then
            It.Kind := S_Rest;
         else
            It.Kind := S_Array;
            It.Ref := Rule_Tok.Text;
         end if;
      end Array_Of;
   begin
      case T.Kind is
         when T_Num =>
            if T.Radix /= 10 then
               Fail (P, T, "a width is a decimal number of bits; "
                     & To_String (T.Text) & " is a constant (write it as an "
                     & "item of its own)");
            end if;
            Next (P);
            if Is_Sym (Cur (P), "*") then
               --  `n*rule`, `n*m rule`
               Next (P);
               It.Min := Natural (T.Value);
               if Cur (P).Kind = T_Num then
                  It.Max := Integer (Cur (P).Value);
                  Next (P);
               else
                  It.Max := -1;
               end if;
               Array_Of;
               if It.Kind = S_Rest then
                  Fail (P, T, "`*u8` is octets; a count of them is "
                        & "`name:[count]`");
               end if;
               return;
            end if;
            if T.Value = 0 or else T.Value > 64 then
               Fail (P, T, "a field of" & Natural'Image (Natural (T.Value))
                     & " bits: fields are 1 to 64 bits; for more, say how "
                     & "many octets with `name:[" & Img (Integer (T.Value) / 8)
                     & "]`");
            end if;
            It.Kind := S_Bits;
            It.Bits := Natural (T.Value);
            Modifiers (T);
            Offset;
         when T_Sym =>
            if Is_Sym (T, "[") then
               Next (P);
               It.Kind := S_Octets;
               It.Count := Parse_Expr (P);
               Expect_Sym (P, "]", " closing the octet count");
               Offset;
            elsif Is_Sym (T, "*") then
               Next (P);
               It.Min := 0;  It.Max := -1;
               Array_Of;
            elsif Is_Sym (T, "(") then
               if Count_Then_Star then
                  Next (P);
                  It.Count := Parse_Expr (P);
                  Expect_Sym (P, ")", " closing the count");
                  Expect_Sym (P, "*", " after the count");
                  It.Min := 0;  It.Max := -1;
                  Array_Of;
                  if It.Kind = S_Rest then
                     Fail (P, T, "`(n)*u8` is `name:[n]`");
                  end if;
               else
                  Next (P);
                  It.Kind := S_Choice;
                  It.Alts := Parse_Alternation (P);
                  Expect_Sym (P, ")", " closing the choice");
               end if;
            else
               Fail (P, T, "expected a width after `:`, found " & Describe (T));
            end if;
         when T_Name =>
            declare
               S        : constant String := To_String (T.Text);
               Is_Fixed : Boolean;
               B        : Natural;
               Sg, Lt   : Boolean;
            begin
               Fixed_Type (S, Is_Fixed, B, Sg, Lt);
               Next (P);
               if S = "bits" and then Is_Sym (Cur (P), "(") then
                  Next (P);
                  It.Kind := S_Bit_Expr;
                  It.Count := Parse_Expr (P);
                  Expect_Sym (P, ")", " closing bits(");
               elsif Is_Fixed then
                  It.Kind := S_Bits;
                  It.Bits := B;  It.Signed := Sg;  It.Little := Lt;
                  Offset;
               else
                  It.Kind := S_Ref;
                  It.Ref := T.Text;
               end if;
            end;
         when others =>
            Fail (P, T, "expected a width after `:`, found " & Describe (T));
      end case;
   end Parse_Spec;

   procedure Parse_Item (P : in out Parser; Seq : Sequence_Access) is
      T : constant Token := Cur (P);
   begin
      case T.Kind is
         when T_Num =>
            if T.Radix = 10 then
               Fail (P, T, "a bare decimal number has no width. A constant "
                     & "is as wide as its digits: write 0x" & "0" & To_String (T.Text)
                     & " (hex, 4 bits a digit) or 0b... (binary, 1 bit a "
                     & "digit)");
            end if;
            Next (P);
            Seq.Items.Append
              (new Item'(Kind => S_Const, Value => T.Value,
                         Bits => T.Ndigits * (if T.Radix = 16 then 4 else 1),
                         Line => T.Line, Col => T.Col, others => <>));
            if Seq.Items.Last_Element.Bits > 64 then
               Fail (P, T, "a constant of" & Natural'Image (Seq.Items.Last_Element.Bits)
                     & " bits: constants are at most 64 bits");
            end if;
         when T_Name =>
            Next (P);
            declare
               It : constant Item_Access :=
                 new Item'(Name => T.Text, Line => T.Line, Col => T.Col,
                           others => <>);
            begin
               if Is_Sym (Cur (P), "@") and then Cur (P).Col = T.End_Col then
                  --  `name@K:W`: W bits, starting at bit K of the record.
                  Next (P);
                  if Cur (P).Kind /= T_Num or else Cur (P).Radix /= 10 then
                     Fail (P, Cur (P), "expected a bit number after `@` "
                           & "(the bit of the record the field starts at), "
                           & "found " & Describe (Cur (P)));
                  end if;
                  It.At_Bit := Integer (Cur (P).Value);
                  Next (P);
                  if not Is_Sym (Cur (P), ":") then
                     Fail (P, Cur (P), "`" & To_String (T.Text) & "@"
                           & Img (It.At_Bit) & "` needs its width: `"
                           & To_String (T.Text) & "@" & Img (It.At_Bit)
                           & ":W`");
                  end if;
                  Next (P);
                  Parse_Spec (P, It);
               elsif Is_Sym (Cur (P), ":") and then Cur (P).Col = T.End_Col then
                  Next (P);
                  Parse_Spec (P, It);
               else
                  It.Kind := S_Ref;
                  It.Ref := T.Text;
               end if;
               Seq.Items.Append (It);
            end;
         when T_Sym =>
            if Is_Sym (T, "(") then
               Next (P);
               declare
                  Alts : constant Seq_Vectors.Vector := Parse_Alternation (P);
               begin
                  Expect_Sym (P, ")", " closing the group");
                  if Natural (Alts.Length) /= 1 then
                     Fail (P, T, "a choice needs a field to hold it: write "
                           & "`name:( a | b )`");
                  end if;
                  if Alts.First_Element.Guard /= null then
                     Fail (P, T, "a guard `?(...)` belongs to an alternative "
                           & "of a choice");
                  end if;
                  for E of Alts.First_Element.Items loop
                     Seq.Items.Append (E);
                  end loop;
               end;
            elsif Is_Sym (T, "-") and then P.Pos > 1
              and then P.Toks (P.Pos - 1).Kind = T_Name
              and then P.Toks (P.Pos - 1).End_Col = T.Col
              and then Peek (P).Kind = T_Name and then Peek (P).Col = T.Col + 1
            then
               Fail (P, T, "`" & To_String (P.Toks (P.Pos - 1).Text) & "-"
                     & To_String (Peek (P).Text) & "` has a hyphen; a name in "
                     & "a binary grammar is a field in an expression, where "
                     & "`-` subtracts: write it with an underscore ("
                     & To_String (P.Toks (P.Pos - 1).Text) & "_"
                     & To_String (Peek (P).Text) & ")");
            elsif Is_Sym (T, ":") then
               Fail (P, T, "a width is glued to its field name, `name:16`; "
                     & "a `:` after a space is not one");
            elsif Is_Sym (T, "?") then
               Next (P);
               Expect_Sym (P, "(", " after `?`");
               declare
                  E : constant Expr_Access := Parse_Expr (P);
               begin
                  Expect_Sym (P, ")", " closing the condition");
                  declare
                     Msg : Unbounded_String;
                  begin
                     --  `?(cond) "what is wrong"`: the words the error uses.
                     if Cur (P).Kind = T_Str then
                        Msg := Cur (P).Text;
                        Next (P);
                     end if;
                     Seq.Items.Append
                       (new Item'(Kind => S_Assert, Count => E, Ref => Msg,
                                  Line => T.Line, Col => T.Col, others => <>));
                  end;
               end;
            elsif Is_Sym (T, "*") or else Is_Sym (T, "[") then
               Fail (P, T, "give a repeated rule or a bracketed group a "
                     & "field name: `name:*rule`, `name:[count]`");
            else
               Fail (P, T, "unexpected " & Describe (T)
                     & "; a rule is a sequence of `name:width`, `name`, "
                     & "constants and groups");
            end if;
         when T_Str =>
            Fail (P, T, "a quoted string is text; this file is `binary`. A "
                  & "fixed byte sequence is a constant: 0x474554 is ""GET""");
         when T_Code =>
            Fail (P, T, "an `%action{ }` goes at the end of a rule, after "
                  & "all its alternatives");
         when T_EOF =>
            Fail (P, T, "unexpected end of the file");
      end case;
   end Parse_Item;

   function Parse_Sequence (P : in out Parser) return Sequence_Access is
      S : constant Sequence_Access := new Sequence;
   begin
      S.Line := Cur (P).Line;
      if Is_Sym (Cur (P), "?") then
         Next (P);
         Expect_Sym (P, "(", " after `?`");
         declare
            E : constant Expr_Access := Parse_Expr (P);
         begin
            Expect_Sym (P, ")", " closing the guard");
            --  `?(cond) "what is wrong"` at the start is a check with its
            --  words, not a guard that picks an alternative.
            if Cur (P).Kind = T_Str then
               S.Items.Append
                 (new Item'(Kind => S_Assert, Count => E, Ref => Cur (P).Text,
                            Line => S.Line, Col => 1, others => <>));
               Next (P);
            else
               S.Guard := E;
            end if;
         end;
      end if;
      while not End_Of_Rule (P) and then Cur (P).Kind /= T_Code
        and then not Is_Sym (Cur (P), "|") and then not Is_Sym (Cur (P), ")")
      loop
         Parse_Item (P, S);
      end loop;
      return S;
   end Parse_Sequence;

   function Parse_Alternation (P : in out Parser) return Seq_Vectors.Vector is
      V : Seq_Vectors.Vector;
   begin
      loop
         V.Append (Parse_Sequence (P));
         exit when not Is_Sym (Cur (P), "|");
         Next (P);
      end loop;
      return V;
   end Parse_Alternation;

   ---------------------------------------------------------------------------
   --  Queries
   ---------------------------------------------------------------------------

   function Find (G : Grammar; Name : String) return Natural is
   begin
      for I in 1 .. Natural (G.Rules.Length) loop
         if To_String (G.Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Is_Value_Set (R : Rule) return Boolean is
      W : Natural := 0;
   begin
      if R.Alts.Is_Empty then
         return False;
      end if;
      for A of R.Alts loop
         if A.Guard /= null or else Natural (A.Items.Length) /= 1
           or else A.Items.First_Element.Kind /= S_Const
         then
            return False;
         end if;
         if W = 0 then
            W := A.Items.First_Element.Bits;
         elsif W /= A.Items.First_Element.Bits then
            return False;
         end if;
      end loop;
      return True;
   end Is_Value_Set;

   function Value_Width (R : Rule) return Natural is
     (if Is_Value_Set (R)
      then R.Alts.First_Element.Items.First_Element.Bits else 0);

   function Storage_Bits (N : Natural) return Positive is
     (if N <= 8 then 8 elsif N <= 16 then 16 elsif N <= 32 then 32 else 64);

   function Fixed_Bits (G : Grammar; S : Sequence) return Integer is
      Total : Integer := 0;
   begin
      for It of S.Items loop
         case It.Kind is
            when S_Bits | S_Const =>
               Total := Total + It.Bits;
            when S_Assert =>
               null;
            when S_Ref =>
               declare
                  K : constant Natural := Find (G, To_String (It.Ref));
               begin
                  if K = 0 then
                     return -1;
                  elsif Is_Value_Set (G.Rules (K)) then
                     Total := Total + Value_Width (G.Rules (K));
                  elsif Natural (G.Rules (K).Alts.Length) = 1 then
                     declare
                        B : constant Integer :=
                          Fixed_Bits (G, G.Rules (K).Alts.First_Element.all);
                     begin
                        if B < 0 then
                           return -1;
                        end if;
                        Total := Total + B;
                     end;
                  else
                     return -1;
                  end if;
               end;
            when others =>
               return -1;
         end case;
      end loop;
      return Total;
   end Fixed_Bits;

   ---------------------------------------------------------------------------
   --  Checking
   ---------------------------------------------------------------------------

   --  A rule name of a text grammar, which may have hyphens (`bech32-symbol`),
   --  read from the tokens: Name { "-" Name }, each glued to the last.
   function Text_Rule_Name (P : in out Parser; What : String) return String is
      T : constant Token := Cur (P);
      R : Unbounded_String;
      End_Col : Positive;
   begin
      if T.Kind /= T_Name then
         Fail (P, T, "expected " & What & ", found " & Describe (T));
      end if;
      R := T.Text;
      End_Col := T.End_Col;
      Next (P);
      while Is_Sym (Cur (P), "-") and then Cur (P).Col = End_Col
        and then Peek (P).Kind = T_Name and then Peek (P).Col = End_Col + 1
      loop
         Next (P);
         Append (R, "-" & To_String (Cur (P).Text));
         End_Col := Cur (P).End_Col;
         Next (P);
      end loop;
      return To_String (R);
   end Text_Rule_Name;

   --  Read the text grammar a `units` line names and take the spellings and
   --  values from its enum rule (and the separator from another).
   procedure Load_Units
     (G : in out Grammar; File, Path, Rule_Name, Sep_Name : String;
      Line : Positive)
   is
      Where : constant String :=
        (if File = "" then "" else File & ":") & Img (Line) & ": ";
      Full  : constant String :=
        (if Path'Length > 0 and then Path (Path'First) = '/' then Path
         elsif File = "" then Path
         else Ada.Directories.Containing_Directory (File) & "/" & Path);

      --  The literal text of the rule's alternatives, with their values.
      procedure Spellings
        (Rules : HBNF_Grammar.Rule_Vectors.Vector; Name : String;
         Out_Units : in out Unit_Vectors.Vector)
      is
         use HBNF_Grammar;
         Found : Boolean := False;
         Place : Natural := 0;
      begin
         for R of Rules loop
            if To_String (R.Name) = Name then
               Found := True;
               for E of R.Pattern loop
                  if E.Kind = Literal then
                     declare
                        Lit : constant String := To_String (E.Lit);
                        V   : constant Integer := Enum_Value (Name, Lit);
                     begin
                        Out_Units.Append
                          (Unit'(Spelling => E.Lit,
                                 Value => (if V >= 0 then V else Place)));
                        Place := Place + 1;
                     end;
                  elsif E.Kind /= Alt then
                     raise Wire_Error with
                       Where & "the rule `" & Name & "` in " & Path
                       & " is not a list of plain literals, which is what "
                       & "spells units (`" & Name & " = ""q"" | ""p"" | ...`)";
                  end if;
               end loop;
            end if;
         end loop;
         if not Found then
            raise Wire_Error with
              Where & "there is no rule `" & Name & "` in " & Path;
         end if;
      end Spellings;

      Rules : HBNF_Grammar.Rule_Vectors.Vector;
   begin
      begin
         Rules := HBNF_Grammar.Parse_File (Full);
      exception
         when E : HBNF_Grammar.Parse_Error =>
            raise Wire_Error with
              Where & "reading " & Path & ": "
              & HBNF_Grammar.Error_Message (E);
         when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
            raise Wire_Error with Where & "cannot read " & Full;
      end;
      Spellings (Rules, Rule_Name, G.Units);
      if G.Units.Is_Empty then
         raise Wire_Error with Where & "the rule `" & Rule_Name & "` has no "
           & "alternatives";
      end if;
      for U of G.Units loop
         if U.Value >= 2 ** G.Unit_Width then
            raise Wire_Error with
              Where & "`" & To_String (U.Spelling) & "` has the value"
              & Natural'Image (U.Value) & ", which does not fit a unit of"
              & Natural'Image (G.Unit_Width) & " bits";
         end if;
      end loop;
      if Sep_Name /= "" then
         declare
            Seps : Unit_Vectors.Vector;
         begin
            Spellings (Rules, Sep_Name, Seps);
            if Natural (Seps.Length) /= 1 then
               raise Wire_Error with
                 Where & "the separator `" & Sep_Name & "` must be one "
                 & "literal";
            end if;
            G.Unit_Sep := Seps.First_Element.Spelling;
         end;
      end if;
   end Load_Units;

   function Parse (Text : String; File : String := "") return Grammar is
      P : Parser;

      procedure Fail_At (It : Item; Msg : String) is
      begin
         raise Wire_Error with
           (if File = "" then "" else File & ":")
           & Img (It.Line) & ":" & Img (It.Col) & ": " & Msg;
      end Fail_At;

      procedure Fail_Rule (R : Rule; Msg : String) is
      begin
         raise Wire_Error with
           (if File = "" then "" else File & ":") & Img (R.Line) & ": rule `"
           & To_String (R.Name) & "`: " & Msg;
      end Fail_Rule;

      --  Names of the numeric fields in scope.
      package Name_Vectors is new Ada.Containers.Vectors
        (Positive, Unbounded_String);

      function Has (V : Name_Vectors.Vector; N : String) return Boolean is
      begin
         for X of V loop
            if To_String (X) = N then
               return True;
            end if;
         end loop;
         return False;
      end Has;

      function List (V : Name_Vectors.Vector) return String is
         R : Unbounded_String;
      begin
         for X of V loop
            if R /= Null_Unbounded_String then
               Append (R, ", ");
            end if;
            Append (R, X);
         end loop;
         return (if R = Null_Unbounded_String then "none yet" else To_String (R));
      end List;

      procedure Check_Expr
        (E : Expr_Access; Scope : Name_Vectors.Vector; R : Rule;
         Line, Col : Natural)
      is
      begin
         if E = null then
            return;
         end if;
         case E.Kind is
            when E_Num => null;
            when E_Var =>
               if To_String (E.Name) = "align" and then P.G.Unit_Width = 0 then
                  raise Wire_Error with
                    (if File = "" then "" else File & ":") & Img (Line) & ":"
                    & Img (Col) & ": rule `" & To_String (R.Name) & "`: "
                    & "`align` is the bits to the next unit boundary, and "
                    & "this file has no `units` line";
               elsif To_String (E.Name) /= "remaining"
                 and then To_String (E.Name) /= "align"
                 and then not Has (Scope, To_String (E.Name))
               then
                  raise Wire_Error with
                    (if File = "" then "" else File & ":") & Img (Line) & ":"
                    & Img (Col) & ": rule `" & To_String (R.Name) & "`: `"
                    & To_String (E.Name) & "` is not a number read before "
                    & "this point (an expression may use the fields above it "
                    & "in the record; here: " & List (Scope) & ")";
               end if;
            when E_Call =>
               --  Octet fields are in the scope as "*name".
               if not Has (Scope, "*" & To_String (E.Arg)) then
                  raise Wire_Error with
                    (if File = "" then "" else File & ":") & Img (Line) & ":"
                    & Img (Col) & ": rule `" & To_String (R.Name)
                    & "`: `len (" & To_String (E.Arg) & ")` needs a field "
                    & "read as octets (`" & To_String (E.Arg) & ":[n]` or `"
                    & To_String (E.Arg) & ":*u8`) before this point";
               end if;
            when E_Unary =>
               Check_Expr (E.Operand, Scope, R, Line, Col);
            when E_Binary =>
               Check_Expr (E.Left, Scope, R, Line, Col);
               Check_Expr (E.Right, Scope, R, Line, Col);
         end case;
      end Check_Expr;

      procedure Check_Seq
        (S : Sequence; Scope_In : Name_Vectors.Vector; R : Rule)
      is
         Scope : Name_Vectors.Vector := Scope_In;
         Off   : Integer := 0;     --  the bit a field starts at, or -1
         Seen  : Name_Vectors.Vector;
      begin
         if S.Guard /= null then
            Check_Expr (S.Guard, Scope, R, S.Line, 1);
         end if;
         for It of S.Items loop
            --  A set of values behind a name or a width.
            if It.Kind = S_Ref then
               declare
                  K : constant Natural := Find (P.G, To_String (It.Ref));
               begin
                  if K = 0 then
                     Fail_At (It.all,
                              "`" & To_String (It.Ref) & "` is not a rule "
                              & "in this file; define it, or give the field "
                              & "a width (`" & To_String (It.Name) & ":8`)");
                  elsif Is_Value_Set (P.G.Rules (K)) then
                     It.Kind := S_Bits;
                     It.Bits := Value_Width (P.G.Rules (K));
                  end if;
               end;
            elsif It.Kind = S_Bits and then It.Name /= Null_Unbounded_String then
               declare
                  K : constant Natural := Find (P.G, To_String (It.Name));
               begin
                  --  `ethertype:16` where `ethertype` is a set of values.
                  if K /= 0 and then Is_Value_Set (P.G.Rules (K)) then
                     if Value_Width (P.G.Rules (K)) /= It.Bits then
                        Fail_At
                          (It.all,
                           "`" & To_String (It.Name) & ":" & Img (It.Bits)
                           & "` but the rule `" & To_String (It.Name)
                           & "` lists values of "
                           & Img (Value_Width (P.G.Rules (K))) & " bits ("
                           & "check the width against the RFC)");
                     end if;
                     It.Ref := It.Name;
                  end if;
               end;
            end if;

            if It.Name /= Null_Unbounded_String then
               if Has (Seen, To_String (It.Name)) then
                  Fail_At (It.all, "the field `" & To_String (It.Name)
                           & "` is named twice in one record; a nested record "
                           & "of the same rule needs a field name of its "
                           & "own (`src:addr dst:addr`)");
               end if;
               Seen.Append (It.Name);
            end if;

            case It.Kind is
               when S_Bits | S_Const =>
                  if It.Kind = S_Bits and then It.Little
                    and then It.Bits mod 8 /= 0
                  then
                     Fail_At (It.all,
                              "little-endian needs a whole number of octets, "
                              & "and" & Natural'Image (It.Bits)
                              & " bits is not; byte order only means "
                              & "something across octets");
                  end if;
                  if It.At_Bit >= 0 then
                     if Off >= 0 and then Off /= It.At_Bit then
                        Fail_At
                          (It.all,
                           "`" & To_String (It.Name) & "@" & Img (It.At_Bit)
                           & ":" & Img (It.Bits) & "` says bit "
                           & Img (It.At_Bit) & ", but the fields above it "
                           & "end at bit " & Img (Off) & " (bit 0 is the "
                           & "most significant bit of the first octet, as in "
                           & "an RFC's packet diagram)");
                     end if;
                     It.Static_Ok := Off >= 0;
                  end if;
                  if Off >= 0 then
                     Off := Off + It.Bits;
                  end if;
                  if It.Kind = S_Bits then
                     Scope.Append (It.Name);
                  end if;
               when S_Octets =>
                  Check_Expr (It.Count, Scope, R, It.Line, It.Col);
                  Off := -1;
                  Scope.Append ("*" & It.Name);
               when S_Assert =>
                  Check_Expr (It.Count, Scope, R, It.Line, It.Col);
               when S_Rest =>
                  Off := -1;
                  Scope.Append ("*" & It.Name);
               when S_Bit_Expr =>
                  Check_Expr (It.Count, Scope, R, It.Line, It.Col);
                  Off := -1;
                  Scope.Append (It.Name);
               when S_Ref =>
                  declare
                     B : constant Integer := Fixed_Bits
                       (P.G, (Items => Item_Vectors.To_Vector (It, 1),
                              others => <>));
                  begin
                     Off := (if Off >= 0 and then B >= 0 then Off + B else -1);
                  end;
               when S_Array =>
                  if Find (P.G, To_String (It.Ref)) = 0 then
                     Fail_At (It.all,
                              "`" & To_String (It.Ref) & "` is not a rule in "
                              & "this file");
                  end if;
                  Check_Expr (It.Count, Scope, R, It.Line, It.Col);
                  Off := -1;
               when S_Choice =>
                  if Natural (It.Alts.Length) < 2 then
                     Fail_At (It.all, "a choice has at least two "
                              & "alternatives; for one, drop the parentheses");
                  end if;
                  for A of It.Alts loop
                     Check_Seq (A.all, Scope, R);
                  end loop;
                  Off := -1;
            end case;
         end loop;
      end Check_Seq;

      --  A record that holds itself by value cannot be laid out.
      procedure Check_Cycles is
         type Mark is (White, Grey, Black);
         Marks : array (1 .. Natural (P.G.Rules.Length)) of Mark :=
           [others => White];

         procedure Visit (K : Positive; Path : String);

         procedure Walk (V : Seq_Vectors.Vector; Path : String) is
         begin
            for S of V loop
               for It of S.Items loop
                  if It.Kind = S_Ref then
                     if Find (P.G, To_String (It.Ref)) /= 0 then
                        Visit (Find (P.G, To_String (It.Ref)),
                               Path & " -> " & To_String (It.Ref));
                     end if;
                  elsif It.Kind = S_Choice then
                     Walk (It.Alts, Path);
                  end if;
               end loop;
            end loop;
         end Walk;

         procedure Visit (K : Positive; Path : String) is
         begin
            if Marks (K) = Grey then
               raise Wire_Error with
                 (if File = "" then "" else File & ":")
                 & Img (P.G.Rules (K).Line) & ": rule `"
                 & To_String (P.G.Rules (K).Name) & "` contains itself ("
                 & Path & "): a record cannot hold itself by value. Put the "
                 & "inner one in a counted array, `inner:0*1 name`.";
            elsif Marks (K) = White then
               Marks (K) := Grey;
               Walk (P.G.Rules (K).Alts, Path);
               Marks (K) := Black;
            end if;
         end Visit;
      begin
         for K in Marks'Range loop
            Visit (K, To_String (P.G.Rules (K).Name));
         end loop;
      end Check_Cycles;
   begin
      P.Toks := Lex (Text, File);
      P.File := To_Unbounded_String (File);

      while Cur (P).Kind /= T_EOF loop
         declare
            T : constant Token := Cur (P);
         begin
            if T.Kind /= T_Name or else T.Col /= 1 then
               Fail (P, T, "expected a rule `name = ...` starting in column 1 "
                     & "(a rule that continues on a later line is indented), "
                     & "found " & Describe (T));
            end if;
            if To_String (T.Text) = "binary" and then not Is_Sym (Peek (P), "=")
            then
               Next (P);
            elsif To_String (T.Text) = "prefix"
              and then not Is_Sym (Peek (P), "=")
            then
               Next (P);
               if Cur (P).Kind = T_Name and then To_String (Cur (P).Text) = "none"
               then
                  P.G.Prefix := Null_Unbounded_String;
               elsif Cur (P).Kind = T_Str then
                  P.G.Prefix := Cur (P).Text;
               else
                  Fail (P, Cur (P), "expected a quoted identifier prefix or "
                        & "`none` after `prefix`");
               end if;
               Next (P);
            elsif To_String (T.Text) = "units"
              and then not Is_Sym (Peek (P), "=")
            then
               Next (P);
               if Cur (P).Kind /= T_Num or else Cur (P).Radix /= 10
                 or else Cur (P).Value = 0 or else Cur (P).Value > 32
               then
                  Fail (P, Cur (P), "`units` takes a width in bits (1 to 32), "
                        & "then the enum rule that spells the units, `from` "
                        & "a text grammar: `units 5 bech32-symbol from "
                        & """bech32.hbnf""`");
               end if;
               P.G.Unit_Width := Natural (Cur (P).Value);
               Next (P);
               declare
                  Rule_Tok : constant Token := Cur (P);
                  Rule_Nm  : constant String :=
                    Text_Rule_Name (P, "the name of the enum rule that "
                                       & "spells the units");
                  Sep_Name : Unbounded_String;
                  Path     : Unbounded_String;
               begin
                  if not (Cur (P).Kind = T_Name
                          and then To_String (Cur (P).Text) = "from")
                  then
                     Fail (P, Cur (P), "expected `from ""file.hbnf""` after "
                           & "the rule name, found " & Describe (Cur (P)));
                  end if;
                  Next (P);
                  if Cur (P).Kind /= T_Str then
                     Fail (P, Cur (P), "expected the text grammar's file name "
                           & "in quotes after `from`, found "
                           & Describe (Cur (P)));
                  end if;
                  Path := Cur (P).Text;
                  Next (P);
                  if Cur (P).Kind = T_Name
                    and then To_String (Cur (P).Text) = "separator"
                  then
                     Next (P);
                     Sep_Name := To_Unbounded_String
                       (Text_Rule_Name (P, "the rule that spells the "
                                           & "separator after `separator`"));
                  end if;
                  Load_Units (P.G, File, To_String (Path), Rule_Nm,
                              To_String (Sep_Name), Rule_Tok.Line);
               end;
            elsif To_String (T.Text) = "entry"
              and then not Is_Sym (Peek (P), "=")
            then
               Fail (P, T, "`entry` is not supported in a binary file yet: "
                     & "the first rule is the one parse_bytes reads");
            else
               Next (P);
               Expect_Sym (P, "=", " after the rule name");
               if Find (P.G, To_String (T.Text)) /= 0 then
                  Fail (P, T, "rule `" & To_String (T.Text)
                        & "` is defined twice");
               end if;
               declare
                  R : Rule;
               begin
                  R.Name := T.Text;
                  R.Line := T.Line;
                  R.Alts := Parse_Alternation (P);
                  if Cur (P).Kind = T_Code then
                     R.Action := Cur (P).Text;
                     Next (P);
                  end if;
                  if not End_Of_Rule (P) then
                     Fail (P, Cur (P), "unexpected " & Describe (Cur (P))
                           & " in rule `" & To_String (R.Name) & "`");
                  end if;
                  P.G.Rules.Append (R);
               end;
            end if;
         end;
      end loop;

      if P.G.Rules.Is_Empty then
         raise Wire_Error with
           (if File = "" then "" else File & ":")
           & "1: a binary grammar needs at least one rule";
      end if;

      Check_Cycles;
      declare
         Empty : Name_Vectors.Vector;
      begin
         for R of P.G.Rules loop
            if not Is_Value_Set (R) then
               for A of R.Alts loop
                  Check_Seq (A.all, Empty, R);
               end loop;
            end if;
         end loop;
      end;
      return P.G;
   end Parse;

end HBNF_Wire;
