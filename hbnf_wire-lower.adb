pragma Ada_2022;

with HBNF_C;

package body HBNF_Wire.Lower is

   package GR renames HBNF_Grammar;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   --  A rule or field name becomes an identifier in the generated code, as it
   --  does in the text backends: a hyphen is an underscore.
   function Ident (S : Unbounded_String) return Unbounded_String is
      R : String := To_String (S);
   begin
      for C of R loop
         if C = '-' then
            C := '_';
         end if;
      end loop;
      return To_Unbounded_String (R);
   end Ident;

   function Lower
     (Wire : GR.Rule_Vectors.Vector;
      Text : GR.Rule_Vectors.Vector;
      File : String) return Grammar
   is
      Result : Grammar;
      Where_File : constant String := (if File = "" then "" else File & ":");

      procedure Lower_Alts
        (V : GR.Element_Vectors.Vector; Alts : out Seq_Vectors.Vector;
         Rule_Name : String);

      procedure Fill_Words (It : Item_Access; Pos : String);

      function Find_Wire (N : String) return Boolean is
        (for some R of Wire => To_String (R.Name) = N);

      procedure Refuse (E : GR.Element; Rule_Name : String; What : String) is
      begin
         raise Wire_Error with
           Where_File & "rule `" & Rule_Name & "`: " & What;
      end Refuse;

      procedure Lower_Element
        (E : GR.Element_Access; S : Sequence_Access; Rule_Name : String)
      is
         use type GR.Element_Kind;
      begin
         case E.Kind is
            when GR.Bit_Field =>
               declare
                  Pos : constant String :=
                    Where_File & Img (E.F_Line) & ":" & Img (E.F_Col);
                  It  : constant Item_Access :=
                    new Item'(Kind => E.F_Kind, Name => Ident (E.F_Name),
                              Bits => E.F_Bits, Value => E.F_Value,
                              Signed => E.F_Signed, Little => E.F_Little,
                              At_Bit => E.F_At, Ref => Ident (E.F_Ref),
                              Min => E.F_Min, Max => E.F_Max,
                              Line => E.F_Line, Col => E.F_Col,
                              others => <>);
               begin
                  case E.F_Kind is
                     when S_Octets | S_Bit_Expr =>
                        It.Count := Parse_Expression
                          (To_String (E.F_Expr), Pos);
                     when S_Array =>
                        if E.F_Expr /= Null_Unbounded_String then
                           It.Count := Parse_Expression
                             (To_String (E.F_Expr), Pos);
                        end if;
                     when S_Choice =>
                        Lower_Alts (E.F_Alts, It.Alts, Rule_Name);
                     when S_Assert =>
                        It.Count := Parse_Expression
                          (To_String (E.F_Expr), Pos);
                        It.Ref := E.F_Message;
                     when others =>
                        null;
                  end case;
                  if E.F_Bitsof then
                     It.Bitsof := True;
                     if Find_Wire (To_String (E.F_Ref)) then
                        Refuse (E.all, Rule_Name,
                                "`bitsof(" & To_String (E.F_Ref) & ")` names "
                                & "a bit rule; it takes a text rule");
                     end if;
                     Fill_Words (It, Pos);
                  end if;
                  --  `?(cond)` at the head of an alternative picks it; with
                  --  words after it, or further on, it is a check.
                  if E.F_Kind = S_Assert
                    and then E.F_Message = Null_Unbounded_String
                    and then S.Items.Is_Empty and then S.Guard = null
                  then
                     S.Guard := It.Count;
                  else
                     S.Items.Append (It);
                  end if;
               end;
            when GR.Name =>
               if E.Min /= 1 or else E.Max /= 1 then
                  Refuse (E.all, Rule_Name,
                          "`" & To_String (E.Name) & "` is repeated; give a "
                          & "repeated record a field name: `entries:*"
                          & To_String (E.Name) & "`");
               end if;
               S.Items.Append
                 (new Item'(Kind => S_Ref, Name => Ident (E.Name), Ref => Ident (E.Name),
                            others => <>));
            when GR.Group =>
               declare
                  Alts : Seq_Vectors.Vector;
               begin
                  Lower_Alts (E.Items, Alts, Rule_Name);
                  if Natural (Alts.Length) /= 1 then
                     Refuse (E.all, Rule_Name,
                             "a choice needs a field to hold it: write "
                             & "`name:( a | b )`");
                  end if;
                  if Alts.First_Element.Guard /= null then
                     Refuse (E.all, Rule_Name,
                             "a guard `?(...)` belongs to an alternative of a "
                             & "choice");
                  end if;
                  for It of Alts.First_Element.Items loop
                     S.Items.Append (It);
                  end loop;
               end;
            when others =>
               Refuse (E.all, Rule_Name,
                       "text and bit fields in one rule (a literal, a "
                       & "character class, a negation or a code block among "
                       & "fields) are not read together yet; keep the text in "
                       & "rules of its own and the bit fields in theirs "
                       & "(RFCPLAN.md step 7b, the direction)");
         end case;
      end Lower_Element;

      procedure Lower_Alts
        (V : GR.Element_Vectors.Vector; Alts : out Seq_Vectors.Vector;
         Rule_Name : String)
      is
         use type GR.Element_Kind;
         Cur : Sequence_Access := new Sequence;
      begin
         Alts.Clear;
         for E of V loop
            if E.Kind = GR.Alt then
               Alts.Append (Cur);
               Cur := new Sequence;
            else
               Lower_Element (E, Cur, Rule_Name);
            end if;
         end loop;
         Alts.Append (Cur);
      end Lower_Alts;

      --  The literals of a text rule, in order, with their numbers.
      procedure Spellings
        (Name : String; Out_Units : in out Unit_Vectors.Vector)
      is
         use type GR.Element_Kind;
         Found : Boolean := False;
         Place : Natural := 0;
      begin
         for R of Text loop
            if To_String (R.Name) = Name then
               Found := True;
               for E of R.Pattern loop
                  if E.Kind = GR.Literal then
                     declare
                        V : constant Integer :=
                          GR.Enum_Value (Name, To_String (E.Lit));
                     begin
                        Out_Units.Append
                          (Unit'(Spelling => E.Lit,
                                 Value => (if V >= 0 then V else Place)));
                        Place := Place + 1;
                     end;
                  elsif E.Kind /= GR.Alt then
                     raise Wire_Error with
                       "`bitsof` needs the rule `" & Name & "`, which is not "
                       & "a list of plain literals (`" & Name
                       & " = ""q"" | ""p"" | ...`)";
                  end if;
               end loop;
            end if;
         end loop;
         if not Found then
            raise Wire_Error with
              "`bitsof` needs the rule `" & Name & "`, which this grammar "
              & "does not define; write it, or `include` the file that does";
         end if;
      end Spellings;

      --  `name:bitsof(rule)`: find the one rule of numbered words in the text
      --  rule (an enum whose literals are numbered), how wide a number is, how
      --  the words are spelled, and what stands between two words.
      procedure Fill_Words (It : Item_Access; Pos : String) is
         use type GR.Element_Kind;
         Name    : constant String := To_String (It.Ref);
         Raw     : Unbounded_String := It.Ref;
         Visited : Name_Vectors.Vector;
         Word    : Unbounded_String;

         function Index_Of (N : String) return Natural is
         begin
            for I in 1 .. Natural (Text.Length) loop
               if To_String (Text (I).Name) = N
                 or else To_String (Ident (Text (I).Name)) = N
               then
                  return I;
               end if;
            end loop;
            return 0;
         end Index_Of;

         function Plain_Enum (R : GR.Rule) return Boolean is
            Lits : Natural := 0;
         begin
            for E of R.Pattern loop
               if E.Kind = GR.Literal then
                  Lits := Lits + 1;
               elsif E.Kind /= GR.Alt then
                  return False;
               end if;
            end loop;
            return Lits > 1;
         end Plain_Enum;

         procedure Visit (N : String);

         procedure Visit_Els (Els : GR.Element_Vectors.Vector) is
         begin
            for E of Els loop
               if E.Kind = GR.Name then
                  Visit (To_String (E.Name));
               elsif E.Kind = GR.Group then
                  Visit_Els (E.Items);
               end if;
            end loop;
         end Visit_Els;

         procedure Visit (N : String) is
            J : constant Natural := Index_Of (N);
         begin
            if J = 0 or else Visited.Contains (To_Unbounded_String (N)) then
               return;
            end if;
            Visited.Append (To_Unbounded_String (N));
            if Plain_Enum (Text (J)) then
               if Word = Null_Unbounded_String then
                  Word := To_Unbounded_String (N);
               elsif To_String (Word) /= N then
                  raise Wire_Error with
                    Pos & ": `bitsof(" & Name & ")`: `" & To_String (Word)
                    & "` and `" & N & "` are both rules of words; the bits "
                    & "come from one, so name one of them as the unit";
               end if;
            else
               Visit_Els (Text (J).Pattern);
            end if;
         end Visit;

         --  The literal text a rule or literal stands for, if it is just one.
         function Literal_Of (E : GR.Element_Access) return String is
         begin
            if E.Kind = GR.Literal then
               return To_String (E.Lit);
            elsif E.Kind = GR.Name then
               declare
                  J : constant Natural := Index_Of (To_String (E.Name));
               begin
                  if J /= 0 and then Natural (Text (J).Pattern.Length) = 1
                    and then Text (J).Pattern (1).Kind = GR.Literal
                  then
                     return To_String (Text (J).Pattern (1).Lit);
                  end if;
               end;
            end if;
            return "";
         end Literal_Of;

         Sep_Found : Boolean := False;

         procedure Find_Sep (Els : GR.Element_Vectors.Vector) is
         begin
            for I in 1 .. Natural (Els.Length) loop
               exit when Sep_Found;
               if Els (I).Kind = GR.Group then
                  Find_Sep (Els (I).Items);
               elsif Els (I).Kind = GR.Name and then I > 1
                 and then To_String (Els (I).Name) = To_String (Word)
               then
                  declare
                     S : Unbounded_String;
                     J : Natural := I - 1;
                  begin
                     while J >= 1 and then Literal_Of (Els (J)) /= "" loop
                        S := To_Unbounded_String (Literal_Of (Els (J)))
                             & S;
                        J := J - 1;
                     end loop;
                     if S /= Null_Unbounded_String then
                        It.Sep := S;
                        Sep_Found := True;
                     end if;
                  end;
               end if;
            end loop;
         end Find_Sep;
      begin
         if Index_Of (Name) = 0 then
            raise Wire_Error with
              Pos & ": `bitsof(" & Name & ")`: the grammar has no text rule "
              & "of that name; write it, or `include` the file that does";
         end if;
         Raw := Text (Index_Of (Name)).Name;
         Visit (Name);
         if Word = Null_Unbounded_String then
            raise Wire_Error with
              Pos & ": `bitsof(" & Name & ")`: `" & Name & "` holds no rule "
              & "of numbered words (a rule such as `word = ""abandon"" | "
              & """ability"" | ...`, whose literals are numbered by their "
              & "place or by `""x""@7`)";
         end if;
         It.Word_Rule := Word;
         Spellings (To_String (Word), It.Words);
         declare
            Max : Natural := 0;
         begin
            for U of It.Words loop
               Max := Natural'Max (Max, U.Value);
            end loop;
            It.Width := 1;
            while Max >= 2 ** It.Width loop
               It.Width := It.Width + 1;
            end loop;
         end;
         for Rn of Visited loop
            declare
               J : constant Natural := Index_Of (To_String (Rn));
            begin
               if J /= 0 then
                  Find_Sep (Text (J).Pattern);
               end if;
            end;
         end loop;
         It.Tmp_Type := To_Unbounded_String
           (HBNF_C.Value_Type (Text, To_String (Raw)));
         It.Tmp_Free := To_Unbounded_String
           (HBNF_C.Value_Free (Text, To_String (Raw)));
      end Fill_Words;
   begin
      for R of Wire loop
         declare
            Rl : Rule;
         begin
            Rl.Name := Ident (R.Name);
            Lower_Alts (R.Pattern, Rl.Alts, To_String (R.Name));
            Rl.Action := R.Action_Code;
            Rl.Emit := To_Unbounded_String
              (GR.Emit_Code (To_String (R.Name)));
            Result.Rules.Append (Rl);
         end;
      end loop;
      Result.Prefix := To_Unbounded_String (GR.Name_Prefix);
      Result.Language := To_Unbounded_String (GR.Language);
      Result.Preamble := To_Unbounded_String (GR.Preamble (GR.Language));
      Result.Epilogue := To_Unbounded_String (GR.Epilogue (GR.Language));
      for R of Text loop
         Result.Externals.Append (Ident (R.Name));
         if GR.Is_Char_Rule (Text, To_String (R.Name)) then
            Result.External_Tokens.Append (Ident (R.Name));
         end if;
      end loop;
      Check (Result, File);
      return Result;
   end Lower;

end HBNF_Wire.Lower;
