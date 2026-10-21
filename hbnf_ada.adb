pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Mustache;
with HBNF_C;
with HBNF_Compilable;
with HBNF_Lookahead;

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
      for C of HBNF_Grammar.Prefixed (S) loop
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

   Writer_On    : Boolean := False;   --  --writer: Write_<root>
   Ast_On       : Boolean := False;   --  --ast: the walker and the dump
   Spans_On     : Boolean := False;   --  --spans: where each node is in the text
   Parents_On   : Boolean := False;   --  --parents: which node holds each node
   Hosted_Types : U;
   Hosted_Spec  : U;
   Hosted_Withs : U;
   Hosted_Code  : U;
   Hosted_Walks : U;                --  " rule=Walk_Proc", for each bit rule that has one
   Hosted_Acts  : Boolean := False; --  some %action to run after the text is read
   Is_Hosted    : Boolean := False;

   procedure Set_Writer (On : Boolean) is
   begin
      Writer_On := On;
   end Set_Writer;

   procedure Set_Ast (On : Boolean) is
   begin
      Ast_On := On;
   end Set_Ast;

   procedure Set_Spans (On : Boolean) is
   begin
      Spans_On := On;
   end Set_Spans;

   procedure Set_Parents (On : Boolean) is
   begin
      Parents_On := On;
   end Set_Parents;

   procedure Set_Hosted (Types, Spec, Withs, Code : String; Walks : String := "") is
   begin
      Hosted_Walks := To_Unbounded_String (" " & Walks & " ");
      Hosted_Acts  := Walks /= "";
      Hosted_Types := To_Unbounded_String (Types);
      Hosted_Spec  := To_Unbounded_String (Spec);
      Hosted_Withs := To_Unbounded_String (Withs);
      Hosted_Code  := To_Unbounded_String (Code);
      Is_Hosted := True;
   end Set_Hosted;

   function Ident (Rule : String) return String is (Ada_Ident (Rule));
   function Type_Name (Rule : String) return String is
     (Ada_Ident (Rule) & "_Type");
   function Parse_Fn (Rule : String) return String is
     ("Parse_" & Ada_Ident (Rule));
   function Scan_Fn (Rule : String) return String is
     ("Scan_" & Ada_Ident (Rule));

   --  The Ada type a rule reference denotes: a core scalar inlines; any
   --  other reference resolves to the referenced rule's own type name.
   function Ada_Type_Of (Rules : Rule_Vectors.Vector; Ref : String)
     return String is
      S : constant String := Scalar_Ada_Type (Ref);
   begin
      if S /= "" then
         return S;
      end if;
      if Find (Rules, Ref) = 0 and then not HBNF_Grammar.Is_Wire_Rule (Ref) then
         raise Parse_Error with "undefined rule: " & HBNF_Grammar.Spelled (Ref)
           & (if HBNF_Grammar.Spelled (Ref) /= Ref then ", which no `::=` defines" else "");
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
            when Bit_Field =>
               null;     --  a rule with bit fields never reaches here (Split_Wire)
            when Negation =>
               null;   --  resolved into a rule of ranges before this runs
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


   --  The Rust/Zig/Ada type a value of rule N is written as: a core scalar, a token, a
   --  rule that is one name (chased), or a choice of names that all come to the same type;
   --  "" if it is none of these.
   function Value_Type
     (Rules : Rule_Vectors.Vector; N : String; Depth : Natural := 0) return String
   is
      C : constant String := Scalar_Ada_Type (N);
   begin
      if C /= "" then
         return C;
      elsif Is_Char_Rule (Rules, N) then
         return "Unbounded_String";
      elsif Depth > 8 then
         return "";
      end if;
      declare
         J : constant Natural := Find (Rules, N);
      begin
         if J = 0 then
            return "";
         elsif Rules (J).Jet_Code /= Null_Unbounded_String then
            return "Unbounded_String";
         elsif Natural (Rules (J).Pattern.Length) = 1
           and then Rules (J).Pattern (1).Kind = Name
           and then Rules (J).Pattern (1).Min = 1
           and then Rules (J).Pattern (1).Max = 1
         then
            return Value_Type (Rules, To_String (Rules (J).Pattern (1).Name), Depth + 1);
         end if;
         return Scalar_Union_Type (Rules, Rules (J).Pattern);
      end;
   end Value_Type;

   --  With --writer, a rule with alternatives records the one it took
   --  (`Alt_No`, from 1): a record whose pattern has a top-level alternation,
   --  and a list entry that is a group with one.  The writer needs it; the C
   --  tree has the same.
   --  With --spans a record and a list entry say where they are in the text
   --  (`Span_Start`, `Span_End`: byte offsets from 0; the blanks before a node
   --  are not in it).
   function Has_Span (Info : Rule_Info) return Boolean is
     (Spans_On and then (Info.Kind = Struct
                         or else (Info.Kind = List and then not Info.Elem_Members.Is_Empty)));

   --  How many alternatives a flat list of elements with Alt separators has.
   function Alt_Labels_Count (Els : Element_Vectors.Vector) return Natural is
      N : Natural := 1;
   begin
      for X of Els loop
         if X.Kind = Alt then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Alt_Labels_Count;

   function Struct_Alt (R : Rule; Info : Rule_Info) return Boolean is
     ((Writer_On or else Ast_On) and then Info.Kind = Struct
      and then Natural (R.Pattern.Length) > 1
      and then (for some X of R.Pattern => X.Kind = Alt));

   function Entry_Alt (R : Rule; Info : Rule_Info) return Boolean is
     ((Writer_On or else Ast_On) and then Info.Kind = List
      and then not Info.Elem_Members.Is_Empty
      and then Natural (R.Pattern.Length) = 1
      and then R.Pattern (1).Kind = Group
      and then (for some X of R.Pattern (1).Items => X.Kind = Alt));

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

   --  The record a name stands for when it is an alias of a record, not a
   --  record itself (`x = item`); 0 otherwise.  Held in a vector or in a list
   --  entry, which are declared before any record body, it is the record's
   --  access type, as a record member is.
   function Alias_Record (Rules : Rule_Vectors.Vector; Ref : String)
     return Natural is
      J : constant Natural := Find (Rules, Ref);
   begin
      if J = 0 or else Scalar_Ada_Type (Ref) /= ""
        or else Analyze (Rules, J).Kind /= Scalar
        or else not Over_Leaf (Rules, J)
      then
         return 0;
      end if;
      declare
         L : constant Natural := Leaf_Record (Rules, Ref);
      begin
         return (if L /= 0 and then Is_Record (Analyze (Rules, L)) then L else 0);
      end;
   end Alias_Record;

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
      function Elem_Type (Owner : Natural; Ref : String; Held : Boolean := False)
        return String is
         S : constant String := Scalar_Ada_Type (Ref);
         J : constant Natural := Find (Rules, Ref);
      begin
         if S /= "" then
            return S;                           -- a core scalar
         elsif J > 0 and then Is_Record (Infos (J)) then
            return Ada_Ident (Ref) & "_Access"; -- a record: access breaks it
         elsif Held and then Alias_Record (Rules, Ref) /= 0 then
            --  An alias of a record (`x = item`) in a list entry is held as
            --  the record is held: through its access type, which is declared
            --  before any body, where the alias's subtype is not yet.
            return Ada_Ident
              (To_String (Rules (Leaf_Record (Rules, Ref)).Name)) & "_Access";
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
                  --  The values follow the numbers the author gave the
                  --  alternatives, or their order as written, not the order
                  --  the parser tries them in (see Enum_Value).
                  Count : constant Natural := Natural (Info.Literals.Length);
                  Vals  : constant Value_Array (1 .. Count) :=
                    [for K in 1 .. Count =>
                       Enum_Value (To_String (R.Name),
                                   To_String (Info.Literals (K)))];
                  Ord   : constant Order_Array := Enum_Order (Vals);
               begin
                  for J in 1 .. Count loop
                     declare
                        I : constant Positive := Ord (J);
                     begin
                     Row := Mustache.New_Map;
                     Mustache.Insert
                       (Row, "ident",
                        Mustache.New_Scalar
                          (Base & "_" & To_String (Names (I))));
                     Mustache.Insert
                       (Row, "value",
                        Mustache.New_Scalar
                          (Ada.Strings.Fixed.Trim
                             (Integer'Image (Vals (I)), Ada.Strings.Left)));
                     --  Mustache has no join, so the separator is a flag on
                     --  every row but the first: `{{#sep}}, {{/sep}}`.
                     if J > 1 then
                        Mustache.Insert (Row, "sep", Mustache.New_Scalar ("1"));
                     end if;
                     Mustache.Append (Items, Row);
                     end;
                  end loop;
                  Mustache.Put (V, "name", TN);
                  Mustache.Put (V, "items", Items);
                  if Enum_Sparse (Vals, Ord) then
                     Mustache.Put (V, "rep", Mustache.New_Scalar ("1"));
                  end if;
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
                  if Struct_Alt (R, Info) then
                     Row := Mustache.New_Map;
                     Mustache.Insert (Row, "field", Mustache.New_Scalar ("Alt_No"));
                     Mustache.Insert (Row, "type", Mustache.New_Scalar ("Natural"));
                     Mustache.Append (Items, Row);
                  end if;
                  if Has_Span (Info) then
                     for F in 1 .. 2 loop
                        Row := Mustache.New_Map;
                        Mustache.Insert (Row, "field", Mustache.New_Scalar (if F = 1 then "Span_Start" else "Span_End"));
                        Mustache.Insert (Row, "type", Mustache.New_Scalar ("Natural"));
                        Mustache.Append (Items, Row);
                     end loop;
                  end if;
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
                 (Base & "_Vectors", Elem_Type (Idx, To_String (Info.Elem_Name), True),
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
                     Mustache.New_Scalar (Elem_Type (Idx, To_String (M.Name), True)));
                  Mustache.Append (Items, Row);
               end loop;
               if Entry_Alt (R, Info) then
                  Row := Mustache.New_Map;
                  Mustache.Insert (Row, "field", Mustache.New_Scalar ("Alt_No"));
                  Mustache.Insert (Row, "type", Mustache.New_Scalar ("Natural"));
                  Mustache.Append (Items, Row);
               end if;
               if Has_Span (Info) then
                  for F in 1 .. 2 loop
                     Row := Mustache.New_Map;
                     Mustache.Insert (Row, "field", Mustache.New_Scalar (if F = 1 then "Span_Start" else "Span_End"));
                     Mustache.Insert (Row, "type", Mustache.New_Scalar ("Natural"));
                     Mustache.Append (Items, Row);
                  end loop;
               end if;
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

      --  The bit rules' types: they hold the scalars above, and the records
      --  below hold them.
      Append (Res, Hosted_Types);

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
                                 Elem_Type (I, To_String (M.Name), True),
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

      --  Can a rule match the empty text?  Then a scan of length 0 is a match,
      --  not a failure (a lifted `[ x ]` of a token is such a rule).
      Nullable : constant HBNF_Lookahead.Flags :=
        HBNF_Lookahead.Nullable_Set (Rules);

      function Can_Be_Empty (Nm : String) return Boolean is
        (Find (Rules, Nm) > 0 and then Nullable (Find (Rules, Nm)));

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
        (HBNF_Grammar.Keywords_Apply
         and then S'Length > 0
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
         --  Whether this rule's file skips whitespace between elements
         --  (`whitespace none` says it does not).
         Skips : constant Boolean :=
           Rules (Owner).Whitespace /= Null_Unbounded_String;
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
                        if Skips then
                           Append (Buf, Ind & "Skip_Ws (P);");
                           Append (Buf, LF);
                        end if;
                        Append (Buf, Ind
                          & (if E.No_Case and then Is_Keyword_Lit (Lit)
                             then "Expect_Word_Nocase"
                             elsif E.No_Case then "Expect_Lit_Nocase"
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
                           if Skips then
                              Append (Buf, Ind & "Skip_Ws (P);");
                              Append (Buf, LF);
                           end if;
                           Append (Buf, Ind & "declare");
                           Append (Buf, LF);
                           Append (Buf, Ind & "   N : constant Natural := "
                             & Scan_Fn (NM)
                             & " (P.Text.all, P.Pos, Limit (P));");
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
                           if Skips then
                              Append (Buf, Ind & "Skip_Ws (P);");
                              Append (Buf, LF);
                           end if;
                           Append (Buf, Ind & "declare");
                           Append (Buf, LF);
                           Append (Buf, Ind & "   N : constant Natural := Scan_"
                             & Ada_Ident (NM)
                             & " (P.Text.all, P.Pos, Limit (P));");
                           Append (Buf, LF);
                           Append (Buf, Ind & "begin");
                           Append (Buf, LF);
                           if not Can_Be_Empty (NM) then
                              Append (Buf, Ind & "   if N = 0 then Fail (P, """
                                & NM & """); end if;");
                              Append (Buf, LF);
                           end if;
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
                           --  An alias of a record held in a list entry is
                           --  allocated as that record; in a record's own field
                           --  it stays a value of the alias's subtype.
                           AR : constant Natural :=
                             (if Alloc_Records and then Owner > 0
                                and then Analyze (Rules, Owner).Kind = List
                              then Alias_Record (Rules, NM)
                              else 0);
                           --  A back-edge member names an alias over a record,
                           --  so it is allocated as that record; a struct
                           --  member is allocated as itself.
                           TN : constant String :=
                             (if Back or else AR /= 0
                              then Ada_Ident
                                (To_String
                                   (Rules (Leaf_Record (Rules, NM)).Name))
                                & "_Type"
                              else Ada_Ident (NM) & "_Type");
                        begin
                           if Skips then
                              Append (Buf, Ind & "Skip_Ws (P);");
                              Append (Buf, LF);
                           end if;
                           if Alloc_Records
                             and then (Is_Struct (NM) or else Back or else AR /= 0)
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
                  when Bit_Field =>
                     null;     --  a rule with bit fields never reaches here (Split_Wire)
                  when Negation =>
                     null;   --  resolved into a rule of ranges before this runs
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
               --  First match wins: this branch is taken only if the next
               --  code point can follow the choice.
               if K <= N and then Els (K).Kind = Alt and then Els (K).Guard /= 0
               then
                  declare
                     G : constant String := Natural'Image (Els (K).Guard);
                  begin
                     Append (Buf, Ind & "   declare");
                     Append (Buf, LF);
                     Append (Buf, Ind & "      Sv : constant Natural := P.Pos;");
                     Append (Buf, LF);
                     Append (Buf, Ind & "      Ok : Boolean;");
                     Append (Buf, LF);
                     Append (Buf, Ind & "   begin");
                     Append (Buf, LF);
                     if Rules (Owner).Whitespace /= Null_Unbounded_String then
                        Append (Buf, Ind & "      Skip_Ws (P);");
                        Append (Buf, LF);
                     end if;
                     Append (Buf, Ind & "      Ok := Guard_" & G (G'First + 1 .. G'Last)
                       & " (P.Text.all, P.Pos);");
                     Append (Buf, LF);
                     Append (Buf, Ind & "      P.Pos := Sv;");
                     Append (Buf, LF);
                     Append (Buf, Ind & "      if not Ok then Fail (P, ""what can "
                       & "follow here""); end if;");
                     Append (Buf, LF);
                     Append (Buf, Ind & "   end;");
                     Append (Buf, LF);
                  end;
               end if;
               if Struct_Alt (Rules (Owner), Analyze (Rules, Owner)) then
                  Append (Buf, Ind & "   R.Alt_No := " & Img (Br) & ";");
                  Append (Buf, LF);
               end if;
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
              & " (P.Text.all, P.Pos, Limit (P));");
            Append (Buf, LF);
            Append (Buf, "      begin");
            Append (Buf, LF);
            if R.Jet_Code /= Null_Unbounded_String
              or else not Can_Be_Empty (NM)
            then
               Append (Buf, "         if N = 0 then Fail (P, """ & Desc & """); end if;");
               Append (Buf, LF);
            end if;
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
               return "Scan_Word (P.Text.all, P.Pos, Limit (P)) = " & NL
                 & " and then " & Eq;
            end if;
            return "P.Pos + " & NL & " - 1 <= Limit (P) and then " & Eq;
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
                  if R.Whitespace /= Null_Unbounded_String then
                     Append (Buf, "            Skip_Ws (P);");
                     Append (Buf, LF);
                  end if;
                  if not Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "            if P.Pos > Limit (P) then P.Pos := Start; exit; end if;");
                     Append (Buf, LF);
                  end if;
                  if Is_Core (To_String (Simple)) then
                     --  A list of a core type (`*word`): read the text in
                     --  place; there is no Parse_ function for a core type.
                     Append (Buf, "            declare");
                     Append (Buf, LF);
                     Append (Buf, "               N : constant Natural := "
                       & Scan_Fn (To_String (Simple))
                       & " (P.Text.all, P.Pos, Limit (P));");
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
                  elsif Alias_Record (Rules, To_String (Simple)) /= 0 then
                     Append (Buf, "            R.Append (new "
                       & Ada_Ident
                           (To_String
                              (Rules (Leaf_Record (Rules, To_String (Simple))).Name))
                       & "_Type'(Parse_"
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
                              if Entry_Alt (R, Analyze (Rules, Idx)) then
                                 Append (Buf, "                  El.Alt_No := " & Img (Br) & ";");
                                 Append (Buf, LF);
                              end if;
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
                  if Has_Span (Analyze (Rules, Idx)) then
                     if R.Whitespace /= Null_Unbounded_String then
                        Append (Buf, "            declare K : constant Natural := P.Pos; begin"
                          & " P.Pos := Save; Skip_Ws (P); E.Span_Start := P.Pos - 1; P.Pos := K; end;");
                     else
                        Append (Buf, "            E.Span_Start := Save - 1;");
                     end if;
                     Append (Buf, LF);
                     Append (Buf, "            E.Span_End := P.Pos - 1;");
                     Append (Buf, LF);
                  end if;
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
            Append (Buf, "      if P.Pos > Limit (P) then Fail (P, ""a " & TN & """); end if;");
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
                    & " (P.Text.all, P.Pos, Limit (P));");
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
            elsif HBNF_Grammar.Except_Operand (NM) /= "" then
               --  `X = A - B` with a phrase on a side: parse A; then try B on
               --  exactly the text A matched (the input ends where A did, and
               --  B must end there too).  If it does, X does not match.
               declare
                  A : constant String := To_String (P (1).Name);
                  B : constant String := HBNF_Grammar.Except_Operand (NM);

                  function Chase (Nm : String) return String is
                     N : Unbounded_String := To_Unbounded_String (Nm);
                  begin
                     for Hops in 1 .. 20 loop
                        declare
                           J : constant Natural := Find (Rules, To_String (N));
                        begin
                           exit when J = 0
                             or else Natural (Rules (J).Pattern.Length) /= 1
                             or else Rules (J).Pattern (1).Kind /= Name
                             or else Rules (J).Pattern (1).Min /= 1
                             or else Rules (J).Pattern (1).Max /= 1
                             or else Is_Core (To_String (Rules (J).Pattern (1).Name));
                           N := Rules (J).Pattern (1).Name;
                        end;
                     end loop;
                     return To_String (N);
                  end Chase;

                  function Owns (Nm : String) return Boolean is
                     J : constant Natural := Find (Rules, Chase (Nm));
                  begin
                     return J /= 0
                       and then Analyze (Rules, J).Kind in Struct | List;
                  end Owns;
               begin
                  Append (Buf, "      declare" & LF);
                  Append (Buf, "         Save : constant Natural := P.Pos;" & LF);
                  Append (Buf, "         R    : " & Ada_Ident (NM) & "_Type := Parse_"
                    & Ada_Ident (A) & " (P);" & LF);
                  Append (Buf, "         Stop : constant Natural := P.Pos;" & LF);
                  Append (Buf, "         Keep : constant Natural := P.Last;" & LF);
                  Append (Buf, "         Same : Boolean := False;" & LF);
                  Append (Buf, "         Tmp  : " & Ada_Ident (B) & "_Type;" & LF);
                  Append (Buf, "      begin" & LF);
                  Append (Buf, "         P.Pos := Save;" & LF);
                  Append (Buf, "         P.Last := Stop;" & LF);
                  Append (Buf, "         begin" & LF);
                  Append (Buf, "            Tmp := Parse_" & Ada_Ident (B) & " (P);" & LF);
                  Append (Buf, "            Same := P.Pos = Stop;" & LF);
                  if Owns (B) then
                     Append (Buf, "            Free_" & Ada_Ident (Chase (B))
                       & " (Tmp);" & LF);
                  end if;
                  Append (Buf, "         exception" & LF);
                  Append (Buf, "            when Parse_Error => null;" & LF);
                  Append (Buf, "         end;" & LF);
                  Append (Buf, "         P.Last := Keep;" & LF);
                  Append (Buf, "         P.Pos := Stop;" & LF);
                  Append (Buf, "         if Same then" & LF);
                  if Owns (A) then
                     Append (Buf, "            Free_" & Ada_Ident (Chase (A))
                       & " (R);" & LF);
                  end if;
                  Append (Buf, "            P.Pos := Save;" & LF);
                  Append (Buf, "            Fail (P, ""`" & A & "` that is not `" & B
                    & """);" & LF);
                  Append (Buf, "         end if;" & LF);
                  Append (Buf, "         return R;" & LF);
                  Append (Buf, "      end;" & LF);
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
                                   & " (P.Text.all, P.Pos, Limit (P));");
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
      Ast_Body   : U;     --  the walker and the dump (--ast)
      Act_Decls  : U;     --  the %actions of the bit rules, run after the read
      Act_Body   : U;

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
           (Idx : Natural; M : Member; Prefix : String; Buf : in out U;
            Held : Boolean := False) is
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
               elsif Held and then Alias_Record (Rules, NM) /= 0 then
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
               elsif Alias_Record (Rules, NM) /= 0 then
                  Free_Vector
                    (Buf, Prefix & F,
                     Ada_Ident
                       (To_String (Rules (Leaf_Record (Rules, NM)).Name)));
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
                           elsif Alias_Record
                                   (Rules, To_String (Info.Elem_Name)) /= 0
                           then
                              Free_Vector
                                (Stmts, "V",
                                 Ada_Ident
                                   (To_String
                                      (Rules (Leaf_Record
                                        (Rules, To_String (Info.Elem_Name))).Name)));
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
                                 "E.", Inner, Held => True);
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

      --  The %actions of the bit rules a text rule holds, run after the whole
      --  text has been read: Act_<rule> walks a record, children first, and
      --  calls the Walk_<bit rule> of each bit rule it holds.
      if Is_Hosted and then Hosted_Acts then
         declare
            --  The walk procedure of a bit rule, "" if it has none.
            function Walk_Of (Name : String) return String is
               Key : constant String := " " & Name & "=";
               Found : constant Natural := Index (Hosted_Walks, Key);
            begin
               if Find (Rules, Name) /= 0 or else Found = 0 then
                  return "";
               end if;
               declare
                  S : constant String := To_String (Hosted_Walks);
                  E : Natural := Found + Key'Length;
               begin
                  while E <= S'Last and then S (E) /= ' ' loop
                     E := E + 1;
                  end loop;
                  return S (Found + Key'Length .. E - 1);
               end;
            end Walk_Of;

            procedure Act_Vector (Buf : in out U; Vec, Elem : String) is
            begin
               Append (Buf, "   for E of " & Vec & " loop" & LF);
               Append (Buf, "      if E /= null then Act_" & Elem & " (E.all, H); end if;" & LF);
               Append (Buf, "   end loop;" & LF);
            end Act_Vector;

            procedure Act_List_Vector (Buf : in out U; Vec, Elem : String) is
            begin
               Append (Buf, "   for E of " & Vec & " loop" & LF);
               Append (Buf, "      Act_" & Elem & " (E, H);" & LF);
               Append (Buf, "   end loop;" & LF);
            end Act_List_Vector;

            procedure Act_Member
              (Idx : Natural; M : Member; Prefix : String; Buf : in out U;
               Held : Boolean := False)
            is
               NM  : constant String := To_String (M.Name);
               F   : constant String := Ada_Field (NM);
               J   : constant Natural := Find (Rules, NM);
               W   : constant String := Walk_Of (NM);
               Rec : constant Natural :=
                 (if J > 0 and then Is_Record (Analyze (Rules, J)) then
                     J
                  elsif Is_Back (Backs, Idx, NM) then
                     Leaf_Record (Rules, NM)
                  elsif Held and then Alias_Record (Rules, NM) /= 0 then
                     Leaf_Record (Rules, NM)
                  else
                     0);
            begin
               if W /= "" then
                  if M.Is_List then
                     Append (Buf, "   for E of " & Prefix & F & " loop" & LF);
                     Append (Buf, "      " & W & " (E, H);" & LF);
                     Append (Buf, "   end loop;" & LF);
                  else
                     Append (Buf, "   " & W & " (" & Prefix & F & ", H);" & LF);
                  end if;
               elsif M.Is_List then
                  if J > 0 and then Is_Record (Analyze (Rules, J)) then
                     Act_Vector (Buf, Prefix & F, Ada_Ident (NM));
                  elsif Alias_Record (Rules, NM) /= 0 then
                     Act_Vector
                       (Buf, Prefix & F,
                        Ada_Ident
                          (To_String (Rules (Leaf_Record (Rules, NM)).Name)));
                  elsif J > 0 and then Over_Leaf (Rules, J)
                    and then Analyze (Rules, Leaf_Target (Rules, J)).Kind = List
                  then
                     Act_List_Vector
                       (Buf, Prefix & F,
                        Ada_Ident (To_String (Rules (Leaf_Target (Rules, J)).Name)));
                  end if;
               elsif Rec > 0 then
                  Append (Buf, "   if " & Prefix & F & " /= null then" & LF);
                  Append (Buf, "      Act_" & Ada_Ident (To_String (Rules (Rec).Name))
                          & " (" & Prefix & F & ".all, H);" & LF);
                  Append (Buf, "   end if;" & LF);
               elsif J > 0 and then Analyze (Rules, J).Kind = List then
                  Append (Buf, "   Act_" & Ada_Ident (NM) & " (" & Prefix & F
                          & ", H);" & LF);
               elsif J > 0 and then Analyze (Rules, J).Kind = Scalar
                 and then Over_Leaf (Rules, J)
               then
                  Append (Buf, "   Act_"
                          & Ada_Ident
                              (To_String (Rules (Leaf_Record (Rules, NM)).Name))
                          & " (" & Prefix & F & ", H);" & LF);
               end if;
            end Act_Member;
         begin
            for I in 1 .. N loop
               declare
                  Info : constant Rule_Info := Analyze (Rules, I);
                  CN   : constant String := Ada_Ident (To_String (Rules (I).Name));
                  Stmts : U;
               begin
                  if Is_Record (Info) or else Info.Kind = List then
                     if Is_Record (Info) then
                        for M of Info.Members loop
                           Act_Member (I, M, "V.", Stmts);
                        end loop;
                     elsif Info.Elem_Members.Is_Empty
                       and then Info.Elem_Name /= Null_Unbounded_String
                     then
                        declare
                           EN : constant String := To_String (Info.Elem_Name);
                           E  : constant Natural := Find (Rules, EN);
                           W  : constant String := Walk_Of (EN);
                        begin
                           if W /= "" then
                              Append (Stmts, "   for E of V loop" & LF
                                      & "      " & W & " (E, H);" & LF
                                      & "   end loop;" & LF);
                           elsif E > 0 and then Is_Record (Analyze (Rules, E)) then
                              Act_Vector (Stmts, "V", Ada_Ident (EN));
                           elsif Alias_Record (Rules, EN) /= 0 then
                              Act_Vector
                                (Stmts, "V",
                                 Ada_Ident
                                   (To_String (Rules (Leaf_Record (Rules, EN)).Name)));
                           elsif E > 0 and then Over_Leaf (Rules, E)
                             and then Analyze (Rules, Leaf_Target (Rules, E)).Kind = List
                           then
                              Act_List_Vector
                                (Stmts, "V",
                                 Ada_Ident
                                   (To_String (Rules (Leaf_Target (Rules, E)).Name)));
                           end if;
                        end;
                     elsif not Info.Elem_Members.Is_Empty then
                        declare
                           Inner : U;
                        begin
                           for M of Info.Elem_Members loop
                              Act_Member
                                (I, (Name => M.Name, Is_List => False),
                                 "E.", Inner, Held => True);
                           end loop;
                           if To_String (Inner) /= "" then
                              Append (Stmts, "   for E of V loop" & LF
                                      & To_String (Inner) & "   end loop;" & LF);
                           end if;
                        end;
                     end if;
                     Append (Act_Decls, "   procedure Act_" & CN & " (V : " & CN
                             & "_Type; H : in out Hooks);" & LF);
                     Append (Act_Body, "   procedure Act_" & CN & " (V : " & CN
                             & "_Type; H : in out Hooks) is" & LF);
                     if To_String (Stmts) = "" then
                        Append (Act_Body, "      pragma Unreferenced (V, H);" & LF
                                & "   begin" & LF & "      null;" & LF);
                     else
                        Append (Act_Body, "   begin" & LF & To_String (Stmts));
                     end if;
                     Append (Act_Body, "   end Act_" & CN & ";" & LF & LF);
                  end if;
               end;
            end loop;
         end;
      end if;

      --  The tree as nodes (--ast): `Node` is any record or list element of the
      --  tree, `Node_Walk` visits them (enter, leave, skip, stop), `Node_Kids`
      --  lists a node's members, and `Node_Dump` writes the S-expression C's
      --  node_dump writes, so a tree dumps the same in every language.  Plain
      --  Ada over the types above; the walker knows nothing of the grammar.
      if Ast_On and then (Is_Record (Analyze (Rules, 1))
                          or else Analyze (Rules, 1).Kind = List
                          or else Over_Leaf (Rules, 1))
      then
         declare
            WB : U renames Ast_Body;
            SP : U renames Free_Decls;

            procedure P (Ind : Natural; S : String) is
            begin
               Append (WB, [1 .. 3 * Ind => ' ']);
               Append (WB, S);
               Append (WB, LF);
            end P;

            procedure PS (Ind : Natural; S : String) is
            begin
               Append (SP, [1 .. 3 * Ind => ' ']);
               Append (SP, S);
               Append (SP, LF);
            end PS;

            function Q (S : String) return String is ("""" & Ada_Escape (S) & """");

            function Walked_Kind (I : Natural) return Boolean is
              (Is_Record (Analyze (Rules, I)) or else Analyze (Rules, I).Kind = List);

            function V (I : Natural) return String is
              (Ada_Ident (To_String (Rules (I).Name)));

            --  The type a node of rule I points at.
            function Elem_Type (I : Natural) return String is
               Info : constant Rule_Info := Analyze (Rules, I);
            begin
               if Is_Record (Info) then
                  return V (I) & "_Type";
               elsif not Info.Elem_Members.Is_Empty then
                  return V (I) & "_Entry";
               elsif Info.Elem_Name /= Null_Unbounded_String then
                  declare
                     EN : constant String := To_String (Info.Elem_Name);
                     E  : constant Natural := Find (Rules, EN);
                  begin
                     if E > 0 and then Is_Record (Analyze (Rules, E)) then
                        return Ada_Ident (EN) & "_Type";
                     elsif Alias_Record (Rules, EN) /= 0 then
                        return Ada_Ident
                          (To_String (Rules (Leaf_Record (Rules, EN)).Name)) & "_Type";
                     end if;
                     return Ada_Type_Of (Rules, EN);
                  end;
               end if;
               return "Unbounded_String";
            end Elem_Type;

            --  Whether the elements of list rule I sit in the vector through
            --  an access (a record) rather than by value.
            function Elem_Is_Access (I : Natural) return Boolean is
               Info : constant Rule_Info := Analyze (Rules, I);
            begin
               if Info.Kind /= List or else not Info.Elem_Members.Is_Empty
                 or else Info.Elem_Name = Null_Unbounded_String
               then
                  return False;
               end if;
               declare
                  EN : constant String := To_String (Info.Elem_Name);
                  E  : constant Natural := Find (Rules, EN);
               begin
                  return (E > 0 and then Is_Record (Analyze (Rules, E)))
                    or else Alias_Record (Rules, EN) /= 0;
               end;
            end Elem_Is_Access;

            --  The rule the root is walked as: itself, or what it is an alias of.
            Rt : constant Natural :=
              (if Is_Record (Analyze (Rules, 1)) or else Analyze (Rules, 1).Kind = List
               then 1 else Leaf_Target (Rules, 1));

            function Node_Of (I : Natural; Ref : String) return String is
              ("(Kind => " & V (I) & "_Kind, Ref_" & V (I) & " => " & Ref & ")");

            --  A node of list rule L from the element Idx of the vector Vec.
            function Elem_Node (L : Natural; Vec, Idx : String) return String is
              (if Elem_Is_Access (L)
               then Node_Of (L, V (L) & "_Ref (" & Vec & ".Element (" & Idx & "))")
               else Node_Of (L, V (L) & "_Ref'(" & Vec & ".Constant_Reference ("
                                & Idx & ").Element.all'Unchecked_Access)"));

            procedure Push (Ind : Natural; Name, Index, Value : String) is
            begin
               P (Ind, "K.Append (Kid'(Name => To_Unbounded_String (" & Q (Name)
                  & "), Index => " & Index & ", Value => " & Value & "));");
            end Push;

            procedure Kid
              (Idx : Natural; Nm : String; Is_List : Boolean; Prefix : String;
               Held : Boolean; Ind : Natural)
            is
               F   : constant String := Prefix & Ada_Field (Nm);
               Lbl : constant String := HBNF_C.Member_Label (Nm);
               J   : constant Natural := Find (Rules, Nm);
               T   : constant String :=
                 Value_Type (Rules, Nm);
               Rec : constant Natural :=
                 (if J > 0 and then Is_Record (Analyze (Rules, J)) then J
                  elsif Is_Back (Backs, Idx, Nm) then Leaf_Record (Rules, Nm)
                  elsif Held and then Alias_Record (Rules, Nm) /= 0
                  then Leaf_Record (Rules, Nm)
                  else 0);
            begin
               if Is_List then
                  if Rec > 0 or else (J > 0 and then Alias_Record (Rules, Nm) /= 0) then
                     declare
                        R : constant Natural :=
                          (if Rec > 0 then Rec else Leaf_Record (Rules, Nm));
                     begin
                        P (Ind, "for I in " & F & ".First_Index .. " & F & ".Last_Index loop");
                        Push (Ind + 1, Lbl, "I - " & F & ".First_Index",
                              "(Kind => Node_Val, N => "
                              & Node_Of (R, V (R) & "_Ref (" & F & ".Element (I))") & ")");
                        P (Ind, "end loop;");
                     end;
                  elsif T = "Unbounded_String" then
                     P (Ind, "for I in " & F & ".First_Index .. " & F & ".Last_Index loop");
                     Push (Ind + 1, Lbl, "I - " & F & ".First_Index",
                           "(Kind => Str_Val, S => " & F & ".Element (I))");
                     P (Ind, "end loop;");
                  end if;
               elsif Rec > 0 then
                  P (Ind, "if " & F & " /= null then");
                  Push (Ind + 1, Lbl, "-1", "(Kind => Node_Val, N => "
                        & Node_Of (Rec, V (Rec) & "_Ref (" & F & ")") & ")");
                  P (Ind, "end if;");
               elsif J > 0 and then Analyze (Rules, J).Kind = List and then Scalar_Ada_Type (Nm) = "" then
                  P (Ind, "for I in " & F & ".First_Index .. " & F & ".Last_Index loop");
                  Push (Ind + 1, Lbl, "I - " & F & ".First_Index",
                        "(Kind => Node_Val, N => " & Elem_Node (J, F, "I") & ")");
                  P (Ind, "end loop;");
               elsif J > 0 and then Analyze (Rules, J).Kind = Enum and then Scalar_Ada_Type (Nm) = "" then
                  declare
                     Names : constant String_Vectors.Vector :=
                       Enum_Names (Analyze (Rules, J).Literals);
                  begin
                     P (Ind, "case " & F & " is");
                     for Ln in 1 .. Natural (Analyze (Rules, J).Literals.Length) loop
                        P (Ind + 1, "when " & Ada_Ident (Nm) & "_" & To_String (Names (Ln)) & " =>");
                        Push (Ind + 2, Lbl, "-1", "(Kind => Enum_Val, E => To_Unbounded_String ("
                              & Q (To_String (Analyze (Rules, J).Literals (Ln))) & "))");
                     end loop;
                     P (Ind, "end case;");
                  end;
               elsif T = "Unbounded_String" then
                  Push (Ind, Lbl, "-1", "(Kind => Str_Val, S => " & F & ")");
               elsif T = "Boolean" then
                  Push (Ind, Lbl, "-1", "(Kind => Bool_Val, B => " & F & ")");
               elsif T'Length > 8 and then T (T'First .. T'First + 7) = "Unsigned" then
                  Push (Ind, Lbl, "-1", "(Kind => UInt_Val, U => Interfaces.Unsigned_64 (" & F & "))");
               elsif T = "Long_Long_Integer" or else
                 (T'Length > 7 and then T (T'First .. T'First + 6) = "Integer")
               then
                  Push (Ind, Lbl, "-1", "(Kind => Int_Val, I => Long_Long_Integer (" & F & "))");
               end if;
            end Kid;

            procedure Members
              (Idx : Natural; Alts_Of : Element_Vectors.Vector; Has_Alts : Boolean;
               All_Members : Member_Vectors.Vector; Bare : Boolean; Ind : Natural)
            is
            begin
               if not Has_Alts then
                  for M of All_Members loop
                     Kid (Idx, To_String (M.Name), M.Is_List and then not Bare, "X.", Bare, Ind);
                  end loop;
                  return;
               end if;
               P (Ind, "case X.Alt_No is");
               declare
                  St : Natural := 1;
                  Br : Natural := 0;
                  Nn : constant Natural := Natural (Alts_Of.Length);
               begin
                  for Kk in 1 .. Nn + 1 loop
                     if Kk > Nn or else Alts_Of (Kk).Kind = Alt then
                        Br := Br + 1;
                        declare
                           Sub  : Element_Vectors.Vector;
                           Ms   : Member_Vectors.Vector;
                           Lits : String_Vectors.Vector;
                           Hasa : Boolean := False;
                        begin
                           for Jj in St .. Kk - 1 loop
                              Sub.Append (Alts_Of (Jj));
                           end loop;
                           Collect (Sub, Ms, Lits, Hasa);
                           P (Ind + 1, "when " & Img (Br) & " =>");
                           for M of Ms loop
                              Kid (Idx, To_String (M.Name), M.Is_List and then not Bare,
                                   "X.", Bare, Ind + 2);
                           end loop;
                           P (Ind + 2, "null;");
                        end;
                        St := Kk + 1;
                     end if;
                  end loop;
               end;
               P (Ind + 1, "when others => null;");
               P (Ind, "end case;");
            end Members;

            function Has_Alts (I : Natural) return Boolean is
              (Struct_Alt (Rules (I), Analyze (Rules, I))
               or else (Entry_Alt (Rules (I), Analyze (Rules, I))
                        and then Rules (I).Left_Bases = 0));

            function Alt_Els (I : Natural) return Element_Vectors.Vector is
              (if Analyze (Rules, I).Kind = Struct then Rules (I).Pattern
               else Rules (I).Pattern (1).Items);
         begin
            --  the specification
            PS (1, "--  The tree as nodes (--ast): any record or list element, walked, listed and dumped.");
            declare
               Kinds : Unbounded_String;
            begin
               for I in 1 .. N loop
                  if Walked_Kind (I) then
                     Append (Kinds, (if Length (Kinds) > 0 then ", " else "") & V (I) & "_Kind");
                  end if;
               end loop;
               PS (1, "type Node_Kind is (" & To_String (Kinds) & ");");
            end;
            for I in 1 .. N loop
               if Walked_Kind (I) then
                  PS (1, "type " & V (I) & "_Ref is access constant " & Elem_Type (I) & ";");
               end if;
            end loop;
            PS (1, "type Node (Kind : Node_Kind := " & V (Rt) & "_Kind) is record");
            PS (2, "case Kind is");
            for I in 1 .. N loop
               if Walked_Kind (I) then
                  PS (3, "when " & V (I) & "_Kind => Ref_" & V (I) & " : " & V (I) & "_Ref;");
               end if;
            end loop;
            PS (2, "end case;");
            PS (1, "end record;");
            PS (1, "type Val_Kind is (Node_Val, Str_Val, Int_Val, UInt_Val, Bool_Val, Enum_Val);");
            PS (1, "type Val (Kind : Val_Kind := Str_Val) is record");
            PS (2, "case Kind is");
            PS (3, "when Node_Val => N : Node;");
            PS (3, "when Str_Val  => S : Unbounded_String;");
            PS (3, "when Int_Val  => I : Long_Long_Integer;");
            PS (3, "when UInt_Val => U : Interfaces.Unsigned_64;");
            PS (3, "when Bool_Val => B : Boolean;");
            PS (3, "when Enum_Val => E : Unbounded_String;");
            PS (2, "end case;");
            PS (1, "end record;");
            PS (1, "--  A member of a node: its name, its place if it is a list element (-1 if not), what it holds.");
            PS (1, "type Kid is record");
            PS (2, "Name  : Unbounded_String;");
            PS (2, "Index : Integer := -1;");
            PS (2, "Value : Val;");
            PS (1, "end record;");
            PS (1, "package Kid_Vectors is new Ada.Containers.Vectors (Positive, Kid);");
            PS (1, "type Walk_Action is (Continue, Skip, Stop);");
            PS (1, "--  Override Enter and Leave; Enter answers Continue, Skip (no descent, no Leave) or Stop.");
            PS (1, "type Walker is abstract tagged limited null record;");
            PS (1, "function Enter (W : in out Walker; N : Node) return Walk_Action is (Continue);");
            PS (1, "function Leave (W : in out Walker; N : Node) return Walk_Action is (Continue);");
            PS (1, "function Node_Kind_Name (N : Node) return String;");
            PS (1, "--  Which alternative a node took, from 1; 0 for a node whose rule has none recorded.");
            PS (1, "function Node_Alt (N : Node) return Natural;");
            PS (1, "function Node_Alt_Name (N : Node; Alt : Natural) return String;");
            PS (1, "function Node_Kids (N : Node) return Kid_Vectors.Vector;");
            PS (1, "--  False if the walk was stopped.");
            PS (1, "function Node_Walk (N : Node; W : in out Walker'Class) return Boolean;");
            PS (1, "--  The S-expression of a node: (kind[alternative] member=value ...).");
            PS (1, "function Node_Dump (N : Node) return String;");
            PS (1, "--  Two nodes are equal when their dumps are.");
            PS (1, "function Node_Equal (A, B : Node) return Boolean;");
            declare
               R  : constant Rule := Rules (1);
               CN : constant String := Ada_Ident (To_String (R.Name));
            begin
               PS (1, "function Walk_" & CN & " (Root : " & Ret_Type (1)
                   & "; W : in out Walker'Class) return Boolean;");
               PS (1, "function Dump_" & CN & " (Root : " & Ret_Type (1) & ") return String;");
            end;
            if Spans_On then
               PS (1, "--  Where a node is in the text: its first byte and its last + 1 (offsets from 0;");
               PS (1, "--  the blanks before it are not in it).  Known is False for a node with no span.");
               PS (1, "type Span is record");
               PS (2, "Known : Boolean := False;");
               PS (2, "First : Natural := 0;");
               PS (2, "Last  : Natural := 0;");
               PS (1, "end record;");
               PS (1, "function Node_Span (N : Node) return Span;");
               PS (1, "type Place is record");
               PS (2, "Line : Positive;");
               PS (2, "Col  : Positive;");
               PS (1, "end record;");
               PS (1, "--  The line and the column, both from 1, of a byte offset (from 0) of Text.");
               PS (1, "function Node_Where (Text : String; Pos : Natural) return Place;");
            end if;
            if Parents_On then
               PS (1, "--  Which node holds each node (--parents): built by Link_<Root>, read by Parent.");
               PS (1, "type Parent_Key is record");
               PS (2, "Addr : System.Storage_Elements.Integer_Address;");
               PS (2, "Kind : Node_Kind;");
               PS (1, "end record;");
               PS (1, "use type System.Storage_Elements.Integer_Address;");
               PS (1, "function ""<"" (A, B : Parent_Key) return Boolean is");
               PS (2, "(A.Addr < B.Addr or else (A.Addr = B.Addr and then A.Kind < B.Kind));");
               PS (1, "package Parent_Maps is new Ada.Containers.Ordered_Maps (Parent_Key, Node);");
               PS (1, "type Parents is record");
               PS (2, "Map : Parent_Maps.Map;");
               PS (1, "end record;");
               PS (1, "type Maybe_Node (Found : Boolean := False) is record");
               PS (2, "case Found is");
               PS (3, "when True  => N : Node;");
               PS (3, "when False => null;");
               PS (2, "end case;");
               PS (1, "end record;");
               PS (1, "--  The node that holds N; not Found for a root.");
               PS (1, "function Parent (Ps : Parents; N : Node) return Maybe_Node;");
               PS (1, "function Link_" & Ada_Ident (To_String (Rules (1).Name))
                   & " (Root : " & Ret_Type (1) & ") return Parents;");
            end if;
            PS (0, "");

            --  the body
            P (1, "--  ---- the tree as nodes (--ast) ----");
            P (1, "function Node_Kind_Name (N : Node) return String is");
            P (2, "(case N.Kind is");
            declare
               First : Boolean := True;
            begin
               for I in 1 .. N loop
                  if Walked_Kind (I) then
                     P (3, (if First then "" else "") & "when " & V (I) & "_Kind => "
                        & Q (To_String (Rules (I).Name)) & ",");
                     First := False;
                  end if;
               end loop;
            end;
            P (3, "when others => """");");
            P (1, "");
            P (1, "function Node_Alt (N : Node) return Natural is");
            P (1, "begin");
            P (2, "case N.Kind is");
            for I in 1 .. N loop
               if Walked_Kind (I) and then Has_Alts (I) then
                  P (3, "when " & V (I) & "_Kind => return N.Ref_" & V (I) & ".Alt_No;");
               end if;
            end loop;
            P (3, "when others => return 0;");
            P (2, "end case;");
            P (1, "end Node_Alt;");
            P (1, "");
            P (1, "function Node_Alt_Name (N : Node; Alt : Natural) return String is");
            P (1, "begin");
            P (2, "case N.Kind is");
            for I in 1 .. N loop
               if Walked_Kind (I) and then Has_Alts (I) then
                  P (3, "when " & V (I) & "_Kind =>");
                  P (4, "case Alt is");
                  declare
                     Els : constant Element_Vectors.Vector := Alt_Els (I);
                     Nb  : Natural := 1;
                  begin
                     for X of Els loop
                        if X.Kind = Alt then
                           Nb := Nb + 1;
                        end if;
                     end loop;
                     for B in 1 .. Nb loop
                        P (5, "when " & Img (B) & " => return " & Q (HBNF_C.Alt_Label (Els, B)) & ";");
                     end loop;
                  end;
                  P (5, "when others => return """";");
                  P (4, "end case;");
               end if;
            end loop;
            P (3, "when others => return """";");
            P (2, "end case;");
            P (1, "end Node_Alt_Name;");
            P (1, "");
            P (1, "function Node_Kids (N : Node) return Kid_Vectors.Vector is");
            P (2, "K : Kid_Vectors.Vector;");
            P (1, "begin");
            P (2, "case N.Kind is");
            for I in 1 .. N loop
               if Walked_Kind (I) then
                  declare
                     Info : constant Rule_Info := Analyze (Rules, I);
                  begin
                     P (3, "when " & V (I) & "_Kind =>");
                     P (4, "declare");
                     P (5, "X : constant " & V (I) & "_Ref := N.Ref_" & V (I) & ";");
                     P (4, "begin");
                     if Is_Record (Info) then
                        Members (I, Alt_Els (I), Has_Alts (I), Info.Members, False, 5);
                     elsif not Info.Elem_Members.Is_Empty then
                        Members (I, Alt_Els (I), Has_Alts (I), Info.Elem_Members, True, 5);
                     elsif Info.Elem_Name /= Null_Unbounded_String then
                        declare
                           EN : constant String := To_String (Info.Elem_Name);
                           E  : constant Natural := Find (Rules, EN);
                           Lf : constant Natural :=
                             (if E > 0 and then Is_Record (Analyze (Rules, E)) then E
                              elsif Alias_Record (Rules, EN) /= 0 then Leaf_Record (Rules, EN)
                              else 0);
                        begin
                           if Lf > 0 then
                              Push (5, HBNF_C.Member_Label (EN), "-1",
                                    "(Kind => Node_Val, N => " & Node_Of (Lf, V (Lf) & "_Ref (X)") & ")");
                           elsif Resolve_Type (Rules, EN) = "Unbounded_String" then
                              Push (5, HBNF_C.Member_Label (EN), "-1", "(Kind => Str_Val, S => X.all)");
                           end if;
                        end;
                     else
                        Push (5, "value", "-1", "(Kind => Str_Val, S => X.all)");
                     end if;
                     P (5, "null;");
                     P (4, "end;");
                  end;
               end if;
            end loop;
            P (2, "end case;");
            P (2, "return K;");
            P (1, "end Node_Kids;");
            P (1, "");
            P (1, "function Node_Walk (N : Node; W : in out Walker'Class) return Boolean is");
            P (2, "A : constant Walk_Action := Enter (W, N);");
            P (1, "begin");
            P (2, "if A = Stop then");
            P (3, "return False;");
            P (2, "elsif A = Skip then");
            P (3, "return True;");
            P (2, "end if;");
            P (2, "for K of Node_Kids (N) loop");
            P (3, "if K.Value.Kind = Node_Val and then not Node_Walk (K.Value.N, W) then");
            P (4, "return False;");
            P (3, "end if;");
            P (2, "end loop;");
            P (2, "return Leave (W, N) /= Stop;");
            P (1, "end Node_Walk;");
            P (1, "");
            P (1, "procedure Dump_Into (S : in out Unbounded_String; N : Node) is");
            P (2, "A : constant Natural := Node_Alt (N);");
            P (2, "function Img (X : Long_Long_Integer) return String is");
            P (3, "(if X < 0 then Long_Long_Integer'Image (X)");
            P (3, " else Long_Long_Integer'Image (X) (2 .. Long_Long_Integer'Image (X)'Last));");
            P (1, "begin");
            P (2, "Append (S, ""("" & Node_Kind_Name (N));");
            P (2, "if A /= 0 then");
            P (3, "Append (S, ""["" & Node_Alt_Name (N, A) & ""]"");");
            P (2, "end if;");
            P (2, "for K of Node_Kids (N) loop");
            P (3, "Append (S, "" "" & To_String (K.Name));");
            P (3, "if K.Index >= 0 then");
            P (4, "Append (S, ""["" & Img (Long_Long_Integer (K.Index)) & ""]"");");
            P (3, "end if;");
            P (3, "Append (S, ""="");");
            P (3, "case K.Value.Kind is");
            P (4, "when Node_Val => Dump_Into (S, K.Value.N);");
            P (4, "when Str_Val =>");
            P (5, "Append (S, '""');");
            P (5, "for C of To_String (K.Value.S) loop");
            P (6, "if C = '""' or else C = '\' then");
            P (7, "Append (S, '\');");
            P (6, "end if;");
            P (6, "if C = ASCII.LF then");
            P (7, "Append (S, ""\n"");");
            P (6, "else");
            P (7, "Append (S, C);");
            P (6, "end if;");
            P (5, "end loop;");
            P (5, "Append (S, '""');");
            P (4, "when Int_Val  => Append (S, Img (K.Value.I));");
            P (4, "when UInt_Val => Append (S, Img (Long_Long_Integer (K.Value.U)));");
            P (4, "when Bool_Val => Append (S, (if K.Value.B then ""true"" else ""false""));");
            P (4, "when Enum_Val => Append (S, K.Value.E);");
            P (3, "end case;");
            P (2, "end loop;");
            P (2, "Append (S, "")"");");
            P (1, "end Dump_Into;");
            P (1, "");
            P (1, "function Node_Dump (N : Node) return String is");
            P (2, "S : Unbounded_String;");
            P (1, "begin");
            P (2, "Dump_Into (S, N);");
            P (2, "return To_String (S);");
            P (1, "end Node_Dump;");
            P (1, "");
            P (1, "function Node_Equal (A, B : Node) return Boolean is");
            P (2, "(Node_Dump (A) = Node_Dump (B));");
            P (1, "");
            if Spans_On then
               P (1, "function Node_Span (N : Node) return Span is");
               P (1, "begin");
               P (2, "case N.Kind is");
               for I in 1 .. N loop
                  if Walked_Kind (I) then
                     declare
                        Info : constant Rule_Info := Analyze (Rules, I);
                        L    : Natural := 0;
                     begin
                        if Info.Kind = List and then Info.Elem_Members.Is_Empty
                          and then Info.Elem_Name /= Null_Unbounded_String
                        then
                           declare
                              EN : constant String := To_String (Info.Elem_Name);
                              E  : constant Natural := Find (Rules, EN);
                           begin
                              L := (if E > 0 and then Is_Record (Analyze (Rules, E)) then E
                                    elsif Alias_Record (Rules, EN) /= 0 then Leaf_Record (Rules, EN)
                                    else 0);
                           end;
                        end if;
                        if Has_Span (Info) or else (L > 0 and then Has_Span (Analyze (Rules, L))) then
                           P (3, "when " & V (I) & "_Kind =>");
                           P (4, "return (Known => True, First => N.Ref_" & V (I)
                              & ".Span_Start, Last => N.Ref_" & V (I) & ".Span_End);");
                        end if;
                     end;
                  end if;
               end loop;
               P (3, "when others => return (Known => False, First => 0, Last => 0);");
               P (2, "end case;");
               P (1, "end Node_Span;");
               P (1, "");
               P (1, "function Node_Where (Text : String; Pos : Natural) return Place is");
               P (2, "L : Positive := 1;");
               P (2, "C : Positive := 1;");
               P (1, "begin");
               P (2, "for I in 0 .. Pos - 1 loop");
               P (3, "exit when Text'First + I > Text'Last;");
               P (3, "if Text (Text'First + I) = ASCII.LF then");
               P (4, "L := L + 1;");
               P (4, "C := 1;");
               P (3, "else");
               P (4, "C := C + 1;");
               P (3, "end if;");
               P (2, "end loop;");
               P (2, "return (Line => L, Col => C);");
               P (1, "end Node_Where;");
               P (1, "");
            end if;
            if Parents_On then
               P (1, "function Key_Of (N : Node) return Parent_Key is");
               P (1, "begin");
               P (2, "case N.Kind is");
               for I in 1 .. N loop
                  if Walked_Kind (I) then
                     P (3, "when " & V (I) & "_Kind =>");
                     P (4, "return (System.Storage_Elements.To_Integer (N.Ref_" & V (I)
                        & ".all'Address), N.Kind);");
                  end if;
               end loop;
               P (2, "end case;");
               P (1, "end Key_Of;");
               P (1, "");
               P (1, "function Parent (Ps : Parents; N : Node) return Maybe_Node is");
               P (2, "C : constant Parent_Maps.Cursor := Ps.Map.Find (Key_Of (N));");
               P (1, "begin");
               P (2, "if Parent_Maps.Has_Element (C) then");
               P (3, "return (Found => True, N => Parent_Maps.Element (C));");
               P (2, "end if;");
               P (2, "return (Found => False);");
               P (1, "end Parent;");
               P (1, "");
               P (1, "procedure Link_Into (M : in out Parent_Maps.Map; N : Node) is");
               P (1, "begin");
               P (2, "for K of Node_Kids (N) loop");
               P (3, "if K.Value.Kind = Node_Val then");
               P (4, "M.Include (Key_Of (K.Value.N), N);");
               P (4, "Link_Into (M, K.Value.N);");
               P (3, "end if;");
               P (2, "end loop;");
               P (1, "end Link_Into;");
               P (1, "");
               declare
                  CN : constant String := Ada_Ident (To_String (Rules (1).Name));
               begin
                  P (1, "function Link_" & CN & " (Root : " & Ret_Type (1) & ") return Parents is");
                  P (2, "Ps : Parents;");
                  P (1, "begin");
                  if Is_Record (Analyze (Rules, Rt)) then
                     P (2, "Link_Into (Ps.Map, " & Node_Of (Rt, V (Rt) & "_Ref'(Root'Unrestricted_Access)") & ");");
                  else
                     P (2, "for I in Root.First_Index .. Root.Last_Index loop");
                     P (3, "Link_Into (Ps.Map, " & Elem_Node (Rt, "Root", "I") & ");");
                     P (2, "end loop;");
                  end if;
                  P (2, "return Ps;");
                  P (1, "end Link_" & CN & ";");
                  P (1, "");
               end;
            end if;
            declare
               R  : constant Rule := Rules (1);
               CN : constant String := Ada_Ident (To_String (R.Name));
            begin
               P (1, "function Walk_" & CN & " (Root : " & Ret_Type (1)
                  & "; W : in out Walker'Class) return Boolean is");
               P (1, "begin");
               if Is_Record (Analyze (Rules, Rt)) then
                  P (2, "return Node_Walk (" & Node_Of (Rt, V (Rt) & "_Ref'(Root'Unrestricted_Access)") & ", W);");
               else
                  P (2, "for I in Root.First_Index .. Root.Last_Index loop");
                  P (3, "if not Node_Walk (" & Elem_Node (Rt, "Root", "I") & ", W) then");
                  P (4, "return False;");
                  P (3, "end if;");
                  P (2, "end loop;");
                  P (2, "return True;");
               end if;
               P (1, "end Walk_" & CN & ";");
               P (1, "");
               P (1, "function Dump_" & CN & " (Root : " & Ret_Type (1) & ") return String is");
               if Is_Record (Analyze (Rules, Rt)) then
                  P (1, "begin");
                  P (2, "return Node_Dump (" & Node_Of (Rt, V (Rt) & "_Ref'(Root'Unrestricted_Access)") & ");");
               else
                  P (2, "S : Unbounded_String := To_Unbounded_String (""(" & To_String (R.Name) & """);");
                  P (1, "begin");
                  P (2, "for I in Root.First_Index .. Root.Last_Index loop");
                  P (3, "Append (S, "" "");");
                  P (3, "Dump_Into (S, " & Elem_Node (Rt, "Root", "I") & ");");
                  P (2, "end loop;");
                  P (2, "return To_String (S) & "")"";");
               end if;
               P (1, "end Dump_" & CN & ";");
               P (1, "");
            end;
         end;
      end if;

      if Writer_On and then (Is_Record (Analyze (Rules, 1))
                             or else Analyze (Rules, 1).Kind = List
                             or else Over_Leaf (Rules, 1))
      then
         Append (Free_Decls, "   --  The tree as text, canonical; Ok is False, and Message says why, when a"
                 & LF & "   --  node cannot be written." & LF
                 & "   procedure Write_" & Ada_Ident (To_String (Rules (1).Name))
                 & " (V : " & Ret_Type (1) & ";" & LF
                 & "      Text : out Unbounded_String; Ok : out Boolean;" & LF
                 & "      Message : out Unbounded_String);" & LF & LF
                 & "   --  A pretty-printer's say in how the tree is written: Before is asked before each" & LF
                 & "   --  token or literal and returns what goes before it (not Found: the writer's own" & LF
                 & "   --  spacing); Replace may give other text for it; On_Enter and On_Leave are called on" & LF
                 & "   --  entering and leaving each node, with its rule's name." & LF
                 & "   type Layout is tagged limited null record;" & LF
                 & "   type Opt_Text (Found : Boolean := False) is record" & LF
                 & "      case Found is" & LF
                 & "         when True  => Text : Unbounded_String;" & LF
                 & "         when False => null;" & LF
                 & "      end case;" & LF
                 & "   end record;" & LF
                 & "   function Before (L : in out Layout; S : String) return Opt_Text is (Found => False);" & LF
                 & "   function Replace (L : in out Layout; S : String) return Opt_Text is (Found => False);" & LF
                 & "   procedure On_Enter (L : in out Layout; Rule : String) is null;" & LF
                 & "   procedure On_Leave (L : in out Layout; Rule : String) is null;" & LF
                 & "   procedure Write_" & Ada_Ident (To_String (Rules (1).Name))
                 & "_With (V : " & Ret_Type (1) & ";" & LF
                 & "      Lay : in out Layout'Class; Text : out Unbounded_String; Ok : out Boolean;" & LF
                 & "      Message : out Unbounded_String);" & LF & LF);
      end if;

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
         Mustache.Put (V, "hosted_spec", To_String (Hosted_Spec));
         Mustache.Put (V, "spec_withs",
           (if Length (Ast_Body) > 0
            then "with Ada.Containers.Vectors;" & LF & "with Interfaces;" & LF
                 & (if Parents_On
                    then "with Ada.Containers.Ordered_Maps;" & LF
                         & "with System.Storage_Elements;" & LF
                    else "")
            else ""));
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
         Mustache.Put (V, "hosted_with",
           To_String (Hosted_Withs)
           & (if Parents_On and then Length (Ast_Body) > 0
              then "with System.Storage_Elements;" & LF else ""));
         Append (Bdy, Mustache.Render_File ("ada_parser_body", V));
      end;

      --  The scanners.  A core rule the grammar does not define (`word`,
      --  `int`, `str`, `ws`) is a built-in: hand-written Ada, the same scan
      --  the C backend's jets make.  Any other jet is hand-written C, which
      --  this backend cannot run, so it is a stub that matches nothing.
      Emit_Builtin_Scans;
      --  The guards `/` sets where a union needs backtracking (first match
      --  wins, as RFC 3986 section 3.2.2 settles `host`): is the next code
      --  point one that can follow the choice?
      for G in 1 .. HBNF_Grammar.Guard_Count loop
         declare
            Rs  : constant HBNF_Grammar.Guard_Range_Array :=
              HBNF_Grammar.Guard_Ranges (G);
            Gid : constant String := Natural'Image (G);
         begin
            Append (Bdy, "   function Guard_" & Gid (Gid'First + 1 .. Gid'Last)
              & " (S : String; Pos : Natural) return Boolean is" & LF);
            if Rs'Length = 0 then
               Append (Bdy, "   begin" & LF);
               Append (Bdy, "      return Pos > S'Last"
                 & (if HBNF_Grammar.Guard_Eoi (G) then "" else " and then False")
                 & ";" & LF);
               Append (Bdy, "   end Guard_" & Gid (Gid'First + 1 .. Gid'Last) & ";"
                 & LF & LF);
               goto Next_Guard_A;
            end if;
            Append (Bdy, "      B : Natural;" & LF);
            Append (Bdy, "      N : Natural;" & LF);
            Append (Bdy, "      C : Natural;" & LF);
            Append (Bdy, "   begin" & LF);
            Append (Bdy, "      if Pos > S'Last then return "
              & (if HBNF_Grammar.Guard_Eoi (G) then "True" else "False")
              & "; end if;" & LF);
            Append (Bdy, "      B := Character'Pos (S (Pos));" & LF);
            Append (Bdy, "      N := (if B < 16#80# then 1 elsif B < 16#E0# then 2"
              & " elsif B < 16#F0# then 3 else 4);" & LF);
            Append (Bdy, "      if Pos + N - 1 > S'Last then return False; end if;" & LF);
            Append (Bdy, "      C := (if N = 1 then B elsif N = 2 then B mod 16#20#"
              & " elsif N = 3 then B mod 16#10# else B mod 8);" & LF);
            Append (Bdy, "      for K in 1 .. N - 1 loop" & LF);
            Append (Bdy, "         C := C * 64 + Character'Pos (S (Pos + K)) mod 64;" & LF);
            Append (Bdy, "      end loop;" & LF);
            Append (Bdy, "      return False");
            for R of Rs loop
               Append (Bdy, " or else (C >= " & Natural'Image (R.Lo)
                 & " and then C <= " & Natural'Image (R.Hi) & ")");
            end loop;
            Append (Bdy, ";" & LF);
            Append (Bdy, "   end Guard_" & Gid (Gid'First + 1 .. Gid'Last) & ";" & LF & LF);
            <<Next_Guard_A>> null;
         end;
      end loop;
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String
           and then not Is_Builtin_Jet (To_String (Rules (I).Name))
         then
            declare
               NM   : constant String := To_String (Rules (I).Name);
               Code : constant String :=
                 HBNF_Grammar.Jet_Body (NM, HBNF_Grammar.Ada_Target);
            begin
               Append (Bdy, "   function Jet_" & Ada_Ident (NM)
                 & " (S : String; Pos, Len : Natural) return Natural is");
               Append (Bdy, LF);
               if Code /= "" then
                  --  The author's body, declarations and `begin` included.
                  Append (Bdy, Code);
                  Append (Bdy, LF);
               else
                  Append (Bdy, "      pragma Unreferenced (S, Pos, Len);");
                  Append (Bdy, LF);
                  Append (Bdy, "   begin");
                  Append (Bdy, LF);
                  Append (Bdy, "      return 0;  --  no Ada code: write `"
                    & NM & " = Ada { ... }`");
                  Append (Bdy, LF);
               end if;
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

      declare
         --  The exceptions (`X = A - B`) call the scanner of B, which may come
         --  after X: their wrappers go after every scanner.
         Wrappers : U;
      begin
      for I in 1 .. N loop
         if Is_Char_Rule (Rules, To_String (Rules (I).Name))
           and then (Is_Char_Token (Rules, To_String (Rules (I).Name))
                     or else To_String (Rules (I).Name) = Ws_Name)
         then
            declare
               NM  : constant String := To_String (Rules (I).Name);
               DNF : constant Cp_Branch_Atom_Vectors.Vector := (if Is_Dfa_Token (Rules, NM)
                       or else HBNF_Grammar.Except_Operand (NM) /= ""
                    then Cp_Branch_Atom_Vectors.Empty_Vector
                    else Char_DNF (Rules, NM));

            begin
               if HBNF_Grammar.Except_Operand (NM) /= "" then
                  --  `X = A - B`: A's text, unless B matches exactly that text.
                  Append (Wrappers, "   function Scan_" & Ada_Ident (NM)
                    & " (S : String; Pos, Len : Natural) return Natural is" & LF);
                  Append (Wrappers, "      N : constant Natural := Scan_"
                    & Ada_Ident (HBNF_Grammar.Except_Base (NM))
                    & " (S, Pos, Len);" & LF);
                  Append (Wrappers, "   begin" & LF);
                  Append (Wrappers, "      if N = 0 or else Scan_"
                    & Ada_Ident (HBNF_Grammar.Except_Operand (NM))
                    & " (S, Pos, Pos + N - 1) = N then" & LF);
                  Append (Wrappers, "         return 0;" & LF);
                  Append (Wrappers, "      end if;" & LF);
                  Append (Wrappers, "      return N;" & LF);
                  Append (Wrappers, "   end Scan_" & Ada_Ident (NM) & ";" & LF & LF);
               elsif Is_Dfa_Token (Rules, NM) then
                  declare
                     D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
                     Ok  : Boolean;
                     Why : Unbounded_String;
                     Lo, Hi, To, First, Acc : Unbounded_String;
                  begin
                     HBNF_Lookahead.Token_Dfa (Rules, NM, D, Ok, Why);
                     HBNF_Lookahead.Dfa_Tables (D, Lo, Hi, To, First, Acc);
                     Append (Bdy, "   function Scan_" & Ada_Ident (NM)
                       & " (S : String; Pos, Len : Natural) return Natural is" & LF);
                     Append (Bdy, "      type Table is array (Natural range <>) of Natural;" & LF);
                     Append (Bdy, "      Lo    : constant Table := (" & To_String (Lo) & ");" & LF);
                     Append (Bdy, "      Hi    : constant Table := (" & To_String (Hi) & ");" & LF);
                     Append (Bdy, "      To    : constant Table := (" & To_String (To) & ");" & LF);
                     Append (Bdy, "      First : constant Table := (" & To_String (First) & ");" & LF);
                     Append (Bdy, "      Acc   : constant Table := (" & To_String (Acc) & ");" & LF);
                     Append (Bdy, "      I     : Natural := Pos;" & LF);
                     Append (Bdy, "      Best  : Natural := 0;" & LF);
                     Append (Bdy, "      St    : Natural := 0;" & LF);
                     Append (Bdy, "      Cp, N, K : Natural;" & LF);
                     Append (Bdy, "   begin" & LF);
                     Append (Bdy, "      loop" & LF);
                     Append (Bdy, "         if Acc (St) /= 0 then Best := I - Pos; end if;" & LF);
                     Append (Bdy, "         exit when I > Len;" & LF);
                     Append (Bdy, "         N := Decode_Utf8 (S, I, Len, Cp);" & LF);
                     Append (Bdy, "         exit when N = 0;" & LF);
                     Append (Bdy, "         K := First (St);" & LF);
                     Append (Bdy, "         while K < First (St + 1)" & LF);
                     Append (Bdy, "           and then not (Cp >= Lo (K) and then Cp <= Hi (K))" & LF);
                     Append (Bdy, "         loop" & LF);
                     Append (Bdy, "            K := K + 1;" & LF);
                     Append (Bdy, "         end loop;" & LF);
                     Append (Bdy, "         exit when K = First (St + 1);" & LF);
                     Append (Bdy, "         St := To (K);" & LF);
                     Append (Bdy, "         I := I + N;" & LF);
                     Append (Bdy, "      end loop;" & LF);
                     Append (Bdy, "      return Best;" & LF);
                     Append (Bdy, "   end Scan_" & Ada_Ident (NM) & ";" & LF & LF);
                  end;
               else
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
               end if;
            end;
         end if;
      end loop;
      Append (Bdy, To_String (Wrappers));
      end;


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
              & "      N : constant Natural := Scan_Word (P.Text.all, P.Pos, Limit (P));" & LF
              & "   begin" & LF
              & "      if N = Lit'Length" & LF
              & "        and then Ada.Strings.Equal_Case_Insensitive" & LF
              & "                   (P.Text (P.Pos .. P.Pos + N - 1), Lit)" & LF
              & "      then" & LF
              & "         P.Pos := P.Pos + N;" & LF
              & "      else" & LF
              & "         Fail (P, ""`"" & Lit & ""`"");" & LF
              & "      end if;" & LF
              & "   end Expect_Word_Nocase;" & LF & LF
              & "   --  A case-insensitive literal that is not a keyword: its characters." & LF
              & "   procedure Expect_Lit_Nocase (P : in out Parser; Lit : String) is" & LF
              & "   begin" & LF
              & "      if P.Pos + Lit'Length - 1 <= Limit (P)" & LF
              & "        and then Ada.Strings.Equal_Case_Insensitive" & LF
              & "                   (P.Text (P.Pos .. P.Pos + Lit'Length - 1), Lit)" & LF
              & "      then" & LF
              & "         P.Pos := P.Pos + Lit'Length;" & LF
              & "      else" & LF
              & "         Fail (P, ""`"" & Lit & ""`"");" & LF
              & "      end if;" & LF
              & "   end Expect_Lit_Nocase;" & LF & LF);
         end if;
         if Ws_Name = "" then
            Append (Skip_Body, "   begin" & LF & "      null;" & LF
              & "   end Skip_Ws;");
         else
            Append (Skip_Body, "      N : Natural;" & LF & "   begin" & LF
              & "      loop" & LF
              & "         N := Scan_" & Ada_Ident (Ws_Name)
              & " (P.Text.all, P.Pos, Limit (P));" & LF
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
         Mustache.Put (V, "parser_bit",
           (if Is_Hosted
            then "      Bit  : Natural := 0;   --  bits of the octet at Pos a bit rule has read" & LF
            else ""));
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
      Append (Bdy, Hosted_Code);
      if Length (Act_Decls) > 0 then
         Append (Bdy, To_String (Act_Decls) & LF & To_String (Act_Body));
      end if;

      for I in 1 .. N loop
         declare
            NM : constant String := To_String (Rules (I).Name);
         begin
            if not (Is_Char_Rule (Rules, NM)
                    and then (Is_Core_Name (NM)
                              or else not Is_Char_Token (Rules, NM)))
            then
               Append (Bdy, "   function Body_Of_" & Ada_Ident (NM)
                 & " (P : in out Parser) return " & Ret_Type (I) & " is");
               Append (Bdy, LF);
               Emit_Rule_Decl (I, Bdy);
               Append (Bdy, "   begin");
               Append (Bdy, LF);
               Emit_Rule_Parser (I, Bdy);
               Append (Bdy, "   end Body_Of_" & Ada_Ident (NM) & ";");
               Append (Bdy, LF);
               Append (Bdy, LF);
               --  the rule is on the stack of rules being read while its body runs
               Append (Bdy, "   function Parse_" & Ada_Ident (NM)
                 & " (P : in out Parser) return " & Ret_Type (I) & " is" & LF
                 & "   begin" & LF
                 & "      Enter (P, " & Img (I) & ");" & LF
                 & "      declare" & LF
                 & (if Analyze (Rules, I).Kind = Struct and then Has_Span (Analyze (Rules, I))
                    then "         Save : constant Natural := P.Pos;" & LF
                         & "         R : " & Ret_Type (I) & " := Body_Of_"
                    else "         R : constant " & Ret_Type (I) & " := Body_Of_")
                 & Ada_Ident (NM) & " (P);" & LF
                 & "      begin" & LF
                 & "         P.Depth := P.Depth - 1;" & LF
                 & (if Analyze (Rules, I).Kind = Struct and then Has_Span (Analyze (Rules, I))
                    then (if Rules (I).Whitespace /= Null_Unbounded_String
                          then "         declare K : constant Natural := P.Pos; begin P.Pos := Save;"
                               & " Skip_Ws (P); R.Span_Start := P.Pos - 1; P.Pos := K; end;" & LF
                          else "         R.Span_Start := Save - 1;" & LF)
                         & "         R.Span_End := P.Pos - 1;" & LF
                    else "")
                 & "         return R;" & LF
                 & "      end;" & LF
                 & "   exception" & LF
                 & "      when Parse_Error =>" & LF
                 & "         P.Depth := P.Depth - 1;" & LF
                 & "         raise;" & LF
                 & "   end Parse_" & Ada_Ident (NM) & ";" & LF & LF);
            end if;
         end;
      end loop;

      Append (Bdy, To_String (Ast_Body));

      --  The rules an error names, by number (a rule the reader made up for a
      --  group or an option is left out), and the message of the farthest failure:
      --  what could have stood there, and, for a failure far from where the
      --  rule it is in began, that rule's line.
      declare
         procedure RL (S : String) is
         begin
            Append (Bdy, "   " & S);
            Append (Bdy, LF);
         end RL;
      begin
         RL ("function Rule_Name (I : Natural) return String is");
         RL ("  (case I is");
         for I in 1 .. N loop
            declare
               NM     : constant String := To_String (Rules (I).Name);
               Cut    : Natural := 0;
               Hidden : Boolean := False;
            begin
               for K in reverse NM'Range loop
                  if NM (K) = '_' then
                     Cut := K;
                     exit;
                  end if;
               end loop;
               if Cut > NM'First and then Cut < NM'Last
                 and then (for all C of NM (Cut + 1 .. NM'Last) => C in '0' .. '9')
                 and then Find (Rules, NM (NM'First .. Cut - 1)) /= 0
               then
                  Hidden := True;
               end if;
               RL ("     when " & Img (I) & " => "
                   & (if Hidden then """""" else """" & Ada_Escape (NM) & """") & ",");
            end;
         end loop;
         RL ("     when others => """");");
         RL ("");
         RL ("function Render (P : Parser) return String is");
         RL ("   At_Pos : constant Natural := P.Err_Pos;");
         RL ("   Last   : constant Natural := P.Text'Last;");
         RL ("   At_End : constant Boolean := At_Pos > Last;");
         RL ("   Line   : Natural := 1;");
         RL ("   Col    : Natural := 1;");
         RL ("   Start  : Natural := 1;");
         RL ("   Msg    : Unbounded_String;");
         RL ("");
         RL ("   function Img (N : Natural) return String is");
         RL ("      S : constant String := Natural'Image (N);");
         RL ("   begin");
         RL ("      return S (S'First + 1 .. S'Last);");
         RL ("   end Img;");
         RL ("begin");
         RL ("   for I in 1 .. Natural'Min (At_Pos, Last + 1) - 1 loop");
         RL ("      if P.Text (I) = ASCII.LF then");
         RL ("         Line := Line + 1;");
         RL ("         Col := 1;");
         RL ("         Start := I + 1;");
         RL ("      else");
         RL ("         Col := Col + 1;");
         RL ("      end if;");
         RL ("   end loop;");
         RL ("   Append (Msg, Img (Line) & "":"" & Img (Col) & "":"" & Img (At_Pos - 1) & "": expected "");");
         RL ("   if P.Alt_N > 1 then");
         RL ("      Append (Msg, ""one of "");");
         RL ("   end if;");
         RL ("   for I in 1 .. P.Alt_N loop");
         RL ("      if I > 1 then");
         RL ("         Append (Msg, "", "");");
         RL ("      end if;");
         RL ("      Append (Msg, P.Alts (I));");
         RL ("   end loop;");
         RL ("   if P.More then");
         RL ("      Append (Msg, "", ..."");");
         RL ("   end if;");
         RL ("   Append (Msg, "", found "" & Found (P, At_Pos));");
         RL ("   declare");
         RL ("      Stop : Natural := Start;");
         RL ("   begin");
         RL ("      while Stop <= Last and then P.Text (Stop) /= ASCII.LF loop");
         RL ("         Stop := Stop + 1;");
         RL ("      end loop;");
         RL ("      declare");
         RL ("         W   : constant Natural := Col - 1;");
         RL ("         Pad : constant String :=");
         RL ("           (if W <= Spaces'Length then Spaces (1 .. W) else Spaces);");
         RL ("      begin");
         RL ("         Append (Msg, ASCII.LF & ""  "" & P.Text (Start .. Stop - 1)");
         RL ("           & ASCII.LF & ""  "" & Pad & ""^"");");
         RL ("      end;");
         RL ("   end;");
         RL ("   for K in reverse 1 .. P.Err_Depth loop");
         RL ("      declare");
         RL ("         Nm : constant String := Rule_Name (P.Err_Stk (K));");
         RL ("         Sp : Natural := P.Err_Stkpos (K);");
         RL ("         L  : Natural := 1;");
         RL ("         Ls : Natural := 1;");
         RL ("         Le : Natural;");
         RL ("      begin");
         RL ("         if Nm'Length > 0 then");
         RL ("            while Sp <= Last and then P.Text (Sp) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR loop");
         RL ("               Sp := Sp + 1;");
         RL ("            end loop;");
         RL ("            for I in 1 .. Natural'Min (Sp, Last + 1) - 1 loop");
         RL ("               if P.Text (I) = ASCII.LF then");
         RL ("                  L := L + 1;");
         RL ("                  Ls := I + 1;");
         RL ("               end if;");
         RL ("            end loop;");
         RL ("            if L + (if At_End then 1 else 3) <= Line then");
         RL ("               Le := Ls;");
         RL ("               while Le <= Last and then P.Text (Le) /= ASCII.LF loop");
         RL ("                  Le := Le + 1;");
         RL ("               end loop;");
         RL ("               Append (Msg, ASCII.LF & ""  "" & Img (L) & "":"" & Img (Sp - Ls + 1)");
         RL ("                 & "":"" & Img (Sp - 1) & "": """);
         RL ("                 & (if At_End then ""the "" else ""inside the "") & Nm");
         RL ("                 & "" that begins here"" & (if At_End then "" is not finished:"" else "":"")");
         RL ("                 & ASCII.LF & ""  "" & P.Text (Ls .. Le - 1) & ASCII.LF & ""  """);
         RL ("                 & (if Sp - Ls <= Spaces'Length then Spaces (1 .. Sp - Ls) else Spaces)");
         RL ("                 & ""^"");");
         RL ("               exit;");
         RL ("            end if;");
         RL ("         end if;");
         RL ("      end;");
         RL ("   end loop;");
         RL ("   return To_String (Msg);");
         RL ("end Render;");
         RL ("");
      end;

      --  Write_<root>: the tree as text, when the grammar was generated with
      --  --writer.  Canonical, not lossless: literals come from the grammar,
      --  tokens from their text, and a blank goes between two items only where
      --  they would run together.  A bit rule in the text is written by its own
      --  Emit_Bits_<rule> (which runs its %emit), its octets going in as they
      --  are.  What it cannot write it says at run time, at the node, so a
      --  shape that is not built yet is never written as something close:
      --  alternatives are not recorded in this tree, so a rule that has them
      --  is not written.
      if Writer_On and then (Is_Record (Analyze (Rules, 1))
                             or else Analyze (Rules, 1).Kind = List
                             or else Over_Leaf (Rules, 1))
      then
         declare
            WB : U renames Bdy;

            procedure P (Ind : Natural; S : String) is
            begin
               Append (WB, [1 .. 3 * Ind => ' ']);
               Append (WB, S);
               Append (WB, LF);
            end P;

            function Q (S : String) return String is ("""" & Ada_Escape (S) & """");

            function Bad (Why : String) return String is
              ("Badw (W, " & Q (Why) & ");");

            function Core_Ok (Core : String) return Boolean is
               J : constant Natural := Find (Rules, Core);
            begin
               return (J > 0 and then Rules (J).Jet_Code /= Null_Unbounded_String)
                 or else (Core = "word" and then J = 0);
            end Core_Ok;

            --  The scanner that reads a token of this rule, "null" if none.
            function Scan_Of (Nm : String; Depth : Natural := 0) return String is
               J : constant Natural := Find (Rules, Nm);
            begin
               if Nm = "str" then
                  return (if Core_Ok ("str") then "Scan_Str'Access" else "null");
               elsif Nm = "int" or else (Scalar_Ada_Type (Nm) /= ""
                                         and then Nm /= "word" and then Nm /= "atom"
                                         and then Nm /= "bool" and then Nm /= "flag")
               then
                  return (if Core_Ok ("int") then "Scan_Int'Access" else "null");
               elsif Nm = "word" or else Nm = "atom" or else Nm = "bool"
                 or else Nm = "flag"
               then
                  return (if Core_Ok ("word") then "Scan_Word'Access" else "null");
               end if;
               if J = 0 or else Depth > 8 then
                  return "null";
               end if;
               if Is_Char_Rule (Rules, Nm) then
                  return "Scan_" & Ada_Ident (Nm) & "'Access";
               end if;
               if Natural (Rules (J).Pattern.Length) = 1
                 and then Rules (J).Pattern (1).Kind = Name
                 and then Rules (J).Pattern (1).Min = 1
                 and then Rules (J).Pattern (1).Max = 1
               then
                  return Scan_Of (To_String (Rules (J).Pattern (1).Name), Depth + 1);
               end if;
               return "null";
            end Scan_Of;

            --  A rule whose value came from the core `str` (quoted again).
            function Has_Str (Nm : String; Depth : Natural := 0) return Boolean is
               J : constant Natural := Find (Rules, Nm);
            begin
               if Nm = "str" then
                  return True;
               end if;
               if J = 0 or else Depth > 8 then
                  return False;
               end if;
               for E of Rules (J).Pattern loop
                  if E.Kind = Name and then Has_Str (To_String (E.Name), Depth + 1)
                  then
                     return True;
                  end if;
               end loop;
               return False;
            end Has_Str;

         --  The text of a rule that is only literals.
         function Lit_Text (J : Natural) return String is
            R : U;
         begin
            for X of Rules (J).Pattern loop
               Append (R, X.Lit);
            end loop;
            return To_String (R);
         end Lit_Text;

            --  Write a scalar, enum or bit rule value, or a record held by
            --  value, the object Expr.
            procedure Leaf_Value (Nm, Expr, Gap : String; Ind : Natural) is
               J : constant Natural := Find (Rules, Nm);
               T : constant String :=
                 Value_Type (Rules, Nm);
            begin
               if J = 0
                 and then HBNF_Grammar.Is_Wire_Rule (Nm)
               then
                  P (Ind, "declare");
                  P (Ind + 1, "Bq  : Octets;");
                  P (Ind + 1, "Nbq : Natural;");
                  P (Ind + 1, "Okq : Boolean;");
                  P (Ind + 1, "Mq  : Unbounded_String;");
                  P (Ind, "begin");
                  P (Ind + 1, "Emit_Bits_" & Ada_Ident (Nm) & " (" & Expr
                     & ", Bq, Nbq, Okq, Mq);");
                  P (Ind + 1, "if not Okq then");
                  P (Ind + 2, "Badw (W, To_String (Mq));");
                  P (Ind + 1, "elsif Nbq mod 8 /= 0 then");
                  P (Ind + 2, Bad ("`" & Nm & "` does not end on an octet, so it cannot be written as text"));
                  P (Ind + 1, "else");
                  P (Ind + 2, "for K in 0 .. Nbq / 8 - 1 loop");
                  P (Ind + 3, "Wput (W, (1 => Character'Val (Bq.Element (K))));");
                  P (Ind + 2, "end loop;");
                  P (Ind + 1, "end if;");
                  P (Ind, "end;");
               elsif J > 0 and then Analyze (Rules, J).Kind = Scalar
                 and then not Rules (J).Pattern.Is_Empty
              and then (for all X of Rules (J).Pattern =>
                          X.Kind = Literal and then X.Min = 1 and then X.Max = 1)
               then
                  --  a rule that is one literal: the literal is its value
                  P (Ind, "Wlit (W, " & Gap & ", "
                     & Q (Lit_Text (J)) & ");");
               elsif J > 0 and then Analyze (Rules, J).Kind in Struct | List | Enum and then Scalar_Ada_Type (Nm) = "" then
                  P (Ind, "Wr_" & Ada_Ident (Nm) & " (W, " & Expr & ");");
               elsif J > 0 and then Analyze (Rules, J).Kind = Scalar
                 and then Over_Leaf (Rules, J)
               then
                  P (Ind, "Wr_"
                     & Ada_Ident (To_String (Rules (Leaf_Record (Rules, Nm)).Name))
                     & " (W, " & Expr & ");");
               elsif T = "Unbounded_String" then
                  P (Ind, "W" & (if Has_Str (Nm) then "str" else "tok") & " (W, "
                     & Gap & ", To_String (" & Expr & "), " & Scan_Of (Nm) & ");");
               elsif T = "Boolean" then
                  P (Ind, "Wtok (W, " & Gap & ", (if " & Expr
                     & " then ""yes"" else ""no""), " & Scan_Of ("word") & ");");
               elsif T = "Unsigned_64" then
                  P (Ind, "Wtok (W, " & Gap & ", Trim_Img (Unsigned_64'Image ("
                     & Expr & ")), " & Scan_Of ("int") & ");");
               elsif T /= "" then
                  P (Ind, "Wtok (W, " & Gap & ", Trim_Img (Long_Long_Integer'Image (Long_Long_Integer ("
                     & Expr & "))), " & Scan_Of ("int") & ");");
               else
                  P (Ind, Bad ("`" & Nm & "` is not a value the writer knows how to write"));
               end if;
            end Leaf_Value;

            --  One member of a record, or a repeated name of a sequence.
            procedure Member
              (Idx : Natural; Nm : String; Is_List : Boolean; Prefix, Gap : String;
               Ind : Natural; Held : Boolean)
            is
               F   : constant String := Prefix & Ada_Field (Nm);
               J   : constant Natural := Find (Rules, Nm);
               Rec : constant Natural :=
                 (if J > 0 and then Is_Record (Analyze (Rules, J)) then J
                  elsif Is_Back (Backs, Idx, Nm) then Leaf_Record (Rules, Nm)
                  elsif Held and then Alias_Record (Rules, Nm) /= 0
                  then Leaf_Record (Rules, Nm)
                  else 0);
            begin
               if Is_List then
                  P (Ind, "for Ex of " & F & " loop");
                  if J > 0 and then Is_Record (Analyze (Rules, J)) then
                     P (Ind + 1, "if Ex /= null then Wr_" & Ada_Ident (Nm) & " (W, Ex.all); end if;");
                  elsif Alias_Record (Rules, Nm) /= 0 then
                     P (Ind + 1, "if Ex /= null then Wr_"
                        & Ada_Ident (To_String (Rules (Leaf_Record (Rules, Nm)).Name))
                        & " (W, Ex.all); end if;");
                  elsif J > 0 and then Over_Leaf (Rules, J)
                    and then Analyze (Rules, Leaf_Target (Rules, J)).Kind = List
                  then
                     P (Ind + 1, "Wr_"
                        & Ada_Ident (To_String (Rules (Leaf_Target (Rules, J)).Name))
                        & " (W, Ex);");
                  else
                     Leaf_Value (Nm, "Ex", Gap, Ind + 1);
                  end if;
                  P (Ind, "end loop;");
               elsif Rec > 0 then
                  P (Ind, "if " & F & " /= null then Wr_"
                     & Ada_Ident (To_String (Rules (Rec).Name)) & " (W, " & F
                     & ".all); end if;");
               else
                  Leaf_Value (Nm, F, Gap, Ind);
               end if;
            end Member;

            --  The elements of a sequence, through accessor Prefix.
            procedure Elements
              (Idx : Natural; Els : Element_Vectors.Vector; Prefix, Gap : String;
               Ind : Natural; Held : Boolean; Alt_Ok : Boolean := False;
               Alt_Off : Natural := 0) is
            begin
               if (for some X of Els => X.Kind = Alt) then
                  if not Alt_Ok then
                     P (Ind, Bad ("an alternation inside a group is not recorded in an Ada tree, so it is not written yet"));
                     return;
                  end if;
                  --  one branch per alternative, chosen by the one the parser took
                  declare
                     St : Natural := 1;
                     Br : Natural := 0;
                     Nn : constant Natural := Natural (Els.Length);
                  begin
                     P (Ind, "case " & Prefix & "Alt_No is");
                     for K in 1 .. Nn + 1 loop
                        if K > Nn or else Els (K).Kind = Alt then
                           Br := Br + 1;
                           declare
                              Sub : Element_Vectors.Vector;
                           begin
                              for J in St .. K - 1 loop
                                 Sub.Append (Els (J));
                              end loop;
                              P (Ind + 1, "when " & Img (Br + Alt_Off) & " =>");
                              Elements (Idx, Sub, Prefix, Gap, Ind + 2, Held);
                              P (Ind + 2, "null;");
                           end;
                           St := K + 1;
                        end if;
                     end loop;
                     P (Ind + 1, "when others =>");
                     P (Ind + 2, Bad ("no alternative was recorded (generate with --writer)"));
                     P (Ind, "end case;");
                  end;
                  return;
               end if;
               for E of Els loop
                  case E.Kind is
                     when Literal =>
                        P (Ind, "Wlit (W, " & Gap & ", " & Q (To_String (E.Lit)) & ");");
                     when Name =>
                        Member (Idx, To_String (E.Name),
                                E.Min /= 1 or else E.Max /= 1, Prefix, Gap, Ind, Held);
                     when Group =>
                        if E.Min /= 1 or else E.Max /= 1 then
                           P (Ind, Bad ("a repeated group inside a sequence"));
                        else
                           Elements (Idx, E.Items, Prefix, Gap, Ind, Held);
                        end if;
                     when others =>
                        P (Ind, Bad ("an element the writer does not know"));
                  end case;
               end loop;
            end Elements;

            function List_Elem_Type (Info : Rule_Info; CN : String) return String is
              (if not Info.Elem_Members.Is_Empty then CN & "_Type" else CN & "_Type");
         begin
            P (1, "--  ---- write (the tree as text, canonical) ----");
            P (1, "type Scan_Access is access function (S : String; Pos, Len : Natural) return Natural;");
            P (1, "type Wr_State is record");
            P (2, "Buf   : Unbounded_String;");
            P (2, "Last  : Character := Character'Val (0);");
            P (2, "Bad   : Unbounded_String;");
            P (2, "Pscan : Scan_Access := null;");
            P (2, "Ptxt  : Unbounded_String;");
            P (2, "Lay   : access Layout'Class := null;");
            P (1, "end record;");
            P (1, "");
            P (1, "procedure Badw (W : in out Wr_State; Why : String) is");
            P (1, "begin");
            P (2, "if Length (W.Bad) = 0 then");
            P (3, "W.Bad := To_Unbounded_String (Why);");
            P (2, "end if;");
            P (1, "end Badw;");
            P (1, "");
            P (1, "procedure Wput (W : in out Wr_State; S : String) is");
            P (1, "begin");
            P (2, "if S'Length > 0 then");
            P (3, "Append (W.Buf, S);");
            P (3, "W.Last := S (S'Last);");
            P (2, "end if;");
            P (1, "end Wput;");
            P (1, "");
            P (1, "function Wdelim (C : Character) return Boolean is");
            P (2, "(C in '(' | ')' | '[' | ']' | ',' | ';');");
            P (1, "");
            P (1, "function Trim_Img (S : String) return String is");
            P (2, "(if S'Length > 0 and then S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);");
            P (1, "");
            P (1, "--  Would the item just written, with Mid and S after it, still end where it");
            P (1, "--  did when the grammar's own scanner reads it?");
            P (1, "function Wfits (W : Wr_State; Mid, S : String) return Boolean is");
            P (2, "T : constant String := To_String (W.Ptxt) & Mid & S;");
            P (1, "begin");
            P (2, "return W.Pscan (T, 1, T'Last) = Length (W.Ptxt);");
            P (1, "end Wfits;");
            P (1, "");
            P (1, "--  What goes between the last item and S: nothing, a blank or a newline, the");
            P (1, "--  first that keeps the last item from reading on into S.");
            P (1, "procedure Wbetween (W : in out Wr_State; Gap : Boolean; S : String) is");
            P (2, "A : constant Character := W.Last;");
            P (1, "begin");
            P (2, "if Length (W.Buf) = 0 or else S'Length = 0 then");
            P (3, "return;");
            P (2, "end if;");
            P (2, "declare");
            P (3, "B    : constant Character := S (S'First);");
            P (3, "Pref : constant String :=");
            P (4, "(if Gap and then A > ' ' and then B > ' ' and then not Wdelim (A)");
            P (4, "   and then not Wdelim (B) then "" "" else """");");
            P (2, "begin");
            P (3, "if W.Pscan /= null and then A > ' ' then");
            P (4, "if Wfits (W, Pref, S) then");
            P (5, "Wput (W, Pref);");
            P (4, "elsif Gap and then Wfits (W, "" "", S) then");
            P (5, "Wput (W, "" "");");
            P (4, "elsif Gap and then Wfits (W, (1 => ASCII.LF), S) then");
            P (5, "Wput (W, (1 => ASCII.LF));");
            P (4, "else");
            P (5, "Badw (W, ""two items cannot be written apart: the first would read on into the second"");");
            P (4, "end if;");
            P (3, "else");
            P (4, "Wput (W, Pref);");
            P (3, "end if;");
            P (2, "end;");
            P (1, "end Wbetween;");
            P (1, "");
            P (1, "procedure Wenter (W : in out Wr_State; Rule : String) is");
            P (1, "begin");
            P (2, "if W.Lay /= null then");
            P (3, "On_Enter (W.Lay.all, Rule);");
            P (2, "end if;");
            P (1, "end Wenter;");
            P (1, "");
            P (1, "procedure Wleave (W : in out Wr_State; Rule : String) is");
            P (1, "begin");
            P (2, "if W.Lay /= null then");
            P (3, "On_Leave (W.Lay.all, Rule);");
            P (2, "end if;");
            P (1, "end Wleave;");
            P (1, "");
            P (1, "procedure Wtext (W : in out Wr_State; Gap : Boolean; S : String; Scan : Scan_Access) is");
            P (2, "Sep   : Opt_Text;");
            P (2, "Out_T : Unbounded_String := To_Unbounded_String (S);");
            P (1, "begin");
            P (2, "if S'Length > 0 and then W.Lay /= null then");
            P (3, "Sep := Before (W.Lay.all, S);");
            P (2, "end if;");
            P (2, "if Sep.Found then");
            P (3, "Wput (W, To_String (Sep.Text));");
            P (2, "else");
            P (3, "Wbetween (W, Gap, S);");
            P (2, "end if;");
            P (2, "if S'Length > 0 and then W.Lay /= null then");
            P (3, "declare");
            P (4, "R : constant Opt_Text := Replace (W.Lay.all, S);");
            P (3, "begin");
            P (4, "if R.Found then");
            P (5, "Out_T := R.Text;");
            P (4, "end if;");
            P (3, "end;");
            P (2, "end if;");
            P (2, "Wput (W, To_String (Out_T));");
            P (2, "W.Pscan := Scan;");
            P (2, "if Scan /= null then");
            P (3, "W.Ptxt := Out_T;");
            P (2, "end if;");
            P (1, "end Wtext;");
            P (1, "");
            P (1, "procedure Wlit (W : in out Wr_State; Gap : Boolean; S : String) is");
            P (1, "begin");
            P (2, "Wtext (W, Gap, S, null);");
            P (1, "end Wlit;");
            P (1, "");
            P (1, "procedure Wtok (W : in out Wr_State; Gap : Boolean; S : String; Scan : Scan_Access) is");
            P (1, "begin");
            P (2, "Wtext (W, Gap, S, Scan);");
            P (1, "end Wtok;");
            P (1, "");
            P (1, "procedure Wstr (W : in out Wr_State; Gap : Boolean; S : String; Scan : Scan_Access) is");
            P (2, "T : Unbounded_String := To_Unbounded_String ("""""""");");
            P (1, "begin");
            P (2, "for C of S loop");
            P (3, "if C = '""' or else C = '\' then");
            P (4, "Append (T, '\');");
            P (3, "end if;");
            P (3, "Append (T, C);");
            P (2, "end loop;");
            P (2, "Append (T, '""');");
            P (2, "Wtext (W, Gap, To_String (T), Scan);");
            P (1, "end Wstr;");
            P (1, "");
            for I in 1 .. N loop
               declare
                  Info : constant Rule_Info := Analyze (Rules, I);
                  CN   : constant String := Ada_Ident (To_String (Rules (I).Name));
               begin
                  if Is_Record (Info) or else Info.Kind in List | Enum then
                     P (1, "procedure Wr_" & CN & " (W : in out Wr_State; N : "
                        & CN & "_Type);");
                  end if;
               end;
            end loop;
            P (1, "");
            for I in 1 .. N loop
               declare
                  R    : constant Rule := Rules (I);
                  Info : constant Rule_Info := Analyze (Rules, I);
                  CN   : constant String := Ada_Ident (To_String (R.Name));
                  Gap  : constant String :=
                    (if R.Whitespace /= Null_Unbounded_String then "True" else "False");
               begin
                  if Is_Record (Info) then
                     P (1, "procedure Wr_" & CN & " (W : in out Wr_State; N : "
                        & CN & "_Type) is");
                     P (1, "begin");
                     P (2, "Wenter (W, " & Q (To_String (R.Name)) & ");");
                     if Natural (R.Pattern.Length) = 1 and then R.Pattern (1).Kind = Group then
                        Elements (I, R.Pattern (1).Items, "N.", Gap, 2, False);
                     else
                        Elements (I, R.Pattern, "N.", Gap, 2, False,
                                  Struct_Alt (R, Info));
                     end if;
                     P (2, "Wleave (W, " & Q (To_String (R.Name)) & ");");
                     P (1, "end Wr_" & CN & ";");
                     P (1, "");
                  elsif Info.Kind = List then
                     P (1, "procedure Wr_" & CN & " (W : in out Wr_State; N : "
                        & CN & "_Type) is");
                     P (1, "begin");
                     P (2, "Wenter (W, " & Q (To_String (R.Name)) & ");");
                     declare
                        Nl : constant String :=
                          (if I = 1 and then HBNF_Grammar.Statements
                           then "Wlit (W, False, (1 => ASCII.LF));" else "null;");
                     begin
                        if Info.Elem_Members.Is_Empty and then Info.Elem_Name = Null_Unbounded_String then
                           --  repeated literals: each element is the text it matched
                           P (2, "for Ex of N loop");
                           P (3, "Wlit (W, " & Gap & ", To_String (Ex));");
                           P (3, Nl);
                           P (2, "end loop;");
                        elsif not Info.Elem_Members.Is_Empty and then R.Left_Bases > 0 then
                           P (2, "declare");
                           P (3, "First : Boolean := True;");
                           P (2, "begin");
                           P (3, "for Ex of N loop");
                           P (4, "if First then");
                           Elements (I, Base_Branches (R), "Ex.", Gap, 5, True, True, 0);
                           P (5, "null;");
                           P (4, "else");
                           Elements (I, Tail_Branches (R), "Ex.", Gap, 5, True, True,
                                     Alt_Labels_Count (Base_Branches (R)));
                           P (5, "null;");
                           P (4, "end if;");
                           P (4, "First := False;");
                           P (4, Nl);
                           P (3, "end loop;");
                           P (2, "end;");
                        elsif not Info.Elem_Members.Is_Empty then
                           P (2, "for Ex of N loop");
                           Elements (I, R.Pattern (1).Items, "Ex.", Gap, 3, True,
                                     Entry_Alt (R, Info));
                           P (3, Nl);
                           P (2, "end loop;");
                        else
                           declare
                              EN : constant String := To_String (Info.Elem_Name);
                              E  : constant Natural := Find (Rules, EN);
                           begin
                              P (2, "for Ex of N loop");
                              if E > 0 and then Is_Record (Analyze (Rules, E)) then
                                 P (3, "if Ex /= null then Wr_" & Ada_Ident (EN) & " (W, Ex.all); end if;");
                              elsif Alias_Record (Rules, EN) /= 0 then
                                 P (3, "if Ex /= null then Wr_"
                                    & Ada_Ident (To_String (Rules (Leaf_Record (Rules, EN)).Name))
                                    & " (W, Ex.all); end if;");
                              elsif E > 0 and then Over_Leaf (Rules, E)
                                and then Analyze (Rules, Leaf_Target (Rules, E)).Kind = List
                              then
                                 P (3, "Wr_"
                                    & Ada_Ident (To_String (Rules (Leaf_Target (Rules, E)).Name))
                                    & " (W, Ex);");
                              else
                                 Leaf_Value (EN, "Ex", Gap, 3);
                              end if;
                              P (3, Nl);
                              P (2, "end loop;");
                           end;
                        end if;
                     end;
                     P (2, "Wleave (W, " & Q (To_String (R.Name)) & ");");
                     P (1, "end Wr_" & CN & ";");
                     P (1, "");
                  elsif Info.Kind = Enum then
                     declare
                        Names : constant String_Vectors.Vector :=
                          Enum_Names (Info.Literals);
                     begin
                        P (1, "procedure Wr_" & CN & " (W : in out Wr_State; N : "
                           & CN & "_Type) is");
                        P (1, "begin");
                        P (2, "case N is");
                        for K in 1 .. Natural (Info.Literals.Length) loop
                           P (3, "when " & CN & "_" & To_String (Names (K))
                              & " => Wlit (W, " & Gap & ", "
                              & Q (To_String (Info.Literals (K))) & ");");
                        end loop;
                        P (2, "end case;");
                        P (1, "end Wr_" & CN & ";");
                        P (1, "");
                     end;
                  end if;
               end;
            end loop;
            declare
               CN : constant String := Ada_Ident (To_String (Rules (1).Name));
            begin
               P (1, "procedure Write_" & CN & " (V : " & Ret_Type (1)
                  & "; Text : out Unbounded_String; Ok : out Boolean;");
               P (3, "Message : out Unbounded_String) is");
               P (2, "Lay : Layout;");
               P (1, "begin");
               P (2, "Write_" & CN & "_With (V, Lay, Text, Ok, Message);");
               P (1, "end Write_" & CN & ";");
               P (1, "");
               P (1, "procedure Write_" & CN & "_With (V : " & Ret_Type (1)
                  & ";");
               P (3, "Lay : in out Layout'Class; Text : out Unbounded_String; Ok : out Boolean;");
               P (3, "Message : out Unbounded_String) is");
               P (2, "W : Wr_State;");
               P (1, "begin");
               P (2, "W.Lay := Lay'Unrestricted_Access;");
               P (2, "Wr_" & (if Over_Leaf (Rules, 1)
                              and then not Is_Record (Analyze (Rules, 1))
                              and then Analyze (Rules, 1).Kind /= List
                              then Ada_Ident (To_String (Rules (Leaf_Target (Rules, 1)).Name))
                              else CN) & " (W, V);");
               P (2, "Text := W.Buf;");
               P (2, "Ok := Length (W.Bad) = 0;");
               P (2, "Message := W.Bad;");
               P (1, "end Write_" & CN & "_With;");
               P (1, "");
            end;
         end;
      end if;

      --  Parse_Text: the whole text through the root rule.
      declare
         V : Mustache.Context := Mustache.View;
      begin
         Mustache.Put (V, "root_type", Ret_Type (1));
         Mustache.Put (V, "bit_init", (if Is_Hosted then ", Bit => 0" else ""));
         Mustache.Put (V, "reset",
           (if Is_Hosted and then Hosted_Acts
            then "      Bnf_Warns.Clear;" & LF else ""));
         Mustache.Put (V, "actions",
           (if Is_Hosted and then Hosted_Acts
              and then (Is_Record (Analyze (Rules, 1))
                        or else Analyze (Rules, 1).Kind = List)
            then
              "      declare" & LF
              & "         H : Hooks;" & LF
              & "      begin" & LF
              & "         Act_" & Ada_Ident (To_String (Rules (1).Name)) & " (R, H);" & LF
              & "         Bnf_Warns := H.Warnings;" & LF
              & "      exception" & LF
              & "         when Bnf_Action_Fail =>" & LF
              & "            raise Parse_Error with To_String (H.Msg);" & LF
              & "      end;" & LF
            else ""));
         Mustache.Put (V, "root_fn",
           "Parse_" & Ada_Ident (To_String (Rules (1).Name)));
         --  The root skips whitespace around itself if its file does.
         Mustache.Put (V, "lead_ws",
           (if Rules (1).Whitespace /= Null_Unbounded_String
            then "      Skip_Ws (P);" & LF else ""));
         Mustache.Put (V, "trail_ws",
           (if Rules (1).Whitespace /= Null_Unbounded_String
            then "      Skip_Ws (P);" & LF else ""));
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
