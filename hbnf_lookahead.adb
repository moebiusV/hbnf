pragma Ada_2022;

with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Environment_Variables;
with Ada.Text_IO;
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Ordered_Sets;
with Ada.Strings.Hash;

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

   function Range_Count (S : Cp_Set) return Natural is
     (Natural (S.Ranges.Length));
   function Range_Lo (S : Cp_Set; K : Positive) return Natural is
     (S.Ranges (K).Lo);
   function Range_Hi (S : Cp_Set; K : Positive) return Natural is
     (S.Ranges (K).Hi);
   function Has_Eoi (S : Cp_Set) return Boolean is (S.Eoi);
   function Has_Any (S : Cp_Set) return Boolean is (S.Any);

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

   --  A rule by name; the names are kept in a table made again when the number
   --  of rules is not the one it was made for (see Index_Of in hbnf_grammar.adb).
   package Index_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Natural);
   Index     : Index_Maps.Map;
   Index_Len : Natural := 0;

   function Find (Rules : Rule_Vectors.Vector; Name : String) return Natural is
      N : constant Natural := Natural (Rules.Length);
   begin
      if N /= Index_Len then
         Index.Clear;
         for I in 1 .. N loop
            declare
               Nm : constant String := To_String (Rules (I).Name);
            begin
               if not Index.Contains (Nm) then
                  Index.Insert (Nm, I);
               end if;
            end;
         end loop;
         Index_Len := N;
      end if;
      declare
         C : constant Index_Maps.Cursor := Index.Find (Name);
      begin
         if Index_Maps.Has_Element (C) then
            declare
               J : constant Natural := Index_Maps.Element (C);
            begin
               if J <= N and then To_String (Rules (J).Name) = Name then
                  return J;
               end if;
            end;
         end if;
      end;
      for I in 1 .. N loop
         if To_String (Rules (I).Name) = Name then
            Index_Len := 0;
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
         when Bit_Field =>
            null;     --  a rule with bit fields never reaches here (Split_Wire)
         when Negation =>
            null;   --  resolved into a rule of ranges before this runs
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
         when Bit_Field =>
            null;     --  a rule with bit fields never reaches here (Split_Wire)
         when Negation =>
            null;   --  resolved into a rule of ranges before this runs
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

   function First_Of
     (A : Analysis; Rules : Rule_Vectors.Vector; E : Element_Access)
      return Cp_Set is
     (El_First (Rules, A.Nullable, A.First, E));

   procedure Branch_First
     (A : Analysis; Rules : Rule_Vectors.Vector;
      V : Element_Vectors.Vector; B : Bounds;
      Set : out Cp_Set; Is_Null : out Boolean) is
   begin
      Seq_First (Rules, A.Nullable, A.First, V, B.First, B.Last, Set, Is_Null);
   end Branch_First;

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
                  when Name    => Spelled (To_String (F.Name)),
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
               when Name       => Spelled (To_String (E.Name)),
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

   --  ---------------------------------------------------------------------
   --  Alternatives as automata
   --  ---------------------------------------------------------------------

   package Int_Vectors is new Ada.Containers.Vectors (Positive, Positive);
   package Cp_Vectors is new Ada.Containers.Vectors (Positive, Natural);
   package State_Sets is new Ada.Containers.Ordered_Sets (Positive);
   package Cp_Sets is new Ada.Containers.Ordered_Sets (Natural);
   package Key_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (String, Ada.Strings.Hash, "=");

   Max_Code_Point : constant := 16#10FFFF#;
   Max_States     : constant := 2_000;   --  past this a rule is "any text"
   Max_Nodes      : constant := 400;   --  pairs of state sets searched

   Approximated : Boolean := False;
   --  Set by Build when the automaton is larger than the text it stands for
   --  (a jet, a recursion, a bounded repetition past 32): Token_Dfa refuses.
   Why_Approximated : Unbounded_String;

   type Edge is record
      Lo, Hi : Natural;
      To     : Positive;
   end record;

   package Edge_Vectors is new Ada.Containers.Vectors (Positive, Edge);

   type State is record
      Edges : Edge_Vectors.Vector;
      Eps   : Int_Vectors.Vector;
   end record;

   package State_Vectors is new Ada.Containers.Vectors (Positive, State);
   package Bool_Vectors is new Ada.Containers.Vectors (Positive, Boolean);

   type Automaton is record
      States        : State_Vectors.Vector;
      Start, Final : Positive := 1;
      Live          : Bool_Vectors.Vector;   --  can reach Final
   end record;

   function Decode (S : String) return Cp_Vectors.Vector is
      R : Cp_Vectors.Vector;
      I : Natural := S'First;
   begin
      while I <= S'Last loop
         declare
            B : constant Natural := Character'Pos (S (I));
            L : constant Natural :=
              (if B < 16#80# then 1 elsif B < 16#E0# then 2
               elsif B < 16#F0# then 3 else 4);
         begin
            R.Append (First_Cp (S (I .. Natural'Min (S'Last, I + L - 1))));
            I := I + L;
         end;
      end loop;
      return R;
   end Decode;

   --  The text V (From .. To) matches, as an automaton.  A rule that refers
   --  to itself, a jet, a built-in scanner or an unknown name matches any
   --  text, and a repetition is read for at most 32 copies and then without
   --  limit: both only make the language larger, which only makes a union look
   --  harder to compile.
   function Build
     (Rules : Rule_Vectors.Vector; Owner : Natural;
      V : Element_Vectors.Vector; From, To : Natural;
      Opaque : Boolean := False) return Automaton
   is
      M     : Automaton;
      Stack : Order_Vectors.Vector;

      type Frag is record
         S, E : Positive;
      end record;

      function New_State return Positive is
         X : State;
      begin
         M.States.Append (X);
         return Positive (M.States.Length);
      end New_State;

      procedure Eps (A, B : Positive) is
      begin
         M.States.Reference (A).Eps.Append (B);
      end Eps;

      procedure Edge_To (A : Positive; Lo, Hi : Natural; B : Positive) is
      begin
         M.States.Reference (A).Edges.Append
           (Edge'(Lo => Lo, Hi => Hi, To => B));
      end Edge_To;

      function Empty_Frag return Frag is
         S : constant Positive := New_State;
      begin
         return (S, S);
      end Empty_Frag;

      function Any_Run return Frag is
         S : constant Positive := New_State;
      begin
         if Opaque then
            --  Matches nothing: no way from here to the end.
            return (S, New_State);
         end if;
         Approximated := True;
         Edge_To (S, 0, Max_Code_Point, S);
         return (S, S);
      end Any_Run;

      function Seq (V : Element_Vectors.Vector; From, To : Natural;
                    Depth : Natural) return Frag;

      function Lit_Frag (E : Element_Access) return Frag is
         First : constant Positive := New_State;
         Cur   : Positive := First;
      begin
         for C of Decode (To_String (E.Lit)) loop
            declare
               N : constant Positive := New_State;
            begin
               Edge_To (Cur, C, C, N);
               if E.No_Case and then C in 65 .. 90 then
                  Edge_To (Cur, C + 32, C + 32, N);
               elsif E.No_Case and then C in 97 .. 122 then
                  Edge_To (Cur, C - 32, C - 32, N);
               end if;
               Cur := N;
            end;
         end loop;
         return (First, Cur);
      end Lit_Frag;

      function One (E : Element_Access; Depth : Natural) return Frag is
      begin
         if Natural (M.States.Length) > Max_States then
            return Any_Run;
         end if;
         case E.Kind is
            when Literal =>
               return Lit_Frag (E);
            when Char_Range =>
               declare
                  S : constant Positive := New_State;
                  N : constant Positive := New_State;
               begin
                  Edge_To (S, E.Lo, E.Hi, N);
                  return (S, N);
               end;
            when Name =>
               declare
                  J : constant Natural := Find (Rules, To_String (E.Name));
               begin
                  if J = 0 or else Depth > 30
                    or else Rules (J).Jet_Code /= Null_Unbounded_String
                    or else (for some X of Stack => X = J)
                  then
                     Why_Approximated := To_Unbounded_String
                       ((if J = 0 then "`" & To_String (E.Name)
                                       & "` is not a rule"
                         elsif Rules (J).Jet_Code /= Null_Unbounded_String
                         then "`" & To_String (E.Name)
                              & "` is code (a built-in scanner or %scan), "
                              & "not text hbnf can see into"
                         else "`" & To_String (E.Name) & "` refers to itself"));
                     return Any_Run;
                  end if;
                  Stack.Append (J);
                  declare
                     F : constant Frag :=
                       Seq (Rules (J).Pattern, 1,
                            Natural (Rules (J).Pattern.Length), Depth + 1);
                  begin
                     Stack.Delete_Last;
                     return F;
                  end;
               end;
            when Group =>
               return Seq (E.Items, 1, Natural (E.Items.Length), Depth + 1);
            when Alt | Block =>
               return Empty_Frag;
            when Bit_Field =>
               null;     --  a rule with bit fields never reaches here (Split_Wire)
            when Negation =>
               null;   --  resolved into a rule of ranges before this runs
         end case;
      end One;

      function Rep (E : Element_Access; Depth : Natural) return Frag is
         Min : constant Natural := Natural'Min (E.Min, 32);
         Max : constant Integer :=
           (if E.Max < 0 or else E.Max > 32 or else E.Min > 32 then -1
            else E.Max);
         S   : Positive;
         Cur : Positive;
      begin
         if E.Min = 1 and then E.Max = 1 then
            return One (E, Depth);
         end if;
         if E.Min > 32 or else E.Max > 32 then
            Approximated := True;
            Why_Approximated := To_Unbounded_String
              ("a repetition with a bound past 32 (write it as `n*` and a "
               & "check, or split it)");
         end if;
         S := New_State;
         Cur := S;
         for I in 1 .. Min loop
            declare
               F : constant Frag := One (E, Depth);
            begin
               Eps (Cur, F.S);
               Cur := F.E;
            end;
         end loop;
         if Max = -1 then
            declare
               Lp  : constant Positive := New_State;
               Fin : constant Positive := New_State;
               F   : constant Frag := One (E, Depth);
            begin
               Eps (Cur, Lp);
               Eps (Lp, Fin);
               Eps (Lp, F.S);
               Eps (F.E, Lp);
               Cur := Fin;
            end;
         elsif Max > Min then
            declare
               Fin : constant Positive := New_State;
            begin
               for I in Min + 1 .. Max loop
                  declare
                     F : constant Frag := One (E, Depth);
                  begin
                     Eps (Cur, Fin);
                     Eps (Cur, F.S);
                     Cur := F.E;
                  end;
               end loop;
               Eps (Cur, Fin);
               Cur := Fin;
            end;
         end if;
         return (S, Cur);
      end Rep;

      function Chain (V : Element_Vectors.Vector; A, Z : Natural;
                      Depth : Natural) return Frag is
         S   : constant Positive := New_State;
         Cur : Positive := S;
      begin
         for I in A .. Z loop
            declare
               F : constant Frag := Rep (V (I), Depth);
            begin
               Eps (Cur, F.S);
               Cur := F.E;
            end;
         end loop;
         return (S, Cur);
      end Chain;

      function Seq (V : Element_Vectors.Vector; From, To : Natural;
                    Depth : Natural) return Frag is
         S  : Positive;
         E  : Positive;
         St : Natural := From;
      begin
         if not (for some I in From .. To => V (I).Kind = Alt) then
            return Chain (V, From, To, Depth);
         end if;
         S := New_State;
         E := New_State;
         for I in From .. To + 1 loop
            if I > To or else V (I).Kind = Alt then
               declare
                  F : constant Frag := Chain (V, St, I - 1, Depth);
               begin
                  Eps (S, F.S);
                  Eps (F.E, E);
               end;
               St := I + 1;
            end if;
         end loop;
         return (S, E);
      end Seq;

      Whole : Frag;
   begin
      if Owner /= 0 then
         Stack.Append (Owner);
      end if;
      Whole := Seq (V, From, To, 0);
      M.Start := Whole.S;
      M.Final := Whole.E;
      --  Live: the states from which the accepting one can be reached.
      declare
         N   : constant Natural := Natural (M.States.Length);
         Rev : array (1 .. N) of Int_Vectors.Vector;
         Todo : Int_Vectors.Vector;
      begin
         for S in 1 .. N loop
            M.Live.Append (False);
            for T of M.States (S).Eps loop
               Rev (T).Append (S);
            end loop;
            for X of M.States (S).Edges loop
               Rev (X.To).Append (S);
            end loop;
         end loop;
         M.Live.Replace_Element (M.Final, True);
         Todo.Append (M.Final);
         while not Todo.Is_Empty loop
            declare
               X : constant Positive := Todo.Last_Element;
            begin
               Todo.Delete_Last;
               for P of Rev (X) loop
                  if not M.Live (P) then
                     M.Live.Replace_Element (P, True);
                     Todo.Append (P);
                  end if;
               end loop;
            end;
         end loop;
      end;
      return M;
   end Build;

   --  The live states reachable from S without reading anything.
   function Closure (A : Automaton; S : State_Sets.Set) return State_Sets.Set
   is
      R    : State_Sets.Set;
      Todo : Int_Vectors.Vector;
   begin
      for X of S loop
         if A.Live (X) and then not R.Contains (X) then
            R.Insert (X);
            Todo.Append (X);
         end if;
      end loop;
      while not Todo.Is_Empty loop
         declare
            X : constant Positive := Todo.Last_Element;
         begin
            Todo.Delete_Last;
            for T of A.States (X).Eps loop
               if A.Live (T) and then not R.Contains (T) then
                  R.Insert (T);
                  Todo.Append (T);
               end if;
            end loop;
         end;
      end loop;
      return R;
   end Closure;

   --  The states reached from S by reading the code point C.
   function Step (A : Automaton; S : State_Sets.Set; C : Natural)
     return State_Sets.Set
   is
      Next : State_Sets.Set;
   begin
      for X of S loop
         for E of A.States (X).Edges loop
            if E.Lo <= C and then C <= E.Hi and then A.Live (E.To) then
               Next.Include (E.To);
            end if;
         end loop;
      end loop;
      return Closure (A, Next);
   end Step;

   function Key (S : State_Sets.Set) return String is
      R : Unbounded_String;
   begin
      for X of S loop
         Append (R, Positive'Image (X));
      end loop;
      return To_String (R);
   end Key;

   --  Walking an automaton on sorted lists of states: what each state reaches
   --  without reading anything is worked out once, and the states a list of
   --  edges lead to are the union of those lists.
   package Clo_Vectors is new Ada.Containers.Vectors
     (Positive, Int_Vectors.Vector, Int_Vectors."=");
   package Nat_Vectors is new Ada.Containers.Vectors (Positive, Natural);
   package Int_Sorting is new Int_Vectors.Generic_Sorting;

   type Walker (A : access constant Automaton) is record
      Clo   : Clo_Vectors.Vector;
      Done  : Nat_Vectors.Vector;   --  1 once the state's closure is in Clo
      Stamp : Nat_Vectors.Vector;
      Gen   : Natural := 0;
   end record;

   --  The tables, empty: a state's closure is worked out when it is first asked for.
   procedure Init (W : in out Walker) is
      N : constant Natural := Natural (W.A.States.Length);
   begin
      W.Stamp.Clear;
      W.Clo.Clear;
      W.Done.Clear;
      for X in 1 .. N loop
         W.Stamp.Append (0);
         W.Clo.Append (Int_Vectors.Empty_Vector);
         W.Done.Append (0);
      end loop;
   end Init;

   --  What the state X reaches without reading anything, itself included.
   procedure Need_Clo (W : in out Walker; X : Positive) is
      Todo : Int_Vectors.Vector;
      R    : Int_Vectors.Vector;
   begin
      if W.Done (X) /= 0 then
         return;
      end if;
      W.Done.Replace_Element (X, 1);
      if not W.A.Live (X) then
         return;
      end if;
      --  The stamps of this walk are numbers above the ones Reach uses.
      W.Gen := W.Gen + 1;
      W.Stamp.Replace_Element (X, W.Gen);
      R.Append (X);
      Todo.Append (X);
      while not Todo.Is_Empty loop
         declare
            Y : constant Positive := Todo.Last_Element;
         begin
            Todo.Delete_Last;
            for T of W.A.States (Y).Eps loop
               if W.A.Live (T) and then W.Stamp (T) /= W.Gen then
                  W.Stamp.Replace_Element (T, W.Gen);
                  R.Append (T);
                  Todo.Append (T);
               end if;
            end loop;
         end;
      end loop;
      Int_Sorting.Sort (R);
      W.Clo.Replace_Element (X, R);
   end Need_Clo;

   type Edge_Ev is record
      Lo, Hi : Natural;
      To     : Positive;
   end record;
   package Ev_Lists is new Ada.Containers.Vectors (Positive, Edge_Ev);
   function Ev_Before (A, B : Edge_Ev) return Boolean is (A.Lo < B.Lo);
   package Ev_Sorting is new Ev_Lists.Generic_Sorting (Ev_Before);

   --  The edges out of the states of S that lead somewhere that can finish,
   --  by the code point they start at.
   function Edges_Of (W : Walker; S : Int_Vectors.Vector) return Ev_Lists.Vector
   is
      R : Ev_Lists.Vector;
   begin
      for X of S loop
         for E of W.A.States (X).Edges loop
            if W.A.Live (E.To) then
               R.Append (Edge_Ev'(E.Lo, E.Hi, E.To));
            end if;
         end loop;
      end loop;
      Ev_Sorting.Sort (R);
      return R;
   end Edges_Of;

   --  Where the edges Active lead, closed.
   function Reach (W : in out Walker; Active : Ev_Lists.Vector)
     return Int_Vectors.Vector
   is
      R : Int_Vectors.Vector;
   begin
      for V of Active loop
         Need_Clo (W, V.To);
      end loop;
      W.Gen := W.Gen + 1;
      for V of Active loop
         for Y of W.Clo (V.To) loop
            if W.Stamp (Y) /= W.Gen then
               W.Stamp.Replace_Element (Y, W.Gen);
               R.Append (Y);
            end if;
         end loop;
      end loop;
      Int_Sorting.Sort (R);
      return R;
   end Reach;

   --  Move the edges that cover the code point Lo into Active, and the ones that
   --  ended out of it; True when that changed it.
   procedure Advance
     (Evs : Ev_Lists.Vector; Nx : in out Positive; Active : in out Ev_Lists.Vector;
      Lo : Natural; Changed : out Boolean)
   is
      Kept : Ev_Lists.Vector;
   begin
      Changed := False;
      while Nx <= Natural (Evs.Length) and then Evs (Nx).Lo <= Lo loop
         Active.Append (Evs (Nx));
         Nx := Nx + 1;
         Changed := True;
      end loop;
      for V of Active loop
         if V.Hi >= Lo then
            Kept.Append (V);
         end if;
      end loop;
      if Natural (Kept.Length) /= Natural (Active.Length) then
         Changed := True;
      end if;
      Active := Kept;
   end Advance;

   function To_List (S : State_Sets.Set) return Int_Vectors.Vector is
      R : Int_Vectors.Vector;
   begin
      for X of S loop
         R.Append (X);
      end loop;
      return R;
   end To_List;

   function Has (S : Int_Vectors.Vector; X : Positive) return Boolean is
     (for some Y of S => Y = X);

   function List_Before (A, B : Int_Vectors.Vector) return Boolean is
   begin
      for I in 1 .. Natural'Min (Natural (A.Length), Natural (B.Length)) loop
         if A (I) /= B (I) then
            return A (I) < B (I);
         end if;
      end loop;
      return Natural (A.Length) < Natural (B.Length);
   end List_Before;

   --  Two lists of states, the places two automata have got to in the same text.
   type Pair is record
      S, B : Int_Vectors.Vector;
   end record;
   function Pair_Before (X, Y : Pair) return Boolean is
     (if Int_Vectors."=" (X.S, Y.S) then List_Before (X.B, Y.B)
      else List_Before (X.S, Y.S));
   package Pair_Sets is new Ada.Containers.Ordered_Sets (Pair, Pair_Before);

   function To_Set (V : Int_Vectors.Vector) return State_Sets.Set is
      R : State_Sets.Set;
   begin
      for X of V loop
         R.Include (X);
      end loop;
      return R;
   end To_Set;

   --  What the start state reaches without reading anything.
   function Start_Of (W : in out Walker; Start : Positive) return Int_Vectors.Vector is
   begin
      Need_Clo (W, Start);
      return W.Clo (Start);
   end Start_Of;

   --  Does Big match all the text Small does?
   function Includes_From
     (Big, Small : Automaton; Big_From, From : State_Sets.Set;
      Limit : Natural := Max_Nodes) return Boolean
   is
      package Pair_Vectors is new Ada.Containers.Vectors (Positive, Pair);

      WS : Walker (Small'Unrestricted_Access);
      WB : Walker (Big'Unrestricted_Access);

      Todo : Pair_Vectors.Vector;
      Seen : Pair_Sets.Set;
      Next : Positive := 1;

      procedure Add (S, B : Int_Vectors.Vector) is
         P : constant Pair := (S => S, B => B);
      begin
         if not Seen.Contains (P) then
            Seen.Insert (P);
            Todo.Append (P);
         end if;
      end Add;
   begin
      Init (WS);
      Init (WB);
      Add (To_List (From), To_List (Big_From));
      while Next <= Natural (Todo.Length) loop
         if Natural (Todo.Length) > Limit then
            return False;
         end if;
         declare
            N      : constant Pair := Todo (Next);
            Bounds : Cp_Sets.Set;
            Es     : constant Ev_Lists.Vector := Edges_Of (WS, N.S);
            Eb     : constant Ev_Lists.Vector := Edges_Of (WB, N.B);
            Ns     : Positive := 1;
            Nb     : Positive := 1;
            As, Ab : Ev_Lists.Vector;
            Ts, Tb : Int_Vectors.Vector;
         begin
            Next := Next + 1;
            if Has (N.S, Small.Final) and then not Has (N.B, Big.Final) then
               return False;
            end if;
            for E of Es loop
               Bounds.Include (E.Lo);
               Bounds.Include (E.Hi + 1);
            end loop;
            for E of Eb loop
               Bounds.Include (E.Lo);
               Bounds.Include (E.Hi + 1);
            end loop;
            declare
               C : Cp_Sets.Cursor := Bounds.First;
            begin
               while Cp_Sets.Has_Element (C) loop
                  declare
                     Lo : constant Natural := Cp_Sets.Element (C);
                     NC : constant Cp_Sets.Cursor := Cp_Sets.Next (C);
                     Cs, Cb : Boolean;
                  begin
                     exit when not Cp_Sets.Has_Element (NC);
                     C := NC;
                     Advance (Es, Ns, As, Lo, Cs);
                     Advance (Eb, Nb, Ab, Lo, Cb);
                     if Cs then
                        Ts := Reach (WS, As);
                     end if;
                     if Cb then
                        Tb := Reach (WB, Ab);
                     end if;
                     if not Ts.Is_Empty then
                        Add (Ts, Tb);
                     end if;
                  end;
               end loop;
            end;
         end;
      end loop;
      return True;
   end Includes_From;

   function Includes
     (Big, Small : Automaton; Limit : Natural := Max_Nodes) return Boolean
   is
      S0, B0 : State_Sets.Set;
   begin
      S0.Insert (Small.Start);
      B0.Insert (Big.Start);
      return Includes_From
        (Big, Small, Closure (Big, B0), Closure (Small, S0), Limit);
   end Includes;

   --  Search the text both automata read for a place where an alternative
   --  tried first takes input the second needed.  Two ways:
   --    - the first has matched all of some text and the second can match more
   --      of it: the first commits to the shorter text;
   --    - the second has matched all of some text and the first can read on,
   --      with a code point that can follow the choice: the first commits to
   --      the longer text, which the rest may not accept.
   --  Witness is the text up to there.
   --  With Greedy, EA is one repetition, EB what follows the repetitions and
   --  Whole more repetitions and then what follows: Found when EA has matched
   --  some text that EB, from its start, can also be in the middle of, and
   --  what is left of EB then is not something Whole could have matched, so
   --  taking that repetition loses text.
   procedure Hazard
     (EA, EB : Automaton; Follow : Cp_Set;
      Found : out Boolean; Witness : out Unbounded_String;
      Greedy : Boolean := False;
      Whole  : access constant Automaton := null)
   is
      type Node is record
         SA, SB : Int_Vectors.Vector;
         Parent : Natural;
         Cp     : Natural;
         Depth  : Natural;
      end record;
      package Node_Vectors is new Ada.Containers.Vectors (Positive, Node);

      Nodes : Node_Vectors.Vector;
      Seen  : Pair_Sets.Set;
      Next  : Positive := 1;
      WA    : Walker (EA'Unrestricted_Access);
      WB    : Walker (EB'Unrestricted_Access);

      --  Greedy: where the repetitions and the rest start, and whether the
      --  rest can match nothing.
      Whole_Start    : State_Sets.Set;
      Whole_Empty_Ok : Boolean := False;

      function Text (N : Positive) return String is
         Rev : Cp_Vectors.Vector;
         K   : Natural := N;
         R   : Unbounded_String;
      begin
         while K /= 0 and then Nodes (K).Depth > 0 loop
            Rev.Append (Nodes (K).Cp);
            K := Nodes (K).Parent;
         end loop;
         for I in reverse 1 .. Natural (Rev.Length) loop
            declare
               C : constant Natural := Rev (I);
            begin
               if C in 33 .. 126 then
                  Append (R, Character'Val (C));
               elsif C = 32 then
                  Append (R, " ");
               else
                  Append (R, "<U+" & Hex (C) & ">");
               end if;
            end;
         end loop;
         return To_String (R);
      end Text;

      procedure Add (SA, SB : Int_Vectors.Vector; Parent, Cp, Depth : Natural) is
         K : constant Pair := (S => SA, B => SB);
      begin
         if not Seen.Contains (K) then
            Seen.Insert (K);
            Nodes.Append
              (Node'(SA => SA, SB => SB, Parent => Parent, Cp => Cp,
                     Depth => Depth));
         end if;
      end Add;
   begin
      Found := False;
      Witness := Null_Unbounded_String;
      Init (WA);
      Init (WB);
      if Greedy then
         declare
            W0 : State_Sets.Set;
         begin
            W0.Insert (Whole.Start);
            Whole_Start := Closure (Whole.all, W0);
            Whole_Empty_Ok := Whole_Start.Contains (Whole.Final);
         end;
      end if;
      Add (Start_Of (WA, EA.Start), Start_Of (WB, EB.Start), 0, 0, 0);
      while Next <= Natural (Nodes.Length) loop
         if Natural (Nodes.Length) > Max_Nodes then
            Found := True;
            Witness := To_Unbounded_String ("...");
            return;
         end if;
         declare
            N       : constant Node := Nodes (Next);
            Here    : constant Positive := Next;
            Bounds  : Cp_Sets.Set;
            A_Done  : constant Boolean := Has (N.SA, EA.Final);
            B_Done  : constant Boolean := Has (N.SB, EB.Final);
            Ea_Evs  : constant Ev_Lists.Vector := Edges_Of (WA, N.SA);
            Eb_Evs  : constant Ev_Lists.Vector := Edges_Of (WB, N.SB);
            Na, Nb  : Positive := 1;
            Aa, Ab  : Ev_Lists.Vector;
            Xa, Xb  : Int_Vectors.Vector;
         begin
            Next := Next + 1;
            --  R can end right where a repetition ends: greedy takes it, and
            --  nothing is left for R unless R can match nothing.
            if Greedy and then N.Depth > 0 and then A_Done
              and then Has (N.SB, EB.Final)
              and then not Whole_Empty_Ok
            then
               Found := True;
               Witness := To_Unbounded_String (Text (Here));
               return;
            end if;
            for E of Ea_Evs loop
               Bounds.Include (E.Lo);
               Bounds.Include (E.Hi + 1);
            end loop;
            for E of Eb_Evs loop
               Bounds.Include (E.Lo);
               Bounds.Include (E.Hi + 1);
            end loop;
            declare
               C : Cp_Sets.Cursor := Bounds.First;
            begin
               while Cp_Sets.Has_Element (C) loop
                  declare
                     Lo : constant Natural := Cp_Sets.Element (C);
                     NC : constant Cp_Sets.Cursor := Cp_Sets.Next (C);
                  begin
                     exit when not Cp_Sets.Has_Element (NC);
                     C := NC;
                     declare
                        Hi : constant Natural := Cp_Sets.Element (NC) - 1;
                        Ca, Cb : Boolean;
                     begin
                        Advance (Ea_Evs, Na, Aa, Lo, Ca);
                        Advance (Eb_Evs, Nb, Ab, Lo, Cb);
                        if Ca then
                           Xa := Reach (WA, Aa);
                        end if;
                        if Cb then
                           Xb := Reach (WB, Ab);
                        end if;
                     declare
                        TA : Int_Vectors.Vector renames Xa;
                        TB : Int_Vectors.Vector renames Xb;
                     begin
                        --  A repetition that could go on does (greedy), so
                        --  what R still needs starts with a code point the
                        --  repetition cannot take; if what is left of R from
                        --  there is not something more repetitions and R
                        --  could have matched, taking this repetition lost
                        --  text.
                        if Greedy and then N.Depth > 0 and then A_Done
                          and then TA.Is_Empty and then not TB.Is_Empty
                          and then not Includes_From
                                         (Whole.all, EB,
                                          Step (Whole.all, Whole_Start, Lo),
                                          To_Set (TB))
                        then
                           Found := True;
                           Witness := To_Unbounded_String
                             (Text (Here) & Cp_Image (Lo));
                           return;
                        end if;
                        --  The earlier alternative stops here, with L able to go
                        --  on, only if it cannot take the next code point
                        --  itself: a repetition in it takes as many as match.
                        if not Greedy and then A_Done and then TA.Is_Empty
                          and then not TB.Is_Empty
                        then
                           Found := True;
                           Witness := To_Unbounded_String (Text (Here));
                           return;
                        end if;
                        if not Greedy and then B_Done and then not TA.Is_Empty
                          and then not Is_Empty
                                         (Meet (Range_Set (Lo, Hi), Follow))
                        then
                           Found := True;
                           Witness := To_Unbounded_String (Text (Here));
                           return;
                        end if;
                        if not TA.Is_Empty and then not TB.Is_Empty then
                           Add (TA, TB, Here, Lo, N.Depth + 1);
                        end if;
                     end;
                     end;
                  end;
               end loop;
            end;
         end;
      end loop;
   end Hazard;

   procedure Greedy_Overlap
     (Rules : Rule_Vectors.Vector; Owner : Natural; E : Element_Access;
      V : Element_Vectors.Vector; From, To : Natural;
      Found : out Boolean;
      Witness : out Unbounded_String)
   is
      One_Copy  : constant Element_Access :=
        new HBNF_Grammar.Element'(E.all);
      Star_Copy : constant Element_Access :=
        new HBNF_Grammar.Element'(E.all);
      Single    : Element_Vectors.Vector;
      Starred   : Element_Vectors.Vector;
   begin
      One_Copy.Min := 1;
      One_Copy.Max := 1;
      Single.Append (One_Copy);
      Star_Copy.Min := 0;
      Star_Copy.Max := -1;
      Starred.Append (Star_Copy);
      for I in From .. To loop
         Starred.Append (V (I));
      end loop;
      declare
         Whole : aliased constant Automaton :=
           Build (Rules, Owner, Starred, 1, Natural (Starred.Length),
                  Opaque => True);
      begin
         Hazard (Build (Rules, Owner, Single, 1, 1, Opaque => True),
                 Build (Rules, Owner, V, From, To, Opaque => True),
                 Empty, Found, Witness, Greedy => True,
                 Whole => Whole'Access);
      end;
   end Greedy_Overlap;

   procedure Check_Choice
     (A : Analysis; Rules : Rule_Vectors.Vector; Owner : Natural;
      V : Element_Vectors.Vector; Follow_Here : Cp_Set;
      Ok : out Boolean;
      Message : out Unbounded_String;
      Order : out Order_Vectors.Vector)
   is
      Bs     : constant Bounds_Vectors.Vector := Branches (V);
      N      : constant Natural := Natural (Bs.Length);
      Firsts : Set_Array (1 .. N);
      Nulls  : Flags (1 .. N);

      Auto  : array (1 .. N) of Automaton;
      Built : Flags (1 .. N) := [others => False];

      function D (K : Positive) return String is
        ("`" & Describe (V, Bs (K)) & "`");

      procedure Need (K : Positive) is
      begin
         if not Built (K) then
            Auto (K) := Build (Rules, Owner, V, Bs (K).First, Bs (K).Last);
            Built (K) := True;
         end if;
      end Need;

      --  Does I, tried before J, take input J needed?
      function Shadows
        (I, J : Positive; Where : out Unbounded_String) return Boolean
      is
         Found : Boolean;
         Text  : Unbounded_String;
      begin
         if not Nulls (I) and then not Nulls (J)
           and then Is_Empty (Meet (Firsts (I), Firsts (J)))
         then
            return False;
         end if;
         Need (I);
         Need (J);
         Hazard (Auto (I), Auto (J), Follow_Here, Found, Text);
         if Found then
            Where := Text;
         end if;
         return Found;
      end Shadows;

      Shadow : array (1 .. N, 1 .. N) of Boolean :=
        [others => [others => False]];
      Why    : array (1 .. N, 1 .. N) of Unbounded_String;
   begin
      Ok := True;
      Message := Null_Unbounded_String;
      Order.Clear;
      for K in 1 .. N loop
         Seq_First (Rules, A.Nullable, A.First, V, Bs (K).First, Bs (K).Last,
                    Firsts (K), Nulls (K));
      end loop;
      for I in 1 .. N loop
         for J in 1 .. N loop
            if I /= J then
               Shadow (I, J) := Shadows (I, J, Why (I, J));
            end if;
         end loop;
      end loop;
      for I in 1 .. N loop
         for J in I + 1 .. N loop
            if Shadow (I, J) and then Shadow (J, I) then
               Ok := False;
               Need (I);
               Need (J);
               declare
                  --  Only the wording of the message depends on these, so they
                  --  are not looked for as long as the check that matters.
                  I_In_J : constant Boolean := Includes (Auto (J), Auto (I), 40);
                  J_In_I : constant Boolean := Includes (Auto (I), Auto (J), 40);
               begin
                  if I_In_J and then J_In_I then
                     Message := To_Unbounded_String
                       (D (I) & " and " & D (J) & " match exactly the same "
                        & "text, so one of them is redundant: leave one out");
                  elsif J_In_I then
                     Message := To_Unbounded_String
                       (D (J) & " only matches text " & D (I) & " also "
                        & "matches, so as an alternative it adds nothing: "
                        & "leave it out");
                  elsif I_In_J then
                     Message := To_Unbounded_String
                       (D (I) & " only matches text " & D (J) & " also "
                        & "matches, so as an alternative it adds nothing: "
                        & "leave it out");
                  else
                     Message := To_Unbounded_String
                       (D (I) & " and " & D (J) & " can both match text "
                        & (if To_String (Why (I, J)) = "..."
                           then "that is too long and varied for hbnf to tell "
                                & "them apart; they "
                           else "beginning `" & To_String (Why (I, J))
                                & "`, and ")
                        & "go on differently, so choosing between them "
                        & "needs backtracking, which hbnf does not do.  "
                        & "Write `|`, ordered choice, with the one to prefer "
                        & "first (the first that matches is kept), or change "
                        & "one so that it cannot match what the other does");
                  end if;
               end;
               return;
            end if;
         end loop;
      end loop;
      --  An order in which no alternative shadows a later one: the
      --  earliest-written alternative that shadows no unplaced one goes first
      --  (so one that can match nothing, which shadows any other, goes last).
      declare
         Placed : Flags (1 .. N) := [others => False];
      begin
         for Step in 1 .. N loop
            declare
               Pick : Natural := 0;
            begin
               for K in 1 .. N loop
                  if not Placed (K) then
                     if not (for some J in 1 .. N =>
                               J /= K and then not Placed (J)
                               and then Shadow (K, J))
                     then
                        Pick := K;
                        exit;
                     end if;
                  end if;
               end loop;
               if Pick = 0 then
                  Ok := False;
                  Message := To_Unbounded_String
                    ("these alternatives cannot be put in an order where "
                     & "none takes input a later one needed.  Write `|`, "
                     & "ordered choice, in the order you want, or change "
                     & "them so that they do not match the same text");
                  Order.Clear;
                  return;
               end if;
               Placed (Pick) := True;
               Order.Append (Pick);
            end;
         end loop;
      end;
      --  An order that puts a broader alternative ahead of a narrower one the
      --  author wrote first makes the narrower one unreachable: the language
      --  is the same, but the parse is not what was written (`host` should be
      --  an IPv4address where it is one).  Keep what was written, with
      --  guards, instead.
      for P in 1 .. N loop
         for Q in P + 1 .. N loop
            if Order (P) > Order (Q) then
               Need (Order (P));
               Need (Order (Q));
               if Includes (Auto (Order (P)), Auto (Order (Q))) then
                  Ok := False;
                  Message := To_Unbounded_String
                    (D (Order (Q)) & " only matches text " & D (Order (P))
                     & " also matches, so a parser that takes whichever comes "
                     & "first would never choose it");
                  Order.Clear;
                  return;
               end if;
            end if;
         end loop;
      end loop;
   end Check_Choice;

   procedure Token_Dfa_Raw
     (Rules : Rule_Vectors.Vector; Nm : String;
      D     : out Dfa_State_Vectors.Vector;
      Ok    : out Boolean;
      Why   : out Ada.Strings.Unbounded.Unbounded_String)
   is
      J : constant Natural := Find (Rules, Nm);

      package Sorting is new Int_Vectors.Generic_Sorting;
      package Set_Vectors is new Ada.Containers.Vectors
        (Positive, Int_Vectors.Vector, Int_Vectors."=");
      package Cp_Sets2 is new Ada.Containers.Ordered_Sets (Natural);
      Seen : Set_Vectors.Vector;   --  the NFA state set (sorted) of each DFA state
      Trace_Nfa : Natural := 0;

      --  Sorted lists of states, in order, so the DFA states already made can be
      --  found in a tree.
      function Before (A, B : Int_Vectors.Vector) return Boolean is
      begin
         for I in 1 .. Natural'Min (Natural (A.Length), Natural (B.Length)) loop
            if A (I) /= B (I) then
               return A (I) < B (I);
            end if;
         end loop;
         return Natural (A.Length) < Natural (B.Length);
      end Before;
      package Set_Maps is new Ada.Containers.Ordered_Maps
        (Int_Vectors.Vector, Positive, Before);
      Seen_Index : Set_Maps.Map;   --  and the other way: a set -> its number
   begin
      D.Clear;
      Why := Null_Unbounded_String;
      Ok  := False;
      if J = 0 then
         Why := To_Unbounded_String ("`" & Nm & "` is not a rule");
         return;
      end if;
      Approximated := False;
      Why_Approximated := Null_Unbounded_String;
      declare
         A : constant Automaton :=
           Build (Rules, J, Rules (J).Pattern, 1,
                  Natural (Rules (J).Pattern.Length));
         N     : constant Natural := Natural (A.States.Length);
         Next  : Positive := 1;
      begin
         Trace_Nfa := N;
         if Approximated then
            Why := Why_Approximated;
            return;
         end if;
         declare
            --  What each state reaches without reading anything, worked out
            --  once, so that a step is a union of lists and not a walk.
            Clo   : array (1 .. N) of Int_Vectors.Vector;
            Stamp : array (1 .. N) of Natural := [others => 0];
            Gen   : Natural := 0;

            procedure Add_Closure (X : Positive; Into : in out Int_Vectors.Vector)
            is
            begin
               for Y of Clo (X) loop
                  if Stamp (Y) /= Gen then
                     Stamp (Y) := Gen;
                     Into.Append (Y);
                  end if;
               end loop;
            end Add_Closure;

            --  The live states reachable from X without reading anything.
            procedure Work_Out (X : Positive) is
               Todo : Int_Vectors.Vector;
               R    : Int_Vectors.Vector;
            begin
               Gen := Gen + 1;
               if A.Live (X) then
                  Stamp (X) := Gen;
                  R.Append (X);
                  Todo.Append (X);
               end if;
               while not Todo.Is_Empty loop
                  declare
                     Y : constant Positive := Todo.Last_Element;
                  begin
                     Todo.Delete_Last;
                     for T of A.States (Y).Eps loop
                        if A.Live (T) and then Stamp (T) /= Gen then
                           Stamp (T) := Gen;
                           R.Append (T);
                           Todo.Append (T);
                        end if;
                     end loop;
                  end;
               end loop;
               Sorting.Sort (R);
               Clo (X) := R;
            end Work_Out;


            Start : Int_Vectors.Vector;
         begin
            for X in 1 .. N loop
               Work_Out (X);
            end loop;
            Start := Clo (A.Start);
            Seen.Append (Start);
            Seen_Index.Insert (Start, 1);
            D.Append (Dfa_State'(others => <>));
            while Next <= Natural (Seen.Length) loop
               declare
                  Cur    : constant Int_Vectors.Vector := Seen (Next);
                  Bounds : Cp_Sets2.Set;
                  Edges  : Dfa_Edge_Vectors.Vector;
               begin
                  D (Next).Accepting := (for some X of Cur => X = A.Final);
                  for X of Cur loop
                     for E of A.States (X).Edges loop
                        Bounds.Include (E.Lo);
                        if E.Hi < Max_Code_Point then
                           Bounds.Include (E.Hi + 1);
                        end if;
                     end loop;
                  end loop;
                  declare
                     type Ev is record
                        Lo, Hi : Natural;
                        To     : Positive;
                     end record;
                     package Ev_Vectors is new Ada.Containers.Vectors (Positive, Ev);
                     function Ev_Before (A, B : Ev) return Boolean is (A.Lo < B.Lo);
                     package Ev_Sorting is new Ev_Vectors.Generic_Sorting (Ev_Before);
                     Evs    : Ev_Vectors.Vector;     --  every edge out of the state, by Lo
                     Active : Ev_Vectors.Vector;     --  the ones that cover the code point
                     Nx     : Positive := 1;
                     Lo     : Natural;
                     Moved  : Boolean;
                     Last_T : Int_Vectors.Vector;
                     Last_Id : Natural := 0;
                  begin
                     for X of Cur loop
                        for E of A.States (X).Edges loop
                           if A.Live (E.To) then
                              Evs.Append (Ev'(E.Lo, E.Hi, E.To));
                           end if;
                        end loop;
                     end loop;
                     Ev_Sorting.Sort (Evs);
                     for C in Bounds.Iterate loop
                        Lo := Cp_Sets2.Element (C);
                        declare
                           Hi : constant Natural :=
                             (if not Cp_Sets2.Has_Element (Cp_Sets2.Next (C))
                              then Max_Code_Point
                              else Cp_Sets2.Element (Cp_Sets2.Next (C)) - 1);
                           T  : Int_Vectors.Vector;
                           Id : Natural := 0;
                        begin
                           --  the edges that start here join, the ones that ended leave
                           Moved := False;
                           while Nx <= Natural (Evs.Length) and then Evs (Nx).Lo <= Lo loop
                              Active.Append (Evs (Nx));
                              Nx := Nx + 1;
                              Moved := True;
                           end loop;
                           declare
                              Kept : Ev_Vectors.Vector;
                           begin
                              for V of Active loop
                                 if V.Hi >= Lo then
                                    Kept.Append (V);
                                 end if;
                              end loop;
                              if Natural (Kept.Length) /= Natural (Active.Length) then
                                 Moved := True;
                              end if;
                              Active := Kept;
                           end;
                           if Moved then
                              --  the code points from here on are read by other edges
                              --  than the last ones were: work out where they lead
                              Gen := Gen + 1;
                              Last_T.Clear;
                              for V of Active loop
                                 Add_Closure (V.To, Last_T);
                              end loop;
                              Sorting.Sort (Last_T);
                              Last_Id := 0;
                              if not Last_T.Is_Empty then
                                 declare
                                    KC : constant Set_Maps.Cursor := Seen_Index.Find (Last_T);
                                 begin
                                    if Set_Maps.Has_Element (KC) then
                                       Last_Id := Set_Maps.Element (KC);
                                    end if;
                                 end;
                              end if;
                           end if;
                           T := Last_T;
                           Id := Last_Id;
                           if not T.Is_Empty then
                              if Id = 0 then
                                 if Natural (Seen.Length) >= Max_States then
                                    Why := To_Unbounded_String
                                      ("it needs more than"
                                       & Integer'Image (Max_States)
                                       & " states as one token");
                                    D.Clear;
                                    return;
                                 end if;
                                 Seen.Append (T);
                                 D.Append (Dfa_State'(others => <>));
                                 Id := Natural (Seen.Length);
                                 Seen_Index.Insert (T, Id);
                                 Last_Id := Id;
                              end if;
                              --  Join a neighbour that goes to the same state.
                              if not Edges.Is_Empty
                                and then Edges.Last_Element.To = Id
                                and then Edges.Last_Element.Hi + 1 = Lo
                              then
                                 Edges.Reference (Edges.Last_Index).Hi := Hi;
                              else
                                 Edges.Append (Dfa_Edge'(Lo, Hi, Id));
                              end if;
                           end if;
                        end;
                     end loop;
                  end;
                  D (Next).Edges := Edges;
                  Next := Next + 1;
               end;
            end loop;
         end;
      end;
      if Ada.Environment_Variables.Exists ("HBNF_TIMING") then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "hbnf: token " & Nm & ": nfa" & Natural'Image (Trace_Nfa)
            & ", dfa" & Natural'Image (Natural (D.Length)));
      end if;
      Ok := True;
   end Token_Dfa_Raw;

   --  The scanner of a rule is asked for by many checks and again by the code
   --  generator, and building it is the costly part of reading a grammar of
   --  thousands of rules; so the answer is kept for as long as the number of
   --  rules is the one it was made for.
   type Dfa_Answer is record
      D   : Dfa_State_Vectors.Vector;
      Ok  : Boolean;
      Why : Unbounded_String;
   end record;
   package Dfa_Answer_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Dfa_Answer);
   Dfa_Answers : Dfa_Answer_Maps.Map;

   --  The rules a rule is made of, with their sizes: what the scanner of the rule
   --  depends on.  Rules added elsewhere in the grammar (the ones `Lift` makes)
   --  do not change it, so they do not make the scanner be built again.
   function Made_Of (Rules : Rule_Vectors.Vector; Nm : String) return String is
      Seen : Key_Sets.Set;
      R    : Unbounded_String;

      procedure Visit (N : String);

      procedure Walk (V : Element_Vectors.Vector) is
      begin
         for E of V loop
            if E.Kind = Name then
               Visit (To_String (E.Name));
            elsif E.Kind = Group then
               Walk (E.Items);
            end if;
         end loop;
      end Walk;

      procedure Visit (N : String) is
         J : constant Natural := Find (Rules, N);
      begin
         if J = 0 or else Seen.Contains (N) then
            return;
         end if;
         Seen.Insert (N);
         Append (R, N & ":" & Natural'Image (Natural (Rules (J).Pattern.Length)) & ";");
         Walk (Rules (J).Pattern);
      end Visit;
   begin
      Visit (Nm);
      return To_String (R);
   end Made_Of;

   --  Merge the states that read alike: the subset construction keeps apart
   --  the states reached through different alternatives of a class (`[ -!]`,
   --  `[#-[]` and `[]-~]` each lead to a state of their own, all of which
   --  accept the same text afterwards), and a scanner whose body is a run of
   --  such states cannot skip the run in one loop.  Moore's refinement: states
   --  start in two classes, accepting or not, and are split while two of one
   --  class have an edge on the same code points to different classes.  The
   --  start state stays the first.
   procedure Minimize (D : in out Dfa_State_Vectors.Vector) is
      N   : constant Natural := Natural (D.Length);
      Cls : array (1 .. N) of Positive := [others => 1];
      Count : Natural := 0;

      function Signature (I : Positive) return String is
         R    : Unbounded_String;
         Prev : Natural := 0;     --  the class of the last edge, and where it ended
         Hi   : Natural := 0;
         Lo   : Natural := 0;
         Open : Boolean := False;

         procedure Flush is
         begin
            if Open then
               Append (R, Natural'Image (Lo) & "-" & Natural'Image (Hi) & ">" & Natural'Image (Prev) & ";");
            end if;
         end Flush;
      begin
         Append (R, Natural'Image (Cls (I)) & (if D (I).Accepting then "A" else "N"));
         for E of D (I).Edges loop
            if Open and then Cls (E.To) = Prev and then Hi + 1 = E.Lo then
               Hi := E.Hi;
            else
               Flush;
               Lo := E.Lo; Hi := E.Hi; Prev := Cls (E.To); Open := True;
            end if;
         end loop;
         Flush;
         return To_String (R);
      end Signature;
   begin
      if N < 2 then
         return;
      end if;
      for I in 1 .. N loop
         Cls (I) := (if D (I).Accepting then 2 else 1);
      end loop;
      loop
         declare
            Seen : Index_Maps.Map;
            Next : array (1 .. N) of Positive;
            K    : Natural := 0;
         begin
            for I in 1 .. N loop
               declare
                  Sig : constant String := Signature (I);
                  C   : constant Index_Maps.Cursor := Seen.Find (Sig);
               begin
                  if Index_Maps.Has_Element (C) then
                     Next (I) := Index_Maps.Element (C);
                  else
                     K := K + 1;
                     Seen.Insert (Sig, K);
                     Next (I) := K;
                  end if;
               end;
            end loop;
            exit when K = Count;
            Count := K;
            for I in 1 .. N loop
               Cls (I) := Next (I);
            end loop;
         end;
      end loop;
      if Count = N then
         return;
      end if;
      declare
         M    : Dfa_State_Vectors.Vector;
         Done : array (1 .. Count) of Boolean := [others => False];
      begin
         for C in 1 .. Count loop
            M.Append (Dfa_State'(others => <>));
         end loop;
         for I in 1 .. N loop
            if not Done (Cls (I)) then
               Done (Cls (I)) := True;
               M (Cls (I)).Accepting := D (I).Accepting;
               for E of D (I).Edges loop
                  if not M (Cls (I)).Edges.Is_Empty
                    and then M (Cls (I)).Edges.Last_Element.To = Cls (E.To)
                    and then M (Cls (I)).Edges.Last_Element.Hi + 1 = E.Lo
                  then
                     M (Cls (I)).Edges.Reference (M (Cls (I)).Edges.Last_Index).Hi := E.Hi;
                  else
                     M (Cls (I)).Edges.Append (Dfa_Edge'(E.Lo, E.Hi, Cls (E.To)));
                  end if;
               end loop;
            end if;
         end loop;
         D := M;
      end;
   end Minimize;

   procedure Token_Dfa
     (Rules : Rule_Vectors.Vector; Nm : String;
      D     : out Dfa_State_Vectors.Vector;
      Ok    : out Boolean;
      Why   : out Ada.Strings.Unbounded.Unbounded_String)
   is
      Key : constant String := Nm & "#" & Made_Of (Rules, Nm);
      C   : constant Dfa_Answer_Maps.Cursor := Dfa_Answers.Find (Key);
   begin
      if Dfa_Answer_Maps.Has_Element (C) then
         declare
            A : constant Dfa_Answer := Dfa_Answer_Maps.Element (C);
         begin
            D := A.D;
            Ok := A.Ok;
            Why := A.Why;
         end;
         return;
      end if;
      Token_Dfa_Raw (Rules, Nm, D, Ok, Why);
      if Ok then
         Minimize (D);
      end if;
      Dfa_Answers.Include (Key, (D => D, Ok => Ok, Why => Why));
   end Token_Dfa;


   procedure Dfa_Tables
     (D : Dfa_State_Vectors.Vector;
      Lo, Hi, To, First, Acc : out Ada.Strings.Unbounded.Unbounded_String)
   is
      Count : Natural := 0;

      function Num (N : Natural) return String is
         I : constant String := Natural'Image (N);
      begin
         return I (I'First + 1 .. I'Last) & ", ";
      end Num;
   begin
      Lo := Null_Unbounded_String;
      Hi := Null_Unbounded_String;
      To := Null_Unbounded_String;
      First := Null_Unbounded_String;
      Acc := Null_Unbounded_String;
      for S of D loop
         Append (First, Num (Count));
         Append (Acc, (if S.Accepting then "1, " else "0, "));
         for E of S.Edges loop
            Append (Lo, Num (E.Lo));
            Append (Hi, Num (E.Hi));
            Append (To, Num (E.To - 1));
            Count := Count + 1;
         end loop;
      end loop;
      declare
         I : constant String := Natural'Image (Count);
      begin
         Append (First, I (I'First + 1 .. I'Last));
      end;
      --  The padding: an edge that matches nothing (lo > hi), and a state
      --  that does not accept.
      Append (Lo, "1, 1");
      Append (Hi, "0, 0");
      Append (To, "0, 0");
      Append (Acc, "0");
   end Dfa_Tables;

end HBNF_Lookahead;
