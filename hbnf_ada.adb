pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Mustache;
with HBNF_Compilable;

package body HBNF_Ada is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;
   use HBNF_Compilable;

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

   --  Escape a literal for an Ada string literal: Ada doubles its quote
   --  delimiter, and every other byte is left alone (backslash is an ordinary
   --  character in Ada, and a control byte — which cannot appear in an Ada
   --  literal — does not occur in any current grammar).
   function Ada_Escape (S : String) return String is
      Buf : U;
   begin
      for C of S loop
         Append (Buf, C);
         if C = '"' then
            --  Ada doubles the quote delimiter; append it once more.
            Append (Buf, C);
         end if;
      end loop;
      return To_String (Buf);
   end Ada_Escape;

   --  True when every `|`-alternative is exactly one Literal — the shape an
   --  enum can hold.  A multi-token alternative (`"a" "b" | "c" "d"`), one that
   --  names another rule, or a single literal (no `|`) is not an enum.
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

   --  =====================================================================
   --  Rule classification, and the by-value graph the one cycle detector in
   --  HBNF_Compilable runs on.
   --
   --  These live at package level, parameterised by Rules, because Emit (the
   --  type package) and Emit_Parser (the child parser package) are separate
   --  functions with separate local state, and both need the same answers --
   --  Emit for the record, alias and access declarations, Emit_Parser for the
   --  commit point and the free walk.  This is not a unification of the four
   --  backends' analyzers, which is a separate job; it only stops Ada keeping
   --  two copies of its own classification.

   function Find (Rules : Rule_Vectors.Vector; Name : String)
     return Natural
   is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if To_String (Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   --  The Ada type a rule reference denotes: a core scalar inlines; any
   --  other reference resolves to the referenced rule's own type name.
   function Ada_Type_Of (Rules : Rule_Vectors.Vector; Ref : String)
     return String is
      S : constant String := Scalar_Ada_Type (Ref);
   begin
      if S /= "" then
         return S;
      end if;
      if Find (Rules, Ref) = 0 then
         raise Parse_Error with "undefined rule: " & Ref;
      end if;
      return Ada_Ident (Ref) & "_Type";
   end Ada_Type_Of;

   --  The underlying scalar Ada type a rule name resolves to, chasing
   --  single-name aliases and jets to their target (so `str | word` and
   --  `ipv4 | ipv6` both collapse to `Unbounded_String`).  "" if not scalar.
   function Resolve_Type
     (Rules : Rule_Vectors.Vector; N : String; Depth : Natural := 0)
      return String
   is
      C : constant String := Scalar_Ada_Type (N);
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
               return "Unbounded_String";
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

   --  If the pattern is a pure alternation of names that all resolve to
   --  the same scalar Ada type, that type (a scalar union); else "".
   function Scalar_Union_Type
     (Rules : Rule_Vectors.Vector; Els : Element_Vectors.Vector)
      return String
   is
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
   --  and whether any '|' alternation appears.
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
            when Char_Range =>
               null;
            when Block =>
               null;  --  lifted to a rule of its own before emission
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

   function Analyze (Rules : Rule_Vectors.Vector; Idx : Natural)
     return Rule_Info is
      R : constant Rule := Rules (Idx);
      P : constant Element_Vectors.Vector := R.Pattern;
   begin
      if Is_Char_Rule (Rules, To_String (R.Name)) then
         --  A character-level rule compiles to a scanner and a token; its
         --  value is the matched text, so it is a scalar string.
         return (Kind        => Scalar,
                 Inline_Type => To_Unbounded_String ("Unbounded_String"));
      end if;
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
                  --  A group of a single rule reference (`*( entry )`) is
                  --  a list of that rule's type, not an anonymous struct.
                  if Natural (E.Items.Length) = 1
                    and then E.Items (1).Kind = Name
                  then
                     return (Kind        => List,
                             Elem_Name    => E.Items (1).Name,
                             Elem_Members => Member_Vectors.Empty_Vector);
                  else
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
                  end if;
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
                           (Ada_Type_Of (Rules, To_String (E.Name))));
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

   function Is_Record (Info : Rule_Info) return Boolean is
     (Info.Kind = Struct);

   --  The rule an alias chain ends at: Over_Leaf is then "the target is a
   --  record or a list".  A chosen back edge always resolves to a record
   --  (a list rule contributes no outgoing edges, so it cannot be on a
   --  cycle), which is what lets the callers use its declared access type.
   function Leaf_Target (Rules : Rule_Vectors.Vector; Idx : Natural)
     return Natural
   is
      J : Natural := Idx;
   begin
      for K in 1 .. 20 loop
         declare
            P : constant Element_Vectors.Vector := Rules (J).Pattern;
         begin
            if Analyze (Rules, J).Kind = Scalar
              and then Natural (P.Length) = 1
              and then P (1).Kind = Name
              and then Scalar_Ada_Type (To_String (P (1).Name)) = ""
            then
               declare
                  Nx : constant Natural := Find (Rules, To_String (P (1).Name));
               begin
                  exit when Nx = 0;
                  J := Nx;
               end;
            else
               exit;
            end if;
         end;
      end loop;
      return J;
   end Leaf_Target;

   --  True when a scalar rule is an alias (directly or through further
   --  aliases) to a record or list (`src = host`, `a = b` with `b = host`):
   --  its subtype must follow the target's full type, so it is emitted in
   --  the record+alias phase rather than among the leaves.
   function Over_Leaf (Rules : Rule_Vectors.Vector; Idx : Natural)
     return Boolean
   is (Analyze (Rules, Leaf_Target (Rules, Idx)).Kind in Struct | List);

   --  True when (Owner, Member) is the field the detector chose to hold
   --  indirectly.  A member name is unique within its record, so the pair
   --  names the edge.
   function Is_Back (Backs : Edge_Vectors.Vector;
                     Owner : Natural; Member : String) return Boolean is
   begin
      for E of Backs loop
         if E.Owner = Owner and then To_String (E.Member) = Member then
            return True;
         end if;
      end loop;
      return False;
   end Is_Back;

   --  The rule a reference resolves to through its alias chain: for a member
   --  naming `expr` with `expr = prim`, that is `prim`.  A chosen back edge
   --  always resolves to a record, because a list rule contributes no
   --  outgoing edges and so cannot lie on a cycle.
   function Leaf_Record (Rules : Rule_Vectors.Vector; Ref : String)
     return Natural
   is (Leaf_Target (Rules, Find (Rules, Ref)));

   --  The rules a record or deferred alias must follow in the combined
   --  record+alias emission: a record follows the deferred aliases its
   --  by-value members name, and a deferred alias (`src = host`) follows
   --  its target when that target is in the same phase (a record or a
   --  further alias); a list target was already emitted with the vectors.
   --  A back edge is left out: it is about to become an access type, so it
   --  no longer orders anything (and would otherwise stall the sort).
   function Type_Deps
     (Rules : Rule_Vectors.Vector; Backs : Edge_Vectors.Vector; Idx : Natural)
      return Natural_Vectors.Vector
   is
      Info : constant Rule_Info := Analyze (Rules, Idx);
      D    : Natural_Vectors.Vector;
   begin
      if Info.Kind = Struct then
         for M of Info.Members loop
            if not M.Is_List
              and then not Is_Back (Backs, Idx, To_String (M.Name))
            then
               declare
                  J : constant Natural := Find (Rules, To_String (M.Name));
               begin
                  if J > 0 and then Over_Leaf (Rules, J) then
                     D.Append (J);
                  end if;
               end;
            end if;
         end loop;
      elsif Info.Kind = Scalar and then Over_Leaf (Rules, Idx) then
         declare
            P : constant Element_Vectors.Vector := Rules (Idx).Pattern;
            J : constant Natural := Find (Rules, To_String (P (1).Name));
         begin
            if J > 0
              and then (Is_Record (Analyze (Rules, J))
                        or else (Analyze (Rules, J).Kind = Scalar
                                 and then Over_Leaf (Rules, J)))
            then
               D.Append (J);
            end if;
         end;
      end if;
      return D;
   end Type_Deps;

   --  The fields Ada must hold indirectly, one per cycle in the by-value
   --  graph, chosen by the one detector in HBNF_Compilable.  A record already
   --  refers to another record through an access type, so the edges that
   --  embed by value are the ones that reach a record through an alias
   --  (`Over_Leaf`): a member naming a scalar alias over a record, and an
   --  alias naming one.  A list member is a vector, which is indirect, so it
   --  imposes no order.  This is `Type_Deps` in edge form, so the detector
   --  refuses exactly the schemas the sort used to stall on.
   function Back_Edges_Ada (Rules : Rule_Vectors.Vector)
     return Edge_Vectors.Vector
   is
      E : Edge_Vectors.Vector;
   begin
      for I in 1 .. Natural (Rules.Length) loop
         declare
            Info : constant Rule_Info := Analyze (Rules, I);
         begin
            case Info.Kind is
               when Struct =>
                  for M of Info.Members loop
                     if not M.Is_List then
                        declare
                           J : constant Natural := Find (Rules, To_String (M.Name));
                        begin
                           if J > 0 and then Over_Leaf (Rules, J) then
                              E.Append
                                (HBNF_Compilable.By_Value_Edge'
                                   (Owner => I, Member => M.Name,
                                    Target => J));
                           end if;
                        end;
                     end if;
                  end loop;
               when Scalar =>
                  --  A rule that is one name is an alias; the edge has no
                  --  member, so it can order but never be broken.
                  if Over_Leaf (Rules, I) then
                     declare
                        P : constant Element_Vectors.Vector :=
                          Rules (I).Pattern;
                        J : constant Natural := Find (Rules, To_String (P (1).Name));
                     begin
                        if J > 0
                          and then (Is_Record (Analyze (Rules, J))
                                    or else (Analyze (Rules, J).Kind = Scalar
                                             and then Over_Leaf (Rules, J)))
                        then
                           E.Append
                             (HBNF_Compilable.By_Value_Edge'
                                (Owner => I,
                                 Member => Null_Unbounded_String,
                                 Target => J));
                        end if;
                     end;
                  end if;
               when others =>
                  null;
            end case;
         end;
      end loop;
      return Back_Edges (Natural (Rules.Length), E);
   end Back_Edges_Ada;

   function Emit (Rules : Rule_Vectors.Vector; Package_Name : String)
     return String
   is

      N : constant Natural := Natural (Rules.Length);

      --  The fields to hold indirectly, one per by-value cycle.  Unlike C
      --  this can be a constant elaborated here: Over_Leaf's alias chase is
      --  bounded, so there is no unbounded search to run away with.
      Backs : constant Edge_Vectors.Vector := Back_Edges_Ada (Rules);

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

      Infos : Info_Vectors.Vector;

      --  The vector element type for a list of Ref, or the type of a record's
      --  member: an access to the record (so recursion can be broken), or the
      --  scalar inlined by value.
      function Elem_Type (Owner : Natural; Ref : String) return String is
         S : constant String := Scalar_Ada_Type (Ref);
         J : constant Natural := Find (Rules, Ref);
      begin
         if S /= "" then
            return S;                           -- a core scalar
         elsif J > 0 and then Is_Record (Infos (J)) then
            return Ada_Ident (Ref) & "_Access"; -- a record: access breaks it
         elsif Is_Back (Backs, Owner, Ref) then
            --  The field chosen to break a cycle, naming an alias over a
            --  record: the alias's subtype would embed that record by value,
            --  which is the cycle.  Point at the resolved record instead; its
            --  access type is declared with the other records, before any
            --  record body, so this can be referenced where the body is.
            return Ada_Ident
              (To_String (Rules (Leaf_Record (Rules, Ref)).Name)) & "_Access";
         else
            return Ada_Type_Of (Rules, Ref);    -- a scalar/enum/list rule
         end if;
      end Elem_Type;

      --  The vector package behind a reference whose rule is a list (through
      --  any aliases), or "" when it is not one.  A vector of vectors needs
      --  the element vector's `=` in scope at the instantiation, and that `=`
      --  is declared in the element's own vector package.
      function Vector_Pkg (Ref : String) return String is
         J : constant Natural := Find (Rules, Ref);
      begin
         if J = 0 or else Scalar_Ada_Type (Ref) /= "" then
            return "";
         end if;
         declare
            L : constant Natural := Leaf_Target (Rules, J);
         begin
            if Infos (L).Kind = List then
               return Ada_Ident (To_String (Rules (L).Name)) & "_Vectors";
            end if;
         end;
         return "";
      end Vector_Pkg;

      --  A vector package instantiation.  Elem_Pkg is the vector package of
      --  the element when the element is itself a vector.
      function Emit_Vector
        (Name, Elem : String; Elem_Pkg : String := "") return String is
         B : U;
      begin
         --  Before the instantiation, which is where the `=` is needed.
         if Elem_Pkg /= "" then
            Append (B, "   use type " & Elem_Pkg & ".Vector;");
            Append (B, LF);
         end if;
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
               declare
                  V : Mustache.Context := Mustache.View;
               begin
                  Mustache.Put (V, "name", TN);
                  Mustache.Put (V, "type", To_String (Info.Inline_Type));
                  Append (Buf, Mustache.Render_File ("ada_scalar", V));
               end;
               Append (Buf, LF);
            when Enum =>
               declare
                  Names : constant String_Vectors.Vector := Enum_Names (Info.Literals);
                  Items : constant Mustache.Value_Access := Mustache.New_List;
                  Row   : Mustache.Value_Access;
                  V     : Mustache.Context := Mustache.View;
               begin
                  for I in 1 .. Natural (Info.Literals.Length) loop
                     Row := Mustache.New_Map;
                     Mustache.Insert
                       (Row, "ident",
                        Mustache.New_Scalar
                          (Base & "_" & To_String (Names (I))));
                     --  Mustache has no join, so the separator is a flag on
                     --  every row but the first: `{{#sep}}, {{/sep}}`.
                     if I > 1 then
                        Mustache.Insert (Row, "sep", Mustache.New_Scalar ("1"));
                     end if;
                     Mustache.Append (Items, Row);
                  end loop;
                  Mustache.Put (V, "name", TN);
                  Mustache.Put (V, "items", Items);
                  Append (Buf, Mustache.Render_File ("ada_enum", V));
               end;
               Append (Buf, LF);
            when Struct =>
               declare
                  Items : constant Mustache.Value_Access := Mustache.New_List;
                  Row   : Mustache.Value_Access;
                  V     : Mustache.Context := Mustache.View;
               begin
                  for M of Info.Members loop
                     Row := Mustache.New_Map;
                     Mustache.Insert
                       (Row, "field",
                        Mustache.New_Scalar (Ada_Field (To_String (M.Name))));
                     Mustache.Insert
                       (Row, "type",
                        Mustache.New_Scalar
                          (if M.Is_List
                           then Base & "_" & Ada_Ident (To_String (M.Name))
                                & "_Vectors.Vector"
                           else Elem_Type (Idx, To_String (M.Name))));
                     Mustache.Append (Items, Row);
                  end loop;
                  Mustache.Put (V, "name", TN);
                  Mustache.Put (V, "items", Items);
                  Append (Buf, Mustache.Render_File ("ada_struct", V));
               end;
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
                 (Base & "_Vectors", Elem_Type (Idx, To_String (Info.Elem_Name)),
                  Vector_Pkg (To_String (Info.Elem_Name))));
            end if;
         else
            --  A group element: emit a named entry record (value members).
            declare
               Items : constant Mustache.Value_Access := Mustache.New_List;
               Row   : Mustache.Value_Access;
               V     : Mustache.Context := Mustache.View;
            begin
               for M of Info.Elem_Members loop
                  Row := Mustache.New_Map;
                  Mustache.Insert
                    (Row, "field",
                     Mustache.New_Scalar (Ada_Field (To_String (M.Name))));
                  Mustache.Insert
                    (Row, "type",
                     Mustache.New_Scalar (Elem_Type (Idx, To_String (M.Name))));
                  Mustache.Append (Items, Row);
               end loop;
               Mustache.Put (V, "name", Base & "_Entry");
               Mustache.Put (V, "items", Items);
               Append (Buf, Mustache.Render_File ("ada_struct", V));
            end;
            Append (Buf, LF);
            Append (Buf, Emit_Vector (Base & "_Vectors", Base & "_Entry"));
         end if;
         declare
            V : Mustache.Context := Mustache.View;
         begin
            Mustache.Put (V, "name", TN);
            Mustache.Put (V, "base", Base);
            Append (Buf, Mustache.Render_File ("ada_list_subtype", V));
         end;
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
         Infos.Append (Analyze (Rules, I));
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
            J : Natural;
         begin
            if Natural (P.Length) = 1 and then P (1).Kind = Name
              and then Scalar_Ada_Type (To_String (P (1).Name)) = ""
            then
               J := Find (Rules, To_String (P (1).Name));
               --  A scalar alias over a record/list (`src = host`) is a
               --  subtype, not a leaf that must follow its target.  Only a
               --  leaf target (another scalar or enum) orders the alias after
               --  it.
               if J > 0
                 and then (Infos (J).Kind = Scalar or else Infos (J).Kind = Enum)
               then
                  return J;
               end if;
            end if;
            return 0;
         end Scalar_Ref;

         Remaining_Leaves : Natural := 0;
      begin
         for I in 1 .. N loop
            if (Infos (I).Kind = Scalar or else Infos (I).Kind = Enum)
              and then not Over_Leaf (Rules, I)
            then
               Remaining_Leaves := Remaining_Leaves + 1;
            end if;
         end loop;
         while Remaining_Leaves > 0 loop
            declare
               Progress : Boolean := False;
            begin
               for I in 1 .. N loop
                  if (Infos (I).Kind = Scalar or else Infos (I).Kind = Enum)
                    and then not Over_Leaf (Rules, I)
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
      --  member of a record rule.  A vector's element, or a group entry's
      --  member, may itself be a list, whose type must be declared first, so
      --  these go in dependency order: rule order wherever nothing is out of
      --  order, and an item whose list is not yet declared waits a pass.
      declare
         --  The list rule a reference ends at (through aliases), 0 if none.
         function List_Leaf (Ref : String) return Natural is
            J : constant Natural := Find (Rules, Ref);
         begin
            if J = 0 or else Scalar_Ada_Type (Ref) /= "" then
               return 0;
            end if;
            declare
               L : constant Natural := Leaf_Target (Rules, J);
            begin
               return (if Infos (L).Kind = List then L else 0);
            end;
         end List_Leaf;

         function Declared (Ref : String; Self : Natural) return Boolean is
            L : constant Natural := List_Leaf (Ref);
         begin
            return L = 0 or else L = Self or else Emitted (L);
         end Declared;

         type Item_Done is array (1 .. N) of Boolean;
         List_Done : Item_Done := [others => False];
         --  A record's repeated-member vectors, done per record.
         Rec_Done  : Item_Done := [others => False];
         Left      : Natural := 0;

         function Rec_Ready (I : Natural) return Boolean is
            Mem : constant Member_Vectors.Vector := Infos (I).Members;
         begin
            for M of Mem loop
               if M.Is_List and then not Declared (To_String (M.Name), 0) then
                  return False;
               end if;
            end loop;
            return True;
         end Rec_Ready;

         function List_Ready (I : Natural) return Boolean is
            Info : constant Rule_Info := Infos (I);
            Ent  : constant Member_Vectors.Vector := Info.Elem_Members;
         begin
            if not Ent.Is_Empty then
               for M of Ent loop
                  if not Declared (To_String (M.Name), I) then
                     return False;
                  end if;
               end loop;
            elsif Info.Elem_Name /= Null_Unbounded_String then
               return Declared (To_String (Info.Elem_Name), I);
            end if;
            return True;
         end List_Ready;
      begin
         for I in 1 .. N loop
            if Infos (I).Kind = List then
               Left := Left + 1;
            elsif Infos (I).Kind = Struct then
               declare
                  Mem : constant Member_Vectors.Vector := Infos (I).Members;
               begin
                  for M of Mem loop
                     if M.Is_List then
                        Left := Left + 1;
                        exit;
                     end if;
                  end loop;
               end;
            end if;
         end loop;
         while Left > 0 loop
            declare
               Progress : Boolean := False;
            begin
               for I in 1 .. N loop
                  if Infos (I).Kind = List
                    and then not List_Done (I) and then List_Ready (I)
                  then
                     Append (Res, Emit_List (I, Infos (I)));
                     Append (Res, LF);
                     Emitted (I) := True;
                     List_Done (I) := True;
                     Left := Left - 1;
                     Progress := True;
                  elsif Infos (I).Kind = Struct and then not Rec_Done (I)
                    and then Rec_Ready (I)
                  then
                     Rec_Done (I) := True;
                     declare
                        Any : Boolean := False;
                        Mem : constant Member_Vectors.Vector := Infos (I).Members;
                     begin
                        for M of Mem loop
                           if M.Is_List then
                              Any := True;
                              Append (Res, Emit_Vector
                                (Ada_Ident (To_String (Rules (I).Name)) & "_" &
                                 Ada_Ident (To_String (M.Name)) & "_Vectors",
                                 Elem_Type (I, To_String (M.Name)),
                                 Vector_Pkg (To_String (M.Name))));
                              Append (Res, LF);
                           end if;
                        end loop;
                        if Any then
                           Left := Left - 1;
                           Progress := True;
                        end if;
                     end;
                  end if;
               end loop;
               if not Progress then
                  raise Parse_Error with
                    "a list's element or entry names a list that names it "
                    & "back: the vector types would contain each other";
               end if;
            end;
         end loop;
      end;

      --  The fields to hold indirectly are already in Backs, computed at the
      --  top: a cycle with no field to break (an all-alias cycle) is still
      --  refused there, by Back_Edges itself.  The sort below is where a
      --  record cycle used to be caught, and its stall-raise stays as
      --  now-unreachable defense, as it does in C.

      --  Record bodies and their subtype aliases (`loport = port`), in
      --  by-value dependency order: a record follows the aliases its by-value
      --  members name, and an alias follows its target record.  A cycle here
      --  means a record contains another by value, transitively, with no list
      --  to break it — infinite size.
      for I in 1 .. N loop
         if Is_Record (Infos (I))
           or else (Infos (I).Kind = Scalar and then Over_Leaf (Rules, I))
         then
            Remaining := Remaining + 1;
         end if;
      end loop;
      while Remaining > 0 loop
         declare
            Progress : Boolean := False;
         begin
            for I in 1 .. N loop
               if (Is_Record (Infos (I))
                   or else (Infos (I).Kind = Scalar and then Over_Leaf (Rules, I)))
                 and then not Emitted (I)
               then
                  declare
                     Ready : Boolean := True;
                  begin
                     for D of Type_Deps (Rules, Backs, I) loop
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
                 "a rule's value cannot contain itself: the tree types are structs "
                 & "by value, so this one would be infinitely sized.  Routing "
                 & "the recursion through a list does not help (a list node "
                 & "holds its element by value too); RFCPLAN.md step 9 adds "
                 & "the pointer that breaks the cycle";
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

      --  The same fields Emit declares as access types, so that here they are
      --  allocated through the pointer rather than assigned into a record.
      --  Two independent computations of one graph: Emit and Emit_Parser do
      --  not share state, and Back_Edges is a pure function of the rules.
      Backs : constant Edge_Vectors.Vector := Back_Edges_Ada (Rules);

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

      --  True when every `|`-alternative is exactly one Literal — the shape
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

      --  True when a rule is a record (struct): its parse yields a _Type whose
      --  full declaration may come after its use, so a list of it stores an
      --  _Access.  Scalars (core, alias, or union) and enums are not records.
      function Is_Struct (Name : String) return Boolean is
         J : constant Natural := Find (Rules, Name);
      begin
         if J = 0 then
            return False;
         end if;
         if Is_Char_Rule (Rules, Name) then
            return False;  -- a char rule is a scalar (Unbounded_String)
         end if;
         declare
            R : constant Rule := Rules (J);
            P : constant Element_Vectors.Vector := R.Pattern;
         begin
            if R.Jet_Code /= Null_Unbounded_String then
               return False;
            end if;
            if Natural (P.Length) = 1 then
               declare
                  E : constant Element_Access := P (1);
               begin
                  if E.Min /= 1 or else E.Max /= 1 then
                     return False;  -- a list
                  end if;
                  return E.Kind = HBNF_Grammar.Group;  -- ( x ) = struct
               end;
            else
               return not Is_Pure_Literal_Alt (P)
                 and then Scalar_Union_Type (Rules, P) = "";
            end if;
         end;
      end Is_Struct;

      --  The condition that the code point (in Cp) lies in [Lo, Hi].  `Cp >= 0`
      --  is a useless comparison (Cp is Natural), so the lower bound is dropped
      --  when Lo = 0.
      function Range_Cond (Lo, Hi : Natural) return String is
      begin
         if Lo = 0 then
            return "(Cp <= " & Img (Hi) & ")";
         else
            return "(Cp >= " & Img (Lo) & " and then Cp <= " & Img (Hi) & ")";
         end if;
      end Range_Cond;

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

      --  The core scanner a core scalar reads: `word`/`atom`/`bool`/`flag`
      --  read the `word` rule, `int`/`uN`/`iN` the `int` rule, `str` the `str`
      --  rule.  The rule is the grammar's own char rule when it defines one,
      --  else the built-in scanner of the same name (see Emit_Builtin_Scans).
      function Core_Base (Name : String) return String is
      begin
         if Name = "str" then
            return "str";
         elsif Name = "int" then
            return "int";
         elsif Name'Length >= 2
           and then (Name (Name'First) = 'u' or else Name (Name'First) = 'i')
           and then (for all C of Name (Name'First + 1 .. Name'Last)
                     => C in '0' .. '9')
         then
            return "int";
         end if;
         return "word";
      end Core_Base;

      function Scan_Fn (Name : String) return String is
        ("Scan_" & Ada_Ident (Core_Base (Name)));

      --  The condition that rejects a matched bareword that is a keyword: a
      --  `word` must not swallow a directive's keyword.  N is the matched
      --  length, the text starts at P.Pos.
      function Scalar_Reject (Name : String) return String is
        (if Name = "atom" or else Name = "word"
         then " or else Is_Keyword (P.Text (P.Pos .. P.Pos + N - 1))"
         else "");

      --  The positive form of Scalar_Reject, for a branch that accepts on N: a
      --  matched bareword must not be a keyword either.
      function Scalar_Guard (Name : String) return String is
        (if Name = "atom" or else Name = "word"
         then " and then not Is_Keyword (P.Text (P.Pos .. P.Pos + N - 1))"
         else "");

      --  The Ada expression converting the matched text (length N, at P.Pos)
      --  into the core scalar's value.
      function Scalar_Value (Name : String) return String is
         Sl : constant String := "P.Text (P.Pos .. P.Pos + N - 1)";
      begin
         if Name = "str" then
            return "Str_Value (" & Sl & ")";
         elsif Name = "int" then
            return "Long_Long_Integer'Value (" & Sl & ")";
         elsif Name = "bool" or else Name = "flag" then
            return Sl & " = ""yes"" or else " & Sl & " = ""on"" or else "
              & Sl & " = ""true""";
         elsif Name'Length >= 2 then
            declare
               P : constant Character := Name (Name'First);
               R : constant String := Name (Name'First + 1 .. Name'Last);
            begin
               if (P = 'u' or else P = 'i')
                 and then (for all C of R => C in '0' .. '9')
               then
                  return (if P = 'u' then "Unsigned_" else "Integer_") & R
                    & "'Value (" & Sl & ")";
               end if;
            end;
         end if;
         return "To_Unbounded_String (" & Sl & ")";
      end Scalar_Value;

      --  A letter-led literal is a keyword: it is matched by the `word`
      --  scanner, so `in` never matches the front of `input`.  Any other
      --  literal compares bytes.  (Same rule as the C backend's.)
      function Is_Keyword_Lit (S : String) return Boolean is
        (S'Length > 0
         and then (S (S'First) in 'a' .. 'z'
                   or else S (S'First) in 'A' .. 'Z'
                   or else S (S'First) = '_')
         and then (HBNF_Grammar.Keyword_Table.Is_Empty
                   or else HBNF_Grammar.Keyword_Table.Contains
                             (To_Unbounded_String (S))));

      --  The rule phrase rules skip between their elements, "" when none.
      function Whitespace_Rule_Name return String is
      begin
         for I in 1 .. N loop
            if Rules (I).Whitespace /= Null_Unbounded_String then
               return To_String (Rules (I).Whitespace);
            end if;
         end loop;
         return "";
      end Whitespace_Rule_Name;

      Ws_Name : constant String := Whitespace_Rule_Name;

      --  The words `word` must not match: the `keywords` table when there is
      --  one, else every letter-led literal in the grammar, in first-appearance
      --  order.  (As the C backend collects them.)
      function Collect_Keywords return String_Vectors.Vector is
         K : String_Vectors.Vector;

         function Present (X : U) return Boolean is
           (for some Y of K => Y = X);

         procedure Walk (Els : Element_Vectors.Vector) is
         begin
            for E of Els loop
               case E.Kind is
                  when Literal =>
                     if Is_Keyword_Lit (To_String (E.Lit))
                       and then not Present (E.Lit)
                     then
                        K.Append (E.Lit);
                     end if;
                  when Group =>
                     Walk (E.Items);
                  when others =>
                     null;
               end case;
            end loop;
         end Walk;
      begin
         if not HBNF_Grammar.Keyword_Table.Is_Empty then
            for W of HBNF_Grammar.Keyword_Table loop
               K.Append (W);
            end loop;
            return K;
         end if;
         for I in 1 .. N loop
            Walk (Rules (I).Pattern);
         end loop;
         return K;
      end Collect_Keywords;

      Keywords : constant String_Vectors.Vector := Collect_Keywords;

      --  The four core scanners a grammar may leave undefined: the compiler
      --  injects each as a C jet, and this backend has its own Ada for them.
      function Is_Builtin_Jet (Nm : String) return Boolean is
        (Nm = "word" or else Nm = "int" or else Nm = "str" or else Nm = "ws");

      --  The scanner a jet rule runs: the built-in Ada one, or the stub for
      --  hand-written C.
      function Jet_Fn (Nm : String) return String is
        ((if Is_Builtin_Jet (Nm) then "Scan_" else "Jet_") & Ada_Ident (Nm));

      function Ret_Type (Idx : Natural) return String is
        (Ada_Ident (To_String (Rules (Idx).Name)) & "_Type");

      procedure Emit_Seq
        (Owner : Natural;
         Els : Element_Vectors.Vector; First, Last : Natural;
         Dst : String; Buf : in out U; Ind : String := "      ";
         Alloc_Records : Boolean := False) is
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               case E.Kind is
                  when Literal =>
                     declare
                        Lit : constant String := To_String (E.Lit);
                     begin
                        Append (Buf, Ind & "Skip_Ws (P);");
                        Append (Buf, LF);
                        Append (Buf, Ind
                          & (if E.No_Case then "Expect_Word_Nocase"
                             elsif Is_Keyword_Lit (Lit) then "Expect_Word"
                             else "Expect_Lit")
                          & " (P, """ & Ada_Escape (Lit) & """);");
                        Append (Buf, LF);
                     end;
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        --  A core scalar: run its scanner at the position and
                        --  convert the matched text.
                        declare
                           NM : constant String := To_String (E.Name);
                        begin
                           Append (Buf, Ind & "Skip_Ws (P);");
                           Append (Buf, LF);
                           Append (Buf, Ind & "declare");
                           Append (Buf, LF);
                           Append (Buf, Ind & "   N : constant Natural := "
                             & Scan_Fn (NM)
                             & " (P.Text.all, P.Pos, P.Text'Last);");
                           Append (Buf, LF);
                           Append (Buf, Ind & "begin");
                           Append (Buf, LF);
                           Append (Buf, Ind & "   if N = 0" & Scalar_Reject (NM)
                             & " then Fail (P, """ & Core_Desc (NM)
                             & """); end if;");
                           Append (Buf, LF);
                           Append (Buf, Ind & "   " & Dst
                             & Ada_Field (NM) & " := " & Scalar_Value (NM)
                             & "; P.Pos := P.Pos + N;");
                           Append (Buf, LF);
                           Append (Buf, Ind & "end;");
                           Append (Buf, LF);
                        end;
                     elsif Is_Char_Rule (Rules, To_String (E.Name)) then
                        --  A char-rule reference runs its scanner here and
                        --  yields the matched text, as a core `str` would.
                        declare
                           NM : constant String := To_String (E.Name);
                        begin
                           Append (Buf, Ind & "Skip_Ws (P);");
                           Append (Buf, LF);
                           Append (Buf, Ind & "declare");
                           Append (Buf, LF);
                           Append (Buf, Ind & "   N : constant Natural := Scan_"
                             & Ada_Ident (NM)
                             & " (P.Text.all, P.Pos, P.Text'Last);");
                           Append (Buf, LF);
                           Append (Buf, Ind & "begin");
                           Append (Buf, LF);
                           Append (Buf, Ind & "   if N = 0 then Fail (P, """
                             & NM & """); end if;");
                           Append (Buf, LF);
                           Append (Buf, Ind & "   " & Dst & Ada_Field (NM)
                             & " := To_Unbounded_String"
                             & " (P.Text (P.Pos .. P.Pos + N - 1));"
                             & " P.Pos := P.Pos + N;");
                           Append (Buf, LF);
                           Append (Buf, Ind & "end;");
                           Append (Buf, LF);
                        end;
                     else
                        declare
                           NM : constant String := To_String (E.Name);
                           Back : constant Boolean :=
                             Is_Back (Backs, Owner, NM);
                           --  A back-edge member names an alias over a record,
                           --  so it is allocated as that record; a struct
                           --  member is allocated as itself.
                           TN : constant String :=
                             (if Back
                              then Ada_Ident
                                (To_String
                                   (Rules (Leaf_Record (Rules, NM)).Name))
                                & "_Type"
                              else Ada_Ident (NM) & "_Type");
                        begin
                           Append (Buf, Ind & "Skip_Ws (P);");
                           Append (Buf, LF);
                           if Alloc_Records
                             and then (Is_Struct (NM) or else Back)
                           then
                              Append (Buf, Ind & Dst & Ada_Field (NM)
                                & " := new " & TN & "'(Parse_"
                                & Ada_Ident (NM) & " (P));");
                           else
                              Append (Buf, Ind & Dst & Ada_Field (NM)
                                & " := Parse_" & Ada_Ident (NM) & " (P);");
                           end if;
                           Append (Buf, LF);
                        end;
                     end if;
                  when Group =>
                     Emit_Seq (Owner, E.Items, 1, Natural (E.Items.Length),
                               Dst, Buf, Ind & "   ", Alloc_Records);
                  when Alt =>
                     null;
                  when Char_Range =>
                     null;
                  when Block =>
                     null;  --  lifted to a rule of its own before emission
               end case;
            end;
         end loop;
      end Emit_Seq;

      --  Emit a backtracking alternation over the Alt-separated branches in
      --  Els.  Each branch runs in its own `declare` block with a fresh R, so a
      --  partial match never leaves stale fields; a failed branch restores
      --  P.Pos (via the caller's Save) and falls to the next, a successful one
      --  returns R directly.  After the last branch fails, control falls
      --  through for the caller's own failure handling.
      procedure Emit_Alternation
        (Owner : Natural;
         Els : Element_Vectors.Vector; TN : String;
         Buf : in out U; Ind : String := "         ";
         Alloc_Records : Boolean := False) is
         N  : constant Natural := Natural (Els.Length);
         St : Natural := 1;
         Br : Natural := 0;
      begin
         for K in 1 .. N + 1 loop
            if K > N or else Els (K).Kind = Alt then
               Br := Br + 1;
               if Br > 1 then
                  Append (Buf, Ind & "P.Pos := Save;");
                  Append (Buf, LF);
               end if;
               Append (Buf, Ind & "declare");
               Append (Buf, LF);
               Append (Buf, Ind & "   R : " & TN & ";");
               Append (Buf, LF);
               Append (Buf, Ind & "begin");
               Append (Buf, LF);
               Emit_Seq (Owner, Els, St, K - 1, "R.", Buf, Ind & "   ",
                        Alloc_Records);
               Append (Buf, Ind & "   return R;");
               Append (Buf, LF);
               Append (Buf, Ind & "exception");
               Append (Buf, LF);
               Append (Buf, Ind & "   when Parse_Error => null;");
               Append (Buf, LF);
               Append (Buf, Ind & "end;");
               Append (Buf, LF);
               St := K + 1;
            end if;
         end loop;
      end Emit_Alternation;

      procedure Emit_Rule_Decl (Idx : Natural; Buf : in out U) is
         R        : constant Rule := Rules (Idx);
         P        : constant Element_Vectors.Vector := R.Pattern;
         TN       : constant String := Ada_Ident (To_String (R.Name)) & "_Type";
         Delegate : constant Boolean :=
           Natural (P.Length) = 1 and then P (1).Kind = HBNF_Grammar.Name
             and then P (1).Min = 1 and then P (1).Max = 1
             and then not Is_Core (To_String (P (1).Name))
             and then not Is_Char_Rule (Rules, To_String (R.Name));
      begin
         if not Delegate then
            Append (Buf, "   R : " & TN & ";");
            Append (Buf, LF);
            if Natural (P.Length) = 1
              and then (P (1).Min /= 1 or else P (1).Max /= 1)
              and then P (1).Kind = HBNF_Grammar.Group
            then
               Append (Buf, "   Save : Natural;");
               Append (Buf, LF);
            end if;
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
         SU : constant String := (if not Is_List then Scalar_Union_Type (Rules, P) else "");

         --  The lines that run a scanner at the position and, when it matched,
         --  yield the text: a char rule, or a jet (a built-in scanner or the
         --  stub for C code this backend cannot run).
         procedure Emit_Scan_Text (Fn, Desc : String) is
         begin
            Append (Buf, "      declare");
            Append (Buf, LF);
            Append (Buf, "         N : constant Natural := " & Fn
              & " (P.Text.all, P.Pos, P.Text'Last);");
            Append (Buf, LF);
            Append (Buf, "      begin");
            Append (Buf, LF);
            Append (Buf, "         if N = 0 then Fail (P, """ & Desc & """); end if;");
            Append (Buf, LF);
            Append (Buf, "         R := To_Unbounded_String (P.Text (P.Pos .. P.Pos + N - 1));");
            Append (Buf, LF);
            Append (Buf, "         P.Pos := P.Pos + N;");
            Append (Buf, LF);
            Append (Buf, "         return R;");
            Append (Buf, LF);
            Append (Buf, "      end;");
            Append (Buf, LF);
         end Emit_Scan_Text;

         --  The condition that literal L is at the position: a keyword by the
         --  `word` scanner (so `in` never matches `input`), any other literal
         --  by its bytes; in any case for a %i literal.
         function Lit_At (L : Element_Access) return String is
            S  : constant String := To_String (L.Lit);
            NL : constant String := Img (S'Length);
            Sl : constant String := "P.Text (P.Pos .. P.Pos + " & NL & " - 1)";
            Eq : constant String :=
              (if L.No_Case
               then "Ada.Strings.Equal_Case_Insensitive (" & Sl & ", """
                    & Ada_Escape (S) & """)"
               else Sl & " = """ & Ada_Escape (S) & """");
         begin
            if Is_Keyword_Lit (S) then
               return "Scan_Word (P.Text.all, P.Pos, P.Text'Last) = " & NL
                 & " and then " & Eq;
            end if;
            return "P.Pos + " & NL & " - 1 <= P.Text'Last and then " & Eq;
         end Lit_At;
      begin
         if Is_Char_Rule (Rules, NM) then
            --  A char rule is a scanner: run it here and capture the text.
            Emit_Scan_Text ("Scan_" & Ada_Ident (NM), NM);
            return;
         end if;
         if R.Jet_Code /= Null_Unbounded_String then
            --  A jet: its scanner (a built-in) or the stub for hand-written C.
            Emit_Scan_Text (Jet_Fn (NM), "a " & NM);
            return;
         end if;
         if Is_List then
            declare
               E      : constant Element_Access := P (1);
               --  A list of a single rule reference: `1*name` or `*( name )`.
               Simple : constant Unbounded_String :=
                 (if E.Kind = HBNF_Grammar.Name then E.Name
                  elsif E.Kind = HBNF_Grammar.Group
                    and then Natural (E.Items.Length) = 1
                    and then E.Items (1).Kind = HBNF_Grammar.Name
                  then E.Items (1).Name
                  else Null_Unbounded_String);
               --  A group of literals only, `0*1( "log" )`, has no fields:
               --  its entries are strings, as the type declaration says.
               function Has_Name (V : Element_Vectors.Vector) return Boolean is
                 (for some X of V =>
                    X.Kind = HBNF_Grammar.Name
                    or else (X.Kind = HBNF_Grammar.Group
                             and then Has_Name (X.Items)));
               Elem : constant String :=
                 (if Simple /= Null_Unbounded_String
                  then Ada_Type_Of (Rules, To_String (Simple))
                  elsif E.Kind = HBNF_Grammar.Group and then not Has_Name (E.Items)
                  then "Unbounded_String"
                  else Ada_Ident (NM) & "_Entry");
            begin
               if E.Min > 0 then
                  --  Repetition bounds, as the C backend enforces them.
                  Append (Buf, "      declare");
                  Append (Buf, LF);
                  Append (Buf, "         Start : constant Natural := P.Pos;");
                  Append (Buf, LF);
                  Append (Buf, "      begin");
                  Append (Buf, LF);
               end if;
               if Simple /= Null_Unbounded_String then
                  --  PEG's `*`: stop at the end of input and at the first
                  --  element that fails, with the position restored; the
                  --  caller then decides.
                  Append (Buf, "      loop");
                  Append (Buf, LF);
                  if E.Max >= 0 then
                     Append (Buf, "         exit when Natural (R.Length) >= "
                       & Img (Natural (E.Max)) & ";");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "         declare");
                  Append (Buf, LF);
                  Append (Buf, "            Start : constant Natural := P.Pos;");
                  Append (Buf, LF);
                  Append (Buf, "         begin");
                  Append (Buf, LF);
                  Append (Buf, "            Skip_Ws (P);");
                  Append (Buf, LF);
                  if not Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "            if P.Pos > P.Text'Last then P.Pos := Start; exit; end if;");
                     Append (Buf, LF);
                  end if;
                  if Is_Core (To_String (Simple)) then
                     --  A list of a core type (`*word`): read the text in
                     --  place; there is no Parse_ function for a core type.
                     Append (Buf, "            declare");
                     Append (Buf, LF);
                     Append (Buf, "               N : constant Natural := "
                       & Scan_Fn (To_String (Simple))
                       & " (P.Text.all, P.Pos, P.Text'Last);");
                     Append (Buf, LF);
                     Append (Buf, "            begin");
                     Append (Buf, LF);
                     Append (Buf, "               if N = 0"
                       & Scalar_Reject (To_String (Simple))
                       & " then P.Pos := Start; exit; end if;");
                     Append (Buf, LF);
                     Append (Buf, "               R.Append ("
                       & Scalar_Value (To_String (Simple)) & ");");
                     Append (Buf, LF);
                     Append (Buf, "               P.Pos := P.Pos + N;");
                     Append (Buf, LF);
                     Append (Buf, "            end;");
                  elsif Is_Struct (To_String (Simple)) then
                     Append (Buf, "            R.Append (new "
                       & Ada_Ident (To_String (Simple)) & "_Type'(Parse_"
                       & Ada_Ident (To_String (Simple)) & " (P)));");
                  else
                     Append (Buf, "            R.Append (Parse_"
                       & Ada_Ident (To_String (Simple)) & " (P));");
                  end if;
                  Append (Buf, LF);
                  --  What is repeated can match nothing: an iteration that
                  --  did not advance would match the same nothing again.
                  if Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "            exit when P.Pos = Start;");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "         exception");
                  Append (Buf, LF);
                  Append (Buf, "            when Parse_Error => P.Pos := Start; exit;");
                  Append (Buf, LF);
                  Append (Buf, "         end;");
                  Append (Buf, LF);
                  Append (Buf, "      end loop;");
                  Append (Buf, LF);
               elsif E.Kind = Group then
                  Append (Buf, "      loop");
                  Append (Buf, LF);
                  if E.Max >= 0 then
                     Append (Buf, "         exit when Natural (R.Length) >= "
                       & Img (Natural (E.Max)) & ";");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "         Save := P.Pos;");
                  Append (Buf, LF);
                  Append (Buf, "         declare");
                  Append (Buf, LF);
                  Append (Buf, "            E : " & Elem & ";");
                  Append (Buf, LF);
                  Append (Buf, "            Matched : Boolean := False;");
                  Append (Buf, LF);
                  Append (Buf, "         begin");
                  Append (Buf, LF);
                  declare
                     St : Natural := 1;
                     Br : Natural := 0;
                  begin
                     for K in 1 .. Natural (E.Items.Length) + 1 loop
                        if K > Natural (E.Items.Length)
                          or else E.Items (K).Kind = Alt
                        then
                           Br := Br + 1;
                           if St <= K - 1 then
                              --  Left recursion, as a loop: the first entry
                              --  is a base, each later one a tail.
                              Append (Buf, "            if not Matched"
                                & (if R.Left_Bases = 0 then ""
                                   elsif Br <= R.Left_Bases
                                   then " and then R.Is_Empty"
                                   else " and then not R.Is_Empty")
                                & " then");
                              Append (Buf, LF);
                              Append (Buf, "               declare");
                              Append (Buf, LF);
                              Append (Buf, "                  El : " & Elem & ";");
                              Append (Buf, LF);
                              Append (Buf, "               begin");
                              Append (Buf, LF);
                              Emit_Seq (Idx, E.Items, St, K - 1, "El.",
                                        Buf, "                  ", True);
                              Append (Buf, "                  E := El; Matched := True;");
                              Append (Buf, LF);
                              Append (Buf, "               exception");
                              Append (Buf, LF);
                              Append (Buf, "                  when Parse_Error => P.Pos := Save;");
                              Append (Buf, LF);
                              Append (Buf, "               end;");
                              Append (Buf, LF);
                              Append (Buf, "            end if;");
                              Append (Buf, LF);
                           end if;
                           St := K + 1;
                        end if;
                     end loop;
                  end;
                  Append (Buf, "            exit when not Matched;");
                  Append (Buf, LF);
                  Append (Buf, "            R.Append (E);");
                  Append (Buf, LF);
                  if Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "            exit when P.Pos = Save;");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "         end;");
                  Append (Buf, LF);
                  Append (Buf, "      end loop;");
                  Append (Buf, LF);
               end if;
               if E.Min > 0 then
                  Append (Buf, "         if Natural (R.Length) < " & Img (E.Min)
                    & " then P.Pos := Start; Fail (P, ""a " & NM & """); end if;");
                  Append (Buf, LF);
                  Append (Buf, "      end;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "      return R;");
               Append (Buf, LF);
            end;
         elsif Is_Enum then
            --  Each alternative matches its literal at the position, in order:
            --  a keyword by the `word` scanner, any other literal by its bytes.
            Append (Buf, "      if P.Pos > P.Text'Last then Fail (P, ""a " & TN & """); end if;");
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
                        Append (Buf, (if Branch = 0 then "      if " else "      elsif ")
                          & Lit_At (P (St)) & " then");
                        Append (Buf, LF);
                        Append (Buf, "         R := " & Ada_Ident (NM) & "_"
                          & To_String (Names (Branch + 1))
                          & "; P.Pos := P.Pos + "
                          & Img (To_String (P (St).Lit)'Length) & ";");
                        Append (Buf, LF);
                        Branch := Branch + 1;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "      else Fail (P, """);
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
                        Append (Buf, "`" & Ada_Escape (To_String (P (St).Lit)) & "`");
                        First := False;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, """); end if;");
            Append (Buf, LF);
            Append (Buf, "      return R;");
            Append (Buf, LF);
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            if Is_Core (To_String (P (1).Name)) then
               declare
                  CN : constant String := To_String (P (1).Name);
               begin
                  Append (Buf, "      declare");
                  Append (Buf, LF);
                  Append (Buf, "         N : constant Natural := " & Scan_Fn (CN)
                    & " (P.Text.all, P.Pos, P.Text'Last);");
                  Append (Buf, LF);
                  Append (Buf, "      begin");
                  Append (Buf, LF);
                  Append (Buf, "         if N = 0" & Scalar_Reject (CN)
                    & " then Fail (P, """ & Core_Desc (CN) & """); end if;");
                  Append (Buf, LF);
                  Append (Buf, "         R := " & Scalar_Value (CN)
                    & "; P.Pos := P.Pos + N;");
                  Append (Buf, LF);
                  Append (Buf, "         return R;");
                  Append (Buf, LF);
                  Append (Buf, "      end;");
                  Append (Buf, LF);
               end;
            else
               Append (Buf, "      return Parse_"
                 & Ada_Ident (To_String (P (1).Name)) & " (P);");
               Append (Buf, LF);
            end if;
         elsif SU /= "" then
            --  A scalar union (str | word, ipv4 | ipv6): try each branch as a
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
                              declare
                                 CN : constant String := To_String (E.Name);
                              begin
                                 Append (Buf, "      declare");
                                 Append (Buf, LF);
                                 Append (Buf, "         N : constant Natural := "
                                   & Scan_Fn (CN)
                                   & " (P.Text.all, P.Pos, P.Text'Last);");
                                 Append (Buf, LF);
                                 Append (Buf, "      begin");
                                 Append (Buf, LF);
                                 Append (Buf, "         if N > 0"
                                   & Scalar_Guard (CN) & " then");
                                 Append (Buf, LF);
                                 Append (Buf, "            R := " & Scalar_Value (CN)
                                   & "; P.Pos := P.Pos + N; return R;");
                                 Append (Buf, LF);
                                 Append (Buf, "         end if;");
                                 Append (Buf, LF);
                                 Append (Buf, "      end;");
                                 Append (Buf, LF);
                              end;
                           elsif E.Kind = Name then
                              Append (Buf, "      begin");
                              Append (Buf, LF);
                              Append (Buf, "         R := Parse_" & Ada_Ident (To_String (E.Name)) & " (P);");
                              Append (Buf, LF);
                              Append (Buf, "         return R;");
                              Append (Buf, LF);
                              Append (Buf, "      exception");
                              Append (Buf, LF);
                              Append (Buf, "         when Parse_Error => null;");
                              Append (Buf, LF);
                              Append (Buf, "      end;");
                              Append (Buf, LF);
                           end if;
                        end;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "      Fail (P, ""a " & NM & """);");
            Append (Buf, LF);
            Append (Buf, "      return R;");
            Append (Buf, LF);
         elsif Has_Alt (P) then
            --  A struct alternation: try each branch with backtracking.
            Append (Buf, "      declare");
            Append (Buf, LF);
            Append (Buf, "         Save : constant Natural := P.Pos;");
            Append (Buf, LF);
            Append (Buf, "      begin");
            Append (Buf, LF);
            Emit_Alternation (Idx, P, TN, Buf, "         ", True);
            Append (Buf, "         P.Pos := Save;");
            Append (Buf, LF);
            Append (Buf, "         Fail (P, ""a " & NM & """);");
            Append (Buf, LF);
            Append (Buf, "         return R;");
            Append (Buf, LF);
            Append (Buf, "      end;");
            Append (Buf, LF);
         else
            Emit_Seq (Idx, P, 1, Natural (P.Length), "R.", Buf, "      ",
                      True);
            Append (Buf, "      return R;");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Parser;

      Spec  : U;
      Bdy  : U;

      --  The built-in scanners, for each of word/int/str/ws that is a jet in
      --  the grammar (not defined as a char rule), and `word` besides when
      --  the grammar names no `word` at all, since a keyword is matched by it.
      procedure Emit_Builtin_Scans is
         function Is_Jet (Nm : String) return Boolean is
            J : constant Natural := Find (Rules, Nm);
         begin
            return J > 0 and then Rules (J).Jet_Code /= Null_Unbounded_String;
         end Is_Jet;

         procedure Put (Text : String) is
         begin
            Append (Bdy, Text);
            Append (Bdy, LF);
         end Put;
      begin
         if Is_Jet ("word") or else Find (Rules, "word") = 0 then
            Put ("   function Scan_Word (S : String; Pos, Len : Natural) return Natural is");
            Put ("      I : Natural := Pos;");
            Put ("   begin");
            Put ("      if I > Len");
            Put ("        or else S (I) not in 'a' .. 'z' | 'A' .. 'Z' | '_' | '-'");
            Put ("      then");
            Put ("         return 0;");
            Put ("      end if;");
            Put ("      I := I + 1;");
            Put ("      while I <= Len");
            Put ("        and then S (I) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '.'");
            Put ("      loop");
            Put ("         I := I + 1;");
            Put ("      end loop;");
            Put ("      return I - Pos;");
            Put ("   end Scan_Word;");
            Put ("");
         end if;
         if Is_Jet ("int") then
            Put ("   function Scan_Int (S : String; Pos, Len : Natural) return Natural is");
            Put ("      I     : Natural := Pos;");
            Put ("      Start : Natural;");
            Put ("   begin");
            Put ("      if I < Len and then S (I) = '-' and then S (I + 1) in '0' .. '9' then");
            Put ("         I := I + 1;");
            Put ("      end if;");
            Put ("      Start := I;");
            Put ("      while I <= Len and then S (I) in '0' .. '9' loop");
            Put ("         I := I + 1;");
            Put ("      end loop;");
            Put ("      return (if I > Start then I - Pos else 0);");
            Put ("   end Scan_Int;");
            Put ("");
         end if;
         if Is_Jet ("str") then
            Put ("   function Scan_Str (S : String; Pos, Len : Natural) return Natural is");
            Put ("      I : Natural;");
            Put ("   begin");
            Put ("      if Pos > Len or else S (Pos) /= '""' then");
            Put ("         return 0;");
            Put ("      end if;");
            Put ("      I := Pos + 1;");
            Put ("      while I <= Len and then S (I) /= '""' loop");
            Put ("         if S (I) = '\' and then I < Len then");
            Put ("            I := I + 1;");
            Put ("         end if;");
            Put ("         I := I + 1;");
            Put ("      end loop;");
            Put ("      if I > Len then");
            Put ("         return 0;");
            Put ("      end if;");
            Put ("      return I + 1 - Pos;");
            Put ("   end Scan_Str;");
            Put ("");
         end if;
         if Is_Jet ("ws") then
            Put ("   function Scan_Ws (S : String; Pos, Len : Natural) return Natural is");
            Put ("   begin");
            Put ("      if Pos <= Len");
            Put ("        and then S (Pos) in ' ' | ASCII.HT | ASCII.CR | ASCII.LF");
            Put ("      then");
            Put ("         return 1;");
            Put ("      end if;");
            Put ("      return 0;");
            Put ("   end Scan_Ws;");
            Put ("");
         end if;
      end Emit_Builtin_Scans;

      --  The generated Free_<rule> declarations (for the child spec) and
      --  bodies (for the child body), filled once before either is rendered.
      Free_Decls : U;
      Free_Body  : U;

      --  Emit the greedy loop for a repetition: match one full branch of the
      --  DNF (the longest one) as many times as Max allows (0 = unbounded),
      --  then require Min.  A branch is a sequence of decoded code points.
      --  Fail runs when fewer than Min iterations matched (`return 0` in a
      --  single branch, `Ok := False` in an alternation branch) and names the
      --  caller's variables, so the branch locals are `Match`/`O`/`Br`, not
      --  the caller's `Ok`.
      procedure Emit_Repeat (A : Cp_Atom; Ind : String; Fail : String) is
      begin
         Append (Bdy, Ind & "declare");
         Append (Bdy, LF);
         Append (Bdy, Ind & "   Cnt : Natural := 0;");
         Append (Bdy, LF);
         Append (Bdy, Ind & "begin");
         Append (Bdy, LF);
         if A.Max = 0 then
            Append (Bdy, Ind & "   loop");
         else
            Append (Bdy, Ind & "   while Cnt < " & Img (A.Max) & " loop");
         end if;
         Append (Bdy, LF);
         Append (Bdy, Ind & "      declare");
         Append (Bdy, LF);
         Append (Bdy, Ind & "         Br    : Natural := 0;");
         Append (Bdy, LF);
         Append (Bdy, Ind & "         O     : Natural;");
         Append (Bdy, LF);
         Append (Bdy, Ind & "         Match : Boolean;");
         Append (Bdy, LF);
         Append (Bdy, Ind & "      begin");
         Append (Bdy, LF);
         for B of A.Sub loop
            Append (Bdy, Ind & "         O := 0;");
            Append (Bdy, LF);
            Append (Bdy, Ind & "         Match := True;");
            Append (Bdy, LF);
            for Rg of B loop
               Append (Bdy, Ind & "         if Match then");
               Append (Bdy, LF);
               Append (Bdy, Ind & "            N := Decode_Utf8 (S, Pos + Off + O, Len, Cp);");
               Append (Bdy, LF);
               Append (Bdy, Ind & "            Match := N > 0 and then "
                 & Range_Cond (Rg.Lo, Rg.Hi) & ";");
               Append (Bdy, LF);
               Append (Bdy, Ind & "            if Match then O := O + N; end if;");
               Append (Bdy, LF);
               Append (Bdy, Ind & "         end if;");
               Append (Bdy, LF);
            end loop;
            Append (Bdy, Ind & "         if Match and then O > Br then Br := O; end if;");
            Append (Bdy, LF);
         end loop;
         Append (Bdy, Ind & "         exit when Br = 0;");
         Append (Bdy, LF);
         Append (Bdy, Ind & "         Off := Off + Br;");
         Append (Bdy, LF);
         Append (Bdy, Ind & "         Cnt := Cnt + 1;");
         Append (Bdy, LF);
         Append (Bdy, Ind & "      end;");
         Append (Bdy, LF);
         Append (Bdy, Ind & "   end loop;");
         Append (Bdy, LF);
         if A.Min > 0 then
            Append (Bdy, Ind & "   if Cnt < " & Img (A.Min) & " then " & Fail & "; end if;");
            Append (Bdy, LF);
         end if;
         Append (Bdy, Ind & "end;");
         Append (Bdy, LF);
      end Emit_Repeat;
   begin
      --  Free_<rule>: release a tree the parse functions built.  A consumer
      --  calls Free_<root> once it is finished with one, and the access nodes
      --  go back to the heap.  The parser is untouched -- a parse that fails
      --  part-way still abandons its partial tree, as it always has -- so this
      --  is purely a dispose for the caller, and the first lifetime code the
      --  Ada backend emits.  It lives in this child package because the
      --  parent is a spec with no body, and adding one would change the files
      --  the generator writes.
      declare
         --  The loop releasing every element of a vector of the named record:
         --  each element is an access node the parse appended with `new`.  A
         --  local stands in for the element because Unchecked_Deallocation
         --  takes its argument `in out`, and a vector element reached through
         --  `V (K)` is a function call, not a variable.
         procedure Free_Vector (Buf : in out U; Vec, Elem : String) is
         begin
            Append (Buf, "   for K in " & Vec & ".First_Index .. "
                    & Vec & ".Last_Index loop" & LF);
            Append (Buf, "      declare" & LF);
            Append (Buf, "         E : " & Elem & "_Access := " & Vec
                    & " (K);" & LF);
            Append (Buf, "      begin" & LF);
            Append (Buf, "         if E /= null then" & LF);
            Append (Buf, "            Free_" & Elem & " (E.all);" & LF);
            Append (Buf, "            " & Vec & ".Replace_Element (K, null);"
                    & LF);
            Append (Buf, "            Dealloc_" & Elem & " (E);" & LF);
            Append (Buf, "         end if;" & LF);
            Append (Buf, "      end;" & LF);
            Append (Buf, "   end loop;" & LF);
         end Free_Vector;

         --  The loop releasing every element of a vector whose elements are
         --  themselves vectors, each freed by its own list rule's Free_.  The
         --  element is a copy (Free_ takes it `in out`), so it is stored back:
         --  the original would otherwise keep the pointers just released.
         procedure Free_List_Vector (Buf : in out U; Vec, Elem : String) is
         begin
            Append (Buf, "   for K in " & Vec & ".First_Index .. "
                    & Vec & ".Last_Index loop" & LF);
            Append (Buf, "      declare" & LF);
            Append (Buf, "         E : " & Elem & "_Type := " & Vec
                    & " (K);" & LF);
            Append (Buf, "      begin" & LF);
            Append (Buf, "         Free_" & Elem & " (E);" & LF);
            Append (Buf, "         " & Vec & ".Replace_Element (K, E);" & LF);
            Append (Buf, "      end;" & LF);
            Append (Buf, "   end loop;" & LF);
         end Free_List_Vector;

         --  One member of a record, released in place.  Prefix is how the record
         --  is named: `V.` for the parameter, `E.` for a local copy of a vector
         --  element.
         procedure Free_Member
           (Idx : Natural; M : Member; Prefix : String; Buf : in out U) is
            NM  : constant String := To_String (M.Name);
            F   : constant String := Ada_Field (NM);
            J   : constant Natural := Find (Rules, NM);
            --  The record this member's field is an access to: its own rule
            --  when that is a record, else the record its alias chain reaches
            --  (which is what a back-edge member names).
            Rec : constant Natural :=
              (if J > 0 and then Is_Record (Analyze (Rules, J)) then
                  J
               elsif Is_Back (Backs, Idx, NM) then
                  Leaf_Record (Rules, NM)
               else
                  0);
         begin
            if M.Is_List then
               --  A vector declared for this member.  Its elements are the
               --  element rule's access nodes whenever Emit made that rule a
               --  record, which is exactly when they were allocated.
               if J > 0 and then Is_Record (Analyze (Rules, J)) then
                  Free_Vector (Buf, Prefix & F, Ada_Ident (NM));
               elsif J > 0 and then Over_Leaf (Rules, J)
                 and then Analyze (Rules, Leaf_Target (Rules, J)).Kind = List
               then
                  Free_List_Vector
                    (Buf, Prefix & F,
                     Ada_Ident (To_String (Rules (Leaf_Target (Rules, J)).Name)));
               end if;
            elsif Rec > 0 then
               Append (Buf, "   if " & Prefix & F & " /= null then" & LF);
               Append (Buf, "      Free_"
                       & Ada_Ident (To_String (Rules (Rec).Name))
                       & " (" & Prefix & F & ".all);" & LF);
               Append (Buf, "      Dealloc_"
                       & Ada_Ident (To_String (Rules (Rec).Name))
                       & " (" & Prefix & F & ");" & LF);
               Append (Buf, "   end if;" & LF);
            elsif J > 0 and then Analyze (Rules, J).Kind = List then
               --  A member naming a list rule: that rule's own Free_ walks
               --  the vector it is a subtype of.
               Append (Buf, "   Free_" & Ada_Ident (NM) & " (" & Prefix & F & ");"
                       & LF);
            elsif J > 0 and then Analyze (Rules, J).Kind = Scalar
              and then Over_Leaf (Rules, J)
            then
               --  A record held by value through an alias (`src = host`).
               --  The alias's subtype denotes the same record, so its own
               --  Free_ takes it as it stands.
               Append (Buf, "   Free_"
                       & Ada_Ident
                           (To_String (Rules (Leaf_Record (Rules, NM)).Name))
                       & " (" & Prefix & F & ");" & LF);
            end if;
            --  Anything else -- a scalar, an enum, an Unbounded_String --
            --  owns no heap node; the string finalizes itself.
         end Free_Member;
      begin
         --  One Unchecked_Deallocation instance per record access type, in the
         --  child body so a consumer never sees them.
         for I in 1 .. N loop
            if Is_Record (Analyze (Rules, I)) then
               Append (Free_Body, "   procedure Dealloc_"
                       & Ada_Ident (To_String (Rules (I).Name))
                       & " is new Ada.Unchecked_Deallocation ("
                       & Ada_Ident (To_String (Rules (I).Name)) & "_Type, "
                       & Ada_Ident (To_String (Rules (I).Name)) & "_Access);"
                       & LF);
            end if;
         end loop;
         Append (Free_Body, LF);

         for I in 1 .. N loop
            declare
               Info : constant Rule_Info := Analyze (Rules, I);
               CN   : constant String :=
                 Ada_Ident (To_String (Rules (I).Name));
            begin
               if Is_Record (Info) or else Info.Kind = List then
                  declare
                     Stmts : U;
                  begin
                     if Is_Record (Info) then
                        for M of Info.Members loop
                           Free_Member (I, M, "V.", Stmts);
                        end loop;
                     elsif Info.Elem_Members.Is_Empty
                       and then Info.Elem_Name /= Null_Unbounded_String
                     then
                        declare
                           E : constant Natural :=
                             Find (Rules, To_String (Info.Elem_Name));
                        begin
                           if E > 0 and then Is_Record (Analyze (Rules, E))
                           then
                              Free_Vector (Stmts, "V",
                                Ada_Ident (To_String (Info.Elem_Name)));
                           elsif E > 0 and then Over_Leaf (Rules, E)
                             and then Analyze
                               (Rules, Leaf_Target (Rules, E)).Kind = List
                           then
                              --  A list of lists (`sums = 1*sum`).
                              Free_List_Vector
                                (Stmts, "V",
                                 Ada_Ident
                                   (To_String
                                      (Rules (Leaf_Target (Rules, E)).Name)));
                           end if;
                        end;
                     elsif not Info.Elem_Members.Is_Empty then
                        --  A group element is a record held by value in the
                        --  vector, holding the access nodes of its members.
                        --  Each is freed on a copy that is then stored back.
                        --  An entry's members are typed bare, not as vectors.
                        declare
                           Inner : U;
                        begin
                           for M of Info.Elem_Members loop
                              Free_Member
                                (I, (Name => M.Name, Is_List => False),
                                 "E.", Inner);
                           end loop;
                           if To_String (Inner) /= "" then
                              Append (Stmts, "   for K in V.First_Index .. "
                                      & "V.Last_Index loop" & LF);
                              Append (Stmts, "      declare" & LF);
                              Append (Stmts, "         E : " & CN & "_Entry := V (K);"
                                      & LF);
                              Append (Stmts, "      begin" & LF);
                              Append (Stmts, To_String (Inner));
                              Append (Stmts, "         V.Replace_Element (K, E);"
                                      & LF);
                              Append (Stmts, "      end;" & LF);
                              Append (Stmts, "   end loop;" & LF);
                           end if;
                        end;
                     end if;

                     Append (Free_Decls, "   procedure Free_" & CN
                             & " (V : in out " & CN & "_Type);" & LF);
                     Append (Free_Body, "   procedure Free_" & CN
                             & " (V : in out " & CN & "_Type) is" & LF);
                     if To_String (Stmts) = "" then
                        --  Nothing to release: say so, and say the parameter
                        --  is deliberately unused (a statement list may not
                        --  be empty, and a silent unused parameter warns).
                        Append (Free_Body, "      pragma Unreferenced (V);" & LF);
                        Append (Free_Body, "   begin" & LF);
                        Append (Free_Body, "      null;" & LF);
                     else
                        Append (Free_Body, "   begin" & LF);
                        Append (Free_Body, To_String (Stmts));
                     end if;
                     Append (Free_Body, "   end Free_" & CN & ";" & LF);
                     Append (Free_Body, LF);
                  end;
               end if;
            end;
         end loop;
      end;

      --  Package specification: the exception and Parse_Text (and Parse_Config).
      declare
         Conf_Decl : constant String :=
           (if Conf
            then "   function Parse_Config (Filename : String) return "
                 & Ret_Type (1) & ";" & LF & LF
            else "");
         V : Mustache.Context := Mustache.View;
      begin
         Mustache.Put (V, "pkg", Package_Name);
         Mustache.Put (V, "ret", Ret_Type (1));
         Mustache.Put (V, "conf", Conf_Decl);
         Mustache.Put (V, "frees", To_String (Free_Decls));
         Append (Spec, Mustache.Render_File ("ada_parser_spec", V));
         Append (Spec, LF);
      end;

      --  Package body, in the order Ada needs: the scanners, then the parser
      --  primitives that call them, then the rules.
      declare
         Nocase_With : constant String :=
           (if Has_No_Case (Rules)
            then "with Ada.Strings.Equal_Case_Insensitive;" & LF
            else "");
         Conf_With : constant String :=
           (if Conf then "with Ada.Text_IO;" & LF else "");
         V : Mustache.Context := Mustache.View;
      begin
         Mustache.Put (V, "pkg", Package_Name);
         Mustache.Put (V, "nocase_with", Nocase_With);
         Mustache.Put (V, "conf_with", Conf_With);
         Mustache.Put (V, "free_with", "with Ada.Unchecked_Deallocation;" & LF);
         Append (Bdy, Mustache.Render_File ("ada_parser_body", V));
      end;

      --  The scanners.  A core rule the grammar does not define (`word`,
      --  `int`, `str`, `ws`) is a built-in: hand-written Ada, the same scan
      --  the C backend's jets make.  Any other jet is hand-written C, which
      --  this backend cannot run, so it is a stub that matches nothing.
      Emit_Builtin_Scans;
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String
           and then not Is_Builtin_Jet (To_String (Rules (I).Name))
         then
            declare
               NM : constant String := To_String (Rules (I).Name);
            begin
               Append (Bdy, "   function Jet_" & Ada_Ident (NM)
                 & " (S : String; Pos, Len : Natural) return Natural is");
               Append (Bdy, LF);
               Append (Bdy, "      pragma Unreferenced (S, Pos, Len);");
               Append (Bdy, LF);
               Append (Bdy, "   begin");
               Append (Bdy, LF);
               Append (Bdy, "      return 0;  --  a %scan{} jet: C code only");
               Append (Bdy, LF);
               Append (Bdy, "   end Jet_" & Ada_Ident (NM) & ";");
               Append (Bdy, LF);
               Append (Bdy, LF);
            end;
         end if;
      end loop;

      --  Character-layer scanners (code-point matching, mirroring the C
      --  backend): each char-level rule compiles to a scanner over decoded
      --  UTF-8 code points, and a phrase rule runs it where it names the rule.
      declare
         Has_Char : Boolean := False;
      begin
         for I in 1 .. N loop
            if Is_Char_Rule (Rules, To_String (Rules (I).Name))
              and then (Is_Char_Token (Rules, To_String (Rules (I).Name))
                        or else To_String (Rules (I).Name) = Ws_Name)
            then
               Has_Char := True;
            end if;
         end loop;
         if Has_Char then
            Append (Bdy, "   function Decode_Utf8 (S : String; Pos, Len : Natural; Cp : out Natural) return Natural is");
            Append (Bdy, LF);
            Append (Bdy, "      B0 : Unsigned_32;");
            Append (Bdy, LF);
            Append (Bdy, "      N  : Natural := 0;");
            Append (Bdy, LF);
            Append (Bdy, "      C  : Unsigned_32 := 0;");
            Append (Bdy, LF);
            Append (Bdy, "      B  : Unsigned_32;");
            Append (Bdy, LF);
            Append (Bdy, "   begin");
            Append (Bdy, LF);
            Append (Bdy, "      Cp := 0;");
            Append (Bdy, LF);
            Append (Bdy, "      if Pos > Len then return 0; end if;");
            Append (Bdy, LF);
            Append (Bdy, "      B0 := Unsigned_32 (Character'Pos (S (Pos)));");
            Append (Bdy, LF);
            Append (Bdy, "      if B0 < 16#80# then");
            Append (Bdy, LF);
            Append (Bdy, "         Cp := Natural (B0); return 1;");
            Append (Bdy, LF);
            Append (Bdy, "      elsif (B0 and 16#E0#) = 16#C0# then N := 2; C := B0 and 16#1F#;");
            Append (Bdy, LF);
            Append (Bdy, "      elsif (B0 and 16#F0#) = 16#E0# then N := 3; C := B0 and 16#0F#;");
            Append (Bdy, LF);
            Append (Bdy, "      elsif (B0 and 16#F8#) = 16#F0# then N := 4; C := B0 and 16#07#;");
            Append (Bdy, LF);
            Append (Bdy, "      else return 0;");
            Append (Bdy, LF);
            Append (Bdy, "      end if;");
            Append (Bdy, LF);
            Append (Bdy, "      if Pos + N - 1 > Len then return 0; end if;");
            Append (Bdy, LF);
            Append (Bdy, "      for J in 1 .. N - 1 loop");
            Append (Bdy, LF);
            Append (Bdy, "         B := Unsigned_32 (Character'Pos (S (Pos + J)));");
            Append (Bdy, LF);
            Append (Bdy, "         if (B and 16#C0#) /= 16#80# then return 0; end if;");
            Append (Bdy, LF);
            Append (Bdy, "         C := C * 16#40# or (B and 16#3F#);");
            Append (Bdy, LF);
            Append (Bdy, "      end loop;");
            Append (Bdy, LF);
            Append (Bdy, "      Cp := Natural (C); return N;");
            Append (Bdy, LF);
            Append (Bdy, "   end Decode_Utf8;");
            Append (Bdy, LF);
            Append (Bdy, LF);
         end if;
      end;

      for I in 1 .. N loop
         if Is_Char_Rule (Rules, To_String (Rules (I).Name))
           and then (Is_Char_Token (Rules, To_String (Rules (I).Name))
                     or else To_String (Rules (I).Name) = Ws_Name)
         then
            declare
               NM  : constant String := To_String (Rules (I).Name);
               DNF : constant Cp_Branch_Atom_Vectors.Vector := Char_DNF (Rules, NM);

            begin
               Append (Bdy, "   function Scan_" & Ada_Ident (NM)
                 & " (S : String; Pos, Len : Natural) return Natural is");
               Append (Bdy, LF);
               if Natural (DNF.Length) = 1 then
                  --  One branch: a sequence of code points, decoded in turn,
                  --  ending at most in one repetition.
                  Append (Bdy, "      Cp  : Natural;");
                  Append (Bdy, LF);
                  Append (Bdy, "      N   : Natural;");
                  Append (Bdy, LF);
                  Append (Bdy, "      Off : Natural := 0;");
                  Append (Bdy, LF);
                  Append (Bdy, "   begin");
                  Append (Bdy, LF);
                  for A of DNF (1) loop
                     case A.Kind is
                        when Single =>
                           Append (Bdy, "      N := Decode_Utf8 (S, Pos + Off, Len, Cp);");
                           Append (Bdy, LF);
                           Append (Bdy, "      if N = 0 or else not "
                             & Range_Cond (A.Lo, A.Hi) & " then return 0; end if;");
                           Append (Bdy, LF);
                           Append (Bdy, "      Off := Off + N;");
                           Append (Bdy, LF);
                        when Repeat =>
                           Emit_Repeat (A, "      ", "return 0");
                     end case;
                  end loop;
                  Append (Bdy, "      return Off;");
                  Append (Bdy, LF);
               else
                  --  Alternation: try each branch, keep the longest match.
                  Append (Bdy, "      Cp   : Natural;");
                  Append (Bdy, LF);
                  Append (Bdy, "      N    : Natural;");
                  Append (Bdy, LF);
                  Append (Bdy, "      Best : Natural := 0;");
                  Append (Bdy, LF);
                  Append (Bdy, "      Off  : Natural;");
                  Append (Bdy, LF);
                  Append (Bdy, "      Ok   : Boolean;");
                  Append (Bdy, LF);
                  Append (Bdy, "   begin");
                  Append (Bdy, LF);
                  for B of DNF loop
                     Append (Bdy, "      Off := 0;");
                     Append (Bdy, LF);
                     Append (Bdy, "      Ok := True;");
                     Append (Bdy, LF);
                     for A of B loop
                        case A.Kind is
                           when Single =>
                              Append (Bdy, "      if Ok then");
                              Append (Bdy, LF);
                              Append (Bdy, "         N := Decode_Utf8 (S, Pos + Off, Len, Cp);");
                              Append (Bdy, LF);
                              Append (Bdy, "         Ok := N > 0 and then "
                                & Range_Cond (A.Lo, A.Hi) & ";");
                              Append (Bdy, LF);
                              Append (Bdy, "         if Ok then Off := Off + N; end if;");
                              Append (Bdy, LF);
                              Append (Bdy, "      end if;");
                              Append (Bdy, LF);
                           when Repeat =>
                              Append (Bdy, "      if Ok then");
                              Append (Bdy, LF);
                              Emit_Repeat (A, "         ", "Ok := False");
                              Append (Bdy, "      end if;");
                              Append (Bdy, LF);
                        end case;
                     end loop;
                     Append (Bdy, "      if Ok and then Off > Best then Best := Off; end if;");
                     Append (Bdy, LF);
                  end loop;
                  Append (Bdy, "      return Best;");
                  Append (Bdy, LF);
               end if;
               Append (Bdy, "   end Scan_" & Ada_Ident (NM) & ";");
               Append (Bdy, LF);
               Append (Bdy, LF);
            end;
         end if;
      end loop;


      --  The parser primitives (position, errors, literals, whitespace).
      declare
         Nocase_Proc : U;
         Skip_Body   : U;
         Kw_Fn       : U;
         V : Mustache.Context := Mustache.View;
      begin
         if Has_No_Case (Rules) then
            Append (Nocase_Proc,
              "   procedure Expect_Word_Nocase (P : in out Parser; Lit : String) is" & LF
              & "      N : constant Natural := Scan_Word (P.Text.all, P.Pos, P.Text'Last);" & LF
              & "   begin" & LF
              & "      if N = Lit'Length" & LF
              & "        and then Ada.Strings.Equal_Case_Insensitive" & LF
              & "                   (P.Text (P.Pos .. P.Pos + N - 1), Lit)" & LF
              & "      then" & LF
              & "         P.Pos := P.Pos + N;" & LF
              & "      else" & LF
              & "         Fail (P, ""`"" & Lit & ""`"");" & LF
              & "      end if;" & LF
              & "   end Expect_Word_Nocase;" & LF & LF);
         end if;
         if Ws_Name = "" then
            Append (Skip_Body, "   begin" & LF & "      null;" & LF
              & "   end Skip_Ws;");
         else
            Append (Skip_Body, "      N : Natural;" & LF & "   begin" & LF
              & "      loop" & LF
              & "         N := Scan_" & Ada_Ident (Ws_Name)
              & " (P.Text.all, P.Pos, P.Text'Last);" & LF
              & "         exit when N = 0;" & LF
              & "         P.Pos := P.Pos + N;" & LF
              & "      end loop;" & LF
              & "   end Skip_Ws;");
         end if;
         Append (Kw_Fn, "   function Is_Keyword (S : String) return Boolean is" & LF
           & "   begin" & LF);
         if Keywords.Is_Empty then
            Append (Kw_Fn, "      pragma Unreferenced (S);" & LF
              & "      return False;" & LF);
         else
            Append (Kw_Fn, "      return");
            for K in 1 .. Natural (Keywords.Length) loop
               Append (Kw_Fn, (if K = 1 then " " else LF & "        or else ")
                 & "S = """ & Ada_Escape (To_String (Keywords (K))) & """");
            end loop;
            Append (Kw_Fn, ";" & LF);
         end if;
         Append (Kw_Fn, "   end Is_Keyword;" & LF);
         Mustache.Put (V, "nocase_proc", To_String (Nocase_Proc));
         Mustache.Put (V, "skip_ws", To_String (Skip_Body));
         Mustache.Put (V, "keyword_fn", To_String (Kw_Fn));
         Append (Bdy, Mustache.Render_File ("ada_parser_prims", V));
      end;
      Append (Bdy, LF);
      Append (Bdy, To_String (Free_Body));

      --  Forward declarations: a rule may call any other, in any order.
      --  A core-type char rule (str/int/word) is read as a scalar in place,
      --  and a building block is inlined into a scanner; neither needs a
      --  Parse function of its own.
      for I in 1 .. N loop
         declare
            NM : constant String := To_String (Rules (I).Name);
         begin
            if not (Is_Char_Rule (Rules, NM)
                    and then (Is_Core_Name (NM)
                              or else not Is_Char_Token (Rules, NM)))
            then
               Append (Bdy, "   function Parse_" & Ada_Ident (NM)
                 & " (P : in out Parser) return " & Ret_Type (I) & ";");
               Append (Bdy, LF);
            end if;
         end;
      end loop;
      Append (Bdy, LF);

      for I in 1 .. N loop
         declare
            NM : constant String := To_String (Rules (I).Name);
         begin
            if not (Is_Char_Rule (Rules, NM)
                    and then (Is_Core_Name (NM)
                              or else not Is_Char_Token (Rules, NM)))
            then
               Append (Bdy, "   function Parse_" & Ada_Ident (NM)
                 & " (P : in out Parser) return " & Ret_Type (I) & " is");
               Append (Bdy, LF);
               Emit_Rule_Decl (I, Bdy);
               Append (Bdy, "   begin");
               Append (Bdy, LF);
               Emit_Rule_Parser (I, Bdy);
               Append (Bdy, "   end Parse_" & Ada_Ident (NM) & ";");
               Append (Bdy, LF);
               Append (Bdy, LF);
            end if;
         end;
      end loop;

      --  Parse_Text: the whole text through the root rule.
      declare
         V : Mustache.Context := Mustache.View;
      begin
         Mustache.Put (V, "root_type", Ret_Type (1));
         Mustache.Put (V, "root_fn",
           "Parse_" & Ada_Ident (To_String (Rules (1).Name)));
         Append (Bdy, Mustache.Render_File ("ada_parse_text", V));
      end;
      Append (Bdy, LF);
      Append (Bdy, LF);
      if Conf then
         declare
            V : Mustache.Context := Mustache.View;
         begin
            Mustache.Put (V, "root_type", Ret_Type (1));
            Append (Bdy, Mustache.Render_File ("conf_ada", V));
         end;
         Append (Bdy, LF);
      end if;
      if Epilogue ("Ada") /= "" then
         Append (Bdy, Epilogue ("Ada"));
         Append (Bdy, LF);
      end if;
      Append (Bdy, "end " & Package_Name & ".Parser;");
      Append (Bdy, LF);

      return To_String (Spec) & LF & To_String (Bdy);
   end Emit_Parser;

end HBNF_Ada;
