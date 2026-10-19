pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Exceptions;

package body HBNF_Wire is

   use Interfaces;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   ---------------------------------------------------------------------------
   --  Expressions
   --
   --  The main reader keeps the text of an expression as written (a field's
   --  octet count, a condition); this reads it.  An expression is C's integer
   --  arithmetic over names, numbers and `len (field)`.
   ---------------------------------------------------------------------------

   type Tok_Kind is (T_Name, T_Num, T_Sym, T_EOF);

   type Token is record
      Kind    : Tok_Kind := T_EOF;
      Text    : Unbounded_String;
      Line    : Positive := 1;
      Col     : Positive := 1;
      End_Col : Positive := 1;   --  the column after the token
      Value   : Unsigned_64 := 0;
      Radix   : Positive := 10;
      Ndigits : Natural := 0;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors (Positive, Token);

   function Lex (Text : String; File : String) return Token_Vectors.Vector is
      Toks : Token_Vectors.Vector;
      I    : Natural := Text'First;
      Line : Positive := 1;
      Col  : Positive := 1;

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
                  Emit (T_Name, Text (I .. J - 1), J - I);
               end;
            elsif (C = '=' and then N = '=')
              or else (C = '!' and then N = '=')
              or else (C = '<' and then N in '=' | '<')
              or else (C = '>' and then N in '=' | '>')
              or else (C = '&' and then N = '&')
              or else (C = '|' and then N = '|')
            then
               Emit (T_Sym, Text (I .. I + 1), 2);
            elsif C in '|' | '(' | ')' | '*' | '+' | '-' | '/' | '%' | '&'
              | '^' | '~' | '!' | '<' | '>' | ','
            then
               Emit (T_Sym, [1 => C], 1);
            else
               raise Wire_Error with
                 Where & ": unexpected character '" & C & "' in an expression";
            end if;
         end;
      end loop;
      Toks.Append (Token'(Kind => T_EOF, Line => Line, Col => 1,
                          others => <>));
      return Toks;
   end Lex;

   type Parser is record
      Toks : Token_Vectors.Vector;
      Pos  : Positive := 1;
      File : Unbounded_String;
   end record;

   function Cur (P : Parser) return Token is (P.Toks (P.Pos));

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
         when T_EOF  => "the end of the expression",
         when T_Name => "`" & To_String (T.Text) & "`",
         when T_Num  => "`" & To_String (T.Text) & "`",
         when T_Sym  => "`" & To_String (T.Text) & "`");

   procedure Expect_Sym (P : in out Parser; S : String; Why : String := "") is
   begin
      if not Is_Sym (Cur (P), S) then
         Fail (P, Cur (P),
               "expected `" & S & "`" & Why & ", found " & Describe (Cur (P)));
      end if;
      Next (P);
   end Expect_Sym;

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

   function Is_Modifier (S : String) return Boolean is
     (S in "s" | "sle" | "sbe" | "le" | "be");

   function Parse_Expression (Text : String; Where : String)
     return Expr_Access
   is
      P : Parser;
   begin
      P.Toks := Lex (Text, "");
      declare
         E : constant Expr_Access := Parse_Expr (P);
      begin
         if Cur (P).Kind /= T_EOF then
            Fail (P, Cur (P), "unexpected " & Describe (Cur (P))
                  & " after the expression");
         end if;
         return E;
      end;
   exception
      when X : Wire_Error =>
         raise Wire_Error with
           Where & ": in `" & Text & "`: "
           & Ada.Exceptions.Exception_Message (X);
   end Parse_Expression;

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

   ---------------------------------------------------------------------------
   --  Queries and checks
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

   procedure Check_Code_Language (G : Grammar; Backend : String) is
      Has_Code : Boolean :=
        G.Preamble /= Null_Unbounded_String
        or else G.Epilogue /= Null_Unbounded_String;
   begin
      for R of G.Rules loop
         if R.Action /= Null_Unbounded_String
           or else R.Emit /= Null_Unbounded_String
         then
            Has_Code := True;
         end if;
      end loop;
      if Has_Code and then To_String (G.Language) /= Backend then
         raise Wire_Error with
           "this grammar has code (a preamble, an epilogue, an %action or an "
           & "%emit), and it is written in " & To_String (G.Language)
           & " (the file's `language` line, C if it has none), so it can be "
           & "emitted in " & To_String (G.Language) & ", not in " & Backend
           & ".  For " & Backend & ", write the same code in " & Backend
           & " in a file that says `language " & Backend & "`; a grammar with "
           & "no code goes to every backend";
      end if;
   end Check_Code_Language;

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

   --  The checks of a wire grammar, once it is read (or lowered from the
   --  main notation): names, scopes of expressions, offsets, cycles.
   procedure Check (G : in out Grammar; File : String) is

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
               if To_String (E.Name) = "align"
                 and then not (for some A of R.Alts =>
                                 (for some X of A.Items => X.Bitsof))
               then
                  raise Wire_Error with
                    (if File = "" then "" else File & ":") & Img (Line) & ":"
                    & Img (Col) & ": rule `" & To_String (R.Name) & "`: "
                    & "`align` is the bits to the next unit boundary of a "
                    & "`name:bitsof(rule)` field, and this rule has none";
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
                  K : constant Natural := Find (G, To_String (It.Ref));
               begin
                  if K = 0
                    and then (for some X of G.Externals => X = It.Ref)
                  then
                     null;     --  a text rule: read by the text parser
                  elsif K = 0 then
                     Fail_At (It.all,
                              "`" & To_String (It.Ref) & "` is not a rule "
                              & "in this file; define it, or give the field "
                              & "a width (`" & To_String (It.Name) & ":8`)");
                  elsif Is_Value_Set (G.Rules (K)) then
                     It.Kind := S_Bits;
                     It.Bits := Value_Width (G.Rules (K));
                  end if;
               end;
            elsif It.Kind = S_Bits and then It.Name /= Null_Unbounded_String then
               declare
                  K : constant Natural := Find (G, To_String (It.Name));
               begin
                  --  `ethertype:16` where `ethertype` is a set of values.
                  if K /= 0 and then Is_Value_Set (G.Rules (K)) then
                     if Value_Width (G.Rules (K)) /= It.Bits then
                        Fail_At
                          (It.all,
                           "`" & To_String (It.Name) & ":" & Img (It.Bits)
                           & "` but the rule `" & To_String (It.Name)
                           & "` lists values of "
                           & Img (Value_Width (G.Rules (K))) & " bits ("
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
                       (G, (Items => Item_Vectors.To_Vector (It, 1),
                              others => <>));
                  begin
                     Off := (if Off >= 0 and then B >= 0 then Off + B else -1);
                  end;
               when S_Array =>
                  if Find (G, To_String (It.Ref)) = 0 then
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
         Marks : array (1 .. Natural (G.Rules.Length)) of Mark :=
           [others => White];

         procedure Visit (K : Positive; Path : String);

         procedure Walk (V : Seq_Vectors.Vector; Path : String) is
         begin
            for S of V loop
               for It of S.Items loop
                  if It.Kind = S_Ref then
                     if Find (G, To_String (It.Ref)) /= 0 then
                        Visit (Find (G, To_String (It.Ref)),
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
                 & Img (G.Rules (K).Line) & ": rule `"
                 & To_String (G.Rules (K).Name) & "` contains itself ("
                 & Path & "): a record cannot hold itself by value. Put the "
                 & "inner one in a counted array, `inner:0*1 name`.";
            elsif Marks (K) = White then
               Marks (K) := Grey;
               Walk (G.Rules (K).Alts, Path);
               Marks (K) := Black;
            end if;
         end Visit;
      begin
         for K in Marks'Range loop
            Visit (K, To_String (G.Rules (K).Name));
         end loop;
      end Check_Cycles;
   begin
      if G.Rules.Is_Empty then
         raise Wire_Error with
           (if File = "" then "" else File & ":")
           & "1: a binary grammar needs at least one rule";
      end if;

      Check_Cycles;
      declare
         Empty : Name_Vectors.Vector;
      begin
         for R of G.Rules loop
            if not Is_Value_Set (R) then
               for A of R.Alts loop
                  Check_Seq (A.all, Empty, R);
               end loop;
            end if;
         end loop;
      end;
   end Check;

   procedure Note_Shift (Rule : String; Bit : Natural) is
   begin
      if Shift_Note = Null_Unbounded_String then
         Shift_Note := To_Unbounded_String
           ("in `" & Rule & "` text follows fields that end at bit"
            & Natural'Image (Bit) & " of an octet, so its octets are read "
            & "shifted.  That is allowed, but it is most often a missing "
            & "field or padding.");
      end if;
   end Note_Shift;

end HBNF_Wire;
