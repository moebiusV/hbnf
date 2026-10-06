pragma Ada_2022;

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
   Max_States     : constant := 20_000;   --  past this a rule is "any text"
   Max_Nodes      : constant := 20_000;   --  pairs of state sets searched

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

   --  Does Big match all the text Small does?
   function Includes_From
     (Big, Small : Automaton; Big_From, From : State_Sets.Set) return Boolean
   is
      type Pair is record
         S, B : State_Sets.Set;
      end record;
      package Pair_Vectors is new Ada.Containers.Vectors (Positive, Pair);

      Todo : Pair_Vectors.Vector;
      Seen : Key_Sets.Set;
      Next : Positive := 1;

      procedure Add (S, B : State_Sets.Set) is
         K : constant String := Key (S) & "|" & Key (B);
      begin
         if not Seen.Contains (K) then
            Seen.Insert (K);
            Todo.Append (Pair'(S => S, B => B));
         end if;
      end Add;
   begin
      Add (From, Big_From);
      while Next <= Natural (Todo.Length) loop
         if Natural (Todo.Length) > Max_Nodes then
            return False;
         end if;
         declare
            N      : constant Pair := Todo (Next);
            Bounds : Cp_Sets.Set;
         begin
            Next := Next + 1;
            if N.S.Contains (Small.Final)
              and then not N.B.Contains (Big.Final)
            then
               return False;
            end if;
            for X of N.S loop
               for E of Small.States (X).Edges loop
                  if Small.Live (E.To) then
                     Bounds.Include (E.Lo);
                     Bounds.Include (E.Hi + 1);
                  end if;
               end loop;
            end loop;
            for X of N.B loop
               for E of Big.States (X).Edges loop
                  if Big.Live (E.To) then
                     Bounds.Include (E.Lo);
                     Bounds.Include (E.Hi + 1);
                  end if;
               end loop;
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
                        TS : constant State_Sets.Set := Step (Small, N.S, Lo);
                     begin
                        if not TS.Is_Empty then
                           Add (TS, Step (Big, N.B, Lo));
                        end if;
                     end;
                  end;
               end loop;
            end;
         end;
      end loop;
      return True;
   end Includes_From;

   function Includes (Big, Small : Automaton) return Boolean is
      S0, B0 : State_Sets.Set;
   begin
      S0.Insert (Small.Start);
      B0.Insert (Big.Start);
      return Includes_From (Big, Small, Closure (Big, B0), Closure (Small, S0));
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
         SA, SB : State_Sets.Set;
         Parent : Natural;
         Cp     : Natural;
         Depth  : Natural;
      end record;
      package Node_Vectors is new Ada.Containers.Vectors (Positive, Node);

      Nodes : Node_Vectors.Vector;
      Seen  : Key_Sets.Set;
      Next  : Positive := 1;

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

      procedure Add (SA, SB : State_Sets.Set; Parent, Cp, Depth : Natural) is
         K : constant String := Key (SA) & "|" & Key (SB);
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
      if Greedy then
         declare
            W0 : State_Sets.Set;
         begin
            W0.Insert (Whole.Start);
            Whole_Start := Closure (Whole.all, W0);
            Whole_Empty_Ok := Whole_Start.Contains (Whole.Final);
         end;
      end if;
      declare
         Only_A : State_Sets.Set;
         Only_B : State_Sets.Set;
      begin
         Only_A.Insert (EA.Start);
         Only_B.Insert (EB.Start);
         Add (Closure (EA, Only_A), Closure (EB, Only_B), 0, 0, 0);
      end;
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
            A_Done  : constant Boolean := N.SA.Contains (EA.Final);
            B_Done  : constant Boolean := N.SB.Contains (EB.Final);
         begin
            Next := Next + 1;
            --  R can end right where a repetition ends: greedy takes it, and
            --  nothing is left for R unless R can match nothing.
            if Greedy and then N.Depth > 0 and then A_Done
              and then N.SB.Contains (EB.Final)
              and then not Whole_Empty_Ok
            then
               Found := True;
               Witness := To_Unbounded_String (Text (Here));
               return;
            end if;
            for X of N.SA loop
               for E of EA.States (X).Edges loop
                  if EA.Live (E.To) then
                     Bounds.Include (E.Lo);
                     Bounds.Include (E.Hi + 1);
                  end if;
               end loop;
            end loop;
            for X of N.SB loop
               for E of EB.States (X).Edges loop
                  if EB.Live (E.To) then
                     Bounds.Include (E.Lo);
                     Bounds.Include (E.Hi + 1);
                  end if;
               end loop;
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
                        TA : constant State_Sets.Set := Step (EA, N.SA, Lo);
                        TB : constant State_Sets.Set := Step (EB, N.SB, Lo);
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
                                          Step (Whole.all, Whole_Start, Lo), TB)
                        then
                           Found := True;
                           Witness := To_Unbounded_String
                             (Text (Here) & Cp_Image (Lo));
                           return;
                        end if;
                        if not Greedy and then A_Done and then not TB.Is_Empty
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
                  I_In_J : constant Boolean := Includes (Auto (J), Auto (I));
                  J_In_I : constant Boolean := Includes (Auto (I), Auto (J));
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
                        & "beginning `" & To_String (Why (I, J)) & "`, and "
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
   end Check_Choice;

end HBNF_Lookahead;
