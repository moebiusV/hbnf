pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

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
               Elem_Type    : U := Null_Unbounded_String;
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
                     return (Kind => List,
                             Elem_Type =>
                               To_Unbounded_String
                                 (C_Type_Of (To_String (E.Name))),
                             Elem_Members => Member_Vectors.Empty_Vector);
                  elsif E.Kind = Group then
                     declare
                        Members : Member_Vectors.Vector;
                        Lits    : String_Vectors.Vector;
                        Has_Alt : Boolean := False;
                     begin
                        Collect (E.Items, Members, Lits, Has_Alt);
                        return (Kind        => List,
                                Elem_Type    => Null_Unbounded_String,
                                Elem_Members => Members);
                     end;
                  else
                     return (Kind        => List,
                             Elem_Type   =>
                               To_Unbounded_String ("const char *"),
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

      --  Struct-like types emit a `struct tag { ... }` body and need a forward
      --  declaration; scalars and enums are leaves.
      function Is_Struct_Like (Info : Rule_Info) return Boolean is
        (Info.Kind = Struct or else Info.Kind = List);

      Infos : Info_Vectors.Vector;

      --  The struct-like rule indices this struct rule must be emitted after:
      --  its non-list members that reference another struct-like type (a
      --  by-value member needs that type complete first).  List members are
      --  pointers and only need the forward declaration.
      function Deps (Idx : Natural) return Natural_Vectors.Vector is
         Members : Member_Vectors.Vector;
         Lits    : String_Vectors.Vector;
         Has_Alt : Boolean := False;
         D       : Natural_Vectors.Vector;
      begin
         if Infos (Idx).Kind /= Struct then
            return D;
         end if;
         Collect (Rules (Idx).Pattern, Members, Lits, Has_Alt);
         for M of Members loop
            if not M.Is_List then
               declare
                  J : constant Natural := Find (To_String (M.Name));
               begin
                  if J > 0 and then Is_Struct_Like (Infos (J)) then
                     declare
                        Present : Boolean := False;
                     begin
                        for X of D loop
                           if X = J then
                              Present := True;
                           end if;
                        end loop;
                        if not Present then
                           D.Append (J);
                        end if;
                     end;
                  end if;
               end;
            end if;
         end loop;
         return D;
      end Deps;

      function Emit_Rule (Idx : Natural; Info : Rule_Info) return String is
         R  : constant Rule := Rules (Idx);
         NM : constant String := To_String (R.Name);
         TN : constant String := C_Name (NM) & "_t";
         Buf : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append (Buf, "/* " & To_String (R.Leading_Comment) & " */");
            Append (Buf, LF);
         end if;

         case Info.Kind is
            when Scalar =>
               Append (Buf, "typedef " & To_String (Info.Inline_Type) & " "
                 & TN & ";");
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
               Append (Buf, "} " & TN & ";");
               Append (Buf, LF);
            when Struct =>
               Append (Buf, "struct " & C_Name (NM) & " {");
               Append (Buf, LF);
               for M of Info.Members loop
                  if M.Is_List then
                     Append (Buf, "    struct { "
                       & C_Type_Of (To_String (M.Name))
                       & " *items; size_t n; } "
                       & C_Field (To_String (M.Name)) & ";");
                  else
                     Append (Buf, "    " & C_Type_Of (To_String (M.Name))
                       & " " & C_Field (To_String (M.Name)) & ";");
                  end if;
                  Append (Buf, LF);
               end loop;
               Append (Buf, "};");
               Append (Buf, LF);
            when List =>
               Append (Buf, "struct " & C_Name (NM) & " {");
               Append (Buf, LF);
               if Info.Elem_Members.Is_Empty then
                  declare
                     ET : constant String := To_String (Info.Elem_Type);
                  begin
                     if ET'Length > 0 and then ET (ET'Last) = '*' then
                        Append (Buf, "    " & ET & "*items;");
                     else
                        Append (Buf, "    " & ET & " *items;");
                     end if;
                     Append (Buf, LF);
                  end;
               else
                  Append (Buf, "    struct {");
                  Append (Buf, LF);
                  for M of Info.Elem_Members loop
                     Append (Buf, "        " & C_Type_Of (To_String (M.Name))
                       & " " & C_Field (To_String (M.Name)) & ";");
                     Append (Buf, LF);
                  end loop;
                  Append (Buf, "    } *items;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    size_t n;");
               Append (Buf, LF);
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

      --  Forward-declare every struct-like type so a struct may refer to one
      --  that is defined later (mutual recursion).
      for I in 1 .. N loop
         if Is_Struct_Like (Infos (I)) then
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
         if not Is_Struct_Like (Infos (I)) then
            Append (Res, Emit_Rule (I, Infos (I)));
            Append (Res, LF);
            Emitted (I) := True;
         end if;
      end loop;

      --  Struct-like bodies, in by-value dependency order.  A cycle here means
      --  a type contains another by value, transitively, with no list to break
      --  it — infinite size.
      while Remaining > 0 loop
         declare
            Progress : Boolean := False;
         begin
            for I in 1 .. N loop
               if Is_Struct_Like (Infos (I)) and then not Emitted (I) then
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

end ASTBNF_C;
