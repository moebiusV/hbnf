pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Templates;

package body HBNF_C is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

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

   --  Natural'Image with the leading blank stripped ("1", not " 1").
   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Img;

   --  Unique enumerator suffixes for a literal list.  C_Ident is case-
   --  insensitive (`dot`/`DoT` both -> `DOT`) and maps punctuation to `_`
   --  (`!=`/`<=` both -> `__`), so plain names collide; dedupe by appending
   --  _2, _3, ..., and name pure-punctuation literals `OP` + position.
   function Enum_Names (Lits : String_Vectors.Vector) return String_Vectors.Vector is
      Names : String_Vectors.Vector;

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
            Base : constant String := C_Ident (To_String (Lits (I)));
            N    : U;
         begin
            if Base = "" or else (for all C of Base => C = '_') then
               N := To_Unbounded_String ("OP" & Img (I));
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

   --  The `_t` typedef name for a rule, with a "_" suffix when it would
   --  collide with a POSIX <sys/types.h> typedef (uid_t, gid_t, ...).
   function C_Type_Name (Ref : String) return String is
      T : constant String := C_Name (Ref) & "_t";
   begin
      if T = "uid_t" or else T = "gid_t" or else T = "pid_t"
        or else T = "off_t" or else T = "size_t" or else T = "ssize_t"
        or else T = "time_t" or else T = "mode_t" or else T = "dev_t"
        or else T = "ino_t" or else T = "nlink_t" or else T = "id_t"
        or else T = "clock_t" or else T = "useconds_t"
        or else T = "suseconds_t" or else T = "timer_t"
        or else T = "socklen_t" or else T = "key_t"
      then
         return T & "_";
      end if;
      return T;
   end C_Type_Name;

   --  The C type of the root (first) rule: a list root is its list head
   --  (`struct <CN>_list`), a struct root its `_t` typedef.
   function Root_Type (Rules : Rule_Vectors.Vector) return String is
      NM : constant String := To_String (Rules (1).Name);
   begin
      if Natural (Rules (1).Pattern.Length) = 1
        and then (Rules (1).Pattern (1).Min /= 1
                  or else Rules (1).Pattern (1).Max /= 1)
      then
         return "struct " & C_Name (NM) & "_list";
      end if;
      return C_Type_Name (NM);
   end Root_Type;

   --  =====================================================================
   --  Classification shared by the id-ref serialization emitters.  Emit and
   --  Emit_Parser keep their own local copies; these package-level versions
   --  are parameterized by Rules so Emit_Serializer and Emit_Rebuild share
   --  one classification.

   type Member is record
      Name    : U;
      Is_List : Boolean;
   end record;
   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

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

   function Find (Rules : Rule_Vectors.Vector; Name : String) return Natural is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if To_String (Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function C_Type_Of (Rules : Rule_Vectors.Vector; Ref : String) return String is
      S : constant String := Scalar_C_Type (Ref);
   begin
      if S /= "" then
         return S;
      end if;
      if Find (Rules, Ref) = 0 then
         raise Parse_Error with "undefined rule: " & Ref;
      end if;
      return C_Type_Name (Ref);
   end C_Type_Of;

   --  The underlying scalar C type a rule name resolves to, chasing
   --  single-name aliases and jets.  "" if not scalar.
   function Resolve_Type (Rules : Rule_Vectors.Vector; N : String;
                          Depth : Natural := 0) return String is
      C : constant String := Scalar_C_Type (N);
   begin
      if C /= "" then
         return C;
      end if;
      if Depth > 8 then
         return "";
      end if;
      declare
         J : constant Natural := Find (Rules, N);
      begin
         if J = 0 then
            return "";
         end if;
         declare
            R : constant Rule := Rules (J);
            P : constant Element_Vectors.Vector := R.Pattern;
         begin
            if R.Jet_Code /= Null_Unbounded_String then
               return "const char *";
            end if;
            if Natural (P.Length) = 1
              and then P (1).Kind = Name
              and then P (1).Min = 1
              and then P (1).Max = 1
            then
               return Resolve_Type (Rules, To_String (P (1).Name), Depth + 1);
            end if;
         end;
      end;
      return "";
   end Resolve_Type;

   --  If the pattern is a pure alternation of names that all resolve to the
   --  same scalar C type, that type; else "".
   function Scalar_Union_Type (Rules : Rule_Vectors.Vector;
                               Els : Element_Vectors.Vector) return String is
      T       : U := Null_Unbounded_String;
      Has_Alt : Boolean := False;
   begin
      for E of Els loop
         if E.Kind = Alt then
            Has_Alt := True;
         elsif E.Kind = Name then
            declare
               R : constant String := Resolve_Type (Rules, To_String (E.Name));
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

   function Contains (V : Member_Vectors.Vector; S : U) return Boolean is
   begin
      for X of V loop
         if X.Name = S then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

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

   function Analyze (Rules : Rule_Vectors.Vector; Idx : Natural)
      return Rule_Info is
      R : constant Rule := Rules (Idx);
      P : constant Element_Vectors.Vector := R.Pattern;
   begin
      if R.Jet_Code /= Null_Unbounded_String then
         return (Kind        => Scalar,
                 Inline_Type => To_Unbounded_String ("const char *"));
      end if;
      if Natural (P.Length) = 1 then
         declare
            E : constant Element_Access := P (1);
         begin
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

            if E.Kind = Name then
               return (Kind        => Scalar,
                       Inline_Type =>
                         To_Unbounded_String
                           (C_Type_Of (Rules, To_String (E.Name))));
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
         if Members.Is_Empty and then Is_Pure_Literal_Alt (P) then
            return (Kind => Enum, Literals => Lits);
         else
            declare
               SU : constant String := Scalar_Union_Type (Rules, P);
            begin
               if SU /= "" then
                  return (Kind => Scalar, Inline_Type => To_Unbounded_String (SU));
               end if;
            end;
            return (Kind => Struct, Members => Members);
         end if;
      end;
   end Analyze;

   function Emit (Rules : Rule_Vectors.Vector; Idref : Boolean := False)
      return String is

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
         return C_Type_Name (Ref);
      end C_Type_Of;

      --  The underlying scalar C type a rule name resolves to, chasing
      --  single-name aliases and jets to their target (so `str / word` and
      --  `ipv4 / ipv6` both collapse to `const char *`).  "" if not scalar.
      function Resolve_Type (N : String; Depth : Natural := 0) return String is
         C : constant String := Scalar_C_Type (N);
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
                  return "const char *";
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
      --  the same scalar C type, that type (a scalar union); else "".
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
            return (Kind        => Scalar,
                    Inline_Type => To_Unbounded_String ("const char *"));
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
         return C_Type_Name (Name);
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
                 & C_Type_Name (NM) & ";");
               Append (Buf, LF);
            when Enum =>
               declare
                  Names : constant String_Vectors.Vector := Enum_Names (Info.Literals);
               begin
                  Append (Buf, "typedef enum {");
                  Append (Buf, LF);
                  for I in 1 .. Natural (Info.Literals.Length) loop
                     Append (Buf, "    " & C_Ident (NM) & "_"
                       & To_String (Names (I)));
                     if I < Natural (Info.Literals.Length) then
                        Append (Buf, ",");
                     end if;
                     Append (Buf, "   /* "
                       & To_String (Info.Literals (I)) & " */");
                     Append (Buf, LF);
                  end loop;
                  Append (Buf, "} " & C_Type_Name (NM) & ";");
                  Append (Buf, LF);
               end;
            when Struct =>
               Append (Buf, "struct " & CN & " {");
               Append (Buf, LF);
               if Idref then
                  Append (Buf, "    objid_t id, parent;");
                  Append (Buf, LF);
               end if;
               for M of Info.Members loop
                  declare
                     J : constant Natural := Find (To_String (M.Name));
                     Is_Head : constant Boolean :=
                       M.Is_List or else
                         (J > 0 and then Infos (J).Kind = List);
                  begin
                     if Is_Head then
                        Append (Buf, "    struct "
                          & C_Name (To_String (M.Name)) & "_list "
                          & C_Field (To_String (M.Name)) & ";");
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
               --  A list-linked node; the head is a `struct <CN>_list`
               --  embedded in the parent.
               Append (Buf, "struct " & CN & " {");
               Append (Buf, LF);
               if Idref then
                  Append (Buf, "    objid_t id, parent;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    HBNF_LIST_ENTRY(" & CN & ");");
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

      --  Emit AST walk (visit) and transform (map) helpers: a node_kind_t
      --  tag per composite rule, plus visit_<rule>/map_<rule> functions that
      --  walk the typed tree the parser builds.  visit_ is pre-order and
      --  read-only; map_ is bottom-up and may mutate a node in place.  A
      --  scalar or enum member is a leaf and is not recursed into.
      procedure Emit_Walk (Buf : in out U) is

         function Ref_Kind (Name : String) return Class_Kind is
            J : constant Natural := Find (Name);
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         --  The recursive call into node field `n-><Name>`: a by-value struct
         --  passes &n->f, a list head passes n->f, a leaf emits nothing.
         procedure Recurse (Name : String; Prefix : String;
                            Buf : in out U; Ind : String) is
            F : constant String := C_Field (Name);
         begin
            case Ref_Kind (Name) is
               when Struct =>
                  Append (Buf, Ind & Prefix & "_" & C_Name (Name)
                    & "(&n->" & F & ", f, ctx);");
               when List =>
                  Append (Buf, Ind & Prefix & "_" & C_Name (Name)
                    & "(&n->" & F & ", f, ctx);");
               when others =>
                  return;
            end case;
            Append (Buf, LF);
         end Recurse;

         --  The element fields of a list node: a single named element, the
         --  bare `value` field, or the members of a grouped element.
         procedure Recurse_Elem (Info : Rule_Info; Prefix : String;
                                 Buf : in out U; Ind : String) is
         begin
            if Info.Elem_Members.Is_Empty then
               if Info.Elem_Name /= Null_Unbounded_String then
                  Recurse (To_String (Info.Elem_Name), Prefix, Buf, Ind);
               end if;
            else
               for M of Info.Elem_Members loop
                  Recurse (To_String (M.Name), Prefix, Buf, Ind);
               end loop;
            end if;
         end Recurse_Elem;

         procedure Visit_Def (Idx : Natural; Buf : in out U) is
            CN   : constant String := C_Name (To_String (Rules (Idx).Name));
            TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
            Info : constant Rule_Info := Infos (Idx);
         begin
            if Info.Kind = Struct then
               Append (Buf, "static void visit_" & CN & "(const "
                 & TN & " *n, visit_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    if (!n) return;");
               Append (Buf, LF);
               Append (Buf, "    f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
               for M of Info.Members loop
                  Recurse (To_String (M.Name), "visit", Buf, "    ");
               end loop;
            else
               Append (Buf, "static void visit_" & CN & "(const struct " & CN
                 & "_list *head, visit_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    const " & TN & " *n;");
               Append (Buf, LF);
               Append (Buf, "    HBNF_LIST_FOREACH(n, head) {");
               Append (Buf, LF);
               Append (Buf, "        f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
               Recurse_Elem (Info, "visit", Buf, "        ");
               Append (Buf, "    }");
               Append (Buf, LF);
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
         end Visit_Def;

         procedure Map_Def (Idx : Natural; Buf : in out U) is
            CN   : constant String := C_Name (To_String (Rules (Idx).Name));
            TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
            Info : constant Rule_Info := Infos (Idx);
         begin
            if Info.Kind = Struct then
               Append (Buf, "static void map_" & CN & "("
                 & TN & " *n, map_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    if (!n) return;");
               Append (Buf, LF);
               for M of Info.Members loop
                  Recurse (To_String (M.Name), "map", Buf, "    ");
               end loop;
               Append (Buf, "    f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
            else
               Append (Buf, "static void map_" & CN & "(struct " & CN
                 & "_list *head, map_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    " & TN & " *n;");
               Append (Buf, LF);
               Append (Buf, "    HBNF_LIST_FOREACH(n, head) {");
               Append (Buf, LF);
               Recurse_Elem (Info, "map", Buf, "        ");
               Append (Buf, "        f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
               Append (Buf, "    }");
               Append (Buf, LF);
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
         end Map_Def;

      begin
         Append (Buf, "/* ---- AST traversal (visit) and transform (map) ---- */");
         Append (Buf, LF);
         Append (Buf, "typedef enum {");
         declare
            First : Boolean := True;
         begin
            for I in 1 .. N loop
               if Infos (I).Kind = Struct or else Infos (I).Kind = List then
                  if not First then
                     Append (Buf, ",");
                  end if;
                  Append (Buf, LF);
                  Append (Buf, "    NODE_" & C_Ident
                    (C_Name (To_String (Rules (I).Name))));
                  First := False;
               end if;
            end loop;
         end;
         Append (Buf, LF);
         Append (Buf, "} node_kind_t;");
         Append (Buf, LF);
         Append (Buf, LF);
         Append (Buf, "typedef void (*visit_fn)(const void *node,"
           & " node_kind_t kind, void *ctx);");
         Append (Buf, LF);
         Append (Buf, "typedef void (*map_fn)(void *node, node_kind_t kind,"
           & " void *ctx);");
         Append (Buf, LF);
         Append (Buf, LF);

         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               declare
                  CN : constant String := C_Name (To_String (Rules (I).Name));
                  TN : constant String := C_Type_Name (To_String (Rules (I).Name));
               begin
                  if Infos (I).Kind = List then
                     Append (Buf, "static void visit_" & CN & "(const struct " & CN
                       & "_list *, visit_fn f, void *ctx);");
                     Append (Buf, LF);
                     Append (Buf, "static void map_" & CN & "(struct " & CN
                       & "_list *, map_fn f, void *ctx);");
                  else
                     Append (Buf, "static void visit_" & CN & "(const "
                       & TN & " *, visit_fn f, void *ctx);");
                     Append (Buf, LF);
                     Append (Buf, "static void map_" & CN & "("
                       & TN & " *, map_fn f, void *ctx);");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, LF);

         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               Visit_Def (I, Buf);
               Append (Buf, LF);
               Map_Def (I, Buf);
               Append (Buf, LF);
            end if;
         end loop;
      end Emit_Walk;

      Emitted   : array (1 .. N) of Boolean := [others => False];
      Remaining : Natural := 0;
      Res       : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (I));
      end loop;

      Append (Res, "/* generated by hbnf -- do not edit */");
      Append (Res, LF);
      if Preamble /= "" then
         Append (Res, Preamble);
         Append (Res, LF);
         Append (Res, LF);
      end if;
      Append (Res, "#include <stdint.h>");
      Append (Res, LF);
      Append (Res, "#include <stdbool.h>");
      Append (Res, LF);
      Append (Res, "#include <stddef.h>");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "/* List container: portable singly-linked by default.  A schema");
      Append (Res, LF);
      Append (Res, "   preamble may #define these to another container (e.g. OpenBSD's");
      Append (Res, LF);
      Append (Res, "   TAILQ, after #include <sys/queue.h>). */");
      Append (Res, LF);
      Append (Res, "#ifndef HBNF_LIST_HEAD");
      Append (Res, LF);
      Append (Res, "#define HBNF_LIST_HEAD(name, type) struct name { struct type *head, **tail; }");
      Append (Res, LF);
      Append (Res, "#define HBNF_LIST_ENTRY(type) struct type *_link");
      Append (Res, LF);
      Append (Res, "#define HBNF_LIST_INIT(h) do { (h)->head = NULL; (h)->tail = &(h)->head; } while (0)");
      Append (Res, LF);
      Append (Res, "#define HBNF_LIST_APPEND(h, e) do { *(h)->tail = (e); (h)->tail = &(e)->_link; } while (0)");
      Append (Res, LF);
      Append (Res, "#define HBNF_LIST_FOREACH(v, h) for ((v) = (h)->head; (v); (v) = (v)->_link)");
      Append (Res, LF);
      Append (Res, "#endif");
      Append (Res, LF);
      Append (Res, LF);

      if Idref then
         Append (Res, "/* object id: assigned by the serializer, resolved on "
           & "the rebuild side */");
         Append (Res, LF);
         Append (Res, "typedef uint32_t objid_t;");
         Append (Res, LF);
         Append (Res, LF);
      end if;

      --  Forward-declare every struct and list node type; a list rule also
      --  gets its list head type.
      for I in 1 .. N loop
         if Is_By_Value (Infos (I)) or else Infos (I).Kind = List then
            Append (Res, "typedef struct "
              & C_Name (To_String (Rules (I).Name))
              & " " & C_Type_Name (To_String (Rules (I).Name)) & ";");
            Append (Res, LF);
            if Infos (I).Kind = List then
               Append (Res, "HBNF_LIST_HEAD("
                 & C_Name (To_String (Rules (I).Name)) & "_list, "
                 & C_Name (To_String (Rules (I).Name)) & ");");
               Append (Res, LF);
            end if;
            Remaining := Remaining + 1;
         end if;
      end loop;
      Append (Res, LF);

      --  Leaves: scalars and enums, in dependency order — a scalar alias
      --  referencing another rule's type (e.g. `addr = ipv4`) must follow it.
      declare
         function Scalar_Ref (Idx : Natural) return Natural is
            R : constant Rule := Rules (Idx);
            P : constant Element_Vectors.Vector := R.Pattern;
         begin
            if Natural (P.Length) = 1 and then P (1).Kind = Name
              and then Scalar_C_Type (To_String (P (1).Name)) = ""
            then
               return Find (To_String (P (1).Name));
            end if;
            return 0;
         end Scalar_Ref;

         Remaining_Leaves : Natural := 0;
      begin
         for I in 1 .. N loop
            if Infos (I).Kind = Scalar or else Infos (I).Kind = Enum then
               Remaining_Leaves := Remaining_Leaves + 1;
            end if;
         end loop;
         while Remaining_Leaves > 0 loop
            declare
               Progress : Boolean := False;
            begin
               for I in 1 .. N loop
                  if (Infos (I).Kind = Scalar or else Infos (I).Kind = Enum)
                    and then not Emitted (I)
                  then
                     declare
                        D : constant Natural := Scalar_Ref (I);
                     begin
                        if D = 0 or else Emitted (D) then
                           Append (Res, Emit_Rule (I, Infos (I)));
                           Append (Res, LF);
                           Emitted (I) := True;
                           Remaining_Leaves := Remaining_Leaves - 1;
                           Progress := True;
                        end if;
                     end;
                  end if;
               end loop;
               if not Progress then
                  raise Parse_Error with "scalar cycle in schema";
               end if;
            end;
         end loop;
      end;

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

      Emit_Walk (Res);
      Append (Res, LF);

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
         return "a number";  --  int / uN / iN
      end if;
   end Core_Desc;

   --  The C expression that converts the token at p->pos into a core value.
   function Scalar_Parse_Expr (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "strdup(p->toks[p->pos].text)";
      elsif Name = "int" then
         return "atoll(p->toks[p->pos].text)";
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

      --  True when every `/`-alternative is exactly one Literal — the shape an
      --  enum can hold.  A multi-token alternative (`"a" "b" / "c" "d"`) or one
      --  that names another rule is not an enum.
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

      --  The underlying scalar C type a rule name resolves to (chasing
      --  single-name aliases and jets); "" if not scalar.
      function Resolve_Type (N : String; Depth : Natural := 0) return String is
         C : constant String := Scalar_C_Type (N);
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
                  return "const char *";
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

      --  The out-parameter type of parse_<rule>: a list hands back a list
      --  head (`struct <CN>_list *`), anything else a by-value struct/scalar
      --  (`<CN>_t *`).
      function Out_Type (Idx : Natural) return String is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            return "struct " & C_Name (To_String (R.Name)) & "_list *";
         end if;
         return C_Type_Name (To_String (R.Name)) & " *";
      end Out_Type;

      --  Emit matching + building for segment Els(First..Last), writing fields
      --  through the accessor Acc ("r." or "nn->").  On failure emits the
      --  `Fail` statement ("goto ..." or "p->pos = save; return false;").
      procedure Emit_Seq
        (Els : Element_Vectors.Vector; First, Last : Natural; Acc : String;
         Buf  : in out U; Fail : String; Ind : String := "    ") is
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               case E.Kind is
                  when Literal =>
                     Append (Buf, Ind & "if (!expect_lit(p, """
                       & To_String (E.Lit) & """)) { " & Fail & " }");
                     Append (Buf, LF);
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        Append (Buf, Ind & "if (!expect_kind(p, "
                          & Scalar_Tok_Kind (To_String (E.Name)) & ", """
                          & Core_Desc (To_String (E.Name)) & """)) { " & Fail & " }");
                        Append (Buf, LF);
                        Append (Buf, Ind & Acc
                          & C_Field (To_String (E.Name)) & " = "
                          & Scalar_Parse_Expr (To_String (E.Name)) & "; p->pos++;");
                        Append (Buf, LF);
                     else
                        Append (Buf, Ind & "if (!parse_rule_"
                          & C_Name (To_String (E.Name)) & "(p, &" & Acc
                          & C_Field (To_String (E.Name)) & ")) { " & Fail & " }");
                        Append (Buf, LF);
                     end if;
                  when Group =>
                     Emit_Seq (E.Items, 1, Natural (E.Items.Length), Acc, Buf,
                               Fail, Ind & "    ");
                  when Alt =>
                     null;
               end case;
            end;
         end loop;
      end Emit_Seq;

      --  Emit a backtracking alternation over the alternatives in Els (a flat
      --  list with Alt separators).  Each branch writes through Acc; a failed
      --  branch restores p->pos and resets the struct (Reset), a successful
      --  branch jumps to label `Ok`.  After the last branch fails, control
      --  falls through for the caller's own failure handling.
      procedure Emit_Alternation
        (Els : Element_Vectors.Vector; Acc, Reset, Ok : String;
         Buf : in out U; Ind : String := "    ") is
         N  : constant Natural := Natural (Els.Length);
         St : Natural := 1;
         Br : Natural := 0;

         function Img (X : Natural) return String is
            S : constant String := Natural'Image (X);
         begin
            if S'Length > 0 and then S (S'First) = ' ' then
               return S (S'First + 1 .. S'Last);
            end if;
            return S;
         end Img;
      begin
         for K in 1 .. N + 1 loop
            if K > N or else Els (K).Kind = Alt then
               Br := Br + 1;
               if Br > 1 then
                  Append (Buf, Ind & "p->pos = save; " & Reset & ";");
                  Append (Buf, LF);
               end if;
               Emit_Seq (Els, St, K - 1, Acc, Buf,
                         "goto alt_fail_" & Img (Br) & ";", Ind);
               Append (Buf, Ind & "goto " & Ok & ";");
               Append (Buf, LF);
               Append (Buf, "alt_fail_" & Img (Br) & ":");
               Append (Buf, LF);
               St := K + 1;
            end if;
         end loop;
      end Emit_Alternation;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         CN : constant String := C_Name (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Is_Pure_Literal_Alt (P);
         SU : constant String := (if not Is_List then Scalar_Union_Type (P) else "");
      begin
         if R.Jet_Code /= Null_Unbounded_String then
            --  A jet: match its own token kind and yield the matched text.
            Append (Buf, "    if (!expect_kind(p, TOK_" & C_Ident (NM)
              & ", ""a " & NM & """)) return false;");
            Append (Buf, LF);
            Append (Buf, "    *out = strdup(p->toks[p->pos].text); p->pos++;");
            Append (Buf, LF);
            Append (Buf, "    return true;");
            Append (Buf, LF);
            return;
         end if;
         if Is_List then
            declare
               E : constant Element_Access := P (1);
            begin
               Append (Buf, "    struct " & C_Name (NM) & "_list head;");
               Append (Buf, LF);
               Append (Buf, "    HBNF_LIST_INIT(&head);");
               Append (Buf, LF);
               Append (Buf, "    while (p->pos < p->n) {");
               Append (Buf, LF);
               Append (Buf, "        " & C_Type_Name (NM) & " *nn ="
                 & " calloc(1, sizeof(*nn));");
               Append (Buf, LF);
               Append (Buf, "        size_t save = p->pos;");
               Append (Buf, LF);
               if E.Kind = Name then
                  Append (Buf, "        if (parse_rule_" & C_Name (To_String (E.Name))
                    & "(p, &nn->" & C_Field (To_String (E.Name)) & ")) goto have;");
                  Append (Buf, LF);
               else
                  Emit_Alternation (E.Items, "nn->",
                                    "memset(nn, 0, sizeof *nn)", "have", Buf,
                                    "        ");
               end if;
               Append (Buf, "        p->pos = save; free(nn); break;");
               Append (Buf, LF);
               Append (Buf, "have:");
               Append (Buf, LF);
               Append (Buf, "        HBNF_LIST_APPEND(&head, nn);");
               Append (Buf, LF);
               Append (Buf, "    }");
               Append (Buf, LF);
               Append (Buf, "    *out = head; return true;");
               Append (Buf, LF);
            end;
         elsif Is_Enum then
            declare
               Lits  : String_Vectors.Vector;
               Names : String_Vectors.Vector;
            begin
               --  Collect each alternative's literal, in order, for naming.
               declare
                  St : Natural := 1;
               begin
                  for K in 1 .. Natural (P.Length) + 1 loop
                     if K > Natural (P.Length) or else P (K).Kind = Alt then
                        if St <= K - 1 and then P (St).Kind = Literal then
                           Lits.Append (P (St).Lit);
                        end if;
                        St := K + 1;
                     end if;
                  end loop;
               end;
               Names := Enum_Names (Lits);

               Append (Buf, "    if (!expect_kind(p, TOK_ATOM, ""a "
                 & CN & """)) return false;");
               Append (Buf, LF);
               Append (Buf, "    {");
               Append (Buf, LF);
               Append (Buf, "        " & C_Type_Name (NM) & " r = " & C_Ident (NM) & "_"
                 & To_String (Names (1)) & ";");
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
                             & To_String (Names (Branch + 1)) & ";");
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
            end;
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
               Append (Buf, "    return parse_rule_" & C_Name (To_String (P (1).Name))
                 & "(p, out);");
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
                              Append (Buf, "    if (p->pos < p->n && p->toks[p->pos].kind == "
                                & Scalar_Tok_Kind (To_String (E.Name)) & ") {");
                              Append (Buf, LF);
                              Append (Buf, "        *out = "
                                & Scalar_Parse_Expr (To_String (E.Name))
                                & "; p->pos++; return true; }");
                              Append (Buf, LF);
                           elsif E.Kind = Name then
                              Append (Buf, "    if (parse_rule_"
                                & C_Name (To_String (E.Name)) & "(p, out)) return true;");
                              Append (Buf, LF);
                           end if;
                        end;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "    fail(p, ""a " & NM & """, p->pos < p->n"
              & " ? p->toks[p->pos].text : ""end of input"");");
            Append (Buf, LF);
            Append (Buf, "    return false;");
            Append (Buf, LF);
         elsif Has_Alt (P) then
            --  A struct alternation: try each branch with backtracking.
            Append (Buf, "    size_t save = p->pos;");
            Append (Buf, LF);
            Append (Buf, "    " & C_Type_Name (NM) & " r = {0};");
            Append (Buf, LF);
            Emit_Alternation (P, "r.", "memset(&r, 0, sizeof r)", "ok", Buf);
            Append (Buf, "    p->pos = save; return false;");
            Append (Buf, LF);
            Append (Buf, "ok:");
            Append (Buf, LF);
            Append (Buf, "    *out = r; return true;");
            Append (Buf, LF);
         else
            --  A struct sequence: match literals and references in order.
            Append (Buf, "    size_t save = p->pos;");
            Append (Buf, LF);
            Append (Buf, "    " & C_Type_Name (NM) & " r = {0};");
            Append (Buf, LF);
            Emit_Seq (P, 1, Natural (P.Length), "r.", Buf,
                      "p->pos = save; return false;");
            Append (Buf, "    *out = r; return true;");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Parser;

      Res : U;
   begin
      Append (Res, "/* generated by hbnf -- do not edit */");
      Append (Res, LF);
      Append (Res, "#include <stdlib.h>");
      Append (Res, LF);
      Append (Res, "#include <string.h>");
      Append (Res, LF);
      Append (Res, "#include <stdio.h>");
      Append (Res, LF);
      Append (Res, "#include <ctype.h>");
      Append (Res, LF);
      Append (Res, LF);
      declare
         Enum : U := To_Unbounded_String
           ("typedef enum { TOK_ATOM, TOK_STR, TOK_INT, TOK_PUNCT");
      begin
         for I in 1 .. N loop
            if Rules (I).Jet_Code /= Null_Unbounded_String then
               Append (Enum, ", TOK_"
                 & C_Ident (To_String (Rules (I).Name)));
            end if;
         end loop;
         Append (Enum, ", TOK_EOF } tok_kind_t;");
         Append (Res, To_String (Enum));
         Append (Res, LF);
      end;
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
      Append (Res, "    size_t err_pos;");
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
      Append (Res, "    if (p->err_pos != (size_t)-1 && p->pos <= p->err_pos)"
        & " return;  /* a deeper failure already recorded */");
      Append (Res, LF);
      Append (Res, "    p->err_pos = p->pos;");
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
         Append (Res, "static bool parse_rule_" & C_Name (To_String (Rules (I).Name))
           & "(parser_t *p, " & Out_Type (I) & " out);");
         Append (Res, LF);
      end loop;
      Append (Res, LF);

      for I in 1 .. N loop
         declare
            R : constant Rule := Rules (I);
         begin
            Append (Res, "static bool parse_rule_" & C_Name (To_String (R.Name))
              & "(parser_t *p, " & Out_Type (I) & " out) {");
            Append (Res, LF);
            Emit_Rule_Parser (I, Res);
            Append (Res, "}");
            Append (Res, LF);
            Append (Res, LF);
         end;
      end loop;

      --  The entry point: parse the root rule, then reject trailing input.
      Append (Res, "bool parse_tokens(const token_t *toks, size_t n, "
        & Out_Type (1) & " out,");
      Append (Res, LF);
      Append (Res, "                  const char *const *lines, size_t nlines,");
      Append (Res, LF);
      Append (Res, "                  char *err, size_t errlen,"
        & " size_t *err_line, size_t *err_col) {");
      Append (Res, LF);
      Append (Res, "    parser_t p = { toks, n, 0, lines, nlines, (size_t)-1, 0, 0, {0} };");
      Append (Res, LF);
      Append (Res, "    if (!parse_rule_" & C_Name (To_String (Rules (1).Name))
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

      --  Jets: hand-written scanners, plus the dispatch the lexer calls.
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               R  : constant Rule := Rules (I);
               NM : constant String := To_String (R.Name);
            begin
               Append (Res, "static size_t jet_" & C_Name (NM)
                 & "(const char *s, size_t pos, size_t len) {");
               Append (Res, LF);
               Append (Res, To_String (R.Jet_Code));
               Append (Res, LF);
               Append (Res, "}");
               Append (Res, LF);
               Append (Res, LF);
            end;
         end if;
      end loop;

      Append (Res, "static size_t jet_dispatch(const char *s, size_t pos,"
        & " size_t len, tok_kind_t *kind) {");
      Append (Res, LF);
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               NM : constant String := To_String (Rules (I).Name);
            begin
               Append (Res, "    { size_t n = jet_" & C_Name (NM)
                 & "(s, pos, len); if (n > 0) { *kind = TOK_" & C_Ident (NM)
                 & "; return n; } }");
               Append (Res, LF);
            end;
         end if;
      end loop;
      Append (Res, "    return 0;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);

      return To_String (Res);
   end Emit_Parser;

   function Emit_Lexer (Rules : Rule_Vectors.Vector) return String is
      Root_T : constant String := Root_Type (Rules);
      Lexer  : constant String :=
        Templates.Substitute (Templates.C_Lexer, "@ROOT_TYPE@", Root_T);
   begin
      if Epilogue = "" then
         return Lexer;
      else
         return Lexer & LF & Epilogue;
      end if;
   end Emit_Lexer;

   --  conf.h: the declarations plus the global `conf`, the error callback and
   --  the parse_config prototype.
   function Emit_Conf_Header (Rules : Rule_Vectors.Vector) return String is
      Root_T : constant String := Root_Type (Rules);
   begin
      return
        "#ifndef CONF_H" & LF &
        "#define CONF_H" & LF & LF &
        Emit (Rules) &
        LF &
        Templates.Substitute (Templates.Conf_H, "@ROOT_TYPE@", Root_T) &
        LF &
        "#endif" & LF;
   end Emit_Conf_Header;

   --  conf.c: the lexer + parser plus the global `conf` and parse_config
   --  (slurp the file, populate conf, report errors through the callback).
   function Emit_Conf_Source (Rules : Rule_Vectors.Vector) return String is
      Root_T : constant String := Root_Type (Rules);
   begin
      return
        "/* generated by hbnf -- do not edit */" & LF & LF &
        "#include ""conf.h""" & LF & LF &
        Emit_Parser (Rules) &
        Emit_Lexer (Rules) &
        LF &
        Templates.Substitute (Templates.Conf_Tail_C, "@ROOT_TYPE@", Root_T);
   end Emit_Conf_Source;

   --  =====================================================================
   --  Emit_Serializer: a pre-order walk of the tree Emit declares that
   --  assigns ids in traversal order and emits one flat, typed record per
   --  object through an abstract `emit` callback.  Cross-references are ids,
   --  never pointers, so the output can cross a process boundary.
   function Emit_Serializer (Rules : Rule_Vectors.Vector) return String is
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      function Ref_Kind (Name : String) return Class_Kind is
         J : constant Natural := Find (Rules, Name);
      begin
         if J = 0 then
            return Scalar;
         end if;
         return Infos (J).Kind;
      end Ref_Kind;

      --  The C type a leaf (scalar/enum) member serializes as.
      function Leaf_Type (Name : String) return String is
      begin
         case Ref_Kind (Name) is
            when Enum =>
               return C_Type_Name (Name);
            when others =>
               declare
                  R : constant String := Resolve_Type (Rules, Name);
               begin
                  if R /= "" then
                     return R;
                  end if;
                  return C_Type_Of (Rules, Name);
               end;
         end case;
      end Leaf_Type;

      --  The members of a node (struct members, or a list's element members).
      function Node_Members (Info : Rule_Info) return Member_Vectors.Vector is
         M : Member_Vectors.Vector;
      begin
         case Info.Kind is
            when Struct =>
               return Info.Members;
            when List =>
               if Info.Elem_Members.Is_Empty then
                  if Info.Elem_Name /= Null_Unbounded_String then
                     M.Append
                       (Member'(Name => Info.Elem_Name, Is_List => False));
                  end if;
               else
                  return Info.Elem_Members;
               end if;
            when others =>
               null;
         end case;
         return M;
      end Node_Members;

      --  A list of a bare literal carries a `value` string field, which is
      --  not a rule reference and so needs special handling.
      function Has_Bare_Value (Info : Rule_Info) return Boolean is
        (Info.Kind = List and then Info.Elem_Members.Is_Empty
         and then Info.Elem_Name = Null_Unbounded_String);

      --  A member is a child node (recursed) rather than a serialized leaf.
      function Is_Child (M : Member) return Boolean is
         J : constant Natural := Find (Rules, To_String (M.Name));
      begin
         return M.Is_List
           or else (J > 0 and then (Infos (J).Kind = Struct
                                    or else Infos (J).Kind = List));
      end Is_Child;

      --  The serializer body for one node, writing through `n->` at the given
      --  indentation.  `CN` names the wire struct (`struct CN_msg`).
      procedure Emit_Body (CN : String; Info : Rule_Info;
                           Buf : in out U; Ind : String) is
         Ms   : constant Member_Vectors.Vector := Node_Members (Info);
         Bare : constant Boolean := Has_Bare_Value (Info);
      begin
         Append (Buf, Ind & "objid_t id = next_id++;");
         Append (Buf, LF);
         Append (Buf, Ind & "struct " & CN & "_msg m; memset(&m, 0, sizeof m);");
         Append (Buf, LF);
         Append (Buf, Ind & "m.id = id; m.parent = parent;");
         Append (Buf, LF);
         if Bare then
            Append (Buf, Ind & "m.value_len = n->value ?"
              & " (uint32_t)strlen(n->value) : 0;");
            Append (Buf, LF);
         end if;
         for M of Ms loop
            if not Is_Child (M) then
               declare
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  if Leaf_Type (To_String (M.Name)) = "const char *" then
                     Append (Buf, Ind & "m." & F & "_len = n->" & F & " ?"
                       & " (uint32_t)strlen(n->" & F & ") : 0;");
                  else
                     Append (Buf, Ind & "m." & F & " = n->" & F & ";");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, Ind & "emit(MSG_" & C_Ident (CN) & ", &m, sizeof m);");
         Append (Buf, LF);
         if Bare then
            Append (Buf, Ind & "if (n->value) emit(MSG_STR, n->value,"
              & " m.value_len);");
            Append (Buf, LF);
         end if;
         for M of Ms loop
            if not Is_Child (M)
              and then Leaf_Type (To_String (M.Name)) = "const char *"
            then
               declare
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  Append (Buf, Ind & "if (n->" & F & ") emit(MSG_STR, n->" & F
                    & ", m." & F & "_len);");
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         for M of Ms loop
            if Is_Child (M) then
               declare
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  --  Both by-value struct members and embedded list heads are
                  --  passed by address (&n->field).
                  Append (Buf, Ind & "serialize_" & C_Name (To_String (M.Name))
                    & "(&n->" & F & ", id, emit);");
                  Append (Buf, LF);
               end;
            end if;
         end loop;
      end Emit_Body;

      procedure Serialize_Def (Idx : Natural; Buf : in out U) is
         NM   : constant String := To_String (Rules (Idx).Name);
         CN   : constant String := C_Name (NM);
         TN   : constant String := C_Type_Name (NM);
         Info : constant Rule_Info := Infos (Idx);
         Ms   : constant Member_Vectors.Vector := Node_Members (Info);
         Bare : constant Boolean := Has_Bare_Value (Info);
      begin
         --  The wire record: ids plus the fixed-width leaves; string leaves
         --  become a length prefix, with the bytes emitted separately.
         Append (Buf, "struct " & CN & "_msg {");
         Append (Buf, LF);
         Append (Buf, "    objid_t id, parent;");
         Append (Buf, LF);
         if Bare then
            Append (Buf, "    uint32_t value_len;");
            Append (Buf, LF);
         end if;
         for M of Ms loop
            if not Is_Child (M) then
               declare
                  T : constant String := Leaf_Type (To_String (M.Name));
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  if T = "const char *" then
                     Append (Buf, "    uint32_t " & F & "_len;");
                  else
                     Append (Buf, "    " & T & " " & F & ";");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, "};");
         Append (Buf, LF);
         Append (Buf, LF);

         if Info.Kind = Struct then
            Append (Buf, "void serialize_" & CN & "(const " & TN
              & " *n, objid_t parent, emit_fn emit) {");
            Append (Buf, LF);
            Append (Buf, "    if (!n) return;");
            Append (Buf, LF);
            Emit_Body (CN, Info, Buf, "    ");
            Append (Buf, "}");
         else
            Append (Buf, "void serialize_" & CN & "(const struct " & CN
              & "_list *head, objid_t parent, emit_fn emit) {");
            Append (Buf, LF);
            Append (Buf, "    const " & TN & " *n;");
            Append (Buf, LF);
            Append (Buf, "    HBNF_LIST_FOREACH(n, head) {");
            Append (Buf, LF);
            Emit_Body (CN, Info, Buf, "        ");
            Append (Buf, "    }");
            Append (Buf, LF);
            Append (Buf, "}");
         end if;
         Append (Buf, LF);
      end Serialize_Def;

      Res : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;

      Append (Res, "/* ---- id-ref serializer ---- */");
      Append (Res, LF);
      Append (Res, "typedef void (*emit_fn)(uint32_t type, const void *p,"
        & " size_t n);");
      Append (Res, LF);
      Append (Res, "static objid_t next_id = 1;");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "enum {");
      Append (Res, LF);
      declare
         First : Boolean := True;
      begin
         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               Append (Res, "    MSG_"
                 & C_Ident (C_Name (To_String (Rules (I).Name))));
               if First then
                  Append (Res, " = 1");
               end if;
               Append (Res, ",");
               Append (Res, LF);
               First := False;
            end if;
         end loop;
      end;
      Append (Res, "    MSG_STR");
      Append (Res, LF);
      Append (Res, "};");
      Append (Res, LF);
      Append (Res, LF);

      --  Forward-declare the per-type serializers (they recurse into each
      --  other).
      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            declare
               CN : constant String := C_Name (To_String (Rules (I).Name));
               TN : constant String := C_Type_Name (To_String (Rules (I).Name));
               PT : constant String :=
                 (if Infos (I).Kind = List then "const struct " & CN & "_list *"
                  else "const " & TN & " *");
            begin
               Append (Res, "void serialize_" & CN & "(" & PT
                 & ", objid_t parent, emit_fn emit);");
               Append (Res, LF);
            end;
         end if;
      end loop;
      Append (Res, LF);

      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            Serialize_Def (I, Res);
            Append (Res, LF);
         end if;
      end loop;

      declare
         RN          : constant String := C_Name (To_String (Rules (1).Name));
         Root_Is_List : constant Boolean := Infos (1).Kind = List;
         RT : constant String :=
           (if Root_Is_List then "struct " & RN & "_list"
            else C_Type_Name (To_String (Rules (1).Name)));
      begin
         --  Named `serialize_tree` (not `serialize_config`) because the root
         --  rule is often literally `config`, whose own per-type serializer
         --  would otherwise collide.
         Append (Res, "void serialize_tree(const " & RT
           & " *conf, emit_fn emit) {");
         Append (Res, LF);
         Append (Res, "    next_id = 1;");
         Append (Res, LF);
         Append (Res, "    serialize_" & RN & "(conf, 0, emit);");
         Append (Res, LF);
         Append (Res, "}");
         Append (Res, LF);
      end;

      return To_String (Res);
   end Emit_Serializer;

   --  =====================================================================
   --  Emit_Rebuild: a flat id-indexed config table, a `_find(id)` helper per
   --  object type, and a `config_get<name>()` per type that allocates, fills
   --  scalars, and stores the object keyed by its id.  The consumer demarshal
   --  s records in id order, sizes the arrays, and relinks children into
   --  parents using the stored parent id and the *_find helpers.
   function Emit_Rebuild (Rules : Rule_Vectors.Vector) return String is
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      function Ref_Kind (Name : String) return Class_Kind is
         J : constant Natural := Find (Rules, Name);
      begin
         if J = 0 then
            return Scalar;
         end if;
         return Infos (J).Kind;
      end Ref_Kind;

      function Leaf_Type (Name : String) return String is
      begin
         case Ref_Kind (Name) is
            when Enum =>
               return C_Type_Name (Name);
            when others =>
               declare
                  R : constant String := Resolve_Type (Rules, Name);
               begin
                  if R /= "" then
                     return R;
                  end if;
                  return C_Type_Of (Rules, Name);
               end;
         end case;
      end Leaf_Type;

      function Node_Members (Info : Rule_Info) return Member_Vectors.Vector is
         M : Member_Vectors.Vector;
      begin
         case Info.Kind is
            when Struct =>
               return Info.Members;
            when List =>
               if Info.Elem_Members.Is_Empty then
                  if Info.Elem_Name /= Null_Unbounded_String then
                     M.Append
                       (Member'(Name => Info.Elem_Name, Is_List => False));
                  end if;
               else
                  return Info.Elem_Members;
               end if;
            when others =>
               null;
         end case;
         return M;
      end Node_Members;

      function Has_Bare_Value (Info : Rule_Info) return Boolean is
        (Info.Kind = List and then Info.Elem_Members.Is_Empty
         and then Info.Elem_Name = Null_Unbounded_String);

      function Is_Child (M : Member) return Boolean is
         J : constant Natural := Find (Rules, To_String (M.Name));
      begin
         return M.Is_List
           or else (J > 0 and then (Infos (J).Kind = Struct
                                    or else Infos (J).Kind = List));
      end Is_Child;

      --  Fixed-width (non-string) leaf fields, in field order.
      function Fixed_Leaves (Info : Rule_Info) return Member_Vectors.Vector is
         V  : Member_Vectors.Vector;
         Ms : constant Member_Vectors.Vector := Node_Members (Info);
      begin
         for M of Ms loop
            if not Is_Child (M)
              and then Leaf_Type (To_String (M.Name)) /= "const char *"
            then
               V.Append (M);
            end if;
         end loop;
         return V;
      end Fixed_Leaves;

      --  String leaf fields, in field order (matches the serializer's emit
      --  order), the bare `value` field first.
      function String_Leaves (Info : Rule_Info) return Member_Vectors.Vector is
         V  : Member_Vectors.Vector;
         Ms : constant Member_Vectors.Vector := Node_Members (Info);
      begin
         if Has_Bare_Value (Info) then
            V.Append
              (Member'(Name => To_Unbounded_String ("value"), Is_List => False));
         end if;
         for M of Ms loop
            if not Is_Child (M)
              and then Leaf_Type (To_String (M.Name)) = "const char *"
            then
               V.Append (M);
            end if;
         end loop;
         return V;
      end String_Leaves;

      procedure Rebuild_Def (Idx : Natural; Buf : in out U) is
         NM   : constant String := To_String (Rules (Idx).Name);
         CN   : constant String := C_Name (NM);
         TN   : constant String := C_Type_Name (NM);
         Info : constant Rule_Info := Infos (Idx);
         Fix  : constant Member_Vectors.Vector := Fixed_Leaves (Info);
         Str  : constant Member_Vectors.Vector := String_Leaves (Info);
      begin
         Append (Buf, TN & " *" & CN & "_find(struct config_table *c, objid_t id) {");
         Append (Buf, LF);
         Append (Buf, "    return (id >= 1 && id <= c->n" & CN
           & ") ? c->" & CN & "[id - 1] : NULL;");
         Append (Buf, LF);
         Append (Buf, "}");
         Append (Buf, LF);
         Append (Buf, LF);

         declare
            Args : U := Null_Unbounded_String;
         begin
            for S of Str loop
               if Args /= Null_Unbounded_String then
                  Append (Args, ", ");
               end if;
               Append (Args, "const char *" & C_Field (To_String (S.Name)));
            end loop;
            Append (Buf, "void config_get" & CN
              & "(struct config_table *c, const struct " & CN & "_msg *m"
              & (if Args = Null_Unbounded_String then ""
                 else ", " & To_String (Args))
              & ") {");
            Append (Buf, LF);
         end;
         Append (Buf, "    " & TN & " *n = calloc(1, sizeof *n);");
         Append (Buf, LF);
         Append (Buf, "    n->id = m->id; n->parent = m->parent;");
         Append (Buf, LF);
         for M of Fix loop
            declare
               F : constant String := C_Field (To_String (M.Name));
            begin
               Append (Buf, "    n->" & F & " = m->" & F & ";");
               Append (Buf, LF);
            end;
         end loop;
         for M of Str loop
            declare
               F : constant String := C_Field (To_String (M.Name));
            begin
               Append (Buf, "    n->" & F & " = " & F & " ? strdup(" & F & ") : NULL;");
               Append (Buf, LF);
            end;
         end loop;
         Append (Buf, "    c->" & CN & "[m->id - 1] = n;");
         Append (Buf, LF);
         Append (Buf, "    if (m->id > c->n" & CN & ") c->n" & CN & " = m->id;");
         Append (Buf, LF);
         Append (Buf, "}");
         Append (Buf, LF);
      end Rebuild_Def;

      Res : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;

      Append (Res, "/* ---- id-ref rebuild ---- */");
      Append (Res, LF);
      Append (Res, "struct config_table {");
      Append (Res, LF);
      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            declare
               CN : constant String := C_Name (To_String (Rules (I).Name));
               TN : constant String := C_Type_Name (To_String (Rules (I).Name));
            begin
               Append (Res, "    " & TN & " **" & CN & ";");
               Append (Res, LF);
               Append (Res, "    objid_t   n" & CN & ";");
               Append (Res, LF);
            end;
         end if;
      end loop;
      Append (Res, "};");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "void config_init(struct config_table *c) { memset(c, 0, sizeof *c); }");
      Append (Res, LF);
      Append (Res, LF);

      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            Rebuild_Def (I, Res);
            Append (Res, LF);
         end if;
      end loop;

      return To_String (Res);
   end Emit_Rebuild;

end HBNF_C;
