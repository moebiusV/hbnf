pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package body ASTBNF_Zig is

   use Ada.Strings.Unbounded;
   use ASTBNF;

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
            if Members.Is_Empty then
               return (Kind => Enum, Literals => Lits);
            else
               return (Kind => Struct, Members => Members);
            end if;
         end;
      end Analyze;

      --  Structs and lists both name types that must precede any rule that
      --  refers to them (Zig has no forward declarations).
      function Is_Type (Info : Rule_Info) return Boolean is
        (Info.Kind = Struct or else Info.Kind = List);

      Infos : Info_Vectors.Vector;

      --  The rule indices this rule must be emitted after.  Unlike C, a list
      --  member (`[]T` slice) also needs its element defined first.
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
      begin
         declare
            Info : constant Rule_Info := Infos (Idx);
         begin
            case Info.Kind is
               when Struct =>
                  for M of Info.Members loop
                     declare
                        J : constant Natural := Find (To_String (M.Name));
                     begin
                        if J > 0 and then Is_Type (Infos (J)) then
                           Add (J);
                        end if;
                     end;
                  end loop;
               when List =>
                  if Info.Elem_Name /= Null_Unbounded_String then
                     declare
                        J : constant Natural :=
                          Find (To_String (Info.Elem_Name));
                     begin
                        if J > 0 and then Is_Type (Infos (J)) then
                           Add (J);
                        end if;
                     end;
                  end if;
                  for M of Info.Elem_Members loop
                     declare
                        J : constant Natural := Find (To_String (M.Name));
                     begin
                        if J > 0 and then Is_Type (Infos (J)) then
                           Add (J);
                        end if;
                     end;
                  end loop;
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
            Append (Buf, "// " & To_String (R.Leading_Comment));
            Append (Buf, LF);
         end if;

         case Info.Kind is
            when Scalar =>
               Append (Buf, "pub const " & Base & " = " &
                       To_String (Info.Inline_Type) & ";");
               Append (Buf, LF);
            when Enum =>
               Append (Buf, "pub const " & Base & " = enum {");
               Append (Buf, LF);
               for I in 1 .. Natural (Info.Literals.Length) loop
                  Append (Buf, "    " &
                          Zig_Field (To_String (Info.Literals (I))) & ",");
                  Append (Buf, LF);
               end loop;
               Append (Buf, "};");
               Append (Buf, LF);
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
            Append (Buf, "// " & To_String (R.Leading_Comment));
            Append (Buf, LF);
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

      Emitted   : array (1 .. N) of Boolean := [others => False];
      Remaining : Natural := 0;
      Res       : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (I));
      end loop;

      Append (Res, "// generated by astbnf -- do not edit");
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

      return To_String (Res);
   end Emit;

   function Emit_Parser (Rules : ASTBNF.Rule_Vectors.Vector) return String is

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

      function Has_Name (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Name then
               return True;
            end if;
         end loop;
         return False;
      end Has_Name;

      function Zig_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Zig_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         return Zig_Type (Ref);
      end Zig_Type_Of;

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
         elsif Name = "dec" or else Name = "float" then
            return ".dec";
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
         elsif Name = "dec" then
            return "std.fmt.parseFloat(f64, p.toks[p.pos].text) catch 0.0";
         elsif Name = "float" then
            return "std.fmt.parseFloat(f32, p.toks[p.pos].text) catch 0.0";
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
            if Natural (P.Length) = 1 and then P (1).Kind = ASTBNF.Name
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
            if P (1).Kind = ASTBNF.Name then
               return "[]" & Zig_Type_Of (To_String (P (1).Name));
            else
               return "[]" & Zig_Type (To_String (R.Name)) & "Entry";
            end if;
         end if;
         return Zig_Type (To_String (R.Name));
      end Ret_Type;

      procedure Emit_Seq
        (Els : Element_Vectors.Vector; First, Last : Natural;
         Dst : String; Buf : in out U; Ind : String := "    ") is
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               case E.Kind is
                  when Literal =>
                     Append (Buf, Ind & "try p.expect_lit("""
                       & To_String (E.Lit) & """, ""`"
                       & To_String (E.Lit) & "`"");");
                     Append (Buf, LF);
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        Append (Buf, Ind & "try p.expect_kind("
                          & Scalar_Kind (To_String (E.Name)) & ", """
                          & Core_Desc (To_String (E.Name)) & """);");
                        Append (Buf, LF);
                        Append (Buf, Ind & Dst
                          & Zig_Field (To_String (E.Name)) & " = "
                          & Scalar_Parse (To_String (E.Name)) & "; p.pos += 1;");
                        Append (Buf, LF);
                     else
                        Append (Buf, Ind & Dst
                          & Zig_Field (To_String (E.Name)) & " = try parse_"
                          & Zig_Snake (To_String (E.Name)) & "(p);");
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

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         ZT : constant String := Zig_Type (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Has_Alt (P)
           and then not Has_Name (P);
      begin
         if Is_List then
            declare
               E    : constant Element_Access := P (1);
               Elem : constant String :=
                 (if E.Kind = ASTBNF.Name
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
                     Append (Buf, "    while (p.pos < p.toks.len and p.toks[p.pos].kind == .atom and (");
                     for I in 1 .. Natural (Firsts.Length) loop
                        if I > 1 then
                           Append (Buf, " or ");
                        end if;
                        Append (Buf, "std.mem.eql(u8, p.toks[p.pos].text, """
                          & To_String (Firsts (I)) & """)");
                     end loop;
                     Append (Buf, ")) {");
                     Append (Buf, LF);
                     Append (Buf, "        var e = std.mem.zeroes(" & Elem & ");");
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
                                    Append (Buf, "        if (std.mem.eql(u8, p.toks[p.pos].text, """
                                      & To_String (E.Items (St).Lit) & """)) {");
                                 else
                                    Append (Buf, "        } else if (std.mem.eql(u8, p.toks[p.pos].text, """
                                      & To_String (E.Items (St).Lit) & """)) {");
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
                     Append (Buf, "        try list.append(p.alloc, e);");
                     Append (Buf, LF);
                     Append (Buf, "    }");
                     Append (Buf, LF);
                  end;
               end if;
               Append (Buf, "    return list.toOwnedSlice(p.alloc);");
               Append (Buf, LF);
            end;
         elsif Is_Enum then
            Append (Buf, "    try p.expect_kind(.atom, ""a " & ZT & """);");
            Append (Buf, LF);
            Append (Buf, "    var r: " & ZT & " = undefined;");
            Append (Buf, LF);
            declare
               St     : Natural := 1;
               Branch : Natural := 0;
            begin
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        if Branch = 0 then
                           Append (Buf, "    if (std.mem.eql(u8, p.toks[p.pos].text, """
                             & To_String (P (St).Lit) & """)) {");
                        else
                           Append (Buf, "    } else if (std.mem.eql(u8, p.toks[p.pos].text, """
                             & To_String (P (St).Lit) & """)) {");
                        end if;
                        Append (Buf, LF);
                        Append (Buf, "        r = ." & Zig_Field (To_String (P (St).Lit)) & ";");
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
                        Append (Buf, "`" & To_String (P (St).Lit) & "`");
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
         else
            Append (Buf, "    var r: " & ZT & " = std.mem.zeroes(" & ZT & ");");
            Append (Buf, LF);
            Emit_Seq (P, 1, Natural (P.Length), "r.", Buf);
            Append (Buf, "    return r;");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Parser;

      Res : U;
   begin
      Append (Res, "// generated by astbnf -- do not edit");
      Append (Res, LF);
      Append (Res, "const std = @import(""std"");");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "pub const Kind = enum { atom, str, int, dec, punct, eof };");
      Append (Res, LF);
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
      Append (Res, LF);
      Append (Res, "    fn set_err(self: *P, expected: []const u8) void {");
      Append (Res, LF);
      Append (Res, "        if (self.err_len != 0) return;");
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

      Append (Res, "pub fn parse_config(alloc: std.mem.Allocator, toks: []const Token,");
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

      return To_String (Res);
   end Emit_Parser;

end ASTBNF_Zig;
