pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Templates;

package body HBNF_Zig is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

   subtype U is Unbounded_String;

   LF : constant Character := ASCII.LF;

   package String_Vectors is new Ada.Containers.Vectors (Positive, U);
   package Natural_Vectors is new Ada.Containers.Vectors (Positive, Natural);

   --  The Zig type for a built-in core rule, or "" if not a core scalar.
   function Scalar_Zig_Type (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "[]const u8";
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
   end Scalar_Zig_Type;

   --  A snake_case identifier from a schema name ('-' -> '_').
   function Zig_Snake (S : String) return String is
      Buf : U;
   begin
      for C of S loop
         Append (Buf, (if C = '-' then '_' else C));
      end loop;
      return To_String (Buf);
   end Zig_Snake;

   --  A PascalCase type name from a schema name ('-' / '_' split a word).
   function Zig_Type (S : String) return String is
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
   end Zig_Type;

   --  A field name: snake_case, with a "_" suffix if it is a Zig keyword.
   function Zig_Field (S : String) return String is
      N : constant String := Zig_Snake (S);
   begin
      if N = "align" or else N = "allowzero" or else N = "and"
        or else N = "anyframe" or else N = "anytype" or else N = "asm"
        or else N = "async" or else N = "await" or else N = "break"
        or else N = "callconv" or else N = "catch" or else N = "comptime"
        or else N = "const" or else N = "continue" or else N = "defer"
        or else N = "else" or else N = "enum" or else N = "errdefer"
        or else N = "error" or else N = "export" or else N = "extern"
        or else N = "fn" or else N = "for" or else N = "if"
        or else N = "inline" or else N = "linksection" or else N = "noalias"
        or else N = "nosuspend" or else N = "opaque" or else N = "or"
        or else N = "orelse" or else N = "packed" or else N = "pub"
        or else N = "resume" or else N = "return" or else N = "struct"
        or else N = "suspend" or else N = "switch" or else N = "test"
        or else N = "threadlocal" or else N = "try" or else N = "union"
        or else N = "unreachable" or else N = "usingnamespace"
        or else N = "var" or else N = "volatile" or else N = "while"
        or else N = "true" or else N = "false" or else N = "null"
        or else N = "undefined" or else N = "void" or else N = "noreturn"
        or else N = "type" or else N = "anyerror"
      then
         return N & "_";
      end if;
      return N;
   end Zig_Field;

   --  Escape a literal for a Zig string literal.  Zig's `\x` takes exactly
   --  two hex digits, so `\xNN` is safe for any non-printable byte; the named
   --  controls use their short forms.
   function Zig_Escape (S : String) return String is
      Buf : U;
      Hex : constant String := "0123456789abcdef";
   begin
      for C of S loop
         case C is
            when '\' => Append (Buf, "\\");
            when '"' => Append (Buf, "\""");
            when others =>
               case Character'Pos (C) is
                  when 9  => Append (Buf, "\t");
                  when 10 => Append (Buf, "\n");
                  when 13 => Append (Buf, "\r");
                  when 32 .. 126 => Append (Buf, C);
                  when others =>
                     declare
                        V : constant Natural := Character'Pos (C);
                     begin
                        Append (Buf, "\x");
                        Append (Buf, Hex (V / 16 + 1));
                        Append (Buf, Hex (V mod 16 + 1));
                     end;
               end case;
         end case;
      end loop;
      return To_String (Buf);
   end Zig_Escape;

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
   --  through Zig_Field and then any non-alphanumeric folded to '_', so
   --  "tlsv1.0" -> "tlsv1_0".  A name that is empty, all '_', or begins with
   --  a digit (pure punctuation like "*" or "!=") becomes `op<pos>`; and
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
            Base : constant String := Fold (Zig_Field (To_String (Lits (I))));
            N    : U;
         begin
            if Base = "" or else (for all C of Base => C = '_')
              or else Base (Base'First) in '0' .. '9'
            then
               N := To_Unbounded_String ("op" & Img (I));
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

   --  Append Text as `//` line comments, prefixing every line (a schema's
   --  leading comment block spans multiple lines joined by LF).
   procedure Append_Comment (B : in out U; Text : String) is
      Line_Start : Natural := Text'First;
   begin
      if Text'Length = 0 then
         return;
      end if;
      for K in Text'Range loop
         if Text (K) = ASCII.LF then
            Append (B, "// " & Text (Line_Start .. K - 1) & LF);
            Line_Start := K + 1;
         end if;
      end loop;
      Append (B, "// " & Text (Line_Start .. Text'Last) & LF);
   end Append_Comment;

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

      --  The Zig type a rule reference denotes: a core scalar inlines; any
      --  other reference resolves to the referenced rule's own type name.
      function Zig_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Zig_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         if Find (Ref) = 0 then
            raise Parse_Error with "undefined rule: " & Ref;
         end if;
         return Zig_Type (Ref);
      end Zig_Type_Of;

      --  The underlying scalar Zig type a rule name resolves to, chasing
      --  single-name aliases and jets to their target (so `str / word` and
      --  `ipv4 / ipv6` both collapse to `[]const u8`).  "" if not scalar.
      function Resolve_Type (N : String; Depth : Natural := 0) return String is
         C : constant String := Scalar_Zig_Type (N);
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
                  return "[]const u8";
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
      --  the same scalar Zig type, that type (a scalar union); else "".
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
         Seen : String_Vectors.Vector;

         function Seen_Here (S : U) return Boolean is
         begin
            for X of Seen loop
               if X = S then
                  return True;
               end if;
            end loop;
            return False;
         end Seen_Here;
      begin
         for E of Els loop
            case E.Kind is
               when Name =>
                  declare
                     Is_List : constant Boolean :=
                       E.Min /= 1 or else E.Max /= 1;
                  begin
                     if Seen_Here (E.Name) then
                        raise Parse_Error with
                          "rule """ & To_String (E.Name)
                          & """ is referenced twice in one alternative;"
                          & " split it into alias rules (e.g. `a = "
                          & To_String (E.Name) & "; b = " & To_String (E.Name)
                          & ";`) so each gets its own field";
                     end if;
                     Seen.Append (E.Name);
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
                  Seen.Clear;
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
            return (Kind        => Scalar,
                    Inline_Type => To_Unbounded_String ("[]const u8"));
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
                              (Zig_Type_Of (To_String (E.Name))));
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
                          Inline_Type => To_Unbounded_String ("[]const u8"));
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

      --  Structs and lists both name a type.  Zig's lazy analysis lets a
      --  declaration refer to a type declared later, so only a genuine
      --  by-value embedding imposes an ordering constraint (and, transitively,
      --  the infinite-type cycle the sort below guards against).
      function Is_Type (Info : Rule_Info) return Boolean is
        (Info.Kind = Struct or else Info.Kind = List);

      --  A struct member embedded by value; a list is a `[]T` slice (and a
      --  reference to a list is its slice alias), so neither embeds by value.
      function Is_By_Value (Info : Rule_Info) return Boolean is
        (Info.Kind = Struct);

      Infos : Info_Vectors.Vector;

      --  The rule indices this rule must be emitted after: only the structs it
      --  embeds by value.  List members and list references are slices, which
      --  break the cycle.
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
                  null;  --  a slice; its element type is not embedded by value
               when others =>
                  null;
            end case;
         end;
         return D;
      end Deps;

      function Emit_Rule (Idx : Natural; Info : Rule_Info) return String is
         R    : constant Rule := Rules (Idx);
         Base : constant String := Zig_Type (To_String (R.Name));
         Buf  : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append_Comment (Buf, To_String (R.Leading_Comment));
         end if;

         case Info.Kind is
            when Scalar =>
               Append (Buf, "pub const " & Base & " = " &
                       To_String (Info.Inline_Type) & ";");
               Append (Buf, LF);
            when Enum =>
               declare
                  Names : constant String_Vectors.Vector := Enum_Names (Info.Literals);
               begin
                  Append (Buf, "pub const " & Base & " = enum {");
                  Append (Buf, LF);
                  for I in 1 .. Natural (Info.Literals.Length) loop
                     Append (Buf, "    " &
                             To_String (Names (I)) & ",");
                     Append (Buf, LF);
                  end loop;
                  Append (Buf, "};");
                  Append (Buf, LF);
               end;
            when Struct =>
               Append (Buf, "pub const " & Base & " = struct {");
               Append (Buf, LF);
               for M of Info.Members loop
                  Append (Buf, "    " &
                          Zig_Field (To_String (M.Name)) & ": ");
                  if M.Is_List then
                     Append (Buf, "[]" &
                             Zig_Type_Of (To_String (M.Name)) & ",");
                  else
                     Append (Buf, Zig_Type_Of (To_String (M.Name)) & ",");
                  end if;
                  Append (Buf, LF);
               end loop;
               Append (Buf, "};");
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

      --  A top-level list rule: a `[]T` slice alias.  A group element becomes
      --  a named `BaseEntry` struct first.
      function Emit_List (Idx : Natural; Info : Rule_Info) return String is
         R    : constant Rule := Rules (Idx);
         Base : constant String := Zig_Type (To_String (R.Name));
         Buf  : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append_Comment (Buf, To_String (R.Leading_Comment));
         end if;

         if Info.Elem_Members.Is_Empty then
            if Info.Elem_Name = Null_Unbounded_String then
               Append (Buf, "pub const " & Base & " = [][]const u8;");
            else
               Append (Buf, "pub const " & Base & " = []" &
                       Zig_Type_Of (To_String (Info.Elem_Name)) & ";");
            end if;
         else
            Append (Buf, "pub const " & Base & "Entry = struct {");
            Append (Buf, LF);
            for M of Info.Elem_Members loop
               Append (Buf, "    " &
                       Zig_Field (To_String (M.Name)) & ": " &
                       Zig_Type_Of (To_String (M.Name)) & ",");
               Append (Buf, LF);
            end loop;
            Append (Buf, "};");
            Append (Buf, LF);
            Append (Buf, "pub const " & Base & " = []" & Base & "Entry;");
         end if;
         Append (Buf, LF);

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " // " & To_String (R.Trailing_Comment));
            Append (Buf, LF);
         end if;
         return To_String (Buf);
      end Emit_List;

      --  Emit AST walk (visit) and transform (fold) helpers: visit_<rule>/
      --  fold_<rule> free functions that take an `anytype` visitor/folder and
      --  do the structural recursion.  visit_ is pre-order and read-only
      --  (`*const`); fold_ is bottom-up and mutates the node in place (`*`).
      --  A scalar or enum member (and a []scalar) is a leaf.
      procedure Emit_Walk (Buf : in out U) is

         function Ref_Kind (Name : String) return Class_Kind is
            J : constant Natural := Find (Name);
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         --  The visit/fold function base for the ELEMENT of a list rule Name,
         --  or "" when the element is a scalar/enum leaf.
         function Elem_Fn (Name : String) return String is
            J    : constant Natural := Find (Name);
            Info : constant Rule_Info := Infos (J);
         begin
            if J = 0 then
               return "";
            end if;
            if not Info.Elem_Members.Is_Empty then
               return Zig_Snake (Name) & "_entry";
            elsif Info.Elem_Name /= Null_Unbounded_String
              and then Ref_Kind (To_String (Info.Elem_Name)) = Struct
            then
               return Zig_Snake (To_String (Info.Elem_Name));
            else
               return "";
            end if;
         end Elem_Fn;

         procedure Visit_Field (Name : String; Buf : in out U; Ind : String) is
            F : constant String := Zig_Field (Name);
         begin
            case Ref_Kind (Name) is
               when Struct =>
                  Append (Buf, Ind & "visit_" & Zig_Snake (Name)
                    & "(&n." & F & ", v);");
                  Append (Buf, LF);
               when List =>
                  declare
                     E : constant String := Elem_Fn (Name);
                  begin
                     if E /= "" then
                        Append (Buf, Ind & "for (n." & F & ") |*e| visit_" & E
                          & "(e, v);");
                        Append (Buf, LF);
                     end if;
                  end;
               when others =>
                  null;
            end case;
         end Visit_Field;

         procedure Fold_Field (Name : String; Buf : in out U; Ind : String) is
            F : constant String := Zig_Field (Name);
         begin
            case Ref_Kind (Name) is
               when Struct =>
                  Append (Buf, Ind & "fold_" & Zig_Snake (Name)
                    & "(&n." & F & ", f);");
                  Append (Buf, LF);
               when List =>
                  declare
                     E : constant String := Elem_Fn (Name);
                  begin
                     if E /= "" then
                        Append (Buf, Ind & "for (n." & F & ") |*e| fold_" & E
                          & "(e, f);");
                        Append (Buf, LF);
                     end if;
                  end;
               when others =>
                  null;
            end case;
         end Fold_Field;

         procedure Emit_Node (Type_Name, Fn : String;
                              Members : Member_Vectors.Vector;
                              Buf : in out U) is
         begin
            Append (Buf, "pub fn visit_" & Fn & "(n: *const " & Type_Name
              & ", v: anytype) void {");
            Append (Buf, LF);
            Append (Buf, "    v.visit_" & Fn & "(n);");
            Append (Buf, LF);
            for M of Members loop
               Visit_Field (To_String (M.Name), Buf, "    ");
            end loop;
            Append (Buf, "}");
            Append (Buf, LF);
            Append (Buf, LF);

            Append (Buf, "pub fn fold_" & Fn & "(n: *" & Type_Name
              & ", f: anytype) void {");
            Append (Buf, LF);
            for M of Members loop
               Fold_Field (To_String (M.Name), Buf, "    ");
            end loop;
            Append (Buf, "    f.fold_" & Fn & "(n);");
            Append (Buf, LF);
            Append (Buf, "}");
            Append (Buf, LF);
         end Emit_Node;

         function Is_Node (Idx : Natural) return Boolean is
            Info : constant Rule_Info := Infos (Idx);
         begin
            return Info.Kind = Struct
              or else (Info.Kind = List and then not Info.Elem_Members.Is_Empty);
         end Is_Node;

         function Node_Type (Idx : Natural) return String is
            Info : constant Rule_Info := Infos (Idx);
            Base : constant String := Zig_Type (To_String (Rules (Idx).Name));
         begin
            if Info.Kind = Struct then
               return Base;
            else
               return Base & "Entry";
            end if;
         end Node_Type;

         function Node_Fn (Idx : Natural) return String is
            Info : constant Rule_Info := Infos (Idx);
            Base : constant String := Zig_Snake (To_String (Rules (Idx).Name));
         begin
            if Info.Kind = Struct then
               return Base;
            else
               return Base & "_entry";
            end if;
         end Node_Fn;

         function Node_Members (Idx : Natural) return Member_Vectors.Vector is
            Info : constant Rule_Info := Infos (Idx);
         begin
            if Info.Kind = Struct then
               return Info.Members;
            else
               return Info.Elem_Members;
            end if;
         end Node_Members;

      begin
         Append (Buf, "// ---- AST traversal (visit) and transform (fold) ----");
         Append (Buf, LF);
         for I in 1 .. N loop
            if Is_Node (I) then
               Emit_Node (Node_Type (I), Node_Fn (I), Node_Members (I), Buf);
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

      Append (Res, "// generated by hbnf -- do not edit");
      Append (Res, LF);
      Append (Res, LF);

      --  Leaves first: scalars and enums carry no ordering constraints.
      for I in 1 .. N loop
         if Infos (I).Kind = Scalar or else Infos (I).Kind = Enum then
            Append (Res, Emit_Rule (I, Infos (I)));
            Append (Res, LF);
            Emitted (I) := True;
         end if;
      end loop;

      --  Structs and lists, in dependency order.  A cycle here means a type
      --  contains another by value, transitively, with no slice to break it.
      for I in 1 .. N loop
         if Is_Type (Infos (I)) then
            Remaining := Remaining + 1;
         end if;
      end loop;
      while Remaining > 0 loop
         declare
            Progress : Boolean := False;
         begin
            for I in 1 .. N loop
               if Is_Type (Infos (I)) and then not Emitted (I) then
                  declare
                     Ready : Boolean := True;
                  begin
                     for D of Deps (I) loop
                        if not Emitted (D) then
                           Ready := False;
                        end if;
                     end loop;
                     if Ready then
                        if Infos (I).Kind = List then
                           Append (Res, Emit_List (I, Infos (I)));
                        else
                           Append (Res, Emit_Rule (I, Infos (I)));
                        end if;
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

   function Emit_Parser (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is

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
        (Scalar_Zig_Type (Name) /= "");

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

      function Zig_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Zig_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         return Zig_Type (Ref);
      end Zig_Type_Of;

      --  The underlying scalar Zig type a rule name resolves to, chasing
      --  single-name aliases and jets to their target.  "" if not scalar.
      function Resolve_Type (N : String; Depth : Natural := 0) return String is
         C : constant String := Scalar_Zig_Type (N);
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
                  return "[]const u8";
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

      --  True when a pattern (or any nested group) names a rule reference.
      function Has_Name (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Name then
               return True;
            elsif E.Kind = Group and then Has_Name (E.Items) then
               return True;
            end if;
         end loop;
         return False;
      end Has_Name;

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

      function Scalar_Kind (Name : String) return String is
      begin
         if Name = "str" then
            return ".str";
         elsif Name = "int" then
            return ".int";
         elsif Name'Length >= 2 then
            declare
               P : constant Character := Name (Name'First);
               R : constant String := Name (Name'First + 1 .. Name'Last);
            begin
               if (P = 'u' or else P = 'i')
                 and then (for all C of R => C in '0' .. '9')
               then
                  return ".int";
               end if;
            end;
         end if;
         return ".atom";
      end Scalar_Kind;

      function Scalar_Parse (Name : String) return String is
      begin
         if Name = "str" or else Name = "atom" or else Name = "word" then
            return "p.toks[p.pos].text";
         elsif Name = "bool" or else Name = "flag" then
            return "(std.mem.eql(u8, p.toks[p.pos].text, ""yes"") or "
              & "std.mem.eql(u8, p.toks[p.pos].text, ""on"") or "
              & "std.mem.eql(u8, p.toks[p.pos].text, ""true""))";
         elsif Name = "int" then
            return "std.fmt.parseInt(i64, p.toks[p.pos].text, 10) catch 0";
         elsif Name'Length >= 2 then
            declare
               P : constant Character := Name (Name'First);
               R : constant String := Name (Name'First + 1 .. Name'Last);
            begin
               if (P = 'u' or else P = 'i')
                 and then (for all C of R => C in '0' .. '9')
               then
                  return "std.fmt.parseInt(" & (if P = 'u' then "u" else "i")
                    & R & ", p.toks[p.pos].text, 10) catch 0";
               end if;
            end;
         end if;
         return "p.toks[p.pos].text";
      end Scalar_Parse;

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

      function Ret_Type (Idx : Natural) return String is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            if P (1).Kind = HBNF_Grammar.Name then
               return "[]" & Zig_Type_Of (To_String (P (1).Name));
            else
               return "[]" & Zig_Type (To_String (R.Name)) & "Entry";
            end if;
         end if;
         return Zig_Type (To_String (R.Name));
      end Ret_Type;

      procedure Emit_Seq
        (Els : Element_Vectors.Vector; First, Last : Natural;
         Dst  : String; Buf : in out U; Fail : String := ""; Ind : String := "    ") is
         Pref : constant String := (if Fail = "" then "try " else "");
         Cat  : constant String := (if Fail = "" then "" else " catch " & Fail);
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               case E.Kind is
                  when Literal =>
                     Append (Buf, Ind & Pref & "p.expect_lit("""
                       & Zig_Escape (To_String (E.Lit)) & """, ""`"
                       & Zig_Escape (To_String (E.Lit)) & "`"")" & Cat & ";");
                     Append (Buf, LF);
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        Append (Buf, Ind & Pref & "p.expect_kind("
                          & Scalar_Kind (To_String (E.Name)) & ", """
                          & Core_Desc (To_String (E.Name)) & """)" & Cat & ";");
                        Append (Buf, LF);
                        Append (Buf, Ind & Dst
                          & Zig_Field (To_String (E.Name)) & " = "
                          & Scalar_Parse (To_String (E.Name)) & "; p.pos += 1;");
                        Append (Buf, LF);
                     else
                        Append (Buf, Ind & Dst
                          & Zig_Field (To_String (E.Name)) & " = "
                          & Pref & "parse_"
                          & Zig_Snake (To_String (E.Name)) & "(p)" & Cat & ";");
                        Append (Buf, LF);
                     end if;
                  when Group =>
                     Emit_Seq (E.Items, 1, Natural (E.Items.Length), Dst, Buf,
                               Fail, Ind & "    ");
                  when Alt =>
                     null;
               end case;
            end;
         end loop;
      end Emit_Seq;

      --  Emit a backtracking alternation over the Alt-separated branches in
      --  Els.  Each branch runs inside a labelled block whose `catch` failures
      --  break out of it; a failed branch restores p.pos and resets the struct
      --  (Reset), a successful one sets `matched` and returns r.  After the
      --  last branch fails, control falls through for the caller's own failure
      --  handling.
      procedure Emit_Alternation
        (Els : Element_Vectors.Vector; Acc, Reset : String;
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
                  Append (Buf, Ind & "p.pos = save; " & Reset & "; matched = false;");
                  Append (Buf, LF);
               end if;
               Append (Buf, Ind & "blk_" & Img (Br) & ": {");
               Append (Buf, LF);
               Emit_Seq (Els, St, K - 1, Acc, Buf,
                         "break :blk_" & Img (Br), Ind & "    ");
               Append (Buf, Ind & "    matched = true;");
               Append (Buf, LF);
               Append (Buf, Ind & "}");
               Append (Buf, LF);
               Append (Buf, Ind & "if (matched) return r;");
               Append (Buf, LF);
               St := K + 1;
            end if;
         end loop;
      end Emit_Alternation;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         ZT : constant String := Zig_Type (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Is_Pure_Literal_Alt (P);
         SU : constant String := (if not Is_List then Scalar_Union_Type (P) else "");
      begin
         if R.Jet_Code /= Null_Unbounded_String then
            --  A jet is a hand-written C scanner; this backend can't run it,
            --  so read the token the generic lexer produced instead.
            Append (Buf, "    try p.expect_kind(.atom, ""a " & NM & """);");
            Append (Buf, LF);
            Append (Buf, "    const r = p.toks[p.pos].text; p.pos += 1;");
            Append (Buf, LF);
            Append (Buf, "    return r;");
            Append (Buf, LF);
            return;
         end if;
         if Is_List then
            declare
               E    : constant Element_Access := P (1);
               Elem : constant String :=
                 (if E.Kind = HBNF_Grammar.Name
                  then Zig_Type_Of (To_String (E.Name))
                  else ZT & "Entry");
            begin
               Append (Buf, "    var list = std.ArrayList(" & Elem
                 & ").empty;");
               Append (Buf, LF);
               if E.Kind = Name then
                  declare
                     SK : constant String := Start_Kind (To_String (E.Name));
                  begin
                     if SK /= "" then
                        Append (Buf, "    while (p.pos < p.toks.len and p.toks[p.pos].kind == "
                          & SK & ") {");
                     else
                        Append (Buf, "    while (p.pos < p.toks.len) {");
                     end if;
                  end;
                  Append (Buf, LF);
                  Append (Buf, "        try list.append(p.alloc, try parse_"
                    & Zig_Snake (To_String (E.Name)) & "(p));");
                  Append (Buf, LF);
                  Append (Buf, "    }");
                  Append (Buf, LF);
               elsif E.Kind = Group then
                  Append (Buf, "    list: while (p.pos < p.toks.len) {");
                  Append (Buf, LF);
                  Append (Buf, "        const save = p.pos;");
                  Append (Buf, LF);
                  Append (Buf, "        var e = std.mem.zeroes(" & Elem & ");");
                  Append (Buf, LF);
                  Append (Buf, "        blk_alt: {");
                  Append (Buf, LF);
                  declare
                     St     : Natural := 1;
                     Branch : Natural := 0;
                  begin
                     for K in 1 .. Natural (E.Items.Length) + 1 loop
                        if K > Natural (E.Items.Length)
                          or else E.Items (K).Kind = Alt
                        then
                           if St <= K - 1 then
                              Branch := Branch + 1;
                              if Branch > 1 then
                                 Append (Buf, "            p.pos = save; e = std.mem.zeroes("
                                   & Elem & ");");
                                 Append (Buf, LF);
                              end if;
                              Append (Buf, "            blk_" & Img (Branch) & ": {");
                              Append (Buf, LF);
                              Emit_Seq (E.Items, St, K - 1, "e.", Buf,
                                        "break :blk_" & Img (Branch),
                                        "                ");
                              Append (Buf, "                break :blk_alt;");
                              Append (Buf, LF);
                              Append (Buf, "            }");
                              Append (Buf, LF);
                           end if;
                           St := K + 1;
                        end if;
                     end loop;
                  end;
                  Append (Buf, "            p.pos = save; break :list;");
                  Append (Buf, LF);
                  Append (Buf, "        }");
                  Append (Buf, LF);
                  Append (Buf, "        try list.append(p.alloc, e);");
                  Append (Buf, LF);
                  Append (Buf, "    }");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    return list.toOwnedSlice(p.alloc);");
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

               Append (Buf, "    try p.expect_kind(.atom, ""a " & ZT & """);");
               Append (Buf, LF);
               Append (Buf, "    var r: " & ZT & " = undefined;");
               Append (Buf, LF);

               St := 1;
               Branch := 0;
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        if Branch = 0 then
                           Append (Buf, "    if (std.mem.eql(u8, p.toks[p.pos].text, """
                             & Zig_Escape (To_String (P (St).Lit)) & """)) {");
                        else
                           Append (Buf, "    } else if (std.mem.eql(u8, p.toks[p.pos].text, """
                             & Zig_Escape (To_String (P (St).Lit)) & """)) {");
                        end if;
                        Append (Buf, LF);
                        Append (Buf, "        r = ." & To_String (Names (Branch + 1)) & ";");
                        Append (Buf, LF);
                        Branch := Branch + 1;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "    } else { try p.fail(""`");
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
                        Append (Buf, "`" & Zig_Escape (To_String (P (St).Lit)) & "`");
                        First := False;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, """); }");
            Append (Buf, LF);
            Append (Buf, "    p.pos += 1;");
            Append (Buf, LF);
            Append (Buf, "    return r;");
            Append (Buf, LF);
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            if Is_Core (To_String (P (1).Name)) then
               Append (Buf, "    try p.expect_kind(" & Scalar_Kind (To_String (P (1).Name))
                 & ", """ & Core_Desc (To_String (P (1).Name)) & """);");
               Append (Buf, LF);
               Append (Buf, "    const r = " & Scalar_Parse (To_String (P (1).Name))
                 & "; p.pos += 1;");
               Append (Buf, LF);
               Append (Buf, "    return r;");
               Append (Buf, LF);
            else
               Append (Buf, "    return try parse_" & Zig_Snake (To_String (P (1).Name))
                 & "(p);");
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
                           if E.Kind = Name and then Is_Core (To_String (E.Name)) then
                              Append (Buf, "    if (p.pos < p.toks.len and p.toks[p.pos].kind == "
                                & Scalar_Kind (To_String (E.Name)) & ") {");
                              Append (Buf, LF);
                              Append (Buf, "        const r = " & Scalar_Parse (To_String (E.Name))
                                & "; p.pos += 1; return r; }");
                              Append (Buf, LF);
                           elsif E.Kind = Name then
                              Append (Buf, "    if (parse_" & Zig_Snake (To_String (E.Name))
                                & "(p)) |r| { return r; } else |_| {}");
                              Append (Buf, LF);
                           end if;
                        end;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "    try p.fail(""a " & NM & """);");
            Append (Buf, LF);
            Append (Buf, "    unreachable;");
            Append (Buf, LF);
         elsif Has_Alt (P) then
            --  A struct alternation: try each branch with backtracking.
            Append (Buf, "    const save = p.pos;");
            Append (Buf, LF);
            Append (Buf, "    var r: " & ZT & " = std.mem.zeroes(" & ZT & ");");
            Append (Buf, LF);
            Append (Buf, "    var matched = false;");
            Append (Buf, LF);
            Emit_Alternation (P, "r.", "r = std.mem.zeroes(" & ZT & ")", Buf);
            Append (Buf, "    p.pos = save;");
            Append (Buf, LF);
            Append (Buf, "    try p.fail(""a " & NM & """);");
            Append (Buf, LF);
            Append (Buf, "    unreachable;");
            Append (Buf, LF);
         else
            if Has_Name (P) then
               Append (Buf, "    var r: " & ZT & " = std.mem.zeroes(" & ZT & ");");
            else
               Append (Buf, "    const r: " & ZT & " = std.mem.zeroes(" & ZT & ");");
            end if;
            Append (Buf, LF);
            Emit_Seq (P, 1, Natural (P.Length), "r.", Buf);
            Append (Buf, "    return r;");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Parser;

      Res : U;
   begin
      Append (Res, "// generated by hbnf -- do not edit");
      Append (Res, LF);
      Append (Res, "const std = @import(""std"");");
      Append (Res, LF);
      Append (Res, LF);
      if Preamble /= "" and then Language = "Zig" then
         Append (Res, Preamble);
         Append (Res, LF);
         Append (Res, LF);
      end if;
      declare
         Enum : U := To_Unbounded_String
           ("pub const Kind = enum { atom, str, int, punct");
      begin
         for I in 1 .. N loop
            if Rules (I).Jet_Code /= Null_Unbounded_String then
               Append (Enum, ", " & Zig_Snake (To_String (Rules (I).Name)));
            end if;
         end loop;
         Append (Enum, ", eof };");
         Append (Res, To_String (Enum));
         Append (Res, LF);
      end;
      Append (Res, "pub const Token = struct { kind: Kind, text: []const u8, line: usize, col: usize };");
      Append (Res, LF);
      Append (Res, "pub const ParseError = error{ Invalid, OutOfMemory };");
      Append (Res, LF);
      Append (Res, "const SPACES = ""                                                                "";");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "const P = struct {");
      Append (Res, LF);
      Append (Res, "    toks: []const Token,");
      Append (Res, LF);
      Append (Res, "    lines: []const []const u8,");
      Append (Res, LF);
      Append (Res, "    alloc: std.mem.Allocator,");
      Append (Res, LF);
      Append (Res, "    pos: usize = 0,");
      Append (Res, LF);
      Append (Res, "    err_line: usize = 0,");
      Append (Res, LF);
      Append (Res, "    err_col: usize = 0,");
      Append (Res, LF);
      Append (Res, "    err: [512]u8 = undefined,");
      Append (Res, LF);
      Append (Res, "    err_len: usize = 0,");
      Append (Res, LF);
      Append (Res, "    err_pos: usize = 0,");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "    fn set_err(self: *P, expected: []const u8) void {");
      Append (Res, LF);
      Append (Res, "        if (self.err_len != 0 and self.pos <= self.err_pos) return;");
      Append (Res, LF);
      Append (Res, "        self.err_pos = self.pos;");
      Append (Res, LF);
      Append (Res, "        const tok = if (self.pos < self.toks.len) self.toks[self.pos] else self.toks[self.toks.len - 1];");
      Append (Res, LF);
      Append (Res, "        self.err_line = tok.line;");
      Append (Res, LF);
      Append (Res, "        self.err_col = tok.col;");
      Append (Res, LF);
      Append (Res, "        const found = if (self.pos < self.toks.len) self.toks[self.pos].text else ""end of input"";");
      Append (Res, LF);
      Append (Res, "        const msg = if (self.err_line >= 1 and self.err_line <= self.lines.len) blk: {");
      Append (Res, LF);
      Append (Res, "            const l = self.lines[self.err_line - 1];");
      Append (Res, LF);
      Append (Res, "            const w0 = if (self.err_col > 1) self.err_col - 1 else 0;");
      Append (Res, LF);
      Append (Res, "            const w = if (w0 > SPACES.len) SPACES.len else w0;");
      Append (Res, LF);
      Append (Res, "            break :blk std.fmt.bufPrint(self.err[0..], ""expected {s}, found {s}\n  {s}\n  {s}^"", .{ expected, found, l, SPACES[0..w] });");
      Append (Res, LF);
      Append (Res, "        } else std.fmt.bufPrint(self.err[0..], ""expected {s}, found {s}"", .{ expected, found });");
      Append (Res, LF);
      Append (Res, "        const m = msg catch { self.err_len = self.err.len; return; };");
      Append (Res, LF);
      Append (Res, "        self.err_len = m.len;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "    fn fail(self: *P, expected: []const u8) ParseError!void {");
      Append (Res, LF);
      Append (Res, "        self.set_err(expected);");
      Append (Res, LF);
      Append (Res, "        return error.Invalid;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "    fn expect_lit(self: *P, lit: []const u8, want: []const u8) ParseError!void {");
      Append (Res, LF);
      Append (Res, "        if (self.pos < self.toks.len and (self.toks[self.pos].kind == .atom or self.toks[self.pos].kind == .punct)");
      Append (Res, LF);
      Append (Res, "            and std.mem.eql(u8, self.toks[self.pos].text, lit)) { self.pos += 1; return; }");
      Append (Res, LF);
      Append (Res, "        return self.fail(want);");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "    fn expect_kind(self: *P, k: Kind, desc: []const u8) ParseError!void {");
      Append (Res, LF);
      Append (Res, "        if (self.pos < self.toks.len and self.toks[self.pos].kind == k) return;");
      Append (Res, LF);
      Append (Res, "        return self.fail(desc);");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "    fn err_out(self: *P, out: *[512]u8, line: *usize, col: *usize) ParseError {");
      Append (Res, LF);
      Append (Res, "        @memcpy(out[0..self.err_len], self.err[0..self.err_len]);");
      Append (Res, LF);
      Append (Res, "        out[self.err_len] = 0;");
      Append (Res, LF);
      Append (Res, "        line.* = self.err_line;");
      Append (Res, LF);
      Append (Res, "        col.* = self.err_col;");
      Append (Res, LF);
      Append (Res, "        return error.Invalid;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "};");
      Append (Res, LF);
      Append (Res, LF);

      for I in 1 .. N loop
         Append (Res, "fn parse_" & Zig_Snake (To_String (Rules (I).Name))
           & "(p: *P) ParseError!" & Ret_Type (I) & " {");
         Append (Res, LF);
         Emit_Rule_Parser (I, Res);
         Append (Res, "}");
         Append (Res, LF);
         Append (Res, LF);
      end loop;

      Append (Res, "pub fn parse_tokens(alloc: std.mem.Allocator, toks: []const Token,");
      Append (Res, LF);
      Append (Res, "                    lines: []const []const u8,");
      Append (Res, LF);
      Append (Res, "                    err: *[512]u8, err_line: *usize, err_col: *usize) ParseError!"
        & Ret_Type (1) & " {");
      Append (Res, LF);
      Append (Res, "    var p = P{ .toks = toks, .lines = lines, .alloc = alloc };");
      Append (Res, LF);
      Append (Res, "    const out = parse_" & Zig_Snake (To_String (Rules (1).Name))
        & "(&p) catch return p.err_out(err, err_line, err_col);");
      Append (Res, LF);
      Append (Res, "    if (p.pos < p.toks.len and p.toks[p.pos].kind != .eof) { p.set_err(""end of config""); return p.err_out(err, err_line, err_col); }");
      Append (Res, LF);
      Append (Res, "    return out;");
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
               Append (Res, "fn jet_" & Zig_Snake (NM)
                 & "(_: []const u8, _: usize, _: usize) usize {");
               Append (Res, LF);
               Append (Res, "    return 0;");
               Append (Res, LF);
               Append (Res, "}");
               Append (Res, LF);
               Append (Res, LF);
            end;
         end if;
      end loop;

      Append (Res, "fn jet_dispatch(s: []const u8, pos: usize, len: usize,"
        & " kind: *Kind) usize {");
      Append (Res, LF);
      declare
         Has_Jet : Boolean := False;
      begin
         for I in 1 .. N loop
            if Rules (I).Jet_Code /= Null_Unbounded_String then
               Has_Jet := True;
               exit;
            end if;
         end loop;
         if not Has_Jet then
            Append (Res, "    _ = s; _ = pos; _ = len; _ = kind;");
            Append (Res, LF);
         end if;
      end;
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               NM : constant String := To_String (Rules (I).Name);
            begin
               Append (Res, "    { const n = jet_" & Zig_Snake (NM)
                 & "(s, pos, len); if (n > 0) { kind.* = ." & Zig_Snake (NM)
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

   function Emit_Lexer (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      R  : constant HBNF_Grammar.Rule := Rules (1);
      P  : constant HBNF_Grammar.Element_Vectors.Vector := R.Pattern;
      Root_T : constant String :=
        (if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            (if P (1).Kind = HBNF_Grammar.Name then
               "[]" & (if Scalar_Zig_Type (To_String (P (1).Name)) /= "" then
                         Scalar_Zig_Type (To_String (P (1).Name))
                       else Zig_Type (To_String (P (1).Name)))
             else "[]" & Zig_Type (To_String (R.Name)) & "Entry")
         else Zig_Type (To_String (R.Name)));
      Lexer  : constant String :=
        Templates.Substitute (Templates.Zig_Lexer, "@ROOT_TYPE@", Root_T);
   begin
      if Epilogue = "" then
         return Lexer;
      else
         return Lexer & LF & Epilogue;
      end if;
   end Emit_Lexer;

   function Emit_Conf (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      Root_T : constant String := Zig_Type (To_String (Rules (1).Name));
   begin
      return Templates.Substitute (Templates.Conf_Zig, "@ROOT_TYPE@", Root_T);
   end Emit_Conf;

end HBNF_Zig;
