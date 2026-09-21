pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package body ASTBNF_Ada is

   use Ada.Strings.Unbounded;
   use ASTBNF;

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
      elsif Name = "dec" then
         return "Long_Float";
      elsif Name = "float" then
         return "Float";
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
            if Members.Is_Empty then
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
               Append (Buf, "   type " & TN & " is (");
               for I in 1 .. Natural (Info.Literals.Length) loop
                  if I > 1 then
                     Append (Buf, ", ");
                  end if;
                  Append (Buf, Base & "_" &
                          Ada_Ident (To_String (Info.Literals (I))));
               end loop;
               Append (Buf, ");");
               Append (Buf, LF);
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

      Append (Res, "--  generated by astbnf -- do not edit");
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

      --  Leaves first: scalar subtypes and enumerations.
      for I in 1 .. N loop
         if Infos (I).Kind = Scalar or else Infos (I).Kind = Enum then
            Append (Res, Emit_Rule (I, Infos (I)));
            Append (Res, LF);
            Emitted (I) := True;
         end if;
      end loop;

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
     (Rules : ASTBNF.Rule_Vectors.Vector; Package_Name : String) return String
   is
   begin
      return "";
   end Emit_Parser;

end ASTBNF_Ada;
