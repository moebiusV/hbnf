pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Templates;

package body HBNF_Rust is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

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

   --  True when every `/`-alternative is exactly one Literal — the shape an
   --  enum can hold.  A multi-token alternative (`"a" "b" / "c" "d"`), one that
   --  names another rule, or a single literal (no `/`) is not an enum.
   function Is_Pure_Literal_Alt (Els : Element_Vectors.Vector) return Boolean is
      N       : constant Natural := Natural (Els.Length);
      St      : Natural := 1;
      Has_Alt : Boolean := False;
   begin
      for K in 1 .. N + 1 loop
         if K > N then
            --  final alternative [St..N] must be exactly one literal
            if N /= St or else Els (St).Kind /= Literal then
               return False;
            end if;
         elsif Els (K).Kind = Alt then
            --  alternative [St..K-1] must be exactly one literal
            if K - 1 /= St or else Els (St).Kind /= Literal then
               return False;
            end if;
            St := K + 1;
            Has_Alt := True;
         end if;
      end loop;
      return Has_Alt;
   end Is_Pure_Literal_Alt;

   --  Natural'Image with the leading blank stripped ("1", not " 1").
   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Img;

   --  Unique enumerator names for a literal list.  Each literal is mapped
   --  through Rust_Type and then any non-alphanumeric folded to '_', so
   --  "tlsv1.0" -> "Tlsv1_0".  A name that is empty, all '_', or begins with
   --  a digit (pure punctuation like "*" or "!=") becomes `Op<pos>`; and
   --  collisions are deduped with _2, _3, ...
   function Enum_Names (Lits : String_Vectors.Vector) return String_Vectors.Vector is
      Names : String_Vectors.Vector;

      function Fold (S : String) return String is
         Buf : U;
      begin
         for C of S loop
            if C in 'a' .. 'z' or else C in 'A' .. 'Z'
              or else C in '0' .. '9'
            then
               Append (Buf, C);
            else
               Append (Buf, '_');
            end if;
         end loop;
         return To_String (Buf);
      end Fold;

      function Used (S : String) return Boolean is
      begin
         for X of Names loop
            if To_String (X) = S then
               return True;
            end if;
         end loop;
         return False;
      end Used;
   begin
      for I in 1 .. Natural (Lits.Length) loop
         declare
            Base : constant String := Fold (Rust_Type (To_String (Lits (I))));
            N    : U;
         begin
            if Base = "" or else (for all C of Base => C = '_')
              or else Base (Base'First) in '0' .. '9'
            then
               N := To_Unbounded_String ("Op" & Img (I));
            else
               N := To_Unbounded_String (Base);
            end if;
            if Used (To_String (N)) then
               declare
                  K : Natural := 2;
               begin
                  while Used (To_String (N) & "_" & Img (K)) loop
                     K := K + 1;
                  end loop;
                  N := To_Unbounded_String (To_String (N) & "_" & Img (K));
               end;
            end if;
            Names.Append (N);
         end;
      end loop;
      return Names;
   end Enum_Names;

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

      --  The underlying scalar Rust type a rule name resolves to, chasing
      --  single-name aliases and jets to their target (so `str / word` and
      --  `ipv4 / ipv6` both collapse to `String`).  "" if not scalar.
      function Resolve_Type (N : String; Depth : Natural := 0) return String is
         C : constant String := Scalar_Rust_Type (N);
      begin
         if C /= "" then
            return C;
         end if;
         if Depth > 8 then
            return "";
         end if;
         declare
            J : constant Natural := Find (N);
         begin
            if J = 0 then
               return "";
            end if;
            declare
               R : constant Rule := Rules (J);
               P : constant Element_Vectors.Vector := R.Pattern;
            begin
               if R.Jet_Code /= Null_Unbounded_String then
                  return "String";
               end if;
               if Natural (P.Length) = 1
                 and then P (1).Kind = Name
                 and then P (1).Min = 1
                 and then P (1).Max = 1
               then
                  return Resolve_Type (To_String (P (1).Name), Depth + 1);
               end if;
            end;
         end;
         return "";
      end Resolve_Type;

      --  If the pattern is a pure alternation of names that all resolve to
      --  the same scalar Rust type, that type (a scalar union); else "".
      function Scalar_Union_Type (Els : Element_Vectors.Vector) return String is
         T       : U := Null_Unbounded_String;
         Has_Alt : Boolean := False;
      begin
         for E of Els loop
            if E.Kind = Alt then
               Has_Alt := True;
            elsif E.Kind = Name then
               declare
                  R : constant String := Resolve_Type (To_String (E.Name));
               begin
                  if R = "" then
                     return "";
                  end if;
                  if T = Null_Unbounded_String then
                     T := To_Unbounded_String (R);
                  elsif To_String (T) /= R then
                     return "";
                  end if;
               end;
            else
               return "";
            end if;
         end loop;
         if Has_Alt and then T /= Null_Unbounded_String then
            return To_String (T);
         end if;
         return "";
      end Scalar_Union_Type;

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
         if R.Jet_Code /= Null_Unbounded_String then
            --  A jet reads its own token kind and yields the matched text.
            return (Kind => Scalar,
                    Inline_Type => To_Unbounded_String ("String"));
         end if;
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
            if Members.Is_Empty and then Is_Pure_Literal_Alt (P) then
               return (Kind => Enum, Literals => Lits);
            else
               declare
                  SU : constant String := Scalar_Union_Type (P);
               begin
                  if SU /= "" then
                     return (Kind => Scalar, Inline_Type => To_Unbounded_String (SU));
                  end if;
               end;
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
               --  A rule whose name already names its resolved type (e.g.
               --  `string` -> `String`) is that type; a self-alias `type
               --  String = String` would shadow std and is omitted.
               if Base /= To_String (Info.Inline_Type) then
                  Append (Buf, "pub type " & Base & " = " &
                          To_String (Info.Inline_Type) & ";");
                  Append (Buf, LF);
               end if;
            when Enum =>
               declare
                  Names : constant String_Vectors.Vector := Enum_Names (Info.Literals);
               begin
                  Append (Buf, "#[derive(Default)]");
                  Append (Buf, LF);
                  Append (Buf, "pub enum " & Base & " {");
                  Append (Buf, LF);
                  for I in 1 .. Natural (Info.Literals.Length) loop
                     if I = 1 then
                        Append (Buf, "    #[default]");
                        Append (Buf, LF);
                     end if;
                     Append (Buf, "    " & Base & "_" &
                             To_String (Names (I)) & ",");
                     Append (Buf, LF);
                  end loop;
                  Append (Buf, "}");
                  Append (Buf, LF);
               end;
            when Struct =>
               Append (Buf, "#[derive(Default)]");
               Append (Buf, LF);
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
            Append (Buf, "#[derive(Default)]");
            Append (Buf, LF);
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

      Append (Res, "// generated by hbnf -- do not edit");
      Append (Res, LF);
      Append (Res, "#![allow(non_camel_case_types, dead_code)]");
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

   function Emit_Parser (Rules : HBNF_Grammar.Rule_Vectors.Vector; Conf : Boolean := False) return String is

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

      function Is_Core (Name : String) return Boolean is
        (Scalar_Rust_Type (Name) /= "");

      function Has_Alt (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Alt then
               return True;
            end if;
         end loop;
         return False;
      end Has_Alt;

      --  True when every `/`-alternative is exactly one Literal — the shape
      --  an enum can hold.
      function Is_Pure_Literal_Alt (Els : Element_Vectors.Vector) return Boolean is
         N       : constant Natural := Natural (Els.Length);
         St      : Natural := 1;
         Has_Alt : Boolean := False;
      begin
         for K in 1 .. N + 1 loop
            if K > N then
               if N /= St or else Els (St).Kind /= Literal then
                  return False;
               end if;
            elsif Els (K).Kind = Alt then
               if K - 1 /= St or else Els (St).Kind /= Literal then
                  return False;
               end if;
               St := K + 1;
               Has_Alt := True;
            end if;
         end loop;
         return Has_Alt;
      end Is_Pure_Literal_Alt;

      --  The Rust type a rule reference denotes.
      function Rust_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Rust_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         return Rust_Type (Ref);
      end Rust_Type_Of;

      --  The underlying scalar Rust type a rule name resolves to, chasing
      --  single-name aliases and jets to their target.  "" if not scalar.
      function Resolve_Type (N : String; Depth : Natural := 0) return String is
         C : constant String := Scalar_Rust_Type (N);
      begin
         if C /= "" then
            return C;
         end if;
         if Depth > 8 then
            return "";
         end if;
         declare
            J : constant Natural := Find (N);
         begin
            if J = 0 then
               return "";
            end if;
            declare
               R : constant Rule := Rules (J);
               P : constant Element_Vectors.Vector := R.Pattern;
            begin
               if R.Jet_Code /= Null_Unbounded_String then
                  return "String";
               end if;
               if Natural (P.Length) = 1
                 and then P (1).Kind = Name
                 and then P (1).Min = 1
                 and then P (1).Max = 1
               then
                  return Resolve_Type (To_String (P (1).Name), Depth + 1);
               end if;
            end;
         end;
         return "";
      end Resolve_Type;

      --  A pure alternation of names resolving to one scalar type; "" else.
      function Scalar_Union_Type (Els : Element_Vectors.Vector) return String is
         T       : U := Null_Unbounded_String;
         Has_Alt : Boolean := False;
      begin
         for E of Els loop
            if E.Kind = Alt then
               Has_Alt := True;
            elsif E.Kind = Name then
               declare
                  R : constant String := Resolve_Type (To_String (E.Name));
               begin
                  if R = "" then
                     return "";
                  end if;
                  if T = Null_Unbounded_String then
                     T := To_Unbounded_String (R);
                  elsif To_String (T) /= R then
                     return "";
                  end if;
               end;
            else
               return "";
            end if;
         end loop;
         if Has_Alt and then T /= Null_Unbounded_String then
            return To_String (T);
         end if;
         return "";
      end Scalar_Union_Type;

      --  A human-readable description of a core scalar.
      function Core_Desc (Name : String) return String is
      begin
         if Name = "str" or else Name = "atom" or else Name = "word" then
            return "a string";
         elsif Name = "bool" or else Name = "flag" then
            return "yes or no";
         else
            return "a number";
         end if;
      end Core_Desc;

      --  The token kind a core scalar reads.
      function Scalar_Kind (Name : String) return String is
      begin
         if Name = "str" then
            return "Kind::Str";
         elsif Name = "int" then
            return "Kind::Int";
         elsif Name'Length >= 2 then
            declare
               P : constant Character := Name (Name'First);
               R : constant String := Name (Name'First + 1 .. Name'Last);
            begin
               if (P = 'u' or else P = 'i')
                 and then (for all C of R => C in '0' .. '9')
               then
                  return "Kind::Int";
               end if;
            end;
         end if;
         return "Kind::Atom";
      end Scalar_Kind;

      --  The Rust expression that converts the token into a core value.
      function Scalar_Parse (Name : String) return String is
      begin
         if Name = "str" or else Name = "atom" or else Name = "word" then
            return "p.toks[p.pos].text.clone()";
         elsif Name = "bool" or else Name = "flag" then
            return "matches!(p.toks[p.pos].text.as_str(), ""yes"" | ""on"" | ""true"")";
         else
            return "p.toks[p.pos].text.parse().unwrap()";
         end if;
      end Scalar_Parse;

      --  The token kind that begins a parse of `Rule_Name`, or "" if unknown.
      function Start_Kind (Rule_Name : String) return String is
         J : constant Natural := Find (Rule_Name);
      begin
         if J = 0 then
            return "";
         end if;
         declare
            P : constant Element_Vectors.Vector := Rules (J).Pattern;
         begin
            if Natural (P.Length) = 1 and then P (1).Kind = HBNF_Grammar.Name
              and then Is_Core (To_String (P (1).Name))
            then
               return Scalar_Kind (To_String (P (1).Name));
            end if;
         end;
         return "";
      end Start_Kind;

      --  A list's element type: Vec<T> wraps the referenced rule's type (a
      --  plain reference) or the entry struct a grouped alternation builds.
      function Ret_Type (Idx : Natural) return String is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            if P (1).Kind = HBNF_Grammar.Name then
               return "Vec<" & Rust_Type_Of (To_String (P (1).Name)) & ">";
            else
               return "Vec<" & Rust_Type (To_String (R.Name)) & "Entry>";
            end if;
         end if;
         return Rust_Type (To_String (R.Name));
      end Ret_Type;

      procedure Emit_Seq
        (Els : Element_Vectors.Vector; First, Last : Natural;
         Dst  : String; Buf : in out U; Ind : String := "    ") is
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               case E.Kind is
                  when Literal =>
                     Append (Buf, Ind & "p.expect_lit("""
                       & To_String (E.Lit) & """)?;");
                     Append (Buf, LF);
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        Append (Buf, Ind & "p.expect_kind("
                          & Scalar_Kind (To_String (E.Name)) & ", """
                          & Core_Desc (To_String (E.Name)) & """)?;");
                        Append (Buf, LF);
                        Append (Buf, Ind & Dst
                          & Rust_Field (To_String (E.Name)) & " = "
                          & Scalar_Parse (To_String (E.Name)) & "; p.pos += 1;");
                        Append (Buf, LF);
                     else
                        Append (Buf, Ind & Dst
                          & Rust_Field (To_String (E.Name)) & " = parse_"
                          & Rust_Snake (To_String (E.Name)) & "(p)?;");
                        Append (Buf, LF);
                     end if;
                  when Group =>
                     Emit_Seq (E.Items, 1, Natural (E.Items.Length), Dst, Buf,
                               Ind & "    ");
                  when Alt =>
                     null;
               end case;
            end;
         end loop;
      end Emit_Seq;

      --  Emit a backtracking alternation over the Alt-separated branches in
      --  Els.  Each branch runs inside a closure so its `?` failures return to
      --  the branch check; a failed branch restores p.pos and resets the struct
      --  (Reset), a successful one breaks out of the labelled `'alt` block.
      --  After the last branch fails, control falls through for the caller's
      --  own failure handling.
      procedure Emit_Alternation
        (Els : Element_Vectors.Vector; Acc, Reset : String;
         Buf : in out U; Ind : String := "    ") is
         N  : constant Natural := Natural (Els.Length);
         St : Natural := 1;
         Br : Natural := 0;
      begin
         for K in 1 .. N + 1 loop
            if K > N or else Els (K).Kind = Alt then
               Br := Br + 1;
               if Br > 1 then
                  Append (Buf, Ind & "p.pos = save; " & Reset & ";");
                  Append (Buf, LF);
               end if;
               Append (Buf, Ind & "if (|| -> Result<(), ParseError> {");
               Append (Buf, LF);
               Emit_Seq (Els, St, K - 1, Acc, Buf, Ind & "    ");
               Append (Buf, Ind & "    Ok(())");
               Append (Buf, LF);
               Append (Buf, Ind & "})().is_ok() { break 'alt; }");
               Append (Buf, LF);
               St := K + 1;
            end if;
         end loop;
      end Emit_Alternation;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         RT : constant String := Rust_Type (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Is_Pure_Literal_Alt (P);
         SU : constant String := (if not Is_List then Scalar_Union_Type (P) else "");
      begin
         if R.Jet_Code /= Null_Unbounded_String then
            Append (Buf, "    p.expect_kind(Kind::" & Rust_Type (NM)
              & ", ""a " & NM & """)?;");
            Append (Buf, LF);
            Append (Buf, "    let r = p.toks[p.pos].text.clone(); p.pos += 1;");
            Append (Buf, LF);
            Append (Buf, "    Ok(r)");
            Append (Buf, LF);
            return;
         end if;
         if Is_List then
            declare
               E : constant Element_Access := P (1);
            begin
               Append (Buf, "    let mut r = Vec::new();");
               Append (Buf, LF);
               if E.Kind = Name then
                  declare
                     SK : constant String := Start_Kind (To_String (E.Name));
                  begin
                     if SK /= "" then
                        Append (Buf, "    while p.pos < p.toks.len() && matches!(p.toks[p.pos].kind, "
                          & SK & ") {");
                     else
                        Append (Buf, "    while p.pos < p.toks.len() {");
                     end if;
                  end;
                  Append (Buf, LF);
                  Append (Buf, "        r.push(parse_" & Rust_Snake (To_String (E.Name))
                    & "(p)?);");
                  Append (Buf, LF);
                  Append (Buf, "    }");
                  Append (Buf, LF);
               elsif E.Kind = Group then
                  declare
                     Firsts : String_Vectors.Vector;
                     St     : Natural := 1;
                  begin
                     for K in 1 .. Natural (E.Items.Length) + 1 loop
                        if K > Natural (E.Items.Length)
                          or else E.Items (K).Kind = Alt
                        then
                           if St <= K - 1 and then E.Items (St).Kind = Literal then
                              Firsts.Append (E.Items (St).Lit);
                           end if;
                           St := K + 1;
                        end if;
                     end loop;
                     Append (Buf, "    while p.pos < p.toks.len() && matches!(p.toks[p.pos].kind, Kind::Atom)");
                     Append (Buf, LF);
                     Append (Buf, "        && (");
                     for I in 1 .. Natural (Firsts.Length) loop
                        if I > 1 then
                           Append (Buf, " || ");
                        end if;
                        Append (Buf, "p.toks[p.pos].text == """
                          & To_String (Firsts (I)) & """");
                     end loop;
                     Append (Buf, ") {");
                     Append (Buf, LF);
                     Append (Buf, "        let mut e = " & RT & "Entry::default();");
                     Append (Buf, LF);
                     St := 1;
                     declare
                        Branch : Natural := 0;
                     begin
                        for K in 1 .. Natural (E.Items.Length) + 1 loop
                           if K > Natural (E.Items.Length)
                             or else E.Items (K).Kind = Alt
                           then
                              if St <= K - 1 and then E.Items (St).Kind = Literal then
                                 if Branch = 0 then
                                    Append (Buf, "        if p.toks[p.pos].text == """
                                      & To_String (E.Items (St).Lit) & """ {");
                                 else
                                    Append (Buf, "        } else if p.toks[p.pos].text == """
                                      & To_String (E.Items (St).Lit) & """ {");
                                 end if;
                                 Append (Buf, LF);
                                 Append (Buf, "            p.pos += 1;");
                                 Append (Buf, LF);
                                 Emit_Seq (E.Items, St + 1, K - 1, "e.", Buf,
                                           "            ");
                                 Branch := Branch + 1;
                              end if;
                              St := K + 1;
                           end if;
                        end loop;
                     end;
                     Append (Buf, "        }");
                     Append (Buf, LF);
                     Append (Buf, "        r.push(e);");
                     Append (Buf, LF);
                     Append (Buf, "    }");
                     Append (Buf, LF);
                  end;
               end if;
               Append (Buf, "    Ok(r)");
               Append (Buf, LF);
            end;
         elsif Is_Enum then
            declare
               Lits   : String_Vectors.Vector;
               Names  : String_Vectors.Vector;
               St     : Natural := 1;
               Branch : Natural := 0;
            begin
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        Lits.Append (P (St).Lit);
                     end if;
                     St := K + 1;
                  end if;
               end loop;
               Names := Enum_Names (Lits);

               Append (Buf, "    p.expect_kind(Kind::Atom, ""a " & RT & """)?;");
               Append (Buf, LF);
               Append (Buf, "    let r = if p.toks[p.pos].text == """
                 & To_String (P (1).Lit) & """ { " & RT & "::" & RT & "_"
                 & To_String (Names (1)) & " }");

               St := 1;
               Branch := 0;
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        if Branch > 0 then
                           Append (Buf, " else if p.toks[p.pos].text == """
                             & To_String (P (St).Lit) & """ { " & RT & "::" & RT
                             & "_" & To_String (Names (Branch + 1)) & " }");
                        end if;
                        Branch := Branch + 1;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, " else { return Err(p.fail(""`");
            declare
               St    : Natural := 1;
               First : Boolean := True;
            begin
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        if not First then
                           Append (Buf, " or ");
                        end if;
                        Append (Buf, "`" & To_String (P (St).Lit) & "`");
                        First := False;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, """)); };");
            Append (Buf, LF);
            Append (Buf, "    p.pos += 1;");
            Append (Buf, LF);
            Append (Buf, "    Ok(r)");
            Append (Buf, LF);
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            if Is_Core (To_String (P (1).Name)) then
               Append (Buf, "    p.expect_kind(" & Scalar_Kind (To_String (P (1).Name))
                 & ", """ & Core_Desc (To_String (P (1).Name)) & """)?;");
               Append (Buf, LF);
               Append (Buf, "    let r = " & Scalar_Parse (To_String (P (1).Name))
                 & "; p.pos += 1;");
               Append (Buf, LF);
               Append (Buf, "    Ok(r)");
               Append (Buf, LF);
            else
               Append (Buf, "    parse_" & Rust_Snake (To_String (P (1).Name))
                 & "(p)");
               Append (Buf, LF);
            end if;
         elsif SU /= "" then
            --  A scalar union (str / word, ipv4 / ipv6): try each branch as a
            --  single scalar read; the first that matches yields the value.
            declare
               St : Natural := 1;
            begin
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 then
                        declare
                           E : constant Element_Access := P (St);
                        begin
                           if E.Kind = Name
                             and then Is_Core (To_String (E.Name))
                           then
                              Append (Buf, "    if p.pos < p.toks.len() && matches!(p.toks[p.pos].kind, "
                                & Scalar_Kind (To_String (E.Name)) & ") {");
                              Append (Buf, LF);
                              Append (Buf, "        let r = " & Scalar_Parse (To_String (E.Name))
                                & "; p.pos += 1; return Ok(r); }");
                              Append (Buf, LF);
                           elsif E.Kind = Name then
                              Append (Buf, "    if let Ok(r) = parse_"
                                & Rust_Snake (To_String (E.Name))
                                & "(p) { return Ok(r); }");
                              Append (Buf, LF);
                           end if;
                        end;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "    return Err(p.fail(""a " & NM & """));");
            Append (Buf, LF);
         elsif Has_Alt (P) then
            --  A struct alternation: try each branch with backtracking.
            Append (Buf, "    let save = p.pos;");
            Append (Buf, LF);
            Append (Buf, "    let mut r = " & RT & "::default();");
            Append (Buf, LF);
            Append (Buf, "    'alt: {");
            Append (Buf, LF);
            Emit_Alternation (P, "r.", "r = " & RT & "::default()", Buf,
                              "        ");
            Append (Buf, "        p.pos = save;");
            Append (Buf, LF);
            Append (Buf, "        return Err(p.fail(""a " & NM & """));");
            Append (Buf, LF);
            Append (Buf, "    }");
            Append (Buf, LF);
            Append (Buf, "    Ok(r)");
            Append (Buf, LF);
         else
            --  A struct sequence: match literals and references in order.
            Append (Buf, "    let mut r = " & RT & "::default();");
            Append (Buf, LF);
            Emit_Seq (P, 1, Natural (P.Length), "r.", Buf);
            Append (Buf, "    Ok(r)");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Parser;

      Res : U;
   begin
      if Preamble /= "" then
         Append (Res, Preamble);
         Append (Res, LF);
         Append (Res, LF);
      end if;
      Append (Res, "// generated by hbnf -- do not edit");
      Append (Res, LF);
      declare
         Enum : U := To_Unbounded_String
           ("#[derive(Clone, PartialEq)] pub enum Kind { Atom, Str, Int, Punct");
      begin
         for I in 1 .. N loop
            if Rules (I).Jet_Code /= Null_Unbounded_String then
               Append (Enum, ", " & Rust_Type (To_String (Rules (I).Name)));
            end if;
         end loop;
         Append (Enum, ", Eof }");
         Append (Res, To_String (Enum));
         Append (Res, LF);
      end;
      Append (Res, "pub struct Token { pub kind: Kind, pub text: String, pub line: usize, pub col: usize }");
      Append (Res, LF);
      Append (Res, "#[derive(Debug, Clone)] pub struct ParseError { pub line: usize, pub col: usize, pub msg: String }");
      Append (Res, LF);
      Append (Res, "struct P<'a> { toks: &'a [Token], lines: &'a [&'a str], pos: usize, err: Option<ParseError> }");
      Append (Res, LF);
      Append (Res, "impl<'a> P<'a> {");
      Append (Res, LF);
      Append (Res, "    fn fail(&mut self, expected: &str) -> ParseError {");
      Append (Res, LF);
      Append (Res, "        if self.err.is_none() {");
      Append (Res, LF);
      Append (Res, "            let (line, col) = if self.pos < self.toks.len() { (self.toks[self.pos].line, self.toks[self.pos].col) } else { (0, 0) };");
      Append (Res, LF);
      Append (Res, "            let found = if self.pos < self.toks.len() { self.toks[self.pos].text.clone() } else { ""end of input"".to_string() };");
      Append (Res, LF);
      Append (Res, "            let msg = if line >= 1 && line <= self.lines.len() {");
      Append (Res, LF);
      Append (Res, "                let l = self.lines[line - 1];");
      Append (Res, LF);
      Append (Res, "                let pad = "" "".repeat(if col > 1 { col - 1 } else { 0 });");
      Append (Res, LF);
      Append (Res, "                format!(""expected {}, found {}\n  {}\n  {}^"", expected, found, l, pad)");
      Append (Res, LF);
      Append (Res, "            } else {");
      Append (Res, LF);
      Append (Res, "                format!(""expected {}, found {}"", expected, found)");
      Append (Res, LF);
      Append (Res, "            };");
      Append (Res, LF);
      if Conf then
         Append (Res, "            config_error(line, &msg);");
         Append (Res, LF);
      end if;
      Append (Res, "            self.err = Some(ParseError { line, col, msg });");
      Append (Res, LF);
      Append (Res, "        }");
      Append (Res, LF);
      Append (Res, "        self.err.clone().unwrap()");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    fn expect_lit(&mut self, lit: &str) -> Result<(), ParseError> {");
      Append (Res, LF);
      Append (Res, "        if self.pos < self.toks.len() && matches!(self.toks[self.pos].kind, Kind::Atom | Kind::Punct)");
      Append (Res, LF);
      Append (Res, "            && self.toks[self.pos].text == lit { self.pos += 1; return Ok(()); }");
      Append (Res, LF);
      Append (Res, "        Err(self.fail(&format!(""`{}`"", lit)))");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    fn expect_kind(&mut self, k: Kind, desc: &str) -> Result<(), ParseError> {");
      Append (Res, LF);
      Append (Res, "        if self.pos < self.toks.len() && self.toks[self.pos].kind == k { return Ok(()); }");
      Append (Res, LF);
      Append (Res, "        Err(self.fail(desc))");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);

      for I in 1 .. N loop
         Append (Res, "fn parse_" & Rust_Snake (To_String (Rules (I).Name))
           & "(p: &mut P) -> Result<" & Ret_Type (I) & ", ParseError> {");
         Append (Res, LF);
         Emit_Rule_Parser (I, Res);
         Append (Res, "}");
         Append (Res, LF);
         Append (Res, LF);
      end loop;

      Append (Res, "pub fn parse_tokens(toks: &[Token], lines: &[&str]) -> Result<"
        & Ret_Type (1) & ", ParseError> {");
      Append (Res, LF);
      Append (Res, "    let mut p = P { toks, lines, pos: 0, err: None };");
      Append (Res, LF);
      Append (Res, "    let out = parse_" & Rust_Snake (To_String (Rules (1).Name))
        & "(&mut p)?;");
      Append (Res, LF);
      Append (Res, "    if p.pos < p.toks.len() && p.toks[p.pos].kind != Kind::Eof { return Err(p.fail(""end of config"")); }");
      Append (Res, LF);
      Append (Res, "    Ok(out)");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);

      --  Jets: hand-written scanners, plus the dispatch the lexer calls.
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               R  : constant Rule := Rules (I);
               NM : constant String := To_String (R.Name);
            begin
               Append (Res, "fn jet_" & Rust_Snake (NM)
                 & "(s: &[u8], pos: usize, len: usize) -> usize {");
               Append (Res, LF);
               Append (Res, To_String (R.Jet_Code));
               Append (Res, LF);
               Append (Res, "}");
               Append (Res, LF);
               Append (Res, LF);
            end;
         end if;
      end loop;

      Append (Res, "fn jet_dispatch(s: &[u8], pos: usize, len: usize)"
        & " -> (usize, Kind) {");
      Append (Res, LF);
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               NM : constant String := To_String (Rules (I).Name);
            begin
               Append (Res, "    { let n = jet_" & Rust_Snake (NM)
                 & "(s, pos, len); if n > 0 { return (n, Kind::" & Rust_Type (NM)
                 & "); } }");
               Append (Res, LF);
            end;
         end if;
      end loop;
      Append (Res, "    (0, Kind::Eof)");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);

      return To_String (Res);
   end Emit_Parser;

   function Emit_Lexer (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      R  : constant HBNF_Grammar.Rule := Rules (1);
      P  : constant HBNF_Grammar.Element_Vectors.Vector := R.Pattern;
      Root_T : constant String :=
        (if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            (if P (1).Kind = HBNF_Grammar.Name then
               "Vec<" & (if Scalar_Rust_Type (To_String (P (1).Name)) /= "" then
                           Scalar_Rust_Type (To_String (P (1).Name))
                         else Rust_Type (To_String (P (1).Name))) & ">"
             else "Vec<" & Rust_Type (To_String (R.Name)) & "Entry>")
         else Rust_Type (To_String (R.Name)));
      Lexer  : constant String :=
        Templates.Substitute (Templates.Rust_Lexer, "@ROOT_TYPE@", Root_T);
   begin
      if Epilogue = "" then
         return Lexer;
      else
         return Lexer & LF & Epilogue;
      end if;
   end Emit_Lexer;

   function Emit_Conf (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      Root_T : constant String := Rust_Type (To_String (Rules (1).Name));
   begin
      return Templates.Substitute (Templates.Conf_Rust, "@ROOT_TYPE@", Root_T);
   end Emit_Conf;

end HBNF_Rust;
