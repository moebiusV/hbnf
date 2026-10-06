pragma Ada_2022;

package body HBNF_Lookahead is

   use Ada.Strings.Unbounded;

   --  ---------------------------------------------------------------------
   --  Code-point sets
   --  ---------------------------------------------------------------------

   function Less (A, B : Cp_Range) return Boolean is (A.Lo < B.Lo);

   package Range_Sorting is new Range_Vectors.Generic_Sorting ("<" => Less);

   procedure Normalize (S : in out Cp_Set) is
      Merged : Range_Vectors.Vector;
   begin
      Range_Sorting.Sort (S.Ranges);
      for R of S.Ranges loop
         if not Merged.Is_Empty
           and then R.Lo <= Merged.Last_Element.Hi + 1
         then
            if R.Hi > Merged.Last_Element.Hi then
               Merged.Reference (Merged.Last_Index).Hi := R.Hi;
            end if;
         else
            Merged.Append (R);
         end if;
      end loop;
      S.Ranges := Merged;
   end Normalize;

   function Range_Set (Lo, Hi : Natural) return Cp_Set is
      S : Cp_Set;
   begin
      S.Ranges.Append (Cp_Range'(Lo => Lo, Hi => Hi));
      return S;
   end Range_Set;

   function Any_Set return Cp_Set is
      S : Cp_Set;
   begin
      S.Any := True;
      return S;
   end Any_Set;

   function Is_Empty (S : Cp_Set) return Boolean is
     (S.Ranges.Is_Empty and then not S.Eoi and then not S.Any);

   function "or" (A, B : Cp_Set) return Cp_Set is
      R : Cp_Set := A;
   begin
      for X of B.Ranges loop
         R.Ranges.Append (X);
      end loop;
      R.Eoi := A.Eoi or else B.Eoi;
      R.Any := A.Any or else B.Any;
      Normalize (R);
      return R;
   end "or";

   function Meet (A, B : Cp_Set) return Cp_Set is
      R : Cp_Set;
   begin
      if A.Any and then not Is_Empty (B) then
         return B or Any_Set;
      elsif B.Any and then not Is_Empty (A) then
         return A or Any_Set;
      end if;
      for X of A.Ranges loop
         for Y of B.Ranges loop
            declare
               Lo : constant Natural := Natural'Max (X.Lo, Y.Lo);
               Hi : constant Natural := Natural'Min (X.Hi, Y.Hi);
            begin
               if Lo <= Hi then
                  R.Ranges.Append (Cp_Range'(Lo => Lo, Hi => Hi));
               end if;
            end;
         end loop;
      end loop;
      R.Eoi := A.Eoi and then B.Eoi;
      Normalize (R);
      return R;
   end Meet;

   function Hex (N : Natural) return String is
      D : constant String := "0123456789ABCDEF";
      R : String (1 .. 8) := [others => '0'];
      I : Natural := 8;
      V : Natural := N;
   begin
      loop
         R (I) := D (V mod 16 + 1);
         V := V / 16;
         exit when V = 0;
         I := I - 1;
      end loop;
      return R (Natural'Min (I, 5) .. 8);
   end Hex;

   function Cp_Image (C : Natural) return String is
     (if C in 33 .. 126 then "`" & Character'Val (C) & "`"
      elsif C = 32 then "SP"
      else "U+" & Hex (C));

   function Image (S : Cp_Set) return String is
      R : Unbounded_String;
      N : Natural := 0;
   begin
      if S.Any then
         return "anything (a jet or built-in scanner)";
      end if;
      for X of S.Ranges loop
         N := N + 1;
         if N > 6 then
            Append (R, " ...");
            exit;
         end if;
         if Length (R) > 0 then
            Append (R, " ");
         end if;
         Append (R, Cp_Image (X.Lo));
         if X.Hi /= X.Lo then
            Append (R, "-" & Cp_Image (X.Hi));
         end if;
      end loop;
      if S.Eoi then
         if Length (R) > 0 then
            Append (R, " ");
         end if;
         Append (R, "end of input");
      end if;
      return To_String (R);
   end Image;

   --  ---------------------------------------------------------------------
   --  Rules and sequences
   --  ---------------------------------------------------------------------

   function Find (Rules : Rule_Vectors.Vector; Name : String) return Natural is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if To_String (Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Branches (V : Element_Vectors.Vector) return Bounds_Vectors.Vector
   is
      Result : Bounds_Vectors.Vector;
      St     : Positive := 1;
      N      : constant Natural := Natural (V.Length);
   begin
      for I in 1 .. N + 1 loop
         if I > N or else V (I).Kind = Alt then
            Result.Append (Bounds'(First => St, Last => I - 1));
            St := I + 1;
         end if;
      end loop;
      return Result;
   end Branches;

   function El_Nullable
     (Rules : Rule_Vectors.Vector; Nullable : Flags; E : Element_Access)
      return Boolean is
   begin
      if E.Min = 0 then
         return True;
      end if;
      case E.Kind is
         when Name =>
            declare
               J : constant Natural := Find (Rules, To_String (E.Name));
            begin
               return J /= 0 and then Nullable (J);
            end;
         when Group =>
            return Seq_Nullable
              (Rules, Nullable, E.Items, 1, Natural (E.Items.Length));
         when Literal | Alt | Char_Range =>
            return False;
         when Block =>
            --  A `%action{ }` between elements matches nothing, so it is
            --  nullable.  `Lift` has already replaced it by the time the
            --  backends run, so the arm is here for completeness.
            return True;
      end case;
   end El_Nullable;

   function Seq_Nullable
     (Rules : Rule_Vectors.Vector; Nullable : Flags;
      V : Element_Vectors.Vector; First, Last : Natural) return Boolean is
      All_Null : Boolean := True;
   begin
      for I in First .. Last + 1 loop
         if I > Last or else V (I).Kind = Alt then
            if All_Null then
               return True;
            end if;
            All_Null := True;
         elsif not El_Nullable (Rules, Nullable, V (I)) then
            All_Null := False;
         end if;
      end loop;
      return False;
   end Seq_Nullable;

   function Nullable_Set (Rules : Rule_Vectors.Vector) return Flags is
      N        : constant Natural := Natural (Rules.Length);
      Nullable : Flags (1 .. N) := [others => False];
      Changed  : Boolean := True;
   begin
      while Changed loop
         Changed := False;
         for I in 1 .. N loop
            if not Nullable (I)
              and then Rules (I).Jet_Code = Null_Unbounded_String
              and then Seq_Nullable (Rules, Nullable, Rules (I).Pattern, 1,
                                     Natural (Rules (I).Pattern.Length))
            then
               Nullable (I) := True;
               Changed := True;
            end if;
         end loop;
      end loop;
      return Nullable;
   end Nullable_Set;

   --  The first code point of a literal's UTF-8 bytes.
   function First_Cp (S : String) return Natural is
      B : constant Natural := Character'Pos (S (S'First));

      function Cont (K : Positive) return Natural is
        (Character'Pos (S (S'First + K)) mod 64);
   begin
      if B < 16#80# then
         return B;
      elsif B in 16#C0# .. 16#DF# and then S'Length >= 2 then
         return (B - 16#C0#) * 64 + Cont (1);
      elsif B in 16#E0# .. 16#EF# and then S'Length >= 3 then
         return (B - 16#E0#) * 4096 + Cont (1) * 64 + Cont (2);
      elsif B in 16#F0# .. 16#F7# and then S'Length >= 4 then
         return (B - 16#F0#) * 262144 + Cont (1) * 4096 + Cont (2) * 64
           + Cont (3);
      else
         return B;
      end if;
   end First_Cp;

   procedure Seq_First
     (Rules : Rule_Vectors.Vector; Nullable : Flags; First : Set_Array;
      V : Element_Vectors.Vector; From, To : Natural;
      Set : out Cp_Set; Is_Null : out Boolean);

   function El_First
     (Rules : Rule_Vectors.Vector; Nullable : Flags; First : Set_Array;
      E : Element_Access) return Cp_Set is
   begin
      case E.Kind is
         when Char_Range =>
            return Range_Set (E.Lo, E.Hi);
         when Literal =>
            declare
               S : constant String := To_String (E.Lit);
            begin
               if S'Length = 0 then
                  return Empty;
               end if;
               declare
                  C : constant Natural := First_Cp (S);
                  R : Cp_Set := Range_Set (C, C);
               begin
                  if E.No_Case and then C in 65 .. 90 then
                     R := R or Range_Set (C + 32, C + 32);
                  elsif E.No_Case and then C in 97 .. 122 then
                     R := R or Range_Set (C - 32, C - 32);
                  end if;
                  return R;
               end;
            end;
         when Name =>
            declare
               J : constant Natural := Find (Rules, To_String (E.Name));
            begin
               if J = 0 or else Rules (J).Jet_Code /= Null_Unbounded_String
               then
                  return Any_Set;
               end if;
               return First (J);
            end;
         when Group =>
            declare
               S : Cp_Set;
               N : Boolean;
            begin
               Seq_First (Rules, Nullable, First, E.Items, 1,
                          Natural (E.Items.Length), S, N);
               return S;
            end;
         when Alt | Block =>
            return Empty;
      end case;
   end El_First;

   --  The first code points of V (From .. To), all its alternatives, and
   --  whether one can match nothing.
   procedure Seq_First
     (Rules : Rule_Vectors.Vector; Nullable : Flags; First : Set_Array;
      V : Element_Vectors.Vector; From, To : Natural;
      Set : out Cp_Set; Is_Null : out Boolean)
   is
      Branch_Set  : Cp_Set;
      Branch_Open : Boolean := True;   --  every element so far can be skipped
   begin
      Set := Empty;
      Is_Null := False;
      for I in From .. To + 1 loop
         if I > To or else V (I).Kind = Alt then
            if Branch_Open then
               Is_Null := True;
            end if;
            Set := Set or Branch_Set;
            Branch_Set := Empty;
            Branch_Open := True;
         elsif Branch_Open then
            Branch_Set := Branch_Set or El_First (Rules, Nullable, First, V (I));
            if not El_Nullable (Rules, Nullable, V (I)) then
               Branch_Open := False;
            end if;
         end if;
      end loop;
   end Seq_First;

   --  ---------------------------------------------------------------------
   --  Two code points
   --  ---------------------------------------------------------------------

   function Subset (X, Y : Cp_Set) return Boolean is
     (if Y.Any then True
      elsif X.Any then False
      else Range_Vectors."=" (Meet (X, Y).Ranges, X.Ranges)
           and then (not X.Eoi or else Y.Eoi));

   --  Add the pair unless an earlier one already holds it.
   procedure Add_Pair (V : in out Pair_Vectors.Vector; A, B : Cp_Set) is
   begin
      if Is_Empty (A) or else Is_Empty (B) then
         return;
      end if;
      for P of V loop
         if Subset (A, P.A) and then Subset (B, P.B) then
            return;
         end if;
      end loop;
      V.Append (Pair'(A => A, B => B));
   end Add_Pair;

   function First_All (Y : Leading) return Cp_Set is
      R : Cp_Set := Y.Singles;
   begin
      for P of Y.Pairs loop
         R := R or P.A;
      end loop;
      return R;
   end First_All;

   function Union (X, Y : Leading) return Leading is
      R : Leading := X;
   begin
      R.Singles := X.Singles or Y.Singles;
      for P of Y.Pairs loop
         Add_Pair (R.Pairs, P.A, P.B);
      end loop;
      R.Null_Ok := X.Null_Ok or else Y.Null_Ok;
      return R;
   end Union;

   function Concat (X, Y : Leading) return Leading is
      R : Leading;
   begin
      if Y.Null_Ok then
         R.Singles := X.Singles;
      end if;
      if X.Null_Ok then
         R.Singles := R.Singles or Y.Singles;
      end if;
      for P of X.Pairs loop
         Add_Pair (R.Pairs, P.A, P.B);
      end loop;
      Add_Pair (R.Pairs, X.Singles, First_All (Y));
      if X.Null_Ok then
         for P of Y.Pairs loop
            Add_Pair (R.Pairs, P.A, P.B);
         end loop;
      end if;
      R.Null_Ok := X.Null_Ok and then Y.Null_Ok;
      return R;
   end Concat;

   function Covered (N, O : Leading) return Boolean is
   begin
      if not Subset (N.Singles, O.Singles)
        or else (N.Null_Ok and then not O.Null_Ok)
      then
         return False;
      end if;
      for P of N.Pairs loop
         if not (for some Q of O.Pairs =>
                   Subset (P.A, Q.A) and then Subset (P.B, Q.B))
         then
            return False;
         end if;
      end loop;
      return True;
   end Covered;

   function Any_Leading return Leading is
      R : Leading;
   begin
      R.Singles := Any_Set;
      R.Pairs.Append (Pair'(A => Any_Set, B => Any_Set));
      return R;
   end Any_Leading;

   --  A literal's code points, one set each (both cases of a %i letter).
   function Literal_Leading (E : Element_Access) return Leading is
      S : constant String := To_String (E.Lit);
      R : Leading;
      I : Natural := S'First;
      Cs : array (1 .. 2) of Cp_Set;
      N  : Natural := 0;
   begin
      if S'Length = 0 then
         R.Null_Ok := True;
         return R;
      end if;
      while I <= S'Last and then N < 2 loop
         declare
            B : constant Natural := Character'Pos (S (I));
            L : constant Natural :=
              (if B < 16#80# then 1 elsif B < 16#E0# then 2
               elsif B < 16#F0# then 3 else 4);
            C : constant Natural := First_Cp (S (I .. S'Last));
            X : Cp_Set := Range_Set (C, C);
         begin
            if E.No_Case and then C in 65 .. 90 then
               X := X or Range_Set (C + 32, C + 32);
            elsif E.No_Case and then C in 97 .. 122 then
               X := X or Range_Set (C - 32, C - 32);
            end if;
            N := N + 1;
            Cs (N) := X;
            I := I + L;
         end;
      end loop;
      if N = 1 and then I > S'Last then
         R.Singles := Cs (1);
      else
         R.Pairs.Append (Pair'(A => Cs (1), B => Cs (2)));
      end if;
      return R;
   end Literal_Leading;

   function Seq_Leading
     (Rules : Rule_Vectors.Vector; Lead : Leading_Array;
      V : Element_Vectors.Vector; From, To : Natural) return Leading;

   function El_Leading
     (Rules : Rule_Vectors.Vector; Lead : Leading_Array;
      E : Element_Access) return Leading
   is
      Base : Leading;
   begin
      case E.Kind is
         when Char_Range =>
            Base.Singles := Range_Set (E.Lo, E.Hi);
         when Literal =>
            Base := Literal_Leading (E);
         when Name =>
            declare
               J : constant Natural := Find (Rules, To_String (E.Name));
            begin
               if J = 0 or else Rules (J).Jet_Code /= Null_Unbounded_String
               then
                  Base := Any_Leading;
               else
                  Base := Lead (J);
               end if;
            end;
         when Group =>
            Base := Seq_Leading
              (Rules, Lead, E.Items, 1, Natural (E.Items.Length));
         when Alt | Block =>
            Base.Null_Ok := True;
            return Base;
      end case;
      if E.Max = 0 then
         return Leading'(Null_Ok => True, others => <>);
      elsif E.Max = 1 then
         Base.Null_Ok := Base.Null_Ok or else E.Min = 0;
         return Base;
      end if;
      --  Repeated: one iteration, and two.  More add no new first two code
      --  points.
      declare
         Twice  : constant Leading := Concat (Base, Base);
         Result : Leading :=
           (if E.Min >= 2 then Twice else Union (Base, Twice));
      begin
         if E.Min = 0 then
            Result.Null_Ok := True;
         end if;
         return Result;
      end;
   end El_Leading;

   function Seq_Leading
     (Rules : Rule_Vectors.Vector; Lead : Leading_Array;
      V : Element_Vectors.Vector; From, To : Natural) return Leading
   is
      Result : Leading;
      Branch : Leading := (Null_Ok => True, others => <>);   --  the empty match
   begin
      for I in From .. To + 1 loop
         if I > To or else V (I).Kind = Alt then
            Result := Union (Result, Branch);
            Branch := Leading'(Null_Ok => True, others => <>);
         else
            Branch := Concat (Branch, El_Leading (Rules, Lead, V (I)));
         end if;
      end loop;
      return Result;
   end Seq_Leading;

   function Follow_After
     (A : Analysis; Rules : Rule_Vectors.Vector;
      V : Element_Vectors.Vector; B : Bounds; P : Positive;
      Follow_Branch : Cp_Set) return Cp_Set
   is
      Result    : Cp_Set := Empty;
      Rest_Null : Boolean := True;
   begin
      for Q in P + 1 .. B.Last loop
         Result := Result or El_First (Rules, A.Nullable, A.First, V (Q));
         if not El_Nullable (Rules, A.Nullable, V (Q)) then
            Rest_Null := False;
            exit;
         end if;
      end loop;
      if Rest_Null then
         Result := Result or Follow_Branch;
      end if;
      if V (P).Max /= 1 then
         Result := Result or El_First (Rules, A.Nullable, A.First, V (P));
      end if;
      return Result;
   end Follow_After;

   function Analyze (Rules : Rule_Vectors.Vector) return Analysis is
      N       : constant Natural := Natural (Rules.Length);
      R       : Analysis (N);
      Changed : Boolean := True;

      procedure Propagate (V : Element_Vectors.Vector; Follow_Branch : Cp_Set)
      is
      begin
         for B of Branches (V) loop
            for P in B.First .. B.Last loop
               declare
                  E : constant Element_Access := V (P);
               begin
                  if E.Kind = Name then
                     declare
                        J : constant Natural := Find (Rules, To_String (E.Name));
                     begin
                        if J /= 0 then
                           declare
                              U : constant Cp_Set :=
                                R.Follow (J)
                                or Follow_After (R, Rules, V, B, P,
                                                 Follow_Branch);
                           begin
                              if U /= R.Follow (J) then
                                 R.Follow (J) := U;
                                 Changed := True;
                              end if;
                           end;
                        end if;
                     end;
                  elsif E.Kind = Group then
                     Propagate (E.Items,
                                Follow_After (R, Rules, V, B, P, Follow_Branch));
                  end if;
               end;
            end loop;
         end loop;
      end Propagate;
   begin
      R.Nullable := Nullable_Set (Rules);
      R.First := [others => Empty];
      R.Follow := [others => Empty];
      while Changed loop
         Changed := False;
         for I in 1 .. N loop
            declare
               S : Cp_Set;
               Z : Boolean;
            begin
               if Rules (I).Jet_Code /= Null_Unbounded_String then
                  S := Any_Set;
               else
                  Seq_First (Rules, R.Nullable, R.First, Rules (I).Pattern, 1,
                             Natural (Rules (I).Pattern.Length), S, Z);
               end if;
               if S /= R.First (I) then
                  R.First (I) := S;
                  Changed := True;
               end if;
            end;
         end loop;
      end loop;
      Changed := True;
      while Changed loop
         Changed := False;
         for I in 1 .. N loop
            declare
               L : constant Leading :=
                 (if Rules (I).Jet_Code /= Null_Unbounded_String
                  then Any_Leading
                  else Seq_Leading (Rules, R.Lead, Rules (I).Pattern, 1,
                                    Natural (Rules (I).Pattern.Length)));
            begin
               if not Covered (L, R.Lead (I)) then
                  R.Lead (I) := Union (R.Lead (I), L);
                  Changed := True;
               end if;
            end;
         end loop;
      end loop;
      if N >= 1 then
         R.Follow (1).Eoi := True;
      end if;
      Changed := True;
      while Changed loop
         Changed := False;
         for I in 1 .. N loop
            if Rules (I).Jet_Code = Null_Unbounded_String then
               Propagate (Rules (I).Pattern, R.Follow (I));
            end if;
         end loop;
      end loop;
      return R;
   end Analyze;

   --  ---------------------------------------------------------------------
   --  The check
   --  ---------------------------------------------------------------------

   --  A branch, as a message names it: its first element, and `...` if more.
   function Describe (V : Element_Vectors.Vector; B : Bounds) return String is

      function Group_Text (E : Element_Access) return String is
         Inner : constant Bounds_Vectors.Vector := Branches (E.Items);
         Open  : constant String := (if E.Min = 0 then "[ " else "( ");
         Close : constant String := (if E.Min = 0 then " ]" else " )");
      begin
         if Inner.Is_Empty or else Inner (1).Last < Inner (1).First then
            return Open & "..." & Close;
         end if;
         declare
            F : constant Element_Access := E.Items (Inner (1).First);
            T : constant String :=
              (case F.Kind is
                  when Name    => To_String (F.Name),
                  when Literal => """" & To_String (F.Lit) & """",
                  when others  => "...");
         begin
            return Open & T & " ..." & Close;
         end;
      end Group_Text;

   begin
      if B.Last < B.First then
         return "(nothing)";
      end if;
      declare
         E : constant Element_Access := V (B.First);
         D : constant String :=
           (case E.Kind is
               when Name       => To_String (E.Name),
               when Literal    => """" & To_String (E.Lit) & """",
               when Char_Range => "%x" & Hex (E.Lo)
                                  & (if E.Hi /= E.Lo then "-" & Hex (E.Hi)
                                     else ""),
               when Group      => Group_Text (E),
               when others     => "...");
      begin
         return D & (if B.Last > B.First then " ..." else "");
      end;
   end Describe;

   procedure Check_Choice
     (A : Analysis; Rules : Rule_Vectors.Vector;
      V : Element_Vectors.Vector; Follow_Here : Cp_Set;
      Ok : out Boolean;
      Message : out Unbounded_String;
      Nullable_Branch : out Natural)
   is
      Bs     : constant Bounds_Vectors.Vector := Branches (V);
      N      : constant Natural := Natural (Bs.Length);
      Firsts : Set_Array (1 .. N);
      Nulls  : Flags (1 .. N);

      function D (K : Positive) return String is
        ("`" & Describe (V, Bs (K)) & "`");
   begin
      Ok := True;
      Message := Null_Unbounded_String;
      Nullable_Branch := 0;
      for K in 1 .. N loop
         Seq_First (Rules, A.Nullable, A.First, V, Bs (K).First, Bs (K).Last,
                    Firsts (K), Nulls (K));
      end loop;
      for K in 1 .. N loop
         if Nulls (K) then
            if Nullable_Branch /= 0 then
               Ok := False;
               Message := To_Unbounded_String
                 (D (Nullable_Branch) & " and " & D (K)
                  & " can both match nothing");
               return;
            end if;
            Nullable_Branch := K;
         end if;
      end loop;
      --  Two code points, when one is not enough.  A branch that matches one
      --  code point is followed by what follows the choice.
      declare
         Pairs : array (1 .. N) of Pair_Vectors.Vector;
         Known : array (1 .. N) of Boolean := [others => False];

         procedure Need (K : Positive) is
         begin
            if not Known (K) then
               declare
                  L : constant Leading :=
                    Seq_Leading (Rules, A.Lead, V, Bs (K).First, Bs (K).Last);
               begin
                  Pairs (K) := L.Pairs;
                  Add_Pair (Pairs (K), L.Singles, Follow_Here);
               end;
               Known (K) := True;
            end if;
         end Need;
      begin
         for I in 1 .. N loop
            for J in I + 1 .. N loop
               declare
                  M : constant Cp_Set := Meet (Firsts (I), Firsts (J));
               begin
                  if not Is_Empty (M) then
                     Need (I);
                     Need (J);
                     declare
                        Clash : Boolean := False;
                        MA, MB : Cp_Set;
                     begin
                        for P of Pairs (I) loop
                           for Q of Pairs (J) loop
                              MA := Meet (P.A, Q.A);
                              MB := Meet (P.B, Q.B);
                              if not Is_Empty (MA) and then not Is_Empty (MB)
                              then
                                 Clash := True;
                                 Message := To_Unbounded_String
                                   (D (I) & " and " & D (J)
                                    & " can both begin with " & Image (MA)
                                    & " then " & Image (MB));
                                 exit;
                              end if;
                           end loop;
                           exit when Clash;
                        end loop;
                        if Clash then
                           Ok := False;
                           return;
                        end if;
                     end;
                  end if;
               end;
            end loop;
         end loop;
      end;
      if Nullable_Branch /= 0 then
         for J in 1 .. N loop
            if J /= Nullable_Branch then
               declare
                  M : constant Cp_Set := Meet (Firsts (J), Follow_Here);
               begin
                  if not Is_Empty (M) then
                     Ok := False;
                     Message := To_Unbounded_String
                       (D (Nullable_Branch) & " can match nothing, and "
                        & Image (M) & " can both follow the choice and begin "
                        & D (J));
                     return;
                  end if;
               end;
            end if;
         end loop;
      end if;
   end Check_Choice;

end HBNF_Lookahead;
