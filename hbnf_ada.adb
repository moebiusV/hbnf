pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Templates;

package body HBNF_Ada is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

   subtype U is Unbounded_String;

   LF : constant Character := ASCII.LF;

   package String_Vectors is new Ada.Containers.Vectors (Positive, U);
   package Natural_Vectors is new Ada.Containers.Vectors (Positive, Natural);

   --  The Ada type for a built-in core rule, or "" if not a core scalar.
   function Scalar_Ada_Type (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "Unbounded_String";
      elsif Name = "int" then
         return "Long_Long_Integer";
      elsif Name = "bool" or else Name = "flag" then
         return "Boolean";
      elsif Name'Length >= 2 then
         declare
            P : constant Character := Name (Name'First);
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            if (P = 'u' or else P = 'i')
              and then (for all C of R => C in '0' .. '9')
            then
               return (if P = 'u' then "Unsigned_" else "Integer_") & R;
            end if;
         end;
      end if;
      return "";
   end Scalar_Ada_Type;

   --  A valid Ada identifier from a schema name: capitalize the first letter
   --  (which also clears every lowercase reserved word) and turn '-' into '_'.
   function Ada_Ident (S : String) return String is
      Buf   : U;
      First : Boolean := True;
   begin
      for C of S loop
         if C = '-' then
            Append (Buf, '_');
         elsif First and then C in 'a' .. 'z' then
            Append (Buf, Character'Val (Character'Pos (C) - 32));
         else
            Append (Buf, C);
         end if;
         First := False;
      end loop;
      return To_String (Buf);
   end Ada_Ident;

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
   --  through Ada_Ident and then any non-alphanumeric folded to '_', so
   --  "tlsv1.0" -> "Tlsv1_0".  A name that is empty, all '_', or begins with
   --  a digit (pure punctuation like "*" or "!=") becomes `Op_<pos>`; and
   --  collisions — Ada identifiers are case-insensitive, so "dot"/"DoT" clash
   --  — are deduped with _2, _3, ...
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

      function Up (S : String) return String is
         Buf : U;
      begin
         for C of S loop
            if C in 'a' .. 'z' then
               Append (Buf, Character'Val (Character'Pos (C) - 32));
            else
               Append (Buf, C);
            end if;
         end loop;
         return To_String (Buf);
      end Up;

      function Used (S : String) return Boolean is
      begin
         for X of Names loop
            if Up (To_String (X)) = Up (S) then
               return True;
            end if;
         end loop;
         return False;
      end Used;
   begin
      for I in 1 .. Natural (Lits.Length) loop
         declare
            Base : constant String := Fold (Ada_Ident (To_String (Lits (I))));
            N    : U;
         begin
            if Base = "" or else (for all C of Base => C = '_')
              or else Base (Base'First) in '0' .. '9'
            then
               N := To_Unbounded_String ("Op_" & Img (I));
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

   function Emit (Rules : Rule_Vectors.Vector; Package_Name : String)
     return String
   is

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

      --  The Ada type a rule reference denotes: a core scalar inlines; any
      --  other reference resolves to the referenced rule's own type name.
      function Ada_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Ada_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         if Find (Ref) = 0 then
            raise Parse_Error with "undefined rule: " & Ref;
         end if;
         return Ada_Ident (Ref) & "_Type";
      end Ada_Type_Of;

      --  A record component name: Ada_Ident, with a "_F" suffix if the bare
      --  identifier is an Ada reserved word (e.g. the rule `entry`).
      function Ada_Field (S : String) return String is
         N : constant String := Ada_Ident (S);
         Reserved : constant Boolean :=
           N = "Abort" or else N = "Abs" or else N = "Abstract"
           or else N = "Accept" or else N = "Access" or else N = "Aliased"
           or else N = "All" or else N = "And" or else N = "Array"
           or else N = "At" or else N = "Begin" or else N = "Body"
           or else N = "Case" or else N = "Constant" or else N = "Declare"
           or else N = "Delay" or else N = "Delta" or else N = "Digits"
           or else N = "Do" or else N = "Else" or else N = "Elsif"
           or else N = "End" or else N = "Entry" or else N = "Exception"
           or else N = "Exit" or else N = "For" or else N = "Function"
           or else N = "Generic" or else N = "Goto" or else N = "If"
           or else N = "In" or else N = "Interface" or else N = "Is"
           or else N = "Limited" or else N = "Loop" or else N = "Mod"
           or else N = "New" or else N = "Not" or else N = "Null"
           or else N = "Of" or else N = "Or" or else N = "Others"
           or else N = "Out" or else N = "Overriding" or else N = "Package"
           or else N = "Pragma" or else N = "Private" or else N = "Procedure"
           or else N = "Protected" or else N = "Raise" or else N = "Range"
           or else N = "Record" or else N = "Rem" or else N = "Renames"
           or else N = "Requeue" or else N = "Return" or else N = "Reverse"
           or else N = "Select" or else N = "Separate" or else N = "Some"
           or else N = "Subtype" or else N = "Synchronized"
           or else N = "Tagged" or else N = "Task" or else N = "Terminate"
           or else N = "Then" or else N = "Type" or else N = "Until"
           or else N = "Use" or else N = "When" or else N = "While"
           or else N = "With" or else N = "Xor";
      begin
         if Reserved then
            return N & "_F";
         end if;
         return N;
      end Ada_Field;

      --  Append Text as an Ada comment block, one "-- " per line (a leading
      --  comment may span several schema lines).
      procedure Append_Comment (B : in out U; Text : String) is
         Line_Start : Natural := Text'First;
      begin
         if Text'Length = 0 then
            return;
         end if;
         for K in Text'Range loop
            if Text (K) = ASCII.LF then
               Append (B, "   -- " & Text (Line_Start .. K - 1) & LF);
               Line_Start := K + 1;
            end if;
         end loop;
         Append (B, "   -- " & Text (Line_Start .. Text'Last));
      end Append_Comment;

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
            return (Kind        => Scalar,
                    Inline_Type => To_Unbounded_String ("Unbounded_String"));
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
                              (Ada_Type_Of (To_String (E.Name))));
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
                          Inline_Type => To_Unbounded_String
                            ("Unbounded_String"));
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
               return (Kind => Struct, Members => Members);
            end if;
         end;
      end Analyze;

      function Is_Record (Info : Rule_Info) return Boolean is
        (Info.Kind = Struct);

      Infos : Info_Vectors.Vector;

      --  The record rule indices this struct rule must be emitted after: its
      --  non-list members that reference another record type (a by-value
      --  member needs that type complete first).
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
                  if J > 0 and then Is_Record (Infos (J)) then
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

      --  The vector element type for a list of Ref: an access to the record
      --  (so recursion can be broken), or the scalar inlined by value.
      function Elem_Type (Ref : String) return String is
         S : constant String := Scalar_Ada_Type (Ref);
         J : constant Natural := Find (Ref);
      begin
         if S /= "" then
            return S;                           -- a core scalar
         elsif J > 0 and then Is_Record (Infos (J)) then
            return Ada_Ident (Ref) & "_Access"; -- a record: access breaks it
         else
            return Ada_Type_Of (Ref);           -- a scalar/enum/list rule
         end if;
      end Elem_Type;

      --  A vector package instantiation.
      function Emit_Vector (Name, Elem : String) return String is
         B : U;
      begin
         Append (B, "   package " & Name & " is new Ada.Containers.Vectors");
         Append (B, LF);
         Append (B, "     (Positive, " & Elem & ");");
         Append (B, LF);
         return To_String (B);
      end Emit_Vector;

      --  A scalar, enum or record declaration, carrying the rule's comments.
      function Emit_Rule (Idx : Natural; Info : Rule_Info) return String is
         R    : constant Rule := Rules (Idx);
         Base : constant String := Ada_Ident (To_String (R.Name));
         TN   : constant String := Base & "_Type";
         Buf  : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append_Comment (Buf, To_String (R.Leading_Comment));
            Append (Buf, LF);
         end if;

         case Info.Kind is
            when Scalar =>
               Append (Buf, "   subtype " & TN & " is " &
                       To_String (Info.Inline_Type) & ";");
               Append (Buf, LF);
            when Enum =>
               declare
                  Names : constant String_Vectors.Vector := Enum_Names (Info.Literals);
               begin
                  Append (Buf, "   type " & TN & " is (");
                  for I in 1 .. Natural (Info.Literals.Length) loop
                     if I > 1 then
                        Append (Buf, ", ");
                     end if;
                     Append (Buf, Base & "_" & To_String (Names (I)));
                  end loop;
                  Append (Buf, ");");
                  Append (Buf, LF);
               end;
            when Struct =>
               Append (Buf, "   type " & TN & " is record");
               Append (Buf, LF);
               for M of Info.Members loop
                  if M.Is_List then
                     Append (Buf, "      " & Ada_Field (To_String (M.Name)) &
                             " : " & Base & "_" &
                             Ada_Ident (To_String (M.Name)) &
                             "_Vectors.Vector;");
                  else
                     Append (Buf, "      " & Ada_Field (To_String (M.Name)) &
                             " : " & Ada_Type_Of (To_String (M.Name)) & ";");
                  end if;
                  Append (Buf, LF);
               end loop;
               Append (Buf, "   end record;");
               Append (Buf, LF);
            when List =>
               null;  --  handled by Emit_List
         end case;

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " -- " & To_String (R.Trailing_Comment));
            Append (Buf, LF);
         end if;
         return To_String (Buf);
      end Emit_Rule;

      --  A top-level list rule: the vector package plus a subtype, carrying
      --  the rule's comments.  A group element becomes a named record first.
      function Emit_List (Idx : Natural; Info : Rule_Info) return String is
         R    : constant Rule := Rules (Idx);
         Base : constant String := Ada_Ident (To_String (R.Name));
         TN   : constant String := Base & "_Type";
         Buf  : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append_Comment (Buf, To_String (R.Leading_Comment));
            Append (Buf, LF);
         end if;

         if Info.Elem_Members.Is_Empty then
            if Info.Elem_Name = Null_Unbounded_String then
               --  A repeated literal: degenerate, treat as a string list.
               Append (Buf, Emit_Vector (Base & "_Vectors",
                                         "Unbounded_String"));
            else
               Append (Buf, Emit_Vector
                 (Base & "_Vectors", Elem_Type (To_String (Info.Elem_Name))));
            end if;
         else
            --  A group element: emit a named entry record (value members).
            Append (Buf, "   type " & Base & "_Entry is record");
            Append (Buf, LF);
            for M of Info.Elem_Members loop
               Append (Buf, "      " & Ada_Field (To_String (M.Name)) &
                       " : " & Ada_Type_Of (To_String (M.Name)) & ";");
               Append (Buf, LF);
            end loop;
            Append (Buf, "   end record;");
            Append (Buf, LF);
            Append (Buf, Emit_Vector (Base & "_Vectors", Base & "_Entry"));
         end if;
         Append (Buf, "   subtype " & TN & " is " & Base & "_Vectors.Vector;");
         Append (Buf, LF);

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " -- " & To_String (R.Trailing_Comment));
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

      Append (Res, "--  generated by hbnf -- do not edit");
      Append (Res, LF);
      Append (Res, "with Ada.Containers.Vectors;");
      Append (Res, LF);
      Append (Res, "with Ada.Strings.Unbounded;");
      Append (Res, LF);
      Append (Res, "with Interfaces;");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "package " & Package_Name & " is");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "   use Ada.Strings.Unbounded;");
      Append (Res, LF);
      Append (Res, "   use Interfaces;");
      Append (Res, LF);
      Append (Res, LF);

      --  Leaves: scalar subtypes and enumerations, in dependency order — a
      --  scalar alias referencing another rule's type (e.g. `addr = ipv4`)
      --  must follow it.
      declare
         function Scalar_Ref (Idx : Natural) return Natural is
            R : constant Rule := Rules (Idx);
            P : constant Element_Vectors.Vector := R.Pattern;
         begin
            if Natural (P.Length) = 1 and then P (1).Kind = Name
              and then Scalar_Ada_Type (To_String (P (1).Name)) = ""
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

      --  Incomplete declarations for every record type, then an access type
      --  for each, so records may refer to one another through access.
      for I in 1 .. N loop
         if Is_Record (Infos (I)) then
            Append (Res, "   type " & Ada_Ident (To_String (Rules (I).Name)) &
                    "_Type;");
            Append (Res, LF);
         end if;
      end loop;
      Append (Res, LF);
      for I in 1 .. N loop
         if Is_Record (Infos (I)) then
            Append (Res, "   type " & Ada_Ident (To_String (Rules (I).Name)) &
                    "_Access is access " &
                    Ada_Ident (To_String (Rules (I).Name)) & "_Type;");
            Append (Res, LF);
         end if;
      end loop;
      Append (Res, LF);

      --  Vector packages: one per top-level list rule, and one per repeated
      --  member of a record rule.
      for I in 1 .. N loop
         if Infos (I).Kind = List then
            Append (Res, Emit_List (I, Infos (I)));
            Append (Res, LF);
            Emitted (I) := True;
         elsif Infos (I).Kind = Struct then
            declare
               Members : constant Member_Vectors.Vector := Infos (I).Members;
            begin
               for M of Members loop
                  if M.Is_List then
                     Append (Res, Emit_Vector
                       (Ada_Ident (To_String (Rules (I).Name)) & "_" &
                        Ada_Ident (To_String (M.Name)) & "_Vectors",
                        Elem_Type (To_String (M.Name))));
                     Append (Res, LF);
                  end if;
               end loop;
            end;
         end if;
      end loop;

      --  Record bodies, in by-value dependency order.  A cycle here means a
      --  record contains another by value, transitively, with no list to
      --  break it — infinite size.
      for I in 1 .. N loop
         if Is_Record (Infos (I)) then
            Remaining := Remaining + 1;
         end if;
      end loop;
      while Remaining > 0 loop
         declare
            Progress : Boolean := False;
         begin
            for I in 1 .. N loop
               if Is_Record (Infos (I)) and then not Emitted (I) then
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

      Append (Res, "end " & Package_Name & ";");
      Append (Res, LF);
      return To_String (Res);
   end Emit;

   function Emit_Parser
     (Rules : HBNF_Grammar.Rule_Vectors.Vector; Package_Name : String;
      Conf  : Boolean := False) return String
   is

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
        (Scalar_Ada_Type (Name) /= "");

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

      function Ada_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Ada_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         return Ada_Ident (Ref) & "_Type";
      end Ada_Type_Of;

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
            return "Str";
         elsif Name = "int" then
            return "Int";
         elsif Name'Length >= 2 then
            declare
               P : constant Character := Name (Name'First);
               R : constant String := Name (Name'First + 1 .. Name'Last);
            begin
               if (P = 'u' or else P = 'i')
                 and then (for all C of R => C in '0' .. '9')
               then
                  return "Int";
               end if;
            end;
         end if;
         return "Atom";
      end Scalar_Kind;

      function Scalar_Parse (Name : String) return String is
      begin
         if Name = "str" or else Name = "atom" or else Name = "word" then
            return "P.Toks (P.Pos).Text";
         elsif Name = "int" then
            return "Long_Long_Integer'Value (To_String (P.Toks (P.Pos).Text))";
         elsif Name = "bool" or else Name = "flag" then
            return "To_String (P.Toks (P.Pos).Text) = ""yes"" or "
              & "To_String (P.Toks (P.Pos).Text) = ""on"" or "
              & "To_String (P.Toks (P.Pos).Text) = ""true""";
         elsif Name'Length >= 2 then
            declare
               P : constant Character := Name (Name'First);
               R : constant String := Name (Name'First + 1 .. Name'Last);
            begin
               if (P = 'u' or else P = 'i')
                 and then (for all C of R => C in '0' .. '9')
               then
                  return (if P = 'u' then "Unsigned_" else "Integer_") & R
                    & "'Value (To_String (P.Toks (P.Pos).Text))";
               end if;
            end;
         end if;
         return "P.Toks (P.Pos).Text";
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
        (Ada_Ident (To_String (Rules (Idx).Name)) & "_Type");

      procedure Emit_Seq
        (Els : Element_Vectors.Vector; First, Last : Natural;
         Dst : String; Buf : in out U; Ind : String := "      ") is
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               case E.Kind is
                  when Literal =>
                     Append (Buf, Ind & "Expect_Lit (P, """
                       & To_String (E.Lit) & """);");
                     Append (Buf, LF);
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        Append (Buf, Ind & "Expect_Kind (P, "
                          & Scalar_Kind (To_String (E.Name)) & ", """
                          & Core_Desc (To_String (E.Name)) & """);");
                        Append (Buf, LF);
                        Append (Buf, Ind & Dst
                          & Ada_Ident (To_String (E.Name)) & " := "
                          & Scalar_Parse (To_String (E.Name)) & "; P.Pos := P.Pos + 1;");
                        Append (Buf, LF);
                     else
                        Append (Buf, Ind & Dst
                          & Ada_Ident (To_String (E.Name)) & " := Parse_"
                          & Ada_Ident (To_String (E.Name)) & " (P);");
                        Append (Buf, LF);
                     end if;
                  when Group =>
                     Emit_Seq (E.Items, 1, Natural (E.Items.Length), Dst, Buf,
                               Ind & "   ");
                  when Alt =>
                     null;
               end case;
            end;
         end loop;
      end Emit_Seq;

      procedure Emit_Rule_Decl (Idx : Natural; Buf : in out U) is
         R        : constant Rule := Rules (Idx);
         P        : constant Element_Vectors.Vector := R.Pattern;
         TN       : constant String := Ada_Ident (To_String (R.Name)) & "_Type";
         Delegate : constant Boolean :=
           Natural (P.Length) = 1 and then P (1).Kind = HBNF_Grammar.Name
             and then P (1).Min = 1 and then P (1).Max = 1
             and then not Is_Core (To_String (P (1).Name));
      begin
         if not Delegate then
            Append (Buf, "   R : " & TN & ";");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Decl;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         TN : constant String := Ada_Ident (NM) & "_Type";
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Is_Pure_Literal_Alt (P);
      begin
         if R.Jet_Code /= Null_Unbounded_String then
            Append (Buf, "      Expect_Kind (P, " & Ada_Ident (NM)
              & ", ""a " & NM & """);");
            Append (Buf, LF);
            Append (Buf, "      R := P.Toks (P.Pos).Text; P.Pos := P.Pos + 1;");
            Append (Buf, LF);
            Append (Buf, "      return R;");
            Append (Buf, LF);
            return;
         end if;
         if Is_List then
            declare
               E    : constant Element_Access := P (1);
               Elem : constant String :=
                 (if E.Kind = HBNF_Grammar.Name
                  then Ada_Type_Of (To_String (E.Name))
                  else Ada_Ident (NM) & "_Entry");
            begin
               if E.Kind = Name then
                  declare
                     SK : constant String := Start_Kind (To_String (E.Name));
                  begin
                     if SK /= "" then
                        Append (Buf, "      while P.Pos <= Natural (P.Toks.Length) and then P.Toks (P.Pos).Kind = "
                          & SK & " loop");
                     else
                        Append (Buf, "      while P.Pos <= Natural (P.Toks.Length) loop");
                     end if;
                  end;
                  Append (Buf, LF);
                  Append (Buf, "         R.Append (Parse_"
                    & Ada_Ident (To_String (E.Name)) & " (P));");
                  Append (Buf, LF);
                  Append (Buf, "      end loop;");
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
                     Append (Buf, "      while P.Pos <= Natural (P.Toks.Length) and then P.Toks (P.Pos).Kind = Atom");
                     Append (Buf, LF);
                     Append (Buf, "        and then (");
                     for I in 1 .. Natural (Firsts.Length) loop
                        if I > 1 then
                           Append (Buf, " or else ");
                        end if;
                        Append (Buf, "To_String (P.Toks (P.Pos).Text) = """
                          & To_String (Firsts (I)) & """");
                     end loop;
                     Append (Buf, ") loop");
                     Append (Buf, LF);
                     Append (Buf, "         declare");
                     Append (Buf, LF);
                     Append (Buf, "            E : " & Elem & ";");
                     Append (Buf, LF);
                     Append (Buf, "         begin");
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
                                    Append (Buf, "            if To_String (P.Toks (P.Pos).Text) = """
                                      & To_String (E.Items (St).Lit) & """ then");
                                 else
                                    Append (Buf, "            elsif To_String (P.Toks (P.Pos).Text) = """
                                      & To_String (E.Items (St).Lit) & """ then");
                                 end if;
                                 Append (Buf, LF);
                                 Append (Buf, "               P.Pos := P.Pos + 1;");
                                 Append (Buf, LF);
                                 Emit_Seq (E.Items, St + 1, K - 1, "E.", Buf,
                                           "               ");
                                 Branch := Branch + 1;
                              end if;
                              St := K + 1;
                           end if;
                        end loop;
                     end;
                     Append (Buf, "            end if;");
                     Append (Buf, LF);
                     Append (Buf, "            R.Append (E);");
                     Append (Buf, LF);
                     Append (Buf, "         end;");
                     Append (Buf, LF);
                     Append (Buf, "      end loop;");
                     Append (Buf, LF);
                  end;
               end if;
               Append (Buf, "      return R;");
               Append (Buf, LF);
            end;
         elsif Is_Enum then
            Append (Buf, "      Expect_Kind (P, Atom, ""a " & TN & """);");
            Append (Buf, LF);
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

               St := 1;
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        if Branch = 0 then
                           Append (Buf, "      if To_String (P.Toks (P.Pos).Text) = """
                             & To_String (P (St).Lit) & """ then R := "
                             & Ada_Ident (NM) & "_" & To_String (Names (Branch + 1)) & ";");
                        else
                           Append (Buf, "      elsif To_String (P.Toks (P.Pos).Text) = """
                             & To_String (P (St).Lit) & """ then R := "
                             & Ada_Ident (NM) & "_" & To_String (Names (Branch + 1)) & ";");
                        end if;
                        Append (Buf, LF);
                        Branch := Branch + 1;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "      else Fail (P, ""`");
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
            Append (Buf, """); end if;");
            Append (Buf, LF);
            Append (Buf, "      P.Pos := P.Pos + 1;");
            Append (Buf, LF);
            Append (Buf, "      return R;");
            Append (Buf, LF);
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            if Is_Core (To_String (P (1).Name)) then
               Append (Buf, "      Expect_Kind (P, "
                 & Scalar_Kind (To_String (P (1).Name)) & ", """
                 & Core_Desc (To_String (P (1).Name)) & """);");
               Append (Buf, LF);
               Append (Buf, "      R := " & Scalar_Parse (To_String (P (1).Name))
                 & "; P.Pos := P.Pos + 1;");
               Append (Buf, LF);
               Append (Buf, "      return R;");
               Append (Buf, LF);
            else
               Append (Buf, "      return Parse_"
                 & Ada_Ident (To_String (P (1).Name)) & " (P);");
               Append (Buf, LF);
            end if;
         else
            Emit_Seq (P, 1, Natural (P.Length), "R.", Buf);
            Append (Buf, "      return R;");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Parser;

      Spec  : U;
      Bdy  : U;
   begin
      --  Package specification: token types, the exception, Parse_Config.
      Append (Spec, "--  generated by hbnf -- do not edit");
      Append (Spec, LF);
      Append (Spec, "with Ada.Containers.Vectors;");
      Append (Spec, LF);
      Append (Spec, "with Ada.Strings.Unbounded;");
      Append (Spec, LF);
      Append (Spec, "with " & Package_Name & ";");
      Append (Spec, LF);
      Append (Spec, LF);
      Append (Spec, "package " & Package_Name & ".Parser is");
      Append (Spec, LF);
      Append (Spec, LF);
      Append (Spec, "   use Ada.Strings.Unbounded;");
      Append (Spec, LF);
      Append (Spec, LF);
      declare
         Enum : U := To_Unbounded_String
           ("   type Token_Kind is (Atom, Str, Int, Punct");
      begin
         for I in 1 .. N loop
            if Rules (I).Jet_Code /= Null_Unbounded_String then
               Append (Enum, ", " & Ada_Ident (To_String (Rules (I).Name)));
            end if;
         end loop;
         Append (Enum, ", Eof);");
         Append (Spec, To_String (Enum));
         Append (Spec, LF);
      end;
      Append (Spec, "   type Token is record");
      Append (Spec, LF);
      Append (Spec, "      Kind : Token_Kind;");
      Append (Spec, LF);
      Append (Spec, "      Text : Unbounded_String;");
      Append (Spec, LF);
      Append (Spec, "      Line : Natural;");
      Append (Spec, LF);
      Append (Spec, "      Col  : Natural;");
      Append (Spec, LF);
      Append (Spec, "   end record;");
      Append (Spec, LF);
      Append (Spec, "   package Token_Vectors is new Ada.Containers.Vectors (Positive, Token);");
      Append (Spec, LF);
      Append (Spec, "   package Line_Vectors is new Ada.Containers.Vectors (Positive, Unbounded_String);");
      Append (Spec, LF);
      Append (Spec, LF);
      Append (Spec, "   Parse_Error : exception;");
      Append (Spec, LF);
      Append (Spec, LF);
      Append (Spec, "   function Parse_Tokens");
      Append (Spec, LF);
      Append (Spec, "     (Toks  : Token_Vectors.Vector;");
      Append (Spec, LF);
      Append (Spec, "      Lines : Line_Vectors.Vector) return " & Ret_Type (1) & ";");
      Append (Spec, LF);
      Append (Spec, LF);
      Append (Spec, "   function Parse_Text (Text : String) return " & Ret_Type (1) & ";");
      Append (Spec, LF);
      Append (Spec, LF);
      if Conf then
         Append (Spec, "   function Parse_Config (Filename : String) return " & Ret_Type (1) & ";");
         Append (Spec, LF);
         Append (Spec, LF);
      end if;
      Append (Spec, "end " & Package_Name & ".Parser;");
      Append (Spec, LF);

      --  Package body: the recursive-descent parser.
      Append (Bdy, "with Interfaces;");
      Append (Bdy, LF);
      if Conf then
         Append (Bdy, "with Ada.Text_IO;");
         Append (Bdy, LF);
      end if;
      Append (Bdy, LF);
      Append (Bdy, "package body " & Package_Name & ".Parser is");
      Append (Bdy, LF);
      Append (Bdy, LF);
      Append (Bdy, "   use Ada.Strings.Unbounded;");
      Append (Bdy, LF);
      Append (Bdy, "   use Interfaces;");
      Append (Bdy, LF);
      Append (Bdy, LF);
      Append (Bdy, "   type Parser is record");
      Append (Bdy, LF);
      Append (Bdy, "      Toks  : Token_Vectors.Vector;");
      Append (Bdy, LF);
      Append (Bdy, "      Lines : Line_Vectors.Vector;");
      Append (Bdy, LF);
      Append (Bdy, "      Pos   : Natural := 1;");
      Append (Bdy, LF);
      Append (Bdy, "   end record;");
      Append (Bdy, LF);
      Append (Bdy, LF);
      Append (Bdy, "   Spaces : constant String :=");
      Append (Bdy, LF);
      Append (Bdy, "     ""                                                                "";");
      Append (Bdy, LF);
      Append (Bdy, LF);
      Append (Bdy, "   function Found (P : Parser) return String is");
      Append (Bdy, LF);
      Append (Bdy, "   begin");
      Append (Bdy, LF);
      Append (Bdy, "      if P.Pos <= Natural (P.Toks.Length) then");
      Append (Bdy, LF);
      Append (Bdy, "         return To_String (P.Toks (P.Pos).Text);");
      Append (Bdy, LF);
      Append (Bdy, "      end if;");
      Append (Bdy, LF);
      Append (Bdy, "      return ""end of input"";");
      Append (Bdy, LF);
      Append (Bdy, "   end Found;");
      Append (Bdy, LF);
      Append (Bdy, LF);
      Append (Bdy, "   procedure Fail (P : Parser; Expected : String) is");
      Append (Bdy, LF);
      Append (Bdy, "      L : Natural := 0;");
      Append (Bdy, LF);
      Append (Bdy, "      C : Natural := 0;");
      Append (Bdy, LF);
      Append (Bdy, "      Msg : Unbounded_String;");
      Append (Bdy, LF);
      Append (Bdy, "   begin");
      Append (Bdy, LF);
      Append (Bdy, "      if P.Pos <= Natural (P.Toks.Length) then");
      Append (Bdy, LF);
      Append (Bdy, "         L := P.Toks (P.Pos).Line;");
      Append (Bdy, LF);
      Append (Bdy, "         C := P.Toks (P.Pos).Col;");
      Append (Bdy, LF);
      Append (Bdy, "      end if;");
      Append (Bdy, LF);
      Append (Bdy, "      Append (Msg, ""expected "" & Expected & "", found "" & Found (P));");
      Append (Bdy, LF);
      Append (Bdy, "      if L >= 1 and then L <= Natural (P.Lines.Length) then");
      Append (Bdy, LF);
      Append (Bdy, "         declare");
      Append (Bdy, LF);
      Append (Bdy, "            W   : constant Natural := (if C > 1 then C - 1 else 0);");
      Append (Bdy, LF);
      Append (Bdy, "            Pad : constant String :=");
      Append (Bdy, LF);
      Append (Bdy, "              (if W <= Spaces'Length then Spaces (1 .. W) else Spaces);");
      Append (Bdy, LF);
      Append (Bdy, "         begin");
      Append (Bdy, LF);
      Append (Bdy, "            Append (Msg, ASCII.LF & ""  "" & To_String (P.Lines (L))");
      Append (Bdy, LF);
      Append (Bdy, "              & ASCII.LF & ""  "" & Pad & ""^"");");
      Append (Bdy, LF);
      Append (Bdy, "         end;");
      Append (Bdy, LF);
      Append (Bdy, "      end if;");
      Append (Bdy, LF);
      Append (Bdy, "      raise Parse_Error with To_String (Msg);");
      Append (Bdy, LF);
      Append (Bdy, "   end Fail;");
      Append (Bdy, LF);
      Append (Bdy, LF);
      Append (Bdy, "   procedure Expect_Lit (P : in out Parser; Lit : String) is");
      Append (Bdy, LF);
      Append (Bdy, "   begin");
      Append (Bdy, LF);
      Append (Bdy, "      if P.Pos <= Natural (P.Toks.Length)");
      Append (Bdy, LF);
      Append (Bdy, "        and then (P.Toks (P.Pos).Kind = Atom or else P.Toks (P.Pos).Kind = Punct)");
      Append (Bdy, LF);
      Append (Bdy, "        and then To_String (P.Toks (P.Pos).Text) = Lit");
      Append (Bdy, LF);
      Append (Bdy, "      then");
      Append (Bdy, LF);
      Append (Bdy, "         P.Pos := P.Pos + 1;");
      Append (Bdy, LF);
      Append (Bdy, "      else");
      Append (Bdy, LF);
      Append (Bdy, "         Fail (P, ""`"" & Lit & ""`"");");
      Append (Bdy, LF);
      Append (Bdy, "      end if;");
      Append (Bdy, LF);
      Append (Bdy, "   end Expect_Lit;");
      Append (Bdy, LF);
      Append (Bdy, LF);
      Append (Bdy, "   procedure Expect_Kind (P : in out Parser; K : Token_Kind; Desc : String) is");
      Append (Bdy, LF);
      Append (Bdy, "   begin");
      Append (Bdy, LF);
      Append (Bdy, "      if P.Pos <= Natural (P.Toks.Length) and then P.Toks (P.Pos).Kind = K then");
      Append (Bdy, LF);
      Append (Bdy, "         null;");
      Append (Bdy, LF);
      Append (Bdy, "      else");
      Append (Bdy, LF);
      Append (Bdy, "         Fail (P, Desc);");
      Append (Bdy, LF);
      Append (Bdy, "      end if;");
      Append (Bdy, LF);
      Append (Bdy, "   end Expect_Kind;");
      Append (Bdy, LF);
      Append (Bdy, LF);

      --  Forward declarations: a rule may call any other, in any order.
      for I in 1 .. N loop
         Append (Bdy, "   function Parse_" & Ada_Ident (To_String (Rules (I).Name))
           & " (P : in out Parser) return " & Ret_Type (I) & ";");
         Append (Bdy, LF);
      end loop;
      Append (Bdy, LF);

      for I in 1 .. N loop
         Append (Bdy, "   function Parse_" & Ada_Ident (To_String (Rules (I).Name))
           & " (P : in out Parser) return " & Ret_Type (I) & " is");
         Append (Bdy, LF);
         Emit_Rule_Decl (I, Bdy);
         Append (Bdy, "   begin");
         Append (Bdy, LF);
         Emit_Rule_Parser (I, Bdy);
         Append (Bdy, "   end Parse_" & Ada_Ident (To_String (Rules (I).Name)) & ";");
         Append (Bdy, LF);
         Append (Bdy, LF);
      end loop;

      Append (Bdy, "   function Parse_Tokens");
      Append (Bdy, LF);
      Append (Bdy, "     (Toks  : Token_Vectors.Vector;");
      Append (Bdy, LF);
      Append (Bdy, "      Lines : Line_Vectors.Vector) return " & Ret_Type (1) & " is");
      Append (Bdy, LF);
      Append (Bdy, "      P : Parser := (Toks => Toks, Lines => Lines, Pos => 1);");
      Append (Bdy, LF);
      Append (Bdy, "      R : " & Ret_Type (1) & ";");
      Append (Bdy, LF);
      Append (Bdy, "   begin");
      Append (Bdy, LF);
      Append (Bdy, "      R := Parse_" & Ada_Ident (To_String (Rules (1).Name)) & " (P);");
      Append (Bdy, LF);
      Append (Bdy, "      if P.Pos <= Natural (P.Toks.Length) and then P.Toks (P.Pos).Kind /= Eof then");
      Append (Bdy, LF);
      Append (Bdy, "         Fail (P, ""end of config"");");
      Append (Bdy, LF);
      Append (Bdy, "      end if;");
      Append (Bdy, LF);
      Append (Bdy, "      return R;");
      Append (Bdy, LF);
      Append (Bdy, "   end Parse_Tokens;");
      Append (Bdy, LF);
      Append (Bdy, LF);

      --  Jets: hand-written scanners, plus the dispatch the lexer calls.
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               R  : constant Rule := Rules (I);
               NM : constant String := To_String (R.Name);
            begin
               Append (Bdy, "   function Jet_" & Ada_Ident (NM)
                 & " (S : String; Pos, Len : Natural) return Natural is");
               Append (Bdy, LF);
               Append (Bdy, "   begin");
               Append (Bdy, LF);
               Append (Bdy, To_String (R.Jet_Code));
               Append (Bdy, LF);
               Append (Bdy, "   end Jet_" & Ada_Ident (NM) & ";");
               Append (Bdy, LF);
               Append (Bdy, LF);
            end;
         end if;
      end loop;

      Append (Bdy, "   function Jet_Dispatch (S : String; Pos, Len : Natural;"
        & " Kind : out Token_Kind) return Natural is");
      Append (Bdy, LF);
      Append (Bdy, "      N : Natural;");
      Append (Bdy, LF);
      Append (Bdy, "   begin");
      Append (Bdy, LF);
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               NM : constant String := To_String (Rules (I).Name);
            begin
               Append (Bdy, "      N := Jet_" & Ada_Ident (NM)
                 & " (S, Pos, Len); if N > 0 then Kind := " & Ada_Ident (NM)
                 & "; return N; end if;");
               Append (Bdy, LF);
            end;
         end if;
      end loop;
      Append (Bdy, "      return 0;");
      Append (Bdy, LF);
      Append (Bdy, "   end Jet_Dispatch;");
      Append (Bdy, LF);
      Append (Bdy, LF);

      --  Lexer: text -> token stream (schema-independent).
      Append (Bdy, Templates.Substitute (Templates.Substitute
        (Templates.Ada_Lexer, "@ROOT_TYPE@", Ret_Type (1)),
        "@ROOT_FN@", "Parse_" & Ada_Ident (To_String (Rules (1).Name))));
      Append (Bdy, LF);
      Append (Bdy, LF);
      if Conf then
         Append (Bdy, Templates.Substitute
           (Templates.Conf_Ada, "@ROOT_TYPE@", Ret_Type (1)));
         Append (Bdy, LF);
      end if;
      if Epilogue /= "" then
         Append (Bdy, Epilogue);
         Append (Bdy, LF);
      end if;
      Append (Bdy, "end " & Package_Name & ".Parser;");
      Append (Bdy, LF);

      return To_String (Spec) & LF & To_String (Bdy);
   end Emit_Parser;

end HBNF_Ada;
