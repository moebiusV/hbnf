pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Templates;

package body HBNF_C is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

   subtype U is Unbounded_String;

   LF : constant Character := ASCII.LF;

   package String_Vectors is new Ada.Containers.Vectors (Positive, U);
   package Natural_Vectors is new Ada.Containers.Vectors (Positive, Natural);

   --  The C type for a built-in core rule, or "" if not a core scalar.
   function Scalar_C_Type (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "const char *";
      elsif Name = "int" then
         return "long long";
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
               return (if P = 'u' then "uint" else "int") & R & "_t";
            end if;
         end;
      end if;
      return "";
   end Scalar_C_Type;

   --  Upper-case C identifier fragment (for enum constants).
   function C_Ident (S : String) return String is
      Buf : U;
   begin
      for C of S loop
         if C in 'a' .. 'z' then
            Append (Buf, Character'Val (Character'Pos (C) - 32));
         elsif (C in 'A' .. 'Z') or else (C in '0' .. '9') then
            Append (Buf, C);
         else
            Append (Buf, '_');
         end if;
      end loop;
      return To_String (Buf);
   end C_Ident;

   --  A literal the lexer interns as a keyword (it gets a KW_ id): one led
   --  by a letter or underscore.  Punctuation and digit-led literals are not
   --  atoms.
   function Is_Keyword_Lit (S : String) return Boolean is
     (S'Length > 0
      and then (S (S'First) in 'a' .. 'z'
                or else S (S'First) in 'A' .. 'Z'
                or else S (S'First) = '_'));

   --  Escape a literal for embedding in a C string literal: backslash and
   --  double-quote take C escapes, the named controls map to their short
   --  forms, and any other non-printable byte becomes a 3-digit octal escape
   --  (C's `\x` is greedy over the following hex digits; `\NNN` is exactly
   --  three, so it can never swallow what comes after).
   function C_Escape (S : String) return String is
      Buf : U;
      Oct : constant String := "01234567";
   begin
      for C of S loop
         case C is
            when '\' => Append (Buf, "\\");
            when '"' => Append (Buf, "\""");
            when others =>
               case Character'Pos (C) is
                  when 7  => Append (Buf, "\a");
                  when 8  => Append (Buf, "\b");
                  when 9  => Append (Buf, "\t");
                  when 10 => Append (Buf, "\n");
                  when 11 => Append (Buf, "\v");
                  when 12 => Append (Buf, "\f");
                  when 13 => Append (Buf, "\r");
                  when 32 .. 126 => Append (Buf, C);
                  when others =>
                     declare
                        V : constant Natural := Character'Pos (C);
                     begin
                        Append (Buf, "\");
                        Append (Buf, Oct (V / 64 + 1));
                        Append (Buf, Oct ((V / 8) mod 8 + 1));
                        Append (Buf, Oct (V mod 8 + 1));
                     end;
               end case;
         end case;
      end loop;
      return To_String (Buf);
   end C_Escape;

   --  The C list container.  A grammar may override each operation with a
   --  top-level `list-<op> { … }` directive: raw C with @name@ (the head's
   --  struct tag), @elem@ (the element type), @h@ (a head-pointer
   --  expression), @e@ (a node pointer) and @v@ (a node-pointer variable)
   --  substituted.  An operation without an override falls back to hbnf's
   --  own head/tail singly-linked list, written directly with no #define.
   function Subst (T, Name, Elem, H, E, V : String) return String is
      Buf : U;
      I   : Natural := T'First;
   begin
      while I <= T'Last loop
         if I < T'Last and then T (I) = '@' then
            declare
               J : Natural := I + 1;
            begin
               while J <= T'Last and then T (J) /= '@' loop
                  J := J + 1;
               end loop;
               if J <= T'Last then
                  declare
                     Key : constant String := T (I + 1 .. J - 1);
                  begin
                     if Key = "name" then
                        Append (Buf, Name);
                     elsif Key = "elem" then
                        Append (Buf, Elem);
                     elsif Key = "h" then
                        Append (Buf, H);
                     elsif Key = "e" then
                        Append (Buf, E);
                     elsif Key = "v" then
                        Append (Buf, V);
                     else
                        Append (Buf, T (I .. J));
                     end if;
                  end;
                  I := J + 1;
               else
                  Append (Buf, T (I));
                  I := I + 1;
               end if;
            end;
         else
            Append (Buf, T (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Buf);
   end Subst;

   function L_Head (Name, Elem : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("head");
   begin
      if O /= "" then
         return Subst (O, Name, Elem, "", "", "");
      end if;
      return "struct " & Name & " { struct " & Elem & " *head, **tail; }";
   end L_Head;

   function L_Entry (Elem : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("entry");
   begin
      if O /= "" then
         return Subst (O, "", Elem, "", "", "");
      end if;
      return "struct " & Elem & " *_link";
   end L_Entry;

   function L_Init (H : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("init");
   begin
      if O /= "" then
         return Subst (O, "", "", H, "", "");
      end if;
      return "(" & H & ")->head = NULL; (" & H & ")->tail = &(" & H
        & ")->head;";
   end L_Init;

   function L_Append (H, E : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("append");
   begin
      if O /= "" then
         return Subst (O, "", "", H, E, "");
      end if;
      return "*(" & H & ")->tail = " & E & "; (" & H & ")->tail = &("
        & E & ")->_link;";
   end L_Append;

   function L_Foreach (V, H : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("foreach");
   begin
      if O /= "" then
         return Subst (O, "", "", H, "", V);
      end if;
      return "for (" & V & " = (" & H & ")->head; " & V & "; " & V & " = "
        & V & "->_link)";
   end L_Foreach;

   function L_First (H : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("first");
   begin
      if O /= "" then
         return Subst (O, "", "", H, "", "");
      end if;
      return "(" & H & ")->head";
   end L_First;

   function L_Next (E : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("next");
   begin
      if O /= "" then
         return Subst (O, "", "", "", E, "");
      end if;
      return "(" & E & ")->_link";
   end L_Next;

   --  After a head has been copied to its final place (the parser builds
   --  lists in locals and copies structs out), repoint what points back at
   --  the head: a TAILQ's first tqe_prev and an empty list's tail.
   function L_Relink (H : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("relink");
   begin
      if O /= "" then
         return Subst (O, "", "", H, "", "");
      end if;
      return "if (!(" & H & ")->head) (" & H & ")->tail = &(" & H
        & ")->head;";
   end L_Relink;

   --  True when any listops operation is overridden: the grammar supplies its
   --  own list container, not hbnf's built-in slist.
   function Has_Listops return Boolean is
   begin
      return HBNF_Grammar.List_Override ("head") /= ""
        or else HBNF_Grammar.List_Override ("entry") /= ""
        or else HBNF_Grammar.List_Override ("init") /= ""
        or else HBNF_Grammar.List_Override ("append") /= ""
        or else HBNF_Grammar.List_Override ("foreach") /= ""
        or else HBNF_Grammar.List_Override ("first") /= ""
        or else HBNF_Grammar.List_Override ("next") /= "";
   end Has_Listops;

   --  A relink walk is emitted for hbnf's built-in slist and for a listops
   --  block that supplies its own relink.  A listops block without a relink
   --  gets no walk: the built-in slist relink does not fit a custom container.
   function Has_Relink return Boolean is
   begin
      return HBNF_Grammar.List_Override ("relink") /= ""
        or else not Has_Listops;
   end Has_Relink;

   --  Natural'Image with the leading blank stripped ("1", not " 1").
   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Img;

   --  Unique enumerator suffixes for a literal list.  C_Ident is case-
   --  insensitive (`dot`/`DoT` both -> `DOT`) and maps punctuation to `_`
   --  (`!=`/`<=` both -> `__`), so plain names collide; dedupe by appending
   --  _2, _3, ..., and name pure-punctuation literals `OP` + position.
   function Enum_Names (Lits : String_Vectors.Vector) return String_Vectors.Vector is
      Names : String_Vectors.Vector;

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
            Base : constant String := C_Ident (To_String (Lits (I)));
            N    : U;
         begin
            if Base = "" or else (for all C of Base => C = '_') then
               N := To_Unbounded_String ("OP" & Img (I));
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

   --  True when every `/`-alternative is exactly one Literal — the shape an
   --  enum can hold.  A multi-token alternative (`"a" "b" / "c" "d"`), one that
   --  names another rule, or a single literal (no `/`) is not an enum.
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

   --  A valid C identifier from a rule name ('-' -> '_').
   function C_Name (S : String) return String is
      Buf : U;
   begin
      for C of S loop
         Append (Buf, (if C = '-' then '_' else C));
      end loop;
      return To_String (Buf);
   end C_Name;

   --  A struct member name, kept clear of C keywords (the core types `int`,
   --  `float` and `bool` are C keywords/macros, so a field named after them
   --  would not compile).
   function C_Field (S : String) return String is
      N : constant String := C_Name (S);
   begin
      if N = "int" or else N = "float" or else N = "bool"
        or else N = "char" or else N = "double" or else N = "long"
        or else N = "short" or else N = "signed" or else N = "unsigned"
        or else N = "void" or else N = "const" or else N = "struct"
        or else N = "union" or else N = "enum" or else N = "auto"
        or else N = "break" or else N = "case" or else N = "continue"
        or else N = "default" or else N = "do" or else N = "else"
        or else N = "extern" or else N = "for" or else N = "goto"
        or else N = "if" or else N = "inline" or else N = "register"
        or else N = "restrict" or else N = "return" or else N = "sizeof"
        or else N = "static" or else N = "switch" or else N = "typedef"
        or else N = "volatile" or else N = "while"
      then
         return N & "_";
      end if;
      return N;
   end C_Field;

   --  The schema's type prefix (`prefix "pf_"`, or --prefix=), put in front
   --  of every generated type and struct tag; "" when absent.
   function Pfx return String is (HBNF_Grammar.Type_Prefix);

   --  The `_t` typedef name for a rule, with a "_" suffix when it would
   --  collide with a POSIX <sys/types.h> typedef (uid_t, gid_t, ...).
   function C_Type_Name (Ref : String) return String is
      T : constant String := C_Name (Ref) & "_t";
   begin
      if Pfx /= "" then
         --  A prefix keeps every generated type out of the system's
         --  namespace, so no name needs special-casing.
         return Pfx & T;
      end if;
      if T = "uid_t" or else T = "gid_t" or else T = "pid_t"
        or else T = "off_t" or else T = "size_t" or else T = "ssize_t"
        or else T = "time_t" or else T = "mode_t" or else T = "dev_t"
        or else T = "ino_t" or else T = "nlink_t" or else T = "id_t"
        or else T = "clock_t" or else T = "useconds_t"
        or else T = "suseconds_t" or else T = "timer_t"
        or else T = "socklen_t" or else T = "key_t"
      then
         return T & "_";
      end if;
      return T;
   end C_Type_Name;

   --  The C type of the root (first) rule: a list root is its list head
   --  (`struct <CN>_list`), a struct root its `_t` typedef.
   function Root_Type (Rules : Rule_Vectors.Vector) return String is
      NM : constant String := To_String (Rules (1).Name);
   begin
      if Natural (Rules (1).Pattern.Length) = 1
        and then (Rules (1).Pattern (1).Min /= 1
                  or else Rules (1).Pattern (1).Max /= 1)
      then
         return "struct " & Pfx & C_Name (NM) & "_list";
      end if;
      return C_Type_Name (NM);
   end Root_Type;

   --  =====================================================================
   --  Classification shared by the id-ref serialization emitters.  Emit and
   --  Emit_Parser keep their own local copies; these package-level versions
   --  are parameterized by Rules so Emit_Serializer and Emit_Rebuild share
   --  one classification.

   type Member is record
      Name    : U;
      Is_List : Boolean;
   end record;
   package Member_Vectors is new Ada.Containers.Vectors (Positive, Member);

   type Class_Kind is (Enum, Scalar, List, Struct);

   type Rule_Info (Kind : Class_Kind := Scalar) is record
      Tags : String_Vectors.Vector := String_Vectors.Empty_Vector;
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

   function Find (Rules : Rule_Vectors.Vector; Name : String) return Natural is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if To_String (Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function C_Type_Of (Rules : Rule_Vectors.Vector; Ref : String) return String is
      S : constant String := Scalar_C_Type (Ref);
      J : constant Natural := Find (Rules, Ref);
   begin
      if S /= "" then
         return S;
      end if;
      if J = 0 then
         raise Parse_Error with "undefined rule: " & Ref;
      end if;
      --  A typed rule (`C-type name = …`) declares its storage class; use
      --  it instead of the inferred type.
      if Rules (J).C_Type /= Null_Unbounded_String then
         return To_String (Rules (J).C_Type);
      end if;
      return C_Type_Name (Ref);
   end C_Type_Of;

   --  The underlying scalar C type a rule name resolves to, chasing
   --  single-name aliases and jets.  "" if not scalar.
   function Resolve_Type (Rules : Rule_Vectors.Vector; N : String;
                          Depth : Natural := 0) return String is
      C : constant String := Scalar_C_Type (N);
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
               return "const char *";
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

   --  If the pattern is a pure alternation of names that all resolve to the
   --  same scalar C type, that type; else "".
   function Scalar_Union_Type (Rules : Rule_Vectors.Vector;
                               Els : Element_Vectors.Vector) return String is
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

   function Contains (V : Member_Vectors.Vector; S : U) return Boolean is
   begin
      for X of V loop
         if X.Name = S then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

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
         end case;
      end loop;
   end Collect;

   --  The distinct leading keywords of a keyword-headed alternation: the
   --  first literal of each '/' branch, deduped in order; empty if there is
   --  no alternation (a plain sequence is not tagged) or if any branch does
   --  not begin with a literal.
   function Leading_Tags (Els : Element_Vectors.Vector)
      return String_Vectors.Vector is
      Tags     : String_Vectors.Vector;
      All_Lit  : Boolean := True;
      Branches : Natural := 0;
      St       : Natural := 1;
   begin
      for K in 1 .. Natural (Els.Length) + 1 loop
         if K > Natural (Els.Length) or else Els (K).Kind = Alt then
            Branches := Branches + 1;
            if St <= K - 1 then
               if Els (St).Kind = Literal then
                  declare
                     Present : Boolean := False;
                  begin
                     for T of Tags loop
                        if T = Els (St).Lit then
                           Present := True;
                        end if;
                     end loop;
                     if not Present then
                        Tags.Append (Els (St).Lit);
                     end if;
                  end;
               else
                  All_Lit := False;
               end if;
            end if;
            St := K + 1;
         end if;
      end loop;
      if Branches < 2 or else not All_Lit then
         return String_Vectors.Empty_Vector;
      end if;
      return Tags;
   end Leading_Tags;

   function Analyze (Rules : Rule_Vectors.Vector; Idx : Natural)
      return Rule_Info is
      R : constant Rule := Rules (Idx);
      P : constant Element_Vectors.Vector := R.Pattern;
   begin
      if R.Jet_Code /= Null_Unbounded_String then
         return (Kind        => Scalar,
                 Inline_Type => To_Unbounded_String ("const char *"),
                 others      => <>);
      end if;
      if Natural (P.Length) = 1 then
         declare
            E : constant Element_Access := P (1);
         begin
            if E.Min /= 1 or else E.Max /= 1 then
               if E.Kind = Name then
                  return (Kind        => List,
                          Elem_Name    => E.Name,
                          Elem_Members => Member_Vectors.Empty_Vector,
                          others       => <>);
               elsif E.Kind = Group then
                  declare
                     Members : Member_Vectors.Vector;
                     Lits    : String_Vectors.Vector;
                     Has_Alt : Boolean := False;
                  begin
                     Collect (E.Items, Members, Lits, Has_Alt);
                     return (Kind        => List,
                             Elem_Name    => Null_Unbounded_String,
                             Elem_Members => Members,
                             Tags         => Leading_Tags (E.Items));
                  end;
               else
                  return (Kind        => List,
                          Elem_Name    => Null_Unbounded_String,
                          Elem_Members => Member_Vectors.Empty_Vector,
                          others       => <>);
               end if;
            end if;

            if E.Kind = Name then
               return (Kind        => Scalar,
                       Inline_Type =>
                         To_Unbounded_String
                           (C_Type_Of (Rules, To_String (E.Name))),
                       others      => <>);
            elsif E.Kind = Group then
               declare
                  Members : Member_Vectors.Vector;
                  Lits    : String_Vectors.Vector;
                  Has_Alt : Boolean := False;
               begin
                  Collect (E.Items, Members, Lits, Has_Alt);
                  return (Kind => Struct, Members => Members,
                          Tags => Leading_Tags (E.Items));
               end;
            else
               return (Kind        => Scalar,
                       Inline_Type => To_Unbounded_String ("const char *"),
                       others      => <>);
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
            return (Kind => Enum, Literals => Lits, others => <>);
         else
            declare
               SU : constant String := Scalar_Union_Type (Rules, P);
            begin
               if SU /= "" then
                  return (Kind => Scalar, Inline_Type => To_Unbounded_String (SU),
                          others => <>);
               end if;
            end;
            return (Kind => Struct, Members => Members,
                    Tags => Leading_Tags (P));
         end if;
      end;
   end Analyze;

   --  The rule a field really holds: an alias (`src = host`), followed
   --  through any chain of aliases, names the struct or list it stands for,
   --  and the free, walk and id-ref code must treat the field as that rule.
   --  Anything else (a core scalar, a scalar alias, an enum) is itself.
   function Alias_Target (Rules : Rule_Vectors.Vector; Name : String)
      return String is
      Cur : U := To_Unbounded_String (Name);
   begin
      for Hop in 1 .. 8 loop
         declare
            J : constant Natural := Find (Rules, To_String (Cur));
         begin
            exit when J = 0;
            declare
               R : constant Rule := Rules (J);
               P : constant Element_Vectors.Vector := R.Pattern;
            begin
               exit when R.Jet_Code /= Null_Unbounded_String
                 or else Natural (P.Length) /= 1
                 or else P (1).Kind /= HBNF_Grammar.Name
                 or else P (1).Min /= 1 or else P (1).Max /= 1
                 or else Scalar_C_Type (To_String (P (1).Name)) /= "";
               declare
                  T : constant Natural := Find (Rules, To_String (P (1).Name));
               begin
                  exit when T = 0;
                  if Analyze (Rules, T).Kind in Struct | List then
                     return To_String (P (1).Name);
                  end if;
                  Cur := P (1).Name;
               end;
            end;
         end;
      end loop;
      return Name;
   end Alias_Target;

   function Emit
     (Rules   : Rule_Vectors.Vector;
      Idref   : Boolean := False;
      Walkers : Boolean := True)
      return String is

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

      function C_Type_Of (Ref : String) return String is
         S : constant String := Scalar_C_Type (Ref);
         J : constant Natural := Find (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         if J = 0 then
            raise Parse_Error with "undefined rule: " & Ref;
         end if;
         --  A typed rule declares its C storage class; use it.
         if Rules (J).C_Type /= Null_Unbounded_String then
            return To_String (Rules (J).C_Type);
         end if;
         return C_Type_Name (Ref);
      end C_Type_Of;

      --  A name-bearing declarator for a C storage class: the array suffix
      --  (if any) moves after the name, so `char[16]` + "ifname" is
      --  `char ifname[ 16 ]`, not the invalid `char[ 16 ] ifname`.
      function Declarator (C_Type : String; Name : String) return String is
         Bracket : Integer := 0;
      begin
         for I in C_Type'Range loop
            if C_Type (I) = '[' then
               Bracket := I;
               exit;
            end if;
         end loop;
         if Bracket = 0 then
            return C_Type & " " & Name;
         end if;
         declare
            Base_Last : Integer := Bracket - 1;
         begin
            while Base_Last >= C_Type'First and then C_Type (Base_Last) = ' '
            loop
               Base_Last := Base_Last - 1;
            end loop;
            return C_Type (C_Type'First .. Base_Last) & " " & Name
              & C_Type (Bracket .. C_Type'Last);
         end;
      end Declarator;

      --  The underlying scalar C type a rule name resolves to, chasing
      --  single-name aliases and jets to their target (so `str / word` and
      --  `ipv4 / ipv6` both collapse to `const char *`).  "" if not scalar.
      function Resolve_Type (N : String; Depth : Natural := 0) return String is
         C : constant String := Scalar_C_Type (N);
      begin
         if C /= "" then
            return C;
         end if;
         if Depth > 8 then
            return "";
         end if;
         declare
            J : constant Natural := Find (N);
         begin
            if J = 0 then
               return "";
            end if;
            declare
               R : constant Rule := Rules (J);
               P : constant Element_Vectors.Vector := R.Pattern;
            begin
               if R.Jet_Code /= Null_Unbounded_String then
                  return "const char *";
               end if;
               if Natural (P.Length) = 1
                 and then P (1).Kind = Name
                 and then P (1).Min = 1
                 and then P (1).Max = 1
               then
                  return Resolve_Type (To_String (P (1).Name), Depth + 1);
               end if;
            end;
         end;
         return "";
      end Resolve_Type;

      --  If the pattern is a pure alternation of names that all resolve to
      --  the same scalar C type, that type (a scalar union); else "".
      function Scalar_Union_Type (Els : Element_Vectors.Vector) return String is
         T       : U := Null_Unbounded_String;
         Has_Alt : Boolean := False;
      begin
         for E of Els loop
            if E.Kind = Alt then
               Has_Alt := True;
            elsif E.Kind = Name then
               declare
                  R : constant String := Resolve_Type (To_String (E.Name));
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
      --  and whether any '/' alternation appears.
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
            end case;
         end loop;
      end Collect;

      type Class_Kind is (Enum, Scalar, List, Struct);

      type Rule_Info (Kind : Class_Kind := Scalar) is record
         Tags : String_Vectors.Vector := String_Vectors.Empty_Vector;
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
         if R.Jet_Code /= Null_Unbounded_String then
            --  A jet reads its own token kind and yields the matched text.
            return (Kind        => Scalar,
                    Inline_Type => To_Unbounded_String ("const char *"),
                    others      => <>);
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
                             Elem_Members => Member_Vectors.Empty_Vector,
                             others       => <>);
                  elsif E.Kind = Group then
                     declare
                        Members : Member_Vectors.Vector;
                        Lits    : String_Vectors.Vector;
                        Has_Alt : Boolean := False;
                     begin
                        Collect (E.Items, Members, Lits, Has_Alt);
                        return (Kind        => List,
                                Elem_Name    => Null_Unbounded_String,
                                Elem_Members => Members,
                                Tags         => Leading_Tags (E.Items));
                     end;
                  else
                     return (Kind        => List,
                             Elem_Name    => Null_Unbounded_String,
                             Elem_Members => Member_Vectors.Empty_Vector,
                             others       => <>);
                  end if;
               end if;

               --  Single element, no repetition.
               if E.Kind = Name then
                  return (Kind => Scalar,
                          Inline_Type =>
                            To_Unbounded_String
                              (C_Type_Of (To_String (E.Name))),
                          others      => <>);
               elsif E.Kind = Group then
                  declare
                     Members : Member_Vectors.Vector;
                     Lits    : String_Vectors.Vector;
                     Has_Alt : Boolean := False;
                  begin
                     Collect (E.Items, Members, Lits, Has_Alt);
                     return (Kind => Struct, Members => Members,
                             Tags => Leading_Tags (E.Items));
                  end;
               else
                  return (Kind        => Scalar,
                          Inline_Type => To_Unbounded_String ("const char *"),
                          others      => <>);
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
               return (Kind => Enum, Literals => Lits, others => <>);
            else
               declare
                  SU : constant String := Scalar_Union_Type (P);
               begin
                  if SU /= "" then
                     return (Kind => Scalar, Inline_Type => To_Unbounded_String (SU),
                          others => <>);
                  end if;
               end;
               return (Kind => Struct, Members => Members,
                       Tags => Leading_Tags (P));
            end if;
         end;
      end Analyze;

      --  A struct is embedded by value; a list is a `next`-linked node
      --  referenced by head pointer, so only structs impose a by-value order.
      function Is_By_Value (Info : Rule_Info) return Boolean is
        (Info.Kind = Struct);

      Infos : Info_Vectors.Vector;

      --  The rule indices this rule must be emitted after: its by-value
      --  members that reference another struct.
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

         procedure Add_Ref (N : U) is
            J : Natural := Find (To_String (N));
         begin
            --  Chase a scalar alias (`src = host`) through to the struct its
            --  by-value field really holds, so the containing struct is laid
            --  out after that struct.  A direct struct member is already there.
            while J > 0 and then Infos (J).Kind = Scalar loop
               declare
                  P : constant Element_Vectors.Vector := Rules (J).Pattern;
               begin
                  if Natural (P.Length) = 1 and then P (1).Kind = Name
                    and then P (1).Min = 1 and then P (1).Max = 1
                  then
                     J := Find (To_String (P (1).Name));
                  else
                     J := 0;
                  end if;
               end;
            end loop;
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
                     if not M.Is_List then
                        Add_Ref (M.Name);
                     end if;
                  end loop;
               when List =>
                  if Info.Elem_Name /= Null_Unbounded_String then
                     Add_Ref (Info.Elem_Name);
                  end if;
                  for M of Info.Elem_Members loop
                     Add_Ref (M.Name);
                  end loop;
               when others =>
                  null;
            end case;
         end;
         return D;
      end Deps;

      --  The C type a struct/list reference denotes (a `_t` typedef name).
      function Ref_Type (Name : String) return String is
         S : constant String := Scalar_C_Type (Name);
      begin
         if S /= "" then
            return S;
         end if;
         return C_Type_Name (Name);
      end Ref_Type;

      --  The `kind` discriminator enum for a keyword-headed alternation:
      --  one value per distinct leading keyword, so the tree records which
      --  alternative matched.
      function Kind_Enum (CN : String; Tags : String_Vectors.Vector)
         return String is
         Buf : U;
      begin
         Append (Buf, "typedef enum {");
         Append (Buf, LF);
         for I in 1 .. Natural (Tags.Length) loop
            Append (Buf, "    " & C_Ident (CN) & "_"
              & C_Ident (To_String (Tags (I))));
            if I < Natural (Tags.Length) then
               Append (Buf, ",");
            end if;
            Append (Buf, "   /* " & To_String (Tags (I)) & " */");
            Append (Buf, LF);
         end loop;
         Append (Buf, "} " & Pfx & CN & "_kind_t;");
         Append (Buf, LF);
         return To_String (Buf);
      end Kind_Enum;

      function Emit_Rule (Idx : Natural; Info : Rule_Info) return String is
         R  : constant Rule := Rules (Idx);
         NM : constant String := To_String (R.Name);
         CN : constant String := C_Name (NM);
         Buf : U;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append (Buf, "/* " & To_String (R.Leading_Comment) & " */");
            Append (Buf, LF);
         end if;

         --  A typed rule (`C-type name = …`) declares an external storage
         --  class; no struct or typedef is emitted — the type comes from
         --  the included header.
         if R.C_Type /= Null_Unbounded_String then
            return To_String (Buf);
         end if;

         case Info.Kind is
            when Scalar =>
               Append (Buf, "typedef " & To_String (Info.Inline_Type) & " "
                 & C_Type_Name (NM) & ";");
               Append (Buf, LF);
            when Enum =>
               declare
                  Names : constant String_Vectors.Vector := Enum_Names (Info.Literals);
               begin
                  Append (Buf, "typedef enum {");
                  Append (Buf, LF);
                  for I in 1 .. Natural (Info.Literals.Length) loop
                     Append (Buf, "    " & C_Ident (NM) & "_"
                       & To_String (Names (I)));
                     if I < Natural (Info.Literals.Length) then
                        Append (Buf, ",");
                     end if;
                     Append (Buf, "   /* "
                       & To_String (Info.Literals (I)) & " */");
                     Append (Buf, LF);
                  end loop;
                  Append (Buf, "} " & C_Type_Name (NM) & ";");
                  Append (Buf, LF);
               end;
            when Struct =>
               if not Info.Tags.Is_Empty then
                  Append (Buf, Kind_Enum (CN, Info.Tags));
               end if;
               Append (Buf, "struct " & Pfx & CN & " {");
               Append (Buf, LF);
               if Idref then
                  Append (Buf, "    objid_t id, parent;");
                  Append (Buf, LF);
               end if;
               if not Info.Tags.Is_Empty then
                  Append (Buf, "    " & Pfx & CN & "_kind_t kind;");
                  Append (Buf, LF);
               end if;
               for M of Info.Members loop
                  declare
                     J : constant Natural := Find (To_String (M.Name));
                     Is_Head : constant Boolean :=
                       M.Is_List or else
                         (J > 0 and then Infos (J).Kind = List);
                  begin
                     if Is_Head then
                        Append (Buf, "    struct " & Pfx
                          & C_Name (To_String (M.Name)) & "_list "
                          & C_Field (To_String (M.Name)) & ";");
                     else
                        Append (Buf, "    " & Declarator
                          (C_Type_Of (To_String (M.Name)),
                           C_Field (To_String (M.Name))) & ";");
                     end if;
                  end;
                  Append (Buf, LF);
               end loop;
               if R.Action_Code /= Null_Unbounded_String then
                  Append (Buf, "    size_t _line;   /* for bind_error */");
                  Append (Buf, LF);
               end if;
               Append (Buf, "};");
               Append (Buf, LF);
            when List =>
               --  A list-linked node; the head is a `struct <CN>_list`
               --  embedded in the parent.
               if not Info.Tags.Is_Empty then
                  Append (Buf, Kind_Enum (CN, Info.Tags));
               end if;
               Append (Buf, "struct " & Pfx & CN & " {");
               Append (Buf, LF);
               if Idref then
                  Append (Buf, "    objid_t id, parent;");
                  Append (Buf, LF);
               end if;
               if not Info.Tags.Is_Empty then
                  Append (Buf, "    " & Pfx & CN & "_kind_t kind;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    " & L_Entry (Pfx & CN) & ";");
               Append (Buf, LF);
               if Info.Elem_Members.Is_Empty then
                  if Info.Elem_Name /= Null_Unbounded_String then
                     Append (Buf, "    " & Declarator
                       (C_Type_Of (To_String (Info.Elem_Name)),
                        C_Field (To_String (Info.Elem_Name))) & ";");
                  else
                     Append (Buf, "    const char *value;");
                  end if;
                  Append (Buf, LF);
               else
                  for M of Info.Elem_Members loop
                     Append (Buf, "    " & Declarator
                       (C_Type_Of (To_String (M.Name)),
                        C_Field (To_String (M.Name))) & ";");
                     Append (Buf, LF);
                  end loop;
               end if;
               if R.Action_Code /= Null_Unbounded_String then
                  Append (Buf, "    size_t _line;   /* for bind_error */");
                  Append (Buf, LF);
               end if;
               Append (Buf, "};");
               Append (Buf, LF);
         end case;

         if R.Trailing_Comment /= Null_Unbounded_String then
            Append (Buf, " /* " & To_String (R.Trailing_Comment) & " */");
            Append (Buf, LF);
         end if;
         return To_String (Buf);
      end Emit_Rule;

      --  Emit AST walk (visit) and transform (map) helpers: a node_kind_t
      --  tag per composite rule, plus visit_<rule>/map_<rule> functions that
      --  walk the typed tree the parser builds.  visit_ is pre-order and
      --  read-only; map_ is bottom-up and may mutate a node in place.  A
      --  scalar or enum member is a leaf and is not recursed into.
      procedure Emit_Walk (Buf : in out U) is

         function Ref_Kind (Name : String) return Class_Kind is
            J : constant Natural := Find (Alias_Target (Rules, Name));
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         --  The recursive call into node field `n-><Name>`: a by-value struct
         --  passes &n->f, a list head passes n->f, a leaf emits nothing.
         procedure Recurse (Name : String; Prefix : String;
                            Buf : in out U; Ind : String) is
            F : constant String := C_Field (Name);
         begin
            case Ref_Kind (Name) is
               when Struct =>
                  Append (Buf, Ind & Prefix & "_"
                    & C_Name (Alias_Target (Rules, Name))
                    & "(&n->" & F & ", f, ctx);");
               when List =>
                  Append (Buf, Ind & Prefix & "_"
                    & C_Name (Alias_Target (Rules, Name))
                    & "(&n->" & F & ", f, ctx);");
               when others =>
                  return;
            end case;
            Append (Buf, LF);
         end Recurse;

         --  The element fields of a list node: a single named element, the
         --  bare `value` field, or the members of a grouped element.
         procedure Recurse_Elem (Info : Rule_Info; Prefix : String;
                                 Buf : in out U; Ind : String) is
         begin
            if Info.Elem_Members.Is_Empty then
               if Info.Elem_Name /= Null_Unbounded_String then
                  Recurse (To_String (Info.Elem_Name), Prefix, Buf, Ind);
               end if;
            else
               for M of Info.Elem_Members loop
                  Recurse (To_String (M.Name), Prefix, Buf, Ind);
               end loop;
            end if;
         end Recurse_Elem;

         procedure Visit_Def (Idx : Natural; Buf : in out U) is
            CN   : constant String := C_Name (To_String (Rules (Idx).Name));
            TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
            Info : constant Rule_Info := Infos (Idx);
         begin
            if Info.Kind = Struct then
               Append (Buf, "static void visit_" & CN & "(const "
                 & TN & " *n, visit_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    if (!n) return;");
               Append (Buf, LF);
               Append (Buf, "    f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
               for M of Info.Members loop
                  Recurse (To_String (M.Name), "visit", Buf, "    ");
               end loop;
            else
               Append (Buf, "static void visit_" & CN & "(const struct " & Pfx & CN
                 & "_list *head, visit_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    const " & TN & " *n;");
               Append (Buf, LF);
               Append (Buf, "    " & L_Foreach ("n", "head") & " {");
               Append (Buf, LF);
               Append (Buf, "        f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
               Recurse_Elem (Info, "visit", Buf, "        ");
               Append (Buf, "    }");
               Append (Buf, LF);
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
         end Visit_Def;

         procedure Map_Def (Idx : Natural; Buf : in out U) is
            CN   : constant String := C_Name (To_String (Rules (Idx).Name));
            TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
            Info : constant Rule_Info := Infos (Idx);
         begin
            if Info.Kind = Struct then
               Append (Buf, "static void map_" & CN & "("
                 & TN & " *n, map_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    if (!n) return;");
               Append (Buf, LF);
               for M of Info.Members loop
                  Recurse (To_String (M.Name), "map", Buf, "    ");
               end loop;
               Append (Buf, "    f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
            else
               Append (Buf, "static void map_" & CN & "(struct " & Pfx & CN
                 & "_list *head, map_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    " & TN & " *n;");
               Append (Buf, LF);
               Append (Buf, "    " & L_Foreach ("n", "head") & " {");
               Append (Buf, LF);
               Recurse_Elem (Info, "map", Buf, "        ");
               Append (Buf, "        f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
               Append (Buf, "    }");
               Append (Buf, LF);
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
         end Map_Def;

      begin
         Append (Buf, "/* ---- AST traversal (visit) and transform (map) ---- */");
         Append (Buf, LF);
         Append (Buf, "typedef enum {");
         declare
            First : Boolean := True;
         begin
            for I in 1 .. N loop
               if Infos (I).Kind = Struct or else Infos (I).Kind = List then
                  if not First then
                     Append (Buf, ",");
                  end if;
                  Append (Buf, LF);
                  Append (Buf, "    NODE_" & C_Ident
                    (C_Name (To_String (Rules (I).Name))));
                  First := False;
               end if;
            end loop;
         end;
         Append (Buf, LF);
         Append (Buf, "} node_kind_t;");
         Append (Buf, LF);
         Append (Buf, LF);
         Append (Buf, "typedef void (*visit_fn)(const void *node,"
           & " node_kind_t kind, void *ctx);");
         Append (Buf, LF);
         Append (Buf, "typedef void (*map_fn)(void *node, node_kind_t kind,"
           & " void *ctx);");
         Append (Buf, LF);
         Append (Buf, LF);

         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               declare
                  CN : constant String := C_Name (To_String (Rules (I).Name));
                  TN : constant String := C_Type_Name (To_String (Rules (I).Name));
               begin
                  if Infos (I).Kind = List then
                     Append (Buf, "static void visit_" & CN & "(const struct " & Pfx & CN
                       & "_list *, visit_fn f, void *ctx);");
                     Append (Buf, LF);
                     Append (Buf, "static void map_" & CN & "(struct " & Pfx & CN
                       & "_list *, map_fn f, void *ctx);");
                  else
                     Append (Buf, "static void visit_" & CN & "(const "
                       & TN & " *, visit_fn f, void *ctx);");
                     Append (Buf, LF);
                     Append (Buf, "static void map_" & CN & "("
                       & TN & " *, map_fn f, void *ctx);");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, LF);

         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               Visit_Def (I, Buf);
               Append (Buf, LF);
               Map_Def (I, Buf);
               Append (Buf, LF);
            end if;
         end loop;
      end Emit_Walk;

      --  Emit bind_<rule>: the bottom-up walk that runs action jets.  After a
      --  successful parse it recurses into a node's children first (so a
      --  parent's action sees its children already processed) and then runs
      --  the rule's action code, if any.  Actions never run during parsing,
      --  so a backtracking re-parse cannot re-run their side effects.
      procedure Emit_Bind (Buf : in out U) is

         function Ref_Kind (Name : String) return Class_Kind is
            J : constant Natural := Find (Alias_Target (Rules, Name));
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         procedure Recurse (Name : String; Buf : in out U; Ind : String) is
            F : constant String := C_Field (Name);
         begin
            case Ref_Kind (Name) is
               when Struct | List =>
                  Append (Buf, Ind & "bind_"
                    & C_Name (Alias_Target (Rules, Name)) & "(&n->" & F & ");");
                  Append (Buf, LF);
               when others =>
                  null;
            end case;
         end Recurse;

         procedure Recurse_Elem (Info : Rule_Info; Buf : in out U; Ind : String)
         is
         begin
            if Info.Elem_Members.Is_Empty then
               if Info.Elem_Name /= Null_Unbounded_String then
                  Recurse (To_String (Info.Elem_Name), Buf, Ind);
               end if;
            else
               for M of Info.Elem_Members loop
                  Recurse (To_String (M.Name), Buf, Ind);
               end loop;
            end if;
         end Recurse_Elem;

         procedure Bind_Def (Idx : Natural; Buf : in out U) is
            CN   : constant String := C_Name (To_String (Rules (Idx).Name));
            TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
            Info : constant Rule_Info := Infos (Idx);
            Act  : constant String := To_String (Rules (Idx).Action_Code);
         begin
            if Info.Kind = Struct then
               Append (Buf, "static void bind_" & CN & "(" & TN & " *n) {");
               Append (Buf, LF);
               Append (Buf, "    if (!n) return;");
               Append (Buf, LF);
               for M of Info.Members loop
                  Recurse (To_String (M.Name), Buf, "    ");
               end loop;
               if Act /= "" then
                  Append (Buf, "    bind_line = n->_line;");
                  Append (Buf, LF);
                  Append (Buf, "    " & Act);
                  Append (Buf, LF);
               end if;
            else
               Append (Buf, "static void bind_" & CN & "(struct " & Pfx & CN
                 & "_list *head) {");
               Append (Buf, LF);
               Append (Buf, "    " & TN & " *n;");
               Append (Buf, LF);
               Append (Buf, "    " & L_Foreach ("n", "head") & " {");
               Append (Buf, LF);
               Recurse_Elem (Info, Buf, "        ");
               if Act /= "" then
                  Append (Buf, "        bind_line = n->_line;");
                  Append (Buf, LF);
                  Append (Buf, "        " & Act);
                  Append (Buf, LF);
               end if;
               Append (Buf, "    }");
               Append (Buf, LF);
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
         end Bind_Def;

      begin
         Append (Buf, "/* ---- bind (run action jets bottom-up, children first) ---- */");
         Append (Buf, LF);
         Append (Buf,
           "/* An action reports a semantic error with bind_error(""fmt"", ...)," & LF &
           "   as a parse.y action calls yyerror: the walk carries on, and the" & LF &
           "   parse fails once it ends.  The message is tagged with the line the" & LF &
           "   action's node starts on.  bind_report, when set, sees every error" & LF &
           "   (the --conf wrapper points it at conf_error); otherwise the first" & LF &
           "   becomes the parse error. */" & LF &
           "#include <stdarg.h>" & LF &
           "#include <stdio.h>" & LF &
           "static size_t bind_errors, bind_line, bind_err_line;" & LF &
           "static char bind_err_msg[512];" & LF &
           "static void (*bind_report)(size_t line, const char *msg);" & LF &
           "static void bind_error(const char *fmt, ...)" & LF &
           "    __attribute__((format(printf, 1, 2), unused));" & LF &
           "static void bind_error(const char *fmt, ...) {" & LF &
           "    char msg[512];" & LF &
           "    va_list ap;" & LF &
           "    va_start(ap, fmt);" & LF &
           "    vsnprintf(msg, sizeof msg, fmt, ap);" & LF &
           "    va_end(ap);" & LF &
           "    if (bind_errors++ == 0) {" & LF &
           "        bind_err_line = bind_line;" & LF &
           "        snprintf(bind_err_msg, sizeof bind_err_msg, ""%s"", msg);" & LF &
           "    }" & LF &
           "    if (bind_report) bind_report(bind_line, msg);" & LF &
           "}" & LF & LF);
         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               declare
                  CN : constant String := C_Name (To_String (Rules (I).Name));
                  TN : constant String :=
                    C_Type_Name (To_String (Rules (I).Name));
               begin
                  if Infos (I).Kind = List then
                     Append (Buf, "static void bind_" & CN & "(struct " & Pfx
                       & CN & "_list *head);");
                  else
                     Append (Buf, "static void bind_" & CN & "(" & TN & " *n);");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, LF);
         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               Bind_Def (I, Buf);
               Append (Buf, LF);
            end if;
         end loop;
      end Emit_Bind;

      --  Emit free_<rule>: drop a parsed tree, freeing every string and list
      --  node the parser allocated (the SIGHUP reload path).  A struct frees
      --  its contents in place (the struct itself is embedded); a list frees
      --  each node and resets the head.
      procedure Emit_Free (Buf : in out U) is

         function Ref_Kind (Name : String) return Class_Kind is
            J : constant Natural := Find (Alias_Target (Rules, Name));
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         --  Free the field `n-><F>`: recurse into a child struct/list, free a
         --  string leaf, leave a numeric/enum leaf alone.  The child's full
         --  free_<child> is called (a non-root child never touches the arena).
         procedure Free_Field (Name : String; Buf : in out U; Ind : String) is
            F : constant String := C_Field (Name);
         begin
            case Ref_Kind (Name) is
               when Struct | List =>
                  Append (Buf, Ind & "free_"
                    & C_Name (Alias_Target (Rules, Name))
                    & "(&n->" & F & ");");
                  Append (Buf, LF);
               when others =>
                  null;  --  string leaves point into the source/arena, not owned
            end case;
         end Free_Field;

         --  free_<CN>_fields: free the owned children of one node/element,
         --  without freeing the node itself or the arena.  Used by the public
         --  free_<CN> and by the backtracking reset, which frees a failed
         --  branch's partial allocations before zeroing the struct.
         procedure Free_Fields_Def (Idx : Natural; Buf : in out U) is
            CN   : constant String := C_Name (To_String (Rules (Idx).Name));
            TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
            Info : constant Rule_Info := Infos (Idx);
         begin
            Append (Buf, "static void free_" & CN & "_fields(" & TN & " *n) {");
            Append (Buf, LF);
            Append (Buf, "    if (!n) return;");
            Append (Buf, LF);
            if Info.Kind = Struct then
               for M of Info.Members loop
                  Free_Field (To_String (M.Name), Buf, "    ");
               end loop;
            elsif Info.Elem_Members.Is_Empty then
               if Info.Elem_Name /= Null_Unbounded_String then
                  Free_Field (To_String (Info.Elem_Name), Buf, "    ");
               end if;
            else
               for M of Info.Elem_Members loop
                  Free_Field (To_String (M.Name), Buf, "    ");
               end loop;
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
         end Free_Fields_Def;

         --  The public free_<CN>: frees the node/element's children, then the
         --  node itself for a list, then the arena at the root.
         procedure Free_Def (Idx : Natural; Buf : in out U) is
            CN   : constant String := C_Name (To_String (Rules (Idx).Name));
            TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
            Info : constant Rule_Info := Infos (Idx);
         begin
            if Info.Kind = Struct then
               Append (Buf, "static void free_" & CN & "(" & TN & " *n) {");
               Append (Buf, LF);
               Append (Buf, "    if (!n) return;");
               Append (Buf, LF);
               Append (Buf, "    free_" & CN & "_fields(n);");
               Append (Buf, LF);
            else
               Append (Buf, "static void free_" & CN & "(struct " & Pfx & CN
                 & "_list *head) {");
               Append (Buf, LF);
               Append (Buf, "    " & TN & " *n = " & L_First ("head") & ", *next;");
               Append (Buf, LF);
               Append (Buf, "    while (n) {");
               Append (Buf, LF);
               Append (Buf, "        next = " & L_Next ("n") & ";");
               Append (Buf, LF);
               Append (Buf, "        free_" & CN & "_fields(n);");
               Append (Buf, LF);
               Append (Buf, "        free(n);");
               Append (Buf, LF);
               Append (Buf, "        n = next;");
               Append (Buf, LF);
               Append (Buf, "    }");
               Append (Buf, LF);
               Append (Buf, "    " & L_Init ("head"));
               Append (Buf, LF);
            end if;
            if Idx = 1 then
               Append (Buf, "    free_arena();");
               Append (Buf, LF);
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
         end Free_Def;

      begin
         Append (Buf, "/* ---- free (drop a parsed tree) ---- */");
         Append (Buf, LF);

         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               declare
                  CN : constant String := C_Name (To_String (Rules (I).Name));
                  TN : constant String := C_Type_Name (To_String (Rules (I).Name));
               begin
                  Append (Buf, "static void free_" & CN & "_fields(" & TN
                    & " *n);");
                  Append (Buf, LF);
                  if Infos (I).Kind = List then
                     Append (Buf, "static void free_" & CN & "(struct " & Pfx & CN
                       & "_list *head);");
                  else
                     Append (Buf, "static void free_" & CN & "(" & TN & " *n);");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, LF);

         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               Free_Fields_Def (I, Buf);
               Append (Buf, LF);
               Free_Def (I, Buf);
               Append (Buf, LF);
            end if;
         end loop;
      end Emit_Free;

      --  relink_<CN>: the parser builds each list in a local head and copies
      --  structs out by value, which leaves a TAILQ's first tqe_prev (and an
      --  empty list's tail) pointing at the stack frame the head was built
      --  in.  After a successful parse one walk over the tree repoints them
      --  at the heads' final addresses, so the daemon may TAILQ_REMOVE,
      --  TAILQ_INSERT_* or TAILQ_CONCAT on the tree as on its own lists.
      --  The repoint itself is container-specific: the grammar's
      --  `list-relink { … }` override when present, else written directly
      --  for hbnf's own slist.
      procedure Emit_Relink (Buf : in out U) is

         function Ref_Kind (Name : String) return Class_Kind is
            J : constant Natural := Find (Alias_Target (Rules, Name));
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         --  True when the rule's value holds a list head somewhere inside it
         --  (itself, or a by-value struct member, transitively): only those
         --  paths need walking.
         function Holds_List (Name : String; Depth : Natural := 0)
           return Boolean is
            J : constant Natural := Find (Alias_Target (Rules, Name));
         begin
            if J = 0 or else Depth > 32 then
               return False;
            end if;
            case Infos (J).Kind is
               when List =>
                  return True;
               when Struct =>
                  declare
                     Info : constant Rule_Info := Infos (J);
                  begin
                     for M of Info.Members loop
                        if Holds_List (To_String (M.Name), Depth + 1) then
                           return True;
                        end if;
                     end loop;
                  end;
                  return False;
               when others =>
                  return False;
            end case;
         end Holds_List;

         function Elem_Holds_List (Info : Rule_Info) return Boolean is
         begin
            if Info.Elem_Members.Is_Empty then
               return Info.Elem_Name /= Null_Unbounded_String
                 and then Holds_List (To_String (Info.Elem_Name));
            end if;
            for M of Info.Elem_Members loop
               if Holds_List (To_String (M.Name)) then
                  return True;
               end if;
            end loop;
            return False;
         end Elem_Holds_List;

         procedure Field (Name : String; Buf : in out U) is
         begin
            if Ref_Kind (Name) in Struct | List and then Holds_List (Name) then
               Append (Buf, "    relink_" & C_Name (Alias_Target (Rules, Name))
                 & "(&n->" & C_Field (Name) & ");");
               Append (Buf, LF);
            end if;
         end Field;

         --  Only what the walk calls is emitted: relink_<rule> for the root
         --  and for every rule that holds a list (the only fields a parent
         --  walks into), and a list's relink_<rule>_fields only when its
         --  elements hold a list.  The rest would be unused static functions.
         function Need_Node (I : Positive) return Boolean is
           (I = 1 or else Holds_List (To_String (Rules (I).Name)));

         function Need_Fields (I : Positive) return Boolean is
           (if Infos (I).Kind = Struct then Need_Node (I)
            else Elem_Holds_List (Infos (I)));

      begin
         Append (Buf, "/* ---- relink (repoint list heads at their final address) ---- */");
         Append (Buf, LF);
         for I in 1 .. N loop
            if (Infos (I).Kind = Struct or else Infos (I).Kind = List)
              and then Need_Node (I)
            then
               declare
                  CN : constant String := C_Name (To_String (Rules (I).Name));
                  TN : constant String :=
                    C_Type_Name (To_String (Rules (I).Name));
               begin
                  if Need_Fields (I) then
                     Append (Buf, "static void relink_" & CN & "_fields(" & TN
                       & " *n);");
                     Append (Buf, LF);
                  end if;
                  if Infos (I).Kind = List then
                     Append (Buf, "static void relink_" & CN & "(struct " & Pfx
                       & CN & "_list *head);");
                  else
                     Append (Buf, "static void relink_" & CN & "(" & TN
                       & " *n);");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, LF);
         for I in 1 .. N loop
            if (Infos (I).Kind = Struct or else Infos (I).Kind = List)
              and then Need_Node (I)
            then
               declare
                  CN   : constant String := C_Name (To_String (Rules (I).Name));
                  TN   : constant String :=
                    C_Type_Name (To_String (Rules (I).Name));
                  Info : constant Rule_Info := Infos (I);
               begin
                  if Need_Fields (I) then
                     Append (Buf, "static void relink_" & CN & "_fields(" & TN
                       & " *n) {");
                     Append (Buf, LF);
                     Append (Buf, "    (void)n;");
                     Append (Buf, LF);
                     if Info.Kind = Struct then
                        for M of Info.Members loop
                           Field (To_String (M.Name), Buf);
                        end loop;
                     elsif Info.Elem_Members.Is_Empty then
                        if Info.Elem_Name /= Null_Unbounded_String then
                           Field (To_String (Info.Elem_Name), Buf);
                        end if;
                     else
                        for M of Info.Elem_Members loop
                           Field (To_String (M.Name), Buf);
                        end loop;
                     end if;
                     Append (Buf, "}");
                     Append (Buf, LF);
                  end if;
                  if Info.Kind = Struct then
                     Append (Buf, "static void relink_" & CN & "(" & TN
                       & " *n) { relink_" & CN & "_fields(n); }");
                     Append (Buf, LF);
                  else
                     Append (Buf, "static void relink_" & CN & "(struct " & Pfx
                       & CN & "_list *head) {");
                     Append (Buf, LF);
                     Append (Buf, "    " & L_Relink ("head"));
                     Append (Buf, LF);
                     if Elem_Holds_List (Info) then
                        Append (Buf, "    " & TN & " *n;");
                        Append (Buf, LF);
                        Append (Buf, "    " & L_Foreach ("n", "head") & " relink_"
                          & CN & "_fields(n);");
                        Append (Buf, LF);
                     end if;
                     Append (Buf, "}");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
      end Emit_Relink;

      Emitted   : array (1 .. N) of Boolean := [others => False];
      Remaining : Natural := 0;
      Res       : U;
      --  A rule with an action jet gets a bind walk; without one the walk is
      --  dead code, so it is emitted only when some rule has an action.
      Has_Action : constant Boolean :=
        (for some I in 1 .. N => Rules (I).Action_Code /= Null_Unbounded_String);
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (I));
      end loop;

      Append (Res, "/* generated by hbnf -- do not edit */");
      Append (Res, LF);
      if Preamble /= "" and then Language = "C" then
         Append (Res, Preamble);
         Append (Res, LF);
         Append (Res, LF);
      end if;
      Append (Res, "#include <stdint.h>");
      Append (Res, LF);
      Append (Res, "#include <stdbool.h>");
      Append (Res, LF);
      Append (Res, "#include <stddef.h>");
      Append (Res, LF);
      Append (Res, "#include <stdlib.h>");
      Append (Res, LF);
      Append (Res, "#include <string.h>");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "/* Out of memory in a small allocation (an arena chunk, the string");
      Append (Res, LF);
      Append (Res, "   scratch, a node): stop, as parse.y's lexer does with err(1, ...).  The");
      Append (Res, LF);
      Append (Res, "   token array, the one large allocation, fails the parse instead. */");
      Append (Res, LF);
      Append (Res, "#include <stdio.h>");
      Append (Res, LF);
      Append (Res, "static void hbnf_oom(void) {");
      Append (Res, LF);
      Append (Res, "    fputs(""hbnf: out of memory\n"", stderr);");
      Append (Res, LF);
      Append (Res, "    exit(1);");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, "/* Arena: a bump allocator over a chain of chunks, so a pointer into it");
      Append (Res, LF);
      Append (Res, "   stays valid for the arena's whole lifetime (chunks are never realloc'd).");
      Append (Res, LF);
      Append (Res, "   The tree's string leaves live here; free_arena walks the chain once. */");
      Append (Res, LF);
      Append (Res, "enum { HBNF_ARENA_CHUNK = 1 << 16 };");
      Append (Res, LF);
      Append (Res, "typedef struct hbnf_chunk hbnf_chunk;");
      Append (Res, LF);
      Append (Res, "struct hbnf_chunk { hbnf_chunk *next; size_t used, cap; char data[]; };");
      Append (Res, LF);
      Append (Res, "static hbnf_chunk *hbnf_arena;");
      Append (Res, LF);
      Append (Res, "/* Bump n zeroed bytes out of the arena, 8-byte aligned, never split");
      Append (Res, LF);
      Append (Res, "   across chunks. */");
      Append (Res, LF);
      Append (Res, "static void *hbnf_alloc(size_t n) {");
      Append (Res, LF);
      Append (Res, "    n = (n + 7u) & ~(size_t)7u;");
      Append (Res, LF);
      Append (Res, "    if (!hbnf_arena || hbnf_arena->used + n > hbnf_arena->cap) {");
      Append (Res, LF);
      Append (Res, "        size_t cap = n > (size_t)HBNF_ARENA_CHUNK ? n : (size_t)HBNF_ARENA_CHUNK;");
      Append (Res, LF);
      Append (Res, "        hbnf_chunk *c = (hbnf_chunk *)malloc(sizeof *c + cap);");
      Append (Res, LF);
      Append (Res, "        if (!c) hbnf_oom();");
      Append (Res, LF);
      Append (Res, "        c->next = hbnf_arena; c->used = 0; c->cap = cap;");
      Append (Res, LF);
      Append (Res, "        hbnf_arena = c;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    void *p = hbnf_arena->data + hbnf_arena->used;");
      Append (Res, LF);
      Append (Res, "    hbnf_arena->used += n;");
      Append (Res, LF);
      Append (Res, "    memset(p, 0, n);");
      Append (Res, LF);
      Append (Res, "    return p;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, "/* Copy a (non-NUL-terminated) token slice into the arena, NUL-terminated,");
      Append (Res, LF);
      Append (Res, "   and return it.  No per-string malloc. */");
      Append (Res, LF);
      Append (Res, "static const char *hbnf_str_append(const char *s, size_t n) {");
      Append (Res, LF);
      Append (Res, "    char *p = (char *)hbnf_alloc(n + 1);");
      Append (Res, LF);
      Append (Res, "    if (n) memcpy(p, s, n);");
      Append (Res, LF);
      Append (Res, "    return p;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, "/* Per-string scratch: the lexer unescapes a quoted string into it char by");
      Append (Res, LF);
      Append (Res, "   char, then copies the finished string into the arena.  Only the lexer");
      Append (Res, LF);
      Append (Res, "   holds a pointer into it, so its realloc never dangles the tree. */");
      Append (Res, LF);
      Append (Res, "static char *hbnf_scratch;");
      Append (Res, LF);
      Append (Res, "static size_t hbnf_scratch_len, hbnf_scratch_cap;");
      Append (Res, LF);
      Append (Res, "static void hbnf_str_put(char c) {");
      Append (Res, LF);
      Append (Res, "    if (hbnf_scratch_len + 1 > hbnf_scratch_cap) {");
      Append (Res, LF);
      Append (Res, "        hbnf_scratch_cap = hbnf_scratch_cap ? hbnf_scratch_cap * 2 : 64;");
      Append (Res, LF);
      Append (Res, "        char *ns = (char *)realloc(hbnf_scratch, hbnf_scratch_cap);");
      Append (Res, LF);
      Append (Res, "        if (!ns) hbnf_oom();");
      Append (Res, LF);
      Append (Res, "        hbnf_scratch = ns;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    hbnf_scratch[hbnf_scratch_len++] = c;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, "static void free_arena(void) {");
      Append (Res, LF);
      Append (Res, "    while (hbnf_arena) {");
      Append (Res, LF);
      Append (Res, "        hbnf_chunk *n = hbnf_arena->next;");
      Append (Res, LF);
      Append (Res, "        free(hbnf_arena);");
      Append (Res, LF);
      Append (Res, "        hbnf_arena = n;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    free(hbnf_scratch); hbnf_scratch = NULL;");
      Append (Res, LF);
      Append (Res, "    hbnf_scratch_len = hbnf_scratch_cap = 0;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);

      if Idref then
         Append (Res, "/* object id: assigned by the serializer, resolved on "
           & "the rebuild side */");
         Append (Res, LF);
         Append (Res, "typedef uint32_t objid_t;");
         Append (Res, LF);
         Append (Res, LF);
      end if;

      --  Forward-declare every struct and list node type; a list rule also
      --  gets its list head type.  A typed rule's type is external, so it
      --  is forward-declared as a typedef alias of the declared type.
      for I in 1 .. N loop
         if Is_By_Value (Infos (I)) or else Infos (I).Kind = List then
            if Rules (I).C_Type /= Null_Unbounded_String then
               Append (Res, "typedef " & Declarator
                 (To_String (Rules (I).C_Type),
                  C_Type_Name (To_String (Rules (I).Name))) & ";");
            else
               Append (Res, "typedef struct " & Pfx
                 & C_Name (To_String (Rules (I).Name))
                 & " " & C_Type_Name (To_String (Rules (I).Name)) & ";");
            end if;
            Append (Res, LF);
            if Infos (I).Kind = List then
               Append (Res, L_Head
                 (Pfx & C_Name (To_String (Rules (I).Name)) & "_list",
                  Pfx & C_Name (To_String (Rules (I).Name))) & ";");
               Append (Res, LF);
            end if;
            Remaining := Remaining + 1;
         end if;
      end loop;
      Append (Res, LF);

      --  Leaves: scalars and enums, in dependency order — a scalar alias
      --  referencing another rule's type (e.g. `addr = ipv4`) must follow it.
      declare
         function Scalar_Ref (Idx : Natural) return Natural is
            R : constant Rule := Rules (Idx);
            P : constant Element_Vectors.Vector := R.Pattern;
            J : Natural;
         begin
            if Natural (P.Length) = 1 and then P (1).Kind = Name
              and then Scalar_C_Type (To_String (P (1).Name)) = ""
            then
               J := Find (To_String (P (1).Name));
               --  A scalar alias over a struct or list (`src = host`) is a
               --  typedef, not a leaf that must follow its target: the struct
               --  is forward-declared, so the alias emits immediately.  Only a
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
            if Infos (I).Kind = Scalar or else Infos (I).Kind = Enum then
               Remaining_Leaves := Remaining_Leaves + 1;
            end if;
         end loop;
         while Remaining_Leaves > 0 loop
            declare
               Progress : Boolean := False;
            begin
               for I in 1 .. N loop
                  if (Infos (I).Kind = Scalar or else Infos (I).Kind = Enum)
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

      --  Struct and list bodies, in by-value dependency order.
      while Remaining > 0 loop
         declare
            Progress : Boolean := False;
         begin
            for I in 1 .. N loop
               if (Is_By_Value (Infos (I)) or else Infos (I).Kind = List)
                 and then not Emitted (I)
               then
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

      if Walkers then
         Emit_Walk (Res);
         Append (Res, LF);
      end if;

      Emit_Free (Res);
      Append (Res, LF);

      if Has_Relink then
         Emit_Relink (Res);
         Append (Res, LF);
      end if;

      if Has_Action then
         Emit_Bind (Res);
         Append (Res, LF);
      end if;

      return To_String (Res);
   end Emit;

   --  =====================================================================
   --  Parser emission: a self-contained recursive-descent parser that
   --  consumes a token stream and allocates/populates the structs above.
   --  =====================================================================

   --  The token kind a core scalar reads (mirrors the matcher's Match_Core).
   function Scalar_Tok_Kind (Name : String) return String is
   begin
      if Name = "str" then
         return "TOK_STR";
      elsif Name = "int" then
         return "TOK_INT";
      elsif Name'Length >= 2 then
         declare
            P : constant Character := Name (Name'First);
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            if (P = 'u' or else P = 'i')
              and then (for all C of R => C in '0' .. '9')
            then
               return "TOK_INT";
            end if;
         end;
      end if;
      return "TOK_ATOM";  --  atom / word / bool / flag
   end Scalar_Tok_Kind;

   --  A `word`/`atom` scalar is a bareword the lexer did NOT intern as a
   --  keyword; the match must reject keyword tokens, else `1*string` would
   --  swallow the next directive's keyword (parse.y's lexer reserves them).
   function Scalar_Kwid_Check (Name : String) return String is
   begin
      if Name = "atom" or else Name = "word" then
         return " && p->toks[p->pos].kwid == KWID_NONE";
      end if;
      return "";
   end Scalar_Kwid_Check;

   --  A human-readable description of a core scalar (for error messages).
   function Core_Desc (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return "a string";
      elsif Name = "bool" or else Name = "flag" then
         return "yes or no";
      else
         return "a number";  --  int / uN / iN
      end if;
   end Core_Desc;

   --  The C expression that converts the token at p->pos into a core value.
   function Scalar_Parse_Expr (Name : String) return String is
   begin
      if Name = "str" then
         --  Quoted strings are already unescaped into the arena, NUL-terminated.
         return "p->toks[p->pos].text";
      elsif Name = "atom" or else Name = "word" then
         return "hbnf_str_append(p->toks[p->pos].text, p->toks[p->pos].len)";
      elsif Name = "int" then
         return "atoll(p->toks[p->pos].text)";
      elsif Name = "bool" or else Name = "flag" then
         return "((p->toks[p->pos].len==3 && strncmp(p->toks[p->pos].text,""yes"",3)==0) "
           & "|| (p->toks[p->pos].len==2 && strncmp(p->toks[p->pos].text,""on"",2)==0) "
           & "|| (p->toks[p->pos].len==4 && strncmp(p->toks[p->pos].text,""true"",4)==0))";
      elsif Name'Length >= 2 then
         declare
            P : constant Character := Name (Name'First);
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            if (P = 'u' or else P = 'i')
              and then (for all C of R => C in '0' .. '9')
            then
               if P = 'u' then
                  return "(uint" & R
                    & "_t)strtoull(p->toks[p->pos].text, NULL, 10)";
               else
                  return "(int" & R
                    & "_t)strtoll(p->toks[p->pos].text, NULL, 10)";
               end if;
            end if;
         end;
      end if;
      return "hbnf_str_append(p->toks[p->pos].text, p->toks[p->pos].len)";
   end Scalar_Parse_Expr;

   --  True when a declared storage class is a fixed-size char buffer
   --  (`char[N]`, with whatever whitespace the schema used).
   function Is_Char_Array (C_Type : String) return Boolean is
   begin
      if C_Type'Length < 4
        or else C_Type (C_Type'First .. C_Type'First + 3) /= "char"
      then
         return False;
      end if;
      for C of C_Type (C_Type'First + 4 .. C_Type'Last) loop
         if C = '[' then
            return True;
         end if;
      end loop;
      return False;
   end Is_Char_Array;

   --  A pointer-to-array declaration for a `char[…]` storage class: the
   --  name is inserted inside the `(*)`, so `char[16]` becomes
   --  `char (*name)[ 16 ]` and `sizeof *name` is the array size.
   function Array_Ptr (C_Type : String; Name : String) return String is
      Buf  : U;
      Done : Boolean := False;
   begin
      for I in C_Type'Range loop
         if not Done and then C_Type (I) = '[' then
            Append (Buf, "(*" & Name & ")");
            Done := True;
         end if;
         Append (Buf, C_Type (I));
      end loop;
      return To_String (Buf);
   end Array_Ptr;

   --  The C text that stores a core-scalar value into a field whose rule
   --  declared a storage class: a `char[…]` is copied in (the value is a
   --  string), anything else is assigned with an explicit cast.
   function Scalar_Store (C_Type : String; Expr : String) return String is
   begin
      if Is_Char_Array (C_Type) then
         return "snprintf(*out, sizeof *out, ""%s"", " & Expr & ")";
      end if;
      return "*out = (" & C_Type & ")" & Expr;
   end Scalar_Store;

   --  True for the numeric core scalars (int / uN / iN), whose strtol/atoll
   --  conversion is deferred to the branch's commit point instead of running
   --  on every speculative branch.
   function Is_Number (Name : String) return Boolean is
   begin
      if Name = "int" then
         return True;
      end if;
      if Name'Length >= 2
        and then (Name (Name'First) = 'u' or else Name (Name'First) = 'i')
      then
         declare
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            return (for all C of R => C in '0' .. '9');
         end;
      end if;
      return False;
   end Is_Number;

   --  The conversion applied to a deferred number's text pointer.
   function Scalar_Convert (Name : String; Ref : String) return String is
   begin
      if Name = "int" then
         return "atoll(" & Ref & ")";
      elsif Name'Length >= 2 then
         declare
            P : constant Character := Name (Name'First);
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            if P = 'u' then
               return "(uint" & R & "_t)strtoull(" & Ref & ", NULL, 10)";
            elsif P = 'i' then
               return "(int" & R & "_t)strtoll(" & Ref & ", NULL, 10)";
            end if;
         end;
      end if;
      return "atoll(" & Ref & ")";
   end Scalar_Convert;

   --  The direct numeric scalar fields (int / uN / iN) of a flat pattern, in
   --  first-seen order, deduped.  Drives the deferred-number temporaries.
   function Numeric_Fields (Els : Element_Vectors.Vector)
     return String_Vectors.Vector is
      V : String_Vectors.Vector;

      function Present (S : U) return Boolean is
      begin
         for X of V loop
            if X = S then
               return True;
            end if;
         end loop;
         return False;
      end Present;

      --  Recurse into `( … )` groups: a number nested there still needs its
      --  `num_<field>` temporary declared at the commit point.
      procedure Collect (Es : Element_Vectors.Vector);

      procedure Collect (Es : Element_Vectors.Vector) is
      begin
         for E of Es loop
            if E.Kind = Name and then Is_Number (To_String (E.Name)) then
               if not Present (E.Name) then
                  V.Append (E.Name);
               end if;
            elsif E.Kind = Group then
               Collect (E.Items);
            end if;
         end loop;
      end Collect;
   begin
      Collect (Els);
      return V;
   end Numeric_Fields;

   function Emit_Parser (Rules : Rule_Vectors.Vector) return String is

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

      function Is_Core (Name : String) return Boolean is
        (Scalar_C_Type (Name) /= "");

      function Has_Alt (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Alt then
               return True;
            end if;
         end loop;
         return False;
      end Has_Alt;

      --  True when every `/`-alternative is exactly one Literal — the shape an
      --  enum can hold.  A multi-token alternative (`"a" "b" / "c" "d"`) or one
      --  that names another rule is not an enum.
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

      --  Every literal in the grammar, deduped in first-appearance order.
      --  These are the keywords the lexer interns against.
      function Collect_Keywords return String_Vectors.Vector is
         K : String_Vectors.Vector;

         function Present (S : U) return Boolean is
         begin
            for X of K loop
               if X = S then
                  return True;
               end if;
            end loop;
            return False;
         end Present;

         procedure Walk (Els : Element_Vectors.Vector) is
         begin
            for E of Els loop
               case E.Kind is
                  when Literal =>
                     declare
                        S : constant String := To_String (E.Lit);
                     begin
                        --  Keywords only: a letter/underscore-led literal
                        --  (punctuation and digit-led literals are not atoms).
                        if Is_Keyword_Lit (S)
                          and then not Present (E.Lit)
                        then
                           K.Append (E.Lit);
                        end if;
                     end;
                  when Group =>
                     Walk (E.Items);
                  when others =>
                     null;
               end case;
            end loop;
         end Walk;
      begin
         for I in 1 .. N loop
            Walk (Rules (I).Pattern);
         end loop;
         return K;
      end Collect_Keywords;

      Keywords : constant String_Vectors.Vector := Collect_Keywords;

      --  Emit the keyword-id enum plus the interning lookup: a switch on
      --  length, then first character, then one inlined memcmp per keyword in
      --  the bucket.  The compiler lowers the switches to jump tables.
      procedure Emit_Keywords (Buf : in out U) is
         function Len (K : U) return Natural is
           (To_String (K)'Length);

         function First (K : U) return Character is
           (To_String (K) (To_String (K)'First));

         function Max_Len return Natural is
            M : Natural := 0;
         begin
            for K of Keywords loop
               if Len (K) > M then
                  M := Len (K);
               end if;
            end loop;
            return M;
         end Max_Len;
      begin
         if Natural (Keywords.Length) >= 65535 then
            raise HBNF_Grammar.Parse_Error with
              "more than 65534 keywords: a token's keyword id is 16 bits";
         end if;
         Append (Buf, "typedef enum { KWID_NONE = 0");
         for K of Keywords loop
            Append (Buf, ", KW_" & C_Ident (To_String (K)));
         end loop;
         Append (Buf, " } kwid_t;");
         Append (Buf, LF);
         Append (Buf, LF);

         Append (Buf, "static kwid_t kw_lookup(const char *s, size_t len) {");
         Append (Buf, LF);
         Append (Buf, "    switch (len) {");
         Append (Buf, LF);
         for L in 1 .. Max_Len loop
            declare
               Seen : array (Character) of Boolean := (others => False);
               Any  : Boolean := False;
            begin
               for K of Keywords loop
                  if Len (K) = L then
                     Any := True;
                     exit;
                  end if;
               end loop;
               if Any then
                  Append (Buf, "    case " & Img (L) & ":");
                  Append (Buf, LF);
                  Append (Buf, "        switch (s[0]) {");
                  Append (Buf, LF);
                  for K of Keywords loop
                     if Len (K) = L and then not Seen (First (K)) then
                        Seen (First (K)) := True;
                        Append (Buf, "        case '" & First (K) & "':");
                        Append (Buf, LF);
                        for K2 of Keywords loop
                           if Len (K2) = L and then First (K2) = First (K) then
                              Append (Buf, "            if (memcmp(s, """
                                & C_Escape (To_String (K2)) & """, " & Img (L)
                                & ") == 0) return KW_" & C_Ident (To_String (K2)) & ";");
                              Append (Buf, LF);
                           end if;
                        end loop;
                        Append (Buf, "            break;");
                        Append (Buf, LF);
                     end if;
                  end loop;
                  Append (Buf, "        }");
                  Append (Buf, LF);
                  Append (Buf, "        break;");
                  Append (Buf, LF);
               end if;
            end;
         end loop;
         Append (Buf, "    }");
         Append (Buf, LF);
         Append (Buf, "    return KWID_NONE;");
         Append (Buf, LF);
         Append (Buf, "}");
         Append (Buf, LF);
      end Emit_Keywords;

      --  The underlying scalar C type a rule name resolves to (chasing
      --  single-name aliases and jets); "" if not scalar.
      function Resolve_Type (N : String; Depth : Natural := 0) return String is
         C : constant String := Scalar_C_Type (N);
      begin
         if C /= "" then
            return C;
         end if;
         if Depth > 8 then
            return "";
         end if;
         declare
            J : constant Natural := Find (N);
         begin
            if J = 0 then
               return "";
            end if;
            declare
               R : constant Rule := Rules (J);
               P : constant Element_Vectors.Vector := R.Pattern;
            begin
               if R.Jet_Code /= Null_Unbounded_String then
                  return "const char *";
               end if;
               if Natural (P.Length) = 1
                 and then P (1).Kind = Name
                 and then P (1).Min = 1
                 and then P (1).Max = 1
               then
                  return Resolve_Type (To_String (P (1).Name), Depth + 1);
               end if;
            end;
         end;
         return "";
      end Resolve_Type;

      --  A pure alternation of names resolving to one scalar type; "" else.
      function Scalar_Union_Type (Els : Element_Vectors.Vector) return String is
         T       : U := Null_Unbounded_String;
         Has_Alt : Boolean := False;
      begin
         for E of Els loop
            if E.Kind = Alt then
               Has_Alt := True;
            elsif E.Kind = Name then
               declare
                  R : constant String := Resolve_Type (To_String (E.Name));
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

      --  The out-parameter type of parse_<rule>: a list hands back a list
      --  head (`struct <CN>_list *`), anything else a by-value struct/scalar
      --  (`<CN>_t *`).
      function Out_Type (Idx : Natural) return String is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if R.C_Type /= Null_Unbounded_String then
            if Is_Char_Array (To_String (R.C_Type)) then
               return Array_Ptr (To_String (R.C_Type), "out");
            end if;
            return To_String (R.C_Type) & " *out";
         end if;
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            return "struct " & Pfx & C_Name (To_String (R.Name)) & "_list *out";
         end if;
         return C_Type_Name (To_String (R.Name)) & " *out";
      end Out_Type;

      --  Emit matching + building for segment Els(First..Last), writing fields
      --  through the accessor Acc ("r." or "nn->").  On failure emits the
      --  `Fail` statement ("goto ..." or "p->pos = save; return false;").
      procedure Emit_Seq
        (Els : Element_Vectors.Vector; First, Last : Natural; Acc : String;
         Buf  : in out U; Fail : String; Ind : String := "    ";
         Typed : Boolean := False) is
      begin
         for K in First .. Last loop
            declare
               E : constant Element_Access := Els (K);
            begin
               case E.Kind is
                  when Literal =>
                     Append (Buf, Ind & "if (!expect_lit(p, """
                       & C_Escape (To_String (E.Lit)) & """, "
                       & Img (To_String (E.Lit)'Length) & ")) { " & Fail & " }");
                     Append (Buf, LF);
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        Append (Buf, Ind & "if (!expect_kind(p, "
                          & Scalar_Tok_Kind (To_String (E.Name)) & ", """
                          & Core_Desc (To_String (E.Name)) & """)) { " & Fail & " }");
                        Append (Buf, LF);
                        if Is_Number (To_String (E.Name)) then
                           Append (Buf, Ind & "num_"
                             & C_Field (To_String (E.Name))
                             & " = p->toks[p->pos].text; p->pos++;");
                        else
                           Append (Buf, Ind & Acc
                             & C_Field (To_String (E.Name)) & " = "
                             & Scalar_Parse_Expr (To_String (E.Name)) & "; p->pos++;");
                        end if;
                        Append (Buf, LF);
                     else
                        declare
                           J         : constant Natural := Find (To_String (E.Name));
                           Is_Scalar : constant Boolean :=
                             J > 0
                             and then Rules (J).C_Type = Null_Unbounded_String
                             and then Resolve_Type (To_String (E.Name)) /= "";
                        begin
                           if Typed and then Is_Scalar then
                              --  The struct declared an external storage class,
                              --  so this field's C type may be narrower than the
                              --  scalar rule's own type.  Parse into a temporary
                              --  of the rule's type, assign, and range-check the
                              --  truncation/sign change in one comparison.
                              Append (Buf, Ind & "{");
                              Append (Buf, LF);
                              Append (Buf, Ind & "    " & C_Type_Name
                                (To_String (E.Name)) & " _tmp;");
                              Append (Buf, LF);
                              Append (Buf, Ind & "    size_t _tok = p->pos;");
                              Append (Buf, LF);
                              Append (Buf, Ind & "    if (!parse_rule_"
                                & C_Name (To_String (E.Name)) & "(p, &_tmp)) { "
                                & Fail & " }");
                              Append (Buf, LF);
                              Append (Buf, Ind & "    " & Acc
                                & C_Field (To_String (E.Name)) & " = _tmp;");
                              Append (Buf, LF);
                              Append (Buf, Ind & "    if (" & Acc
                                & C_Field (To_String (E.Name)) & " != _tmp) { "
                                & "fail_range(p, _tok, """
                                & C_Field (To_String (E.Name)) & """); "
                                & Fail & " }");
                              Append (Buf, LF);
                              Append (Buf, Ind & "}");
                              Append (Buf, LF);
                           else
                              Append (Buf, Ind & "if (!parse_rule_"
                                & C_Name (To_String (E.Name)) & "(p, &" & Acc
                                & C_Field (To_String (E.Name)) & ")) { " & Fail & " }");
                              Append (Buf, LF);
                           end if;
                        end;
                     end if;
                  when Group =>
                     Emit_Seq (E.Items, 1, Natural (E.Items.Length), Acc, Buf,
                               Fail, Ind & "    ", Typed);
                  when Alt =>
                     null;
               end case;
            end;
         end loop;
      end Emit_Seq;

      --  FIRST-set computation for keyword dispatch: the literal keywords that
      --  can begin an element, transitively through rule references.  A core
      --  scalar (word / atom / int / str / …) or a jet has no bounded keyword
      --  set, so it makes the whole alternation fall back to linear probing.
      function Is_Keyword (S : String) return Boolean is
        (S'Length > 0
         and then (S (S'First) in 'a' .. 'z'
                   or else S (S'First) in 'A' .. 'Z'
                   or else S (S'First) = '_'));

      function First_Union (A : String_Vectors.Vector; B : String_Vectors.Vector)
        return String_Vectors.Vector is
         R : String_Vectors.Vector := A;
      begin
         for S of B loop
            declare
               Present : Boolean := False;
            begin
               for X of R loop
                  if X = S then
                     Present := True;
                  end if;
               end loop;
               if not Present then
                  R.Append (S);
               end if;
            end;
         end loop;
         return R;
      end First_Union;

      --  A FIRST-set member standing for "a token that is not a keyword":
      --  punctuation, a digit-led literal, or a jet's own token kind.  Such a
      --  token has kwid KWID_NONE, and can never be a keyword, so a branch
      --  that starts with one is reached through `case KWID_NONE` while a
      --  keyword that starts no branch still fails fast.  (It cannot clash
      --  with a keyword: those start with a letter or `_`.)
      Other_Tok : constant U := To_Unbounded_String ("<non-keyword>");

      function First_Of (Els : Element_Vectors.Vector; Depth : Natural;
                         Known : out Boolean) return String_Vectors.Vector;
      function First_Elem (E : Element_Access; Depth : Natural;
                           Known : out Boolean) return String_Vectors.Vector;

      function First_Elem (E : Element_Access; Depth : Natural;
                           Known : out Boolean) return String_Vectors.Vector is
         V : String_Vectors.Vector;
      begin
         Known := True;
         if Depth > 8 then
            Known := False;
            return V;
         end if;
         --  A nullable leading element (e.g. `[ "x" ]`) can match without its
         --  keyword, so its FIRST set is not a complete dispatch key: a switch
         --  whose default fails fast would wrongly reject a token the branch
         --  matches as empty.  Mark it unknown to fall back to linear probing.
         if E.Min = 0 then
            Known := False;
            return V;
         end if;
         case E.Kind is
            when Literal =>
               if Is_Keyword (To_String (E.Lit)) then
                  V.Append (E.Lit);
               else
                  V.Append (Other_Tok);
               end if;
            when Name =>
               if Is_Core (To_String (E.Name)) then
                  Known := False;
               else
                  declare
                     J : constant Natural := Find (To_String (E.Name));
                  begin
                     if J = 0 then
                        Known := False;
                     elsif Rules (J).Jet_Code /= Null_Unbounded_String then
                        --  A jet has no pattern: it is its own token kind.
                        V.Append (Other_Tok);
                     else
                        return First_Of (Rules (J).Pattern, Depth + 1, Known);
                     end if;
                  end;
               end if;
            when Group =>
               return First_Of (E.Items, Depth + 1, Known);
            when Alt =>
               null;
         end case;
         return V;
      end First_Elem;

      function First_Of (Els : Element_Vectors.Vector; Depth : Natural;
                         Known : out Boolean) return String_Vectors.Vector is
      begin
         Known := True;
         if Els.Is_Empty then
            return String_Vectors.Empty_Vector;
         end if;
         if Has_Alt (Els) then
            declare
               R  : String_Vectors.Vector;
               St : Natural := 1;
               K  : Boolean;
            begin
               for I in 1 .. Natural (Els.Length) + 1 loop
                  if I > Natural (Els.Length) or else Els (I).Kind = Alt then
                     if St <= I - 1 then
                        R := First_Union
                          (R, First_Elem (Els (St), Depth, K));
                        if not K then
                           Known := False;
                        end if;
                     end if;
                     St := I + 1;
                  end if;
               end loop;
               return R;
            end;
         else
            return First_Elem (Els (1), Depth, Known);
         end if;
      end First_Of;

      --  The FIRST set of each '/' branch, flattened into one vector: branch
      --  Br's keywords are Flat (Offs (Br) .. Offs (Br + 1) - 1).  Offs is
      --  empty when any branch's leading keyword is unbounded (a core scalar
      --  or jet), so the caller falls back to linear probing.
      procedure Branch_Firsts
        (Els  : Element_Vectors.Vector;
         Flat : out String_Vectors.Vector;
         Offs : out Natural_Vectors.Vector) is
         St : Natural := 1;
         K  : Boolean;
      begin
         Offs.Clear;
         for I in 1 .. Natural (Els.Length) + 1 loop
            if I > Natural (Els.Length) or else Els (I).Kind = Alt then
               if St <= I - 1 then
                  declare
                     F : constant String_Vectors.Vector :=
                       First_Elem (Els (St), 0, K);
                  begin
                     if not K then
                        Offs.Clear;
                        Flat.Clear;
                        return;
                     end if;
                     Offs.Append (Natural (Flat.Length) + 1);
                     for S of F loop
                        Flat.Append (S);
                     end loop;
                  end;
               end if;
               St := I + 1;
            end if;
         end loop;
         Offs.Append (Natural (Flat.Length) + 1);
      end Branch_Firsts;

      --  True when keyword K leads branch Br and no other branch -- i.e. the
      --  switch can jump straight to Br on K.
      function Unique_To
        (K : U; Flat : String_Vectors.Vector; Offs : Natural_Vectors.Vector;
         Br : Positive) return Boolean is
      begin
         if K = Other_Tok then
            return False;
         end if;
         for X in 1 .. Natural (Offs.Length) - 1 loop
            if X /= Br then
               for I in Offs (X) .. Offs (X + 1) - 1 loop
                  if Flat (I) = K then
                     return False;
                  end if;
               end loop;
            end if;
         end loop;
         return True;
      end Unique_To;

      --  The branch keyword K uniquely starts (0 when K starts no branch, or
      --  two or more branches).
      function Unique_Branch
        (K : U; Flat : String_Vectors.Vector; Offs : Natural_Vectors.Vector)
        return Natural is
         Br : Natural := 0;
      begin
         for X in 1 .. Natural (Offs.Length) - 1 loop
            for I in Offs (X) .. Offs (X + 1) - 1 loop
               if Flat (I) = K then
                  if Br = 0 then
                     Br := X;
                  else
                     return 0;
                  end if;
               end if;
            end loop;
         end loop;
         return Br;
      end Unique_Branch;

      --  True when some branch after the first has a keyword unique to it, so
      --  a switch dispatch pays for itself.
      function Has_Dispatch
        (Flat : String_Vectors.Vector; Offs : Natural_Vectors.Vector)
        return Boolean is
      begin
         for X in 2 .. Natural (Offs.Length) - 1 loop
            for I in Offs (X) .. Offs (X + 1) - 1 loop
               if Unique_To (Flat (I), Flat, Offs, X) then
                  return True;
               end if;
            end loop;
         end loop;
         return False;
      end Has_Dispatch;

      --  Emit a backtracking alternation over the alternatives in Els (a flat
      --  list with Alt separators).  Each branch writes through Acc; a failed
      --  branch restores p->pos and resets the struct (Reset), a successful
      --  branch jumps to label `Ok`.  After the last branch fails, control
      --  falls through for the caller's own failure handling.
      procedure Emit_Alternation
        (Els : Element_Vectors.Vector; Acc, Reset, Ok : String;
         Kind_Prefix : String := "";
         Buf : in out U; Ind : String := "    ") is
         N    : constant Natural := Natural (Els.Length);
         Flat : String_Vectors.Vector;
         Offs : Natural_Vectors.Vector;

         function Img (X : Natural) return String is
            S : constant String := Natural'Image (X);
         begin
            if S'Length > 0 and then S (S'First) = ' ' then
               return S (S'First + 1 .. S'Last);
            end if;
            return S;
         end Img;

         --  The linear ordered-choice chain: try each branch in source order,
         --  restoring p->pos and resetting the struct between attempts.  After
         --  the last branch fails, control falls through to the caller's own
         --  failure handling.
         procedure Emit_Linear is
            LSt : Natural := 1;
            LBr : Natural := 0;
         begin
            for K in 1 .. N + 1 loop
               if K > N or else Els (K).Kind = Alt then
                  LBr := LBr + 1;
                  if LBr > 1 then
                     Append (Buf, Ind & "p->pos = save; " & Reset & ";");
                     Append (Buf, LF);
                  end if;
                  Emit_Seq (Els, LSt, K - 1, Acc, Buf,
                            "goto alt_fail_" & Img (LBr) & ";", Ind);
                  if Kind_Prefix /= "" and then LSt <= K - 1
                    and then Els (LSt).Kind = Literal
                  then
                     Append (Buf, Ind & Acc & "kind = " & Kind_Prefix & "_"
                       & C_Ident (To_String (Els (LSt).Lit)) & ";");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, Ind & "goto " & Ok & ";");
                  Append (Buf, LF);
                  Append (Buf, "alt_fail_" & Img (LBr) & ":");
                  Append (Buf, LF);
                  LSt := K + 1;
               end if;
            end loop;
         end Emit_Linear;
      begin
         Branch_Firsts (Els, Flat, Offs);
         if not Offs.Is_Empty and then Has_Dispatch (Flat, Offs) then
            --  Keyword dispatch: an O(1) jump table on the interned keyword
            --  id.  A keyword unique to one branch jumps straight to that
            --  branch's body in the linear chain below (branch 1 is entered
            --  via alt_linear); a keyword shared by two branches falls to the
            --  chain to try them in order; anything else (a non-keyword, or a
            --  keyword no branch can start with) fails fast on the last
            --  branch's label, instead of probing every branch.
            Append (Buf, Ind & "switch (p->toks[p->pos].kwid) {");
            Append (Buf, LF);
            for X in 2 .. Natural (Offs.Length) - 1 loop
               declare
                  Emitted : Boolean := False;
               begin
                  for I in Offs (X) .. Offs (X + 1) - 1 loop
                     if Unique_To (Flat (I), Flat, Offs, X) then
                        Append (Buf, Ind & "case KW_"
                          & C_Ident (To_String (Flat (I))) & ":");
                        Append (Buf, LF);
                        Emitted := True;
                     end if;
                  end loop;
                  if Emitted then
                     Append (Buf, Ind & "    goto alt_fail_"
                       & Img (X - 1) & ";");
                     Append (Buf, LF);
                  end if;
               end;
            end loop;
            for I in 1 .. Natural (Flat.Length) loop
               declare
                  K    : constant U := Flat (I);
                  Seen : Boolean := False;
                  Br   : Natural;
               begin
                  for J in 1 .. I - 1 loop
                     if Flat (J) = K then
                        Seen := True;
                     end if;
                  end loop;
                  if not Seen and then K /= Other_Tok then
                     --  A keyword the switch does not jump straight on (it
                     --  leads branch 1, or several branches) enters the chain
                     --  to honour source order.
                     Br := Unique_Branch (K, Flat, Offs);
                     if Br <= 1 then
                        Append (Buf, Ind & "case KW_" & C_Ident (To_String (K))
                          & ": goto alt_linear;");
                        Append (Buf, LF);
                     end if;
                  end if;
               end;
            end loop;
            --  The end of input (with `statements`, of every statement): no
            --  branch can start there (none is nullable, or there would be
            --  no dispatch), so fail at once, recording what probing the
            --  chain would have -- the first branch's first keyword.
            declare
               Last : constant String := Img (Natural (Offs.Length) - 1);
               At_End : constant String :=
                 "if (p->toks[p->pos].kind == TOK_EOF) { fail(p, """
                 & C_Escape (To_String (Flat (1))) & """, 1, "
                 & "p->toks[p->pos].text); goto alt_fail_" & Last & "; }";
            begin
               if Flat.Contains (Other_Tok) then
                  --  Some branch starts with a non-keyword token: try the
                  --  chain for one.  A keyword no branch starts with cannot
                  --  match those branches, so it still fails fast below.
                  if Flat (1) /= Other_Tok then
                     Append (Buf, Ind & "case KWID_NONE:");
                     Append (Buf, LF);
                     Append (Buf, Ind & "    " & At_End);
                     Append (Buf, LF);
                     Append (Buf, Ind & "    goto alt_linear;");
                  else
                     Append (Buf, Ind & "case KWID_NONE: goto alt_linear;");
                  end if;
                  Append (Buf, LF);
               else
                  Append (Buf, Ind & "case KWID_NONE:");
                  Append (Buf, LF);
                  Append (Buf, Ind & "    " & At_End);
                  Append (Buf, LF);
                  Append (Buf, Ind & "    goto alt_fail_" & Last & ";");
                  Append (Buf, LF);
               end if;
            end;
            Append (Buf, Ind & "default: goto alt_fail_"
              & Img (Natural (Offs.Length) - 1) & ";");
            Append (Buf, LF);
            Append (Buf, Ind & "}");
            Append (Buf, LF);
            Append (Buf, "alt_linear:");
            Append (Buf, LF);
            Emit_Linear;
         else
            Emit_Linear;
         end if;
      end Emit_Alternation;

      --  Deferred-number plumbing: a numeric field (`int` / `uN` / `iN`) is
      --  parsed into a `num_<field>` text pointer and converted only at the
      --  branch's commit point, so speculative branches skip the strtol/atoll.

      procedure Emit_Number_Deferrals
        (Nums : String_Vectors.Vector; Buf : in out U; Ind : String) is
      begin
         for N of Nums loop
            Append (Buf, Ind & "const char *num_"
              & C_Field (To_String (N)) & " = NULL;");
            Append (Buf, LF);
         end loop;
      end Emit_Number_Deferrals;

      procedure Emit_Number_Converts
        (Nums : String_Vectors.Vector; Acc : String; Check : Boolean;
         Buf : in out U; Ind : String) is
      begin
         for N of Nums loop
            if Check then
               Append (Buf, Ind & "if (num_" & C_Field (To_String (N)) & ") "
                 & Acc & C_Field (To_String (N)) & " = "
                 & Scalar_Convert (To_String (N),
                                   "num_" & C_Field (To_String (N))) & ";");
            else
               Append (Buf, Ind & Acc & C_Field (To_String (N)) & " = "
                 & Scalar_Convert (To_String (N),
                                   "num_" & C_Field (To_String (N))) & ";");
            end if;
            Append (Buf, LF);
         end loop;
      end Emit_Number_Converts;

      --  The `; num_<field> = NULL` statements folded into an alternation's
      --  reset, so a branch that leaves a field unset does not inherit a
      --  stale pointer from an earlier speculative branch.
      function Num_Clears (Nums : String_Vectors.Vector) return String is
         S : U;
      begin
         for N of Nums loop
            Append (S, "; num_" & C_Field (To_String (N)) & " = NULL");
         end loop;
         return To_String (S);
      end Num_Clears;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         CN : constant String := C_Name (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Is_Pure_Literal_Alt (P);
         SU : constant String := (if not Is_List then Scalar_Union_Type (P) else "");
      begin
         if R.Jet_Code /= Null_Unbounded_String then
            --  A jet: match its own token kind and yield the matched text.
            Append (Buf, "    if (!expect_kind(p, TOK_" & C_Ident (NM)
              & ", ""a " & NM & """)) return false;");
            Append (Buf, LF);
            Append (Buf, "    *out = hbnf_str_append(p->toks[p->pos].text,"
              & " p->toks[p->pos].len); p->pos++;");
            Append (Buf, LF);
            Append (Buf, "    return true;");
            Append (Buf, LF);
            return;
         end if;
         if Is_List then
            declare
               E : constant Element_Access := P (1);
               --  With `statements` the root list is read one statement at
               --  a time, and a statement is one entry, as each of parse.y's
               --  `grammar : grammar entry '\n'` productions is.
               Max : constant Integer :=
                 (if Idx = 1 and then HBNF_Grammar.Statements then 1
                  else E.Max);
               Bounded : constant Boolean := E.Min > 0 or else Max >= 0;
               Nums : constant String_Vectors.Vector :=
                 (if E.Kind = Group then Numeric_Fields (E.Items)
                  else String_Vectors.Empty_Vector);
            begin
               Append (Buf, "    struct " & Pfx & C_Name (NM) & "_list head;");
               Append (Buf, LF);
               Append (Buf, "    " & L_Init ("&head"));
               Append (Buf, LF);
               --  Repetition bounds: only a bounded rule pays for the count.
               if Bounded then
                  Append (Buf, "    size_t count = 0;");
                  Append (Buf, LF);
               end if;
               if E.Min > 0 then
                  Append (Buf, "    size_t start = p->pos;");
                  Append (Buf, LF);
               end if;
               if Max >= 0 then
                  Append (Buf, "    while (p->pos < p->n && count < "
                    & Img (Natural (Max)) & ") {");
               else
                  Append (Buf, "    while (p->pos < p->n) {");
               end if;
               Append (Buf, LF);
               Append (Buf, "        " & C_Type_Name (NM) & " *nn ="
                 & " calloc(1, sizeof(*nn));");
               Append (Buf, LF);
               Append (Buf, "        if (!nn) hbnf_oom();");
               Append (Buf, LF);
               Append (Buf, "        size_t save = p->pos;");
               Append (Buf, LF);
               Emit_Number_Deferrals (Nums, Buf, "        ");
               if E.Kind = Name and then Is_Core (To_String (E.Name)) then
                  --  A list of a core type (`1*word`): read the token in
                  --  place; there is no parse_rule_ function for a core type.
                  Append (Buf, "        if (p->toks[p->pos].kind == "
                    & Scalar_Tok_Kind (To_String (E.Name))
                    & Scalar_Kwid_Check (To_String (E.Name))
                    & ") { nn->"
                    & C_Field (To_String (E.Name)) & " = "
                    & Scalar_Parse_Expr (To_String (E.Name))
                    & "; p->pos++; goto have; }");
                  Append (Buf, LF);
                  Append (Buf, "        fail(p, """ & Core_Desc (To_String (E.Name))
                    & """, 0, p->toks[p->pos].text);");
                  Append (Buf, LF);
               elsif E.Kind = Name then
                  Append (Buf, "        if (parse_rule_" & C_Name (To_String (E.Name))
                    & "(p, &nn->" & C_Field (To_String (E.Name)) & ")) goto have;");
                  Append (Buf, LF);
               else
                  declare
                     Tags : constant String_Vectors.Vector :=
                       Leading_Tags (E.Items);
                  begin
                     Emit_Alternation
                       (E.Items, "nn->",
                        "free_" & CN & "_fields(nn); memset(nn, 0, sizeof *nn)"
                        & Num_Clears (Nums),
                        "have",
                        (if Tags.Is_Empty then "" else C_Ident (CN)),
                        Buf, "        ");
                  end;
               end if;
               Append (Buf, "        p->pos = save; free(nn); break;");
               Append (Buf, LF);
               Append (Buf, "have:");
               Append (Buf, LF);
               Emit_Number_Converts (Nums, "nn->", True, Buf, "        ");
               if R.Action_Code /= Null_Unbounded_String then
                  Append (Buf, "        nn->_line = p->toks[save].line;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "        " & L_Append ("&head", "nn"));
               Append (Buf, LF);
               if Bounded then
                  Append (Buf, "        count++;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    }");
               Append (Buf, LF);
               if E.Min > 0 then
                  --  The root's free_ also frees the arena, which the
                  --  error message still reads: free just the nodes there.
                  if Idx = 1 then
                     Append (Buf, "    if (count < " & Img (E.Min) & ") { "
                       & C_Type_Name (NM) & " *dn = " & L_First ("&head")
                       & ", *dx; while (dn) { dx = " & L_Next ("dn")
                       & "; free_" & CN & "_fields(dn); free(dn); dn = dx; }"
                       & " p->pos = start; return false; }");
                  else
                     Append (Buf, "    if (count < " & Img (E.Min) & ") { free_"
                       & CN & "(&head); p->pos = start; return false; }");
                  end if;
                  Append (Buf, LF);
               end if;
               Append (Buf, "    *out = head; return true;");
               Append (Buf, LF);
            end;
         elsif Is_Enum then
            declare
               Lits  : String_Vectors.Vector;
               Names : String_Vectors.Vector;
            begin
               --  Collect each alternative's literal, in order, for naming.
               declare
                  St : Natural := 1;
               begin
                  for K in 1 .. Natural (P.Length) + 1 loop
                     if K > Natural (P.Length) or else P (K).Kind = Alt then
                        if St <= K - 1 and then P (St).Kind = Literal then
                           Lits.Append (P (St).Lit);
                        end if;
                        St := K + 1;
                     end if;
                  end loop;
               end;
               Names := Enum_Names (Lits);

               --  Each alternative checks the token itself: a keyword by its
               --  keyword id, any other literal by its text.  No kind gate: a
               --  non-keyword literal like "*" may arrive as a jet's token
               --  (commonconf's wildcard), which is not an atom.
               Append (Buf, "    if (p->pos >= p->n) { fail(p, ""a " & CN
                 & """, 0, ""end of input""); return false; }");
               Append (Buf, LF);
               Append (Buf, "    {");
               Append (Buf, LF);
               Append (Buf, "        " & C_Type_Name (NM) & " r = " & C_Ident (NM) & "_"
                 & To_String (Names (1)) & ";");
               Append (Buf, LF);
               declare
                  St     : Natural := 1;
                  Branch : Natural := 0;
               begin
                  for K in 1 .. Natural (P.Length) + 1 loop
                     if K > Natural (P.Length) or else P (K).Kind = Alt then
                        if St <= K - 1 and then P (St).Kind = Literal then
                           declare
                              L    : constant String := To_String (P (St).Lit);
                              Cond : constant String :=
                                (if Is_Keyword_Lit (L)
                                 then "p->toks[p->pos].kwid == KW_" & C_Ident (L)
                                 else "p->toks[p->pos].len == strlen("
                                   & '"' & C_Escape (L) & '"'
                                   & ") && strncmp(p->toks[p->pos].text, "
                                   & '"' & C_Escape (L) & '"'
                                   & ", p->toks[p->pos].len)==0");
                           begin
                              Append (Buf, (if Branch = 0 then "        if ("
                                            else "        else if (")
                                & Cond & ")");
                           end;
                           Append (Buf, " r = " & C_Ident (NM) & "_"
                             & To_String (Names (Branch + 1)) & ";");
                           Append (Buf, LF);
                           Branch := Branch + 1;
                        end if;
                        St := K + 1;
                     end if;
                  end loop;
               end;
               Append (Buf, "        else { fail(p, """);
               declare
                  St     : Natural := 1;
                  First  : Boolean := True;
               begin
                  for K in 1 .. Natural (P.Length) + 1 loop
                     if K > Natural (P.Length) or else P (K).Kind = Alt then
                        if St <= K - 1 and then P (St).Kind = Literal then
                           if not First then
                              Append (Buf, " or ");
                           end if;
                           Append (Buf, "`" & C_Escape (To_String (P (St).Lit)) & "`");
                           First := False;
                        end if;
                        St := K + 1;
                     end if;
                  end loop;
               end;
               Append (Buf, """, 0, p->toks[p->pos].text); return false; }");
               Append (Buf, LF);
               Append (Buf, "        p->pos++; *out = r; return true;");
               Append (Buf, LF);
               Append (Buf, "    }");
               Append (Buf, LF);
            end;
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            --  A scalar alias: read a core token, or delegate to the rule.
            if Is_Core (To_String (P (1).Name)) then
               Append (Buf, "    if (!expect_kind(p, "
                 & Scalar_Tok_Kind (To_String (P (1).Name)) & ", """
                 & Core_Desc (To_String (P (1).Name)) & """)) return false;");
               Append (Buf, LF);
               if R.C_Type /= Null_Unbounded_String then
                  if Is_Char_Array (To_String (R.C_Type)) then
                     Append (Buf, "    if (snprintf(*out, sizeof *out, ""%s"", "
                       & Scalar_Parse_Expr (To_String (P (1).Name))
                       & ") >= (int)sizeof *out) {");
                     Append (Buf, LF);
                     Append (Buf, "        fail(p, ""a string that fits `"
                       & To_String (R.Name) & "`"", 0, p->toks[p->pos].text);"
                       & " return false; }");
                     Append (Buf, LF);
                     Append (Buf, "    p->pos++;");
                  else
                     Append (Buf, "    "
                       & Scalar_Store (To_String (R.C_Type),
                                       Scalar_Parse_Expr (To_String (P (1).Name)))
                       & "; p->pos++;");
                  end if;
               else
                  Append (Buf, "    *out = "
                    & Scalar_Parse_Expr (To_String (P (1).Name)) & "; p->pos++;");
               end if;
               Append (Buf, LF);
               Append (Buf, "    return true;");
               Append (Buf, LF);
            else
               Append (Buf, "    return parse_rule_" & C_Name (To_String (P (1).Name))
                 & "(p, out);");
               Append (Buf, LF);
            end if;
         elsif SU /= "" then
            --  A scalar union (str / word, ipv4 / ipv6): try each branch as a
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
                              Append (Buf, "    if (p->pos < p->n && p->toks[p->pos].kind == "
                                & Scalar_Tok_Kind (To_String (E.Name))
                                & Scalar_Kwid_Check (To_String (E.Name))
                                & ") {");
                              Append (Buf, LF);
                              Append (Buf, "        *out = "
                                & Scalar_Parse_Expr (To_String (E.Name))
                                & "; p->pos++; return true; }");
                              Append (Buf, LF);
                           elsif E.Kind = Name then
                              Append (Buf, "    if (parse_rule_"
                                & C_Name (To_String (E.Name)) & "(p, out)) return true;");
                              Append (Buf, LF);
                           end if;
                        end;
                     end if;
                     St := K + 1;
                  end if;
               end loop;
            end;
            Append (Buf, "    fail(p, ""a " & NM & """, 0, p->pos < p->n"
              & " ? p->toks[p->pos].text : ""end of input"");");
            Append (Buf, LF);
            Append (Buf, "    return false;");
            Append (Buf, LF);
         elsif Has_Alt (P) then
            --  A struct alternation: try each branch with backtracking.
            declare
               Nums : constant String_Vectors.Vector := Numeric_Fields (P);
            begin
               Append (Buf, "    size_t save = p->pos;");
               Append (Buf, LF);
               Append (Buf, "    " & C_Type_Name (NM) & " r = {0};");
               Append (Buf, LF);
               Emit_Number_Deferrals (Nums, Buf, "    ");
               Emit_Alternation (P, "r.",
                                 "free_" & CN & "_fields(&r); memset(&r, 0, sizeof r)"
                                 & Num_Clears (Nums),
                                 "ok",
                                 (if Leading_Tags (P).Is_Empty then "" else C_Ident (CN)),
                                 Buf);
               --  The last branch failed: free what it built (a list it
               --  had filled before a later token failed), as each
               --  earlier branch's failure does.
               Append (Buf, "    p->pos = save; free_" & CN
                 & "_fields(&r); return false;");
               Append (Buf, LF);
               Append (Buf, "ok:");
               Append (Buf, LF);
               Emit_Number_Converts (Nums, "r.", True, Buf, "    ");
               if R.Action_Code /= Null_Unbounded_String then
                  Append (Buf, "    r._line = p->toks[save].line;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    *out = r; return true;");
               Append (Buf, LF);
            end;
         else
            --  A struct sequence: match literals and references in order.
            declare
               Nums : constant String_Vectors.Vector := Numeric_Fields (P);
            begin
               Append (Buf, "    size_t save = p->pos;");
               Append (Buf, LF);
               Append (Buf, "    " & C_Type_Name (NM) & " r = {0};");
               Append (Buf, LF);
               Emit_Number_Deferrals (Nums, Buf, "    ");
               --  On failure, free what the sequence built so far (its
               --  lists): the caller only restores the position.  The
               --  _fields variant, since the root's free_ also frees the
               --  arena, which the error message still reads.
               Emit_Seq (P, 1, Natural (P.Length), "r.", Buf,
                         (if R.C_Type = Null_Unbounded_String
                            and then Analyze (Rules, Idx).Kind = Struct
                          then "free_" & CN & "_fields(&r); "
                          else "")
                         & "p->pos = save; return false;",
                         Typed => R.C_Type /= Null_Unbounded_String);
               Emit_Number_Converts (Nums, "r.", False, Buf, "    ");
               if R.Action_Code /= Null_Unbounded_String then
                  Append (Buf, "    r._line = p->toks[save].line;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    *out = r; return true;");
               Append (Buf, LF);
            end;
         end if;
      end Emit_Rule_Parser;

      --  A typed rule declares an external C storage class; only then can a
      --  scalar field's declared type differ from the scalar rule's own type,
      --  so only then is the range-check (and its custom error) emitted.
      Has_Typed : constant Boolean :=
        (for some I in 1 .. N => Rules (I).C_Type /= Null_Unbounded_String);

      --  A rule with an action jet gets a bind walk; without one the walk is
      --  dead code, so it is emitted only when some rule has an action.
      Has_Action : constant Boolean :=
        (for some I in 1 .. N => Rules (I).Action_Code /= Null_Unbounded_String);

      --  `statements`: what the driver (templates/statements.c) needs from
      --  the grammar -- the root list's operations, whether an action jet
      --  has already reported a failed bind, and the `macros` and
      --  `includes` rules tried on each parsed statement.
      procedure Emit_Statement_Hooks (Res : in out U) is
         RC : constant String := C_Name (To_String (Rules (1).Name));
         RH : constant String := Root_Type (Rules);
         RE : constant String := C_Type_Name (To_String (Rules (1).Name));

         procedure Line (S : String) is
         begin
            Append (Res, S);
            Append (Res, LF);
         end Line;

         --  static bool/char *<Fn>(toks, n): does rule Name match the whole
         --  statement?  The rule's value is built and freed again.
         procedure Whole (Fn, Name, Ret, Yes, No : String) is
            J    : constant Natural := Find (Name);
            T    : constant String := Alias_Target (Rules, Name);
            K    : constant Natural := Find (T);
            Decl : constant String := Out_Type (J);
         begin
            Line ("static " & Ret & Fn
                  & "(const token_t *toks, size_t n) {");
            Line ("    parser_t p = { toks, n, 0, NULL, (size_t)-1, 0, 0 };");
            Line ("    " & Decl (Decl'First .. Decl'Last - 4) & "v;");
            Line ("    bool whole;");
            Line ("");
            Line ("    memset(&v, 0, sizeof v);");
            Line ("    whole = parse_rule_" & C_Name (Name) & "(&p, &v)");
            Line ("        && p.pos < p.n && p.toks[p.pos].kind == TOK_EOF;");
            if K /= 0 and then Analyze (Rules, K).Kind in Struct | List then
               Line ("    free_" & C_Name (T) & "(&v);");
            end if;
            if Yes = "true" and then No = "false" then
               Line ("    return whole;");
            else
               Line ("    return whole ? " & Yes & " : " & No & ";");
            end if;
            Line ("}");
            Line ("");
         end Whole;
      begin
         Line ("");
         Line ("/* ---- statements: the grammar's side of the driver ---- */");
         Line ("static void hbnf_part_init(" & RH & " *h) { "
               & L_Init ("h") & " }");
         Line ("");
         Line ("/* Move a statement's entries to the end of the config. */");
         Line ("static void hbnf_part_move(" & RH & " *dst, " & RH
               & " *src) {");
         Line ("    " & RE & " *n = " & L_First ("src") & ", *next;");
         Line ("    while (n) {");
         Line ("        next = " & L_Next ("n") & ";");
         Line ("        " & L_Append ("dst", "n"));
         Line ("        n = next;");
         Line ("    }");
         Line ("    " & L_Init ("src"));
         Line ("}");
         Line ("");
         Line ("/* A failed statement's entries go; the strings they point to"
               & " stay in the");
         Line ("   arena with the rest of the config's. */");
         Line ("static void hbnf_part_drop(" & RH & " *h) {");
         Line ("    " & RE & " *n = " & L_First ("h") & ", *next;");
         Line ("    while (n) {");
         Line ("        next = " & L_Next ("n") & ";");
         Line ("        free_" & RC & "_fields(n);");
         Line ("        free(n);");
         Line ("        n = next;");
         Line ("    }");
         Line ("    " & L_Init ("h"));
         Line ("}");
         Line ("");
         Line ("/* Nothing is kept: the entries and the string arena go. */");
         Line ("static void hbnf_part_free(" & RH & " *h) { free_" & RC
               & "(h); }");
         Line ("");
         Line ("/* A bind failure an action jet has already reported. */");
         if Has_Action then
            Line ("static int hbnf_bind_reported(void) {"
                  & " return bind_errors && bind_report; }");
         else
            Line ("static int hbnf_bind_reported(void) { return 0; }");
         end if;
         Line ("");
         if HBNF_Grammar.Macros_Rule /= "" then
            Line ("/* `macros " & HBNF_Grammar.Macros_Rule
                  & "`: this statement defines a macro. */");
            Whole ("hbnf_is_macro", HBNF_Grammar.Macros_Rule, "bool ",
                   "true", "false");
         end if;
         if HBNF_Grammar.Includes_Rule /= "" then
            Line ("/* `includes " & HBNF_Grammar.Includes_Rule
                  & "`: this statement includes the file its last token"
                  & " names. */");
            Whole ("hbnf_include_tok", HBNF_Grammar.Includes_Rule,
                   "const token_t *", "&toks[p.pos - 1]", "NULL");
         else
            Line ("static const token_t *hbnf_include_tok(const token_t *toks,"
                  & " size_t n) {");
            Line ("    (void)toks;");
            Line ("    (void)n;");
            Line ("    return NULL;");
            Line ("}");
         end if;
      end Emit_Statement_Hooks;

      Res : U;
   begin
      Append (Res, "/* generated by hbnf -- do not edit */");
      Append (Res, LF);
      Append (Res, "#include <stdlib.h>");
      Append (Res, LF);
      Append (Res, "#include <string.h>");
      Append (Res, LF);
      Append (Res, "#include <stdio.h>");
      Append (Res, LF);
      Append (Res, "#include <ctype.h>");
      Append (Res, LF);
      Append (Res, LF);
      declare
         Enum : U := To_Unbounded_String
           ("typedef enum { TOK_ATOM, TOK_STR, TOK_INT, TOK_PUNCT");
      begin
         for I in 1 .. N loop
            if Rules (I).Jet_Code /= Null_Unbounded_String then
               Append (Enum, ", TOK_"
                 & C_Ident (To_String (Rules (I).Name)));
            end if;
         end loop;
         Append (Enum, ", TOK_EOF } tok_kind_t;");
         Append (Res, To_String (Enum));
         Append (Res, LF);
      end;
      Emit_Keywords (Res);
      Append (Res, LF);
      --  24 bytes a token (was 48): the lexer checks the input fits in
      --  32-bit offsets, and kinds and keyword ids fit in 16 bits (checked
      --  when generating).
      Append (Res, "typedef struct { const char *text; uint32_t len, line, col;"
        & " uint16_t kind, kwid; } token_t;");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "typedef struct {");
      Append (Res, LF);
      Append (Res, "    const token_t *toks;");
      Append (Res, LF);
      Append (Res, "    size_t n, pos;");
      Append (Res, LF);
      Append (Res, "    const char *text;   /* source, for the lazy caret line */");
      Append (Res, LF);
      Append (Res, "    size_t err_pos;");
      Append (Res, LF);
      Append (Res, "    size_t err_line, err_col;");
      Append (Res, LF);
      Append (Res, "    const char *err_expected, *err_found;");
      Append (Res, LF);
      Append (Res, "    int err_is_lit;");
      Append (Res, LF);
      Append (Res, "} parser_t;");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "/* The line the text being lexed starts on: 1 for a whole file,"
        & " a statement's");
      Append (Res, LF);
      Append (Res, "   first line when a config is read one statement at a time. */");
      Append (Res, LF);
      Append (Res, "static size_t hbnf_line_base = 1;");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "static void fail(parser_t *p, const char *expected,"
        & " int is_lit, const char *found) {");
      Append (Res, LF);
      Append (Res, "    if (p->err_pos != (size_t)-1 && p->pos <= p->err_pos)"
        & " return;  /* a deeper failure already recorded */");
      Append (Res, LF);
      Append (Res, "    p->err_pos = p->pos;");
      Append (Res, LF);
      Append (Res, "    p->err_expected = expected; p->err_found = found;"
        & " p->err_is_lit = is_lit;");
      Append (Res, LF);
      Append (Res, "    p->err_line = p->pos < p->n ? p->toks[p->pos].line : 0;");
      Append (Res, LF);
      Append (Res, "    p->err_col  = p->pos < p->n ? p->toks[p->pos].col  : 0;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);
      if Has_Typed then
         Append (Res, "/* A value did not fit its field's declared type: report it as");
         Append (Res, LF);
         Append (Res, "   ""<value>: out of range for `field`"" at the value, not at the");
         Append (Res, LF);
         Append (Res, "   token after it.  err_is_lit = 2 marks the custom format. */");
         Append (Res, LF);
         Append (Res, "static void fail_range(parser_t *p, size_t pos, const char *field) {");
         Append (Res, LF);
         Append (Res, "    if (p->err_pos != (size_t)-1 && pos <= p->err_pos) return;");
         Append (Res, LF);
         Append (Res, "    p->err_pos = pos;");
         Append (Res, LF);
         Append (Res, "    p->err_expected = field; p->err_found = p->toks[pos].text;");
         Append (Res, LF);
         Append (Res, "    p->err_is_lit = 2;");
         Append (Res, LF);
         Append (Res, "    p->err_line = pos < p->n ? p->toks[pos].line : 0;");
         Append (Res, LF);
         Append (Res, "    p->err_col  = pos < p->n ? p->toks[pos].col  : 0;");
         Append (Res, LF);
         Append (Res, "}");
         Append (Res, LF);
         Append (Res, LF);
      end if;
      Append (Res, "static bool expect_lit(parser_t *p, const char *lit,"
        & " size_t lit_len) {");
      Append (Res, LF);
      Append (Res, "    if (p->pos < p->n && (p->toks[p->pos].kind == TOK_ATOM"
        & " || p->toks[p->pos].kind == TOK_PUNCT)");
      Append (Res, LF);
      Append (Res, "        && p->toks[p->pos].text && p->toks[p->pos].len == lit_len");
      Append (Res, LF);
      Append (Res, "        && strncmp(p->toks[p->pos].text, lit, p->toks[p->pos].len) == 0) {");
      Append (Res, LF);
      Append (Res, "        p->pos++; return true;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    fail(p, lit, 1, p->pos < p->n ? p->toks[p->pos].text"
        & " : ""end of input""); return false;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "static bool expect_kind(parser_t *p, tok_kind_t k,"
        & " const char *desc) {");
      Append (Res, LF);
      Append (Res, "    if (p->pos < p->n && p->toks[p->pos].kind == k"
        & " && (k != TOK_ATOM || p->toks[p->pos].kwid == KWID_NONE)) return true;");
      Append (Res, LF);
      Append (Res, "    fail(p, desc, 0, p->pos < p->n ? p->toks[p->pos].text"
        & " : ""end of input"");");
      Append (Res, LF);
      Append (Res, "    return false;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);

      --  Forward declarations of every parse function.
      for I in 1 .. N loop
         Append (Res, "static bool parse_rule_" & C_Name (To_String (Rules (I).Name))
           & "(parser_t *p, " & Out_Type (I) & ");");
         Append (Res, LF);
      end loop;
      Append (Res, LF);

      for I in 1 .. N loop
         declare
            R : constant Rule := Rules (I);
         begin
            Append (Res, "static bool parse_rule_" & C_Name (To_String (R.Name))
              & "(parser_t *p, " & Out_Type (I) & ") {");
            Append (Res, LF);
            Emit_Rule_Parser (I, Res);
            Append (Res, "}");
            Append (Res, LF);
            Append (Res, LF);
         end;
      end loop;

      --  The entry point: parse the root rule, then reject trailing input.
      Append (Res, "bool parse_tokens(const token_t *toks, size_t n, "
        & Out_Type (1) & ",");
      Append (Res, LF);
      Append (Res, "                  const char *text,");
      Append (Res, LF);
      Append (Res, "                  char *err, size_t errlen,"
        & " size_t *err_line, size_t *err_col) {");
      Append (Res, LF);
      Append (Res, "    parser_t p = { toks, n, 0, text, (size_t)-1, 0, 0 };");
      Append (Res, LF);
      Append (Res, "    if (!parse_rule_" & C_Name (To_String (Rules (1).Name))
        & "(&p, out)) goto err;");
      Append (Res, LF);
      --  Input left over: with `statements`, nothing on the line was a
      --  statement, or something follows one.
      Append (Res, "    if (p.pos < p.n && p.toks[p.pos].kind != TOK_EOF) { fail(&p, "
        & (if HBNF_Grammar.Statements
           then "p.pos == 0 ? ""a statement"" : ""end of statement"""
           else """end of config""")
        & ", 0, p.toks[p.pos].text); goto err; }");
      Append (Res, LF);
      if Analyze (Rules, 1).Kind in Struct | List and then Has_Relink then
         Append (Res, "    relink_" & C_Name (To_String (Rules (1).Name))
           & "(out);");
         Append (Res, LF);
      end if;
      if Analyze (Rules, 1).Kind in Struct | List and then Has_Action then
         Append (Res, "    bind_errors = 0; bind_line = 0; bind_err_line = 0;"
           & " bind_err_msg[0] = '\0';");
         Append (Res, LF);
         Append (Res, "    bind_" & C_Name (To_String (Rules (1).Name))
           & "(out);");
         Append (Res, LF);
         Append (Res, "    if (bind_errors) {");
         Append (Res, LF);
         Append (Res, "        snprintf(err, errlen, ""%s"", bind_err_msg);");
         Append (Res, LF);
         Append (Res, "        *err_line = bind_err_line; *err_col = 0;");
         Append (Res, LF);
         Append (Res, "        return false;");
         Append (Res, LF);
         Append (Res, "    }");
         Append (Res, LF);
      end if;
      Append (Res, "    return true;");
      Append (Res, LF);
      Append (Res, "err:");
      Append (Res, LF);
      --  Found at the end: the EOF token's text is empty, so say what ends
      --  there (a statement, with `statements`; else the input).
      Append (Res, "    { const char *f = p.err_found ? p.err_found"
        & " : ""end of input"";");
      Append (Res, LF);
      Append (Res, "      int at_end = p.err_pos >= p.n"
        & " || p.toks[p.err_pos].kind == TOK_EOF;");
      Append (Res, LF);
      Append (Res, "      if (at_end) f = """
        & (if HBNF_Grammar.Statements then "end of statement"
           else "end of input") & """;");
      Append (Res, LF);
      Append (Res, "      size_t fl = at_end ? strlen(f)"
        & " : p.toks[p.err_pos].len;");
      Append (Res, LF);
      Append (Res, "      char want[160];");
      Append (Res, LF);
      if Has_Typed then
         Append (Res, "      if (p.err_is_lit == 2) snprintf(want, sizeof want,"
           & " ""%.*s: out of range for `%s`"", (int)fl, f,"
           & " p.err_expected ? p.err_expected : """");");
         Append (Res, LF);
         Append (Res, "      else if (p.err_is_lit) snprintf(want, sizeof want, ""`%s`"","
           & " p.err_expected ? p.err_expected : """");");
         Append (Res, LF);
         Append (Res, "      else snprintf(want, sizeof want, ""%s"","
           & " p.err_expected ? p.err_expected : """");");
         Append (Res, LF);
      else
         Append (Res, "      if (p.err_is_lit) snprintf(want, sizeof want, ""`%s`"","
           & " p.err_expected ? p.err_expected : """");");
         Append (Res, LF);
         Append (Res, "      else snprintf(want, sizeof want, ""%s"","
           & " p.err_expected ? p.err_expected : """");");
         Append (Res, LF);
      end if;
      Append (Res, "      if (p.text && p.err_line >= hbnf_line_base) {");
      Append (Res, LF);
      Append (Res, "          const char *l; size_t ll;");
      Append (Res, LF);
      Append (Res, "          { const char *s = p.text;"
        & " size_t ln = p.err_line - hbnf_line_base + 1;");
      Append (Res, LF);
      Append (Res, "            while (ln > 1) {");
      Append (Res, LF);
      Append (Res, "                const char *nl = strchr(s, '\n');");
      Append (Res, LF);
      Append (Res, "                if (!nl) break;");
      Append (Res, LF);
      Append (Res, "                s = nl + 1; ln--;");
      Append (Res, LF);
      Append (Res, "            }");
      Append (Res, LF);
      Append (Res, "            const char *nl = strchr(s, '\n');");
      Append (Res, LF);
      Append (Res, "            l = s; ll = nl ? (size_t)(nl - s) : strlen(s); }");
      Append (Res, LF);
      Append (Res, "          char pad[64];");
      Append (Res, LF);
      Append (Res, "          size_t w = p.err_col > 1 ? p.err_col - 1 : 0;");
      Append (Res, LF);
      Append (Res, "          if (w > sizeof pad - 1) w = sizeof pad - 1;");
      Append (Res, LF);
      Append (Res, "          memset(pad, ' ', w); pad[w] = '\0';");
      Append (Res, LF);
      if Has_Typed then
         Append (Res, "          if (p.err_is_lit == 2) snprintf(err, errlen,"
           & " ""%s\n  %.*s\n  %s^"", want, (int)ll, l, pad);");
         Append (Res, LF);
         Append (Res, "          else snprintf(err, errlen,"
           & " ""expected %s, found %.*s\n  %.*s\n  %s^"", want, (int)fl, f, (int)ll, l, pad);");
         Append (Res, LF);
      else
         Append (Res, "          snprintf(err, errlen,"
           & " ""expected %s, found %.*s\n  %.*s\n  %s^"", want, (int)fl, f, (int)ll, l, pad);");
         Append (Res, LF);
      end if;
      Append (Res, "      } else {");
      Append (Res, LF);
      if Has_Typed then
         Append (Res, "          if (p.err_is_lit == 2) snprintf(err, errlen, ""%s"", want);");
         Append (Res, LF);
         Append (Res, "          else snprintf(err, errlen, ""expected %s, found %.*s"","
           & " want, (int)fl, f);");
         Append (Res, LF);
      else
         Append (Res, "          snprintf(err, errlen, ""expected %s, found %.*s"","
           & " want, (int)fl, f);");
         Append (Res, LF);
      end if;
      Append (Res, "      }");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    *err_line = p.err_line; *err_col = p.err_col;");
      Append (Res, LF);
      Append (Res, "    return false;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);

      --  Jets: hand-written scanners, plus the dispatch the lexer calls.
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               R  : constant Rule := Rules (I);
               NM : constant String := To_String (R.Name);
            begin
               Append (Res, "static size_t jet_" & C_Name (NM)
                 & "(const char *s, size_t pos, size_t len) {");
               Append (Res, LF);
               Append (Res, To_String (R.Jet_Code));
               Append (Res, LF);
               Append (Res, "}");
               Append (Res, LF);
               Append (Res, LF);
            end;
         end if;
      end loop;

      Append (Res, "static size_t jet_dispatch(const char *s, size_t pos,"
        & " size_t len, tok_kind_t *kind) {");
      Append (Res, LF);
      for I in 1 .. N loop
         if Rules (I).Jet_Code /= Null_Unbounded_String then
            declare
               NM : constant String := To_String (Rules (I).Name);
            begin
               Append (Res, "    { size_t n = jet_" & C_Name (NM)
                 & "(s, pos, len); if (n > 0) { *kind = TOK_" & C_Ident (NM)
                 & "; return n; } }");
               Append (Res, LF);
            end;
         end if;
      end loop;
      Append (Res, "    return 0;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);

      if HBNF_Grammar.Statements then
         Emit_Statement_Hooks (Res);
      end if;

      return To_String (Res);
   end Emit_Parser;

   function Emit_Lexer
     (Rules      : Rule_Vectors.Vector;
      Text_Entry : Boolean := True) return String
   is
      Root_T : constant String := Root_Type (Rules);
      Wc     : U;
      Res    : U;

      procedure Add (Template : String) is
      begin
         Append (Res, LF);
         Append (Res, Templates.Substitute (Template, "@ROOT_TYPE@", Root_T));
      end Add;
   begin
      for C of Word_Chars loop
         Append (Wc, " || c == '" & C & "'");
      end loop;
      Append (Res, Templates.Substitute
                (Templates.C_Lexer, "@WORD_CHARS@", To_String (Wc)));
      Append (Res, LF);
      if HBNF_Grammar.Statements then
         --  The statement driver, the macro expansion (or its stubs), and
         --  parse_text over the driver.
         Add (Templates.C_Statements);
         Add (if HBNF_Grammar.Macros_Rule /= "" then Templates.C_Macros
              else Templates.C_No_Macros);
         if Text_Entry then
            Add (Templates.C_Stmt_Text);
         end if;
      else
         Add (Templates.C_Parse_Text);
      end if;
      if Epilogue /= "" then
         Append (Res, LF);
         Append (Res, Epilogue);
      end if;
      return To_String (Res);
   end Emit_Lexer;

   --  conf.h: the declarations plus the global `conf`, the error callback and
   --  the parse_config prototype.
   function Emit_Conf_Header (Rules : Rule_Vectors.Vector) return String is
      Root_T : constant String := Root_Type (Rules);
      Conf_T : constant String := HBNF_Grammar.Conf_Type;
      Tail   : constant String :=
        (if Conf_T /= "" then
            Templates.Substitute
              (Templates.Substitute
                 (Templates.Conf_H_Typed, "@CONF_TYPE@", Conf_T),
               "@ROOT_TYPE@", Root_T)
         else
            Templates.Substitute (Templates.Conf_H, "@ROOT_TYPE@", Root_T));

      --  `struct X` / `union X` can be declared ahead of the prototype, so
      --  the header stands alone; a typedef name comes from the daemon's
      --  own header, included before this one.
      function Forward return String is
        ((if (Conf_T'Length > 7
              and then Conf_T (Conf_T'First .. Conf_T'First + 6) = "struct ")
           or else (Conf_T'Length > 6
                    and then Conf_T (Conf_T'First .. Conf_T'First + 5)
                             = "union ")
          then Conf_T & ";" & LF & LF
          else ""));

      --  `macros`: -D name=value, as the daemons' cmdline_symset.
      Symset : constant String :=
        (if HBNF_Grammar.Macros_Rule /= "" then
            LF & LF & "/* -D name=value: a macro the config cannot redefine; -1"
            & " without `=`. */" & LF & "int cmdline_symset(char *s);" & LF
         else "");
   begin
      if Conf_T /= "" then
         --  A daemon binding: the daemon's own header declares its conf
         --  struct and parse_config, and nothing but conf.c includes this
         --  one, so it carries declarations only; the code is in conf.c.
         return
           "#ifndef CONF_H" & LF &
           "#define CONF_H" & LF & LF &
           "#include <stddef.h>" & LF & LF &
           Forward &
           Tail &
           Symset &
           LF &
           "#endif" & LF;
      end if;
      return
        "#ifndef CONF_H" & LF &
        "#define CONF_H" & LF & LF &
        Emit (Rules) &
        LF &
        Tail &
        Symset &
        LF &
        "#endif" & LF;
   end Emit_Conf_Header;

   --  conf.c: the lexer + parser plus the global `conf` and parse_config
   --  (slurp the file, populate conf, report errors through the callback).
   function Emit_Conf_Source (Rules : Rule_Vectors.Vector) return String is
      Root_T : constant String := Root_Type (Rules);
      Root_C : constant String := C_Name (To_String (Rules (1).Name));
      Conf_T : constant String := HBNF_Grammar.Conf_Type;
   begin
      if Conf_T /= "" then
         --  Typed wrapper: the daemon owns `conf`; parse_config fills it via
         --  the action jets, so there is no parser-owned conf to free.  The
         --  declarations (and the grammar's preamble, which includes the
         --  daemon's header) come first, then conf.h; parse_config is the
         --  one external function the daemon links against, so the parser's
         --  own entry points are made static.
         --  With `statements`, parse_config reads the file through the
         --  statement driver and drops each statement once bound, so there
         --  is no parse_text.
         return
           "/* generated by hbnf -- do not edit */" & LF & LF &
           Emit (Rules, Walkers => False) &
           LF &
           "#include ""conf.h""" & LF & LF &
           Templates.Substitute
             (Emit_Parser (Rules),
              LF & "bool parse_tokens(", LF & "static bool parse_tokens(") &
           Templates.Substitute
             (Templates.Substitute
                (Emit_Lexer (Rules,
                             Text_Entry => not HBNF_Grammar.Statements),
                 LF & "lexed_t lex(const char *text) {",
                 LF & "static lexed_t lex(const char *text) {"),
              LF & "bool parse_text(const char *text,",
              LF & "static bool parse_text(const char *text,") &
           LF &
           Templates.Substitute
             (Templates.Substitute
                (Templates.Substitute
                   ((if HBNF_Grammar.Statements
                     then Templates.Conf_Tail_C_Typed_Stmt
                     else Templates.Conf_Tail_C_Typed),
                    "@CONF_TYPE@", Conf_T),
                 "@ROOT_TYPE@", Root_T),
              "@ROOT_C@", Root_C);
      end if;

      return
        "/* generated by hbnf -- do not edit */" & LF & LF &
        "#include ""conf.h""" & LF & LF &
        Emit_Parser (Rules) &
        Emit_Lexer (Rules) &
        LF &
        Templates.Substitute (Templates.Conf_Tail_C, "@ROOT_TYPE@", Root_T) &
        LF &
        "/* Drop the current config tree (the SIGHUP reload path). */" & LF &
        "void free_conf(void) {" & LF &
        "    if (!conf) return;" & LF &
        "    free_" & Root_C & "(conf);" & LF &
        "    free(conf);" & LF &
        "    conf = NULL;" & LF &
        "}";
   end Emit_Conf_Source;

   --  =====================================================================
   --  Emit_Serializer: a pre-order walk of the tree Emit declares that
   --  assigns ids in traversal order and emits one flat, typed record per
   --  object through an abstract `emit` callback.  Cross-references are ids,
   --  never pointers, so the output can cross a process boundary.
   function Emit_Serializer (Rules : Rule_Vectors.Vector) return String is
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      function Ref_Kind (Name : String) return Class_Kind is
         J : constant Natural := Find (Rules, Alias_Target (Rules, Name));
      begin
         if J = 0 then
            return Scalar;
         end if;
         return Infos (J).Kind;
      end Ref_Kind;

      --  The C type a leaf (scalar/enum) member serializes as.
      function Leaf_Type (Name : String) return String is
      begin
         case Ref_Kind (Name) is
            when Enum =>
               return C_Type_Name (Name);
            when others =>
               declare
                  R : constant String := Resolve_Type (Rules, Name);
               begin
                  if R /= "" then
                     return R;
                  end if;
                  return C_Type_Of (Rules, Name);
               end;
         end case;
      end Leaf_Type;

      --  The members of a node (struct members, or a list's element members).
      function Node_Members (Info : Rule_Info) return Member_Vectors.Vector is
         M : Member_Vectors.Vector;
      begin
         case Info.Kind is
            when Struct =>
               return Info.Members;
            when List =>
               if Info.Elem_Members.Is_Empty then
                  if Info.Elem_Name /= Null_Unbounded_String then
                     M.Append
                       (Member'(Name => Info.Elem_Name, Is_List => False));
                  end if;
               else
                  return Info.Elem_Members;
               end if;
            when others =>
               null;
         end case;
         return M;
      end Node_Members;

      --  A list of a bare literal carries a `value` string field, which is
      --  not a rule reference and so needs special handling.
      function Has_Bare_Value (Info : Rule_Info) return Boolean is
        (Info.Kind = List and then Info.Elem_Members.Is_Empty
         and then Info.Elem_Name = Null_Unbounded_String);

      --  A member is a child node (recursed) rather than a serialized leaf.
      function Is_Child (M : Member) return Boolean is
         J : constant Natural :=
           Find (Rules, Alias_Target (Rules, To_String (M.Name)));
      begin
         return M.Is_List
           or else (J > 0 and then (Infos (J).Kind = Struct
                                    or else Infos (J).Kind = List));
      end Is_Child;

      --  The serializer body for one node, writing through `n->` at the given
      --  indentation.  `CN` names the wire struct (`struct CN_msg`).
      procedure Emit_Body (CN : String; Info : Rule_Info;
                           Buf : in out U; Ind : String) is
         Ms   : constant Member_Vectors.Vector := Node_Members (Info);
         Bare : constant Boolean := Has_Bare_Value (Info);
      begin
         Append (Buf, Ind & "objid_t id = next_id++;");
         Append (Buf, LF);
         Append (Buf, Ind & "struct " & Pfx & CN & "_msg m; memset(&m, 0, sizeof m);");
         Append (Buf, LF);
         Append (Buf, Ind & "m.id = id; m.parent = parent;");
         Append (Buf, LF);
         if not Info.Tags.Is_Empty then
            Append (Buf, Ind & "m.kind = (uint32_t)n->kind;");
            Append (Buf, LF);
         end if;
         if Bare then
            Append (Buf, Ind & "m.value_len = n->value ?"
              & " (uint32_t)strlen(n->value) : (uint32_t)-1;");
            Append (Buf, LF);
         end if;
         for M of Ms loop
            if not Is_Child (M) then
               declare
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  if Leaf_Type (To_String (M.Name)) = "const char *" then
                     Append (Buf, Ind & "m." & F & "_len = n->" & F & " ?"
                       & " (uint32_t)strlen(n->" & F & ") : (uint32_t)-1;");
                  else
                     Append (Buf, Ind & "m." & F & " = n->" & F & ";");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, Ind & "emit(MSG_" & C_Ident (CN) & ", &m, sizeof m);");
         Append (Buf, LF);
         if Bare then
            Append (Buf, Ind & "if (n->value) emit(MSG_STR, n->value,"
              & " m.value_len);");
            Append (Buf, LF);
         end if;
         for M of Ms loop
            if not Is_Child (M)
              and then Leaf_Type (To_String (M.Name)) = "const char *"
            then
               declare
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  Append (Buf, Ind & "if (n->" & F & ") emit(MSG_STR, n->" & F
                    & ", m." & F & "_len);");
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         for M of Ms loop
            if Is_Child (M) then
               declare
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  --  Both by-value struct members and embedded list heads are
                  --  passed by address (&n->field).
                  Append (Buf, Ind & "serialize_"
                    & C_Name (Alias_Target (Rules, To_String (M.Name)))
                    & "(&n->" & F & ", id, emit);");
                  Append (Buf, LF);
               end;
            end if;
         end loop;
      end Emit_Body;

      procedure Serialize_Def (Idx : Natural; Buf : in out U) is
         NM   : constant String := To_String (Rules (Idx).Name);
         CN   : constant String := C_Name (NM);
         TN   : constant String := C_Type_Name (NM);
         Info : constant Rule_Info := Infos (Idx);
         Ms   : constant Member_Vectors.Vector := Node_Members (Info);
         Bare : constant Boolean := Has_Bare_Value (Info);
      begin
         --  The wire record: ids plus the fixed-width leaves; string leaves
         --  become a length prefix, with the bytes emitted separately.
         Append (Buf, "struct " & Pfx & CN & "_msg {");
         Append (Buf, LF);
         Append (Buf, "    objid_t id, parent;");
         Append (Buf, LF);
         if not Info.Tags.Is_Empty then
            Append (Buf, "    uint32_t kind;");
            Append (Buf, LF);
         end if;
         if Bare then
            Append (Buf, "    uint32_t value_len;");
            Append (Buf, LF);
         end if;
         for M of Ms loop
            if not Is_Child (M) then
               declare
                  T : constant String := Leaf_Type (To_String (M.Name));
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  if T = "const char *" then
                     Append (Buf, "    uint32_t " & F & "_len;");
                  else
                     Append (Buf, "    " & T & " " & F & ";");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         Append (Buf, "};");
         Append (Buf, LF);
         Append (Buf, LF);

         if Info.Kind = Struct then
            Append (Buf, "void serialize_" & CN & "(const " & TN
              & " *n, objid_t parent, emit_fn emit) {");
            Append (Buf, LF);
            Append (Buf, "    if (!n) return;");
            Append (Buf, LF);
            Emit_Body (CN, Info, Buf, "    ");
            Append (Buf, "}");
         else
            Append (Buf, "void serialize_" & CN & "(const struct " & Pfx & CN
              & "_list *head, objid_t parent, emit_fn emit) {");
            Append (Buf, LF);
            Append (Buf, "    const " & TN & " *n;");
            Append (Buf, LF);
            Append (Buf, "    uint32_t n_ = 0;");
            Append (Buf, LF);
            Append (Buf, "    " & L_Foreach ("n", "head") & " n_++;");
            Append (Buf, LF);
            Append (Buf, "    emit(MSG_COUNT, &n_, sizeof n_);");
            Append (Buf, LF);
            Append (Buf, "    " & L_Foreach ("n", "head") & " {");
            Append (Buf, LF);
            Emit_Body (CN, Info, Buf, "        ");
            Append (Buf, "    }");
            Append (Buf, LF);
            Append (Buf, "}");
         end if;
         Append (Buf, LF);
      end Serialize_Def;

      Res : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;

      Append (Res, "/* ---- id-ref serializer ---- */");
      Append (Res, LF);
      Append (Res, "typedef void (*emit_fn)(uint32_t type, const void *p,"
        & " size_t n);");
      Append (Res, LF);
      Append (Res, "static objid_t next_id = 1;");
      Append (Res, LF);
      Append (Res, LF);
      Append (Res, "enum {");
      Append (Res, LF);
      declare
         First : Boolean := True;
      begin
         for I in 1 .. N loop
            if Infos (I).Kind = Struct or else Infos (I).Kind = List then
               Append (Res, "    MSG_"
                 & C_Ident (C_Name (To_String (Rules (I).Name))));
               if First then
                  Append (Res, " = 1");
               end if;
               Append (Res, ",");
               Append (Res, LF);
               First := False;
            end if;
         end loop;
      end;
      Append (Res, "    MSG_STR,");
      Append (Res, LF);
      Append (Res, "    MSG_COUNT");
      Append (Res, LF);
      Append (Res, "};");
      Append (Res, LF);
      Append (Res, LF);

      --  Forward-declare the per-type serializers (they recurse into each
      --  other).
      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            declare
               CN : constant String := C_Name (To_String (Rules (I).Name));
               TN : constant String := C_Type_Name (To_String (Rules (I).Name));
               PT : constant String :=
                 (if Infos (I).Kind = List then "const struct " & Pfx & CN & "_list *"
                  else "const " & TN & " *");
            begin
               Append (Res, "void serialize_" & CN & "(" & PT
                 & ", objid_t parent, emit_fn emit);");
               Append (Res, LF);
            end;
         end if;
      end loop;
      Append (Res, LF);

      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            Serialize_Def (I, Res);
            Append (Res, LF);
         end if;
      end loop;

      declare
         RN          : constant String := C_Name (To_String (Rules (1).Name));
         Root_Is_List : constant Boolean := Infos (1).Kind = List;
         RT : constant String :=
           (if Root_Is_List then "struct " & Pfx & RN & "_list"
            else C_Type_Name (To_String (Rules (1).Name)));
      begin
         --  Named `serialize_tree` (not `serialize_config`) because the root
         --  rule is often literally `config`, whose own per-type serializer
         --  would otherwise collide.
         Append (Res, "void serialize_tree(const " & RT
           & " *conf, emit_fn emit) {");
         Append (Res, LF);
         Append (Res, "    next_id = 1;");
         Append (Res, LF);
         Append (Res, "    serialize_" & RN & "(conf, 0, emit);");
         Append (Res, LF);
         Append (Res, "}");
         Append (Res, LF);
      end;

      return To_String (Res);
   end Emit_Serializer;

   --  =====================================================================
   --  Emit_Rebuild: the decode side of --idref.  A reader walks the records
   --  in the order Emit_Serializer wrote them (pre-order), and a
   --  decode_<rule> per struct and list rebuilds the pointer tree from them,
   --  its strings bump-allocated in the arena so the root's free_ releases
   --  them.  Parent ids are carried but not needed: pre-order is enough.
   function Emit_Rebuild (Rules : Rule_Vectors.Vector) return String is
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      function Ref_Kind (Name : String) return Class_Kind is
         J : constant Natural := Find (Rules, Alias_Target (Rules, Name));
      begin
         if J = 0 then
            return Scalar;
         end if;
         return Infos (J).Kind;
      end Ref_Kind;

      function Leaf_Type (Name : String) return String is
      begin
         case Ref_Kind (Name) is
            when Enum =>
               return C_Type_Name (Name);
            when others =>
               declare
                  R : constant String := Resolve_Type (Rules, Name);
               begin
                  if R /= "" then
                     return R;
                  end if;
                  return C_Type_Of (Rules, Name);
               end;
         end case;
      end Leaf_Type;

      function Node_Members (Info : Rule_Info) return Member_Vectors.Vector is
         M : Member_Vectors.Vector;
      begin
         case Info.Kind is
            when Struct =>
               return Info.Members;
            when List =>
               if Info.Elem_Members.Is_Empty then
                  if Info.Elem_Name /= Null_Unbounded_String then
                     M.Append
                       (Member'(Name => Info.Elem_Name, Is_List => False));
                  end if;
               else
                  return Info.Elem_Members;
               end if;
            when others =>
               null;
         end case;
         return M;
      end Node_Members;

      function Has_Bare_Value (Info : Rule_Info) return Boolean is
        (Info.Kind = List and then Info.Elem_Members.Is_Empty
         and then Info.Elem_Name = Null_Unbounded_String);

      function Is_Child (M : Member) return Boolean is
         J : constant Natural :=
           Find (Rules, Alias_Target (Rules, To_String (M.Name)));
      begin
         return M.Is_List
           or else (J > 0 and then (Infos (J).Kind = Struct
                                    or else Infos (J).Kind = List));
      end Is_Child;

      --  Emit the body of decode_<CN>: read one node's msg, fill its leaves,
      --  read its string payloads, and recurse into its children in field
      --  order (the inverse of the serializer's Emit_Body).
      procedure Decode_Body (CN : String; Info : Rule_Info;
                             Buf : in out U; Ind : String) is
         Ms   : constant Member_Vectors.Vector := Node_Members (Info);
         Bare : constant Boolean := Has_Bare_Value (Info);
      begin
         Append (Buf, Ind & "uint32_t _t; const char *_d; uint32_t _l;");
         Append (Buf, LF);
         Append (Buf, Ind & "struct " & Pfx & CN & "_msg _m;");
         Append (Buf, LF);
         Append (Buf, Ind & "hbnf_next(rd, &_t, &_d, &_l);");
         Append (Buf, LF);
         Append (Buf, Ind & "memcpy(&_m, _d, sizeof _m);");
         Append (Buf, LF);
         Append (Buf, Ind & "n->id = _m.id; n->parent = _m.parent;");
         Append (Buf, LF);
         if not Info.Tags.Is_Empty then
            Append (Buf, Ind & "n->kind = (" & Pfx & CN & "_kind_t)_m.kind;");
            Append (Buf, LF);
         end if;
         if Bare then
            Append (Buf, Ind & "n->value = _m.value_len == (uint32_t)-1"
              & " ? NULL : hbnf_str(rd);");
            Append (Buf, LF);
         end if;
         for M of Ms loop
            if not Is_Child (M) then
               declare
                  F : constant String := C_Field (To_String (M.Name));
               begin
                  if Leaf_Type (To_String (M.Name)) = "const char *" then
                     Append (Buf, Ind & "n->" & F & " = _m." & F
                       & "_len == (uint32_t)-1 ? NULL : hbnf_str(rd);");
                  else
                     Append (Buf, Ind & "n->" & F & " = _m." & F & ";");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
         for M of Ms loop
            if Is_Child (M) then
               declare
                  F   : constant String := C_Field (To_String (M.Name));
                  CN2 : constant String :=
                    C_Name (Alias_Target (Rules, To_String (M.Name)));
                  J   : constant Natural := Find (Rules, To_String (M.Name));
               begin
                  if M.Is_List or else (J > 0 and then Infos (J).Kind = List) then
                     Append (Buf, Ind & "decode_" & CN2
                       & "_list(rd, &n->" & F & ");");
                  else
                     Append (Buf, Ind & "decode_" & CN2 & "(rd, &n->" & F & ");");
                  end if;
                  Append (Buf, LF);
               end;
            end if;
         end loop;
      end Decode_Body;

      procedure Decode_Def (Idx : Natural; Buf : in out U) is
         NM   : constant String := To_String (Rules (Idx).Name);
         CN   : constant String := C_Name (NM);
         TN   : constant String := C_Type_Name (NM);
         Info : constant Rule_Info := Infos (Idx);
      begin
         Append (Buf, "void decode_" & CN & "(struct hbnf_reader *rd, "
           & TN & " *n) {");
         Append (Buf, LF);
         Decode_Body (CN, Info, Buf, "    ");
         Append (Buf, "}");
         Append (Buf, LF);
         Append (Buf, LF);
         if Info.Kind = List then
            Append (Buf, "void decode_" & CN & "_list(struct hbnf_reader *rd,"
              & " struct " & Pfx & CN & "_list *head) {");
            Append (Buf, LF);
            Append (Buf, "    uint32_t _t; const char *_d; uint32_t _l, _n;");
            Append (Buf, LF);
            Append (Buf, "    hbnf_next(rd, &_t, &_d, &_l);");
            Append (Buf, LF);
            Append (Buf, "    memcpy(&_n, _d, sizeof _n);");
            Append (Buf, LF);
            Append (Buf, "    " & L_Init ("head"));
            Append (Buf, LF);
            Append (Buf, "    for (uint32_t _i = 0; _i < _n; _i++) {");
            Append (Buf, LF);
            Append (Buf, "        " & TN & " *nn = calloc(1, sizeof *nn);");
            Append (Buf, LF);
            Append (Buf, "        if (!nn) hbnf_oom();");
            Append (Buf, LF);
            Append (Buf, "        decode_" & CN & "(rd, nn);");
            Append (Buf, LF);
            Append (Buf, "        " & L_Append ("head", "nn"));
            Append (Buf, LF);
            Append (Buf, "    }");
            Append (Buf, LF);
            Append (Buf, "}");
            Append (Buf, LF);
            Append (Buf, LF);
         end if;
      end Decode_Def;

      Res : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;

      Append (Res, "/* ---- id-ref rebuild (decoder) ---- */");
      Append (Res, LF);
      Append (Res, "typedef struct { uint32_t type; const char *data;"
        & " uint32_t len; } hbnf_record;");
      Append (Res, LF);
      Append (Res, "struct hbnf_reader { const hbnf_record *r; size_t n, pos; };");
      Append (Res, LF);
      Append (Res, "static int hbnf_next(struct hbnf_reader *rd, uint32_t *type,");
      Append (Res, LF);
      Append (Res, "                    const char **data, uint32_t *len) {");
      Append (Res, LF);
      Append (Res, "    if (rd->pos >= rd->n) return 0;");
      Append (Res, LF);
      Append (Res, "    *type = rd->r[rd->pos].type; *data = rd->r[rd->pos].data;");
      Append (Res, LF);
      Append (Res, "    *len = rd->r[rd->pos].len; rd->pos++;");
      Append (Res, LF);
      Append (Res, "    return 1;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, "static char *hbnf_str(struct hbnf_reader *rd) {");
      Append (Res, LF);
      Append (Res, "    uint32_t type; const char *data; uint32_t len;");
      Append (Res, LF);
      Append (Res, "    if (!hbnf_next(rd, &type, &data, &len)) return NULL;");
      Append (Res, LF);
      --  Into the arena, like the parser's strings, so the root's free_
      --  releases them (free_ assumes the arena; strndup'd copies leaked).
      Append (Res, "    char *s = (char *)hbnf_alloc((size_t)len + 1);");
      Append (Res, LF);
      Append (Res, "    if (len) memcpy(s, data, len);");
      Append (Res, LF);
      Append (Res, "    return s;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, LF);

      --  Forward declarations of every decoder.
      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            declare
               CN : constant String := C_Name (To_String (Rules (I).Name));
               TN : constant String := C_Type_Name (To_String (Rules (I).Name));
            begin
               Append (Res, "void decode_" & CN & "(struct hbnf_reader *rd, "
                 & TN & " *n);");
               Append (Res, LF);
               if Infos (I).Kind = List then
                  Append (Res, "void decode_" & CN
                    & "_list(struct hbnf_reader *rd, struct " & Pfx & CN
                    & "_list *head);");
                  Append (Res, LF);
               end if;
            end;
         end if;
      end loop;
      Append (Res, LF);

      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            Decode_Def (I, Res);
            Append (Res, LF);
         end if;
      end loop;

      declare
         RN : constant String := C_Name (To_String (Rules (1).Name));
      begin
         Append (Res, "void config_decode(" & Root_Type (Rules) & " *conf,"
           & " const hbnf_record *r, size_t n) {");
         Append (Res, LF);
         Append (Res, "    struct hbnf_reader rd = { r, n, 0 };");
         Append (Res, LF);
         if Infos (1).Kind = List then
            Append (Res, "    decode_" & RN & "_list(&rd, conf);");
         else
            Append (Res, "    decode_" & RN & "(&rd, conf);");
         end if;
         Append (Res, LF);
         Append (Res, "}");
         Append (Res, LF);
      end;

      return To_String (Res);
   end Emit_Rebuild;

   --  =====================================================================
   --  Emit_Compare: a deep-equality walk of the typed tree, for byte-identity
   --  checking.  Two trees are equal when every scalar compares by value
   --  (strings by content, char[N] by memcmp), every enum and kind tag by
   --  value, every struct recurses, and every list matches element by element.
   --  Pointer addresses, TAILQ links and padding are never compared, so the
   --  same input parsed by two different parsers yields trees that compare
   --  equal regardless of allocation order.
   function Emit_Compare (Rules : Rule_Vectors.Vector) return String is
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      function Ref_Kind (Name : String) return Class_Kind is
         J : constant Natural := Find (Rules, Alias_Target (Rules, Name));
      begin
         if J = 0 then
            return Scalar;
         end if;
         return Infos (J).Kind;
      end Ref_Kind;

      --  Compare one member field of two nodes named A and B.
      procedure Cmp_Field (Name : String; A, B : String;
                           Buf : in out U; Ind : String) is
         F : constant String := C_Field (Name);
      begin
         case Ref_Kind (Name) is
            when Struct | List =>
               Append (Buf, Ind & "if (!compare_"
                 & C_Name (Alias_Target (Rules, Name))
                 & "(&" & A & "->" & F & ", &" & B & "->" & F
                 & ")) return false;");
               Append (Buf, LF);
            when Enum | Scalar =>
               --  A `char[N]` type jet is a fixed buffer (memcmp); a scalar
               --  that resolves to `const char *` is a string (strcmp, NULL
               --  handled); anything else (numbers, bools, enums) by value.
               if Is_Char_Array (C_Type_Of (Rules, Name)) then
                  Append (Buf, Ind & "if (memcmp(" & A & "->" & F & ", " & B
                    & "->" & F & ", sizeof " & A & "->" & F & ") != 0) return false;");
                  Append (Buf, LF);
               elsif Resolve_Type (Rules, Name) = "const char *" then
                  Append (Buf, Ind & "if ((" & A & "->" & F & " == NULL) != ("
                    & B & "->" & F & " == NULL)) return false;");
                  Append (Buf, LF);
                  Append (Buf, Ind & "if (" & A & "->" & F & " && strcmp(" & A
                    & "->" & F & ", " & B & "->" & F & ") != 0) return false;");
                  Append (Buf, LF);
               else
                  Append (Buf, Ind & "if (" & A & "->" & F & " != " & B & "->"
                    & F & ") return false;");
                  Append (Buf, LF);
               end if;
         end case;
      end Cmp_Field;

      --  The element fields of a list node: a single named element, or the
      --  members of a grouped element.
      procedure Cmp_Elem (Info : Rule_Info; A, B : String;
                          Buf : in out U; Ind : String) is
      begin
         if Info.Elem_Members.Is_Empty then
            if Info.Elem_Name /= Null_Unbounded_String then
               Cmp_Field (To_String (Info.Elem_Name), A, B, Buf, Ind);
            end if;
         else
            for M of Info.Elem_Members loop
               Cmp_Field (To_String (M.Name), A, B, Buf, Ind);
            end loop;
         end if;
      end Cmp_Elem;

      procedure Compare_Fields_Def (Idx : Natural; Buf : in out U) is
         CN   : constant String := C_Name (To_String (Rules (Idx).Name));
         TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
         Info : constant Rule_Info := Infos (Idx);
      begin
         Append (Buf, "static bool compare_" & CN & "_fields(const " & TN
           & " *a, const " & TN & " *b) {");
         Append (Buf, LF);
         if not Info.Tags.Is_Empty then
            Append (Buf, "    if (a->kind != b->kind) return false;");
            Append (Buf, LF);
         end if;
         if Info.Kind = Struct then
            for M of Info.Members loop
               Cmp_Field (To_String (M.Name), "a", "b", Buf, "    ");
            end loop;
         else
            Cmp_Elem (Info, "a", "b", Buf, "    ");
         end if;
         Append (Buf, "    return true;");
         Append (Buf, LF);
         Append (Buf, "}");
         Append (Buf, LF);
      end Compare_Fields_Def;

      procedure Compare_Def (Idx : Natural; Buf : in out U) is
         CN   : constant String := C_Name (To_String (Rules (Idx).Name));
         TN   : constant String := C_Type_Name (To_String (Rules (Idx).Name));
         Info : constant Rule_Info := Infos (Idx);
      begin
         if Info.Kind = Struct then
            Append (Buf, "static bool compare_" & CN & "(const " & TN
              & " *a, const " & TN & " *b) {");
            Append (Buf, LF);
            Append (Buf, "    if (!a || !b) return a == b;");
            Append (Buf, LF);
            Append (Buf, "    return compare_" & CN & "_fields(a, b);");
            Append (Buf, LF);
         else
            Append (Buf, "static bool compare_" & CN & "(const struct " & Pfx
              & CN & "_list *a, const struct " & Pfx & CN & "_list *b) {");
            Append (Buf, LF);
            Append (Buf, "    const " & TN & " *na = " & L_First ("a")
              & ", *nb = " & L_First ("b") & ";");
            Append (Buf, LF);
            Append (Buf, "    while (na && nb) {");
            Append (Buf, LF);
            Append (Buf, "        if (!compare_" & CN & "_fields(na, nb)) return false;");
            Append (Buf, LF);
            Append (Buf, "        na = " & L_Next ("na") & "; nb = " & L_Next ("nb") & ";");
            Append (Buf, LF);
            Append (Buf, "    }");
            Append (Buf, LF);
            Append (Buf, "    return na == NULL && nb == NULL;");
            Append (Buf, LF);
         end if;
         Append (Buf, "}");
         Append (Buf, LF);
      end Compare_Def;

      Res : U;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;

      Append (Res, "/* ---- deep compare (semantic equality for byte-identity) ---- */");
      Append (Res, LF);

      --  Forward-declare every compare function (they recurse into each
      --  other through by-value struct members and list elements).
      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            declare
               CN : constant String := C_Name (To_String (Rules (I).Name));
               TN : constant String := C_Type_Name (To_String (Rules (I).Name));
               PT : constant String :=
                 (if Infos (I).Kind = List then "const struct " & Pfx & CN & "_list *"
                  else "const " & TN & " *");
            begin
               Append (Res, "static bool compare_" & CN & "(" & PT
                 & "a, " & PT & "b);");
               Append (Res, LF);
            end;
         end if;
      end loop;
      Append (Res, LF);

      for I in 1 .. N loop
         if Infos (I).Kind = Struct or else Infos (I).Kind = List then
            Compare_Fields_Def (I, Res);
            Append (Res, LF);
            Compare_Def (I, Res);
            Append (Res, LF);
         end if;
      end loop;

      declare
         RN           : constant String := C_Name (To_String (Rules (1).Name));
         Root_Is_List : constant Boolean := Infos (1).Kind = List;
         RT : constant String :=
           (if Root_Is_List then "struct " & Pfx & RN & "_list"
            else C_Type_Name (To_String (Rules (1).Name)));
      begin
         Append (Res, "bool compare_tree(const " & RT & " *a, const " & RT
           & " *b) {");
         Append (Res, LF);
         Append (Res, "    return compare_" & RN & "(a, b);");
         Append (Res, LF);
         Append (Res, "}");
         Append (Res, LF);
      end;

      return To_String (Res);
   end Emit_Compare;

end HBNF_C;
