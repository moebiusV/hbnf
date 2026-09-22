   function Lex (Text : String) return Token_Vectors.Vector is
      Toks : Token_Vectors.Vector;
      I    : Natural := Text'First;
      Line : Natural := 1;
      Col  : Natural := 1;
      C    : Character;
   begin
      while I <= Text'Last loop
         C := Text (I);
         declare
            JK : Token_Kind;
            JL : constant Natural := Jet_Dispatch (Text, I, Text'Last, JK);
         begin
            if JL > 0 then
               Toks.Append (Token'(JK, To_Unbounded_String (Text (I .. I + JL - 1)), Line, Col));
               I := I + JL; Col := Col + JL;
            elsif C = ' ' or else C = ASCII.HT or else C = ASCII.CR then
               I := I + 1; Col := Col + 1;
         elsif C = ASCII.LF then
            I := I + 1; Line := Line + 1; Col := 1;
         elsif C = '#' then
            while I <= Text'Last and then Text (I) /= ASCII.LF loop
               I := I + 1;
            end loop;
         elsif C = '"' then
            declare
               SC  : constant Natural := Col;
               Buf : Unbounded_String;
            begin
               I := I + 1; Col := Col + 1;
               while I <= Text'Last and then Text (I) /= '"' loop
                  if Text (I) = '\' and then I < Text'Last then
                     I := I + 1; Col := Col + 1;
                  end if;
                  Append (Buf, Text (I));
                  I := I + 1; Col := Col + 1;
               end loop;
               if I <= Text'Last then
                  I := I + 1; Col := Col + 1;
               end if;
               Toks.Append (Token'(Str, Buf, Line, SC));
            end;
         elsif C in '0' .. '9' then
            declare
               SC      : constant Natural := Col;
               Start_I : constant Natural := I;
               Buf     : Unbounded_String;
            begin
               while I <= Text'Last and then Text (I) in '0' .. '9' loop
                  Append (Buf, Text (I)); I := I + 1; Col := Col + 1;
               end loop;
               if I <= Text'Last
                 and then (Text (I) in 'a' .. 'z' or else Text (I) in 'A' .. 'Z'
                   or else Text (I) = '.' or else Text (I) = '_'
                   or else Text (I) = '-')
               then
                  --  dotted/alphanumeric run (1.2.3.4, 123abc) is one word
                  I := Start_I; Col := SC;
                  Buf := Null_Unbounded_String;
                  while I <= Text'Last loop
                     C := Text (I);
                     exit when not (C in 'a' .. 'z' or else C in 'A' .. 'Z'
                       or else C in '0' .. '9' or else C = '_' or else C = '-'
                       or else C = '.');
                     Append (Buf, C); I := I + 1; Col := Col + 1;
                  end loop;
                  Toks.Append (Token'(Atom, Buf, Line, SC));
               else
                  Toks.Append (Token'(Int, Buf, Line, SC));
               end if;
            end;
         elsif C in 'a' .. 'z' or else C in 'A' .. 'Z' or else C = '_' or else C = '-' then
            declare
               SC  : constant Natural := Col;
               Buf : Unbounded_String;
            begin
               while I <= Text'Last loop
                  C := Text (I);
                  exit when not (C in 'a' .. 'z' or else C in 'A' .. 'Z'
                    or else C in '0' .. '9' or else C = '_' or else C = '-'
                    or else C = '.');
                  Append (Buf, C); I := I + 1; Col := Col + 1;
               end loop;
               Toks.Append (Token'(Atom, Buf, Line, SC));
            end;
         else
            declare
               Buf : Unbounded_String;
            begin
               Append (Buf, C);
               Toks.Append (Token'(Punct, Buf, Line, Col));
               I := I + 1; Col := Col + 1;
            end;
         end if;
         end;
      end loop;
      Toks.Append (Token'(Eof, Null_Unbounded_String, Line, Col));
      return Toks;
   end Lex;

   function Parse_Text (Text : String) return @ROOT_TYPE@ is
      Toks  : Token_Vectors.Vector := Lex (Text);
      Lines : Line_Vectors.Vector;
      S     : Natural := Text'First;
   begin
      for K in Text'Range loop
         if Text (K) = ASCII.LF then
            Lines.Append (To_Unbounded_String (Text (S .. K - 1)));
            S := K + 1;
         end if;
      end loop;
      Lines.Append (To_Unbounded_String (Text (S .. Text'Last)));
      declare
         P : Parser := (Toks => Toks, Lines => Lines, Pos => 1);
         R : @ROOT_TYPE@;
      begin
         R := @ROOT_FN@ (P);
         if P.Pos <= Natural (P.Toks.Length) and then P.Toks (P.Pos).Kind /= Eof then
            Fail (P, "end of config");
         end if;
         return R;
      end;
   end Parse_Text;
