pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package body ASTBNF_Rust is

   use Ada.Strings.Unbounded;
   use ASTBNF;

   subtype U is Unbounded_String;

   LF : constant Character := ASCII.LF;

   package String_Vectors is new Ada.Containers.Vectors (Positive, U);

   --  The Rust type for a built-in core rule, or "" if not a core scalar.
   function Scalar_Rust_Type (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "String";
      elsif Name = "int" then
         return "i64";
      elsif Name = "dec" then
         return "f64";
      elsif Name = "float" then
         return "f32";
      elsif Name = "bool" or else Name = "flag" then
         return "bool";
      elsif Name'Length >= 2 then
         declare
            P : constant Character := Name (Name'First);
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            if (P = 'u' or else P = 'i')
              and then (for all C of R => C in '0' .. '9')
            then
               return (if P = 'u' then "u" else "i") & R;
            end if;
         end;
      end if;
      return "";
   end Scalar_Rust_Type;

   --  A snake_case identifier from a schema name ('-' -> '_').
   function Rust_Snake (S : String) return String is
      Buf : U;
   begin
      for C of S loop
         Append (Buf, (if C = '-' then '_' else C));
      end loop;
      return To_String (Buf);
   end Rust_Snake;

   --  A PascalCase type name from a schema name ('-' / '_' split a word).
   function Rust_Type (S : String) return String is
      Buf : U;
      Up  : Boolean := True;
   begin
      for C of S loop
         if C = '-' or else C = '_' then
            Up := True;
         elsif Up then
            Append (Buf, (if C in 'a' .. 'z'
                          then Character'Val (Character'Pos (C) - 32)
                          else C));
            Up := False;
         else
            Append (Buf, C);
         end if;
      end loop;
      return To_String (Buf);
   end Rust_Type;

   --  A field name: snake_case, with a "_" suffix if it is a Rust keyword.
   function Rust_Field (S : String) return String is
      N : constant String := Rust_Snake (S);
   begin
      if N = "as" or else N = "break" or else N = "const"
        or else N = "continue" or else N = "crate" or else N = "dyn"
        or else N = "else" or else N = "enum" or else N = "extern"
        or else N = "false" or else N = "fn" or else N = "for"
        or else N = "if" or else N = "impl" or else N = "in"
        or else N = "let" or else N = "loop" or else N = "match"
        or else N = "mod" or else N = "move" or else N = "mut"
        or else N = "pub" or else N = "ref" or else N = "return"
        or else N = "self" or else N = "static" or else N = "struct"
        or else N = "super" or else N = "trait" or else N = "true"
        or else N = "type" or else N = "unsafe" or else N = "use"
        or else N = "where" or else N = "while" or else N = "async"
        or else N = "await" or else N = "box" or else N = "do"
        or else N = "final" or else N = "macro" or else N = "override"
        or else N = "priv" or else N = "try" or else N = "typeof"
        or else N = "unsized" or else N = "virtual" or else N = "yield"
      then
         return N & "_";
      end if;
      return N;
   end Rust_Field;

   function Emit (Rules : Rule_Vectors.Vector) return String is

      N : constant Natural := Natural (Rules.Length);

      function Find (Name : String) return Natural is
      begin
         for I in 1 .. N loop
            if To_String (Rules (I).Name) = Name then
               return I;
            end if;
         end loop;
         return 0;
      end Find;

      --  The Rust type a rule reference denotes: a core scalar inlines; any
      --  other reference resolves to the referenced rule's own type name.
      function Rust_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Rust_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         if Find (Ref) = 0 then
            raise Parse_Error with "undefined rule: " & Ref;
         end if;
         return Rust_Type (Ref);
      end Rust_Type_Of;

      --  A struct member: the referenced name, and whether it is a list
      --  (appeared with a repetition prefix) rather than a single value.
      type Member is record
         Name    : U;
         Is_List : Boolean;
      end record;

      package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

      function Contains (V : Member_Vectors.Vector; S : U) return Boolean is
      begin
         for X of V loop
            if X.Name = S then
               return True;
            end if;
         end loop;
         return False;
      end Contains;

      --  Walk a pattern, collecting referenced rule names (deduped, in order)
      --  as Members (Is_List marks a repeated reference), the literal strings,
      --  and whether any '/' alternation appears.
      procedure Collect
        (Els     : Element_Vectors.Vector;
         Members : in out Member_Vectors.Vector;
         Lits    : in out String_Vectors.Vector;
         Has_Alt : in out Boolean) is
      begin
         for E of Els loop
            case E.Kind is
               when Name =>
                  declare
                     Is_List : constant Boolean :=
                       E.Min /= 1 or else E.Max /= 1;
                  begin
                     if Contains (Members, E.Name) then
                        if Is_List then
                           for K in 1 .. Natural (Members.Length) loop
                              if Members (K).Name = E.Name then
                                 Members.Replace_Element
                                   (K,
                                    Member'(Name => E.Name, Is_List => True));
                              end if;
                           end loop;
                        end if;
                     else
                        Members.Append
                          (Member'(Name => E.Name, Is_List => Is_List));
                     end if;
                  end;
               when Literal =>
                  Lits.Append (E.Lit);
               when Alt =>
                  Has_Alt := True;
               when Group =>
                  Collect (E.Items, Members, Lits, Has_Alt);
            end case;
         end loop;
      end Collect;

      type Class_Kind is (Enum, Scalar, List, Struct);

      type Rule_Info (Kind : Class_Kind := Scalar) is record
         case Kind is
            when Enum =>
               Literals : String_Vectors.Vector := String_Vectors.Empty_Vector;
            when Scalar =>
               Inline_Type : U := Null_Unbounded_String;
            when List =>
               Elem_Name    : U := Null_Unbounded_String;
               Elem_Members : Member_Vectors.Vector;
            when Struct =>
               Members : Member_Vectors.Vector := Member_Vectors.Empty_Vector;
         end case;
      end record;

      package Info_Vectors is new Ada.Containers.Vectors (Positive, Rule_Info);

      function Analyze (Idx : Natural) return Rule_Info is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if Natural (P.Length) = 1 then
            declare
               E : constant Element_Access := P (1);
            begin
               --  Repetition => a list.
               if E.Min /= 1 or else E.Max /= 1 then
                  if E.Kind = Name then
                     return (Kind        => List,
                             Elem_Name    => E.Name,
                             Elem_Members => Member_Vectors.Empty_Vector);
                  elsif E.Kind = Group then
                     declare
                        Members : Member_Vectors.Vector;
                        Lits    : String_Vectors.Vector;
                        Has_Alt : Boolean := False;
                     begin
                        Collect (E.Items, Members, Lits, Has_Alt);
                        return (Kind        => List,
                                Elem_Name    => Null_Unbounded_String,
                                Elem_Members => Members);
                     end;
                  else
                     return (Kind        => List,
                             Elem_Name    => Null_Unbounded_String,
                             Elem_Members => Member_Vectors.Empty_Vector);
                  end if;
               end if;

               --  Single element, no repetition.
               if E.Kind = Name then
                  return (Kind => Scalar,
                          Inline_Type =>
                            To_Unbounded_String
                              (Rust_Type_Of (To_String (E.Name))));
               elsif E.Kind = Group then
                  declare
                     Members : Member_Vectors.Vector;
                     Lits    : String_Vectors.Vector;
                     Has_Alt : Boolean := False;
                  begin
                     Collect (E.Items, Members, Lits, Has_Alt);
                     return (Kind => Struct, Members => Members);
                  end;
               else
                  return (Kind        => Scalar,
                          Inline_Type => To_Unbounded_String ("String"));
               end if;
            end;
         end if;

         declare
            Members : Member_Vectors.Vector;
            Lits    : String_Vectors.Vector;
            Has_Alt : Boolean := False;
         begin
            Collect (P, Members, Lits, Has_Alt);
            if Members.Is_Empty then
               return (Kind => Enum, Literals => Lits);
            else
               return (Kind => Struct, Members => Members);
            end if;
         end;
      end Analyze;

      Infos : Info_Vectors.Vector;

      function Emit_Rule (Idx : Natural; Info : Rule_Info) return String is
         R    : constant Rule := Rules (Idx);
         Base : constant String := Rust_Type (To_String (R.Name));
         Buf  : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append (Buf, "// " & To_String (R.Leading_Comment));
            Append (Buf, LF);
         end if;

         case Info.Kind is
            when Scalar =>
               Append (Buf, "pub type " & Base & " = " &
                       To_String (Info.Inline_Type) & ";");
               Append (Buf, LF);
            when Enum =>
               Append (Buf, "pub enum " & Base & " {");
               Append (Buf, LF);
               for I in 1 .. Natural (Info.Literals.Length) loop
                  Append (Buf, "    " & Base & "_" &
                          Rust_Type (To_String (Info.Literals (I))) & ",");
                  Append (Buf, LF);
               end loop;
               Append (Buf, "}");
               Append (Buf, LF);
            when Struct =>
               Append (Buf, "pub struct " & Base & " {");
               Append (Buf, LF);
               for M of Info.Members loop
                  Append (Buf, "    pub " &
                          Rust_Field (To_String (M.Name)) & ": ");
                  if M.Is_List then
                     Append (Buf, "Vec<" &
                             Rust_Type_Of (To_String (M.Name)) & ">,");
                  else
                     Append (Buf, Rust_Type_Of (To_String (M.Name)) & ",");
                  end if;
                  Append (Buf, LF);
               end loop;
               Append (Buf, "}");
               Append (Buf, LF);
            when List =>
               null;  --  handled by Emit_List
         end case;

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " // " & To_String (R.Trailing_Comment));
            Append (Buf, LF);
         end if;
         return To_String (Buf);
      end Emit_Rule;

      --  A top-level list rule: a `Vec<T>` alias.  A group element becomes a
      --  named `BaseEntry` struct first.
      function Emit_List (Idx : Natural; Info : Rule_Info) return String is
         R    : constant Rule := Rules (Idx);
         Base : constant String := Rust_Type (To_String (R.Name));
         Buf  : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append (Buf, "// " & To_String (R.Leading_Comment));
            Append (Buf, LF);
         end if;

         if Info.Elem_Members.Is_Empty then
            if Info.Elem_Name = Null_Unbounded_String then
               Append (Buf, "pub type " & Base & " = Vec<String>;");
            else
               Append (Buf, "pub type " & Base & " = Vec<" &
                       Rust_Type_Of (To_String (Info.Elem_Name)) & ">;");
            end if;
         else
            Append (Buf, "pub struct " & Base & "Entry {");
            Append (Buf, LF);
            for M of Info.Elem_Members loop
               Append (Buf, "    pub " &
                       Rust_Field (To_String (M.Name)) & ": " &
                       Rust_Type_Of (To_String (M.Name)) & ",");
               Append (Buf, LF);
            end loop;
            Append (Buf, "}");
            Append (Buf, LF);
            Append (Buf, "pub type " & Base & " = Vec<" & Base & "Entry>;");
         end if;
         Append (Buf, LF);

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " // " & To_String (R.Trailing_Comment));
            Append (Buf, LF);
         end if;
         return To_String (Buf);
      end Emit_List;

      Res : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (I));
      end loop;

      Append (Res, "// generated by astbnf -- do not edit");
      Append (Res, LF);
      Append (Res, LF);

      --  Rust needs no forward declarations or ordering: every rule emits in
      --  source order, and `Vec<T>` (heap) breaks any recursion a repetition
      --  introduces.
      for I in 1 .. N loop
         if Infos (I).Kind = List then
            Append (Res, Emit_List (I, Infos (I)));
         else
            Append (Res, Emit_Rule (I, Infos (I)));
         end if;
         Append (Res, LF);
      end loop;

      return To_String (Res);
   end Emit;

   function Emit_Parser (Rules : ASTBNF.Rule_Vectors.Vector) return String is
   begin
      return "";
   end Emit_Parser;

end ASTBNF_Rust;
