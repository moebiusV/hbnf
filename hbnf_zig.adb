pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Mustache;
with HBNF_Compilable;
with HBNF_Lookahead;

package body HBNF_Zig is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;
   use HBNF_Compilable;

   subtype U is Unbounded_String;

   LF : constant Character := ASCII.LF;

   --  A whole-file template whose one hole is the root rule's type.  The
   --  `@ROOT_TYPE@` substitution these two templates used is now
   --  `{{&root_type}}` like every other hole (RFCPLAN.md step 3b).
   function Render_Root (Name, Root_T : String) return String is
      V : Mustache.Context := Mustache.View;
   begin
      Mustache.Put (V, "root_type", Root_T);
      return Mustache.Render_File (Name, V);
   end Render_Root;

   package String_Vectors is new Ada.Containers.Vectors (Positive, U);
   package Natural_Vectors is new Ada.Containers.Vectors (Positive, Natural);

   --  The Zig type for a built-in core rule, or "" if not a core scalar.
   function Scalar_Zig_Type (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "[]const u8";
      elsif Name = "int" then
         return "i64";
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

   --  A labeled block nothing breaks out of is an error in Zig ("unused block
   --  label"): a branch whose every element cannot fail, as a token that can
   --  match the empty text cannot, has no break.  Drop the label then.
   --  Header is the text that opened the block, at Start in Buf; Brk is the
   --  statement that would leave it.
   procedure Drop_Unused_Label
     (Buf : in out Unbounded_String; Start : Natural;
      Header, Brk, Replacement : String)
   is
      Seg  : constant String :=
        Slice (Buf, Start + 1 + Header'Length, Length (Buf));
      Used : Boolean := False;
   begin
      for I in Seg'Range loop
         if I + Brk'Length - 1 <= Seg'Last
           and then Seg (I .. I + Brk'Length - 1) = Brk
           and then (I + Brk'Length > Seg'Last
                     or else Seg (I + Brk'Length) not in
                       'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_')
         then
            Used := True;
            exit;
         end if;
      end loop;
      if not Used then
         Replace_Slice (Buf, Start + 1, Start + Header'Length, Replacement);
      end if;
   end Drop_Unused_Label;

   --  A snake_case identifier from a schema name ('-' -> '_', upper -> lower).
   function Zig_Snake (S : String) return String is
      Buf : U;
   begin
      for C of HBNF_Grammar.Prefixed (S) loop
         if C = '-' then
            Append (Buf, '_');
         elsif C in 'A' .. 'Z' then
            Append (Buf, Character'Val (Character'Pos (C) + 32));
         else
            Append (Buf, C);
         end if;
      end loop;
      return To_String (Buf);
   end Zig_Snake;

   --  A PascalCase type name from a schema name ('-' / '_' split a word).
   function Zig_Type (S : String) return String is
      Buf : U;
      Up  : Boolean := True;
   begin
      for C of HBNF_Grammar.Prefixed (S) loop
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

   --  Escape a literal for a Zig string literal.  Zig's `\x` takes exactly
   --  two hex digits, so `\xNN` is safe for any non-printable byte; the named
   --  controls use their short forms.
   function Zig_Escape (S : String) return String is
      Buf : U;
      Hex : constant String := "0123456789abcdef";
   begin
      for C of S loop
         case C is
            when '\' => Append (Buf, "\\");
            when '"' => Append (Buf, "\""");
            when others =>
               case Character'Pos (C) is
                  when 9  => Append (Buf, "\t");
                  when 10 => Append (Buf, "\n");
                  when 13 => Append (Buf, "\r");
                  when 32 .. 126 => Append (Buf, C);
                  when others =>
                     declare
                        V : constant Natural := Character'Pos (C);
                     begin
                        Append (Buf, "\x");
                        Append (Buf, Hex (V / 16 + 1));
                        Append (Buf, Hex (V mod 16 + 1));
                     end;
               end case;
         end case;
      end loop;
      return To_String (Buf);
   end Zig_Escape;

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
   --  through Zig_Field and then any non-alphanumeric folded to '_', so
   --  "tlsv1.0" -> "tlsv1_0".  A name that is empty, all '_', or begins with
   --  a digit (pure punctuation like "*" or "!=") becomes `op<pos>`; and
   --  collisions are deduped with _2, _3, ...
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

      function Used (S : String) return Boolean is
      begin
         for X of Names loop
            if To_String (X) = S then
               return True;
            end if;
         end loop;
         return False;
      end Used;
   begin
      for I in 1 .. Natural (Lits.Length) loop
         declare
            Base : constant String := Fold (Zig_Field (To_String (Lits (I))));
            N    : U;
         begin
            if Base = "" or else (for all C of Base => C = '_')
              or else Base (Base'First) in '0' .. '9'
            then
               N := To_Unbounded_String ("op" & Img (I));
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

   --  Append Text as `//` line comments, prefixing every line (a schema's
   --  leading comment block spans multiple lines joined by LF).
   procedure Append_Comment (B : in out U; Text : String) is
      Line_Start : Natural := Text'First;
   begin
      if Text'Length = 0 then
         return;
      end if;
      for K in Text'Range loop
         if Text (K) = ASCII.LF then
            Append (B, "// " & Text (Line_Start .. K - 1) & LF);
            Line_Start := K + 1;
         end if;
      end loop;
      Append (B, "// " & Text (Line_Start .. Text'Last) & LF);
   end Append_Comment;

   --  =====================================================================
   --  Rule classification, and the by-value graph the one cycle detector in
   --  HBNF_Compilable runs on.  At package level, parameterised by Rules,
   --  because Emit (the types and walkers) and Emit_Parser (the commit
   --  point) are separate functions with separate local state and both need
   --  to know which member is the back edge.

   function Find (Rules : Rule_Vectors.Vector; Name : String) return Natural is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if To_String (Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   Writer_On    : Boolean := False;   --  --writer: write_<root>
   Hosted_Types : U;
   Hosted_Walks : U;                --  the bit rules with a walk_<rule>, space-separated
   Hosted_Acts  : Boolean := False; --  some %action to run after the text is read
   Hosted_Code  : U;
   Is_Hosted    : Boolean := False;

   procedure Set_Writer (On : Boolean) is
   begin
      Writer_On := On;
   end Set_Writer;

   procedure Set_Hosted (Types, Code : String; Walks : String := "") is
   begin
      Hosted_Walks := To_Unbounded_String (" " & Walks & " ");
      Hosted_Acts  := Walks /= "";
      Hosted_Types := To_Unbounded_String (Types);
      Hosted_Code  := To_Unbounded_String (Code);
      Is_Hosted := True;
   end Set_Hosted;

   function Scan_Fn (Rule : String) return String is
     ("scan_" & Zig_Snake (Rule));

   function Parse_Fn (Rule : String) return String is
     ("parse_" & Zig_Snake (Rule));

   --  The Zig type a rule reference denotes: a core scalar inlines; any
   --  other reference resolves to the referenced rule's own type name.
   function Zig_Type_Of (Rules : Rule_Vectors.Vector; Ref : String)
     return String is
      S : constant String := Scalar_Zig_Type (Ref);
   begin
      if S /= "" then
         return S;
      end if;
      if Find (Rules, Ref) = 0 and then not HBNF_Grammar.Is_Wire_Rule (Ref) then
         raise Parse_Error with "undefined rule: " & HBNF_Grammar.Spelled (Ref)
           & (if HBNF_Grammar.Spelled (Ref) /= Ref then ", which no `::=` defines" else "");
      end if;
      return Zig_Type (Ref);
   end Zig_Type_Of;

   --  The underlying scalar Zig type a rule name resolves to, chasing
   --  single-name aliases and jets to their target (so `str | word` and
   --  `ipv4 | ipv6` both collapse to `[]const u8`).  "" if not scalar.
   function Resolve_Type
     (Rules : Rule_Vectors.Vector; N : String; Depth : Natural := 0)
     return String is
      C : constant String := Scalar_Zig_Type (N);
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
               return "[]const u8";
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
   --  the same scalar Zig type, that type (a scalar union); else "".
   function Scalar_Union_Type
     (Rules : Rule_Vectors.Vector; Els : Element_Vectors.Vector) return String is
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
                 Inline_Type => To_Unbounded_String ("[]const u8"));
      end if;
      if R.Jet_Code /= Null_Unbounded_String then
         return (Kind        => Scalar,
                 Inline_Type => To_Unbounded_String ("[]const u8"));
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
                           (Zig_Type_Of (Rules, To_String (E.Name))));
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

   --  Structs and lists both name a type.  Zig's lazy analysis lets a
   --  declaration refer to a type declared later, so only a genuine
   --  by-value embedding imposes an ordering constraint (and, transitively,
   --  the infinite-type cycle the sort below guards against).
   function Is_Type (Info : Rule_Info) return Boolean is
     (Info.Kind = Struct or else Info.Kind = List);

   --  A struct member embedded by value; a list is a `[]T` slice (and a
   --  reference to a list is its slice alias), so neither embeds by value.
   function Is_By_Value (Info : Rule_Info) return Boolean is
     (Info.Kind = Struct);

   --  The by-value edges of the tree-type graph, for the one cycle detector
   --  in HBNF_Compilable; the edges it picks to make indirect come back.
   function Back_Edges_Zig (Rules : Rule_Vectors.Vector)
     return HBNF_Compilable.Edge_Vectors.Vector
   is
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      --  The rule a reference holds by value: chase a scalar alias
      --  (`src = host`) through to the struct its field really holds, so the
      --  containing struct is laid out after that struct and so the cycle
      --  detector sees the edge the field really makes.  A direct struct
      --  member is already there.  0 when it holds nothing by value.
      function Resolve (N : U) return Natural is
         J    : Natural := Find (Rules, To_String (N));
         Hops : Natural := 0;
      begin
         while J > 0 and then Hops < 20 and then Infos (J).Kind = Scalar loop
            Hops := Hops + 1;
            declare
               P : constant Element_Vectors.Vector := Rules (J).Pattern;
            begin
               if Natural (P.Length) = 1 and then P (1).Kind = Name
                 and then P (1).Min = 1 and then P (1).Max = 1
               then
                  J := Find (Rules, To_String (P (1).Name));
               else
                  J := 0;
               end if;
            end;
         end loop;
         if J > 0 and then Hops < 20 and then Is_By_Value (Infos (J)) then
            return J;
         end if;
         return 0;
      end Resolve;

      --  The by-value edges of the tree-type graph, for the one cycle
      --  detector in HBNF_Compilable.  Only a struct's non-list member and a
      --  scalar's alias are edges: a list field holds a `[]T` slice, which is
      --  indirect, so it imposes no order.
      function By_Value_Edges return HBNF_Compilable.Edge_Vectors.Vector is
         E : HBNF_Compilable.Edge_Vectors.Vector;
      begin
         for I in 1 .. N loop
            declare
               Info : constant Rule_Info := Infos (I);
            begin
               case Info.Kind is
                  when Struct =>
                     for M of Info.Members loop
                        if not M.Is_List then
                           declare
                              J : constant Natural := Resolve (M.Name);
                           begin
                              if J > 0 then
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
                     if Info.Inline_Type /= Null_Unbounded_String then
                        declare
                           P : constant Element_Vectors.Vector :=
                             Rules (I).Pattern;
                           J : constant Natural := Resolve (Rules (I).Name);
                        begin
                           if J > 0
                             and then Natural (P.Length) = 1
                             and then P (1).Kind = Name
                           then
                              E.Append
                                (HBNF_Compilable.By_Value_Edge'
                                   (Owner => I, Member => Null_Unbounded_String,
                                    Target => J));
                           end if;
                        end;
                     end if;
                  when others =>
                     null;
               end case;
            end;
         end loop;
         return E;
      end By_Value_Edges;

   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;
      return HBNF_Compilable.Back_Edges (N, By_Value_Edges);
   end Back_Edges_Zig;

   --  The rule a back edge points at, or 0 when (Owner, Member) is not one.
   --  A member name is unique within its struct, so the pair names the edge.
   function Back_Target (Backs : HBNF_Compilable.Edge_Vectors.Vector;
                         Owner : Natural; Member : String) return Natural is
   begin
      for E of Backs loop
         if E.Owner = Owner and then To_String (E.Member) = Member then
            return E.Target;
         end if;
      end loop;
      return 0;
   end Back_Target;

   --  True when Owner has a field that breaks a cycle, so that its struct
   --  holds something to release and a failed branch must release it.
   function Has_Back (Backs : HBNF_Compilable.Edge_Vectors.Vector;
                      Owner : Natural) return Boolean is
     (for some E of Backs => E.Owner = Owner);

   --  With --writer, a rule with alternatives records the one it took
   --  (`_alt`, from 1): a struct whose pattern has a top-level alternation, and
   --  a list entry that is a group with one.  The writer needs it; the C tree
   --  has the same.
   function Struct_Alt (R : Rule; Info : Rule_Info) return Boolean is
     (Writer_On and then Info.Kind = Struct
      and then Natural (R.Pattern.Length) > 1
      and then (for some X of R.Pattern => X.Kind = Alt));

   function Entry_Alt (R : Rule; Info : Rule_Info) return Boolean is
     (Writer_On and then Info.Kind = List
      and then not Info.Elem_Members.Is_Empty
      and then R.Left_Bases = 0
      and then Natural (R.Pattern.Length) = 1
      and then R.Pattern (1).Kind = Group
      and then (for some X of R.Pattern (1).Items => X.Kind = Alt));

   function Emit (Rules : Rule_Vectors.Vector) return String is

      N : constant Natural := Natural (Rules.Length);

      Infos : Info_Vectors.Vector;

      --  The fields that break a cycle, emitted `?*T`.
      Backs : constant HBNF_Compilable.Edge_Vectors.Vector :=
        Back_Edges_Zig (Rules);

      --  The rule indices this rule must be emitted after: only the structs it
      --  embeds by value.  List members and list references are slices, which
      --  break the cycle.
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

         procedure Add_Ref (Name : U) is
            J : constant Natural := Find (Rules, To_String (Name));
         begin
            if J > 0 and then Is_By_Value (Infos (J)) then
               Add (J);
            end if;
         end Add_Ref;
      begin
         declare
            Info : constant Rule_Info := Infos (Idx);
         begin
            case Info.Kind is
               when Struct =>
                  for M of Info.Members loop
                     if not M.Is_List
                       and then Back_Target (Backs, Idx, To_String (M.Name)) = 0
                     then
                        Add_Ref (M.Name);
                     end if;
                  end loop;
               when List =>
                  null;  --  a slice; its element type is not embedded by value
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
            Append_Comment (Buf, To_String (R.Leading_Comment));
         end if;

         case Info.Kind is
            when Scalar =>
               declare
                  V : Mustache.Context := Mustache.View;
               begin
                  Mustache.Put (V, "name", Base);
                  Mustache.Put (V, "type", To_String (Info.Inline_Type));
                  Append (Buf, Mustache.Render_File ("zig_scalar", V));
               end;
               Append (Buf, LF);
            when Enum =>
               declare
                  Names : constant String_Vectors.Vector :=
                    Enum_Names (Info.Literals);
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
                       (Row, "item",
                        Mustache.New_Scalar (To_String (Names (I))));
                     Mustache.Insert
                       (Row, "init",
                        Mustache.New_Scalar (Enum_Init (Vals, Ord, J)));
                     Mustache.Append (Items, Row);
                     end;
                  end loop;
                  --  A struct is started from zeroes, which needs an enum to
                  --  have a tag for 0.  One that starts higher (`"icmp"@1`) is
                  --  open, `_`: 0 is then "none of them", and nothing in the
                  --  parser switches on an enum.
                  if Count > 0 and then Vals (Ord (1)) > 0 then
                     Row := Mustache.New_Map;
                     Mustache.Insert (Row, "item", Mustache.New_Scalar ("_"));
                     Mustache.Insert (Row, "init", Mustache.New_Scalar (""));
                     Mustache.Append (Items, Row);
                  end if;
                  --  Zig gives an enum numbers only with a type for them.
                  Mustache.Put
                    (V, "backing",
                     (if not Enum_Sparse (Vals, Ord)
                         and then not (Count > 0 and then Vals (Ord (1)) > 0)
                      then ""
                      elsif Enum_Max (Vals) < 256 then "(u8)"
                      elsif Enum_Max (Vals) < 65536 then "(u16)"
                      else "(u32)"));
                  Mustache.Put (V, "name", Base);
                  Mustache.Put (V, "items", Items);
                  Append (Buf, Mustache.Render_File ("zig_enum", V));
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
                        Mustache.New_Scalar (Zig_Field (To_String (M.Name))));
                     Mustache.Insert
                       (Row, "type",
                        Mustache.New_Scalar
                          (if M.Is_List
                           then "[]" & Zig_Type_Of (Rules, To_String (M.Name))
                           elsif Back_Target (Backs, Idx, To_String (M.Name)) > 0
                           then "?*" & Zig_Type_Of (Rules, To_String (M.Name))
                           else Zig_Type_Of (Rules, To_String (M.Name))));
                     Mustache.Append (Items, Row);
                  end loop;
                  if Struct_Alt (R, Info) then
                     Row := Mustache.New_Map;
                     Mustache.Insert (Row, "field", Mustache.New_Scalar ("_alt"));
                     Mustache.Insert (Row, "type", Mustache.New_Scalar ("u16"));
                     Mustache.Append (Items, Row);
                  end if;
                  Mustache.Put (V, "name", Base);
                  Mustache.Put (V, "items", Items);
                  Append (Buf, Mustache.Render_File ("zig_struct", V));
               end;
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
            Append_Comment (Buf, To_String (R.Leading_Comment));
         end if;

         if Info.Elem_Members.Is_Empty then
            declare
               V : Mustache.Context := Mustache.View;
            begin
               Mustache.Put (V, "name", Base);
               if Info.Elem_Name = Null_Unbounded_String then
                  Append (Buf, Mustache.Render_File ("zig_list_bytes", V));
               else
                  Mustache.Put
                    (V, "type", Zig_Type_Of (Rules, To_String (Info.Elem_Name)));
                  Append (Buf, Mustache.Render_File ("zig_list_simple", V));
               end if;
            end;
         else
            declare
               Items : constant Mustache.Value_Access := Mustache.New_List;
               Row   : Mustache.Value_Access;
               V     : Mustache.Context := Mustache.View;
            begin
               for M of Info.Elem_Members loop
                  Row := Mustache.New_Map;
                  Mustache.Insert
                    (Row, "field",
                     Mustache.New_Scalar (Zig_Field (To_String (M.Name))));
                  Mustache.Insert
                    (Row, "type",
                     Mustache.New_Scalar (Zig_Type_Of (Rules, To_String (M.Name))));
                  Mustache.Append (Items, Row);
               end loop;
               if Entry_Alt (R, Info) then
                  Row := Mustache.New_Map;
                  Mustache.Insert (Row, "field", Mustache.New_Scalar ("_alt"));
                  Mustache.Insert (Row, "type", Mustache.New_Scalar ("u16"));
                  Mustache.Append (Items, Row);
               end if;
               Mustache.Put (V, "name", Base);
               Mustache.Put (V, "items", Items);
               Append (Buf, Mustache.Render_File ("zig_list_entry", V));
            end;
         end if;
         Append (Buf, LF);

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " // " & To_String (R.Trailing_Comment));
            Append (Buf, LF);
         end if;
         return To_String (Buf);
      end Emit_List;

      --  Emit AST walk (visit) and transform (fold) helpers: visit_<rule>/
      --  fold_<rule> free functions that take an `anytype` visitor/folder and
      --  do the structural recursion.  visit_ is pre-order and read-only
      --  (`*const`); fold_ is bottom-up and mutates the node in place (`*`).
      --  A scalar or enum member (and a []scalar) is a leaf.
      procedure Emit_Walk (Buf : in out U) is

         function Ref_Kind (Name : String) return Class_Kind is
            J : constant Natural := Find (Rules, Name);
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         --  The visit/fold function base for the ELEMENT of a list rule Name,
         --  or "" when the element is a scalar/enum leaf.
         function Elem_Fn (Name : String) return String is
            J    : constant Natural := Find (Rules, Name);
            Info : constant Rule_Info := Infos (J);
         begin
            if J = 0 then
               return "";
            end if;
            if not Info.Elem_Members.Is_Empty then
               return Zig_Snake (Name) & "_entry";
            elsif Info.Elem_Name /= Null_Unbounded_String
              and then Ref_Kind (To_String (Info.Elem_Name)) = Struct
            then
               return Zig_Snake (To_String (Info.Elem_Name));
            else
               return "";
            end if;
         end Elem_Fn;

         --  Back is the rule a back edge points at, or 0.  The box holds that
         --  rule whatever the member names, so it is walked through `Back`
         --  rather than through the member's own kind (which, for a member
         --  naming a scalar alias, is not Struct and would not be walked).
         procedure Visit_Field
           (Name : String; Back : Natural; Buf : in out U; Ind : String) is
            F : constant String := Zig_Field (Name);
         begin
            if Back > 0 then
               Append (Buf, Ind & "if (n." & F & ") |c| visit_"
                 & Zig_Snake (To_String (Rules (Back).Name)) & "(c, v);");
               Append (Buf, LF);
               return;
            end if;
            case Ref_Kind (Name) is
               when Struct =>
                  Append (Buf, Ind & "visit_" & Zig_Snake (Name)
                    & "(&n." & F & ", v);");
                  Append (Buf, LF);
               when List =>
                  declare
                     E : constant String := Elem_Fn (Name);
                  begin
                     if E /= "" then
                        Append (Buf, Ind & "for (n." & F & ") |*e| visit_" & E
                          & "(e, v);");
                        Append (Buf, LF);
                     end if;
                  end;
               when others =>
                  null;
            end case;
         end Visit_Field;

         procedure Fold_Field
           (Name : String; Back : Natural; Buf : in out U; Ind : String) is
            F : constant String := Zig_Field (Name);
         begin
            if Back > 0 then
               Append (Buf, Ind & "if (n." & F & ") |c| fold_"
                 & Zig_Snake (To_String (Rules (Back).Name)) & "(c, f);");
               Append (Buf, LF);
               return;
            end if;
            case Ref_Kind (Name) is
               when Struct =>
                  Append (Buf, Ind & "fold_" & Zig_Snake (Name)
                    & "(&n." & F & ", f);");
                  Append (Buf, LF);
               when List =>
                  declare
                     E : constant String := Elem_Fn (Name);
                  begin
                     if E /= "" then
                        Append (Buf, Ind & "for (n." & F & ") |*e| fold_" & E
                          & "(e, f);");
                        Append (Buf, LF);
                     end if;
                  end;
               when others =>
                  null;
            end case;
         end Fold_Field;

         procedure Emit_Node (Owner : Natural; Type_Name, Fn : String;
                              Members : Member_Vectors.Vector;
                              Buf : in out U) is
         begin
            Append (Buf, "pub fn visit_" & Fn & "(n: *const " & Type_Name
              & ", v: anytype) void {");
            Append (Buf, LF);
            Append (Buf, "    v.visit_" & Fn & "(n);");
            Append (Buf, LF);
            for M of Members loop
               Visit_Field
                 (To_String (M.Name),
                  Back_Target (Backs, Owner, To_String (M.Name)), Buf, "    ");
            end loop;
            Append (Buf, "}");
            Append (Buf, LF);
            Append (Buf, LF);

            Append (Buf, "pub fn fold_" & Fn & "(n: *" & Type_Name
              & ", f: anytype) void {");
            Append (Buf, LF);
            for M of Members loop
               Fold_Field
                 (To_String (M.Name),
                  Back_Target (Backs, Owner, To_String (M.Name)), Buf, "    ");
            end loop;
            Append (Buf, "    f.fold_" & Fn & "(n);");
            Append (Buf, LF);
            Append (Buf, "}");
            Append (Buf, LF);
         end Emit_Node;

         function Is_Node (Idx : Natural) return Boolean is
            Info : constant Rule_Info := Infos (Idx);
         begin
            return Info.Kind = Struct
              or else (Info.Kind = List and then not Info.Elem_Members.Is_Empty);
         end Is_Node;

         function Node_Type (Idx : Natural) return String is
            Info : constant Rule_Info := Infos (Idx);
            Base : constant String := Zig_Type (To_String (Rules (Idx).Name));
         begin
            if Info.Kind = Struct then
               return Base;
            else
               return Base & "Entry";
            end if;
         end Node_Type;

         function Node_Fn (Idx : Natural) return String is
            Info : constant Rule_Info := Infos (Idx);
            Base : constant String := Zig_Snake (To_String (Rules (Idx).Name));
         begin
            if Info.Kind = Struct then
               return Base;
            else
               return Base & "_entry";
            end if;
         end Node_Fn;

         function Node_Members (Idx : Natural) return Member_Vectors.Vector is
            Info : constant Rule_Info := Infos (Idx);
         begin
            if Info.Kind = Struct then
               return Info.Members;
            else
               return Info.Elem_Members;
            end if;
         end Node_Members;

         --  The composite rule a reference ends at, chasing scalar aliases
         --  (`expr = prim`): a struct or a list, the two that own something
         --  to release.  0 for a core scalar, an enum or an undefined name.
         function Leaf (Ref : String) return Natural is
            J    : Natural := Find (Rules, Ref);
            Hops : Natural := 0;
         begin
            while J > 0 and then Hops < 20 and then Infos (J).Kind = Scalar
            loop
               Hops := Hops + 1;
               declare
                  P : constant Element_Vectors.Vector := Rules (J).Pattern;
               begin
                  if Natural (P.Length) = 1 and then P (1).Kind = Name
                    and then P (1).Min = 1 and then P (1).Max = 1
                  then
                     J := Find (Rules, To_String (P (1).Name));
                  else
                     J := 0;
                  end if;
               end;
            end loop;
            if J > 0 and then Hops < 20
              and then (Infos (J).Kind = Struct or else Infos (J).Kind = List)
            then
               return J;
            end if;
            return 0;
         end Leaf;

         --  deinit_<rule>(n, alloc) releases what the parser allocated under
         --  a node: the box a back edge made, the slice a list returned, and
         --  whatever those hold, and never the node itself.  It is for a tree
         --  parsed with the same allocator.  Strings are slices of the token
         --  text and are not the tree's to free.  Rep is whether a repeated
         --  member is a slice of its own (a struct's) or not (an entry's).
         procedure Deinit_Member
           (Owner : Natural; M : Member; Rep : Boolean; Any : in out Boolean;
            Buf : in out U) is
            Name : constant String := To_String (M.Name);
            F    : constant String := Zig_Field (Name);
            Back : constant Natural := Back_Target (Backs, Owner, Name);
            L    : constant Natural := Leaf (Name);
         begin
            if Back > 0 then
               Append (Buf, "    if (n." & F & ") |c| { deinit_"
                 & Zig_Snake (To_String (Rules (Back).Name))
                 & "(c, alloc); alloc.destroy(c); }");
               Append (Buf, LF);
               Any := True;
            elsif Rep and then M.Is_List then
               if L > 0 then
                  Append (Buf, "    for (n." & F & ") |*e| deinit_"
                    & Zig_Snake (To_String (Rules (L).Name)) & "(e, alloc);");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    alloc.free(n." & F & ");");
               Append (Buf, LF);
               Any := True;
            elsif L > 0 then
               Append (Buf, "    deinit_" & Zig_Snake (To_String (Rules (L).Name))
                 & "(&n." & F & ", alloc);");
               Append (Buf, LF);
               Any := True;
            end if;
         end Deinit_Member;

         procedure Deinit_Node
           (Owner : Natural; Type_Name, Fn : String; Rep : Boolean;
            Members : Member_Vectors.Vector; Buf : in out U) is
            Body_Buf : U;
            Any      : Boolean := False;
         begin
            for M of Members loop
               Deinit_Member (Owner, M, Rep, Any, Body_Buf);
            end loop;
            Append (Buf, "pub fn deinit_" & Fn & "(n: *" & Type_Name
              & ", alloc: std.mem.Allocator) void {");
            Append (Buf, LF);
            if Any then
               Append (Buf, To_String (Body_Buf));
            else
               Append (Buf, "    _ = n;");
               Append (Buf, LF);
               Append (Buf, "    _ = alloc;");
               Append (Buf, LF);
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
            Append (Buf, LF);
         end Deinit_Node;

         --  A list rule's own release: each composite element, then the slice.
         procedure Deinit_List (Idx : Natural; Buf : in out U) is
            Info : constant Rule_Info := Infos (Idx);
            Base : constant String := Zig_Type (To_String (Rules (Idx).Name));
            Fn   : constant String := Zig_Snake (To_String (Rules (Idx).Name));
            E    : constant Natural :=
              (if Info.Elem_Name /= Null_Unbounded_String
               then Leaf (To_String (Info.Elem_Name)) else 0);
         begin
            Append (Buf, "pub fn deinit_" & Fn & "(n: *" & Base
              & ", alloc: std.mem.Allocator) void {");
            Append (Buf, LF);
            if not Info.Elem_Members.Is_Empty then
               Append (Buf, "    for (n.*) |*e| deinit_" & Fn & "_entry(e, alloc);");
               Append (Buf, LF);
            elsif E > 0 then
               Append (Buf, "    for (n.*) |*e| deinit_"
                 & Zig_Snake (To_String (Rules (E).Name)) & "(e, alloc);");
               Append (Buf, LF);
            end if;
            Append (Buf, "    alloc.free(n.*);");
            Append (Buf, LF);
            Append (Buf, "}");
            Append (Buf, LF);
            Append (Buf, LF);
         end Deinit_List;

         procedure Emit_Deinit (Buf : in out U) is
         begin
            Append (Buf, "// ---- release (deinit) ----");
            Append (Buf, LF);
            for I in 1 .. N loop
               case Infos (I).Kind is
                  when Struct =>
                     Deinit_Node
                       (I, Node_Type (I), Node_Fn (I), True,
                        Node_Members (I), Buf);
                  when List =>
                     if not Infos (I).Elem_Members.Is_Empty then
                        --  An entry's members are typed bare, not as slices.
                        Deinit_Node
                          (I, Node_Type (I), Node_Fn (I), False,
                           Node_Members (I), Buf);
                     end if;
                     Deinit_List (I, Buf);
                  when others =>
                     null;
               end case;
            end loop;
         end Emit_Deinit;

      begin
         Append (Buf, "// ---- AST traversal (visit) and transform (fold) ----");
         Append (Buf, LF);
         for I in 1 .. N loop
            if Is_Node (I) then
               Emit_Node
                 (I, Node_Type (I), Node_Fn (I), Node_Members (I), Buf);
               Append (Buf, LF);
            end if;
         end loop;

         Emit_Deinit (Buf);

         --  The %actions of the bit rules a text rule holds, run after the whole
         --  text has been read: bnf_act_<rule> walks a node, children first, and
         --  calls the walk_<bit rule> of each bit rule it holds.
         if Is_Hosted and then Hosted_Acts then
            declare
               function Walked (Name : String) return Boolean is
                 (Find (Rules, Name) = 0
                  and then Index (Hosted_Walks, " " & Name & " ") > 0);

               procedure Act_Stmt
                 (Name : String; Is_List : Boolean; Back : Natural;
                  Expr : String; Buf : in out U; Ind : String)
               is
                  L : constant Natural := Leaf (Name);

                  procedure Elems (E : String; Idx : Natural) is
                     Info : constant Rule_Info := Infos (Idx);
                  begin
                     if not Info.Elem_Members.Is_Empty then
                        Append (Buf, Ind & "for (" & E & ") |*e| try bnf_act_"
                          & Zig_Snake (To_String (Rules (Idx).Name))
                          & "_entry(e, h);" & LF);
                     elsif Info.Elem_Name /= Null_Unbounded_String then
                        declare
                           EN : constant String := To_String (Info.Elem_Name);
                           EL : constant Natural := Leaf (EN);
                        begin
                           if Walked (EN) then
                              Append (Buf, Ind & "for (" & E & ") |*e| try walk_"
                                & EN & "(e, h);" & LF);
                           elsif EL > 0 and then Infos (EL).Kind = Struct then
                              Append (Buf, Ind & "for (" & E & ") |*e| try bnf_act_"
                                & Zig_Snake (To_String (Rules (EL).Name))
                                & "(e, h);" & LF);
                           end if;
                        end;
                     end if;
                  end Elems;
               begin
                  if Back > 0 then
                     Append (Buf, Ind & "if (" & Expr & ") |c| try bnf_act_"
                       & Zig_Snake (To_String (Rules (Back).Name)) & "(c, h);" & LF);
                  elsif Walked (Name) then
                     if Is_List then
                        Append (Buf, Ind & "for (" & Expr & ") |*e| try walk_"
                          & Name & "(e, h);" & LF);
                     else
                        Append (Buf, Ind & "try walk_" & Name & "(&" & Expr
                          & ", h);" & LF);
                     end if;
                  elsif L > 0 and then Infos (L).Kind = Struct then
                     if Is_List then
                        Append (Buf, Ind & "for (" & Expr & ") |*e| try bnf_act_"
                          & Zig_Snake (To_String (Rules (L).Name)) & "(e, h);" & LF);
                     else
                        Append (Buf, Ind & "try bnf_act_"
                          & Zig_Snake (To_String (Rules (L).Name)) & "(&" & Expr
                          & ", h);" & LF);
                     end if;
                  elsif L > 0 and then Infos (L).Kind = List then
                     Elems (Expr, L);
                  end if;
               end Act_Stmt;

               procedure Act_Node
                 (Owner : Natural; Type_Name, Fn : String; Rep : Boolean;
                  Members : Member_Vectors.Vector; Buf : in out U) is
               begin
                  Append (Buf, "fn bnf_act_" & Fn & "(n: *const " & Type_Name
                    & ", h: *Hooks) error{HbnfFail}!void {" & LF);
                  Append (Buf, "    _ = &n;" & LF & "    _ = &h;" & LF);
                  for M of Members loop
                     Act_Stmt (To_String (M.Name), Rep and then M.Is_List,
                               Back_Target (Backs, Owner, To_String (M.Name)),
                               "n." & Zig_Field (To_String (M.Name)), Buf, "    ");
                  end loop;
                  Append (Buf, "}" & LF & LF);
               end Act_Node;
            begin
               Append (Buf, "// ---- the %actions of the bit rules, after the read ----" & LF);
               for I in 1 .. N loop
                  case Infos (I).Kind is
                     when Struct =>
                        Act_Node (I, Node_Type (I), Node_Fn (I), True,
                                  Node_Members (I), Buf);
                     when List =>
                        if not Infos (I).Elem_Members.Is_Empty then
                           Act_Node (I, Node_Type (I), Node_Fn (I), False,
                                     Node_Members (I), Buf);
                        end if;
                     when others =>
                        null;
                  end case;
               end loop;
               Append (Buf, "fn bnf_act_root(n: anytype, h: *Hooks) error{HbnfFail}!void {" & LF);
               Append (Buf, "    _ = &n;" & LF & "    _ = &h;" & LF);
               Act_Stmt (To_String (Rules (1).Name), False, 0, "n.*", Buf, "    ");
               Append (Buf, "}" & LF & LF);
            end;
         end if;
      end Emit_Walk;

      --  write_<root>: the tree as text, when the grammar was generated with
      --  --writer.  Canonical, not lossless: literals come from the grammar,
      --  tokens from their text, and a blank goes between two items only where
      --  they would run together.  A bit rule in the text is written by its own
      --  emit_bits_<rule> (which runs its %emit), its octets going in as they
      --  are.  What it cannot write it says at run time, at the node, so a
      --  shape that is not built yet is never written as something close:
      --  alternatives are not recorded in this tree, so a rule that has them
      --  is not written.
      procedure Emit_Writer (Buf : in out U) is

         function Img (X : Natural) return String is
            S : constant String := Natural'Image (X);
         begin
            return S (S'First + 1 .. S'Last);
         end Img;

         procedure P (Ind : Natural; S : String) is
         begin
            Append (Buf, [1 .. 4 * Ind => ' ']);
            Append (Buf, S);
            Append (Buf, LF);
         end P;

         function Bad (Why : String) return String is
           ("w.badw(""" & Zig_Escape (Why) & """);");

         --  The scanner that reads a token of this rule, "null" if none is
         --  known (the fit of two items is then not checked).
         --  The built-in scanners exist for a core rule the grammar leaves
         --  to them (or, for `word`, does not name at all).
         function Core_Ok (Core : String) return Boolean is
            J : constant Natural := Find (Rules, Core);
         begin
            return (J > 0 and then Rules (J).Jet_Code /= Null_Unbounded_String)
              or else (Core = "word" and then J = 0);
         end Core_Ok;

         function Scan_Of (Nm : String; Depth : Natural := 0) return String is
            J : constant Natural := Find (Rules, Nm);
         begin
            if Nm = "str" then
               return (if Core_Ok ("str") then "scan_str" else "null");
            elsif Nm = "int" or else (Scalar_Zig_Type (Nm) /= ""
                                      and then Nm /= "word" and then Nm /= "atom"
                                      and then Nm /= "bool" and then Nm /= "flag")
            then
               return (if Core_Ok ("int") then "scan_int" else "null");
            elsif Nm = "word" or else Nm = "atom" or else Nm = "bool"
              or else Nm = "flag"
            then
               return (if Core_Ok ("word") then "scan_word" else "null");
            end if;
            if J = 0 or else Depth > 8 then
               return "null";
            end if;
            if Is_Char_Rule (Rules, Nm) then
               return "scan_" & Zig_Snake (Nm);
            end if;
            if Rules (J).Jet_Code /= Null_Unbounded_String then
               return "jet_" & Zig_Snake (Nm);
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

         --  Write the value Expr (an lvalue) of a name.
         procedure Value (Idx : Natural; Nm, Expr, Gap : String; Back : Boolean;
                          Ind : Natural) is
            J : constant Natural := Find (Rules, Nm);
            T : constant String :=
              (if Is_Char_Rule (Rules, Nm) then "[]const u8" else Resolve_Type (Rules, Nm));
         begin
            if J = 0 and then Scalar_Zig_Type (Nm) = ""
              and then HBNF_Grammar.Is_Wire_Rule (Nm)
            then
               P (Ind, "{");
               P (Ind + 1, "var m_: []const u8 = """";");
               P (Ind + 1, "if (emit_bits_" & Nm & "(w.alloc, " & Expr
                  & ", &m_)) |eb_| {");
               P (Ind + 2, "if (eb_.nbits % 8 != 0) w.badw(""`" & Nm
                  & "` does not end on an octet, so it cannot be written as text"")");
               P (Ind + 2, "else w.put(eb_.bytes[0 .. eb_.nbits / 8]);");
               P (Ind + 1, "} else |_| w.badw(m_);");
               P (Ind, "}");
            elsif J > 0 and then Infos (J).Kind = Scalar
              and then not Rules (J).Pattern.Is_Empty
              and then (for all X of Rules (J).Pattern =>
                          X.Kind = Literal and then X.Min = 1 and then X.Max = 1)
            then
               --  a rule that is one literal: the literal is its value
               P (Ind, "w.lit(" & Gap & ", """
                  & Zig_Escape (Lit_Text (J)) & """);");
            elsif J > 0 and then Infos (J).Kind = Struct then
               P (Ind, "wr_" & Zig_Snake (Nm) & "(w, "
                  & (if Back then Expr else "&" & Expr) & ");");
            elsif J > 0 and then Infos (J).Kind = List then
               P (Ind, "wr_" & Zig_Snake (Nm) & "(w, &" & Expr & ");");
            elsif J > 0 and then Infos (J).Kind = Enum then
               P (Ind, "wr_" & Zig_Snake (Nm) & "(w, " & Expr & ");");
            elsif T = "[]const u8" then
               P (Ind, "w." & (if Has_Str (Nm) then "str" else "tok") & "("
                  & Gap & ", " & Expr & ", " & Scan_Of (Nm) & ");");
            elsif T = "bool" then
               P (Ind, "w.tok(" & Gap & ", if (" & Expr & ") ""yes"" else ""no"", " & Scan_Of ("word") & ");");
            elsif T'Length > 1 and then T (T'First) in 'i' | 'u' then
               P (Ind, "w.num(" & Gap & ", " & Expr & ", " & Scan_Of ("int") & ");");
            else
               P (Ind, Bad ("`" & Nm & "` is not a value the writer knows how to write"));
            end if;
         end Value;

         --  The elements of a sequence, through accessor Acc.
         procedure Elements
           (Idx : Natural; Els : Element_Vectors.Vector; Acc, Gap : String;
            Ind : Natural; Alt_Ok : Boolean := False) is
         begin
            if (for some X of Els => X.Kind = Alt) then
               if not Alt_Ok then
                  P (Ind, Bad ("an alternation inside a group is not recorded in a Zig tree, so it is not written yet"));
                  return;
               end if;
               --  one branch per alternative, chosen by the one the parser took
               declare
                  St : Natural := 1;
                  Br : Natural := 0;
                  Nn : constant Natural := Natural (Els.Length);
               begin
                  P (Ind, "switch (" & Acc & "_alt) {");
                  for K in 1 .. Nn + 1 loop
                     if K > Nn or else Els (K).Kind = Alt then
                        Br := Br + 1;
                        declare
                           Sub : Element_Vectors.Vector;
                        begin
                           for J in St .. K - 1 loop
                              Sub.Append (Els (J));
                           end loop;
                           P (Ind + 1, Img (Br) & " => {");
                           Elements (Idx, Sub, Acc, Gap, Ind + 2);
                           P (Ind + 1, "},");
                        end;
                        St := K + 1;
                     end if;
                  end loop;
                  P (Ind + 1, "else => { " & Bad ("no alternative was recorded (generate with --writer)") & " },");
                  P (Ind, "}");
               end;
               return;
            end if;
            for E of Els loop
               case E.Kind is
                  when Literal =>
                     P (Ind, "w.lit(" & Gap & ", """ & Zig_Escape (To_String (E.Lit)) & """);");
                  when Name =>
                     declare
                        Nm : constant String := To_String (E.Name);
                        F  : constant String := Acc & Zig_Field (Nm);
                        Bk : constant Boolean :=
                          Back_Target (Backs, Idx, Nm) > 0;
                     begin
                        if E.Min /= 1 or else E.Max /= 1 then
                           P (Ind, "for (" & F & ") |*e_| {");
                           Value (Idx, Nm, "e_.*", Gap, False, Ind + 1);
                           P (Ind, "}");
                        elsif Bk then
                           P (Ind, "if (" & F & ") |c_| {");
                           Value (Idx, Nm, "c_", Gap, True, Ind + 1);
                           P (Ind, "}");
                        else
                           Value (Idx, Nm, F, Gap, False, Ind);
                        end if;
                     end;
                  when Group =>
                     if E.Min /= 1 or else E.Max /= 1 then
                        P (Ind, Bad ("a repeated group inside a sequence"));
                     else
                        Elements (Idx, E.Items, Acc, Gap, Ind);
                     end if;
                  when others =>
                     P (Ind, Bad ("an element the writer does not know"));
               end case;
            end loop;
         end Elements;

         function Ref_Name (Idx : Natural) return String is
           (Zig_Snake (To_String (Rules (Idx).Name)));
      begin
         P (0, "// ---- write (the tree as text, canonical) ----");
         P (0, "const BnfW = struct {");
         P (1, "alloc: std.mem.Allocator,");
         P (1, "buf: std.ArrayList(u8) = .empty,");
         P (1, "last: u8 = 0,");
         P (1, "bad: ?[]const u8 = null,");
         P (1, "pscan: ?*const fn ([]const u8, usize, usize) usize = null,");
         P (1, "ptxt: std.ArrayList(u8) = .empty,");
         P (0, "");
         P (1, "fn badw(self: *BnfW, why: []const u8) void {");
         P (2, "if (self.bad == null) self.bad = why;");
         P (1, "}");
         P (0, "");
         P (1, "fn put(self: *BnfW, s: []const u8) void {");
         P (2, "self.buf.appendSlice(self.alloc, s) catch {");
         P (3, "self.badw(""out of memory"");");
         P (3, "return;");
         P (2, "};");
         P (2, "if (s.len > 0) self.last = s[s.len - 1];");
         P (1, "}");
         P (0, "");
         P (1, "fn delim(c: u8) bool {");
         P (2, "return c != 0 and std.mem.indexOfScalar(u8, ""()[],;"", c) != null;");
         P (1, "}");
         P (0, "");
         P (1, "// Would the item just written, with sep and s after it, still end where it");
         P (1, "// did when the grammar's own scanner reads it?");
         P (1, "fn fits(self: *BnfW, mid: []const u8, s: []const u8) bool {");
         P (2, "var t: std.ArrayList(u8) = .empty;");
         P (2, "defer t.deinit(self.alloc);");
         P (2, "t.appendSlice(self.alloc, self.ptxt.items) catch return false;");
         P (2, "t.appendSlice(self.alloc, mid) catch return false;");
         P (2, "t.appendSlice(self.alloc, s) catch return false;");
         P (2, "return self.pscan.?(t.items, 0, t.items.len) == self.ptxt.items.len;");
         P (1, "}");
         P (0, "");
         P (1, "// What goes between the last item and s: nothing, a blank or a newline, the");
         P (1, "// first that keeps the last item from reading on into s.");
         P (1, "fn between(self: *BnfW, gap: bool, s: []const u8) void {");
         P (2, "if (self.buf.items.len == 0 or s.len == 0) return;");
         P (2, "const a = self.last;");
         P (2, "const b = s[0];");
         P (2, "const pref: []const u8 = if (gap and a > ' ' and b > ' ' and !delim(a) and !delim(b)) "" "" else """";");
         P (2, "if (self.pscan != null and a > ' ') {");
         P (3, "const c = [_][]const u8{ pref, "" "", ""\n"" };");
         P (3, "const n: usize = if (gap) 3 else 1;");
         P (3, "for (c[0..n]) |x| {");
         P (4, "if (self.fits(x, s)) {");
         P (5, "self.put(x);");
         P (5, "return;");
         P (4, "}");
         P (3, "}");
         P (3, "self.badw(""two items cannot be written apart: the first would read on into the second"");");
         P (3, "return;");
         P (2, "}");
         P (2, "self.put(pref);");
         P (1, "}");
         P (0, "");
         P (1, "fn text(self: *BnfW, gap: bool, s: []const u8, scan: ?*const fn ([]const u8, usize, usize) usize) void {");
         P (2, "self.between(gap, s);");
         P (2, "self.put(s);");
         P (2, "self.pscan = scan;");
         P (2, "if (scan != null) {");
         P (3, "self.ptxt.clearRetainingCapacity();");
         P (3, "self.ptxt.appendSlice(self.alloc, s) catch {");
         P (4, "self.pscan = null;");
         P (3, "};");
         P (2, "}");
         P (1, "}");
         P (0, "");
         P (1, "fn lit(self: *BnfW, gap: bool, s: []const u8) void {");
         P (2, "self.text(gap, s, null);");
         P (1, "}");
         P (0, "");
         P (1, "fn tok(self: *BnfW, gap: bool, s: []const u8, scan: ?*const fn ([]const u8, usize, usize) usize) void {");
         P (2, "self.text(gap, s, scan);");
         P (1, "}");
         P (0, "");
         P (1, "fn str(self: *BnfW, gap: bool, s: []const u8, scan: ?*const fn ([]const u8, usize, usize) usize) void {");
         P (2, "var t: std.ArrayList(u8) = .empty;");
         P (2, "defer t.deinit(self.alloc);");
         P (2, "t.append(self.alloc, '""') catch return self.badw(""out of memory"");");
         P (2, "for (s) |c| {");
         P (3, "if (c == '""' or c == '\\') t.append(self.alloc, '\\') catch return self.badw(""out of memory"");");
         P (3, "t.append(self.alloc, c) catch return self.badw(""out of memory"");");
         P (2, "}");
         P (2, "t.append(self.alloc, '""') catch return self.badw(""out of memory"");");
         P (2, "self.text(gap, t.items, scan);");
         P (1, "}");
         P (0, "");
         P (1, "fn num(self: *BnfW, gap: bool, v: anytype, scan: ?*const fn ([]const u8, usize, usize) usize) void {");
         P (2, "var t: [32]u8 = undefined;");
         P (2, "const s = std.fmt.bufPrint(&t, ""{d}"", .{v}) catch return self.badw(""a number too long to write"");");
         P (2, "self.text(gap, s, scan);");
         P (1, "}");
         P (0, "};");
         P (0, "");
         for I in 1 .. N loop
            declare
               R    : constant Rule := Rules (I);
               NM   : constant String := To_String (R.Name);
               Info : constant Rule_Info := Infos (I);
               Gap  : constant String :=
                 (if R.Whitespace /= Null_Unbounded_String then "true" else "false");
               Fn   : constant String := Ref_Name (I);
            begin
               case Info.Kind is
                  when Struct =>
                     P (0, "fn wr_" & Fn & "(w: *BnfW, n: *const "
                        & Zig_Type (NM) & ") void {");
                     P (1, "_ = &n;");
                     if Natural (R.Pattern.Length) = 1
                       and then R.Pattern (1).Kind = Group
                     then
                        Elements (I, R.Pattern (1).Items, "n.", Gap, 1);
                     else
                        Elements (I, R.Pattern, "n.", Gap, 1, Struct_Alt (R, Info));
                     end if;
                     P (0, "}");
                     P (0, "");
                  when List =>
                     P (0, "fn wr_" & Fn & "(w: *BnfW, n: *const " & Zig_Type (NM)
                        & ") void {");
                     P (1, "_ = &n;");
                     if R.Left_Bases > 0 then
                        P (1, Bad ("a left-recursive list is not written yet"));
                     elsif R.Pattern (1).Kind = Group then
                        P (1, "for (n.*) |*e_| {");
                        Elements (I, R.Pattern (1).Items, "e_.", Gap, 2,
                                  Entry_Alt (R, Info));
                        P (1, "}");
                     elsif Info.Elem_Name /= Null_Unbounded_String then
                        P (1, "for (n.*) |*e_| {");
                        Value (I, To_String (Info.Elem_Name), "e_.*", Gap, False, 2);
                        P (1, "}");
                     else
                        P (1, "for (n.*) |e_| w.tok(" & Gap & ", e_, null);");
                     end if;
                     P (0, "}");
                     P (0, "");
                  when Enum =>
                     declare
                        Names : constant String_Vectors.Vector :=
                          Enum_Names (Info.Literals);
                     begin
                        P (0, "fn wr_" & Fn & "(w: *BnfW, v: " & Zig_Type (NM) & ") void {");
                        P (1, "switch (v) {");
                        for K in 1 .. Natural (Info.Literals.Length) loop
                           P (2, "." & To_String (Names (K)) & " => w.lit(" & Gap & ", """
                              & Zig_Escape (To_String (Info.Literals (K))) & """),");
                        end loop;
                        P (2, "else => {},");
                        P (1, "}");
                        P (0, "}");
                        P (0, "");
                     end;
                  when Scalar =>
                     null;
               end case;
            end;
         end loop;
         if Infos (1).Kind in Struct | List then
            declare
               R      : constant Rule := Rules (1);
               Root_T : constant String :=
                 (if Infos (1).Kind = Struct then Zig_Type (To_String (R.Name))
                  elsif Natural (R.Pattern.Length) = 1
                    and then R.Pattern (1).Kind = Name
                    and then (R.Pattern (1).Min /= 1 or else R.Pattern (1).Max /= 1)
                  then
                     "[]" & (if Scalar_Zig_Type (To_String (R.Pattern (1).Name)) /= ""
                             then Scalar_Zig_Type (To_String (R.Pattern (1).Name))
                             else Zig_Type (To_String (R.Pattern (1).Name)))
                  else Zig_Type (To_String (R.Name)));
            begin
               P (0, "/// The tree as text, or error.Write and why in msg when a node cannot be written.");
               P (0, "pub fn write_" & Ref_Name (1) & "(alloc: std.mem.Allocator, root: *const "
                  & Root_T & ", msg: *[]const u8) error{Write}![]u8 {");
               P (1, "var w = BnfW{ .alloc = alloc };");
               P (1, "wr_" & Ref_Name (1) & "(&w, root);");
               P (1, "if (w.bad) |b| {");
               P (2, "msg.* = b;");
               P (2, "return error.Write;");
               P (1, "}");
               P (1, "return w.buf.items;");
               P (0, "}");
               P (0, "");
            end;
         end if;
      end Emit_Writer;

      Emitted   : array (1 .. N) of Boolean := [others => False];
      Remaining : Natural := 0;
      Res       : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;

      Append (Res, "// generated by hbnf -- do not edit");
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
                 "a rule's value cannot contain itself: the tree types are structs "
                 & "by value, so this one would be infinitely sized.  Routing "
                 & "the recursion through a list does not help (a list node "
                 & "holds its element by value too); RFCPLAN.md step 9 adds "
                 & "the pointer that breaks the cycle";
            end if;
         end;
      end loop;

      Emit_Walk (Res);
      Append (Res, LF);
      Append (Res, Hosted_Types);
      if Writer_On then
         Emit_Writer (Res);
      end if;

      return To_String (Res);
   end Emit;

   function Emit_Parser (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      --  Can a rule match the empty text?  Then a scan of length 0 is a match,
      --  not a failure (a lifted `[ x ]` of a token is such a rule).
      Nullable : constant HBNF_Lookahead.Flags :=
        HBNF_Lookahead.Nullable_Set (Rules);

      function Can_Be_Empty (Nm : String) return Boolean is
        (Find (Rules, Nm) > 0 and then Nullable (Find (Rules, Nm)));

      N : constant Natural := Natural (Rules.Length);

      --  The fields Emit declared `?*T`: the commit point boxes what it
      --  parsed, and a rule that owns one releases it when a branch fails.
      Backs : constant HBNF_Compilable.Edge_Vectors.Vector :=
        Back_Edges_Zig (Rules);

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

      function Zig_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Zig_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         return Zig_Type (Ref);
      end Zig_Type_Of;

      --  True when a pattern (or any nested group) names a rule reference.
      function Has_Name (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Name then
               return True;
            elsif E.Kind = Group and then Has_Name (E.Items) then
               return True;
            end if;
         end loop;
         return False;
      end Has_Name;

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
      --  else the built-in scanner of the same name.
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

      --  The call that scans a core scalar at the parser's position.
      function Scan_Call (Name : String) return String is
        ("scan_" & Zig_Snake (Core_Base (Name))
         & "(p.text, p.pos, p.text.len)");

      --  The extra condition that rejects a matched bareword that is a
      --  keyword (`word` must not swallow a directive's keyword), and its
      --  positive form.  n is the matched length, the text starts at p.pos.
      function Scalar_Reject (Name : String) return String is
        (if Name = "atom" or else Name = "word"
         then " or is_keyword(p.text[p.pos .. p.pos + n])"
         else "");

      function Scalar_Guard (Name : String) return String is
        (if Name = "atom" or else Name = "word"
         then " and !is_keyword(p.text[p.pos .. p.pos + n])"
         else "");

      --  The Zig expression that converts the matched text into a core value.
      --  Pref and Cat make the `try` of str_value, which may allocate, into
      --  the `catch` of a branch that must not return.
      function Scalar_Value (Name : String; Pref, Cat : String := "")
        return String
      is
         Sl : constant String := "p.text[p.pos .. p.pos + n]";
      begin
         if Name = "str" then
            return Pref & "str_value(p.alloc, " & Sl & ")" & Cat;
         elsif Name = "bool" or else Name = "flag" then
            return "(std.mem.eql(u8, " & Sl & ", ""yes"") or "
              & "std.mem.eql(u8, " & Sl & ", ""on"") or "
              & "std.mem.eql(u8, " & Sl & ", ""true""))";
         elsif Name = "int" then
            return "std.fmt.parseInt(i64, " & Sl & ", 10) catch 0";
         elsif Name'Length >= 2 then
            declare
               P : constant Character := Name (Name'First);
               R : constant String := Name (Name'First + 1 .. Name'Last);
            begin
               if (P = 'u' or else P = 'i')
                 and then (for all C of R => C in '0' .. '9')
               then
                  return "std.fmt.parseInt(" & (if P = 'u' then "u" else "i")
                    & R & ", " & Sl & ", 10) catch 0";
               end if;
            end;
         end if;
         return Sl;
      end Scalar_Value;

      --  A letter-led literal is a keyword: matched by the `word` scanner, so
      --  `in` never matches the front of `input`.  Any other literal compares
      --  bytes.  (Same rule as the C backend's.)
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
      --  injects each as a C jet, and this backend has its own Zig for them.
      function Is_Builtin_Jet (Nm : String) return Boolean is
        (Nm = "word" or else Nm = "int" or else Nm = "str" or else Nm = "ws");

      --  The scanner a jet rule runs: the built-in one, or the stub for
      --  hand-written C.
      function Jet_Fn (Nm : String) return String is
        ((if Is_Builtin_Jet (Nm) then "scan_" else "jet_") & Zig_Snake (Nm));

      --  A group of literals only, `0*1( "log" )`: its list entries carry
      --  no field, so each is a []const u8, as the list's type says.
      function Lit_Only (V : Element_Vectors.Vector) return Boolean is
        (for all X of V =>
           X.Kind /= HBNF_Grammar.Name
           and then (X.Kind /= HBNF_Grammar.Group or else Lit_Only (X.Items)));

      function Ret_Type (Idx : Natural) return String is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if Is_Char_Rule (Rules, To_String (R.Name)) then
            return Zig_Type (To_String (R.Name));
         end if;
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            if P (1).Kind = HBNF_Grammar.Name then
               return "[]" & Zig_Type_Of (To_String (P (1).Name));
            elsif P (1).Kind = HBNF_Grammar.Group and then Lit_Only (P (1).Items)
            then
               return "[][]const u8";
            else
               return "[]" & Zig_Type (To_String (R.Name)) & "Entry";
            end if;
         end if;
         return Zig_Type (To_String (R.Name));
      end Ret_Type;

      --  The code-point match condition for one range, as a Zig boolean
      --  expression over the decoded code point `c` (a u32).  `c >= 0` is a
      --  useless comparison for an unsigned code point (Zig rejects it), so
      --  the lower bound is dropped when Lo = 0.
      function Range_Cond (Lo, Hi : Natural) return String is
      begin
         if Lo = 0 then
            return "(c <= " & Img (Hi) & ")";
         else
            return "(c >= " & Img (Lo) & " and c <= " & Img (Hi) & ")";
         end if;
      end Range_Cond;

      procedure Emit_Seq
        (Owner : Natural;
         Els : Element_Vectors.Vector; First, Last : Natural;
         Dst  : String; Buf : in out U; Fail : String := ""; Ind : String := "    ") is
         --  Whether this rule's file skips whitespace between elements
         --  (`whitespace none` says it does not).
         Skips : constant Boolean :=
           Rules (Owner).Whitespace /= Null_Unbounded_String;
         Pref : constant String := (if Fail = "" then "try " else "");
         Cat  : constant String := (if Fail = "" then "" else " catch " & Fail);
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               --  A phrase rule skips whitespace before each element.
               if Skips and then (E.Kind = Literal or else E.Kind = Name) then
                  Append (Buf, Ind & "p.skip_ws();");
                  Append (Buf, LF);
               end if;
               case E.Kind is
                  when Literal =>
                     declare
                        Lit : constant String := To_String (E.Lit);
                     begin
                        Append (Buf, Ind & Pref
                          & (if E.No_Case and then Is_Keyword_Lit (Lit)
                             then "p.expect_word_nocase"
                             elsif E.No_Case then "p.expect_lit_nocase"
                             elsif Is_Keyword_Lit (Lit) then "p.expect_word"
                             else "p.expect_lit")
                          & "(""" & Zig_Escape (Lit) & """, ""`"
                          & Zig_Escape (Lit) & "`"")" & Cat & ";");
                        Append (Buf, LF);
                     end;
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        --  A core scalar: run its scanner at the position and
                        --  convert the matched text.
                        declare
                           NM : constant String := To_String (E.Name);
                        begin
                           Append (Buf, Ind & "{ const n = " & Scan_Call (NM)
                             & "; if (n == 0" & Scalar_Reject (NM) & ") { "
                             & Pref & "p.fail(""" & Core_Desc (NM) & """)"
                             & Cat & "; } " & Dst & Zig_Field (NM) & " = "
                             & Scalar_Value (NM, Pref, Cat)
                             & "; p.pos += n; }");
                           Append (Buf, LF);
                        end;
                     elsif Is_Char_Rule (Rules, To_String (E.Name)) then
                        --  A char-rule reference runs its scanner here and
                        --  yields the matched text.
                        declare
                           NM : constant String := To_String (E.Name);
                        begin
                           Append (Buf, Ind & "{ const n = scan_" & Zig_Snake (NM)
                             & "(p.text, p.pos, p.text.len);"
                             & (if Can_Be_Empty (NM) then " "
                                else " if (n == 0) { " & Pref & "p.fail("""
                                     & NM & """)" & Cat & "; } ")
                             & Dst & Zig_Field (NM)
                             & " = p.text[p.pos .. p.pos + n]; p.pos += n; }");
                           Append (Buf, LF);
                        end;
                     elsif Back_Target (Backs, Owner, To_String (E.Name)) > 0
                     then
                        --  The back edge: parse the subtree, then box it.
                        --  Parsing first leaves nothing allocated to leak
                        --  when the subtree does not match.
                        Append (Buf, Ind & Dst
                          & Zig_Field (To_String (E.Name)) & " = "
                          & Pref & "p.box("
                          & Zig_Type_Of (To_String (E.Name)) & ", "
                          & Pref & "parse_" & Zig_Snake (To_String (E.Name))
                          & "(p)" & Cat & ")" & Cat & ";");
                        Append (Buf, LF);
                     else
                        Append (Buf, Ind & Dst
                          & Zig_Field (To_String (E.Name)) & " = "
                          & Pref & "parse_"
                          & Zig_Snake (To_String (E.Name)) & "(p)" & Cat & ";");
                        Append (Buf, LF);
                     end if;
                  when Group =>
                     Emit_Seq (Owner, E.Items, 1, Natural (E.Items.Length), Dst, Buf,
                               Fail, Ind & "    ");
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
      --  Els.  Each branch runs inside a labelled block whose `catch` failures
      --  break out of it; a failed branch restores p.pos and resets the struct
      --  (Reset), a successful one sets `matched` and returns r.  After the
      --  last branch fails, control falls through for the caller's own failure
      --  handling.
      procedure Emit_Alternation
        (Owner : Natural;
         Els : Element_Vectors.Vector; Acc, Reset : String;
         Buf : in out U; Ind : String := "    ") is
         N  : constant Natural := Natural (Els.Length);
         St : Natural := 1;
         Br : Natural := 0;
         Block_Start : Natural := 0;

         function Img (X : Natural) return String is
            S : constant String := Natural'Image (X);
         begin
            if S'Length > 0 and then S (S'First) = ' ' then
               return S (S'First + 1 .. S'Last);
            end if;
            return S;
         end Img;
      begin
         for K in 1 .. N + 1 loop
            if K > N or else Els (K).Kind = Alt then
               Br := Br + 1;
               if Br > 1 then
                  Append (Buf, Ind & "p.pos = save; " & Reset & "; matched = false;");
                  Append (Buf, LF);
               end if;
               Block_Start := Length (Buf);
               Append (Buf, Ind & "blk_" & Img (Br) & ": {");
               Append (Buf, LF);
               Emit_Seq (Owner, Els, St, K - 1, Acc, Buf,
                         "break :blk_" & Img (Br), Ind & "    ");
               --  First match wins: this branch is taken only if the next
               --  code point can follow the choice.
               if K <= N and then Els (K).Kind = Alt and then Els (K).Guard /= 0
               then
                  Append (Buf, Ind & "    { const sv = p.pos;"
                    & (if Rules (Owner).Whitespace /= Null_Unbounded_String
                       then " p.skip_ws();" else "")
                    & " const g = p.guard_" & Img (Els (K).Guard)
                    & "(); p.pos = sv; if (!g) break :blk_" & Img (Br) & "; }");
                  Append (Buf, LF);
               end if;
               if Writer_On and then Natural (Rules (Owner).Pattern.Length) > 1 then
                  Append (Buf, Ind & "    r._alt = " & Img (Br) & ";");
                  Append (Buf, LF);
               end if;
               Append (Buf, Ind & "    matched = true;");
               Append (Buf, LF);
               Append (Buf, Ind & "}");
               Append (Buf, LF);
               Drop_Unused_Label
                 (Buf, Block_Start, Ind & "blk_" & Img (Br) & ": {",
                  "break :blk_" & Img (Br), Ind & "{");
               Append (Buf, Ind & "if (matched) return r;");
               Append (Buf, LF);
               St := K + 1;
            end if;
         end loop;
      end Emit_Alternation;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         ZT : constant String := Zig_Type (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Is_Pure_Literal_Alt (P);
         SU : constant String :=
           (if not Is_List then Scalar_Union_Type (Rules, P) else "");

         --  A rule that owns a box releases it when it fails after the field
         --  was set: on a failed branch (before the next one runs) and on the
         --  error return (the last branch, or a plain sequence).
         Owns    : constant Boolean := Has_Back (Backs, Idx);
         Release : constant String :=
           "deinit_" & Zig_Snake (NM) & "(&r, p.alloc)";
         Reset   : constant String :=
           (if Owns then Release & "; " else "")
           & "r = std.mem.zeroes(" & ZT & ")";
      begin
         if Is_Char_Rule (Rules, NM) or else R.Jet_Code /= Null_Unbounded_String
         then
            --  A char rule is a scanner: run it here and capture the text.  A
            --  jet is its built-in scanner, or the stub for hand-written C.
            Append (Buf, "    const n = "
              & (if R.Jet_Code /= Null_Unbounded_String
                 then Jet_Fn (NM) else "scan_" & Zig_Snake (NM))
              & "(p.text, p.pos, p.text.len);");
            Append (Buf, LF);
            if R.Jet_Code /= Null_Unbounded_String
              or else not Can_Be_Empty (NM)
            then
               Append (Buf, "    if (n == 0) try p.fail("""
                 & (if R.Jet_Code /= Null_Unbounded_String then "a " else "")
                 & NM & """);");
               Append (Buf, LF);
            end if;
            Append (Buf, "    const r = p.text[p.pos .. p.pos + n]; p.pos += n;");
            Append (Buf, LF);
            Append (Buf, "    return r;");
            Append (Buf, LF);
            return;
         end if;
         if Is_List then
            declare
               E    : constant Element_Access := P (1);
               Elem : constant String :=
                 (if E.Kind = HBNF_Grammar.Name
                  then Zig_Type_Of (To_String (E.Name))
                  elsif Lit_Only (E.Items) then "[]const u8"
                  else ZT & "Entry");
               --  An entry with no field is never written.
               No_Fields : constant Boolean :=
                 E.Kind = HBNF_Grammar.Group and then Lit_Only (E.Items);
               --  Repetition bounds, as the C backend enforces them.
               Max_Stop : constant String :=
                 (if E.Max >= 0
                  then "if (list.items.len >= " & Img (Natural (E.Max))
                       & ") break"
                  else "");

               --  The alternatives of V as labelled blocks: a branch that
               --  matches breaks out of blk_alt with e filled in; one that
               --  fails breaks out of its own block, and the next starts
               --  from save.
               procedure Alt_Blocks (V : Element_Vectors.Vector;
                                     Label, Ind : String) is
                  St     : Natural := 1;
                  Branch : Natural := 0;
                  Block_Start : Natural := 0;
               begin
                  for K in 1 .. Natural (V.Length) + 1 loop
                     if K > Natural (V.Length) or else V (K).Kind = Alt then
                        if St <= K - 1 then
                           Branch := Branch + 1;
                           if Branch > 1 then
                              Append (Buf, Ind & "p.pos = save;"
                                & (if No_Fields then ""
                                   else " e = std.mem.zeroes(" & Elem & ");"));
                              Append (Buf, LF);
                           end if;
                           Block_Start := Length (Buf);
                           Append (Buf, Ind & Label & "blk_" & Img (Branch) & ": {");
                           Append (Buf, LF);
                           Emit_Seq (Idx, V, St, K - 1, "e.", Buf,
                                     "break :" & Label & "blk_" & Img (Branch),
                                     Ind & "    ");
                           if Entry_Alt (R, Analyze (Rules, Idx)) and then Label = ""
                             and then R.Left_Bases = 0
                           then
                              Append (Buf, Ind & "    e._alt = " & Img (Branch) & ";");
                              Append (Buf, LF);
                           end if;
                           Append (Buf, Ind & "    break :blk_alt;");
                           Append (Buf, LF);
                           Append (Buf, Ind & "}");
                           Append (Buf, LF);
                           Drop_Unused_Label
                             (Buf, Block_Start,
                              Ind & Label & "blk_" & Img (Branch) & ": {",
                              "break :" & Label & "blk_" & Img (Branch),
                              Ind & "{");
                        end if;
                        St := K + 1;
                     end if;
                  end loop;
               end Alt_Blocks;
            begin
               Append (Buf, "    var list = std.ArrayList(" & Elem
                 & ").empty;");
               Append (Buf, LF);
               if E.Min > 0 then
                  Append (Buf, "    const start = p.pos;");
                  Append (Buf, LF);
               end if;
               if E.Kind = Name then
                  --  PEG's `*`: stop at the end of input and at the first
                  --  element that fails, with the position restored, as C
                  --  does; the caller decides.
                  Append (Buf, "    while (true) {");
                  Append (Buf, LF);
                  if Max_Stop /= "" then
                     Append (Buf, "        " & Max_Stop & ";");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "        const save = p.pos;");
                  Append (Buf, LF);
                  if R.Whitespace /= Null_Unbounded_String then
                     Append (Buf, "        p.skip_ws();");
                     Append (Buf, LF);
                  end if;
                  if not Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "        if (p.pos >= p.text.len) { p.pos = save; break; }");
                     Append (Buf, LF);
                  end if;
                  if Is_Core (To_String (E.Name)) then
                     --  A list of a core type (`*word`): read the text in
                     --  place; there is no parse_ function for a core type.
                     Append (Buf, "        const n = " & Scan_Call (To_String (E.Name)) & ";");
                     Append (Buf, LF);
                     Append (Buf, "        if (n == 0" & Scalar_Reject (To_String (E.Name))
                       & ") { p.pos = save; break; }");
                     Append (Buf, LF);
                     Append (Buf, "        try list.append(p.alloc, "
                       & Scalar_Value (To_String (E.Name), "try ", "") & ");");
                     Append (Buf, LF);
                     Append (Buf, "        p.pos += n;");
                     Append (Buf, LF);
                  else
                     Append (Buf, "        const v = parse_"
                       & Zig_Snake (To_String (E.Name)) & "(p) catch |err| switch (err) {");
                     Append (Buf, LF);
                     Append (Buf, "            error.OutOfMemory => return err,");
                     Append (Buf, LF);
                     Append (Buf, "            else => { p.pos = save; break; },");
                     Append (Buf, LF);
                     Append (Buf, "        };");
                     Append (Buf, LF);
                     Append (Buf, "        try list.append(p.alloc, v);");
                     Append (Buf, LF);
                  end if;
                  --  What is repeated can match nothing: an iteration that
                  --  did not advance would match the same nothing again.
                  if Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "        if (p.pos == save) break;");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "    }");
                  Append (Buf, LF);
               elsif E.Kind = Group then
                  Append (Buf, "    list: while ("
                    & (if Repeated_Body_Nullable (Rules, E) then "true"
                       else "p.pos < p.text.len") & ") {");
                  Append (Buf, LF);
                  if Max_Stop /= "" then
                     Append (Buf, "        " & Max_Stop & " :list;");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "        const save = p.pos;");
                  Append (Buf, LF);
                  Append (Buf, (if No_Fields
                                then "        const e: []const u8 = """";"
                                else "        var e = std.mem.zeroes(" & Elem & ");"));
                  Append (Buf, LF);
                  Append (Buf, "        blk_alt: {");
                  Append (Buf, LF);
                  if R.Left_Bases > 0 then
                     --  Left recursion, as a loop: the first entry is a
                     --  base, each later one a tail.
                     Append (Buf, "            if (list.items.len == 0) {");
                     Append (Buf, LF);
                     Alt_Blocks (Base_Branches (R), "base_", "                ");
                     Append (Buf, "                p.pos = save; break :list;");
                     Append (Buf, LF);
                     Append (Buf, "            }");
                     Append (Buf, LF);
                     Alt_Blocks (Tail_Branches (R), "", "            ");
                  else
                     Alt_Blocks (E.Items, "", "            ");
                  end if;
                  Append (Buf, "            p.pos = save; break :list;");
                  Append (Buf, LF);
                  Append (Buf, "        }");
                  Append (Buf, LF);
                  Append (Buf, "        try list.append(p.alloc, e);");
                  Append (Buf, LF);
                  if Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "        if (p.pos == save) break :list;");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "    }");
                  Append (Buf, LF);
               end if;
               if E.Min > 0 then
                  Append (Buf, "    if (list.items.len < " & Img (E.Min)
                    & ") { p.pos = start; list.deinit(p.alloc); try p.fail(""a "
                    & NM & """); }");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    return list.toOwnedSlice(p.alloc);");
               Append (Buf, LF);
            end;
         elsif Is_Enum then
            --  Each alternative matches its literal at the position, in order:
            --  a keyword by the `word` scanner, any other literal by its bytes.
            declare
               Lits   : String_Vectors.Vector;
               Names  : String_Vectors.Vector;
               St     : Natural := 1;
               Branch : Natural := 0;

               function Lit_At (L : Element_Access) return String is
                  S  : constant String := To_String (L.Lit);
                  NL : constant String := Img (S'Length);
                  Sl : constant String := "p.text[p.pos .. p.pos + " & NL & "]";
                  Eq : constant String :=
                    (if L.No_Case then "std.ascii.eqlIgnoreCase(" & Sl & ", """
                                       & Zig_Escape (S) & """)"
                     else "std.mem.eql(u8, " & Sl & ", """
                          & Zig_Escape (S) & """)");
               begin
                  if Is_Keyword_Lit (S) then
                     return "scan_word(p.text, p.pos, p.text.len) == " & NL
                       & " and " & Eq;
                  end if;
                  return "p.pos + " & NL & " <= p.text.len and " & Eq;
               end Lit_At;
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

               Append (Buf, "    if (p.pos >= p.text.len) try p.fail(""a " & ZT & """);");
               Append (Buf, LF);
               Append (Buf, "    var r: " & ZT & " = undefined;");
               Append (Buf, LF);

               St := 1;
               Branch := 0;
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        Append (Buf, (if Branch = 0 then "    if (" else "    } else if (")
                          & Lit_At (P (St)) & ") {");
                        Append (Buf, LF);
                        Append (Buf, "        r = ." & To_String (Names (Branch + 1))
                          & "; p.pos += "
                          & Img (To_String (P (St).Lit)'Length) & ";");
                        Append (Buf, LF);
                        Branch := Branch + 1;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "    } else { try p.fail(""");
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
                        Append (Buf, "`" & Zig_Escape (To_String (P (St).Lit)) & "`");
                        First := False;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, """); }");
            Append (Buf, LF);
            Append (Buf, "    return r;");
            Append (Buf, LF);
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            if Is_Core (To_String (P (1).Name)) then
               Append (Buf, "    const n = " & Scan_Call (To_String (P (1).Name)) & ";");
               Append (Buf, LF);
               Append (Buf, "    if (n == 0" & Scalar_Reject (To_String (P (1).Name))
                 & ") try p.fail(""" & Core_Desc (To_String (P (1).Name)) & """);");
               Append (Buf, LF);
               Append (Buf, "    const r = " & Scalar_Value (To_String (P (1).Name), "try ", "")
                 & "; p.pos += n;");
               Append (Buf, LF);
               Append (Buf, "    return r;");
               Append (Buf, LF);
            elsif HBNF_Grammar.Except_Operand (NM) /= "" then
               --  `X = A - B` with a phrase on a side: parse A; then try B on
               --  exactly the text A matched (the input ends where A did, and
               --  B must end there too).  If it does, X does not match.
               declare
                  A : constant String := To_String (P (1).Name);
                  B : constant String := HBNF_Grammar.Except_Operand (NM);

                  --  The rule a name stands for, through single-name aliases.
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

                  --  Does a value of this rule own memory to release?
                  function Owns (Nm : String) return Boolean is
                     J : constant Natural := Find (Rules, Chase (Nm));
                  begin
                     return J /= 0
                       and then Analyze (Rules, J).Kind in Struct | List;
                  end Owns;
               begin
                  Append (Buf, "    const save = p.pos;" & LF);
                  Append (Buf, "    " & (if Owns (A) then "var" else "const")
                    & " r = try parse_" & Zig_Snake (A) & "(p);" & LF);
                  if Owns (A) then
                     Append (Buf, "    errdefer deinit_" & Zig_Snake (Chase (A))
                       & "(&r, p.alloc);" & LF);
                  end if;
                  Append (Buf, "    const end = p.pos;" & LF);
                  Append (Buf, "    const keep = p.*;" & LF);
                  Append (Buf, "    p.text = p.text[0..end]; p.pos = save;" & LF);
                  Append (Buf, "    var same = false;" & LF);
                  if Owns (B) then
                     Append (Buf, "    if (parse_" & Zig_Snake (B) & "(p)) |bv| {" & LF);
                     Append (Buf, "        var b = bv;" & LF);
                     Append (Buf, "        same = p.pos == end;" & LF);
                     Append (Buf, "        deinit_" & Zig_Snake (Chase (B))
                       & "(&b, p.alloc);" & LF);
                  else
                     Append (Buf, "    if (parse_" & Zig_Snake (B) & "(p)) |_| {" & LF);
                     Append (Buf, "        same = p.pos == end;" & LF);
                  end if;
                  Append (Buf, "    } else |e| {" & LF);
                  Append (Buf, "        if (e == error.OutOfMemory) { p.* = keep; return e; }" & LF);
                  Append (Buf, "    }" & LF);
                  Append (Buf, "    p.* = keep;" & LF);
                  Append (Buf, "    if (same) { p.pos = save; try p.fail(""`" & A
                    & "` that is not `" & B & """); }" & LF);
                  Append (Buf, "    return r;" & LF);
               end;
            else
               Append (Buf, "    return try parse_" & Zig_Snake (To_String (P (1).Name))
                 & "(p);");
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
                              Append (Buf, "    { const n = " & Scan_Call (To_String (E.Name))
                                & "; if (n > 0" & Scalar_Guard (To_String (E.Name))
                                & ") { const r = "
                                & Scalar_Value (To_String (E.Name), "try ", "")
                                & "; p.pos += n; return r; } }");
                              Append (Buf, LF);
                           elsif E.Kind = Name then
                              Append (Buf, "    if (parse_" & Zig_Snake (To_String (E.Name))
                                & "(p)) |r| { return r; } else |_| {}");
                              Append (Buf, LF);
                           end if;
                        end;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "    try p.fail(""a " & NM & """);");
            Append (Buf, LF);
            Append (Buf, "    unreachable;");
            Append (Buf, LF);
         elsif Has_Alt (P) then
            --  A struct alternation: try each branch with backtracking.
            Append (Buf, "    const save = p.pos;");
            Append (Buf, LF);
            Append (Buf, "    var r: " & ZT & " = std.mem.zeroes(" & ZT & ");");
            Append (Buf, LF);
            if Owns then
               Append (Buf, "    errdefer " & Release & ";");
               Append (Buf, LF);
            end if;
            Append (Buf, "    var matched = false;");
            Append (Buf, LF);
            Emit_Alternation (Idx, P, "r.", Reset, Buf);
            Append (Buf, "    p.pos = save;");
            Append (Buf, LF);
            Append (Buf, "    try p.fail(""a " & NM & """);");
            Append (Buf, LF);
            Append (Buf, "    unreachable;");
            Append (Buf, LF);
         else
            if Has_Name (P) then
               Append (Buf, "    var r: " & ZT & " = std.mem.zeroes(" & ZT & ");");
               if Owns then
                  Append (Buf, LF);
                  Append (Buf, "    errdefer " & Release & ";");
               end if;
            else
               Append (Buf, "    const r: " & ZT & " = std.mem.zeroes(" & ZT & ");");
            end if;
            Append (Buf, LF);
            Emit_Seq (Idx, P, 1, Natural (P.Length), "r.", Buf);
            Append (Buf, "    return r;");
            Append (Buf, LF);
         end if;
      end Emit_Rule_Parser;

      Res : U;

      --  Emit the greedy loop for a repetition: match one full branch of the
      --  DNF (the longest one) as many times as Max allows (0 = unbounded),
      --  then require Min.  A branch is a sequence of decoded code points.
      procedure Emit_Repeat (A : Cp_Atom; Ind : String; Fail : String) is
         procedure Emit_Branch (B : Cp_Range_Vectors.Vector) is
         begin
            Append (Res, Ind & "        { var o: usize = 0; var ok = true;");
            Append (Res, LF);
            for Rg of B loop
               Append (Res, Ind & "          if (ok) { var c: u32 = 0; const n = decode_utf8(s,"
                 & " pos + off + o, len, &c); if (n == 0 or !"
                 & Range_Cond (Rg.Lo, Rg.Hi) & ") { ok = false; } else { o += n; } }");
               Append (Res, LF);
            end loop;
            Append (Res, Ind & "          if (ok and o > br) { br = o; } }");
            Append (Res, LF);
         end Emit_Branch;
      begin
         Append (Res, Ind & "{ var cnt: usize = 0;");
         Append (Res, LF);
         if A.Max = 0 then
            Append (Res, Ind & "    while (true) {");
         else
            Append (Res, Ind & "    while (cnt < " & Img (A.Max) & ") {");
         end if;
         Append (Res, LF);
         Append (Res, Ind & "        var br: usize = 0;");
         Append (Res, LF);
         for B of A.Sub loop
            Emit_Branch (B);
         end loop;
         Append (Res, Ind & "        if (br == 0) break;");
         Append (Res, LF);
         Append (Res, Ind & "        off += br; cnt += 1;");
         Append (Res, LF);
         Append (Res, Ind & "    }");
         Append (Res, LF);
         if A.Min > 0 then
            Append (Res, Ind & "    if (cnt < " & Img (A.Min) & ") " & Fail & ";");
            Append (Res, LF);
         end if;
         Append (Res, Ind & "}");
         Append (Res, LF);
      end Emit_Repeat;
   begin
      Append (Res, "// generated by hbnf -- do not edit");
      Append (Res, LF);
      Append (Res, "const std = @import(""std"");");
      Append (Res, LF);
      Append (Res, LF);
      if Preamble ("Zig") /= "" then
         Append (Res, Preamble ("Zig"));
         Append (Res, LF);
         Append (Res, LF);
      end if;
      Append (Res, "pub const ParseError = error{ Invalid, OutOfMemory };");
      Append (Res, LF);
      Append (Res, "const SPACES = ""                                                                "";");
      Append (Res, LF);
      Append (Res, "fn is_word_char(c: u8) bool {");
      Append (Res, LF);
      Append (Res, "    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-' or c == '.';");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "// The parser reads the text itself: a byte position in it, no token array.");
      Append (Res, LF);
      Append (Res, "// The farthest failure: what could have stood there (each told once), the");
      Append (Res, LF);
      Append (Res, "// message made of them, and the rules being read, to say where an unfinished");
      Append (Res, LF);
      Append (Res, "// construct began.");
      Append (Res, LF);
      Append (Res, "const ErrState = struct {");
      Append (Res, LF);
      Append (Res, "    line: usize = 0,");
      Append (Res, LF);
      Append (Res, "    col: usize = 0,");
      Append (Res, LF);
      Append (Res, "    buf: [512]u8 = undefined,");
      Append (Res, LF);
      Append (Res, "    len: usize = 0,");
      Append (Res, LF);
      Append (Res, "    pos: usize = 0,");
      Append (Res, LF);
      Append (Res, "    alt_n: usize = 0,");
      Append (Res, LF);
      Append (Res, "    alt_exp: [16][]const u8 = undefined,");
      Append (Res, LF);
      Append (Res, "    alt_more: bool = false,");
      Append (Res, LF);
      Append (Res, "    text: []const u8 = """",");
      Append (Res, LF);
      Append (Res, "    depth: usize = 0,");
      Append (Res, LF);
      Append (Res, "    stk: [24]u16 = undefined,");
      Append (Res, LF);
      Append (Res, "    stkpos: [24]usize = undefined,");
      Append (Res, LF);
      Append (Res, "};");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "const P = struct {");
      Append (Res, LF);
      Append (Res, "    text: []const u8,");
      Append (Res, LF);
      Append (Res, "    alloc: std.mem.Allocator,");
      Append (Res, LF);
      Append (Res, "    pos: usize = 0,");
      Append (Res, LF);
      Append (Res, "    e: ErrState = .{},   // the farthest failure, as the message");
      Append (Res, LF);
      Append (Res, "    depth: usize = 0,   // the rules being read, and where each began");
      Append (Res, LF);
      Append (Res, "    stk: [24]u16 = undefined,");
      Append (Res, LF);
      Append (Res, "    stkpos: [24]usize = undefined,");
      Append (Res, LF);
      if Is_Hosted then
         Append (Res, "    bit: u3 = 0,   // bits of the octet at pos already read by a bit rule");
         Append (Res, LF);
      end if;
      Append (Res, LF);
      if not Backs.Is_Empty then
         --  A back edge's subtree lives behind a pointer: move the parsed
         --  value onto the heap.
         Append (Res, "    fn box(self: *P, comptime T: type, v: T) ParseError!*T {");
         Append (Res, LF);
         Append (Res, "        const c = try self.alloc.create(T);");
         Append (Res, LF);
         Append (Res, "        c.* = v;");
         Append (Res, LF);
         Append (Res, "        return c;");
         Append (Res, LF);
         Append (Res, "    }");
         Append (Res, LF);
         Append (Res, LF);
      end if;
      declare
         procedure Put (Text : String) is
         begin
            Append (Res, Text);
            Append (Res, LF);
         end Put;
      begin
         Put ("    fn emit(self: *P, s: []const u8) void {");
         Put ("        const n = @min(s.len, self.e.buf.len - 1 - self.e.len);");
         Put ("        @memcpy(self.e.buf[self.e.len..][0..n], s[0..n]);");
         Put ("        self.e.len += n;");
         Put ("    }");
         Put ("");
         Put ("    fn set_err(self: *P, expected: []const u8) void {");
         Put ("        if (self.e.len != 0 and self.pos < self.e.pos) return;");
         Put ("        if (self.e.len != 0 and self.pos == self.e.pos) {");
         Put ("            // the same place: another thing that could have stood here");
         Put ("            for (self.e.alt_exp[0..self.e.alt_n]) |x| {");
         Put ("                if (std.mem.eql(u8, x, expected)) return;");
         Put ("            }");
         Put ("            if (self.e.alt_n < 16) {");
         Put ("                self.e.alt_exp[self.e.alt_n] = expected;");
         Put ("                self.e.alt_n += 1;");
         Put ("            } else self.e.alt_more = true;");
         Put ("            self.render();");
         Put ("            return;");
         Put ("        }");
         Put ("        self.e.pos = self.pos;");
         Put ("        self.e.alt_n = 1;");
         Put ("        self.e.alt_exp[0] = expected;");
         Put ("        self.e.alt_more = false;");
         Put ("        self.e.text = self.text;");
         Put ("        self.e.depth = @min(self.depth, 24);");
         Put ("        @memcpy(self.e.stk[0..self.e.depth], self.stk[0..self.e.depth]);");
         Put ("        @memcpy(self.e.stkpos[0..self.e.depth], self.stkpos[0..self.e.depth]);");
         Put ("        self.render();");
         Put ("    }");
         Put ("");
         Put ("    // The message: what was expected, what was found, the line and where in it;");
         Put ("    // and, for a failure far from where the rule it is in began, that rule's line.");
         Put ("    fn render(self: *P) void {");
         Put ("        const t = self.e.text;");
         Put ("        const at = self.e.pos;");
         Put ("        const end = if (at < t.len) at else t.len;");
         Put ("        var line: usize = 1;");
         Put ("        var start: usize = 0;");
         Put ("        var i: usize = 0;");
         Put ("        while (i < end) : (i += 1) {");
         Put ("            if (t[i] == '\n') { line += 1; start = i + 1; }");
         Put ("        }");
         Put ("        const col = end - start + 1;");
         Put ("        var stop = start;");
         Put ("        while (stop < t.len and t[stop] != '\n') stop += 1;");
         Put ("        self.e.line = line;");
         Put ("        self.e.col = col;");
         Put ("        // What stands there: the bareword that starts at the position,");
         Put ("        // else the one character, else the end of the text.");
         Put ("        var fend = at;");
         Put ("        const at_end = at >= t.len;");
         Put ("        const found = if (at_end) ""end of input"" else blk: {");
         Put ("            if (is_word_char(t[at])) {");
         Put ("                while (fend < t.len and is_word_char(t[fend])) fend += 1;");
         Put ("            } else {");
         Put ("                fend += 1;");
         Put ("                while (fend < t.len and (t[fend] & 0xC0) == 0x80) fend += 1;");
         Put ("            }");
         Put ("            break :blk t[at..fend];");
         Put ("        };");
         Put ("        const w = if (col - 1 > SPACES.len) SPACES.len else col - 1;");
         Put ("        self.e.len = 0;");
         Put ("        var pb: [72]u8 = undefined;");
         Put ("        self.emit(std.fmt.bufPrint(&pb, ""{d}:{d}:{d}: "", .{ line, col, at }) catch """");");
         Put ("        self.emit(""expected "");");
         Put ("        if (self.e.alt_n > 1) self.emit(""one of "");");
         Put ("        for (self.e.alt_exp[0..self.e.alt_n], 0..) |x, k| {");
         Put ("            if (k > 0) self.emit("", "");");
         Put ("            self.emit(x);");
         Put ("        }");
         Put ("        if (self.e.alt_more) self.emit("", ..."");");
         Put ("        self.emit("", found "");");
         Put ("        self.emit(found);");
         Put ("        self.emit(""\n  "");");
         Put ("        self.emit(t[start..stop]);");
         Put ("        self.emit(""\n  "");");
         Put ("        self.emit(SPACES[0..w]);");
         Put ("        self.emit(""^"");");
         Put ("        var k: usize = self.e.depth;");
         Put ("        while (k > 0) {");
         Put ("            k -= 1;");
         Put ("            const nm = RN[self.e.stk[k]];");
         Put ("            if (nm.len == 0) continue;");
         Put ("            var sp = self.e.stkpos[k];");
         Put ("            while (sp < t.len and (t[sp] == ' ' or t[sp] == '\t' or t[sp] == '\n' or t[sp] == '\r')) sp += 1;");
         Put ("            var l: usize = 1;");
         Put ("            var ls: usize = 0;");
         Put ("            for (t[0..sp], 0..) |c, j| {");
         Put ("                if (c == '\n') { l += 1; ls = j + 1; }");
         Put ("            }");
         Put ("            if (l + (if (at_end) @as(usize, 1) else 3) > line) continue;");
         Put ("            var le = sp;");
         Put ("            while (le < t.len and t[le] != '\n') le += 1;");
         Put ("            self.emit(""\n  "");");
         Put ("            self.emit(std.fmt.bufPrint(&pb, ""{d}:{d}:{d}: "", .{ l, sp - ls + 1, sp }) catch """");");
         Put ("            self.emit(if (at_end) ""the "" else ""inside the "");");
         Put ("            self.emit(nm);");
         Put ("            self.emit(if (at_end) "" that begins here is not finished:\n  "" else "" that begins here:\n  "");");
         Put ("            self.emit(t[ls..le]);");
         Put ("            self.emit(""\n  "");");
         Put ("            self.emit(SPACES[0..@min(sp - ls, SPACES.len)]);");
         Put ("            self.emit(""^"");");
         Put ("            break;");
         Put ("        }");
         Put ("    }");
         Put ("");
         Put ("    fn fail(self: *P, expected: []const u8) ParseError!void {");
         Put ("        self.set_err(expected);");
         Put ("        return error.Invalid;");
         Put ("    }");
         Put ("");
         Put ("    // A punctuation- or digit-led literal: compare bytes at the position (a");
         Put ("    // prefix is correct there, e.g. ""-"" in ""-5"", ""0x"" in ""0x1F"").");
         Put ("    fn expect_lit(self: *P, lit: []const u8, want: []const u8) ParseError!void {");
         Put ("        if (self.pos + lit.len <= self.text.len");
         Put ("            and std.mem.eql(u8, self.text[self.pos .. self.pos + lit.len], lit)) { self.pos += lit.len; return; }");
         Put ("        return self.fail(want);");
         Put ("    }");
         Put ("");
         --  The guards `/` sets where a union needs backtracking (first match
         --  wins, as RFC 3986 section 3.2.2 settles `host`).
         for G in 1 .. HBNF_Grammar.Guard_Count loop
            declare
               Rs  : constant HBNF_Grammar.Guard_Range_Array :=
                 HBNF_Grammar.Guard_Ranges (G);
               Gid : constant String := Natural'Image (G);
               Cond : Unbounded_String := To_Unbounded_String ("false");
            begin
               for R of Rs loop
                  Append (Cond, " or (c >= " & Natural'Image (R.Lo) & " and c <= "
                    & Natural'Image (R.Hi) & ")");
               end loop;
               Put ("    fn guard_" & Gid (Gid'First + 1 .. Gid'Last)
                 & "(self: *P) bool {");
               Put ("        if (self.pos >= self.text.len) return "
                 & (if HBNF_Grammar.Guard_Eoi (G) then "true" else "false") & ";");
               if Rs'Length = 0 then
                  Put ("        return false;");
                  Put ("    }");
                  Put ("");
                  goto Next_Guard_Z;
               end if;
               Put ("        const b = self.text[self.pos];");
               Put ("        const n: usize = if (b < 0x80) 1 else if (b < 0xE0) 2 else if (b < 0xF0) 3 else 4;");
               Put ("        if (self.pos + n > self.text.len) return false;");
               Put ("        var c: u32 = if (n == 1) b else if (n == 2) (b & 0x1F) else if (n == 3) (b & 0x0F) else (b & 0x07);");
               Put ("        var i: usize = 1;");
               Put ("        while (i < n) : (i += 1) c = (c << 6) | (self.text[self.pos + i] & 0x3F);");
               Put ("        return " & To_String (Cond) & ";");
               Put ("    }");
               Put ("");
               <<Next_Guard_Z>> null;
            end;
         end loop;
         Put ("    // A keyword: the whole bareword at the position must be the literal, so");
         Put ("    // `in` does not match the front of `input`.");
         Put ("    fn expect_word(self: *P, lit: []const u8, want: []const u8) ParseError!void {");
         Put ("        const n = scan_word(self.text, self.pos, self.text.len);");
         Put ("        if (n == lit.len and std.mem.eql(u8, self.text[self.pos .. self.pos + n], lit)) { self.pos += n; return; }");
         Put ("        return self.fail(want);");
         Put ("    }");
         Put ("");
         if Has_No_Case (Rules) then
            Put ("    fn expect_word_nocase(self: *P, lit: []const u8, want: []const u8) ParseError!void {");
            Put ("        const n = scan_word(self.text, self.pos, self.text.len);");
            Put ("        if (n == lit.len and std.ascii.eqlIgnoreCase(self.text[self.pos .. self.pos + n], lit)) { self.pos += n; return; }");
            Put ("        return self.fail(want);");
            Put ("    }");
            Put ("");
            Put ("    // A case-insensitive literal that is not a keyword: its characters.");
            Put ("    fn expect_lit_nocase(self: *P, lit: []const u8, want: []const u8) ParseError!void {");
            Put ("        if (self.pos + lit.len <= self.text.len");
            Put ("            and std.ascii.eqlIgnoreCase(self.text[self.pos .. self.pos + lit.len], lit)) { self.pos += lit.len; return; }");
            Put ("        return self.fail(want);");
            Put ("    }");
            Put ("");
         end if;
         Put ("    // Skip what the grammar calls whitespace, one match at a time.");
         Put ("    fn skip_ws(self: *P) void {");
         if Ws_Name = "" then
            Put ("        _ = self;");
         else
            Put ("        while (true) {");
            Put ("            const n = scan_" & Zig_Snake (Ws_Name)
              & "(self.text, self.pos, self.text.len);");
            Put ("            if (n == 0) break;");
            Put ("            self.pos += n;");
            Put ("        }");
         end if;
         Put ("    }");
         Put ("");
      end;
      Append (Res, "    fn err_out(self: *P, out: *[512]u8, line: *usize, col: *usize) ParseError {");
      Append (Res, LF);
      Append (Res, "        @memcpy(out[0..self.e.len], self.e.buf[0..self.e.len]);");
      Append (Res, LF);
      Append (Res, "        out[self.e.len] = 0;");
      Append (Res, LF);
      Append (Res, "        line.* = self.e.line;");
      Append (Res, LF);
      Append (Res, "        col.* = self.e.col;");
      Append (Res, LF);
      Append (Res, "        return error.Invalid;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "};");
      Append (Res, LF);
      Append (Res, LF);

      for I in 1 .. N loop
         declare
            NM : constant String := To_String (Rules (I).Name);
         begin
            --  A core-type char rule (str/int/word) is read as a scalar in
            --  place, and a building block is inlined into a token's scanner;
            --  neither needs a parse function of its own.
            if not (Is_Char_Rule (Rules, NM)
                    and then (Is_Core_Name (NM)
                              or else not Is_Char_Token (Rules, NM)))
            then
               --  An empty rule's body never reads the parser, so its
               --  parameter is anonymous: Zig rejects an unused function
               --  parameter outright, not just as a warning.  A jet rule also
               --  has an empty pattern but does read `p`, so it keeps the name.
               declare
                  Param : constant String :=
                    (if Rules (I).Pattern.Is_Empty
                       and then Rules (I).Jet_Code = Null_Unbounded_String
                     then "_" else "p");
               begin
                  Append (Res, "fn parse_" & Zig_Snake (NM)
                    & "(" & Param & ": *P) ParseError!" & Ret_Type (I) & " {");
                  Append (Res, LF);
                  if Param = "p" then
                     Append (Res, "    if (p.depth < 24) { p.stk[p.depth] = " & Img (I)
                       & "; p.stkpos[p.depth] = p.pos; }");
                     Append (Res, LF);
                     Append (Res, "    p.depth += 1;");
                     Append (Res, LF);
                     Append (Res, "    defer p.depth -= 1;");
                     Append (Res, LF);
                  end if;
                  Emit_Rule_Parser (I, Res);
                  Append (Res, "}");
                  Append (Res, LF);
                  Append (Res, LF);
               end;
            end if;
         end;
      end loop;

      --  The rules an error names, by number (a rule the reader made up for a
      --  group or an option is left out).
      Append (Res, "const RN = [_][]const u8{ """"," & LF);
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
            Append (Res, (if Hidden then """""" else """" & NM & """") & "," & LF);
         end;
      end loop;
      Append (Res, "};" & LF & LF);

      --  The scanners.  A core rule the grammar does not define (`word`,
      --  `int`, `str`, `ws`) is a built-in: hand-written Zig, the same scan
      --  the C backend's jets make.  Any other jet is hand-written C, which
      --  this backend cannot run, so it is a stub that matches nothing.
      declare
         procedure Put (Text : String) is
         begin
            Append (Res, Text);
            Append (Res, LF);
         end Put;

         function Is_Jet (Nm : String) return Boolean is
            J : constant Natural := Find (Rules, Nm);
         begin
            return J > 0 and then Rules (J).Jet_Code /= Null_Unbounded_String;
         end Is_Jet;
      begin
         if Is_Jet ("word") or else Find (Rules, "word") = 0 then
            Put ("fn scan_word(s: []const u8, pos: usize, len: usize) usize {");
            Put ("    var i = pos;");
            Put ("    if (i >= len or !(std.ascii.isAlphabetic(s[i]) or s[i] == '_' or s[i] == '-')) return 0;");
            Put ("    i += 1;");
            Put ("    while (i < len and is_word_char(s[i])) i += 1;");
            Put ("    return i - pos;");
            Put ("}");
            Put ("");
         end if;
         if Is_Jet ("int") then
            Put ("fn scan_int(s: []const u8, pos: usize, len: usize) usize {");
            Put ("    var i = pos;");
            Put ("    if (i + 1 < len and s[i] == '-' and std.ascii.isDigit(s[i + 1])) i += 1;");
            Put ("    const start = i;");
            Put ("    while (i < len and std.ascii.isDigit(s[i])) i += 1;");
            Put ("    return if (i > start) i - pos else 0;");
            Put ("}");
            Put ("");
         end if;
         if Is_Jet ("str") then
            Put ("fn scan_str(s: []const u8, pos: usize, len: usize) usize {");
            Put ("    if (pos >= len or s[pos] != '""') return 0;");
            Put ("    var i = pos + 1;");
            Put ("    while (i < len and s[i] != '""') {");
            Put ("        if (s[i] == '\\' and i + 1 < len) i += 1;");
            Put ("        i += 1;");
            Put ("    }");
            Put ("    if (i >= len) return 0;");
            Put ("    return i + 1 - pos;");
            Put ("}");
            Put ("");
         end if;
         if Is_Jet ("ws") then
            Put ("fn scan_ws(s: []const u8, pos: usize, len: usize) usize {");
            Put ("    if (pos < len and (s[pos] == ' ' or s[pos] == '\t' or s[pos] == '\r' or s[pos] == '\n')) return 1;");
            Put ("    return 0;");
            Put ("}");
            Put ("");
         end if;
         for I in 1 .. N loop
            if Rules (I).Jet_Code /= Null_Unbounded_String
              and then not Is_Builtin_Jet (To_String (Rules (I).Name))
            then
               declare
                  NM   : constant String := To_String (Rules (I).Name);
                  Code : constant String :=
                    HBNF_Grammar.Jet_Body (NM, HBNF_Grammar.Zig_Target);
               begin
                  if Code /= "" then
                     Put ("fn jet_" & Zig_Snake (NM)
                       & "(s: []const u8, pos: usize, len: usize) usize {");
                     Put ("    _ = .{ s, pos, len };");
                     Put (Code);
                     Put ("}");
                     Put ("");
                  else
                     Put ("fn jet_" & Zig_Snake (NM)
                       & "(_: []const u8, _: usize, _: usize) usize {");
                     Put ("    return 0;  // no Zig code: write `" & NM
                       & " = Zig { ... }`");
                     Put ("}");
                     Put ("");
                  end if;
               end;
            end if;
         end loop;

         --  The content of a quoted string: strip the quotes, and drop a
         --  backslash (keeping the character after it) or a backslash-newline.
         --  With no backslash it is a slice of the text and needs no copy.
         Put ("fn str_value(alloc: std.mem.Allocator, s: []const u8) ParseError![]const u8 {");
         Put ("    const inner = s[1 .. s.len - 1];");
         Put ("    if (std.mem.indexOfScalar(u8, inner, '\\') == null) return inner;");
         Put ("    var r = std.ArrayList(u8).empty;");
         Put ("    errdefer r.deinit(alloc);");
         Put ("    var i: usize = 0;");
         Put ("    while (i < inner.len) : (i += 1) {");
         Put ("        if (inner[i] == '\\' and i + 1 < inner.len) {");
         Put ("            i += 1;");
         Put ("            if (inner[i] != '\n') try r.append(alloc, inner[i]);");
         Put ("        } else {");
         Put ("            try r.append(alloc, inner[i]);");
         Put ("        }");
         Put ("    }");
         Put ("    return r.toOwnedSlice(alloc);");
         Put ("}");
         Put ("");

         --  The words `word` must not match.
         if Keywords.Is_Empty then
            Put ("fn is_keyword(s: []const u8) bool {");
            Put ("    _ = s;");
            Put ("    return false;");
            Put ("}");
         else
            Put ("fn is_keyword(s: []const u8) bool {");
            Append (Res, "    return");
            for K in 1 .. Natural (Keywords.Length) loop
               Append (Res, (if K = 1 then " " else LF & "        or ")
                 & "std.mem.eql(u8, s, """ & Zig_Escape (To_String (Keywords (K))) & """)");
            end loop;
            Put (";");
            Put ("}");
         end if;
         Put ("");
      end;

      --  Character-level scanners: a code point matches a char rule, the
      --  longest branch wins -- maximal munch -- and a phrase rule runs the
      --  scanner where it names the rule.
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
            Append (Res, "fn decode_utf8(s: []const u8, pos: usize, len: usize, cp: *u32) usize {");
            Append (Res, LF);
            Append (Res, "    if (pos >= len) return 0;");
            Append (Res, LF);
            Append (Res, "    const b0: u32 = s[pos];");
            Append (Res, LF);
            Append (Res, "    if (b0 < 0x80) { cp.* = b0; return 1; }");
            Append (Res, LF);
            Append (Res, "    var n: usize = 0;");
            Append (Res, LF);
            Append (Res, "    var c: u32 = 0;");
            Append (Res, LF);
            Append (Res, "    if (b0 & 0xE0 == 0xC0) { n = 2; c = b0 & 0x1F; }");
            Append (Res, LF);
            Append (Res, "    else if (b0 & 0xF0 == 0xE0) { n = 3; c = b0 & 0x0F; }");
            Append (Res, LF);
            Append (Res, "    else if (b0 & 0xF8 == 0xF0) { n = 4; c = b0 & 0x07; }");
            Append (Res, LF);
            Append (Res, "    else return 0;");
            Append (Res, LF);
            Append (Res, "    if (pos + n > len) return 0;");
            Append (Res, LF);
            Append (Res, "    var k: usize = 1;");
            Append (Res, LF);
            Append (Res, "    while (k < n) : (k += 1) {");
            Append (Res, LF);
            Append (Res, "        const b: u32 = s[pos + k];");
            Append (Res, LF);
            Append (Res, "        if (b & 0xC0 != 0x80) return 0;");
            Append (Res, LF);
            Append (Res, "        c = (c << 6) | (b & 0x3F);");
            Append (Res, LF);
            Append (Res, "    }");
            Append (Res, LF);
            Append (Res, "    cp.* = c;");
            Append (Res, LF);
            Append (Res, "    return n;");
            Append (Res, LF);
            Append (Res, "}");
            Append (Res, LF);
            Append (Res, LF);
         end if;

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
Append (Res, "fn scan_" & Zig_Snake (NM)
  & "(s: []const u8, pos: usize, len: usize) usize {" & LF);
Append (Res, "    const n = scan_" & Zig_Snake (HBNF_Grammar.Except_Base (NM))
  & "(s, pos, len);" & LF);
Append (Res, "    if (n == 0 or scan_" & Zig_Snake (HBNF_Grammar.Except_Operand (NM))
  & "(s, pos, pos + n) == n) return 0;" & LF);
Append (Res, "    return n;" & LF & "}" & LF & LF);
elsif Is_Dfa_Token (Rules, NM) then
declare
   D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
   Ok  : Boolean;
   Why : Unbounded_String;
   Lo, Hi, To, First, Acc : Unbounded_String;
begin
   HBNF_Lookahead.Token_Dfa (Rules, NM, D, Ok, Why);
   HBNF_Lookahead.Dfa_Tables (D, Lo, Hi, To, First, Acc);
   Append (Res, "fn scan_" & Zig_Snake (NM)
     & "(s: []const u8, pos: usize, len: usize) usize {" & LF);
   Append (Res, "    const lo = [_]u32{" & To_String (Lo) & "};" & LF);
   Append (Res, "    const hi = [_]u32{" & To_String (Hi) & "};" & LF);
   Append (Res, "    const to = [_]u16{" & To_String (To) & "};" & LF);
   Append (Res, "    const first = [_]u16{" & To_String (First) & "};" & LF);
   Append (Res, "    const acc = [_]u8{" & To_String (Acc) & "};" & LF);
   Append (Res, "    var i: usize = pos;" & LF);
   Append (Res, "    var best: usize = 0;" & LF);
   Append (Res, "    var st: usize = 0;" & LF);
   Append (Res, "    while (true) {" & LF);
   Append (Res, "        if (acc[st] != 0) best = i - pos;" & LF);
   Append (Res, "        if (i >= len) break;" & LF);
   Append (Res, "        var c: u32 = 0;" & LF);
   Append (Res, "        const n = decode_utf8(s, i, len, &c);" & LF);
   Append (Res, "        if (n == 0) break;" & LF);
   Append (Res, "        var k: usize = first[st];" & LF);
   Append (Res, "        const end: usize = first[st + 1];" & LF);
   Append (Res, "        while (k < end and !(c >= lo[k] and c <= hi[k])) k += 1;" & LF);
   Append (Res, "        if (k == end) break;" & LF);
   Append (Res, "        st = to[k];" & LF);
   Append (Res, "        i += n;" & LF);
   Append (Res, "    }" & LF);
   Append (Res, "    return best;" & LF & "}" & LF & LF);
end;
else
Append (Res, "fn scan_" & Zig_Snake (NM)
                    & "(s: []const u8, pos: usize, len: usize) usize {");
                  Append (Res, LF);
                  if Natural (DNF.Length) = 1 then
                     --  One branch: a sequence of code points, decoded in turn,
                     --  ending at most in one repetition.
                     Append (Res, "    var off: usize = 0;");
                     Append (Res, LF);
                     for A of DNF (1) loop
                        case A.Kind is
                           when Single =>
                              Append (Res, "    {");
                              Append (Res, LF);
                              Append (Res, "        var c: u32 = 0;");
                              Append (Res, LF);
                              Append (Res, "        const n = decode_utf8(s, pos + off, len, &c);");
                              Append (Res, LF);
                              Append (Res, "        if (n == 0 or !" & Range_Cond (A.Lo, A.Hi)
                                & ") return 0;");
                              Append (Res, LF);
                              Append (Res, "        off += n;");
                              Append (Res, LF);
                              Append (Res, "    }");
                              Append (Res, LF);
                           when Repeat =>
                              Emit_Repeat (A, "    ", "return 0");
                        end case;
                     end loop;
                     Append (Res, "    return off;");
                     Append (Res, LF);
                  else
                     --  Alternation: try each branch, keep the longest match.
                     Append (Res, "    var best: usize = 0;");
                     Append (Res, LF);
                     declare
                        Br : Natural := 0;
                     begin
                        for B of DNF loop
                           Br := Br + 1;
                           Append (Res, "    br" & Img (Br) & ": {");
                           Append (Res, LF);
                           Append (Res, "        var off: usize = 0;");
                           Append (Res, LF);
                           for A of B loop
                              case A.Kind is
                                 when Single =>
                                    Append (Res, "        {");
                                    Append (Res, LF);
                                    Append (Res, "            var c: u32 = 0;");
                                    Append (Res, LF);
                                    Append (Res, "            const n = decode_utf8(s, pos + off, len, &c);");
                                    Append (Res, LF);
                                    Append (Res, "            if (n == 0 or !"
                                      & Range_Cond (A.Lo, A.Hi) & ") break :br"
                                      & Img (Br) & ";");
                                    Append (Res, LF);
                                    Append (Res, "            off += n;");
                                    Append (Res, LF);
                                    Append (Res, "        }");
                                    Append (Res, LF);
                                 when Repeat =>
                                    Emit_Repeat (A, "        ", "break :br" & Img (Br));
                              end case;
                           end loop;
                           Append (Res, "        if (off > best) best = off;");
                           Append (Res, LF);
                           Append (Res, "    }");
                           Append (Res, LF);
                        end loop;
                     end;
                     Append (Res, "    return best;");
                     Append (Res, LF);
                  end if;
                  Append (Res, "}");
                  Append (Res, LF);
                  Append (Res, LF);
                  end if;
               end;
            end if;
         end loop;

      end;

      Append (Res, Hosted_Code);
      return To_String (Res);
   end Emit_Parser;

   function Emit_Lexer (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      R  : constant HBNF_Grammar.Rule := Rules (1);
      P  : constant HBNF_Grammar.Element_Vectors.Vector := R.Pattern;
      Root_T : constant String :=
        (if Is_Char_Rule (Rules, To_String (R.Name))
         then Zig_Type (To_String (R.Name))
         elsif Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            (if P (1).Kind = HBNF_Grammar.Name then
               "[]" & (if Scalar_Zig_Type (To_String (P (1).Name)) /= "" then
                         Scalar_Zig_Type (To_String (P (1).Name))
                       else Zig_Type (To_String (P (1).Name)))
             else "[]" & Zig_Type (To_String (R.Name)) & "Entry")
         else Zig_Type (To_String (R.Name)));
      --  parse_text: the whole text through the root rule.
      function Parse_Text_Src return String is
         V : Mustache.Context := Mustache.View;
      begin
         Mustache.Put (V, "root_type", Root_T);
         Mustache.Put (V, "reset",
           (if Is_Hosted and then Hosted_Acts
            then "    bnf_warning_list = &.{};" & LF else ""));
         Mustache.Put (V, "actions",
           (if Is_Hosted and then Hosted_Acts then
              "    var h_ = Hooks{ .alloc = alloc };" & LF
              & "    bnf_act_root(&out, &h_) catch {" & LF
              & "        const n = @min(h_.msg.len, err.len - 1);" & LF
              & "        @memcpy(err[0..n], h_.msg[0..n]);" & LF
              & "        err[n] = 0;" & LF
              & "        err_line.* = 0;" & LF
              & "        err_col.* = 0;" & LF
              & "        return error.Invalid;" & LF
              & "    };" & LF
              & "    bnf_warning_list = h_.warnings.items;" & LF
            else ""));
        Mustache.Put (V, "root_fn",
           "parse_" & Zig_Snake (To_String (R.Name)));
         --  The root skips whitespace around itself if its file does.
         Mustache.Put (V, "lead_ws",
           (if R.Whitespace /= Null_Unbounded_String
            then "    p.skip_ws();" & LF else ""));
         Mustache.Put (V, "trail_ws",
           (if R.Whitespace /= Null_Unbounded_String
            then "    p.skip_ws();" & LF else ""));
         return Mustache.Render_File ("zig_parse_text", V);
      end Parse_Text_Src;

      Lexer  : constant String := Parse_Text_Src;
   begin
      if Epilogue ("Zig") = "" then
         return Lexer;
      else
         return Lexer & LF & Epilogue ("Zig");
      end if;
   end Emit_Lexer;

   function Emit_Conf (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      Root_T : constant String := Zig_Type (To_String (Rules (1).Name));
   begin
      return Render_Root ("conf_zig", Root_T);
   end Emit_Conf;

end HBNF_Zig;
