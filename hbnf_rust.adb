pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Mustache;
with HBNF_C;
with HBNF_Compilable;
with HBNF_Lookahead;

package body HBNF_Rust is

   --  A whole-file template whose one hole is the root rule's type: the
   --  `@ROOT_TYPE@` substitution is now `{{&root_type}}` (RFCPLAN step 3b).
   function Render_Root (Name, Root_T : String) return String is
      V : Mustache.Context := Mustache.View;
   begin
      Mustache.Put (V, "root_type", Root_T);
      return Mustache.Render_File (Name, V);
   end Render_Root;

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;
   use HBNF_Compilable;

   subtype U is Unbounded_String;

   LF : constant Character := ASCII.LF;

   package String_Vectors is new Ada.Containers.Vectors (Positive, U);

   --  The Rust type for a built-in core rule, or "" if not a core scalar.
   function Scalar_Rust_Type (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "String";
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
   end Scalar_Rust_Type;

   --  A snake_case identifier from a schema name ('-' -> '_', upper -> lower).
   function Rust_Snake (S : String) return String is
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
   end Rust_Snake;

   --  A PascalCase type name from a schema name ('-' / '_' split a word).
   function Rust_Type (S : String) return String is
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
      --  A rule named after a std prelude type would shadow it and break the
      --  generated parser (which uses Option/Result/Vec/String unqualified).
      declare
         T : constant String := To_String (Buf);
      begin
         if T = "Option" or else T = "Result" or else T = "String"
           or else T = "Vec" or else T = "Box"
         then
            return T & "_";
         end if;
         return T;
      end;
   end Rust_Type;

   --  A field name: snake_case, with a "_" suffix if it is a Rust keyword.
   function Rust_Field (S : String) return String is
      N : constant String := Rust_Snake (S);
   begin
      if N = "as" or else N = "break" or else N = "const"
        or else N = "continue" or else N = "crate" or else N = "dyn"
        or else N = "else" or else N = "enum" or else N = "extern"
        or else N = "false" or else N = "fn" or else N = "for"
        or else N = "if" or else N = "impl" or else N = "in"
        or else N = "let" or else N = "loop" or else N = "match"
        or else N = "mod" or else N = "move" or else N = "mut"
        or else N = "pub" or else N = "ref" or else N = "return"
        or else N = "self" or else N = "static" or else N = "struct"
        or else N = "super" or else N = "trait" or else N = "true"
        or else N = "type" or else N = "unsafe" or else N = "use"
        or else N = "where" or else N = "while" or else N = "async"
        or else N = "await" or else N = "box" or else N = "do"
        or else N = "final" or else N = "macro" or else N = "override"
        or else N = "priv" or else N = "try" or else N = "typeof"
        or else N = "unsized" or else N = "virtual" or else N = "yield"
      then
         return N & "_";
      end if;
      return N;
   end Rust_Field;

   --  Escape a literal for a Rust string literal.  Rust's `\x` takes exactly
   --  two hex digits (unlike C), so `\xNN` is safe to emit for any non-ASCII-
   --  printable byte; the named controls use their short forms.
   function Rust_Escape (S : String) return String is
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
   end Rust_Escape;

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
   --  through Rust_Type and then any non-alphanumeric folded to '_', so
   --  "tlsv1.0" -> "Tlsv1_0".  A name that is empty, all '_', or begins with
   --  a digit (pure punctuation like "*" or "!=") becomes `Op<pos>`; and
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
            Base : constant String := Fold (Rust_Type (To_String (Lits (I))));
            N    : U;
         begin
            if Base = "" or else (for all C of Base => C = '_')
              or else Base (Base'First) in '0' .. '9'
            then
               N := To_Unbounded_String ("Op" & Img (I));
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
   Ast_On       : Boolean := False;   --  --ast: the walker and the dump
   Spans_On     : Boolean := False;   --  --spans: where each node is in the text
   Parents_On   : Boolean := False;   --  --parents: which node holds each node
   Hosted_Types : U;
   Hosted_Code  : U;
   Hosted_Walks : U;                --  the bit rules with a walk_<rule>, space-separated
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

   procedure Set_Parents (On : Boolean) is
   begin
      Parents_On := On;
   end Set_Parents;

   procedure Set_Spans (On : Boolean) is
   begin
      Spans_On := On;
   end Set_Spans;

   procedure Set_Hosted (Types, Code : String; Walks : String := "") is
   begin
      Hosted_Walks := To_Unbounded_String (" " & Walks & " ");
      Hosted_Acts  := Walks /= "";
      Hosted_Types := To_Unbounded_String (Types);
      Hosted_Code  := To_Unbounded_String (Code);
      Is_Hosted := True;
   end Set_Hosted;

   function Type_Name (Rule : String) return String is (Rust_Type (Rule));
   function Parse_Fn (Rule : String) return String is
     ("parse_" & Rust_Snake (Rule));
   function Scan_Fn (Rule : String) return String is
     ("scan_" & Rust_Snake (Rule));

   --  The Rust type a rule reference denotes: a core scalar inlines; any
   --  other reference resolves to the referenced rule's own type name.
   function Rust_Type_Of (Rules : Rule_Vectors.Vector; Ref : String)
     return String is
      S : constant String := Scalar_Rust_Type (Ref);
   begin
      if S /= "" then
         return S;
      end if;
      if Find (Rules, Ref) = 0 and then not HBNF_Grammar.Is_Wire_Rule (Ref) then
         raise Parse_Error with "undefined rule: " & HBNF_Grammar.Spelled (Ref)
           & (if HBNF_Grammar.Spelled (Ref) /= Ref then ", which no `::=` defines" else "");
      end if;
      return Rust_Type (Ref);
   end Rust_Type_Of;

   --  The underlying scalar Rust type a rule name resolves to, chasing
   --  single-name aliases and jets to their target (so `str | word` and
   --  `ipv4 | ipv6` both collapse to `String`).  "" if not scalar.
   function Resolve_Type
     (Rules : Rule_Vectors.Vector; N : String; Depth : Natural := 0)
     return String is
      C : constant String := Scalar_Rust_Type (N);
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
               return "String";
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
   --  the same scalar Rust type, that type (a scalar union); else "".
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
         --  A character-level rule compiles to a scanner + token; its value
         --  is the matched text, so it is a scalar string.
         return (Kind => Scalar,
                 Inline_Type => To_Unbounded_String ("String"));
      end if;
      if R.Jet_Code /= Null_Unbounded_String then
         --  A jet reads its own token kind and yields the matched text.
         return (Kind => Scalar,
                 Inline_Type => To_Unbounded_String ("String"));
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
                           (Rust_Type_Of (Rules, To_String (E.Name))));
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
                       Inline_Type => To_Unbounded_String ("String"));
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


   --  The by-value edges of the tree-type graph, for the one cycle detector
   --  in HBNF_Compilable; the edges it picks to make indirect come back.
   function Back_Edges_Rust (Rules : Rule_Vectors.Vector)
     return HBNF_Compilable.Edge_Vectors.Vector
   is
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      --  A struct is embedded by value; a list is a `Vec`, which is heap, so
      --  only structs impose a by-value order.
      function Is_By_Value (Info : Rule_Info) return Boolean is
        (Info.Kind = Struct);

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
      --  scalar's alias are edges: a list field holds a `Vec`, which is heap,
      --  so it is indirect and imposes no order.
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
   end Back_Edges_Rust;

   --  True when (Owner, Member) is a back edge: that field is emitted
   --  indirectly.  A member name is unique within its struct, so the pair
   --  names the edge.
   function Is_Back (Backs : HBNF_Compilable.Edge_Vectors.Vector;
                     Owner : Natural; Member : String) return Boolean is
   begin
      for E of Backs loop
         if E.Owner = Owner and then To_String (E.Member) = Member then
            return True;
         end if;
      end loop;
      return False;
   end Is_Back;

   --  The rule a back edge points at, or 0 when (Owner, Member) is not one.
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

   --  With --writer, a rule with alternatives records the one it took
   --  (`_alt`, from 1): a struct whose pattern has a top-level alternation, and
   --  a list entry that is a group with one.  The writer needs it; the C tree
   --  has the same.
   function Struct_Alt (R : Rule; Info : Rule_Info) return Boolean is
     ((Writer_On or else Ast_On) and then Info.Kind = Struct
      and then Natural (R.Pattern.Length) > 1
      and then (for some X of R.Pattern => X.Kind = Alt));

   function Entry_Alt (R : Rule; Info : Rule_Info) return Boolean is
     ((Writer_On or else Ast_On) and then Info.Kind = List
      and then not Info.Elem_Members.Is_Empty
      and then R.Left_Bases = 0
      and then Natural (R.Pattern.Length) = 1
      and then R.Pattern (1).Kind = Group
      and then (for some X of R.Pattern (1).Items => X.Kind = Alt));

   --  With --spans a struct and a list entry record where they are in the text
   --  (`_pos`, `_end`, byte offsets; the blanks before a node are not in it).
   function Has_Span (Info : Rule_Info) return Boolean is
     (Spans_On and then (Info.Kind = Struct
                         or else (Info.Kind = List and then not Info.Elem_Members.Is_Empty)));

   function Emit (Rules : Rule_Vectors.Vector) return String is

      N : constant Natural := Natural (Rules.Length);

      Infos : Info_Vectors.Vector;

      --  The fields that break a cycle, emitted `Option<Box<T>>`.
      Backs : constant HBNF_Compilable.Edge_Vectors.Vector :=
        Back_Edges_Rust (Rules);

      function Emit_Rule (Idx : Natural; Info : Rule_Info) return String is
         R    : constant Rule := Rules (Idx);
         Base : constant String := Rust_Type (To_String (R.Name));
         Buf  : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append_Comment (Buf, To_String (R.Leading_Comment));
         end if;

         case Info.Kind is
            when Scalar =>
               --  A rule whose name already names its resolved type (e.g.
               --  `string` -> `String`) is that type; a self-alias `type
               --  String = String` would shadow std and is omitted.
               if Base /= To_String (Info.Inline_Type) then
                  declare
                     V : Mustache.Context := Mustache.View;
                  begin
                     Mustache.Put (V, "name", Base);
                     Mustache.Put (V, "type", To_String (Info.Inline_Type));
                     Append (Buf, Mustache.Render_File ("rust_scalar", V));
                  end;
                  Append (Buf, LF);
               end if;
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
                       (Row, "init",
                        Mustache.New_Scalar (Enum_Init (Vals, Ord, J)));
                     --  `#[default]` goes on the first variant only: the two
                     --  item templates became one `{{#first}}` section.
                     if J = 1 then
                        Mustache.Insert (Row, "first", Mustache.New_Scalar ("1"));
                     end if;
                     Mustache.Append (Items, Row);
                     end;
                  end loop;
                  Mustache.Put (V, "name", Base);
                  Mustache.Put (V, "items", Items);
                  Append (Buf, Mustache.Render_File ("rust_enum", V));
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
                        Mustache.New_Scalar (Rust_Field (To_String (M.Name))));
                     --  A back edge is the one field that holds its subtree
                     --  behind a pointer.  `Option`, because a struct
                     --  derives Default and `Box<T>::default()` would
                     --  recurse without end; `None` is the empty field.
                     Mustache.Insert
                       (Row, "type",
                        Mustache.New_Scalar
                          (if M.Is_List
                           then "Vec<" & Rust_Type_Of (Rules, To_String (M.Name)) & ">"
                           elsif Is_Back (Backs, Idx, To_String (M.Name))
                           then "Option<Box<"
                                & Rust_Type_Of (Rules, To_String (M.Name)) & ">>"
                           else Rust_Type_Of (Rules, To_String (M.Name))));
                     Mustache.Append (Items, Row);
                  end loop;
                  if Struct_Alt (R, Info) then
                     Row := Mustache.New_Map;
                     Mustache.Insert (Row, "field", Mustache.New_Scalar ("_alt"));
                     Mustache.Insert (Row, "type", Mustache.New_Scalar ("u16"));
                     Mustache.Append (Items, Row);
                  end if;
                  if Has_Span (Info) then
                     for F in 1 .. 2 loop
                        Row := Mustache.New_Map;
                        Mustache.Insert (Row, "field", Mustache.New_Scalar (if F = 1 then "_pos" else "_end"));
                        Mustache.Insert (Row, "type", Mustache.New_Scalar ("usize"));
                        Mustache.Append (Items, Row);
                     end loop;
                  end if;
                  Mustache.Put (V, "name", Base);
                  Mustache.Put (V, "items", Items);
                  Append (Buf, Mustache.Render_File ("rust_struct", V));
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

      --  A top-level list rule: a `Vec<T>` alias.  A group element becomes a
      --  named `BaseEntry` struct first.
      function Emit_List (Idx : Natural; Info : Rule_Info) return String is
         R    : constant Rule := Rules (Idx);
         Base : constant String := Rust_Type (To_String (R.Name));
         Buf  : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append_Comment (Buf, To_String (R.Leading_Comment));
         end if;

         if Info.Elem_Members.Is_Empty then
            if Info.Elem_Name = Null_Unbounded_String then
               declare
                  V : Mustache.Context := Mustache.View;
               begin
                  Mustache.Put (V, "name", Base);
                  Append (Buf, Mustache.Render_File ("rust_list_bytes", V));
               end;
            else
               declare
                  V : Mustache.Context := Mustache.View;
               begin
                  Mustache.Put (V, "name", Base);
                  Mustache.Put
                    (V, "type", Rust_Type_Of (Rules, To_String (Info.Elem_Name)));
                  Append (Buf, Mustache.Render_File ("rust_list_simple", V));
               end;
            end if;
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
                     Mustache.New_Scalar (Rust_Field (To_String (M.Name))));
                  Mustache.Insert
                    (Row, "type",
                     Mustache.New_Scalar (Rust_Type_Of (Rules, To_String (M.Name))));
                  Mustache.Append (Items, Row);
               end loop;
               if Entry_Alt (Rules (Idx), Info) then
                  Row := Mustache.New_Map;
                  Mustache.Insert (Row, "field", Mustache.New_Scalar ("_alt"));
                  Mustache.Insert (Row, "type", Mustache.New_Scalar ("u16"));
                  Mustache.Append (Items, Row);
               end if;
               if Has_Span (Info) then
                  for F in 1 .. 2 loop
                     Row := Mustache.New_Map;
                     Mustache.Insert (Row, "field", Mustache.New_Scalar (if F = 1 then "_pos" else "_end"));
                     Mustache.Insert (Row, "type", Mustache.New_Scalar ("usize"));
                     Mustache.Append (Items, Row);
                  end loop;
               end if;
               Mustache.Put (V, "name", Base);
               Mustache.Put (V, "items", Items);
               Append (Buf, Mustache.Render_File ("rust_list_entry", V));
            end;
         end if;
         Append (Buf, LF);

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " // " & To_String (R.Trailing_Comment));
            Append (Buf, LF);
         end if;
         return To_String (Buf);
      end Emit_List;

      --  Emit AST walk (visit) and transform (fold) helpers, syn-style: a
      --  `Visitor` and a `Folder` trait with a defaulted method per composite
      --  type, plus visit_<rule>/fold_<rule> free functions that do the
      --  structural recursion.  visit_ is pre-order and read-only; fold_
      --  rebuilds bottom-up.  A scalar or enum member (and a Vec<scalar>) is a
      --  leaf and is not recursed into.
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
         --  or "" when the element is a scalar/enum leaf: a group element
         --  becomes `<snake>_entry`, a single-name struct element that struct.
         function Elem_Fn (Name : String) return String is
            J    : constant Natural := Find (Rules, Name);
            Info : constant Rule_Info := Infos (J);
         begin
            if J = 0 then
               return "";
            end if;
            if not Info.Elem_Members.Is_Empty then
               return Rust_Snake (Name) & "_entry";
            elsif Info.Elem_Name /= Null_Unbounded_String
              and then Ref_Kind (To_String (Info.Elem_Name)) = Struct
            then
               return Rust_Snake (To_String (Info.Elem_Name));
            else
               return "";
            end if;
         end Elem_Fn;

         --  True when a member Name recurses: a struct, or a list whose
         --  element is itself composite.
         function Recurses (Name : String) return Boolean is
         begin
            case Ref_Kind (Name) is
               when Struct => return True;
               when List => return Elem_Fn (Name) /= "";
               when others => return False;
            end case;
         end Recurses;

         --  Back is the rule a back edge points at, or 0.  The box holds that
         --  rule whatever the member names, so it is walked through `Back`
         --  rather than through the member's own kind, which for a member
         --  naming a scalar alias (`expr = prim`) is not Struct.
         procedure Visit_Field
           (Name : String; Back : Natural; Buf : in out U; Ind : String) is
            F : constant String := Rust_Field (Name);
         begin
            if Back > 0 then
               Append (Buf, Ind & "if let Some(" & F & ") = &n." & F
                 & " { visit_" & Rust_Snake (To_String (Rules (Back).Name))
                 & "(" & F & ", v); }");
               Append (Buf, LF);
               return;
            end if;
            case Ref_Kind (Name) is
               when Struct =>
                  Append (Buf, Ind & "visit_" & Rust_Snake (Name)
                    & "(&n." & F & ", v);");
                  Append (Buf, LF);
               when List =>
                  declare
                     E : constant String := Elem_Fn (Name);
                  begin
                     if E /= "" then
                        Append (Buf, Ind & "for e in &n." & F & " { visit_"
                          & E & "(e, v); }");
                        Append (Buf, LF);
                     end if;
                  end;
               when others =>
                  null;
            end case;
         end Visit_Field;

         procedure Fold_Field
           (Name : String; Back : Natural; Buf : in out U; Ind : String) is
            F : constant String := Rust_Field (Name);
         begin
            if Back > 0 then
               Append (Buf, Ind & "let " & F & " = " & F
                 & ".map(|b| Box::new(fold_"
                 & Rust_Snake (To_String (Rules (Back).Name)) & "(*b, f)));");
               Append (Buf, LF);
               return;
            end if;
            case Ref_Kind (Name) is
               when Struct =>
                  Append (Buf, Ind & "let " & F & " = fold_"
                    & Rust_Snake (Name) & "(" & F & ", f);");
                  Append (Buf, LF);
               when List =>
                  declare
                     E : constant String := Elem_Fn (Name);
                  begin
                     if E /= "" then
                        Append (Buf, Ind & "let " & F & " = " & F
                          & ".into_iter().map(|e| fold_" & E
                          & "(e, f)).collect::<Vec<_>>();");
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
            Has_Child : Boolean := False;
            Has_Alt_Field : constant Boolean :=
              Struct_Alt (Rules (Owner), Infos (Owner))
              or else Entry_Alt (Rules (Owner), Infos (Owner));
            Extra : constant String :=
              (if Has_Alt_Field then "_alt" else "")
              & (if Has_Span (Infos (Owner))
                 then (if Has_Alt_Field then ", " else "") & "_pos, _end" else "");
         begin
            for M of Members loop
               if Recurses (To_String (M.Name))
                 or else Back_Target (Backs, Owner, To_String (M.Name)) > 0
               then
                  Has_Child := True;
               end if;
            end loop;

            Append (Buf, "pub fn visit_" & Fn & "(n: &" & Type_Name
              & ", v: &mut impl Visitor) {");
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

            Append (Buf, "pub fn fold_" & Fn & "(n: " & Type_Name
              & ", f: &mut impl Folder) -> " & Type_Name & " {");
            Append (Buf, LF);
            if not Has_Child then
               Append (Buf, "    f.fold_" & Fn & "(n)");
            else
               Append (Buf, "    let " & Type_Name & " { ");
               declare
                  First : Boolean := True;
               begin
                  for M of Members loop
                     if not First then
                        Append (Buf, ", ");
                     end if;
                     Append (Buf, Rust_Field (To_String (M.Name)));
                     First := False;
                  end loop;
               end;
               if Extra /= "" then
                  Append (Buf, (if Members.Is_Empty then "" else ", ") & Extra);
               end if;
               Append (Buf, " } = n;");
               Append (Buf, LF);
               for M of Members loop
                  Fold_Field
                    (To_String (M.Name),
                     Back_Target (Backs, Owner, To_String (M.Name)), Buf, "    ");
               end loop;
               Append (Buf, "    let n = " & Type_Name & " { ");
               declare
                  First : Boolean := True;
               begin
                  for M of Members loop
                     if not First then
                        Append (Buf, ", ");
                     end if;
                     Append (Buf, Rust_Field (To_String (M.Name)));
                     First := False;
                  end loop;
               end;
               if Extra /= "" then
                  Append (Buf, (if Members.Is_Empty then "" else ", ") & Extra);
               end if;
               Append (Buf, " };");
               Append (Buf, LF);
               Append (Buf, "    f.fold_" & Fn & "(n)");
            end if;
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
            Base : constant String := Rust_Type (To_String (Rules (Idx).Name));
         begin
            if Info.Kind = Struct then
               return Base;
            else
               return Base & "Entry";
            end if;
         end Node_Type;

         function Node_Fn (Idx : Natural) return String is
            Info : constant Rule_Info := Infos (Idx);
            Base : constant String := Rust_Snake (To_String (Rules (Idx).Name));
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

      begin
         Append (Buf, "// ---- AST traversal (visit) and transform (fold) ----");
         Append (Buf, LF);

         Append (Buf, "pub trait Visitor {");
         Append (Buf, LF);
         for I in 1 .. N loop
            if Is_Node (I) then
               Append (Buf, "    fn visit_" & Node_Fn (I)
                 & "(&mut self, _n: &" & Node_Type (I) & ") {}");
               Append (Buf, LF);
            end if;
         end loop;
         Append (Buf, "}");
         Append (Buf, LF);
         Append (Buf, LF);

         Append (Buf, "pub trait Folder {");
         Append (Buf, LF);
         for I in 1 .. N loop
            if Is_Node (I) then
               Append (Buf, "    fn fold_" & Node_Fn (I)
                 & "(&mut self, n: " & Node_Type (I) & ") -> "
                 & Node_Type (I) & " { n }");
               Append (Buf, LF);
            end if;
         end loop;
         Append (Buf, "}");
         Append (Buf, LF);
         Append (Buf, LF);

         for I in 1 .. N loop
            if Is_Node (I) then
               Emit_Node (I, Node_Type (I), Node_Fn (I), Node_Members (I), Buf);
               Append (Buf, LF);
            end if;
         end loop;

         --  The %actions of the bit rules a text rule holds, run after the whole
         --  text has been read: bnf_act_<rule> walks a node, children first, and
         --  calls the walk_<bit rule> of each bit rule it holds.
         if Is_Hosted and then Hosted_Acts then
            declare
               function Walked (Name : String) return Boolean is
                 (Find (Rules, Name) = 0
                  and then Index (Hosted_Walks, " " & Name & " ") > 0);

               --  The struct or list a reference ends at, chasing scalar aliases.
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

               procedure Act_Stmt
                 (Name : String; Is_List : Boolean; Back : Natural;
                  Expr : String; Buf : in out U; Ind : String)
               is
                  L : constant Natural := Leaf (Name);

                  procedure Elems (E : String; Idx : Natural) is
                     Info : constant Rule_Info := Infos (Idx);
                  begin
                     if not Info.Elem_Members.Is_Empty then
                        Append (Buf, Ind & "for e in &" & E & " { bnf_act_"
                          & Rust_Snake (To_String (Rules (Idx).Name))
                          & "_entry(e, h)?; }" & LF);
                     elsif Info.Elem_Name /= Null_Unbounded_String then
                        declare
                           EN : constant String := To_String (Info.Elem_Name);
                           EL : constant Natural := Leaf (EN);
                        begin
                           if Walked (EN) then
                              Append (Buf, Ind & "for e in &" & E & " { walk_"
                                & EN & "(e, h)?; }" & LF);
                           elsif EL > 0 and then Infos (EL).Kind = Struct then
                              Append (Buf, Ind & "for e in &" & E & " { bnf_act_"
                                & Rust_Snake (To_String (Rules (EL).Name))
                                & "(e, h)?; }" & LF);
                           end if;
                        end;
                     end if;
                  end Elems;
               begin
                  if Back > 0 then
                     Append (Buf, Ind & "if let Some(c) = &" & Expr & " { bnf_act_"
                       & Rust_Snake (To_String (Rules (Back).Name)) & "(c, h)?; }" & LF);
                  elsif Walked (Name) then
                     if Is_List then
                        Append (Buf, Ind & "for e in &" & Expr & " { walk_"
                          & Name & "(e, h)?; }" & LF);
                     else
                        Append (Buf, Ind & "walk_" & Name & "(&" & Expr
                          & ", h)?;" & LF);
                     end if;
                  elsif L > 0 and then Infos (L).Kind = Struct then
                     if Is_List then
                        Append (Buf, Ind & "for e in &" & Expr & " { bnf_act_"
                          & Rust_Snake (To_String (Rules (L).Name)) & "(e, h)?; }" & LF);
                     else
                        Append (Buf, Ind & "bnf_act_"
                          & Rust_Snake (To_String (Rules (L).Name)) & "(&" & Expr
                          & ", h)?;" & LF);
                     end if;
                  elsif L > 0 and then Infos (L).Kind = List then
                     Elems (Expr, L);
                  end if;
               end Act_Stmt;

               procedure Act_Node
                 (Owner : Natural; Type_Name, Fn : String; Rep : Boolean;
                  Members : Member_Vectors.Vector; Buf : in out U) is
               begin
                  Append (Buf, "fn bnf_act_" & Fn & "(n: &" & Type_Name
                    & ", h: &mut Hooks) -> Result<(), String> {" & LF);
                  for M of Members loop
                     Act_Stmt (To_String (M.Name), Rep and then M.Is_List,
                               Back_Target (Backs, Owner, To_String (M.Name)),
                               "n." & Rust_Field (To_String (M.Name)), Buf, "    ");
                  end loop;
                  Append (Buf, "    Ok(())" & LF & "}" & LF & LF);
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
               declare
                  R : constant HBNF_Grammar.Rule := Rules (1);
                  P : constant HBNF_Grammar.Element_Vectors.Vector := R.Pattern;
                  Root_T : constant String :=
                    (if Is_Char_Rule (Rules, To_String (R.Name))
                     then Rust_Type (To_String (R.Name))
                     elsif Natural (P.Length) = 1
                       and then (P (1).Min /= 1 or else P (1).Max /= 1)
                     then
                        (if P (1).Kind = HBNF_Grammar.Name then
                           "Vec<" & (if Scalar_Rust_Type (To_String (P (1).Name)) /= "" then
                                       Scalar_Rust_Type (To_String (P (1).Name))
                                     else Rust_Type (To_String (P (1).Name))) & ">"
                         else "Vec<" & Rust_Type (To_String (R.Name)) & "Entry>")
                     else Rust_Type (To_String (R.Name)));
               begin
                  Append (Buf, "fn bnf_act_root(n: &" & Root_T
                    & ", h: &mut Hooks) -> Result<(), String> {" & LF);
                  Act_Stmt (To_String (R.Name), False, 0, "(*n)", Buf, "    ");
                  Append (Buf, "    Ok(())" & LF & "}" & LF & LF);
               end;
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

         procedure P (Ind : Natural; S : String) is
         begin
            Append (Buf, [1 .. 4 * Ind => ' ']);
            Append (Buf, S);
            Append (Buf, LF);
         end P;

         function Bad (Why : String) return String is
           ("w.badw(""" & Rust_Escape (Why) & """);");

         --  The scanner that reads a token of this rule, "None" if none is
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
               return (if Core_Ok ("str") then "Some(scan_str)" else "None");
            elsif Nm = "int" or else (Scalar_Rust_Type (Nm) /= ""
                                      and then Nm /= "word" and then Nm /= "atom"
                                      and then Nm /= "bool" and then Nm /= "flag")
            then
               return (if Core_Ok ("int") then "Some(scan_int)" else "None");
            elsif Nm = "word" or else Nm = "atom" or else Nm = "bool"
              or else Nm = "flag"
            then
               return (if Core_Ok ("word") then "Some(scan_word)" else "None");
            end if;
            if J = 0 or else Depth > 8 then
               return "None";
            end if;
            if Is_Char_Rule (Rules, Nm) then
               return "Some(scan_" & Rust_Snake (Nm) & ")";
            end if;
            if Rules (J).Jet_Code /= Null_Unbounded_String then
               return "Some(jet_" & Rust_Snake (Nm) & ")";
            end if;
            if Natural (Rules (J).Pattern.Length) = 1
              and then Rules (J).Pattern (1).Kind = Name
              and then Rules (J).Pattern (1).Min = 1
              and then Rules (J).Pattern (1).Max = 1
            then
               return Scan_Of (To_String (Rules (J).Pattern (1).Name), Depth + 1);
            end if;
            return "None";
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

         --  Write the value Expr (a place) of a name.
         procedure Value (Nm, Expr, Gap : String; Ind : Natural) is
            J : constant Natural := Find (Rules, Nm);
            T : constant String :=
              (if Is_Char_Rule (Rules, Nm) then "String" else Resolve_Type (Rules, Nm));
         begin
            if J = 0 and then Scalar_Rust_Type (Nm) = ""
              and then HBNF_Grammar.Is_Wire_Rule (Nm)
            then
               P (Ind, "match emit_bits_" & Nm & "(&" & Expr & ") {");
               P (Ind + 1, "Ok((b_, nb_)) => {");
               P (Ind + 2, "if nb_ % 8 != 0 { w.badw(""`" & Nm
                  & "` does not end on an octet, so it cannot be written as text""); }");
               P (Ind + 2, "else { w.put(&b_[..nb_ / 8]); }");
               P (Ind + 1, "}");
               P (Ind + 1, "Err(m_) => w.badw(&m_),");
               P (Ind, "}");
            elsif J > 0 and then Infos (J).Kind = Scalar
              and then not Rules (J).Pattern.Is_Empty
              and then (for all X of Rules (J).Pattern =>
                          X.Kind = Literal and then X.Min = 1 and then X.Max = 1)
            then
               --  a rule that is one literal: the literal is its value
               P (Ind, "w.lit(" & Gap & ", b"""
                  & Rust_Escape (Lit_Text (J)) & """);");
            elsif J > 0 and then Infos (J).Kind in Struct | List | Enum then
               P (Ind, "wr_" & Rust_Snake (Nm) & "(w, &" & Expr & ");");
            elsif T = "String" then
               P (Ind, "w." & (if Has_Str (Nm) then "str" else "tok") & "("
                  & Gap & ", " & Expr & ".as_bytes(), " & Scan_Of (Nm) & ");");
            elsif T = "bool" then
               P (Ind, "w.tok(" & Gap & ", if " & Expr
                  & " { b""yes"" } else { b""no"" }, " & Scan_Of ("word") & ");");
            elsif T'Length > 1 and then T (T'First) in 'i' | 'u' then
               P (Ind, "w.tok(" & Gap & ", format!(""{}"", " & Expr
                  & ").as_bytes(), " & Scan_Of ("int") & ");");
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
                  P (Ind, Bad ("an alternation inside a group is not recorded in a Rust tree, so it is not written yet"));
                  return;
               end if;
               --  one branch per alternative, chosen by the one the parser took
               declare
                  St : Natural := 1;
                  Br : Natural := 0;
                  Nn : constant Natural := Natural (Els.Length);
               begin
                  P (Ind, "match " & Acc & "_alt {");
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
                           P (Ind + 1, "}");
                        end;
                        St := K + 1;
                     end if;
                  end loop;
                  P (Ind + 1, "_ => { " & Bad ("no alternative was recorded (generate with --writer)") & " }");
                  P (Ind, "}");
               end;
               return;
            end if;
            for E of Els loop
               case E.Kind is
                  when Literal =>
                     P (Ind, "w.lit(" & Gap & ", b""" & Rust_Escape (To_String (E.Lit)) & """);");
                  when Name =>
                     declare
                        Nm : constant String := To_String (E.Name);
                        F  : constant String := Acc & Rust_Field (Nm);
                     begin
                        if E.Min /= 1 or else E.Max /= 1 then
                           P (Ind, "for e_ in &" & F & " {");
                           Value (Nm, "(*e_)", Gap, Ind + 1);
                           P (Ind, "}");
                        elsif Is_Back (Backs, Idx, Nm) then
                           P (Ind, "if let Some(c_) = &" & F & " {");
                           Value (Nm, "(*c_)", Gap, Ind + 1);
                           P (Ind, "}");
                        else
                           Value (Nm, F, Gap, Ind);
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
           (Rust_Snake (To_String (Rules (Idx).Name)));
      begin
         P (0, "// ---- write (the tree as text, canonical) ----");
         P (0, "type BnfScan = fn(&[u8], usize, usize) -> usize;");
         P (0, "struct BnfW {");
         P (1, "buf: Vec<u8>,");
         P (1, "last: u8,");
         P (1, "bad: Option<String>,");
         P (1, "pscan: Option<BnfScan>,");
         P (1, "ptxt: Vec<u8>,");
         P (0, "}");
         P (0, "");
         P (0, "impl BnfW {");
         P (1, "fn badw(&mut self, why: &str) {");
         P (2, "if self.bad.is_none() { self.bad = Some(why.to_string()); }");
         P (1, "}");
         P (0, "");
         P (1, "fn put(&mut self, s: &[u8]) {");
         P (2, "self.buf.extend_from_slice(s);");
         P (2, "if let Some(c) = s.last() { self.last = *c; }");
         P (1, "}");
         P (0, "");
         P (1, "fn delim(c: u8) -> bool {");
         P (2, "c != 0 && b""()[],;"".contains(&c)");
         P (1, "}");
         P (0, "");
         P (1, "// Would the item just written, with mid and s after it, still end where it");
         P (1, "// did when the grammar's own scanner reads it?");
         P (1, "fn fits(&self, mid: &[u8], s: &[u8]) -> bool {");
         P (2, "let mut t = self.ptxt.clone();");
         P (2, "t.extend_from_slice(mid);");
         P (2, "t.extend_from_slice(s);");
         P (2, "(self.pscan.unwrap())(&t, 0, t.len()) == self.ptxt.len()");
         P (1, "}");
         P (0, "");
         P (1, "// What goes between the last item and s: nothing, a blank or a newline, the");
         P (1, "// first that keeps the last item from reading on into s.");
         P (1, "fn between(&mut self, gap: bool, s: &[u8]) {");
         P (2, "if self.buf.is_empty() || s.is_empty() { return; }");
         P (2, "let a = self.last;");
         P (2, "let b = s[0];");
         P (2, "let pref: &[u8] = if gap && a > b' ' && b > b' ' && !Self::delim(a) && !Self::delim(b) { b"" "" } else { b"""" };");
         P (2, "if self.pscan.is_some() && a > b' ' {");
         P (3, "let c: [&[u8]; 3] = [pref, b"" "", b""\n""];");
         P (3, "let n = if gap { 3 } else { 1 };");
         P (3, "for x in &c[..n] {");
         P (4, "if self.fits(x, s) {");
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
         P (1, "fn text(&mut self, gap: bool, s: &[u8], scan: Option<BnfScan>) {");
         P (2, "self.between(gap, s);");
         P (2, "self.put(s);");
         P (2, "self.pscan = scan;");
         P (2, "if scan.is_some() {");
         P (3, "self.ptxt.clear();");
         P (3, "self.ptxt.extend_from_slice(s);");
         P (2, "}");
         P (1, "}");
         P (0, "");
         P (1, "fn lit(&mut self, gap: bool, s: &[u8]) {");
         P (2, "self.text(gap, s, None);");
         P (1, "}");
         P (0, "");
         P (1, "fn tok(&mut self, gap: bool, s: &[u8], scan: Option<BnfScan>) {");
         P (2, "self.text(gap, s, scan);");
         P (1, "}");
         P (0, "");
         P (1, "fn str(&mut self, gap: bool, s: &[u8], scan: Option<BnfScan>) {");
         P (2, "let mut t: Vec<u8> = vec![b'""'];");
         P (2, "for &c in s {");
         P (3, "if c == b'""' || c == b'\\' { t.push(b'\\'); }");
         P (3, "t.push(c);");
         P (2, "}");
         P (2, "t.push(b'""');");
         P (2, "self.text(gap, &t, scan);");
         P (1, "}");
         P (0, "}");
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
                     P (0, "fn wr_" & Fn & "(w: &mut BnfW, n: &" & Rust_Type (NM) & ") {");
                     P (1, "let _ = &n;");
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
                     P (0, "fn wr_" & Fn & "(w: &mut BnfW, n: &Vec<"
                        & (if R.Pattern (1).Kind = Group then Rust_Type (NM) & "Entry"
                           elsif Info.Elem_Name /= Null_Unbounded_String
                           then (if Scalar_Rust_Type (To_String (Info.Elem_Name)) /= ""
                                 then Scalar_Rust_Type (To_String (Info.Elem_Name))
                                 else Rust_Type (To_String (Info.Elem_Name)))
                           else "String") & ">) {");
                     P (1, "let _ = &n;");
                     if R.Left_Bases > 0 then
                        P (1, Bad ("a left-recursive list is not written yet"));
                     elsif R.Pattern (1).Kind = Group then
                        P (1, "for e_ in n {");
                        Elements (I, R.Pattern (1).Items, "e_.", Gap, 2,
                                  Entry_Alt (R, Info));
                        P (1, "}");
                     elsif Info.Elem_Name /= Null_Unbounded_String then
                        P (1, "for e_ in n {");
                        Value (To_String (Info.Elem_Name), "(*e_)", Gap, 2);
                        P (1, "}");
                     else
                        P (1, "for e_ in n { w.tok(" & Gap & ", e_.as_bytes(), None); }");
                     end if;
                     P (0, "}");
                     P (0, "");
                  when Enum =>
                     declare
                        Names : constant String_Vectors.Vector :=
                          Enum_Names (Info.Literals);
                     begin
                        P (0, "fn wr_" & Fn & "(w: &mut BnfW, v: &" & Rust_Type (NM) & ") {");
                        P (1, "match v {");
                        for K in 1 .. Natural (Info.Literals.Length) loop
                           P (2, Rust_Type (NM) & "::" & Rust_Type (NM) & "_"
                              & To_String (Names (K)) & " => w.lit(" & Gap & ", b"""
                              & Rust_Escape (To_String (Info.Literals (K))) & """),");
                        end loop;
                        P (2, "#[allow(unreachable_patterns)] _ => {}");
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
                 (if Infos (1).Kind = Struct then Rust_Type (To_String (R.Name))
                  elsif Natural (R.Pattern.Length) = 1
                    and then R.Pattern (1).Kind = Name
                    and then (R.Pattern (1).Min /= 1 or else R.Pattern (1).Max /= 1)
                  then
                     "Vec<" & (if Scalar_Rust_Type (To_String (R.Pattern (1).Name)) /= ""
                               then Scalar_Rust_Type (To_String (R.Pattern (1).Name))
                               else Rust_Type (To_String (R.Pattern (1).Name))) & ">"
                  else "Vec<" & Rust_Type (To_String (R.Name)) & "Entry>");
            begin
               P (0, "/// The tree as text, or why a node cannot be written.");
               P (0, "pub fn write_" & Ref_Name (1) & "(root: &" & Root_T
                  & ") -> Result<Vec<u8>, String> {");
               P (1, "let mut w = BnfW { buf: Vec::new(), last: 0, bad: None, pscan: None, ptxt: Vec::new() };");
               P (1, "wr_" & Ref_Name (1) & "(&mut w, root);");
               P (1, "match w.bad {");
               P (2, "Some(b) => Err(b),");
               P (2, "None => Ok(w.buf),");
               P (1, "}");
               P (0, "}");
               P (0, "");
            end;
         end if;
      end Emit_Writer;

      --  The tree as nodes (--ast): `Node` is any struct or list element of the
      --  tree, `node_walk` visits them (enter, leave, skip, stop), `node_kids`
      --  lists a node's members, and `node_dump` writes the S-expression C's
      --  node_dump writes, so a tree dumps the same in every language.  Plain
      --  Rust over the types above; the walker knows nothing of the grammar.
      procedure Emit_Ast (Buf : in out U) is

         procedure P (Ind : Natural; S : String) is
         begin
            Append (Buf, [1 .. 4 * Ind => ' ']);
            Append (Buf, S);
            Append (Buf, LF);
         end P;

         function Q (S : String) return String is ("""" & Rust_Escape (S) & """");

         function Walked_Kind (I : Natural) return Boolean is
           (Infos (I).Kind in Struct | List);

         --  The Rust type of one element of list rule I.
         function Elem_Type (I : Natural) return String is
            Info : constant Rule_Info := Infos (I);
         begin
            if not Info.Elem_Members.Is_Empty then
               return Rust_Type (To_String (Rules (I).Name)) & "Entry";
            elsif Info.Elem_Name /= Null_Unbounded_String then
               return Rust_Type_Of (Rules, To_String (Info.Elem_Name));
            end if;
            return "String";
         end Elem_Type;

         --  The struct or list a reference ends at, chasing scalar aliases.
         function Leaf (Ref : String) return Natural is
            J    : Natural := Find (Rules, Ref);
            Hops : Natural := 0;
         begin
            while J > 0 and then Hops < 20 and then Infos (J).Kind = Scalar loop
               Hops := Hops + 1;
               declare
                  Pt : constant Element_Vectors.Vector := Rules (J).Pattern;
               begin
                  if Natural (Pt.Length) = 1 and then Pt (1).Kind = Name
                    and then Pt (1).Min = 1 and then Pt (1).Max = 1
                  then
                     J := Find (Rules, To_String (Pt (1).Name));
                  else
                     J := 0;
                  end if;
               end;
            end loop;
            if J > 0 and then Hops < 20 and then Infos (J).Kind in Struct | List then
               return J;
            end if;
            return 0;
         end Leaf;

         function Variant (I : Natural) return String is
           (Rust_Type (To_String (Rules (I).Name)));

         --  Push the kid for member Nm, whose field is Expr; Base_Index is
         --  the first of its elements when it is a repeated reference.
         procedure Kid (Idx : Natural; Nm : String; Is_List : Boolean;
                        Expr : String; Ind : Natural)
         is
            L   : constant Natural := Leaf (Nm);
            Lbl : constant String := Q (HBNF_C.Member_Label (Nm));
            J   : constant Natural := Find (Rules, Nm);
            T   : constant String :=
              (if Is_Char_Rule (Rules, Nm) then "String" else Resolve_Type (Rules, Nm));

            procedure Push (Index, Val : String) is
            begin
               P (Ind, "v.push(Kid { name: " & Lbl & ", index: " & Index
                  & ", value: " & Val & " });");
            end Push;
         begin
            if Back_Target (Backs, Idx, Nm) > 0 then
               P (Ind, "if let Some(c) = &" & Expr & " {");
               Push ("None", "Val::Node(Node::" & Variant (Back_Target (Backs, Idx, Nm)) & "(c))");
               P (Ind, "}");
            elsif L > 0 and then Infos (L).Kind = Struct then
               if Is_List then
                  P (Ind, "for (i, e) in " & Expr & ".iter().enumerate() {");
                  Push ("Some(i)", "Val::Node(Node::" & Variant (L) & "(e))");
                  P (Ind, "}");
               else
                  Push ("None", "Val::Node(Node::" & Variant (L) & "(&" & Expr & "))");
               end if;
            elsif L > 0 and then Infos (L).Kind = List then
               P (Ind, "for (i, e) in " & Expr & ".iter().enumerate() {");
               Push ("Some(i)", "Val::Node(Node::" & Variant (L) & "(e))");
               P (Ind, "}");
            elsif J > 0 and then Infos (J).Kind = Enum then
               declare
                  Names : constant String_Vectors.Vector :=
                    Enum_Names (Infos (J).Literals);
                  RT    : constant String := Rust_Type (Nm);
               begin
                  P (Ind, "{");
                  P (Ind + 1, "let s = match " & Expr & " {");
                  for K in 1 .. Natural (Infos (J).Literals.Length) loop
                     P (Ind + 2, RT & "::" & RT & "_" & To_String (Names (K))
                        & " => " & Q (To_String (Infos (J).Literals (K))) & ",");
                  end loop;
                  P (Ind + 2, "#[allow(unreachable_patterns)] _ => ""?"",");
                  P (Ind + 1, "};");
                  Push ("None", "Val::Enum(s)");
                  P (Ind, "}");
               end;
            elsif T = "String" then
               if Is_List then
                  P (Ind, "for (i, e) in " & Expr & ".iter().enumerate() {");
                  Push ("Some(i)", "Val::Str(e)");
                  P (Ind, "}");
               else
                  Push ("None", "Val::Str(&" & Expr & ")");
               end if;
            elsif T = "bool" then
               Push ("None", "Val::Bool(" & Expr & ")");
            elsif T'Length > 1 and then T (T'First) = 'i' then
               Push ("None", "Val::Int(" & Expr & " as i64)");
            elsif T'Length > 1 and then T (T'First) = 'u' then
               Push ("None", "Val::UInt(" & Expr & " as u64)");
            end if;
         end Kid;

         --  The members of a node, all of them or those of the alternative it
         --  took.
         procedure Members
           (Idx : Natural; Alts_Of : Element_Vectors.Vector; Has_Alts : Boolean;
            All_Members : Member_Vectors.Vector; Bare : Boolean; Ind : Natural)
         is
         begin
            if not Has_Alts then
               for M of All_Members loop
                  Kid (Idx, To_String (M.Name), M.Is_List and then not Bare,
                       "x." & Rust_Field (To_String (M.Name)), Ind);
               end loop;
               return;
            end if;
            P (Ind, "match x._alt {");
            declare
               St : Natural := 1;
               Br : Natural := 0;
               Nn : constant Natural := Natural (Alts_Of.Length);
            begin
               for K in 1 .. Nn + 1 loop
                  if K > Nn or else Alts_Of (K).Kind = Alt then
                     Br := Br + 1;
                     declare
                        Sub  : Element_Vectors.Vector;
                        Ms   : Member_Vectors.Vector;
                        Lits : String_Vectors.Vector;
                        Hasa : Boolean := False;
                     begin
                        for J in St .. K - 1 loop
                           Sub.Append (Alts_Of (J));
                        end loop;
                        Collect (Sub, Ms, Lits, Hasa);
                        P (Ind + 1, Img (Br) & " => {");
                        for M of Ms loop
                           Kid (Idx, To_String (M.Name), M.Is_List and then not Bare,
                                "x." & Rust_Field (To_String (M.Name)), Ind + 2);
                        end loop;
                        P (Ind + 1, "}");
                     end;
                     St := K + 1;
                  end if;
               end loop;
            end;
            P (Ind + 1, "_ => {}");
            P (Ind, "}");
         end Members;

         function Has_Alts (I : Natural) return Boolean is
           (Struct_Alt (Rules (I), Infos (I)) or else Entry_Alt (Rules (I), Infos (I)));

         function Alt_Els (I : Natural) return Element_Vectors.Vector is
           (if Infos (I).Kind = Struct then Rules (I).Pattern
            else Rules (I).Pattern (1).Items);

      begin
         P (0, "// ---- the tree as nodes: walk and dump (--ast) ----");
         P (0, "#[derive(Clone, Copy)]");
         P (0, "pub enum Node<'a> {");
         for I in 1 .. N loop
            if Walked_Kind (I) then
               P (1, Variant (I) & "(&'a " & (if Infos (I).Kind = Struct
                                                 then Rust_Type (To_String (Rules (I).Name))
                                                 else Elem_Type (I)) & "),");
            end if;
         end loop;
         P (0, "}");
         P (0, "");
         P (0, "pub enum Val<'a> { Node(Node<'a>), Str(&'a str), Int(i64), UInt(u64), Bool(bool), Enum(&'static str) }");
         P (0, "/// A member of a node: its name, the place in a list if it is an element, and what it holds.");
         P (0, "pub struct Kid<'a> { pub name: &'static str, pub index: Option<usize>, pub value: Val<'a> }");
         P (0, "pub enum Walk { Continue, Skip, Stop }");
         P (0, "");
         P (0, "pub fn node_kind_name(n: Node) -> &'static str {");
         P (1, "match n {");
         for I in 1 .. N loop
            if Walked_Kind (I) then
               P (2, "Node::" & Variant (I) & "(_) => " & Q (To_String (Rules (I).Name)) & ",");
            end if;
         end loop;
         P (1, "}");
         P (0, "}");
         P (0, "");
         P (0, "/// Which alternative a node took, from 1; 0 for a node whose rule has none recorded.");
         P (0, "pub fn node_alt(n: Node) -> usize {");
         P (1, "match n {");
         for I in 1 .. N loop
            if Walked_Kind (I) and then Has_Alts (I) then
               P (2, "Node::" & Variant (I) & "(x) => x._alt as usize,");
            end if;
         end loop;
         P (2, "#[allow(unreachable_patterns)] _ => 0,");
         P (1, "}");
         P (0, "}");
         P (0, "");
         P (0, "pub fn node_alt_name(n: Node, alt: usize) -> &'static str {");
         P (1, "match n {");
         for I in 1 .. N loop
            if Walked_Kind (I) and then Has_Alts (I) then
               P (2, "Node::" & Variant (I) & "(_) => match alt {");
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
                     P (3, Img (B) & " => " & Q (HBNF_C.Alt_Label (Els, B)) & ",");
                  end loop;
               end;
               P (3, "_ => """",");
               P (2, "},");
            end if;
         end loop;
         P (2, "#[allow(unreachable_patterns)] _ => """",");
         P (1, "}");
         P (0, "}");
         P (0, "");
         P (0, "/// The members of a node, in the order the grammar has them (those of the alternative it took).");
         P (0, "pub fn node_kids<'a>(n: Node<'a>) -> Vec<Kid<'a>> {");
         P (1, "let mut v: Vec<Kid<'a>> = Vec::new();");
         P (1, "match n {");
         for I in 1 .. N loop
            if Walked_Kind (I) then
               declare
                  Info : constant Rule_Info := Infos (I);
               begin
                  P (2, "Node::" & Variant (I) & "(x) => {");
                  if Info.Kind = Struct then
                     Members (I, Alt_Els (I), Has_Alts (I), Info.Members, False, 3);
                  elsif not Info.Elem_Members.Is_Empty then
                     Members (I, Alt_Els (I), Has_Alts (I), Info.Elem_Members, True, 3);
                  elsif Info.Elem_Name /= Null_Unbounded_String then
                     declare
                        EN : constant String := To_String (Info.Elem_Name);
                        L  : constant Natural := Leaf (EN);
                     begin
                        if L > 0 and then Infos (L).Kind = Struct then
                           P (3, "v.push(Kid { name: " & Q (HBNF_C.Member_Label (EN))
                              & ", index: None, value: Val::Node(Node::" & Variant (L) & "(x)) });");
                        elsif Resolve_Type (Rules, EN) = "String" then
                           P (3, "v.push(Kid { name: " & Q (HBNF_C.Member_Label (EN))
                              & ", index: None, value: Val::Str(x) });");
                        else
                           P (3, "let _ = x;");
                        end if;
                     end;
                  else
                     P (3, "v.push(Kid { name: ""value"", index: None, value: Val::Str(x) });");
                  end if;
                  P (2, "}");
               end;
            end if;
         end loop;
         P (1, "}");
         P (1, "v");
         P (0, "}");
         P (0, "");
         P (0, "/// Enter and leave every node under n; enter answers Continue, Skip (no descent, no leave) or Stop.");
         P (0, "pub trait Walker {");
         P (1, "fn enter(&mut self, _n: Node) -> Walk { Walk::Continue }");
         P (1, "fn leave(&mut self, _n: Node) -> Walk { Walk::Continue }");
         P (0, "}");
         P (0, "");
         P (0, "/// False if the walk was stopped.");
         P (0, "pub fn node_walk(n: Node, w: &mut impl Walker) -> bool {");
         P (1, "match w.enter(n) {");
         P (2, "Walk::Stop => return false,");
         P (2, "Walk::Skip => return true,");
         P (2, "Walk::Continue => {}");
         P (1, "}");
         P (1, "for k in node_kids(n) {");
         P (2, "if let Val::Node(c) = k.value {");
         P (3, "if !node_walk(c, w) { return false; }");
         P (2, "}");
         P (1, "}");
         P (1, "!matches!(w.leave(n), Walk::Stop)");
         P (0, "}");
         P (0, "");
         P (0, "fn dump_into(s: &mut String, n: Node) {");
         P (1, "s.push('(');");
         P (1, "s.push_str(node_kind_name(n));");
         P (1, "let a = node_alt(n);");
         P (1, "if a != 0 { s.push('['); s.push_str(node_alt_name(n, a)); s.push(']'); }");
         P (1, "for k in node_kids(n) {");
         P (2, "s.push(' ');");
         P (2, "s.push_str(k.name);");
         P (2, "if let Some(i) = k.index { s.push_str(&format!(""[{}]"", i)); }");
         P (2, "s.push('=');");
         P (2, "match k.value {");
         P (3, "Val::Node(c) => dump_into(s, c),");
         P (3, "Val::Str(t) => {");
         P (4, "s.push('""');");
         P (4, "for c in t.chars() {");
         P (5, "if c == '""' || c == '\\' { s.push('\\'); }");
         P (5, "if c == '\n' { s.push_str(""\\n""); } else { s.push(c); }");
         P (4, "}");
         P (4, "s.push('""');");
         P (3, "}");
         P (3, "Val::Int(i) => s.push_str(&i.to_string()),");
         P (3, "Val::UInt(u) => s.push_str(&u.to_string()),");
         P (3, "Val::Bool(b) => s.push_str(if b { ""true"" } else { ""false"" }),");
         P (3, "Val::Enum(e) => s.push_str(e),");
         P (2, "}");
         P (1, "}");
         P (1, "s.push(')');");
         P (0, "}");
         P (0, "");
         P (0, "/// Two nodes are equal when their dumps are: same rules, alternatives, members and values.");
         P (0, "pub fn node_equal(a: Node, b: Node) -> bool { node_dump(a) == node_dump(b) }");
         P (0, "");
         P (0, "/// The S-expression of a node: (kind[alternative] member=value ...).");
         P (0, "pub fn node_dump(n: Node) -> String {");
         P (1, "let mut s = String::new();");
         P (1, "dump_into(&mut s, n);");
         P (1, "s");
         P (0, "}");
         P (0, "");
         if Spans_On then
            P (0, "/// Where a node is in the text: its first and last byte + 1 (the blanks before it are not in it).");
            P (0, "pub fn node_span(n: Node) -> Option<(usize, usize)> {");
            P (1, "match n {");
            for I in 1 .. N loop
               if Walked_Kind (I) then
                  declare
                     Info : constant Rule_Info := Infos (I);
                     L    : constant Natural :=
                       (if Info.Kind = List and then Info.Elem_Members.Is_Empty
                             and then Info.Elem_Name /= Null_Unbounded_String
                        then Leaf (To_String (Info.Elem_Name)) else 0);
                  begin
                     if Has_Span (Info) or else (L > 0 and then Has_Span (Infos (L))) then
                        P (2, "Node::" & Variant (I) & "(x) => Some((x._pos, x._end)),");
                     end if;
                  end;
               end if;
            end loop;
            P (2, "#[allow(unreachable_patterns)] _ => None,");
            P (1, "}");
            P (0, "}");
            P (0, "");
            P (0, "/// The line and the column, both from 1, of a byte offset of text.");
            P (0, "pub fn node_where(text: &str, pos: usize) -> (usize, usize) {");
            P (1, "let (mut l, mut c) = (1usize, 1usize);");
            P (1, "for (i, ch) in text.bytes().enumerate() {");
            P (2, "if i >= pos { break; }");
            P (2, "if ch == b'\n' { l += 1; c = 1; } else { c += 1; }");
            P (1, "}");
            P (1, "(l, c)");
            P (0, "}");
            P (0, "");
         end if;
         if Parents_On then
            P (0, "fn node_addr(n: Node) -> usize {");
            P (1, "match n {");
            for I in 1 .. N loop
               if Walked_Kind (I) then
                  P (2, "Node::" & Variant (I) & "(x) => x as *const _ as usize,");
               end if;
            end loop;
            P (1, "}");
            P (0, "}");
            P (0, "");
            P (0, "/// Which node holds each node (--parents): built by `link_<root>`, read by `parent`.");
            P (0, "pub struct Parents<'a> { map: std::collections::HashMap<(usize, &'static str), Node<'a>> }");
            P (0, "impl<'a> Parents<'a> {");
            P (1, "/// The node that holds n, or None for a root.");
            P (1, "pub fn parent(&self, n: Node) -> Option<Node<'a>> {");
            P (2, "self.map.get(&(node_addr(n), node_kind_name(n))).copied()");
            P (1, "}");
            P (0, "}");
            P (0, "fn link_into<'a>(map: &mut std::collections::HashMap<(usize, &'static str), Node<'a>>, n: Node<'a>) {");
            P (1, "for k in node_kids(n) {");
            P (2, "if let Val::Node(c) = k.value {");
            P (3, "map.insert((node_addr(c), node_kind_name(c)), n);");
            P (3, "link_into(map, c);");
            P (2, "}");
            P (1, "}");
            P (0, "}");
            P (0, "");
         end if;
         --  the whole tree
         declare
            R  : constant Rule := Rules (1);
            RN : constant String := Rust_Snake (To_String (R.Name));
         begin
            if Infos (1).Kind = Struct then
               P (0, "pub fn walk_" & RN & "(root: &" & Rust_Type (To_String (R.Name))
                  & ", w: &mut impl Walker) -> bool { node_walk(Node::" & Variant (1)
                  & "(root), w) }");
               P (0, "pub fn dump_" & RN & "(root: &" & Rust_Type (To_String (R.Name))
                  & ") -> String { node_dump(Node::" & Variant (1) & "(root)) }");
               if Parents_On then
                  P (0, "pub fn link_" & RN & "(root: &" & Rust_Type (To_String (R.Name))
                     & ") -> Parents<'_> {");
                  P (1, "let mut map = std::collections::HashMap::new();");
                  P (1, "link_into(&mut map, Node::" & Variant (1) & "(root));");
                  P (1, "Parents { map }");
                  P (0, "}");
               end if;
            elsif Infos (1).Kind = List then
               P (0, "pub fn walk_" & RN & "(root: &[" & Elem_Type (1)
                  & "], w: &mut impl Walker) -> bool {");
               P (1, "for e in root { if !node_walk(Node::" & Variant (1) & "(e), w) { return false; } }");
               P (1, "true");
               P (0, "}");
               if Parents_On then
                  P (0, "pub fn link_" & RN & "(root: &[" & Elem_Type (1) & "]) -> Parents<'_> {");
                  P (1, "let mut map = std::collections::HashMap::new();");
                  P (1, "for e in root { link_into(&mut map, Node::" & Variant (1) & "(e)); }");
                  P (1, "Parents { map }");
                  P (0, "}");
               end if;
               P (0, "pub fn dump_" & RN & "(root: &[" & Elem_Type (1) & "]) -> String {");
               P (1, "let mut s = String::from(""(" & To_String (R.Name) & """);");
               P (1, "for e in root { s.push(' '); dump_into(&mut s, Node::" & Variant (1) & "(e)); }");
               P (1, "s.push(')');");
               P (1, "s");
               P (0, "}");
            end if;
         end;
      end Emit_Ast;

      Res : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;

      Append (Res, "// generated by hbnf -- do not edit");
      Append (Res, LF);
      Append (Res, "#![allow(non_camel_case_types, dead_code)]");
      Append (Res, LF);
      Append (Res, LF);

      --  Rust needs no forward declarations or ordering: every rule emits in
      --  source order, and `Vec<T>` (heap) breaks any recursion a repetition
      --  introduces.
      for I in 1 .. N loop
         if Infos (I).Kind = List then
            Append (Res, Emit_List (I, Infos (I)));
         else
            Append (Res, Emit_Rule (I, Infos (I)));
         end if;
         Append (Res, LF);
      end loop;

      Emit_Walk (Res);
      Append (Res, LF);
      Append (Res, Hosted_Types);
      if Writer_On then
         Emit_Writer (Res);
      end if;
      if Ast_On then
         Emit_Ast (Res);
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

      --  The fields Emit declared `Option<Box<T>>`: the commit point boxes
      --  what it parsed.
      Backs : constant HBNF_Compilable.Edge_Vectors.Vector :=
        Back_Edges_Rust (Rules);

      function Is_Core (Name : String) return Boolean is
        (Scalar_Rust_Type (Name) /= "");

      function Has_Alt (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Alt then
               return True;
            end if;
         end loop;
         return False;
      end Has_Alt;

      --  The Rust type a rule reference denotes.
      function Rust_Type_Of (Ref : String) return String is
         S : constant String := Scalar_Rust_Type (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         return Rust_Type (Ref);
      end Rust_Type_Of;

      --  A human-readable description of a core scalar.
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

      --  The token kind a core scalar reads.
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
        ("scan_" & Rust_Snake (Core_Base (Name))
         & "(p.text.as_bytes(), p.pos, p.text.len())");

      --  The extra condition that rejects a matched bareword that is a
      --  keyword (`word` must not swallow a directive's keyword), and its
      --  positive form.  n is the matched length, the text starts at p.pos.
      function Scalar_Reject (Name : String) return String is
        (if Name = "atom" or else Name = "word"
         then " || is_keyword(&p.text[p.pos..p.pos + n])"
         else "");

      function Scalar_Guard (Name : String) return String is
        (if Name = "atom" or else Name = "word"
         then " && !is_keyword(&p.text[p.pos..p.pos + n])"
         else "");

      --  The Rust expression that converts the matched text into a core value.
      function Scalar_Value (Name : String) return String is
         Raw : constant String := "p.text[p.pos..p.pos + n]";
      begin
         if Name = "str" then
            return "str_value(&" & Raw & ")";
         elsif Name = "atom" or else Name = "word" then
            return Raw & ".to_string()";
         elsif Name = "bool" or else Name = "flag" then
            return "matches!(&" & Raw & ", ""yes"" | ""on"" | ""true"")";
         else
            return Raw & ".parse().unwrap()";
         end if;
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
      --  injects each as a C jet, and this backend has its own Rust for them.
      function Is_Builtin_Jet (Nm : String) return Boolean is
        (Nm = "word" or else Nm = "int" or else Nm = "str" or else Nm = "ws");

      --  The scanner a jet rule runs: the built-in one, or the stub for
      --  hand-written C.
      function Jet_Fn (Nm : String) return String is
        ((if Is_Builtin_Jet (Nm) then "scan_" else "jet_") & Rust_Snake (Nm));

      --  A list's element type: Vec<T> wraps the referenced rule's type (a
      --  plain reference) or the entry struct a grouped alternation builds.
      --  A group of literals only, `0*1( "log" )`: its list entries carry
      --  no field, so each is a String, as the list's type says.
      function Lit_Only (V : Element_Vectors.Vector) return Boolean is
        (for all X of V =>
           X.Kind /= HBNF_Grammar.Name
           and then (X.Kind /= HBNF_Grammar.Group or else Lit_Only (X.Items)));

      function Ret_Type (Idx : Natural) return String is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if Is_Char_Rule (Rules, To_String (R.Name)) then
            return Rust_Type (To_String (R.Name));
         end if;
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            if P (1).Kind = HBNF_Grammar.Name then
               return "Vec<" & Rust_Type_Of (To_String (P (1).Name)) & ">";
            elsif P (1).Kind = HBNF_Grammar.Group and then Lit_Only (P (1).Items)
            then
               return "Vec<String>";
            else
               return "Vec<" & Rust_Type (To_String (R.Name)) & "Entry>";
            end if;
         end if;
         return Rust_Type (To_String (R.Name));
      end Ret_Type;

      --  The condition that the code point (in `c`) lies in [Lo, Hi].  `c >= 0`
      --  is a useless comparison for an unsigned code point (rustc's
      --  -D unused-comparisons rejects it), so the lower bound is dropped when
      --  Lo = 0.  The upper bound is never useless: a permissive 4-byte decode
      --  can yield code points above 0x10FFFF.
      function Range_Cond (Lo, Hi : Natural) return String is
      begin
         if Lo = 0 then
            return "(c <= " & Img (Hi) & ")";
         else
            return "(c >= " & Img (Lo) & " && c <= " & Img (Hi) & ")";
         end if;
      end Range_Cond;

      procedure Emit_Seq
        (Owner : Natural;
         Els : Element_Vectors.Vector; First, Last : Natural;
         Dst  : String; Buf : in out U; Ind : String := "    ") is
         --  Whether this rule's file skips whitespace between elements
         --  (`whitespace none` says it does not).
         Skips : constant Boolean :=
           Rules (Owner).Whitespace /= Null_Unbounded_String;
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
                        Append (Buf, Ind
                          & (if E.No_Case and then Is_Keyword_Lit (Lit)
                             then "p.expect_word_nocase"
                             elsif E.No_Case then "p.expect_lit_nocase"
                             elsif Is_Keyword_Lit (Lit) then "p.expect_word"
                             else "p.expect_lit")
                          & "(""" & Rust_Escape (Lit) & """)?;");
                        Append (Buf, LF);
                     end;
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        --  A core scalar: run its scanner at the position and
                        --  convert the matched text.
                        declare
                           NM : constant String := To_String (E.Name);
                        begin
                           Append (Buf, Ind & "{ let n = " & Scan_Call (NM)
                             & "; if n == 0" & Scalar_Reject (NM)
                             & " { return Err(p.fail(""" & Core_Desc (NM)
                             & """)); } " & Dst & Rust_Field (NM) & " = "
                             & Scalar_Value (NM) & "; p.pos += n; }");
                           Append (Buf, LF);
                        end;
                     elsif Is_Char_Rule (Rules, To_String (E.Name)) then
                        --  A char-rule reference runs its scanner here and
                        --  yields the matched text.
                        declare
                           NM : constant String := To_String (E.Name);
                        begin
                           Append (Buf, Ind & "{ let n = scan_" & Rust_Snake (NM)
                             & "(p.text.as_bytes(), p.pos, p.text.len());"
                             & (if Can_Be_Empty (NM) then " "
                                else " if n == 0 { return Err(p.fail(""" & NM
                                     & """)); } ")
                             & Dst & Rust_Field (NM)
                             & " = p.text[p.pos..p.pos + n].to_string();"
                             & " p.pos += n; }");
                           Append (Buf, LF);
                        end;
                     elsif Is_Back (Backs, Owner, To_String (E.Name)) then
                        Append (Buf, Ind & Dst
                          & Rust_Field (To_String (E.Name)) & " = Some(Box::new(parse_"
                          & Rust_Snake (To_String (E.Name)) & "(p)?));");
                        Append (Buf, LF);
                     else
                        Append (Buf, Ind & Dst
                          & Rust_Field (To_String (E.Name)) & " = parse_"
                          & Rust_Snake (To_String (E.Name)) & "(p)?;");
                        Append (Buf, LF);
                     end if;
                  when Group =>
                     Emit_Seq (Owner, E.Items, 1, Natural (E.Items.Length), Dst, Buf,
                               Ind & "    ");
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
      --  Els.  Each branch runs inside a closure so its `?` failures return to
      --  the branch check; a failed branch restores p.pos and resets the struct
      --  (Reset), a successful one breaks out of the labelled `'alt` block.
      --  After the last branch fails, control falls through for the caller's
      --  own failure handling.
      procedure Emit_Alternation
        (Owner : Natural;
         Els : Element_Vectors.Vector; Acc, Reset : String;
         Buf : in out U; Ind : String := "    ") is
         N  : constant Natural := Natural (Els.Length);
         St : Natural := 1;
         Br : Natural := 0;
      begin
         for K in 1 .. N + 1 loop
            if K > N or else Els (K).Kind = Alt then
               Br := Br + 1;
               if Br > 1 then
                  Append (Buf, Ind & "p.pos = save;"
                    & (if Reset = "" then "" else " " & Reset & ";"));
                  Append (Buf, LF);
               end if;
               Append (Buf, Ind & "if (|| -> Result<(), ParseError> {");
               Append (Buf, LF);
               Emit_Seq (Owner, Els, St, K - 1, Acc, Buf, Ind & "    ");
               --  First match wins: this branch is taken only if the next
               --  code point can follow the choice.
               if K <= N and then Els (K).Kind = Alt and then Els (K).Guard /= 0
               then
                  declare
                     G : constant String := Natural'Image (Els (K).Guard);
                  begin
                     Append (Buf, Ind & "    { let sv = p.pos;"
                       & (if Rules (Owner).Whitespace /= Null_Unbounded_String
                          then " p.skip_ws();" else "")
                       & " let g = p.guard_" & G (G'First + 1 .. G'Last)
                       & "(); p.pos = sv; if !g { return Err(p.fail(""what "
                       & "can follow here"")); } }");
                     Append (Buf, LF);
                  end;
               end if;
               if (Writer_On or else Ast_On)
                 and then ((Acc = "r." and then Struct_Alt (Rules (Owner), Analyze (Rules, Owner)))
                           or else (Acc = "e." and then Entry_Alt (Rules (Owner), Analyze (Rules, Owner))))
               then
                  Append (Buf, Ind & "    " & Acc & "_alt = " & Img (Br) & ";");
                  Append (Buf, LF);
               end if;
               Append (Buf, Ind & "    Ok(())");
               Append (Buf, LF);
               Append (Buf, Ind & "})().is_ok() { break 'alt; }");
               Append (Buf, LF);
               St := K + 1;
            end if;
         end loop;
      end Emit_Alternation;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         RT : constant String := Rust_Type (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Is_Pure_Literal_Alt (P);
         SU : constant String :=
           (if not Is_List then Scalar_Union_Type (Rules, P) else "");

         --  True when the sequence assigns any field of `r`.  Only a rule
         --  reference does: a literal, a character range and an empty rule
         --  assign nothing (a group is assigned through, as Emit_Seq does).
         --  `r` must not be `mut` when nothing is assigned: rustc rejects it
         --  under `-D unused-mut`, which tests/portable.sh passes.
         function Assigns (Els : Element_Vectors.Vector) return Boolean is
         begin
            for E of Els loop
               if E.Kind = Name then
                  return True;
               elsif E.Kind = Group and then Assigns (E.Items) then
                  return True;
               end if;
            end loop;
            return False;
         end Assigns;
      begin
         if Is_Char_Rule (Rules, NM) or else R.Jet_Code /= Null_Unbounded_String
         then
            --  A char rule is a scanner: run it here and capture the text.  A
            --  jet is its built-in scanner, or the stub for hand-written C.
            Append (Buf, "    let n = "
              & (if R.Jet_Code /= Null_Unbounded_String
                 then Jet_Fn (NM) else "scan_" & Rust_Snake (NM))
              & "(p.text.as_bytes(), p.pos, p.text.len());");
            Append (Buf, LF);
            if R.Jet_Code /= Null_Unbounded_String
              or else not Can_Be_Empty (NM)
            then
               Append (Buf, "    if n == 0 { return Err(p.fail("""
                 & (if R.Jet_Code /= Null_Unbounded_String then "a " else "")
                 & NM & """)); }");
               Append (Buf, LF);
            end if;
            Append (Buf, "    let r = p.text[p.pos..p.pos + n].to_string(); p.pos += n;");
            Append (Buf, LF);
            Append (Buf, "    Ok(r)");
            Append (Buf, LF);
            return;
         end if;
         if Is_List then
            declare
               E : constant Element_Access := P (1);
               --  Repetition bounds, as the C backend enforces them.
               Max_Stop : constant String :=
                 (if E.Max >= 0
                  then (if E.Max = 0
                        --  `0x`: none at all.  `r.len() >= 0` is always true,
                        --  and rustc's -D warnings refuses the comparison.
                        then "if true { break"
                        else "if r.len() >= " & Img (Natural (E.Max))
                             & " { break")
                  else "");
            begin
               Append (Buf, "    let mut r = Vec::new();");
               Append (Buf, LF);
               if E.Min > 0 then
                  Append (Buf, "    let start = p.pos;");
                  Append (Buf, LF);
               end if;
               if E.Kind = Name then
                  --  PEG's `*`: stop at the end of input and at the first
                  --  element that fails, with the position restored, as C
                  --  does; the caller decides.
                  Append (Buf, "    loop {");
                  Append (Buf, LF);
                  if Max_Stop /= "" then
                     Append (Buf, "        " & Max_Stop & "; }");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "        let save = p.pos;");
                  Append (Buf, LF);
                  if R.Whitespace /= Null_Unbounded_String then
                     Append (Buf, "        p.skip_ws();");
                     Append (Buf, LF);
                  end if;
                  if not Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "        if p.pos >= p.text.len() { p.pos = save; break; }");
                     Append (Buf, LF);
                  end if;
                  if Is_Core (To_String (E.Name)) then
                     --  A list of a core type (`*word`): read the text in
                     --  place; there is no parse_ function for a core type.
                     Append (Buf, "        let n = " & Scan_Call (To_String (E.Name)) & ";");
                     Append (Buf, LF);
                     Append (Buf, "        if n == 0" & Scalar_Reject (To_String (E.Name))
                       & " { p.pos = save; break; }");
                     Append (Buf, LF);
                     Append (Buf, "        r.push(" & Scalar_Value (To_String (E.Name))
                       & "); p.pos += n;");
                     Append (Buf, LF);
                  else
                     Append (Buf, "        match parse_" & Rust_Snake (To_String (E.Name))
                       & "(p) { Ok(v) => r.push(v), Err(_) => { p.pos = save; break; } }");
                     Append (Buf, LF);
                  end if;
                  --  What is repeated can match nothing: an iteration that
                  --  did not advance would match the same nothing again.
                  if Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "        if p.pos == save { break; }");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "    }");
                  Append (Buf, LF);
               elsif E.Kind = Group then
                  Append (Buf, "    'list: loop {");
                  Append (Buf, LF);
                  if Max_Stop /= "" then
                     Append (Buf, "        " & Max_Stop & " 'list; }");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "        let save = p.pos;");
                  Append (Buf, LF);
                  Append (Buf, (if Lit_Only (E.Items)
                                then "        let e = String::new();"
                                else "        let mut e = " & RT & "Entry::default();"));
                  Append (Buf, LF);
                  Append (Buf, "        'alt: {");
                  Append (Buf, LF);
                  if R.Left_Bases > 0 then
                     --  Left recursion, as a loop: the first entry is a
                     --  base, each later one a tail.
                     Append (Buf, "            if r.is_empty() {");
                     Append (Buf, LF);
                     Emit_Alternation (Idx, Base_Branches (R), "e.",
                                       (if Lit_Only (E.Items) then ""
                                        else "e = " & RT & "Entry::default()"), Buf,
                                       "                ");
                     Append (Buf, "                p.pos = save; break 'list;");
                     Append (Buf, LF);
                     Append (Buf, "            }");
                     Append (Buf, LF);
                     Emit_Alternation (Idx, Tail_Branches (R), "e.",
                                       (if Lit_Only (E.Items) then ""
                                        else "e = " & RT & "Entry::default()"), Buf,
                                       "            ");
                  else
                     Emit_Alternation (Idx, E.Items, "e.",
                                       (if Lit_Only (E.Items) then ""
                                        else "e = " & RT & "Entry::default()"), Buf,
                                       "            ");
                  end if;
                  Append (Buf, "            p.pos = save; break 'list;");
                  Append (Buf, LF);
                  Append (Buf, "        }");
                  Append (Buf, LF);
                  if Has_Span (Analyze (Rules, Idx)) and then not Lit_Only (E.Items) then
                     if R.Whitespace /= Null_Unbounded_String then
                        Append (Buf, "        { let k = p.pos; p.pos = save; p.skip_ws(); e._pos = p.pos; p.pos = k; }");
                     else
                        Append (Buf, "        e._pos = save;");
                     end if;
                     Append (Buf, LF);
                     Append (Buf, "        e._end = p.pos;");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "        r.push(e);");
                  Append (Buf, LF);
                  if Repeated_Body_Nullable (Rules, E) then
                     Append (Buf, "        if p.pos == save { break; }");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "    }");
                  Append (Buf, LF);
               end if;
               if E.Min > 0 then
                  Append (Buf, "    if r.len() < " & Img (E.Min)
                    & " { p.pos = start; return Err(p.fail(""a " & NM & """)); }");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    Ok(r)");
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
                  B  : constant String := "p.text.as_bytes()";
                  Sl : constant String := B & "[p.pos..p.pos + " & NL & "]";
                  Eq : constant String :=
                    (if L.No_Case
                     then Sl & ".eq_ignore_ascii_case(""" & Rust_Escape (S)
                          & """.as_bytes())"
                     else Sl & " == *""" & Rust_Escape (S) & """.as_bytes()");
               begin
                  if Is_Keyword_Lit (S) then
                     return "scan_word(" & B & ", p.pos, p.text.len()) == "
                       & NL & " && " & Eq;
                  end if;
                  return "p.pos + " & NL & " <= p.text.len() && " & Eq;
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

               Append (Buf, "    if p.pos >= p.text.len() { return Err(p.fail(""a "
                 & RT & """)); }");
               Append (Buf, LF);
               Append (Buf, "    let r = ");
               St := 1;
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     if St <= K - 1 and then P (St).Kind = Literal then
                        Append (Buf, (if Branch = 0 then "if " else " else if ")
                          & Lit_At (P (St)) & " { p.pos += "
                          & Img (To_String (P (St).Lit)'Length) & "; "
                          & RT & "::" & RT & "_"
                          & To_String (Names (Branch + 1)) & " }");
                        Branch := Branch + 1;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, " else { return Err(p.fail(""");
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
                        Append (Buf, "`" & Rust_Escape (To_String (P (St).Lit)) & "`");
                        First := False;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, """)); };");
            Append (Buf, LF);
            Append (Buf, "    Ok(r)");
            Append (Buf, LF);
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            if Is_Core (To_String (P (1).Name)) then
               Append (Buf, "    let n = " & Scan_Call (To_String (P (1).Name)) & ";");
               Append (Buf, LF);
               Append (Buf, "    if n == 0" & Scalar_Reject (To_String (P (1).Name))
                 & " { return Err(p.fail(""" & Core_Desc (To_String (P (1).Name))
                 & """)); }");
               Append (Buf, LF);
               Append (Buf, "    let r = " & Scalar_Value (To_String (P (1).Name))
                 & "; p.pos += n;");
               Append (Buf, LF);
               Append (Buf, "    Ok(r)");
               Append (Buf, LF);
            elsif HBNF_Grammar.Except_Operand (NM) /= "" then
               --  `X = A - B` with a phrase on a side: parse A; then try B on
               --  exactly the text A matched (the input ends where A did, and
               --  B must end there too).  If it does, X does not match.
               declare
                  A : constant String := To_String (P (1).Name);
                  B : constant String := HBNF_Grammar.Except_Operand (NM);
               begin
                  Append (Buf, "    let save = p.pos;" & LF);
                  Append (Buf, "    let r = parse_" & Rust_Snake (A) & "(p)?;" & LF);
                  Append (Buf, "    let end = p.pos;" & LF);
                  Append (Buf, "    let full = p.text;" & LF);
                  Append (Buf, "    let (keep_pos, keep_err) = (p.err_pos, (p.err.clone(), p.ex.clone()));" & LF);
                  Append (Buf, (if Is_Hosted
                                then "    p.text = full.cut(end); p.pos = save;"
                                else "    p.text = &full[..end]; p.pos = save;") & LF);
                  Append (Buf, "    let same = parse_" & Rust_Snake (B)
                    & "(p).is_ok() && p.pos == end;" & LF);
                  Append (Buf, "    p.text = full; p.pos = end;" & LF);
                  Append (Buf, "    p.err_pos = keep_pos; p.err = keep_err.0; { let d = p.ex.depth; p.ex = keep_err.1; p.ex.depth = d; }" & LF);
                  Append (Buf, "    if same { p.pos = save; return Err(p.fail(""`" & A
                    & "` that is not `" & B & """)); }" & LF);
                  Append (Buf, "    Ok(r)" & LF);
               end;
            else
               Append (Buf, "    parse_" & Rust_Snake (To_String (P (1).Name))
                 & "(p)");
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
                           if E.Kind = Name
                             and then Is_Core (To_String (E.Name))
                           then
                              Append (Buf, "    { let n = " & Scan_Call (To_String (E.Name))
                                & "; if n > 0" & Scalar_Guard (To_String (E.Name))
                                & " { let r = " & Scalar_Value (To_String (E.Name))
                                & "; p.pos += n; return Ok(r); } }");
                              Append (Buf, LF);
                           elsif E.Kind = Name then
                              Append (Buf, "    if let Ok(r) = parse_"
                                & Rust_Snake (To_String (E.Name))
                                & "(p) { return Ok(r); }");
                              Append (Buf, LF);
                           end if;
                        end;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "    return Err(p.fail(""a " & NM & """));");
            Append (Buf, LF);
         elsif Has_Alt (P) then
            --  A struct alternation: try each branch with backtracking.
            Append (Buf, "    let save = p.pos;");
            Append (Buf, LF);
            Append (Buf, "    let mut r = " & RT & "::default();");
            Append (Buf, LF);
            Append (Buf, "    'alt: {");
            Append (Buf, LF);
            Emit_Alternation (Idx, P, "r.", "r = " & RT & "::default()", Buf,
                              "        ");
            Append (Buf, "        p.pos = save;");
            Append (Buf, LF);
            Append (Buf, "        return Err(p.fail(""a " & NM & """));");
            Append (Buf, LF);
            Append (Buf, "    }");
            Append (Buf, LF);
            Append (Buf, "    Ok(r)");
            Append (Buf, LF);
         else
            --  A struct sequence: match literals and references in order.
            --  `mut` only when a reference assigns a field (see Assigns).
            Append (Buf, (if Assigns (P)
                          then "    let mut r = " else "    let r = ")
              & RT & "::default();");
            Append (Buf, LF);
            Emit_Seq (Idx, P, 1, Natural (P.Length), "r.", Buf);
            Append (Buf, "    Ok(r)");
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
            Append (Res, Ind & "        { let mut o = 0usize; let mut ok = true;");
            Append (Res, LF);
            for Rg of B loop
               Append (Res, Ind & "          if ok { let (n, c) = decode_utf8(s, pos + off + o, len);"
                 & " if n == 0 || !" & Range_Cond (Rg.Lo, Rg.Hi)
                 & " { ok = false; } else { o += n; } }");
               Append (Res, LF);
            end loop;
            Append (Res, Ind & "          if ok && o > br { br = o; } }");
            Append (Res, LF);
         end Emit_Branch;
      begin
         --  `cnt` is read only by the upper-bound test and by the minimum
         --  test.  An unbounded repetition with no minimum reads it never, and
         --  rustc rejects a variable that is only assigned (`-D
         --  unused-variables`, which tests/portable.sh passes).
         declare
            Cnt_Used : constant Boolean := A.Max /= 0 or else A.Min > 0;
         begin
            Append (Res, Ind & (if Cnt_Used
                                then "{ let mut cnt = 0usize;" else "{"));
            Append (Res, LF);
            if A.Max = 0 then
               Append (Res, Ind & "    loop {");
            else
               Append (Res, Ind & "    while cnt < " & Img (A.Max) & " {");
            end if;
            Append (Res, LF);
            Append (Res, Ind & "        let mut br = 0usize;");
            Append (Res, LF);
            for B of A.Sub loop
               Emit_Branch (B);
            end loop;
            Append (Res, Ind & "        if br == 0 { break; }");
            Append (Res, LF);
            Append (Res, Ind & (if Cnt_Used
                                then "        off += br; cnt += 1;"
                                else "        off += br;"));
            Append (Res, LF);
            Append (Res, Ind & "    }");
            Append (Res, LF);
            if A.Min > 0 then
               Append (Res, Ind & "    if cnt < " & Img (A.Min) & " { " & Fail
                 & "; }");
               Append (Res, LF);
            end if;
            Append (Res, Ind & "}");
            Append (Res, LF);
         end;
      end Emit_Repeat;
   begin
      if Preamble ("Rust") /= "" then
         Append (Res, Preamble ("Rust"));
         Append (Res, LF);
         Append (Res, LF);
      end if;
      declare
         Nocase  : U;
         Skip_Ws : U;
      begin
         --  The guards `/` sets where a union needs backtracking (first match
         --  wins, as RFC 3986 section 3.2.2 settles `host`): is the next code
         --  point one that can follow the choice?
         for G in 1 .. HBNF_Grammar.Guard_Count loop
            declare
               Rs  : constant HBNF_Grammar.Guard_Range_Array :=
                 HBNF_Grammar.Guard_Ranges (G);
               Gid : constant String := Natural'Image (G);
            begin
               Append (Nocase, "    #[allow(dead_code)]" & LF);
               Append (Nocase, "    fn guard_" & Gid (Gid'First + 1 .. Gid'Last)
                 & "(&self) -> bool {" & LF);
               if Rs'Length = 0 then
                  Append (Nocase, "        " & (if HBNF_Grammar.Guard_Eoi (G)
                    then "self.pos >= self.text.len()" else "false") & LF
                    & "    }" & LF);
                  goto Next_Guard_R;
               end if;
               Append (Nocase, "        let c = match self.text[self.pos..].chars().next() {"
                 & " Some(c) => c as u32, None => return "
                 & (if HBNF_Grammar.Guard_Eoi (G) then "true" else "false")
                 & " };" & LF);
               Append (Nocase, "        false");
               for R of Rs loop
                  Append (Nocase, " || (c >= " & Natural'Image (R.Lo) & " && c <= "
                    & Natural'Image (R.Hi) & ")");
               end loop;
               Append (Nocase, LF & "    }" & LF);
               <<Next_Guard_R>> null;
            end;
         end loop;
         if Has_No_Case (Rules) then
            Append (Nocase,
              "    fn expect_word_nocase(&mut self, lit: &str) -> Result<(), ParseError> {");
            Append (Nocase, LF);
            Append (Nocase,
              "        let n = scan_word(self.text.as_bytes(), self.pos, self.text.len());");
            Append (Nocase, LF);
            Append (Nocase,
              "        if n == lit.len() && self.text[self.pos..self.pos + n].eq_ignore_ascii_case(lit) { self.pos += n; return Ok(()); }");
            Append (Nocase, LF);
            Append (Nocase, "        Err(self.fail(&format!(""`{}`"", lit)))");
            Append (Nocase, LF);
            Append (Nocase, "    }");
            Append (Nocase, LF);
            --  A case-insensitive literal that is not a keyword: its characters.
            Append (Nocase,
              "    fn expect_lit_nocase(&mut self, lit: &str) -> Result<(), ParseError> {");
            Append (Nocase, LF);
            Append (Nocase,
              "        if let Some(b) = self.text.as_bytes().get(self.pos..self.pos + lit.len()) {");
            Append (Nocase, LF);
            Append (Nocase,
              "            if b.eq_ignore_ascii_case(lit.as_bytes()) { self.pos += lit.len(); return Ok(()); }");
            Append (Nocase, LF);
            Append (Nocase, "        }");
            Append (Nocase, LF);
            Append (Nocase, "        Err(self.fail(&format!(""`{}`"", lit)))");
            Append (Nocase, LF);
            Append (Nocase, "    }");
            Append (Nocase, LF);
         end if;
         if Ws_Name = "" then
            Append (Skip_Ws, "");
         else
            Append (Skip_Ws, "        loop {" & LF
              & "            let n = scan_" & Rust_Snake (Ws_Name)
              & "(self.text.as_bytes(), self.pos, self.text.len());" & LF
              & "            if n == 0 { break; }" & LF
              & "            self.pos += n;" & LF
              & "        }" & LF);
         end if;
         declare
            V : Mustache.Context := Mustache.View;
         begin
            Mustache.Put (V, "nocase", To_String (Nocase));
            Mustache.Put (V, "skip_ws", To_String (Skip_Ws));
            Mustache.Put (V, "text_type", (if Is_Hosted then "Txt<'a>" else "&'a str"));
            Mustache.Put (V, "bit_field",
              (if Is_Hosted then "bit: usize, " else ""));
            Mustache.Put (V, "first_char",
              (if Is_Hosted then "bnf_first_char(&b[self.pos..])"
               else "self.text[self.pos..].chars().next().unwrap().to_string()"));
            Mustache.Put (V, "line_text",
              (if Is_Hosted then "bnf_lossy(&b[start..stop])"
               else "&self.text[start..stop]"));
            Append (Res, Mustache.Render_File ("rust_parser", V));
         end;
      end;
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
               --  parameter is `_p`: rustc rejects an unused one under
               --  `-D unused-variables`, which tests/portable.sh passes.  A
               --  jet rule also has an empty pattern but does read `p`, so it
               --  keeps the name.
               declare
                  Param : constant String :=
                    (if Rules (I).Pattern.Is_Empty
                       and then Rules (I).Jet_Code = Null_Unbounded_String
                     then "_p" else "p");
               begin
                  if Param = "p" then
                     --  the rule is on the stack of rules being read while its body runs
                     Append (Res, "fn parse_" & Rust_Snake (NM)
                       & "(p: &mut P) -> Result<" & Ret_Type (I)
                       & ", ParseError> {" & LF
                       & "    p.enter(" & Img (I) & ");" & LF
                       & (if Analyze (Rules, I).Kind = Struct and then Has_Span (Analyze (Rules, I))
                          then "    let save = p.pos;" & LF else "")
                       & "    let r = parse_body_" & Rust_Snake (NM) & "(p);" & LF
                       & "    p.ex.depth -= 1;" & LF
                       & (if Analyze (Rules, I).Kind = Struct and then Has_Span (Analyze (Rules, I))
                          then "    r.map(|mut v| {" & LF
                            & (if Rules (I).Whitespace /= Null_Unbounded_String
                               then "        let k = p.pos; p.pos = save; p.skip_ws(); v._pos = p.pos; p.pos = k;" & LF
                               else "        v._pos = save;" & LF)
                            & "        v._end = p.pos;" & LF
                            & "        v" & LF & "    })" & LF
                          else "    r" & LF)
                       & "}" & LF & LF);
                     Append (Res, "fn parse_body_" & Rust_Snake (NM)
                       & "(p: &mut P) -> Result<" & Ret_Type (I)
                       & ", ParseError> {");
                  else
                     Append (Res, "fn parse_" & Rust_Snake (NM)
                       & "(" & Param & ": &mut P) -> Result<" & Ret_Type (I)
                       & ", ParseError> {");
                  end if;
                  Append (Res, LF);
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
      Append (Res, "const RN: [&str; " & Img (N + 1) & "] = [""""," & LF);
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
      Append (Res, "];" & LF & LF);

      --  The scanners.  A core rule the grammar does not define (`word`,
      --  `int`, `str`, `ws`) is a built-in: hand-written Rust, the same scan
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
            Put ("fn scan_word(s: &[u8], pos: usize, len: usize) -> usize {");
            Put ("    let mut i = pos;");
            Put ("    if i >= len || !(s[i].is_ascii_alphabetic() || s[i] == b'_' || s[i] == b'-') { return 0; }");
            Put ("    i += 1;");
            Put ("    while i < len && is_word_char(s[i]) { i += 1; }");
            Put ("    i - pos");
            Put ("}");
            Put ("");
         end if;
         if Is_Jet ("int") then
            Put ("fn scan_int(s: &[u8], pos: usize, len: usize) -> usize {");
            Put ("    let mut i = pos;");
            Put ("    if i + 1 < len && s[i] == b'-' && s[i + 1].is_ascii_digit() { i += 1; }");
            Put ("    let start = i;");
            Put ("    while i < len && s[i].is_ascii_digit() { i += 1; }");
            Put ("    if i > start { i - pos } else { 0 }");
            Put ("}");
            Put ("");
         end if;
         if Is_Jet ("str") then
            Put ("fn scan_str(s: &[u8], pos: usize, len: usize) -> usize {");
            Put ("    if pos >= len || s[pos] != b'""' { return 0; }");
            Put ("    let mut i = pos + 1;");
            Put ("    while i < len && s[i] != b'""' {");
            Put ("        if s[i] == b'\\' && i + 1 < len { i += 1; }");
            Put ("        i += 1;");
            Put ("    }");
            Put ("    if i >= len { return 0; }");
            Put ("    i + 1 - pos");
            Put ("}");
            Put ("");
         end if;
         if Is_Jet ("ws") then
            Put ("fn scan_ws(s: &[u8], pos: usize, len: usize) -> usize {");
            Put ("    if pos < len && matches!(s[pos], b' ' | b'\t' | b'\r' | b'\n') { 1 } else { 0 }");
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
                    HBNF_Grammar.Jet_Body (NM, HBNF_Grammar.Rust_Target);
               begin
                  --  `name = Rust { ... }` is the body.
                  Put ("fn jet_" & Rust_Snake (NM)
                    & "(s: &[u8], pos: usize, len: usize) -> usize {");
                  Put ("    let _ = (s, pos, len);");
                  if Code /= "" then
                     Put (Code);
                  else
                     Put ("    0  // no Rust code: write `" & NM
                       & " = Rust { ... }`");
                  end if;
                  Put ("}");
                  Put ("");
               end;
            end if;
         end loop;

         --  The content of a quoted string: strip the quotes, and drop a
         --  backslash (keeping the character after it) or a backslash-newline.
         Put ("fn str_value(s: &str) -> String {");
         Put ("    let b = s.as_bytes();");
         Put ("    let mut r: Vec<u8> = Vec::new();");
         Put ("    let mut i = 1usize;");
         Put ("    while i + 1 < b.len() {");
         Put ("        if b[i] == b'\\' && i + 2 < b.len() {");
         Put ("            i += 1;");
         Put ("            if b[i] != b'\n' { r.push(b[i]); }");
         Put ("        } else {");
         Put ("            r.push(b[i]);");
         Put ("        }");
         Put ("        i += 1;");
         Put ("    }");
         Put ("    String::from_utf8_lossy(&r).into_owned()");
         Put ("}");
         Put ("");

         --  The words `word` must not match.
         if Keywords.Is_Empty then
            Put ("fn is_keyword(_s: &str) -> bool { false }");
         else
            Append (Res, "fn is_keyword(s: &str) -> bool { matches!(s, ");
            for K in 1 .. Natural (Keywords.Length) loop
               Append (Res, (if K = 1 then "" else " | ") & """"
                 & Rust_Escape (To_String (Keywords (K))) & """");
            end loop;
            Put (") }");
         end if;
         Put ("");
      end;

      --  Character-layer scanners (code-point matching, mirroring the C and Ada
      --  backends): each char-level rule compiles to a scanner over decoded UTF-8
      --  code points, and a phrase rule runs it where it names the rule.
      declare
         Has_Char : constant Boolean :=
           (for some I in 1 .. N =>
              Is_Char_Rule (Rules, To_String (Rules (I).Name))
                and then (Is_Char_Token (Rules, To_String (Rules (I).Name))
                          or else To_String (Rules (I).Name) = Ws_Name));
      begin
         if Has_Char then
            Append (Res, "fn decode_utf8(s: &[u8], pos: usize, len: usize) -> (usize, u32) {");
            Append (Res, LF);
            Append (Res, "    if pos >= len { return (0, 0); }");
            Append (Res, LF);
            Append (Res, "    let b0 = s[pos] as u32;");
            Append (Res, LF);
            Append (Res, "    if b0 < 0x80 { return (1, b0); }");
            Append (Res, LF);
            Append (Res, "    let (n, mut c) = if b0 & 0xE0 == 0xC0 { (2, b0 & 0x1F) }");
            Append (Res, LF);
            Append (Res, "        else if b0 & 0xF0 == 0xE0 { (3, b0 & 0x0F) }");
            Append (Res, LF);
            Append (Res, "        else if b0 & 0xF8 == 0xF0 { (4, b0 & 0x07) }");
            Append (Res, LF);
            Append (Res, "        else { return (0, 0); };");
            Append (Res, LF);
            Append (Res, "    if pos + n > len { return (0, 0); }");
            Append (Res, LF);
            Append (Res, "    for k in 1..n {");
            Append (Res, LF);
            Append (Res, "        let b = s[pos + k] as u32;");
            Append (Res, LF);
            Append (Res, "        if b & 0xC0 != 0x80 { return (0, 0); }");
            Append (Res, LF);
            Append (Res, "        c = (c << 6) | (b & 0x3F);");
            Append (Res, LF);
            Append (Res, "    }");
            Append (Res, LF);
            Append (Res, "    (n, c)");
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
Append (Res, "fn scan_" & Rust_Snake (NM)
  & "(s: &[u8], pos: usize, len: usize) -> usize {" & LF);
Append (Res, "    let n = scan_" & Rust_Snake (HBNF_Grammar.Except_Base (NM))
  & "(s, pos, len);" & LF);
Append (Res, "    if n == 0 || scan_" & Rust_Snake (HBNF_Grammar.Except_Operand (NM))
  & "(s, pos, pos + n) == n { return 0; }" & LF);
Append (Res, "    n" & LF & "}" & LF & LF);
elsif Is_Dfa_Token (Rules, NM) then
declare
   D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
   Ok  : Boolean;
   Why : Unbounded_String;
   Lo, Hi, To, First, Acc : Unbounded_String;
begin
   HBNF_Lookahead.Token_Dfa (Rules, NM, D, Ok, Why);
   HBNF_Lookahead.Dfa_Tables (D, Lo, Hi, To, First, Acc);
   Append (Res, "fn scan_" & Rust_Snake (NM)
     & "(s: &[u8], pos: usize, len: usize) -> usize {" & LF);
   Append (Res, "    const LO: &[u32] = &[" & To_String (Lo) & "];" & LF);
   Append (Res, "    const HI: &[u32] = &[" & To_String (Hi) & "];" & LF);
   Append (Res, "    const TO: &[u16] = &[" & To_String (To) & "];" & LF);
   Append (Res, "    const FIRST: &[u16] = &[" & To_String (First) & "];" & LF);
   Append (Res, "    const ACC: &[u8] = &[" & To_String (Acc) & "];" & LF);
   Append (Res, "    let (mut i, mut best, mut st) = (pos, 0usize, 0usize);" & LF);
   Append (Res, "    loop {" & LF);
   Append (Res, "        if ACC[st] != 0 { best = i - pos; }" & LF);
   Append (Res, "        if i >= len { break; }" & LF);
   Append (Res, "        let (n, c) = decode_utf8(s, i, len);" & LF);
   Append (Res, "        if n == 0 { break; }" & LF);
   Append (Res, "        let mut k = FIRST[st] as usize;" & LF);
   Append (Res, "        let end = FIRST[st + 1] as usize;" & LF);
   Append (Res, "        while k < end && !(c >= LO[k] && c <= HI[k]) { k += 1; }" & LF);
   Append (Res, "        if k == end { break; }" & LF);
   Append (Res, "        st = TO[k] as usize; i += n;" & LF);
   Append (Res, "    }" & LF);
   Append (Res, "    best" & LF & "}" & LF & LF);
end;
else
Append (Res, "fn scan_" & Rust_Snake (NM)
                    & "(s: &[u8], pos: usize, len: usize) -> usize {");
                  Append (Res, LF);
                  if Natural (DNF.Length) = 1 then
                     --  One branch: a sequence of code points, decoded in turn,
                     --  ending at most in one repetition.
                     Append (Res, "    let mut off = 0usize;");
                     Append (Res, LF);
                     for A of DNF (1) loop
                        case A.Kind is
                           when Single =>
                              Append (Res, "    { let (n, c) = decode_utf8(s, pos + off, len);"
                                & " if n == 0 || !" & Range_Cond (A.Lo, A.Hi)
                                & " { return 0; } off += n; }");
                              Append (Res, LF);
                           when Repeat =>
                              Emit_Repeat (A, "    ", "return 0");
                        end case;
                     end loop;
                     Append (Res, "    off");
                     Append (Res, LF);
                  else
                     --  Alternation: try each branch, keep the longest match.
                     Append (Res, "    let mut best = 0usize;");
                     Append (Res, LF);
                     declare
                        Br : Natural := 0;
                     begin
                        for B of DNF loop
                           Br := Br + 1;
                           Append (Res, "    'br" & Img (Br) & ": {");
                           Append (Res, LF);
                           Append (Res, "        let mut off = 0usize;");
                           Append (Res, LF);
                           for A of B loop
                              case A.Kind is
                                 when Single =>
                                    Append (Res, "        let (n, c) = decode_utf8(s, pos + off, len);"
                                      & " if n == 0 || !" & Range_Cond (A.Lo, A.Hi)
                                      & " { break 'br" & Img (Br) & "; } off += n;");
                                    Append (Res, LF);
                                 when Repeat =>
                                    Emit_Repeat (A, "        ", "break 'br" & Img (Br));
                              end case;
                           end loop;
                           Append (Res, "        if off > best { best = off; }");
                           Append (Res, LF);
                           Append (Res, "    }");
                           Append (Res, LF);
                        end loop;
                     end;
                     Append (Res, "    best");
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

      return To_String (Res);
   end Emit_Parser;

   function Emit_Lexer (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      R  : constant HBNF_Grammar.Rule := Rules (1);
      P  : constant HBNF_Grammar.Element_Vectors.Vector := R.Pattern;
      Root_T : constant String :=
        (if Is_Char_Rule (Rules, To_String (R.Name))
         then Rust_Type (To_String (R.Name))
         elsif Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            (if P (1).Kind = HBNF_Grammar.Name then
               "Vec<" & (if Scalar_Rust_Type (To_String (P (1).Name)) /= "" then
                           Scalar_Rust_Type (To_String (P (1).Name))
                         else Rust_Type (To_String (P (1).Name))) & ">"
             else "Vec<" & Rust_Type (To_String (R.Name)) & "Entry>")
         else Rust_Type (To_String (R.Name)));
      --  parse_text: the whole text through the root rule.
      function Parse_Text_Src return String is
         V : Mustache.Context := Mustache.View;
      begin
         Mustache.Put (V, "root_type", Root_T);
         Mustache.Put (V, "text_param", (if Is_Hosted then "&[u8]" else "&str"));
         Mustache.Put (V, "text_init", (if Is_Hosted then ": Txt(text)" else ""));
         Mustache.Put (V, "bit_init", (if Is_Hosted then "bit: 0, " else ""));
         Mustache.Put (V, "reset",
           (if Is_Hosted and then Hosted_Acts
            then "    BNF_WARNINGS.with(|w| w.borrow_mut().clear());" & LF else ""));
         Mustache.Put (V, "actions",
           (if Is_Hosted and then Hosted_Acts then
              "    let mut h_ = Hooks { warnings: Vec::new() };" & LF
              & "    let r_ = bnf_act_root(&out, &mut h_);" & LF
              & "    BNF_WARNINGS.with(|w| *w.borrow_mut() = h_.warnings);" & LF
              & "    if let Err(m) = r_ { return Err(ParseError { line: 0, col: 0, msg: m }); }" & LF
            else ""));
         Mustache.Put (V, "root_fn",
           "parse_" & Rust_Snake (To_String (R.Name)));
         --  The root skips whitespace around itself if its file does.
         Mustache.Put (V, "lead_ws",
           (if R.Whitespace /= Null_Unbounded_String
            then "    p.skip_ws();" & LF else ""));
         Mustache.Put (V, "trail_ws",
           (if R.Whitespace /= Null_Unbounded_String
            then "    p.skip_ws();" & LF else ""));
         return Mustache.Render_File ("rust_parse_text", V);
      end Parse_Text_Src;

      Lexer  : constant String := Parse_Text_Src;
   begin
      if Epilogue ("Rust") = "" then
         return Lexer & To_String (Hosted_Code);
      else
         return Lexer & To_String (Hosted_Code) & LF & Epilogue ("Rust");
      end if;
   end Emit_Lexer;

   function Emit_Conf (Rules : HBNF_Grammar.Rule_Vectors.Vector) return String is
      Root_T : constant String := Rust_Type (To_String (Rules (1).Name));
   begin
      return Render_Root ("conf_rust", Root_T);
   end Emit_Conf;

end HBNF_Rust;
