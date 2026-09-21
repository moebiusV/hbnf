pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Templates;

package body ASTBNF_C is

   use Ada.Strings.Unbounded;
   use ASTBNF;

   subtype U is Unbounded_String;

   LF : constant Character := ASCII.LF;

   package String_Vectors is new Ada.Containers.Vectors (Positive, U);
   package Natural_Vectors is new Ada.Containers.Vectors (Positive, Natural);

   --  The C type for a built-in core rule, or "" if not a core scalar.
   function Scalar_C_Type (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "const char *";
      elsif Name = "int" then
         return "long long";
      elsif Name = "dec" then
         return "double";
      elsif Name = "float" then
         return "float";
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
               return (if P = 'u' then "uint" else "int") & R & "_t";
            end if;
         end;
      end if;
      return "";
   end Scalar_C_Type;

   --  Upper-case C identifier fragment (for enum constants).
   function C_Ident (S : String) return String is
      Buf : U;
   begin
      for C of S loop
         if C in 'a' .. 'z' then
            Append (Buf, Character'Val (Character'Pos (C) - 32));
         elsif (C in 'A' .. 'Z') or else (C in '0' .. '9') then
            Append (Buf, C);
         else
            Append (Buf, '_');
         end if;
      end loop;
      return To_String (Buf);
   end C_Ident;

   --  A valid C identifier from a rule name ('-' -> '_').
   function C_Name (S : String) return String is
      Buf : U;
   begin
      for C of S loop
         Append (Buf, (if C = '-' then '_' else C));
      end loop;
      return To_String (Buf);
   end C_Name;

   --  A struct member name, kept clear of C keywords (the core types `int`,
   --  `float` and `bool` are C keywords/macros, so a field named after them
   --  would not compile).
   function C_Field (S : String) return String is
      N : constant String := C_Name (S);
   begin
      if N = "int" or else N = "float" or else N = "bool"
        or else N = "char" or else N = "double" or else N = "long"
        or else N = "short" or else N = "signed" or else N = "unsigned"
        or else N = "void" or else N = "const" or else N = "struct"
        or else N = "union" or else N = "enum" or else N = "auto"
        or else N = "break" or else N = "case" or else N = "continue"
        or else N = "default" or else N = "do" or else N = "else"
        or else N = "extern" or else N = "for" or else N = "goto"
        or else N = "if" or else N = "inline" or else N = "register"
        or else N = "restrict" or else N = "return" or else N = "sizeof"
        or else N = "static" or else N = "switch" or else N = "typedef"
        or else N = "volatile" or else N = "while"
      then
         return N & "_";
      end if;
      return N;
   end C_Field;

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

      function C_Type_Of (Ref : String) return String is
         S : constant String := Scalar_C_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         if Find (Ref) = 0 then
            raise Parse_Error with "undefined rule: " & Ref;
         end if;
         return C_Name (Ref) & "_t";
      end C_Type_Of;

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
                              (C_Type_Of (To_String (E.Name))));
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
                          Inline_Type => To_Unbounded_String ("const char *"));
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

      --  A struct is embedded by value; a list is a `next`-linked node
      --  referenced by head pointer, so only structs impose a by-value order.
      function Is_By_Value (Info : Rule_Info) return Boolean is
        (Info.Kind = Struct);

      Infos : Info_Vectors.Vector;

      --  The rule indices this rule must be emitted after: its by-value
      --  members that reference another struct.
      function Deps (Idx : Natural) return Natural_Vectors.Vector is
         D : Natural_Vectors.Vector;

         procedure Add (J : Natural) is
            Present : Boolean := False;
         begin
            if J = 0 then
               return;
            end if;
            for X of D loop
               if X = J then
                  Present := True;
               end if;
            end loop;
            if not Present then
               D.Append (J);
            end if;
         end Add;

         procedure Add_Ref (Name : U) is
            J : constant Natural := Find (To_String (Name));
         begin
            if J > 0 and then Is_By_Value (Infos (J)) then
               Add (J);
            end if;
         end Add_Ref;
      begin
         declare
            Info : constant Rule_Info := Infos (Idx);
         begin
            case Info.Kind is
               when Struct =>
                  for M of Info.Members loop
                     if not M.Is_List then
                        Add_Ref (M.Name);
                     end if;
                  end loop;
               when List =>
                  if Info.Elem_Name /= Null_Unbounded_String then
                     Add_Ref (Info.Elem_Name);
                  end if;
                  for M of Info.Elem_Members loop
                     Add_Ref (M.Name);
                  end loop;
               when others =>
                  null;
            end case;
         end;
         return D;
      end Deps;

      --  The C type a struct/list reference denotes (a `_t` typedef name).
      function Ref_Type (Name : String) return String is
         S : constant String := Scalar_C_Type (Name);
      begin
         if S /= "" then
            return S;
         end if;
         return C_Name (Name) & "_t";
      end Ref_Type;

      function Emit_Rule (Idx : Natural; Info : Rule_Info) return String is
         R  : constant Rule := Rules (Idx);
         NM : constant String := To_String (R.Name);
         CN : constant String := C_Name (NM);
         Buf : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append (Buf, "/* " & To_String (R.Leading_Comment) & " */");
            Append (Buf, LF);
         end if;

         case Info.Kind is
            when Scalar =>
               Append (Buf, "typedef " & To_String (Info.Inline_Type) & " "
                 & CN & "_t;");
               Append (Buf, LF);
            when Enum =>
               Append (Buf, "typedef enum {");
               Append (Buf, LF);
               for I in 1 .. Natural (Info.Literals.Length) loop
                  Append (Buf, "    " & C_Ident (NM) & "_"
                    & C_Ident (To_String (Info.Literals (I))));
                  if I < Natural (Info.Literals.Length) then
                     Append (Buf, ",");
                  end if;
                  Append (Buf, "   /* "
                    & To_String (Info.Literals (I)) & " */");
                  Append (Buf, LF);
               end loop;
               Append (Buf, "} " & CN & "_t;");
               Append (Buf, LF);
            when Struct =>
               Append (Buf, "struct " & CN & " {");
               Append (Buf, LF);
               for M of Info.Members loop
                  declare
                     J : constant Natural := Find (To_String (M.Name));
                     Is_Head : constant Boolean :=
                       M.Is_List or else
                         (J > 0 and then Infos (J).Kind = List);
                  begin
                     if Is_Head then
                        Append (Buf, "    " & Ref_Type (To_String (M.Name))
                          & " *" & C_Field (To_String (M.Name)) & ";");
                     else
                        Append (Buf, "    " & C_Type_Of (To_String (M.Name))
                          & " " & C_Field (To_String (M.Name)) & ";");
                     end if;
                  end;
                  Append (Buf, LF);
               end loop;
               Append (Buf, "};");
               Append (Buf, LF);
            when List =>
               --  A `next`-linked node: the list is a head pointer elsewhere.
               Append (Buf, "struct " & CN & " {");
               Append (Buf, LF);
               Append (Buf, "    struct " & CN & " *next;");
               Append (Buf, LF);
               if Info.Elem_Members.Is_Empty then
                  if Info.Elem_Name /= Null_Unbounded_String then
                     Append (Buf, "    " & C_Type_Of
                       (To_String (Info.Elem_Name)) & " "
                       & C_Field (To_String (Info.Elem_Name)) & ";");
                  else
                     Append (Buf, "    const char *value;");
                  end if;
                  Append (Buf, LF);
               else
                  for M of Info.Elem_Members loop
                     Append (Buf, "    " & C_Type_Of (To_String (M.Name))
                       & " " & C_Field (To_String (M.Name)) & ";");
                     Append (Buf, LF);
                  end loop;
               end if;
               Append (Buf, "};");
               Append (Buf, LF);
         end case;

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " /* " & To_String (R.Trailing_Comment) & " */");
            Append (Buf, LF);
         end if;
         return To_String (Buf);
      end Emit_Rule;

      Emitted   : array (1 .. N) of Boolean := [others => False];
      Remaining : Natural := 0;
      Res       : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (I));
      end loop;

      Append (Res, "/* generated by astbnf -- do not edit */");
      Append (Res, LF);
      Append (Res, "#include <stdint.h>");
      Append (Res, LF);
      Append (Res, "#include <stdbool.h>");
      Append (Res, LF);
      Append (Res, "#include <stddef.h>");
      Append (Res, LF);
      Append (Res, LF);

      --  Forward-declare every struct and list node type.
      for I in 1 .. N loop
         if Is_By_Value (Infos (I)) or else Infos (I).Kind = List then
            Append (Res, "typedef struct "
              & C_Name (To_String (Rules (I).Name))
              & " " & C_Name (To_String (Rules (I).Name)) & "_t;");
            Append (Res, LF);
            Remaining := Remaining + 1;
         end if;
      end loop;
      Append (Res, LF);

      --  Leaves first: scalars and enums carry no ordering constraints.
      for I in 1 .. N loop
         if Infos (I).Kind = Scalar or else Infos (I).Kind = Enum then
            Append (Res, Emit_Rule (I, Infos (I)));
            Append (Res, LF);
            Emitted (I) := True;
         end if;
      end loop;

      --  Struct and list bodies, in by-value dependency order.
      while Remaining > 0 loop
         declare
            Progress : Boolean := False;
         begin
            for I in 1 .. N loop
               if (Is_By_Value (Infos (I)) or else Infos (I).Kind = List)
                 and then not Emitted (I)
               then
                  declare
                     Ready : Boolean := True;
                  begin
                     for D of Deps (I) loop
                        if not Emitted (D) then
                           Ready := False;
                        end if;
                     end loop;
                     if Ready then
                        Append (Res, Emit_Rule (I, Infos (I)));
                        Append (Res, LF);
                        Emitted (I) := True;
                        Remaining := Remaining - 1;
                        Progress := True;
                     end if;
                  end;
               end if;
            end loop;
            if not Progress then
               raise Parse_Error with
                 "by-value cycle in schema (add a * repetition)";
            end if;
         end;
      end loop;

      return To_String (Res);
   end Emit;

   --  =====================================================================
   --  Parser emission: a self-contained recursive-descent parser that
   --  consumes a token stream and allocates/populates the structs above.
   --  =====================================================================

   --  The token kind a core scalar reads (mirrors the matcher's Match_Core).
   function Scalar_Tok_Kind (Name : String) return String is
   begin
      if Name = "str" then
         return "TOK_STR";
      elsif Name = "int" then
         return "TOK_INT";
      elsif Name = "dec" or else Name = "float" then
         return "TOK_DEC";
      elsif Name'Length >= 2 then
         declare
            P : constant Character := Name (Name'First);
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            if (P = 'u' or else P = 'i')
              and then (for all C of R => C in '0' .. '9')
            then
               return "TOK_INT";
            end if;
         end;
      end if;
      return "TOK_ATOM";  --  atom / word / bool / flag
   end Scalar_Tok_Kind;

   --  A human-readable description of a core scalar (for error messages).
   function Core_Desc (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "a string";
      elsif Name = "bool" or else Name = "flag" then
         return "yes or no";
      else
         return "a number";  --  int / dec / float / uN / iN
      end if;
   end Core_Desc;

   --  The C expression that converts the token at p->pos into a core value.
   function Scalar_Parse_Expr (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "strdup(p->toks[p->pos].text)";
      elsif Name = "int" then
         return "atoll(p->toks[p->pos].text)";
      elsif Name = "dec" then
         return "atof(p->toks[p->pos].text)";
      elsif Name = "float" then
         return "(float)atof(p->toks[p->pos].text)";
      elsif Name = "bool" or else Name = "flag" then
         return "(strcmp(p->toks[p->pos].text,""yes"")==0 "
           & "|| strcmp(p->toks[p->pos].text,""on"")==0 "
           & "|| strcmp(p->toks[p->pos].text,""true"")==0)";
      elsif Name'Length >= 2 then
         declare
            P : constant Character := Name (Name'First);
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            if (P = 'u' or else P = 'i')
              and then (for all C of R => C in '0' .. '9')
            then
               if P = 'u' then
                  return "(uint" & R
                    & "_t)strtoull(p->toks[p->pos].text, NULL, 10)";
               else
                  return "(int" & R
                    & "_t)strtoll(p->toks[p->pos].text, NULL, 10)";
               end if;
            end if;
         end;
      end if;
      return "strdup(p->toks[p->pos].text)";
   end Scalar_Parse_Expr;

   function Emit_Parser (Rules : Rule_Vectors.Vector) return String is

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
        (Scalar_C_Type (Name) /= "");

      function Has_Alt (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Alt then
               return True;
            end if;
         end loop;
         return False;
      end Has_Alt;

      function Has_Name (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Name then
               return True;
            end if;
         end loop;
         return False;
      end Has_Name;

      --  The out-parameter type of parse_<rule>: a list hands back a head
      --  pointer (`X_t **`), anything else a by-value struct/scalar (`X_t *`).
      function Out_Type (Idx : Natural) return String is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            return C_Name (To_String (R.Name)) & "_t **";
         end if;
         return C_Name (To_String (R.Name)) & "_t *";
      end Out_Type;

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
            if Natural (P.Length) = 1 and then P (1).Kind = ASTBNF.Name
              and then Is_Core (To_String (P (1).Name))
            then
               return Scalar_Tok_Kind (To_String (P (1).Name));
            end if;
         end;
         return "";
      end Start_Kind;

      --  Emit matching + building for segment Els(First..Last), writing fields
      --  through the accessor Acc ("r." or "nn->").  On failure returns false.
      procedure Emit_Seq
        (Els : Element_Vectors.Vector; First, Last : Natural; Acc : String;
         Buf  : in out U; Ind : String := "    ") is
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               case E.Kind is
                  when Literal =>
                     Append (Buf, Ind & "if (!expect_lit(p, """
                       & To_String (E.Lit) & """)) return false;");
                     Append (Buf, LF);
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        Append (Buf, Ind & "if (!expect_kind(p, "
                          & Scalar_Tok_Kind (To_String (E.Name)) & ", """
                          & Core_Desc (To_String (E.Name)) & """)) return false;");
                        Append (Buf, LF);
                        Append (Buf, Ind & Acc
                          & C_Field (To_String (E.Name)) & " = "
                          & Scalar_Parse_Expr (To_String (E.Name)) & "; p->pos++;");
                        Append (Buf, LF);
                     else
                        Append (Buf, Ind & "if (!parse_"
                          & C_Name (To_String (E.Name)) & "(p, &" & Acc
                          & C_Field (To_String (E.Name)) & ")) return false;");
                        Append (Buf, LF);
                     end if;
                  when Group =>
                     Emit_Seq (E.Items, 1, Natural (E.Items.Length), Acc, Buf,
                               Ind & "    ");
                  when Alt =>
                     null;
               end case;
            end;
         end loop;
      end Emit_Seq;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         CN : constant String := C_Name (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Has_Alt (P)
           and then not Has_Name (P);
      begin
         if Is_List then
            declare
               E : constant Element_Access := P (1);
            begin
               Append (Buf, "    " & CN & "_t *head = NULL, **tail = &head;");
               Append (Buf, LF);
               if E.Kind = Name then
                  declare
                     SK : constant String := Start_Kind (To_String (E.Name));
                  begin
                     if SK /= "" then
                        Append (Buf, "    while (p->pos < p->n && p->toks[p->pos].kind == "
                          & SK & ") {");
                     else
                        Append (Buf, "    while (p->pos < p->n) {");
                     end if;
                  end;
                  Append (Buf, LF);
                  Append (Buf, "        " & CN & "_t *nn ="
                    & " calloc(1, sizeof(*nn));");
                  Append (Buf, LF);
                  Append (Buf, "        if (!parse_" & C_Name (To_String (E.Name))
                    & "(p, &nn->" & C_Field (To_String (E.Name)) & ")) { free(nn); return false; }");
                  Append (Buf, LF);
                  Append (Buf, "        *tail = nn; tail = &nn->next;");
                  Append (Buf, LF);
                  Append (Buf, "    }");
                  Append (Buf, LF);
                  Append (Buf, "    *out = head; return true;");
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
                           if St <= K - 1
                             and then E.Items (St).Kind = Literal
                           then
                              Firsts.Append (E.Items (St).Lit);
                           end if;
                           St := K + 1;
                        end if;
                     end loop;

                     Append (Buf, "    while (p->pos < p->n && p->toks[p->pos].kind == TOK_ATOM && (");
                     for I in 1 .. Natural (Firsts.Length) loop
                        if I > 1 then
                           Append (Buf, " || ");
                        end if;
                        Append (Buf, "strcmp(p->toks[p->pos].text, """
                          & To_String (Firsts (I)) & """)==0");
                     end loop;
                     Append (Buf, ")) {");
                     Append (Buf, LF);
                     Append (Buf, "        " & CN & "_t *nn ="
                       & " calloc(1, sizeof(*nn));");
                     Append (Buf, LF);

                     St := 1;
                     declare
                        Branch : Natural := 0;
                     begin
                        for K in 1 .. Natural (E.Items.Length) + 1 loop
                           if K > Natural (E.Items.Length)
                             or else E.Items (K).Kind = Alt
                           then
                              if St <= K - 1
                                and then E.Items (St).Kind = Literal
                              then
                                 if Branch = 0 then
                                    Append (Buf, "        if (strcmp(p->toks[p->pos].text, "
                                      & '"' & To_String (E.Items (St).Lit)
                                      & '"' & ")==0) {");
                                 else
                                    Append (Buf, "        } else if (strcmp(p->toks[p->pos].text, "
                                      & '"' & To_String (E.Items (St).Lit)
                                      & '"' & ")==0) {");
                                 end if;
                                 Append (Buf, " p->pos++;");
                                 Append (Buf, LF);
                                 Emit_Seq (E.Items, St + 1, K - 1, "nn->",
                                           Buf, "            ");
                                 Branch := Branch + 1;
                              end if;
                              St := K + 1;
                           end if;
                        end loop;
                     end;
                     Append (Buf, "        }");
                     Append (Buf, LF);
                     Append (Buf, "        *tail = nn; tail = &nn->next;");
                     Append (Buf, LF);
                     Append (Buf, "    }");
                     Append (Buf, LF);
                     Append (Buf, "    *out = head; return true;");
                     Append (Buf, LF);
                  end;
               else
                  Append (Buf, "    *out = NULL; return true;");
                  Append (Buf, LF);
               end if;
            end;
         elsif Is_Enum then
            Append (Buf, "    if (!expect_kind(p, TOK_ATOM, ""a "
              & CN & """)) return false;");
            Append (Buf, LF);
            Append (Buf, "    {");
            Append (Buf, LF);
            Append (Buf, "        " & CN & "_t r = " & C_Ident (NM) & "_"
              & C_Ident (To_String (P (1).Lit)) & ";");
            Append (Buf, LF);
            declare
               St     : Natural := 1;
               Branch : Natural := 0;
            begin
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        if Branch = 0 then
                           Append (Buf, "        if (strcmp(p->toks[p->pos].text, "
                             & '"' & To_String (P (St).Lit) & '"' & ")==0)");
                        else
                           Append (Buf, "        else if (strcmp(p->toks[p->pos].text, "
                             & '"' & To_String (P (St).Lit) & '"' & ")==0)");
                        end if;
                        Append (Buf, " r = " & C_Ident (NM) & "_"
                          & C_Ident (To_String (P (St).Lit)) & ";");
                        Append (Buf, LF);
                        Branch := Branch + 1;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "        else { fail(p, ""`");
            declare
               St     : Natural := 1;
               First  : Boolean := True;
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
            Append (Buf, """, p->toks[p->pos].text); return false; }");
            Append (Buf, LF);
            Append (Buf, "        p->pos++; *out = r; return true;");
            Append (Buf, LF);
            Append (Buf, "    }");
            Append (Buf, LF);
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            --  A scalar alias: read a core token, or delegate to the rule.
            if Is_Core (To_String (P (1).Name)) then
               Append (Buf, "    if (!expect_kind(p, "
                 & Scalar_Tok_Kind (To_String (P (1).Name)) & ", """
                 & Core_Desc (To_String (P (1).Name)) & """)) return false;");
               Append (Buf, LF);
               Append (Buf, "    *out = "
                 & Scalar_Parse_Expr (To_String (P (1).Name)) & "; p->pos++;");
               Append (Buf, LF);
               Append (Buf, "    return true;");
               Append (Buf, LF);
            else
               Append (Buf, "    return parse_" & C_Name (To_String (P (1).Name))
                 & "(p, out);");
               Append (Buf, LF);
            end if;
         else
            --  A struct: match literals and references in order.
            Append (Buf, "    " & CN & "_t r = {0};");
            Append (Buf, LF);
            Emit_Seq (P, 1, Natural (P.Length), "r.", Buf);
            Append (Buf, "    *out = r; return true;");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Parser;

      Res : U;
   begin
      Append (Res, "/* generated by astbnf -- do not edit */");
      Append (Res, LF);
      Append (Res, "#include <stdlib.h>");
      Append (Res, LF);
      Append (Res, "#include <string.h>");
      Append (Res, LF);
      Append (Res, "#include <stdio.h>");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "typedef enum { TOK_ATOM, TOK_STR, TOK_INT, TOK_DEC,"
        & " TOK_PUNCT, TOK_EOF } tok_kind_t;");
      Append (Res, LF);
      Append (Res, "typedef struct { tok_kind_t kind; const char *text;"
        & " size_t line, col; } token_t;");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "typedef struct {");
      Append (Res, LF);
      Append (Res, "    const token_t *toks;");
      Append (Res, LF);
      Append (Res, "    size_t n, pos;");
      Append (Res, LF);
      Append (Res, "    const char *const *lines;  /* source lines, for the caret */");
      Append (Res, LF);
      Append (Res, "    size_t nlines;");
      Append (Res, LF);
      Append (Res, "    size_t err_line, err_col;");
      Append (Res, LF);
      Append (Res, "    char err[512];");
      Append (Res, LF);
      Append (Res, "} parser_t;");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "static void fail(parser_t *p, const char *expected,"
        & " const char *found) {");
      Append (Res, LF);
      Append (Res, "    if (p->err[0]) return;  /* first error wins */");
      Append (Res, LF);
      Append (Res, "    p->err_line = p->pos < p->n ? p->toks[p->pos].line : 0;");
      Append (Res, LF);
      Append (Res, "    p->err_col  = p->pos < p->n ? p->toks[p->pos].col  : 0;");
      Append (Res, LF);
      Append (Res, "    if (p->lines && p->err_line >= 1 && p->err_line <= p->nlines) {");
      Append (Res, LF);
      Append (Res, "        const char *l = p->lines[p->err_line - 1];");
      Append (Res, LF);
      Append (Res, "        char pad[64];");
      Append (Res, LF);
      Append (Res, "        size_t w = p->err_col > 1 ? p->err_col - 1 : 0;");
      Append (Res, LF);
      Append (Res, "        if (w > sizeof pad - 1) w = sizeof pad - 1;");
      Append (Res, LF);
      Append (Res, "        memset(pad, ' ', w); pad[w] = '\0';");
      Append (Res, LF);
      Append (Res, "        snprintf(p->err, sizeof p->err,");
      Append (Res, LF);
      Append (Res, "                 ""expected %s, found %s\n  %s\n  %s^"",");
      Append (Res, LF);
      Append (Res, "                 expected, found, l, pad);");
      Append (Res, LF);
      Append (Res, "    } else {");
      Append (Res, LF);
      Append (Res, "        snprintf(p->err, sizeof p->err, ""expected %s, found %s"",");
      Append (Res, LF);
      Append (Res, "                 expected, found);");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "static bool expect_lit(parser_t *p, const char *lit) {");
      Append (Res, LF);
      Append (Res, "    if (p->pos < p->n && (p->toks[p->pos].kind == TOK_ATOM"
        & " || p->toks[p->pos].kind == TOK_PUNCT)");
      Append (Res, LF);
      Append (Res, "        && p->toks[p->pos].text && strcmp(p->toks[p->pos].text, lit) == 0) {");
      Append (Res, LF);
      Append (Res, "        p->pos++; return true;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    { char want[64]; snprintf(want, sizeof want, ""`%s`"", lit);");
      Append (Res, LF);
      Append (Res, "      fail(p, want, p->pos < p->n ? p->toks[p->pos].text"
        & " : ""end of input""); return false; }");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "static bool expect_kind(parser_t *p, tok_kind_t k,"
        & " const char *desc) {");
      Append (Res, LF);
      Append (Res, "    if (p->pos < p->n && p->toks[p->pos].kind == k) return true;");
      Append (Res, LF);
      Append (Res, "    fail(p, desc, p->pos < p->n ? p->toks[p->pos].text"
        & " : ""end of input"");");
      Append (Res, LF);
      Append (Res, "    return false;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);

      --  Forward declarations of every parse function.
      for I in 1 .. N loop
         Append (Res, "static bool parse_" & C_Name (To_String (Rules (I).Name))
           & "(parser_t *p, " & Out_Type (I) & " out);");
         Append (Res, LF);
      end loop;
      Append (Res, LF);

      for I in 1 .. N loop
         declare
            R : constant Rule := Rules (I);
         begin
            Append (Res, "static bool parse_" & C_Name (To_String (R.Name))
              & "(parser_t *p, " & Out_Type (I) & " out) {");
            Append (Res, LF);
            Emit_Rule_Parser (I, Res);
            Append (Res, "}");
            Append (Res, LF);
            Append (Res, LF);
         end;
      end loop;

      --  The entry point: parse the root rule, then reject trailing input.
      Append (Res, "bool parse_config(const token_t *toks, size_t n, "
        & C_Name (To_String (Rules (1).Name)) & "_t *out,");
      Append (Res, LF);
      Append (Res, "                  const char *const *lines, size_t nlines,");
      Append (Res, LF);
      Append (Res, "                  char *err, size_t errlen,"
        & " size_t *err_line, size_t *err_col) {");
      Append (Res, LF);
      Append (Res, "    parser_t p = { toks, n, 0, lines, nlines, 0, 0, {0} };");
      Append (Res, LF);
      Append (Res, "    if (!parse_" & C_Name (To_String (Rules (1).Name))
        & "(&p, out)) goto err;");
      Append (Res, LF);
      Append (Res, "    if (p.pos < p.n && p.toks[p.pos].kind != TOK_EOF) { fail(&p, ""end of config"", p.toks[p.pos].text); goto err; }");
      Append (Res, LF);
      Append (Res, "    return true;");
      Append (Res, LF);
      Append (Res, "err:");
      Append (Res, LF);
      Append (Res, "    snprintf(err, errlen, ""%s"", p.err);");
      Append (Res, LF);
      Append (Res, "    *err_line = p.err_line; *err_col = p.err_col;");
      Append (Res, LF);
      Append (Res, "    return false;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);

      return To_String (Res);
   end Emit_Parser;

   function Emit_Lexer (Rules : Rule_Vectors.Vector) return String is
      Root_T : constant String := C_Name (To_String (Rules (1).Name)) & "_t";
   begin
      return Templates.Substitute (Templates.C_Lexer, "@ROOT_TYPE@", Root_T);
   end Emit_Lexer;

end ASTBNF_C;
