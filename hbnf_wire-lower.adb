pragma Ada_2022;

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
                       "`units` names the rule `" & Name & "`, which is not "
                       & "a list of plain literals (`" & Name
                       & " = ""q"" | ""p"" | ...`)";
                  end if;
               end loop;
            end if;
         end loop;
         if not Found then
            raise Wire_Error with
              "`units` names the rule `" & Name & "`, which this grammar "
              & "does not define; write it, or `include` the file that does";
         end if;
      end Spellings;
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
      if GR.Units_Width > 0 then
         Result.Unit_Width := GR.Units_Width;
         Spellings (GR.Units_Rule, Result.Units);
         for U of Result.Units loop
            if U.Value >= 2 ** Result.Unit_Width then
               raise Wire_Error with
                 "`" & To_String (U.Spelling) & "` has the value"
                 & Natural'Image (U.Value) & ", which does not fit a unit of"
                 & Natural'Image (Result.Unit_Width) & " bits";
            end if;
         end loop;
         if GR.Units_Separator /= "" then
            declare
               Seps : Unit_Vectors.Vector;
            begin
               Spellings (GR.Units_Separator, Seps);
               if Natural (Seps.Length) /= 1 then
                  raise Wire_Error with
                    "the separator `" & GR.Units_Separator
                    & "` must be one literal";
               end if;
               Result.Unit_Sep := Seps.First_Element.Spelling;
            end;
         end if;
      end if;
      Check (Result, File);
      return Result;
   end Lower;

end HBNF_Wire.Lower;
