pragma Ada_2022;

with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body HBNF_Compilable is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

   function Has_Alt (V : Element_Vectors.Vector) return Boolean is
     (for some E of V => E.Kind = Alt);

   procedure Reject (Rule_Name, What : String) is
   begin
      raise Parse_Error with
        Rule_Name & ": " & What & " inside a sequence is not supported by "
        & "the compiled backends yet; move it into a rule of its own";
   end Reject;

   function Same (A, B : Element_Access) return Boolean;

   function Same_Seq (A, B : Element_Vectors.Vector) return Boolean is
     (Natural (A.Length) = Natural (B.Length)
      and then (for all I in 1 .. Natural (A.Length) => Same (A (I), B (I))));

   function Same (A, B : Element_Access) return Boolean is
     (A.Kind = B.Kind and then A.Min = B.Min and then A.Max = B.Max
      and then (case A.Kind is
                  when Literal => A.Lit = B.Lit,
                  when Name    => A.Name = B.Name,
                  when Group   => Same_Seq (A.Items, B.Items),
                  when Alt     => True));

   function Image (V : Element_Vectors.Vector; First, Last : Natural)
     return String is
      Buf : Unbounded_String;
   begin
      for I in First .. Last loop
         if I > First then
            Append (Buf, " ");
         end if;
         case V (I).Kind is
            when Literal => Append (Buf, '"' & To_String (V (I).Lit) & '"');
            when Name    => Append (Buf, V (I).Name);
            when Group   => Append (Buf, "( ... )");
            when Alt     => Append (Buf, "/");
         end case;
      end loop;
      return To_String (Buf);
   end Image;

   --  Shadowed alternatives found: each is printed as it is found, and the
   --  check fails once the whole schema has been walked.
   Shadowed : Natural := 0;

   --  Ordered choice keeps the first branch that matches, so a branch that
   --  begins with the whole of an earlier one can never be reached: the
   --  earlier one matches first (`"keypair" name / "keypair" name "key" k`
   --  never reads the key).  Reject it rather than parse less than the
   --  grammar says.
   procedure Check_Shadowing (Rule_Name : String; V : Element_Vectors.Vector)
   is
      type Span is record
         First, Last : Natural;
      end record;
      type Span_Array is array (Positive range <>) of Span;
      Count : Natural := 1;
   begin
      for E of V loop
         if E.Kind = Alt then
            Count := Count + 1;
         end if;
      end loop;
      if Count = 1 then
         return;
      end if;
      declare
         Br : Span_Array (1 .. Count);
         K  : Positive := 1;
         St : Positive := 1;
      begin
         for I in 1 .. Natural (V.Length) + 1 loop
            if I > Natural (V.Length) or else V (I).Kind = Alt then
               Br (K) := (St, I - 1);
               K := K + 1;
               St := I + 1;
            end if;
         end loop;
         for I in Br'Range loop
            for J in I + 1 .. Br'Last loop
               declare
                  LI : constant Natural := Br (I).Last - Br (I).First + 1;
                  LJ : constant Natural := Br (J).Last - Br (J).First + 1;
               begin
                  if LI > 0 and then LI < LJ
                    and then (for all X in 0 .. LI - 1 =>
                                Same (V (Br (I).First + X),
                                      V (Br (J).First + X)))
                  then
                     Shadowed := Shadowed + 1;
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "hbnf: " & Rule_Name & ": the alternative `"
                        & Image (V, Br (J).First, Br (J).Last)
                        & "` can never match: the earlier `"
                        & Image (V, Br (I).First, Br (I).Last)
                        & "` matches its start first (put the longer one "
                        & "first)");
                  end if;
               end;
            end loop;
         end loop;
      end;
   end Check_Shadowing;

   --  Walk a sequence (or an alternation's branches).  Sole is True when V
   --  is a rule's whole pattern and has exactly one element: that element's
   --  repetition or grouping is the rule itself (a list, an optional rule,
   --  a grouped alternation) and the emitters handle it.
   procedure Walk
     (Rule_Name : String; V : Element_Vectors.Vector; Sole : Boolean) is
   begin
      Check_Shadowing (Rule_Name, V);
      for E of V loop
         case E.Kind is
            when Group =>
               if not Sole then
                  if E.Min /= 1 or else E.Max /= 1 then
                     Reject (Rule_Name,
                             (if E.Min = 0 and then E.Max = 1
                              then "an optional [ ]"
                              else "a repeated group"));
                  elsif Has_Alt (E.Items) then
                     Reject (Rule_Name, "an alternation group ( a / b )");
                  end if;
               end if;
               Walk (Rule_Name, E.Items, False);
            when Name =>
               if not Sole and then (E.Min /= 1 or else E.Max /= 1) then
                  Reject (Rule_Name,
                          "a repeated reference to " & To_String (E.Name));
               end if;
            when Literal | Alt =>
               null;
         end case;
      end loop;
   end Walk;

   function Find (Rules : Rule_Vectors.Vector; Name : String) return Natural is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if To_String (Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Is_List_Rule (R : Rule) return Boolean is
     (Natural (R.Pattern.Length) = 1
      and then R.Jet_Code = Null_Unbounded_String
      and then not (R.Pattern (1).Min = 1 and then R.Pattern (1).Max = 1));

   procedure Append_Comma (S : in out Unbounded_String; Item : String) is
   begin
      if S /= Null_Unbounded_String then
         Append (S, ", ");
      end if;
      Append (S, Item);
   end Append_Comma;

   procedure Check
     (Rules   : HBNF_Grammar.Rule_Vectors.Vector;
      Backend : String) is
   begin
      if Natural (Rules.Length) = 0 then
         raise Parse_Error with "the schema defines no rules";
      end if;
      Shadowed := 0;

      --  `conf struct X` hands parse_config the daemon's own struct, which
      --  only action jets fill: without one the parse would succeed and
      --  leave the daemon's conf empty.
      if Conf_Type /= ""
        and then not (for some R of Rules =>
                        R.Action_Code /= Null_Unbounded_String)
      then
         raise Parse_Error with
           "`conf " & Conf_Type & "` is filled by action jets, and no rule "
           & "has one (add `action <rule> { ... }`)";
      end if;

      --  A listops block overrides hbnf's built-in list operation by
      --  operation.  The seven structural operations form one list, so a
      --  partial block (mixing overridden and built-in operations) would
      --  generate a list whose parts do not fit together.  Require all seven
      --  when any is given; relink stays optional.
      if Backend = "c" then
         declare
            Ops     : constant array (Positive range <>) of Unbounded_String :=
              (To_Unbounded_String ("head"), To_Unbounded_String ("entry"),
               To_Unbounded_String ("init"), To_Unbounded_String ("append"),
               To_Unbounded_String ("foreach"), To_Unbounded_String ("first"),
               To_Unbounded_String ("next"));
            Given   : Unbounded_String;
            Missing : Unbounded_String;
         begin
            for Op of Ops loop
               if List_Override (To_String (Op)) /= "" then
                  Append_Comma (Given, To_String (Op));
               else
                  Append_Comma (Missing, To_String (Op));
               end if;
            end loop;
            if Given /= Null_Unbounded_String
              and then Missing /= Null_Unbounded_String
            then
               raise Parse_Error with
                 "listops: gives " & To_String (Given) & " but not "
                 & To_String (Missing)
                 & "; give all of head, entry, init, append, foreach, first, "
                 & "next (relink is optional)";
            end if;
         end;
      end if;

      --  `statements` reads the root list one entry per statement, so the
      --  root must be an unbounded, possibly empty list; `macros` and
      --  `includes` name rules the driver tries on each statement.
      if Statements or else Macros_Rule /= "" or else Includes_Rule /= ""
      then
         declare
            Root : constant Rule := Rules (1);
            RN   : constant String := To_String (Root.Name);

            procedure Need (Directive, Name : String) is
               J : constant Natural := Find (Rules, Name);
            begin
               if Name = "" then
                  return;
               end if;
               if J = 0 then
                  raise Parse_Error with
                    Directive & " " & Name & ": no rule `" & Name
                    & "` that the root uses";
               end if;
               if Rules (J).Jet_Code /= Null_Unbounded_String
                 or else Rules (J).C_Type /= Null_Unbounded_String
               then
                  raise Parse_Error with
                    Directive & " " & Name & ": `" & Name
                    & "` must be a plain rule (not a jet or a typed rule)";
               end if;
            end Need;
         begin
            if not Statements then
               raise Parse_Error with
                 "`macros` and `includes` work on statements; add "
                 & "`statements`";
            end if;
            if not Is_List_Rule (Root)
              or else Root.C_Type /= Null_Unbounded_String
              or else Root.Pattern (1).Min /= 0
              or else Root.Pattern (1).Max /= -1
            then
               raise Parse_Error with
                 "statements: the root rule `" & RN & "` must be a list "
                 & "`*( ... )`, one entry per statement";
            end if;
            Need ("macros", Macros_Rule);
            Need ("includes", Includes_Rule);
            if Backend /= "c" then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "hbnf: warning: statements, macros and includes are "
                  & "implemented by the C backend only; the " & Backend
                  & " backend parses the whole file and expands no macros");
            end if;
         end;
      end if;

      for R of Rules loop
         declare
            P : constant Element_Vectors.Vector := R.Pattern;
            N : constant String := To_String (R.Name);
         begin
            Walk (N, P, Natural (P.Length) = 1);
            --  An alias of a list rule would take the list's node type,
            --  not its head type, in every backend.
            if Natural (P.Length) = 1 and then P (1).Kind = Name
              and then P (1).Min = 1 and then P (1).Max = 1
            then
               declare
                  T : constant Natural := Find (Rules, To_String (P (1).Name));
               begin
                  if T /= 0 and then Is_List_Rule (Rules (T)) then
                     raise Parse_Error with
                       N & ": an alias of the list rule `"
                       & To_String (P (1).Name) & "` is not supported yet; "
                       & "define " & N & " as a list of the same element";
                  end if;
               end;
            end if;
            if Backend /= "c"
              and then Natural (P.Length) = 1
              and then not (P (1).Min = 1 and then P (1).Max = 1)
              and then not (P (1).Min = 0 and then P (1).Max = -1)
            then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "hbnf: warning: " & N & ": repetition bounds are enforced "
                  & "by the C backend only; the " & Backend
                  & " backend treats this rule as *");
            end if;
         end;
      end loop;
      if Shadowed > 0 then
         raise Parse_Error with
           Natural'Image (Shadowed) & " alternative(s) can never match "
           & "(listed above)";
      end if;
   end Check;

end HBNF_Compilable;
