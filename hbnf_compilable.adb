pragma Ada_2022;

with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body HBNF_Compilable is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

   function Has_Alt (V : Element_Vectors.Vector) return Boolean is
     (for some E of V => E.Kind = Alt);

   --  True when the rule named Nm is character-level: its pattern is a
   --  sequence/alternation of Char_Range terminals, plain string literals and
   --  references to other char-level rules, each matching some number of code
   --  points (Min..Max; Max = -1 unbounded).  Shared by the emitters' shape
   --  analyzers and their parser/lexer emission.  The extra constraints the
   --  scanner still cannot express (a repetition followed by more elements,
   --  a repetition of a repetition, a %i literal) are diagnosed by
   --  Validate_Char_Rules, not reflected here.
   function Is_Char_Rule (Rules : Rule_Vectors.Vector; Nm : String)
      return Boolean is
      function Rec (N : String; Depth : Natural) return Boolean is
         J : Natural := 0;
      begin
         for I in 1 .. Natural (Rules.Length) loop
            if To_String (Rules (I).Name) = N then
               J := I;
               exit;
            end if;
         end loop;
         if J = 0 or else Depth = 0 then
            return False;
         end if;
         declare
            R : constant Rule := Rules (J);
         begin
            if R.Jet_Code /= Null_Unbounded_String
              or else Natural (R.Pattern.Length) = 0
            then
               return False;
            end if;
            declare
               Has_Anchor : Boolean := False;
            begin
               for E of R.Pattern loop
                  case E.Kind is
                     when Char_Range =>
                        Has_Anchor := True;
                     when Alt =>
                        null;
                     when Literal =>
                        if E.No_Case then
                           return False;
                        end if;
                     when Name =>
                        if not Rec (To_String (E.Name), Depth - 1) then
                           return False;
                        end if;
                        Has_Anchor := True;
                     when Group =>
                        return False;
                  end case;
               end loop;
               --  A literal-only rule (no character terminal, no char-rule
               --  reference) is a keyword enum, not a scanner.
               return Has_Anchor;
            end;
         end;
      end Rec;
   begin
      return Rec (Nm, 20);
   end Is_Char_Rule;

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
                  when Literal => A.Lit = B.Lit and then A.No_Case = B.No_Case,
                  when Name    => A.Name = B.Name,
                  when Group   => Same_Seq (A.Items, B.Items),
                  when Char_Range   => A.Lo = B.Lo and then A.Hi = B.Hi,
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
            when Literal =>
               Append (Buf, (if V (I).No_Case then "%i" else "")
                            & '"' & To_String (V (I).Lit) & '"');
            when Name    => Append (Buf, V (I).Name);
            when Group   => Append (Buf, "( ... )");
            when Char_Range   => Append (Buf, "%x..");
            when Alt     => Append (Buf, "|");
         end case;
      end loop;
      return To_String (Buf);
   end Image;

   --  Shadowed alternatives found: each is printed as it is found, and the
   --  check fails once the whole schema has been walked.
   Shadowed : Natural := 0;

   --  Ordered choice keeps the first branch that matches, so a branch that
   --  begins with the whole of an earlier one can never be reached: the
   --  earlier one matches first (`"keypair" name | "keypair" name "key" k`
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
            when Literal | Alt | Char_Range =>
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

   function Char_DNF (Rules : Rule_Vectors.Vector; Nm : String)
      return Cp_Branch_Atom_Vectors.Vector is

      --  A literal's UTF-8 bytes as single-code-point ranges.
      function Code_Points (S : String) return Cp_Range_Vectors.Vector is
         V : Cp_Range_Vectors.Vector;
         I : Natural := S'First;
      begin
         while I <= S'Last loop
            declare
               B0 : constant Natural := Character'Pos (S (I));
               C  : Natural;
               N  : Natural;
            begin
               if B0 < 16#80# then
                  C := B0; N := 1;
               elsif B0 in 16#C0# .. 16#DF# then
                  C := B0 - 16#C0#; N := 2;
               elsif B0 in 16#E0# .. 16#EF# then
                  C := B0 - 16#E0#; N := 3;
               elsif B0 in 16#F0# .. 16#F7# then
                  C := B0 - 16#F0#; N := 4;
               else
                  C := B0; N := 1;
               end if;
               for K in 1 .. N - 1 loop
                  exit when I + K > S'Last;
                  declare
                     B : constant Natural := Character'Pos (S (I + K));
                  begin
                     if B not in 16#80# .. 16#BF# then
                        N := 1; C := B0; exit;
                     end if;
                     C := C * 16#40# + (B - 16#80#);
                  end;
               end loop;
               V.Append (Cp_Range'(Lo => C, Hi => C));
               I := I + N;
            end;
         end loop;
         return V;
      end Code_Points;

      function Has_Trailing_Rep (Sub : Cp_Branch_Atom_Vectors.Vector)
        return Boolean is
        (for some B of Sub =>
           Natural (B.Length) > 0
           and then B (Natural (B.Length)).Kind = Repeat);

      --  The flat DNF (branches of single code points) of a rule that is not
      --  repeated: a repetition inside it is a repetition of a repetition,
      --  which the scanner cannot express.
      function Flat (J : Natural; Depth : Natural) return Cp_Branch_Vectors.Vector is
         R : constant Rule := Rules (J);

         function Flat_Seq (First, Last : Natural) return Cp_Branch_Vectors.Vector is
            Branches : Cp_Branch_Vectors.Vector;
         begin
            Branches.Append (Cp_Range_Vectors.Empty_Vector);
            for K in First .. Last loop
               declare
                  E : constant Element_Access := R.Pattern (K);
               begin
                  if E.Min /= 1 or else E.Max /= 1 then
                     raise Parse_Error with To_String (R.Name)
                       & ": a repetition of a repetition is not a scanner";
                  end if;
                  if E.Kind = Char_Range then
                     for B of Branches loop
                        B.Append (Cp_Range'(Lo => E.Lo, Hi => E.Hi));
                     end loop;
                  elsif E.Kind = Literal then
                     for B of Branches loop
                        for Rg of Code_Points (To_String (E.Lit)) loop
                           B.Append (Rg);
                        end loop;
                     end loop;
                  elsif E.Kind = Name then
                     declare
                        Idx : constant Natural := Find (Rules, To_String (E.Name));
                        Sub : Cp_Branch_Vectors.Vector;
                        New_Branches : Cp_Branch_Vectors.Vector;
                     begin
                        if Idx /= 0 then
                           Sub := Flat (Idx, Depth - 1);
                        end if;
                        for B of Branches loop
                           for S of Sub loop
                              declare
                                 Cat : Cp_Range_Vectors.Vector := B;
                              begin
                                 for Rg of S loop
                                    Cat.Append (Rg);
                                 end loop;
                                 New_Branches.Append (Cat);
                              end;
                           end loop;
                        end loop;
                        Branches := New_Branches;
                     end;
                  end if;
               end;
            end loop;
            return Branches;
         end Flat_Seq;
      begin
         if J = 0 or else Depth = 0 or else Natural (R.Pattern.Length) = 0 then
            declare
               One : Cp_Branch_Vectors.Vector;
            begin
               One.Append (Cp_Range_Vectors.Empty_Vector);
               return One;
            end;
         end if;
         declare
            P        : constant Element_Vectors.Vector := R.Pattern;
            Branches : Cp_Branch_Vectors.Vector;
            St       : Natural := 1;
         begin
            for K in 1 .. Natural (P.Length) + 1 loop
               if K > Natural (P.Length) or else P (K).Kind = Alt then
                  declare
                     Sub : Cp_Branch_Vectors.Vector := Flat_Seq (St, K - 1);
                  begin
                     for S of Sub loop
                        Branches.Append (S);
                     end loop;
                  end;
                  St := K + 1;
               end if;
            end loop;
            return Branches;
         end;
      end Flat;

      --  The flat DNF of one repeated element: a Char_Range, a plain Literal,
      --  or a Name of a repetition-free rule (nested repetition raises).  A
      --  repetition matches one code point per iteration, so the result must
      --  be a char class -- one range per branch -- not a sequence.
      function Flat_Element (E : Element_Access; Depth : Natural;
                             In_Rule : String)
        return Cp_Branch_Vectors.Vector is
         Result : Cp_Branch_Vectors.Vector;
      begin
         if E.Kind = Char_Range then
            declare
               Inner : Cp_Range_Vectors.Vector;
            begin
               Inner.Append (Cp_Range'(Lo => E.Lo, Hi => E.Hi));
               Result.Append (Inner);
            end;
         elsif E.Kind = Literal then
            declare
               Inner : constant Cp_Range_Vectors.Vector :=
                 Code_Points (To_String (E.Lit));
            begin
               Result.Append (Inner);
            end;
         else
            declare
               Idx : constant Natural := Find (Rules, To_String (E.Name));
            begin
               if Idx = 0 then
                  Result.Append (Cp_Range_Vectors.Empty_Vector);
               else
                  Result := Flat (Idx, Depth - 1);
               end if;
            end;
         end if;
         if (for some B of Result => Natural (B.Length) /= 1) then
            raise Parse_Error with In_Rule
              & ": a repetition matches one code point per iteration (a "
              & "character class), not a sequence";
         end if;
         return Result;
      end Flat_Element;

      --  The atom DNF (branches of Single/Repeat atoms) of a rule.
      function Atom (J : Natural; Depth : Natural)
        return Cp_Branch_Atom_Vectors.Vector is
         R : constant Rule := Rules (J);

         function Atom_Seq (First, Last : Natural)
           return Cp_Branch_Atom_Vectors.Vector is
            Branches : Cp_Branch_Atom_Vectors.Vector;
         begin
            Branches.Append (Cp_Atom_Vectors.Empty_Vector);
            for K in First .. Last loop
               declare
                  E       : constant Element_Access := R.Pattern (K);
                  Rep     : constant Boolean := E.Min /= 1 or else E.Max /= 1;
                  Last_El : constant Boolean := K = Last;
               begin
                  if Rep and then not Last_El then
                     raise Parse_Error with To_String (R.Name)
                       & ": a repetition must be the last element of a "
                       & "character rule (it would need backtracking)";
                  end if;
                  if Rep then
                     declare
                        Rpt : constant Cp_Atom :=
                          Cp_Atom'(Kind => Repeat, Lo => 0, Hi => 0,
                                   Min => E.Min,
                                   Max => (if E.Max = -1 then 0
                                           else Natural (E.Max)),
                                   Sub => Flat_Element
                                            (E, Depth, To_String (R.Name)));
                     begin
                        for B of Branches loop
                           B.Append (Rpt);
                        end loop;
                     end;
                  elsif E.Kind = Char_Range then
                     for B of Branches loop
                        B.Append (Cp_Atom'(Kind => Single,
                                           Lo => E.Lo, Hi => E.Hi));
                     end loop;
                  elsif E.Kind = Literal then
                     for B of Branches loop
                        for Rg of Code_Points (To_String (E.Lit)) loop
                           B.Append (Cp_Atom'(Kind => Single,
                                              Lo => Rg.Lo, Hi => Rg.Hi));
                        end loop;
                     end loop;
                  else
                     --  A non-repeated Name: distribute its atom DNF.
                     declare
                        Idx : constant Natural := Find (Rules, To_String (E.Name));
                        Sub : Cp_Branch_Atom_Vectors.Vector;
                        New_Branches : Cp_Branch_Atom_Vectors.Vector;
                     begin
                        if Idx /= 0 then
                           Sub := Atom (Idx, Depth - 1);
                        end if;
                        if not Last_El and then Has_Trailing_Rep (Sub) then
                           raise Parse_Error with To_String (R.Name)
                             & ": `" & To_String (E.Name)
                             & "` ends in a repetition and is followed by "
                             & "more; write the repetition last";
                        end if;
                        for B of Branches loop
                           for S of Sub loop
                              declare
                                 Cat : Cp_Atom_Vectors.Vector := B;
                              begin
                                 for A of S loop
                                    Cat.Append (A);
                                 end loop;
                                 New_Branches.Append (Cat);
                              end;
                           end loop;
                        end loop;
                        Branches := New_Branches;
                     end;
                  end if;
               end;
            end loop;
            return Branches;
         end Atom_Seq;
      begin
         if J = 0 or else Depth = 0 or else Natural (R.Pattern.Length) = 0 then
            declare
               One : Cp_Branch_Atom_Vectors.Vector;
            begin
               One.Append (Cp_Atom_Vectors.Empty_Vector);
               return One;
            end;
         end if;
         declare
            P        : constant Element_Vectors.Vector := R.Pattern;
            Branches : Cp_Branch_Atom_Vectors.Vector;
            St       : Natural := 1;
         begin
            for K in 1 .. Natural (P.Length) + 1 loop
               if K > Natural (P.Length) or else P (K).Kind = Alt then
                  declare
                     Sub : Cp_Branch_Atom_Vectors.Vector := Atom_Seq (St, K - 1);
                  begin
                     for S of Sub loop
                        Branches.Append (S);
                     end loop;
                  end;
                  St := K + 1;
               end if;
            end loop;
            return Branches;
         end;
      end Atom;
   begin
      return Atom (Find (Rules, Nm), 20);
   end Char_DNF;

   function Is_List_Rule (R : Rule) return Boolean is
     (Natural (R.Pattern.Length) = 1
      and then R.Jet_Code = Null_Unbounded_String
      and then not (R.Pattern (1).Min = 1 and then R.Pattern (1).Max = 1));

   --  Left recursion the reader did not turn into a loop: through other
   --  rules (`a = b x`, `b = a y`), or behind something that can match
   --  nothing (`a = [x] a y`).  The parser would call a rule again at the
   --  same position, and recurse until the stack ran out.  A rule can
   --  begin with the rules its leftmost elements name, and with the
   --  elements after one that can match nothing; a list rewritten from
   --  left recursion begins with its bases only, since a tail comes after
   --  an entry.
   procedure Check_Left_Recursion (Rules : Rule_Vectors.Vector) is
      N        : constant Natural := Natural (Rules.Length);
      Nullable : array (1 .. N) of Boolean := [others => False];
      type Edge_Array is array (1 .. N) of Boolean;
      Left     : array (1 .. N) of Edge_Array :=
        [others => [others => False]];

      function Rule_Of (E : Element_Access) return Natural is
        (if E.Kind = Name then Find (Rules, To_String (E.Name)) else 0);

      function Seq_Nullable (V : Element_Vectors.Vector;
                             First, Last : Natural) return Boolean;

      function El_Nullable (E : Element_Access) return Boolean is
      begin
         if E.Min = 0 then
            return True;
         end if;
         case E.Kind is
            when Name =>
               return Rule_Of (E) /= 0 and then Nullable (Rule_Of (E));
            when Group =>
               return Seq_Nullable (E.Items, 1, Natural (E.Items.Length));
            when Literal | Alt | Char_Range =>
               return False;
         end case;
      end El_Nullable;

      --  True when some branch of V (First .. Last) can match nothing.
      function Seq_Nullable (V : Element_Vectors.Vector;
                             First, Last : Natural) return Boolean is
         All_Null : Boolean := True;
      begin
         for I in First .. Last + 1 loop
            if I > Last or else V (I).Kind = Alt then
               if All_Null then
                  return True;
               end if;
               All_Null := True;
            elsif not El_Nullable (V (I)) then
               All_Null := False;
            end if;
         end loop;
         return False;
      end Seq_Nullable;

      function Starts (R : Rule) return Element_Vectors.Vector is
        (if R.Left_Bases > 0
         and then not Seq_Nullable (Base_Branches (R), 1,
                                    Natural (Base_Branches (R).Length))
         then Base_Branches (R)
         else R.Pattern);

      --  Record in Left (From) every rule V's branches can begin with.
      procedure Mark (From : Positive; V : Element_Vectors.Vector) is
         Skip : Boolean := False;   --  past a branch's first solid element
      begin
         for E of V loop
            if E.Kind = Alt then
               Skip := False;
            elsif not Skip then
               if Rule_Of (E) /= 0 then
                  Left (From) (Rule_Of (E)) := True;
               elsif E.Kind = Group then
                  Mark (From, E.Items);
               end if;
               Skip := not El_Nullable (E);
            end if;
         end loop;
      end Mark;

      Changed : Boolean := True;
   begin
      while Changed loop
         Changed := False;
         for I in 1 .. N loop
            if not Nullable (I) and then Rules (I).Jet_Code = Null_Unbounded_String
              and then Seq_Nullable (Rules (I).Pattern, 1,
                                     Natural (Rules (I).Pattern.Length))
            then
               Nullable (I) := True;
               Changed := True;
            end if;
         end loop;
      end loop;
      for I in 1 .. N loop
         if Rules (I).Jet_Code = Null_Unbounded_String then
            Mark (I, Starts (Rules (I)));
         end if;
      end loop;

      --  A depth-first search from each rule for a way back to it.
      for Root in 1 .. N loop
         declare
            From : array (1 .. N) of Natural := [others => 0];
            Seen : Edge_Array := [others => False];
            Stack : array (1 .. N) of Positive;
            Top   : Natural := 1;
         begin
            Stack (1) := Root;
            Seen (Root) := True;
            while Top > 0 loop
               declare
                  At_R : constant Positive := Stack (Top);
               begin
                  Top := Top - 1;
                  for J in 1 .. N loop
                     if Left (At_R) (J) and then J = Root then
                        declare
                           Path : Unbounded_String :=
                             To_Unbounded_String (To_String (Rules (Root).Name));
                           K    : Natural := At_R;
                           Hops : Unbounded_String;
                        begin
                           while K /= Root loop
                              Hops := " -> " & Rules (K).Name & Hops;
                              K := From (K);
                           end loop;
                           Append (Path, Hops);
                           Append (Path, " -> " & To_String (Rules (Root).Name));
                           --  GNAT cuts an exception message at 200
                           --  characters: keep it short.
                           raise Parse_Error with
                             To_String (Rules (Root).Name)
                             & ": left recursion "
                             & (if At_R = Root
                                then "after something that can match nothing"
                                else "through another rule")
                             & " (" & To_String (Path) & "); hbnf makes "
                             & "only direct left recursion (a = a x | y) "
                             & "into a loop";
                        end;
                     elsif Left (At_R) (J) and then not Seen (J) then
                        Seen (J) := True;
                        From (J) := At_R;
                        Top := Top + 1;
                        Stack (Top) := J;
                     end if;
                  end loop;
               end;
            end loop;
         end;
      end loop;
   end Check_Left_Recursion;

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

      --  `entry` renames the function the conf wrapper defines, which
      --  exists only with `conf`.
      if Entry_Name /= "parse_config" and then Conf_Type = "" then
         raise Parse_Error with
           "`entry " & Entry_Name & "` names the function the `conf` "
           & "wrapper defines; add `conf struct <daemon conf>`";
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
               if Rules (J).Jet_Code /= Null_Unbounded_String then
                  raise Parse_Error with
                    Directive & " " & Name & ": `" & Name
                    & "` must be a plain rule (not a jet)";
               end if;
            end Need;
         begin
            if not Statements then
               raise Parse_Error with
                 "`macros` and `includes` work on statements; add "
                 & "`statements`";
            end if;
            if not Is_List_Rule (Root)
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
            if R.Left_Bases > 0 then
               --  A base and a tail are never tried at the same place, so
               --  neither can shadow the other.
               Walk (N, Base_Branches (R), False);
               Walk (N, Tail_Branches (R), False);
            else
               Walk (N, P, Natural (P.Length) = 1);
            end if;
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
         end;
      end loop;

      --  A character rule the scanner cannot express -- a repetition followed
      --  by more elements, or a repetition of a repetition -- is diagnosed
      --  here, before emission, by running the DNF builder once (it raises).
      for R of Rules loop
         if Is_Char_Rule (Rules, To_String (R.Name)) then
            declare
               Dummy : constant Cp_Branch_Atom_Vectors.Vector :=
                 Char_DNF (Rules, To_String (R.Name));
               pragma Unreferenced (Dummy);
            begin
               null;
            end;
         end if;
      end loop;

      Check_Left_Recursion (Rules);
      if Shadowed > 0 then
         raise Parse_Error with
           Natural'Image (Shadowed) & " alternative(s) can never match "
           & "(listed above)";
      end if;
   end Check;

end HBNF_Compilable;
