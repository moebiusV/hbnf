pragma Ada_2022;

with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with HBNF_Template;
with HBNF_Wire;
with HBNF_Compilable;
with HBNF_Shape;
with HBNF_Lookahead;

package body HBNF_C is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;
   use HBNF_Compilable;
   use HBNF_Shape;

   subtype U is Unbounded_String;

   LF : constant Character := ASCII.LF;

   --  One render of a loaded template from a flat (name, value) table.
   --  Mustache does the rendering (RFCPLAN.md step 3b); this is only the
   --  argument shape, because the C emitter's holes are overwhelmingly flat
   --  and a declare block per call site would bury the code it emits.
   type Hole is record
      Name  : U;
      Value : U;
   end record;

   type Holes is array (Positive range <>) of Hole;

   function H (Name, Value : String) return Hole is
     (Name => To_Unbounded_String (Name), Value => To_Unbounded_String (Value));

   --  A plain string replacement over emitted text -- not a template hole.
   --  the old Substitute did double duty as both; only this use is left.
   function Replace (Text, From, To : String) return String is
      Res : U;
      I   : Positive := Text'First;
   begin
      while I <= Text'Last loop
         if From'Length > 0
           and then I + From'Length - 1 <= Text'Last
           and then Text (I .. I + From'Length - 1) = From
         then
            Append (Res, To);
            I := I + From'Length;
         else
            Append (Res, Text (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Res);
   end Replace;

   function Fill (Tmpl : String; Table : Holes) return String is
      V : HBNF_Template.Context := HBNF_Template.View;
   begin
      for P of Table loop
         HBNF_Template.Put (V, To_String (P.Name), To_String (P.Value));
      end loop;
      return HBNF_Template.Render_File (Tmpl, V);
   end Fill;


   --  The C type for a built-in core rule, or "" if not a core scalar.
   Views_On : Boolean := False;

   procedure Set_Views (On : Boolean) is
   begin
      Views_On := On;
   end Set_Views;

   function Scalar_C_Type (Name : String) return String is
   begin
      if Name = "str" or else Name = "atom" or else Name = "word" then
         return (if Views_On then "hbnf_str" else "const char *");
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

   --  True when the rule named Nm is character-level: its pattern is a
   --  sequence/alternation of Char_Range terminals and references to other
   --  char-level rules, each matching code points.  Shared by the shape
   --  analyzer (Emit) and the parser/lexer emission (Emit_Parser).
   --  (The classification itself lives in HBNF_Compilable.Is_Char_Rule.)

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
   --  by a letter or underscore -- punctuation and digit-led literals are
   --  not atoms -- and, when the grammar has a `keywords` table, one in it.
   --  Any other literal is matched by its text and reserves nothing.
   function Is_Keyword_Lit (S : String) return Boolean is
     (HBNF_Grammar.Keywords_Apply
      and then S'Length > 0
      and then (S (S'First) in 'a' .. 'z'
                or else S (S'First) in 'A' .. 'Z'
                or else S (S'First) = '_')
      and then (HBNF_Grammar.Keyword_Table.Is_Empty
                or else HBNF_Grammar.Keyword_Table.Contains
                          (To_Unbounded_String (S))));

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
   --  own head/tail singly-linked list, written directly with no #define.  @key@ is the layout's
   --  `key` text, with @e@ the element it is asked of.
   In_Key : Boolean := False;   --  while @key@ is being written, so a key that names itself is left as written

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
                     elsif Key'Length > 5 and then Key (Key'First .. Key'First + 3) = "key("
                       and then Key (Key'Last) = ')' and then not In_Key
                       and then HBNF_Grammar.List_Override ("key") = ""
                     then
                        raise Parse_Error with
                          "a layout operation uses @key(...)@ and the grammar gives no key; say which field "
                          & "orders the list: layout_ops { key { HBNF_RB_STR((@e@)->FIELD) } }, for a string field";
                     elsif Key'Length > 5 and then Key (Key'First .. Key'First + 3) = "key("
                       and then Key (Key'Last) = ')' and then not In_Key
                     then
                        --  @key(X)@: the key of the expression X
                        In_Key := True;
                        Append (Buf, Subst (HBNF_Grammar.List_Override ("key"), Name, Elem, H,
                                            Key (Key'First + 4 .. Key'Last - 1), V));
                        In_Key := False;
                     elsif Key = "key" and then not In_Key
                       and then HBNF_Grammar.List_Override ("key") = ""
                     then
                        raise Parse_Error with
                          "a layout operation uses @key@ and the grammar gives no key; say which field "
                          & "orders the list: layout_ops { key { HBNF_RB_STR((@e@)->FIELD) } }, for a string field";
                     elsif Key = "key" and then not In_Key then
                        --  the layout's key, for the element E
                        In_Key := True;
                        Append (Buf, Subst (HBNF_Grammar.List_Override ("key"), Name, Elem, H, E, V));
                        In_Key := False;
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

   --  skip_ws for a white-space rule that is a scanner and nothing more.  A scanner is a function of the
   --  text and the position, and backtracking asks for the same positions again, so the last two answers
   --  are kept: where white space was skipped from (and to), and where there was none left.  The marks
   --  hold the position plus one, so that zero is "none", and are good for the length they were made at.
   function Scanner_Skip (Scanner : String) return String is
   begin
      return "static void skip_ws_run(parser_t *p) {" & LF
        & "    size_t from = p->pos, n;" & LF
        & "    if (p->ws_len1 != p->len + 1) { p->ws_len1 = p->len + 1; p->ws_at1 = 0; p->ws_from1 = 0; }" & LF
        & "    while ((n = " & Scanner & "(p->text, p->pos, p->len)) > 0) p->pos += n;" & LF
        & "    if (p->pos != from) { p->ws_from1 = from + 1; p->ws_to = p->pos; }" & LF
        & "    p->ws_at1 = p->pos + 1;" & LF
        & "}" & LF
        & "__attribute__((unused))" & LF
        & "static inline void skip_ws(parser_t *p) {" & LF
        & "    if (p->ws_len1 == p->len + 1) {" & LF
        & "        if (p->ws_at1 == p->pos + 1) return;" & LF
        & "        if (p->ws_from1 == p->pos + 1) { p->pos = p->ws_to; return; }" & LF
        & "    }" & LF
        & "    skip_ws_run(p);" & LF;
   end Scanner_Skip;

   --  True when any layout_ops operation is overridden: the grammar supplies its
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

   --  hbnf's own list stores only its head: the parser builds a list with a tail it keeps on the side,
   --  so a node holding a list pays one pointer for it, not two, and nothing points at the head, so the
   --  tree needs no walk after the parse to repoint tails.  The root rule's list, if it is one, keeps a
   --  tail: the `statements` driver appends to it after the parse.  A grammar's own container (layout_ops)
   --  is its own.
   Root_Name : Unbounded_String;
   function Note_Root (Rules : Rule_Vectors.Vector) return Boolean is
   begin
      Root_Name := (if Rules.Is_Empty then Null_Unbounded_String else Rules (1).Name);
      return True;
   end Note_Root;
   function Keeps_Tail (Rule : String) return Boolean is
     (Has_Listops or else Rule = "" or else Rule = To_String (Root_Name));

   --  The head tag and the element tag of the list a rule is (see L_Head's callers), for the operations
   --  that name them: with the `rb` layout RB_INSERT (name, head, elm) wants the tree's name.
   function List_Name_Of (Rule : String) return String;
   function List_Elem_Of (Rule : String) return String;

   function L_Head (Name, Elem : String; Rule : String := "") return String is
      O : constant String := HBNF_Grammar.List_Override ("head");
   begin
      if O /= "" then
         return Subst (O, Name, Elem, "", "", "");
      end if;
      return "struct " & Name & " { struct " & Elem & " *head" & (if Keeps_Tail (Rule) then ", **tail" else "") & "; }";
   end L_Head;

   function L_Entry (Elem : String) return String is
      O : constant String := HBNF_Grammar.List_Override ("entry");
   begin
      if O /= "" then
         return Subst (O, "", Elem, "", "", "");
      end if;
      return "struct " & Elem & " *_link";
   end L_Entry;

   function L_Init (H : String; Rule : String := "") return String is
      O : constant String := HBNF_Grammar.List_Override ("init");
   begin
      if O /= "" then
         return Subst (O, List_Name_Of (Rule), List_Elem_Of (Rule), H, "", "");
      end if;
      if not Keeps_Tail (Rule) then
         return "(" & H & ")->head = NULL;";
      end if;
      return "(" & H & ")->head = NULL; (" & H & ")->tail = &(" & H
        & ")->head;";
   end L_Init;

   function L_Append (H, E : String; Rule : String := "") return String is
      O : constant String := HBNF_Grammar.List_Override ("append");
   begin
      if O /= "" then
         return Subst (O, List_Name_Of (Rule), List_Elem_Of (Rule), H, E, "");
      end if;
      return "*(" & H & ")->tail = " & E & "; (" & H & ")->tail = &("
        & E & ")->_link;";
   end L_Append;

   function L_Foreach (V, H : String; Rule : String := "") return String is
      O : constant String := HBNF_Grammar.List_Override ("foreach");
   begin
      if O /= "" then
         return Subst (O, List_Name_Of (Rule), List_Elem_Of (Rule), H, "", V);
      end if;
      return "for (" & V & " = (" & H & ")->head; " & V & "; " & V & " = "
        & V & "->_link)";
   end L_Foreach;

   function L_First (H : String; Rule : String := "") return String is
      O : constant String := HBNF_Grammar.List_Override ("first");
   begin
      if O /= "" then
         return Subst (O, List_Name_Of (Rule), List_Elem_Of (Rule), H, "", "");
      end if;
      return "(" & H & ")->head";
   end L_First;

   function L_Next (E : String; Rule : String := "") return String is
      O : constant String := HBNF_Grammar.List_Override ("next");
   begin
      if O /= "" then
         return Subst (O, List_Name_Of (Rule), List_Elem_Of (Rule), "", E, "");
      end if;
      return "(" & E & ")->_link";
   end L_Next;

   --  After a head has been copied to its final place (the parser builds
   --  lists in locals and copies structs out), repoint what points back at
   --  the head: a TAILQ's first tqe_prev and an empty list's tail.
   function L_Relink (H : String; Rule : String := "") return String is
      O : constant String := HBNF_Grammar.List_Override ("relink");
   begin
      if O /= "" then
         return Subst (O, List_Name_Of (Rule), List_Elem_Of (Rule), H, "", "");
      end if;
      if not Keeps_Tail (Rule) then
         return "(void)0;";
      end if;
      return "if (!(" & H & ")->head) (" & H & ")->tail = &(" & H
        & ")->head;";
   end L_Relink;

   --  A relink walk is emitted for a layout_ops block that supplies its own relink.  hbnf's own list
   --  has none: it stores no pointer into its head.
   function Has_Relink return Boolean is
   begin
      return HBNF_Grammar.List_Override ("relink") /= "";
   end Has_Relink;

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

   --  The schema's type prefix (`prefix "pf_"`, or --prefix=), put in front
   --  of every generated type and struct tag; "" when absent.
   function Pfx return String is (HBNF_Grammar.Type_Prefix);

   --  The `_t` typedef name for a rule, with a "_" suffix when it would
   --  collide with a POSIX <sys/types.h> typedef (uid_t, gid_t, ...).
   --  The bit rules of a grammar that has some (Set_Hosted).
   Hosted_Types : Unbounded_String;
   Hosted_Code  : Unbounded_String;

   Hosted_Actions : Boolean := False;
   Writer_On      : Boolean := False;
   --  --ast: which alternative a node took is recorded (`_alt`), and the tables
   --  and walker of Emit_Ast are generated.  Off, the output is as it was.
   Ast_On         : Boolean := False;
   Ast_Tools_On   : Boolean := False;
   --  --paths: the parser keeps the stack of rules it is in, and an error says
   --  which they were (in statement > block > arg).
   Paths_On       : Boolean := False;
   --  --spans: every node records where it is in the text (_pos, _end);
   --  --parents: and which node holds it (_up, _upk, set by node_link).
   Spans_On       : Boolean := False;
   Parents_On     : Boolean := False;

   Forks_On       : Boolean := False;
   Compact_On     : Boolean := True;

   Ladder_On : Boolean := True;

   procedure Set_Ladder (On : Boolean) is
   begin
      Ladder_On := On;
   end Set_Ladder;

   procedure Set_Compact (On : Boolean) is
   begin
      Compact_On := On;
   end Set_Compact;

   function Needs_Copies return Boolean is (Ast_On or else Ast_Tools_On or else Writer_On);

   --  Off for the tools that read a choice's fields as a struct (see Is_Choice).
   Choice_Off : Boolean := False;

   procedure Set_Choice (On : Boolean) is
   begin
      Choice_Off := not On;
   end Set_Choice;
   Quiet_Forks    : Boolean := False;

   procedure Set_Forks (On : Boolean; Quiet : Boolean := False) is
   begin
      Forks_On := On;
      Quiet_Forks := Quiet;
   end Set_Forks;

   procedure Set_Spans (On : Boolean) is
   begin
      Spans_On := On;
   end Set_Spans;

   procedure Set_Parents (On : Boolean) is
   begin
      Parents_On := On;
      if On then
         Ast_On := True;
      end if;
   end Set_Parents;

   procedure Set_Paths (On : Boolean) is
   begin
      Paths_On := On;
   end Set_Paths;

   procedure Set_Writer (On : Boolean) is
   begin
      Writer_On := On;
      if On then
         Ast_On := True;
      end if;
   end Set_Writer;

   procedure Set_Ast (On : Boolean) is
   begin
      Ast_On := On;
   end Set_Ast;

   procedure Set_Ast_Tools (On : Boolean) is
   begin
      Ast_Tools_On := On;
      if On then
         Ast_On := True;
      end if;
   end Set_Ast_Tools;

   procedure Set_Hosted (Types, Code : String; Actions : Boolean := False) is
   begin
      Hosted_Actions := Actions;
      Hosted_Types := To_Unbounded_String (Types);
      Hosted_Code := To_Unbounded_String (Code);
   end Set_Hosted;

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

   --  The struct tag for a rule: the rule name with a "_s" suffix, so the
   --  tag can never collide with a `_t` typedef.  C keeps tags and typedefs
   --  in separate namespaces, but C++ puts them in one, so the tag is
   --  `typedef struct foo_s foo_t;`.
   function C_Tag (S : String) return String is (C_Name (S) & "_s");

   function List_Name_Of (Rule : String) return String is
     (if Rule = "" then "" else Pfx & C_Name (Rule) & "_list");
   function List_Elem_Of (Rule : String) return String is
     (if Rule = "" then "" else Pfx & C_Tag (Rule));

   --  The C type of the root (first) rule: a list root is its list head
   --  (`struct <CN>_list`), a struct root its `_t` typedef.
   function Root_Type (Rules : Rule_Vectors.Vector) return String is
      NM : constant String := To_String (Rules (1).Name);
   begin
      if Is_Char_Rule (Rules, NM) then
         return C_Type_Name (NM);
      end if;
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

   --  A rule by name, through a tree of the names that is made again when the
   --  number of rules changes (see Index_Of in hbnf_grammar.adb).
   package Name_Idx_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Natural);
   Name_Idx     : Name_Idx_Maps.Map;
   Name_Idx_Len : Natural := 0;

   function Find (Rules : Rule_Vectors.Vector; Name : String) return Natural is
      N : constant Natural := Natural (Rules.Length);
   begin
      if N /= Name_Idx_Len then
         Name_Idx.Clear;
         for I in 1 .. N loop
            declare
               Nm : constant String := To_String (Rules (I).Name);
            begin
               if not Name_Idx.Contains (Nm) then
                  Name_Idx.Insert (Nm, I);
               end if;
            end;
         end loop;
         Name_Idx_Len := N;
      end if;
      declare
         C : constant Name_Idx_Maps.Cursor := Name_Idx.Find (Name);
      begin
         if Name_Idx_Maps.Has_Element (C) then
            declare
               J : constant Natural := Name_Idx_Maps.Element (C);
            begin
               if J <= N and then To_String (Rules (J).Name) = Name then
                  return J;
               end if;
            end;
         end if;
      end;
      for I in 1 .. N loop
         if To_String (Rules (I).Name) = Name then
            Name_Idx_Len := 0;
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Whitespace_Rule_Name (Rules : Rule_Vectors.Vector)
     return Unbounded_String
   is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if Rules (I).Whitespace /= Null_Unbounded_String then
            return Rules (I).Whitespace;
         end if;
      end loop;
      return Null_Unbounded_String;
   end Whitespace_Rule_Name;

   --  True when a rule is parsed by name: a core type (word/int/str/…, char
   --  rule or jet) is read as a scalar in place, a building block is inlined
   --  into a token's scanner, and the whitespace rule is only scanned by
   --  skip_ws — none of them gets a parse_rule_<name>.
   function Needs_Parse_Fn (Rules : Rule_Vectors.Vector; NM : String)
      return Boolean
   is
   begin
      if Is_Core_Name (NM) then
         return False;
      end if;
      if Is_Char_Rule (Rules, NM) and then not Is_Char_Token (Rules, NM) then
         return False;
      end if;
      if NM = To_String (Whitespace_Rule_Name (Rules)) then
         return False;
      end if;
      return True;
   end Needs_Parse_Fn;

   --  The scanner a rule runs: its jet, or a char-rule scanner.  The whitespace
   --  rule is one or the other, never a core scalar, so Scalar_Scan_Fn (which
   --  maps any non-core name onto `word`) would be wrong for it.
   --  Contexts (RFCPLAN.md decision 13): true when the grammar declares one.
   function Ctx_On return Boolean is (HBNF_Grammar.Context_Count > 0);
   Ctx_Seq : Natural := 0;       --  numbers the names the emitters make up

   --  The C spelling of a context's name, for CTX_<name>: hyphens are
   --  underscores.
   function C_Ident_Lower (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C = '-' then
            C := '_';
         end if;
      end loop;
      return R;
   end C_Ident_Lower;

   function Ctx_Img (X : Natural) return String is
      S : constant String := Natural'Image (X);
   begin
      return S (S'First + 1 .. S'Last);
   end Ctx_Img;

   --  What a grammar with contexts needs ahead of its rules: the context
   --  numbers, the set itself (templates/c_context.tmpl), and a function for
   --  each `%where { }` and `%bind { }` it holds, numbered as they are met.
   function Context_Runtime (Rules : Rule_Vectors.Vector) return String is
      R  : U;
      Id : Natural := 0;

      procedure Walk (Owner : Natural; V : Element_Vectors.Vector) is
      begin
         for E of V loop
            if E.Kind = Block and then E.Op in B_Where | B_Bind_Code then
               Id := Id + 1;
               E.Id := Id;
               declare
                  T : constant String :=
                    C_Type_Name (To_String (Rules (Owner).Name));
                  N : constant String := Ctx_Img (Id);
               begin
                  if E.Op = B_Where then
                     Append (R, "static bool where_" & N & " (parser_t *p, "
                       & "const char *text, size_t len, " & T & " *n) {"
                       & ASCII.LF
                       & "    (void)p; (void)text; (void)len; (void)n;"
                       & ASCII.LF);
                  else
                     Append (R, "static void bindc_" & N & " (parser_t *p, "
                       & "const char *text, size_t len, " & T & " *n) {"
                       & ASCII.LF
                       & "    (void)p; (void)text; (void)len; (void)n;"
                       & ASCII.LF);
                  end if;
                  Append (R, To_String (E.Code) & ASCII.LF & "}" & ASCII.LF);
               end;
            elsif E.Kind = Group then
               Walk (Owner, E.Items);
            end if;
         end loop;
      end Walk;

      Head : U;
   begin
      Append (Head, "enum {");
      for K in 1 .. HBNF_Grammar.Context_Count loop
         Append (Head, " CTX_" & C_Ident_Lower (HBNF_Grammar.Context_Name (K))
           & ",");
      end loop;
      Append (Head, " HBNF_NCTX };" & ASCII.LF);
      for I in 1 .. Natural (Rules.Length) loop
         Walk (I, Rules (I).Pattern);
      end loop;
      return To_String (Head) & HBNF_Template.Get ("c_context") & ASCII.LF
        & To_String (R);
   end Context_Runtime;

   function Guard_Slot (K : Natural) return String is ("HF(" & Ctx_Img (K) & ")");

   --  A number expression of a rule with a frame (`k + 1`) as C: the names are
   --  the frame's slots of that rule.
   function Frame_Expr (Owner, Text : String) return String is
      R : U;
      I : Natural := Text'First;
   begin
      while I <= Text'Last loop
         if Text (I) in 'a' .. 'z' | 'A' .. 'Z' | '_' then
            declare
               J : Natural := I;
            begin
               while J <= Text'Last
                 and then Text (J) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_'
               loop
                  J := J + 1;
               end loop;
               Append (R, "HF(" & Ctx_Img (Natural'Max (0, HBNF_Grammar.Slot_Of (Owner, Text (I .. J - 1))))
                       & ")");
               I := J;
            end;
         else
            Append (R, Text (I));
            I := I + 1;
         end if;
      end loop;
      return "(" & To_String (R) & ")";
   end Frame_Expr;

   --  The C expression that parses a reference to a rule, Call being the call
   --  of the rule's function.  A rule with parameters that are numbers runs in
   --  a frame the reference makes from its arguments, worked out in the frame
   --  it stands in.
   function Rule_Call
     (Owner : String; E : Element_Access; Call : String) return String
   is
      Callee : constant HBNF_Grammar.Frame_Info :=
        HBNF_Grammar.Frame_Of (To_String (E.Name));
      Args   : U;
      Set    : U;
      N      : Natural := 0;
      Text   : constant String := To_String (E.Args);
      Start  : Natural := Text'First;
      Depth  : Natural := 0;

      procedure One (A : String) is
      begin
         Append (Args, "long a" & Ctx_Img (N) & "_ = "
                 & Frame_Expr (Owner, A) & "; ");
         Append (Set, " HF(" & Ctx_Img (N) & ") = a" & Ctx_Img (N) & "_;");
         N := N + 1;
      end One;
   begin
      if Length (Callee.Slots) = 0 or else Callee.Shares then
         return Call;
      end if;
      --  The callee is given the caller's own numbers, in the same places, and keeps nothing of
      --  its own in a frame (a rule only reads its parameters): it runs in the caller's frame,
      --  and no new one is made for it.
      declare
         Caller : constant HBNF_Grammar.Frame_Info := HBNF_Grammar.Frame_Of (Owner);

         function Names (S : String) return String_Vectors.Vector is
            V     : String_Vectors.Vector;
            First : Natural := S'First;
         begin
            if S'Length = 0 then
               return V;
            end if;
            for K in S'Range loop
               if S (K) = ' ' then
                  V.Append (To_Unbounded_String (S (First .. K - 1)));
                  First := K + 1;
               end if;
            end loop;
            V.Append (To_Unbounded_String (S (First .. S'Last)));
            return V;
         end Names;

         function Trim_Both (S : String) return String is
            F : Natural := S'First;
            L : Natural := S'Last;
         begin
            while F <= L and then S (F) = ' ' loop
               F := F + 1;
            end loop;
            while L >= F and then S (L) = ' ' loop
               L := L - 1;
            end loop;
            return S (F .. L);
         end Trim_Both;

         Mine   : constant String_Vectors.Vector := Names (To_String (Caller.Slots));
         Theirs : constant String_Vectors.Vector := Names (To_String (Callee.Slots));
         Given  : String_Vectors.Vector;
      begin
         if Callee.Arity > 0 and then Natural (Theirs.Length) = Callee.Arity
           and then Natural (Mine.Length) >= Callee.Arity
         then
            declare
               D : Natural := 0;
               F : Natural := Text'First;
            begin
               for K in Text'Range loop
                  if Text (K) = '(' then
                     D := D + 1;
                  elsif Text (K) = ')' then
                     D := D - 1;
                  elsif Text (K) = ',' and then D = 0 then
                     Given.Append (To_Unbounded_String (Trim_Both (Text (F .. K - 1))));
                     F := K + 1;
                  end if;
               end loop;
               if Text'Length > 0 then
                  Given.Append (To_Unbounded_String (Trim_Both (Text (F .. Text'Last))));
               end if;
            end;
            if Natural (Given.Length) = Callee.Arity
              and then (for all K in 1 .. Callee.Arity => Given (K) = Mine (K))
            then
               return Call;
            end if;
         end if;
      end;
      for I in Text'Range loop
         if Text (I) = '(' then
            Depth := Depth + 1;
         elsif Text (I) = ')' then
            Depth := Depth - 1;
         elsif Text (I) = ',' and then Depth = 0 then
            One (Text (Start .. I - 1));
            Start := I + 1;
         end if;
      end loop;
      if Text'Length > 0 then
         One (Text (Start .. Text'Last));
      end if;
      declare
         Slots : Natural := 1;
      begin
         for C of To_String (Callee.Slots) loop
            if C = ' ' then
               Slots := Slots + 1;
            end if;
         end loop;
         return "({ " & To_String (Args) & "size_t ob_ = hbnf_fpush ("
           & Ctx_Img (Slots) & ");" & To_String (Set) & " bool r_ = " & Call
           & "; hbnf_fpop (ob_); r_; })";
      end;
   end Rule_Call;

   --  The C statement that records where a node starts: after the blanks
   --  before it, which the first element of the node would skip.
   function Span_Start (Ws : Boolean; Acc, Save : String) return String is
     (if Ws
      then "{ size_t k_ = p->pos; p->pos = " & Save & "; skip_ws(p); " & Acc
           & "_pos = p->pos; p->pos = k_; }"
      else Acc & "_pos = " & Save & ";");

   function Rule_Scanner (Rules : Rule_Vectors.Vector; Name : String)
      return String
   is
      J : constant Natural := Find (Rules, Name);
   begin
      if J /= 0 and then Rules (J).Jet_Code /= Null_Unbounded_String then
         return "jet_" & C_Name (Name);
      end if;
      return "scan_" & C_Name (Name);
   end Rule_Scanner;

   function C_Type_Of (Rules : Rule_Vectors.Vector; Ref : String) return String is
      S : constant String := Scalar_C_Type (Ref);
      J : constant Natural := Find (Rules, Ref);
   begin
      if S /= "" then
         return S;
      end if;
      if J = 0 and then HBNF_Grammar.Is_Wire_Rule (Ref) then
         return C_Type_Name (Ref);          --  a bit rule: a struct of its own
      end if;
      if J = 0 then
         raise Parse_Error with "undefined rule: " & HBNF_Grammar.Spelled (Ref)
           & (if HBNF_Grammar.Spelled (Ref) /= Ref then ", which no `::=` defines" else "");
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
            if Is_Char_Rule (Rules, N) then
               return "const char *";
            end if;
            if Natural (P.Length) = 1
              and then P (1).Kind = Literal
              and then P (1).Min = 1
              and then P (1).Max = 1
            then
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

   --  The distinct leading keywords of a keyword-headed alternation: the
   --  first literal of each '|' branch, deduped in order; empty if there is
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

   --  The C name of a kind tag.  Enum_Names spells punctuation as OP1,
   --  OP2 ..., as an enum does, where C_Ident would give `_` for both "+"
   --  and "-".
   function Tag_Name (Tags : String_Vectors.Vector; Lit : U) return String is
      Names : constant String_Vectors.Vector := Enum_Names (Tags);
   begin
      for I in 1 .. Natural (Tags.Length) loop
         if Tags (I) = Lit then
            return To_String (Names (I));
         end if;
      end loop;
      return C_Ident (To_String (Lit));
   end Tag_Name;

   --  The kind tags of a list's entries.  A list rewritten from left
   --  recursion tags the tails, `sum = sum "+" n | sum "-" n | n`; its
   --  first entry, the base, gets <CN>_BASE (Kind_Enum), which is 0.
   function List_Tags (R : Rule) return String_Vectors.Vector is
     (if R.Left_Bases > 0 then Leading_Tags (Tail_Branches (R))
      else Leading_Tags (R.Pattern (1).Items));

   --  A rule with an `%emit` in its own pattern, or a `name :: type =` head, is run for its
   --  emits and yields the declared value (RFCPLAN.md step 15).  The type is the author's; a rule
   --  with emits and no type yields nothing, which is a char nobody reads.
   function Holds_Emit (V : Element_Vectors.Vector) return Boolean is
   begin
      for E of V loop
         if (E.Kind = Block and then E.Op = B_Emit)
           or else (E.Kind = Group and then Holds_Emit (E.Items))
         then
            return True;
         end if;
      end loop;
      return False;
   end Holds_Emit;

   --  The C lvalues of `rollback { a, b }`, split at the commas that are not inside brackets.
   function Rollback_Items return String_Vectors.Vector is
      T     : constant String := HBNF_Grammar.Rollback_State;
      Res   : String_Vectors.Vector;
      Depth : Natural := 0;
      From  : Natural := T'First;

      procedure Add (A, B : Natural) is
         X : Natural := A;
         Y : Natural := B;
      begin
         while X <= Y and then T (X) in ' ' | ASCII.LF | ASCII.HT loop X := X + 1; end loop;
         while Y >= X and then T (Y) in ' ' | ASCII.LF | ASCII.HT loop Y := Y - 1; end loop;
         if X <= Y then
            Res.Append (To_Unbounded_String (T (X .. Y)));
         end if;
      end Add;
   begin
      for K in T'Range loop
         case T (K) is
            when '(' | '[' | '{' => Depth := Depth + 1;
            when ')' | ']' | '}' => Depth := Depth - 1;
            when ',' =>
               if Depth = 0 then
                  Add (From, K - 1);
                  From := K + 1;
               end if;
            when others => null;
         end case;
      end loop;
      Add (From, T'Last);
      return Res;
   end Rollback_Items;

   function Emit_Value_Type (R : Rule) return String is
      T : constant String := HBNF_Grammar.Value_Type (To_String (R.Name));
   begin
      if T /= "" then
         return T;
      elsif Holds_Emit (R.Pattern) then
         return "char";
      end if;
      return "";
   end Emit_Value_Type;

   function Analyze (Rules : Rule_Vectors.Vector; Idx : Natural)
      return Rule_Info is
      R : constant Rule := Rules (Idx);
      P : constant Element_Vectors.Vector := R.Pattern;
   begin
      if Emit_Value_Type (R) /= "" then
         return (Kind        => Scalar,
                 Inline_Type => To_Unbounded_String (Emit_Value_Type (R)),
                 others      => <>);
      end if;
      if R.Jet_Code /= Null_Unbounded_String then
         return (Kind        => Scalar,
                 Inline_Type => To_Unbounded_String ("const char *"),
                 others      => <>);
      end if;
      if Is_Char_Rule (Rules, To_String (R.Name)) then
         --  A char-level rule is a token definition, like a jet.
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
                             Tags         => List_Tags (R));
                  end;
               else
                  return (Kind        => List,
                          Elem_Name    => Null_Unbounded_String,
                          Elem_Members => Member_Vectors.Empty_Vector,
                          others       => <>);
               end if;
            end if;

            if E.Kind = Name then
               declare
                  T : constant Natural := Find (Rules, To_String (E.Name));
                  Names_List : constant Boolean :=
                    T /= 0
                    and then Rules (T).Jet_Code = Null_Unbounded_String
                    and then not Is_Char_Rule (Rules, To_String (E.Name))
                    and then Natural (Rules (T).Pattern.Length) = 1
                    and then (Rules (T).Pattern (1).Min /= 1
                              or else Rules (T).Pattern (1).Max /= 1);
               begin
                  --  An alias of a list rule stands for the list itself: its
                  --  head struct, as a field naming the list would hold, not
                  --  the list's node type.
                  return (Kind        => Scalar,
                          Inline_Type =>
                            To_Unbounded_String
                              (if Names_List
                               then "struct " & Pfx & C_Name (To_String (E.Name))
                                    & "_list"
                               else C_Type_Of (Rules, To_String (E.Name))),
                          others      => <>);
               end;
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

   function Value_Type
     (Rules : Rule_Vectors.Vector; Name : String) return String
   is
      J : constant Natural := Find (Rules, Name);
   begin
      if J = 0 then
         return "";
      elsif Analyze (Rules, J).Kind = List then
         return "struct " & Pfx & C_Name (Name) & "_list";
      end if;
      return C_Type_Name (Name);
   end Value_Type;

   function Value_Free
     (Rules : Rule_Vectors.Vector; Name : String) return String
   is
      J : constant Natural := Find (Rules, Name);
   begin
      if J = 0 then
         return "";
      end if;
      case Analyze (Rules, J).Kind is
         when Struct => return "free_" & C_Name (Name) & "_fields(@);";
         when List   => return "free_" & C_Name (Name) & "(@);";
         when others => return "";
      end case;
   end Value_Free;

   --  The numbers of those alternatives, from Start: what `_alt` holds (the
   --  names are in the tables, node_alt_name).
   function Alt_Idents
     (CN : String; Els : Element_Vectors.Vector; Start : Positive := 1)
      return String_Vectors.Vector
   is
      pragma Unreferenced (CN);
      Res : String_Vectors.Vector;
      N   : constant Natural := Natural (Alt_Labels (Els).Length);
   begin
      for K in 1 .. N loop
         declare
            S : constant String := Natural'Image (Start + K - 1);
         begin
            Res.Append (To_Unbounded_String (S (S'First + 1 .. S'Last)));
         end;
      end loop;
      return Res;
   end Alt_Idents;

   --  The alternatives a rule's node records (--ast), in the order of the
   --  constants of <rule>_alt_t; empty for a rule with none.
   function Rule_Alts (R : Rule; Is_List : Boolean) return String_Vectors.Vector
   is
      CN : constant String := C_Name (To_String (R.Name));
      P  : constant Element_Vectors.Vector := R.Pattern;
      Res : String_Vectors.Vector;
   begin
      if Is_List and then R.Left_Bases > 0 then
         Res := Alt_Idents (CN, Base_Branches (R));
         for X of Alt_Idents (CN, Tail_Branches (R),
                              Natural (Res.Length) + 1)
         loop
            Res.Append (X);
         end loop;
      elsif Is_List and then Natural (P.Length) = 1
        and then P (1).Kind = Group
        and then (for some X of P (1).Items => X.Kind = Alt)
      then
         Res := Alt_Idents (CN, P (1).Items);
      elsif not Is_List and then Natural (P.Length) > 1
        and then (for some X of P => X.Kind = Alt)
      then
         Res := Alt_Idents (CN, P);
      end if;
      return Res;
   end Rule_Alts;

   --  A rule that is only a choice among other rules, `value = object / array / string`, holds
   --  exactly one of them: its node is the number of the alternative taken (`_alt`, from 1) and
   --  a union of the alternatives, not a field for each with all but one empty.  Left out where
   --  something else reads the fields as a struct (the id-ref, writer, AST, spans, parents and
   --  compare tools, the fork detector).
   function Is_Choice (R : Rule) return Boolean is
      P : constant Element_Vectors.Vector := R.Pattern;
      N : constant Natural := Natural (P.Length);
   begin
      if Choice_Off or else Ast_On or else Spans_On or else Parents_On or else Forks_On
        or else R.Action_Code /= Null_Unbounded_String
        or else R.Left_Bases > 0
        or else N < 3 or else N mod 2 = 0
      then
         return False;
      end if;
      for I in 1 .. N loop
         if I mod 2 = 1 then
            if P (I).Kind /= Name or else P (I).Min /= 1 or else P (I).Max /= 1 then
               return False;
            end if;
            for J in 1 .. I - 2 loop
               if J mod 2 = 1 and then P (J).Name = P (I).Name then
                  return False;      --  the same rule twice would be one field
               end if;
            end loop;
         elsif P (I).Kind /= Alt then
            return False;
         end if;
      end loop;
      return True;
   end Is_Choice;


   --  The fields the C backend must emit indirectly, one per cycle in the
   --  by-value graph, chosen by the one detector in HBNF_Compilable.  Emit
   --  (the types, free and walkers) and Emit_Parser (the commit point) are
   --  separate functions with separate local state, so both ask here for the
   --  same answer rather than each rebuilding the graph.
   function Back_Edges_C (Rules : Rule_Vectors.Vector)
     return Edge_Vectors.Vector
   is
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      --  The struct a field really holds: a scalar alias is followed to its
      --  target, and only a struct is embedded by value, so anything else
      --  yields 0.  Bounded like Alias_Target: an all-alias cycle is refused
      --  by Emit's leaf sort before Emit gets here, but Emit_Parser can meet
      --  one directly, and this must not spin.
      function Resolve (N : U) return Natural is
         J : Natural := Find (Rules, To_String (N));
      begin
         for Hop in 1 .. 8 loop
            exit when J = 0 or else Infos (J).Kind /= Scalar;
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
         if J > 0 and then Infos (J).Kind = Struct then
            return J;
         end if;
         return 0;
      end Resolve;

      E : Edge_Vectors.Vector;
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (Rules, I));
      end loop;

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
                                (By_Value_Edge'
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
                             (By_Value_Edge'
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

      declare
         R : Edge_Vectors.Vector := Back_Edges (N, E);
      begin
         --  Compact nodes: a struct-valued field that only some of a choice's
         --  alternatives hold (the rule is `a | b | c`, a few of them naming
         --  this field) is held by pointer, so a node costs the alternative
         --  taken.  A field every alternative has, or a rule that is one
         --  sequence, is always there, and stays by value.
         if Compact_On then
            for I in 1 .. N loop
               if Infos (I).Kind = Struct then
                  declare
                     Info : constant Rule_Info := Infos (I);
                  begin
                     for M of Info.Members loop
                        if not M.Is_List and then Resolve (M.Name) > 0
                          and then HBNF_Compilable.Partly_Held
                                     (Rules (I).Pattern, To_String (M.Name))
                        then
                           declare
                              Have : Boolean := False;
                           begin
                              for X of R loop
                                 if X.Owner = I and then X.Member = M.Name then
                                    Have := True;
                                 end if;
                              end loop;
                              if not Have then
                                 R.Append
                                   (By_Value_Edge'
                                      (Owner => I, Member => M.Name,
                                       Target => Resolve (M.Name)));
                              end if;
                           end;
                        end if;
                     end loop;
                  end;
               end if;
            end loop;
         end if;
         return R;
      end;
   end Back_Edges_C;

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

      Noted : constant Boolean := Note_Root (Rules);
      N : constant Natural := Natural (Rules.Length);

      function Find (Name : String) return Natural is (Find (Rules, Name));

      function C_Type_Of (Ref : String) return String is
         S : constant String := Scalar_C_Type (Ref);
         J : constant Natural := Find (Ref);
      begin
         if S /= "" then
            return S;
         end if;
         if J = 0 and then HBNF_Grammar.Is_Wire_Rule (Ref) then
            return C_Type_Name (Ref);       --  a bit rule: a struct of its own
         end if;
         if J = 0 then
            raise Parse_Error with "undefined rule: " & HBNF_Grammar.Spelled (Ref)
           & (if HBNF_Grammar.Spelled (Ref) /= Ref then ", which no `::=` defines" else "");
         end if;
         return C_Type_Name (Ref);
      end C_Type_Of;

      --  The underlying scalar C type a rule name resolves to, chasing
      --  single-name aliases and jets to their target (so `str | word` and
      --  `ipv4 | ipv6` both collapse to `const char *`).  "" if not scalar.
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
               if Is_Char_Rule (Rules, N) then
                  return "const char *";
               end if;
               if Natural (P.Length) = 1
                 and then P (1).Kind = Literal
                 and then P (1).Min = 1
                 and then P (1).Max = 1
               then
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
         if Emit_Value_Type (R) /= "" then
            return (Kind        => Scalar,
                    Inline_Type => To_Unbounded_String (Emit_Value_Type (R)),
                    others      => <>);
         end if;

         if R.Jet_Code /= Null_Unbounded_String then
            --  A jet reads its own token kind and yields the matched text.
            return (Kind        => Scalar,
                    Inline_Type => To_Unbounded_String ("const char *"),
                    others      => <>);
         end if;
         if Is_Char_Rule (Rules, To_String (R.Name)) then
            --  A char-level rule is a token definition, like a jet.
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
                                Tags         => List_Tags (R));
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
                  declare
                     T : constant Natural := Find (To_String (E.Name));
                     Names_List : constant Boolean :=
                       T /= 0
                       and then Rules (T).Jet_Code = Null_Unbounded_String
                       and then not Is_Char_Rule (Rules, To_String (E.Name))
                       and then Natural (Rules (T).Pattern.Length) = 1
                       and then (Rules (T).Pattern (1).Min /= 1
                                 or else Rules (T).Pattern (1).Max /= 1);
                  begin
                     --  An alias of a list rule stands for the list itself.
                     return (Kind => Scalar,
                             Inline_Type =>
                               To_Unbounded_String
                                 (if Names_List
                                  then "struct " & Pfx & C_Name (To_String (E.Name))
                                       & "_list"
                                  else C_Type_Of (To_String (E.Name))),
                             others      => <>);
                  end;
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

      --  The rule a reference holds by value: chase a scalar alias
      --  (`src = host`) through to the struct its field really holds, so the
      --  containing struct is laid out after that struct and so the cycle
      --  detector sees the edge the field really makes.  A direct struct
      --  member is already there.  0 when it holds nothing by value.
      function Resolve (N : U) return Natural is
         J : Natural := Find (To_String (N));
      begin
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
            return J;
         end if;
         return 0;
      end Resolve;

      --  The fields to emit indirectly, one per by-value cycle: the same set
      --  Emit_Parser asks for at the commit point.  Assigned in the statement
      --  part, after the leaf sort has rejected a scalar cycle -- the alias
      --  chase inside Back_Edges_C is finite only once that has passed, so it
      --  cannot be a constant elaborated here.
      Backs : Edge_Vectors.Vector := Edge_Vectors.Empty_Vector;

      --  True when this struct field is the one chosen to break a cycle, so
      --  it is held and passed as a pointer.  A member name is unique within
      --  its struct, so (Owner, Member) names the edge.
      function Is_Back (Owner : Natural; Member : String) return Boolean is
      begin
         for E of Backs loop
            if E.Owner = Owner and then To_String (E.Member) = Member then
               return True;
            end if;
         end loop;
         return False;
      end Is_Back;

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
            J : constant Natural := Resolve (N);
         begin
            if J > 0 then
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
                     --  A list field already holds two pointers, and a
                     --  back-edge field is about to become one, so neither
                     --  imposes a by-value order.
                     if not M.Is_List
                       and then not Is_Back (Idx, To_String (M.Name))
                     then
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
      --  alternative matched.  A list rewritten from left recursion (Base)
      --  has a first value, <CN>_BASE, for its first entry, the base.
      --  Render a template from the table of name/value rows (RFCPLAN.md
      --  step 3: a hole with no row is Render's error).
      function Kind_Enum (CN : String; Tags : String_Vectors.Vector;
                          Base : Boolean := False)
         return String is
         Items : U;
         Names : constant String_Vectors.Vector := Enum_Names (Tags);
         --  Hoisted out of the Bind aggregate below: GNAT 13.3.0 raises
         --  Program_Error (sem_type.adb:811) on a quantified expression
         --  inside an array aggregate of function calls.
         Has_Base : constant Boolean :=
           (for some N of Names => To_String (N) = "BASE");
      begin
         if Base then
            Append (Items, Fill ("c_enum_base",
              (H ("ident", C_Ident (CN)),
               H ("suffix",
                 (if Has_Base then "_0" else "")))));
            Append (Items, LF);
         end if;
         for I in 1 .. Natural (Tags.Length) loop
            Append (Items, Fill
              ((if I < Natural (Tags.Length)
                then "c_enum_item" else "c_enum_item_last"),
               (H ("ident", C_Ident (CN) & "_" & To_String (Names (I))),
                H ("lit", To_String (Tags (I))),
                H ("init", ""))));
            Append (Items, LF);
         end loop;
         return Fill ("c_enum",
           (H ("name", Pfx & CN & "_kind_t"),
            H ("items", To_String (Items)))) & LF;
      end Kind_Enum;

      function Emit_Rule (Idx : Natural; Info : Rule_Info) return String is
         R  : constant Rule := Rules (Idx);
         NM : constant String := To_String (R.Name);
         CN : constant String := C_Name (NM);
         Buf : U;

         --  One field of a struct or of a list's node.  A field whose rule
         --  is itself a list holds that list's head, not one of its nodes:
         --  the head is two pointers, so a forward declaration is enough and
         --  the parse code, the free function and the walkers already pass
         --  `&n->field` to the list-taking entry points.  Declaring the node
         --  type here instead is what made a list of a list (`sums = 1*sum`
         --  with `sum` left-recursive) emit C that does not compile.
         function Field_Decl (Nm : String; Forced : Boolean) return String is
            J       : constant Natural := Find (Nm);
            Is_Head : constant Boolean :=
              Forced or else (J > 0 and then Infos (J).Kind = List);
            --  The field chosen to break a by-value cycle: its rule's type
            --  contains this struct, so it is held as a pointer instead of
            --  by value, which is what stops the type being infinitely sized.
            Ptr     : constant Boolean :=
              not Is_Head and then Is_Back (Idx, Nm);
         begin
            return Fill
              ((if Is_Head then "c_list_field"
                elsif Ptr then "c_ptr_field"
                else "c_field"),
               (H ("type",
                  (if Is_Head then Pfx & C_Name (Nm) else C_Type_Of (Nm))),
                H ("field", C_Field (Nm))));
         end Field_Decl;
      begin
         if R.Leading_Comment /= Null_Unbounded_String then
            Append (Buf, "/* " & To_String (R.Leading_Comment) & " */");
            Append (Buf, LF);
         end if;

         case Info.Kind is
            when Scalar =>
               Append (Buf, Fill ("c_scalar",
                 (H ("type", (if Views_On and then To_String (Info.Inline_Type) = "const char *"
                              then "hbnf_str" else To_String (Info.Inline_Type))),
                  H ("name", C_Type_Name (NM)))));
               Append (Buf, LF);
            when Enum =>
               declare
                  Names : constant String_Vectors.Vector := Enum_Names (Info.Literals);
                  Items : U;
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
                     Append (Items, Fill
                       ((if J < Count
                         then "c_enum_item" else "c_enum_item_last"),
                        (H ("ident",
                           C_Ident (NM) & "_" & To_String (Names (I))),
                         H ("lit", To_String (Info.Literals (I))),
                         H ("init", Enum_Init (Vals, Ord, J)))));
                     Append (Items, LF);
                     end;
                  end loop;
                  Append (Buf, Fill ("c_enum",
                    (H ("name", C_Type_Name (NM)),
                     H ("items", To_String (Items)))));
               end;
               Append (Buf, LF);
            when Struct =>
               if not Info.Tags.Is_Empty then
                  Append (Buf, Kind_Enum (CN, Info.Tags));
               end if;
               declare
                  Pre   : U;
                  Items : U;
                  Post  : U;
               begin
                  if Idref then
                     Append (Pre, HBNF_Template.Get ("c_idref"));
                     Append (Pre, LF);
                  end if;
                  if not Info.Tags.Is_Empty then
                     Append (Pre, Fill ("c_kind",
                       (1 => H ("kind", Pfx & CN & "_kind_t"))));
                     Append (Pre, LF);
                  end if;
                  if Ast_On and then not Rule_Alts (R, False).Is_Empty then
                     Append (Pre, "    " & "unsigned short _alt;   /* the "
                       & "alternative taken (--ast) */");
                     Append (Pre, LF);
                  end if;
                  if Spans_On then
                     Append (Pre, "    size_t _pos, _end;   /* where in the text"
                       & " (--spans) */" & LF);
                  end if;
                  if Parents_On then
                     Append (Pre, "    const void *_up;   /* the node that "
                       & "holds this one (--parents; node_link) */" & LF
                       & "    unsigned short _upk;   /* and its rule */" & LF);
                  end if;
                  if Is_Choice (R) then
                     Append (Pre, "    unsigned short _alt;   /* the alternative taken, from 1: the"
                       & " member of the union that is set */" & LF);
                     Append (Items, "    union {" & LF);
                  end if;
                  for M of Info.Members loop
                     Append (Items,
                       Field_Decl (To_String (M.Name), M.Is_List));
                     Append (Items, LF);
                  end loop;
                  if Is_Choice (R) then
                     Append (Items, "    };" & LF);
                  end if;
                  if R.Action_Code /= Null_Unbounded_String then
                     Append (Post, HBNF_Template.Get ("c_line"));
                     Append (Post, LF);
                  end if;
                  Append (Buf, Fill ("c_struct",
                    (H ("name", Pfx & C_Tag (NM)),
                     H ("pre", To_String (Pre)),
                     H ("items", To_String (Items)),
                     H ("post", To_String (Post)))));
               end;
               Append (Buf, LF);
            when List =>
               --  A list-linked node; the head is a `struct <CN>_list`
               --  embedded in the parent.
               if not Info.Tags.Is_Empty then
                  Append (Buf, Kind_Enum (CN, Info.Tags, R.Left_Bases > 0));
               end if;
               declare
                  Pre   : U;
                  Items : U;
                  Post  : U;
               begin
                  if Idref then
                     Append (Pre, HBNF_Template.Get ("c_idref"));
                     Append (Pre, LF);
                  end if;
                  if not Info.Tags.Is_Empty then
                     Append (Pre, Fill ("c_kind",
                       (1 => H ("kind", Pfx & CN & "_kind_t"))));
                     Append (Pre, LF);
                  end if;
                  Append (Items, Fill ("c_entry",
                    (1 => H ("entry", L_Entry (Pfx & C_Tag (NM))))));
                  Append (Items, LF);
                  if Ast_On and then not Rule_Alts (R, True).Is_Empty then
                     Append (Items, "    " & "unsigned short _alt;   /* the "
                       & "alternative taken (--ast) */");
                     Append (Items, LF);
                  end if;
                  if Spans_On then
                     Append (Items, "    size_t _pos, _end;   /* where in the "
                       & "text (--spans) */" & LF);
                  end if;
                  if Parents_On then
                     Append (Items, "    const void *_up;   /* the node that "
                       & "holds this one (--parents; node_link) */" & LF
                       & "    unsigned short _upk;   /* and its rule */" & LF);
                  end if;
                  if Info.Elem_Members.Is_Empty then
                     if Info.Elem_Name /= Null_Unbounded_String then
                        Append (Items,
                          Field_Decl (To_String (Info.Elem_Name), False));
                     else
                        Append (Items, HBNF_Template.Get ("c_value"));
                     end if;
                     Append (Items, LF);
                  else
                     for M of Info.Elem_Members loop
                        Append (Items,
                          Field_Decl (To_String (M.Name), M.Is_List));
                        Append (Items, LF);
                     end loop;
                  end if;
                  if R.Action_Code /= Null_Unbounded_String then
                     Append (Post, HBNF_Template.Get ("c_line"));
                     Append (Post, LF);
                  end if;
                  Append (Buf, Fill ("c_struct",
                    (H ("name", Pfx & C_Tag (NM)),
                     H ("pre", To_String (Pre)),
                     H ("items", To_String (Items)),
                     H ("post", To_String (Post)))));
               end;
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
         procedure Recurse (Idx : Natural; Name : String; Prefix : String;
                            Buf : in out U; Ind : String) is
            F : constant String := C_Field (Name);
            --  A back-edge struct field is a pointer, so the walker takes it
            --  as it stands; every other field is held by value and is
            --  addressed.  A list field is a head by value either way.
            Ref : constant String :=
              (if Ref_Kind (Name) = Struct and then Is_Back (Idx, Name)
               then "n->" & F else "&n->" & F);
         begin
            case Ref_Kind (Name) is
               when Struct | List =>
                  Append (Buf, Ind & Prefix & "_"
                    & C_Name (Alias_Target (Rules, Name))
                    & "(" & Ref & ", f, ctx);");
               when others =>
                  return;
            end case;
            Append (Buf, LF);
         end Recurse;

         --  The element fields of a list node: a single named element, the
         --  bare `value` field, or the members of a grouped element.
         procedure Recurse_Elem (Idx : Natural; Info : Rule_Info;
                                 Prefix : String;
                                 Buf : in out U; Ind : String) is
         begin
            if Info.Elem_Members.Is_Empty then
               if Info.Elem_Name /= Null_Unbounded_String then
                  Recurse (Idx, To_String (Info.Elem_Name), Prefix, Buf, Ind);
               end if;
            else
               for M of Info.Elem_Members loop
                  Recurse (Idx, To_String (M.Name), Prefix, Buf, Ind);
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
               if Is_Choice (Rules (Idx)) then
                  Append (Buf, "    switch (n->_alt) {" & LF);
                  declare
                     K : Natural := 0;
                  begin
                     for M of Info.Members loop
                        K := K + 1;
                        Append (Buf, "    case " & Img (K) & ":" & LF);
                        Recurse (Idx, To_String (M.Name), "visit", Buf, "        ");
                        Append (Buf, "        break;" & LF);
                     end loop;
                  end;
                  Append (Buf, "    default: break;" & LF & "    }" & LF);
               else
               for M of Info.Members loop
                  Recurse (Idx, To_String (M.Name), "visit", Buf, "    ");
               end loop;
               end if;
            else
               Append (Buf, "static void visit_" & CN & "(const struct " & Pfx & CN
                 & "_list *head, visit_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    const " & TN & " *n;");
               Append (Buf, LF);
               Append (Buf, "    " & L_Foreach ("n", "head", Rule => To_String (Rules (Idx).Name)) & " {");
               Append (Buf, LF);
               Append (Buf, "        f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
               Recurse_Elem (Idx, Info, "visit", Buf, "        ");
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
               if Is_Choice (Rules (Idx)) then
                  Append (Buf, "    switch (n->_alt) {" & LF);
                  declare
                     K : Natural := 0;
                  begin
                     for M of Info.Members loop
                        K := K + 1;
                        Append (Buf, "    case " & Img (K) & ":" & LF);
                        Recurse (Idx, To_String (M.Name), "map", Buf, "        ");
                        Append (Buf, "        break;" & LF);
                     end loop;
                  end;
                  Append (Buf, "    default: break;" & LF & "    }" & LF);
               else
               for M of Info.Members loop
                  Recurse (Idx, To_String (M.Name), "map", Buf, "    ");
               end loop;
               end if;
               Append (Buf, "    f(n, NODE_" & C_Ident (CN) & ", ctx);");
               Append (Buf, LF);
            else
               Append (Buf, "static void map_" & CN & "(struct " & Pfx & CN
                 & "_list *head, map_fn f, void *ctx) {");
               Append (Buf, LF);
               Append (Buf, "    " & TN & " *n;");
               Append (Buf, LF);
               Append (Buf, "    " & L_Foreach ("n", "head", Rule => To_String (Rules (Idx).Name)) & " {");
               Append (Buf, LF);
               Recurse_Elem (Idx, Info, "map", Buf, "        ");
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
            if First then
               --  No tree nodes (an all-scalar schema, e.g. a char-only
               --  alphabet): give the enum a sentinel so it is not empty
               --  (an empty enum is invalid C).
               Append (Buf, "    NODE_NONE");
               First := False;
            end if;
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
                     Append (Buf, "static void __attribute__((unused)) visit_" & CN & "(const struct " & Pfx & CN
                       & "_list *, visit_fn f, void *ctx);");
                     Append (Buf, LF);
                     Append (Buf, "static void __attribute__((unused)) map_" & CN & "(struct " & Pfx & CN
                       & "_list *, map_fn f, void *ctx);");
                  else
                     Append (Buf, "static void __attribute__((unused)) visit_" & CN & "(const "
                       & TN & " *, visit_fn f, void *ctx);");
                     Append (Buf, LF);
                     Append (Buf, "static void __attribute__((unused)) map_" & CN & "("
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

         procedure Recurse (Idx : Natural; Name : String;
                            Buf : in out U; Ind : String) is
            F : constant String := C_Field (Name);
            --  As in Emit_Walk: a back-edge struct field is a pointer and is
            --  passed as it stands; every other field is addressed.
            Ref : constant String :=
              (if Ref_Kind (Name) = Struct and then Is_Back (Idx, Name)
               then "n->" & F else "&n->" & F);
         begin
            case Ref_Kind (Name) is
               when Struct | List =>
                  Append (Buf, Ind & "bind_"
                    & C_Name (Alias_Target (Rules, Name)) & "(" & Ref & ");");
                  Append (Buf, LF);
               when others =>
                  --  A bit rule's record is a field of its own: its actions
                  --  (the readers are in the wire emitter's code) run here.
                  if HBNF_Grammar.Is_Wire_Rule (Alias_Target (Rules, Name)) then
                     Append (Buf, Ind & "walk_"
                       & C_Name (Alias_Target (Rules, Name)) & "(&n->" & F
                       & ");");
                     Append (Buf, LF);
                  end if;
            end case;
         end Recurse;

         procedure Recurse_Elem (Idx : Natural; Info : Rule_Info;
                                 Buf : in out U; Ind : String)
         is
         begin
            if Info.Elem_Members.Is_Empty then
               if Info.Elem_Name /= Null_Unbounded_String then
                  Recurse (Idx, To_String (Info.Elem_Name), Buf, Ind);
               end if;
            else
               for M of Info.Elem_Members loop
                  Recurse (Idx, To_String (M.Name), Buf, Ind);
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
               if Act /= "" then
                  --  A struct is embedded in its parent whether or not the
                  --  parse matched it (one of an entry's alternatives, an
                  --  optional part): _line, set when it matches, tells.
                  Append (Buf, "    if (!n || !n->_line) return;"
                    & "  /* not in the config */");
               else
                  Append (Buf, "    if (!n) return;");
               end if;
               Append (Buf, LF);
               for M of Info.Members loop
                  Recurse (Idx, To_String (M.Name), Buf, "    ");
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
               Append (Buf, "    " & L_Foreach ("n", "head", Rule => To_String (Rules (Idx).Name)) & " {");
               Append (Buf, LF);
               Recurse_Elem (Idx, Info, Buf, "        ");
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
           "   (a config grammar's epilogue points it at conf_error); otherwise the first" & LF &
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
            elsif Rules (I).Action_Code /= Null_Unbounded_String then
               --  The walk visits nodes; an enum or scalar is a field of
               --  one, and its action would silently never run.
               raise HBNF_Grammar.Parse_Error with
                 To_String (Rules (I).Name) & ": an action runs on a node "
                 & "(a sequence, alternation or list rule); this rule is "
                 & (if Infos (I).Kind = Enum then "an enum" else "a scalar")
                 & ", so put the action on the rule that uses it";
            end if;
         end loop;
      end Emit_Bind;


      --  Emit the AST support (--ast): tables describing the tree, and one
      --  small shared walker over them.  The tables cost a few bytes a member
      --  (a row of macros each), the walker a fixed ~2 KB of source, so the
      --  cost does not grow with a rule of code per rule.  node_walk (enter,
      --  leave, skip, stop), node_kids (the members of a node, leaves too),
      --  node_kind_name, node_alt, node_alt_name, node_dump and node_equal
      --  work on any node of any grammar.
      procedure Emit_Ast (Buf : in out U) is

         Rows, Branch_Rows, Rule_Rows, Enum_Rows, Enum_Heads : U;
         N_Mem : Natural := 1;            --  row 0 is a placeholder
         N_Br, N_Ev, N_En : Natural := 0;
         Used : U;                       --  the macros the rows use (HN, HS, ...)
         --  The grammar's own list container (layout_ops): the walker reads its
         --  lists through two small functions per list rule, not offsets.
         Own_Lists : constant Boolean :=
           HBNF_Grammar.List_Override ("first") /= ""
           or else HBNF_Grammar.List_Override ("next") /= "";
         Node_Of : array (1 .. N) of Natural := [others => 0];
         Enum_Of : array (1 .. N) of Natural := [others => 0];

         function Ref_Kind (Nm : String) return Class_Kind is
            J : constant Natural := Find (Alias_Target (Rules, Nm));
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         function Img (X : Natural) return String is
            S : constant String := Natural'Image (X);
         begin
            return S (S'First + 1 .. S'Last);
         end Img;

         function Members_Of
           (Els : Element_Vectors.Vector; First, Last : Natural)
            return Member_Vectors.Vector
         is
            Sub  : Element_Vectors.Vector;
            Ms   : Member_Vectors.Vector;
            Lits : String_Vectors.Vector;
            Alt  : Boolean := False;
         begin
            for K in First .. Last loop
               Sub.Append (Els (K));
            end loop;
            Collect (Sub, Ms, Lits, Alt);
            return Ms;
         end Members_Of;

         --  The row for member Nm of rule Idx, or "" for one the walker has
         --  nothing to say about.
         function Row (Idx : Natural; Nm : String) return String is
            T  : constant String := C_Type_Name (To_String (Rules (Idx).Name));
            F  : constant String := C_Field (Nm);
            A  : constant String := Alias_Target (Rules, Nm);
            J  : constant Natural := Find (A);
            Pre : constant String := "(" & T & "," & F;
         begin
            case Ref_Kind (Nm) is
               when Struct =>
                  return (if Is_Back (Idx, Nm) then "HP" else "HN") & Pre & ","
                    & Img (Node_Of (J)) & ")";
               when List =>
                  return "HL" & Pre & "," & Img (Node_Of (J)) & ")";
               when Enum =>
                  return "HE" & Pre & "," & Img (Enum_Of (J)) & ")";
               when Scalar =>
                  declare
                     Ty : constant String :=
                       (if Scalar_C_Type (Nm) /= "" then Scalar_C_Type (Nm)
                        elsif Resolve_Type (Nm) /= "" then Resolve_Type (Nm)
                        elsif J /= 0 and then Infos (J).Kind = Scalar
                        then To_String (Infos (J).Inline_Type) else "");
                  begin
                     if Ty = "const char *" then
                        return "HS" & Pre & ")";
                     elsif Ty = "bool" then
                        return "HB" & Pre & ")";
                     elsif Ty = "long long" or else (Ty'Length > 3
                             and then Ty (Ty'First .. Ty'First + 2) = "int")
                     then
                        return "HI" & Pre & ")";
                     elsif Ty'Length > 4
                       and then Ty (Ty'First .. Ty'First + 3) = "uint"
                     then
                        return "HU" & Pre & ")";
                     end if;
                     return "";
                  end;
            end case;
         end Row;

         --  One branch: its members, in the tables.
         procedure Branch (Idx : Natural; Ms : Member_Vectors.Vector;
                           Label : String) is
            First : constant Natural := N_Mem;
         begin
            for M of Ms loop
               declare
                  R : constant String := Row (Idx, To_String (M.Name));
               begin
                  if R /= "" then
                     if Index (Used, R (R'First .. R'First + 1)) = 0 then
                        Append (Used, R (R'First .. R'First + 1) & " ");
                     end if;
                     Append (Rows, R & "," & LF);
                     N_Mem := N_Mem + 1;
                  end if;
               end;
            end loop;
            Append (Branch_Rows, "{" & Img (First) & "," & Img (N_Mem - First)
              & ",""" & C_Escape (Label) & """}," & LF);
            N_Br := N_Br + 1;
         end Branch;

         --  The branches of a flat list of elements, one Branch each.
         procedure Branches (Idx : Natural; Els : Element_Vectors.Vector) is
            Last   : constant Natural := Natural (Els.Length);
            Labels : constant String_Vectors.Vector := Alt_Labels (Els);
            St     : Natural := 1;
            Br     : Natural := 0;
         begin
            for K in 1 .. Last + 1 loop
               if K > Last or else Els (K).Kind = Alt then
                  Br := Br + 1;
                  Branch (Idx, Members_Of (Els, St, K - 1),
                          To_String (Labels (Br)));
                  St := K + 1;
               end if;
            end loop;
         end Branches;

      begin
         declare
            Cn : Natural := 0;
            Ce : Natural := 0;
         begin
            for I in 1 .. N loop
               if Infos (I).Kind in Struct | List then
                  Node_Of (I) := Cn;
                  Cn := Cn + 1;
               elsif Infos (I).Kind = Enum then
                  Enum_Of (I) := Ce;
                  Ce := Ce + 1;
               end if;
            end loop;
         end;
         --  Enums: their values and spellings.
         for I in 1 .. N loop
            if Infos (I).Kind = Enum then
               declare
                  NM    : constant String := To_String (Rules (I).Name);
                  Names : constant String_Vectors.Vector :=
                    Enum_Names (Infos (I).Literals);
               begin
                  Append (Enum_Heads, "{" & Img (N_Ev) & ","
                    & Img (Natural (Infos (I).Literals.Length)) & "}," & LF);
                  N_En := N_En + 1;
                  for K in 1 .. Natural (Infos (I).Literals.Length) loop
                     Append (Enum_Rows, "{(int)" & C_Ident (NM) & "_"
                       & To_String (Names (K)) & ",""" 
                       & C_Escape (To_String (Infos (I).Literals (K)))
                       & """}," & LF);
                     N_Ev := N_Ev + 1;
                  end loop;
               end;
            end if;
         end loop;
         --  Rules: their branches and members.
         for I in 1 .. N loop
            if Infos (I).Kind in Struct | List then
               declare
                  R    : constant Rule := Rules (I);
                  Info : constant Rule_Info := Infos (I);
                  T    : constant String := C_Type_Name (To_String (R.Name));
                  Alts : constant String_Vectors.Vector :=
                    Rule_Alts (R, Info.Kind = List);
                  B0   : constant Natural := N_Br;
               begin
                  if Info.Kind = Struct then
                     if Alts.Is_Empty then
                        Branch (I, Info.Members, To_String (R.Name));
                     else
                        Branches (I, R.Pattern);
                     end if;
                  elsif R.Left_Bases > 0 then
                     Branches (I, Base_Branches (R));
                     Branches (I, Tail_Branches (R));
                  elsif R.Pattern (1).Kind = Group then
                     if Alts.Is_Empty then
                        Branch (I, Info.Elem_Members, To_String (R.Name));
                     else
                        Branches (I, R.Pattern (1).Items);
                     end if;
                  elsif Info.Elem_Name /= Null_Unbounded_String then
                     declare
                        One : Member_Vectors.Vector;
                     begin
                        One.Append (Member'(Name => Info.Elem_Name,
                                            Is_List => False));
                        Branch (I, One, To_String (R.Name));
                     end;
                  else
                     Append (Rows, "HS(" & T & ",value)," & LF);
                     N_Mem := N_Mem + 1;
                     Append (Branch_Rows, "{" & Img (N_Mem - 1) & ",1,"""
                       & C_Escape (To_String (R.Name)) & """}," & LF);
                     N_Br := N_Br + 1;
                  end if;
                  Append (Rule_Rows, "{""" & C_Escape (To_String (R.Name))
                    & """," & Img (B0) & "," & Img (N_Br - B0) & ","
                    & (if Alts.Is_Empty then "0xFFFF"
                       else "offsetof(" & T & ",_alt)") & ","
                    & (if Info.Kind = List and then not Own_Lists
                       then "offsetof(" & T & ",_link)" else "0") & ","
                    & (if Info.Kind = List and then Own_Lists
                       then "lf_" & C_Name (To_String (R.Name)) & ",ln_"
                            & C_Name (To_String (R.Name))
                       else "0,0") & ","
                    & (if Spans_On then "offsetof(" & T & ",_pos)"
                       else "0xFFFF") & ","
                    & (if Parents_On then "offsetof(" & T & ",_up),offsetof("
                         & T & ",_upk)" else "0xFFFF,0") & "}," & LF);
               end;
            end if;
         end loop;

         Append (Buf, "/* ---- the tree, described: tables and one walker (--ast) ---- */"
           & LF
           & "enum { HM_NODE, HM_PTR, HM_LIST, HM_STR, HM_INT, HM_UINT, HM_BOOL, "
           & "HM_ENUM };" & LF
           & "typedef struct { const char *name; unsigned short off; "
           & "unsigned char type, target, size; } hbnf_m_t;" & LF
           & "typedef struct { unsigned short first, n; const char *name; } "
           & "hbnf_b_t;" & LF
           & "typedef struct { const char *name; unsigned short b0, nb, alt, "
           & "link; const void *(*first)(const void *); "
           & "const void *(*next)(const void *); "
           & "unsigned short span, up, upk; } hbnf_r_t;" & LF
           & "" );
         declare
            procedure Def (Id, Text : String) is
            begin
               if Index (Used, Id) /= 0 then
                  Append (Buf, "#define " & Text & LF);
               end if;
            end Def;
         begin
            Def ("HN", "HN(T,f,g) {#f, offsetof(T,f), HM_NODE, g, 0}");
            Def ("HP", "HP(T,f,g) {#f, offsetof(T,f), HM_PTR, g, 0}");
            Def ("HL", "HL(T,f,g) {#f, offsetof(T,f), HM_LIST, g, 0}");
            Def ("HS", "HS(T,f) {#f, offsetof(T,f), HM_STR, 0, 0}");
            Def ("HI", "HI(T,f) {#f, offsetof(T,f), HM_INT, 0, sizeof (((T *)0)->f)}");
            Def ("HU", "HU(T,f) {#f, offsetof(T,f), HM_UINT, 0, sizeof (((T *)0)->f)}");
            Def ("HB", "HB(T,f) {#f, offsetof(T,f), HM_BOOL, 0, sizeof (((T *)0)->f)}");
            Def ("HE", "HE(T,f,g) {#f, offsetof(T,f), HM_ENUM, g, sizeof (((T *)0)->f)}");
         end;
         Append (Buf, "static const hbnf_m_t hbnf_m[] = {" & LF
           & "{0,0,0,0,0}," & LF & To_String (Rows) & "};" & LF);
         Append (Buf, "static const hbnf_b_t hbnf_b[] = {" & LF
           & To_String (Branch_Rows) & "};" & LF);
         if Own_Lists then
            for I in 1 .. N loop
               if Infos (I).Kind = List then
                  declare
                     CN : constant String := C_Name (To_String (Rules (I).Name));
                     TN : constant String :=
                       C_Type_Name (To_String (Rules (I).Name));
                  begin
                     Append (Buf, "static const void *lf_" & CN
                       & " (const void *h) { return " & L_First ("((const struct "
                       & Pfx & CN & "_list *)h)", Rule => To_String (Rules (I).Name)) & "; }" & LF
                       & "static const void *ln_" & CN
                       & " (const void *e) { return " & L_Next ("((const " & TN
                       & " *)e)", Rule => To_String (Rules (I).Name)) & "; }" & LF);
                  end;
               end if;
            end loop;
         end if;
         Append (Buf, "static const hbnf_r_t hbnf_r[] = {" & LF
           & To_String (Rule_Rows) & "};" & LF);
         if Ast_Tools_On then
            Append (Buf, "typedef struct { int v; const char *name; } hbnf_ev_t;"
              & LF
              & "typedef struct { unsigned short first, n; } hbnf_e_t;" & LF
              & "static const hbnf_ev_t hbnf_ev[] = {" & LF
              & (if N_En = 0 then "{0,0}," & LF else To_String (Enum_Rows))
              & "};" & LF
              & "static const hbnf_e_t hbnf_e[] = {" & LF
              & (if N_En = 0 then "{0,0}," & LF else To_String (Enum_Heads))
              & "};" & LF);
         end if;
         declare
            All_Ids : constant String := "HNHPHLHSHIHUHBHE";
         begin
            for K in 0 .. 7 loop
               if Index (Used, All_Ids (1 + 2 * K .. 2 + 2 * K)) /= 0 then
                  Append (Buf, "#undef " & All_Ids (1 + 2 * K .. 2 + 2 * K)
                    & LF);
               end if;
            end loop;
         end;
         Append (Buf, HBNF_Template.Get ("c_ast"));
         Append (Buf, LF);
         if Spans_On then
            Append (Buf, HBNF_Template.Get ("c_ast_spans"));
            Append (Buf, LF);
         end if;
         if Parents_On then
            Append (Buf, HBNF_Template.Get ("c_ast_parents"));
            Append (Buf, LF);
         end if;
         if Ast_Tools_On then
            Append (Buf, HBNF_Template.Get ("c_ast_tools"));
            Append (Buf, LF);
         end if;
         --  The whole tree: the root rule's walk and dump.
         declare
            RN : constant String := C_Name (To_String (Rules (1).Name));
            RT : constant String := C_Type_Name (To_String (Rules (1).Name));
         begin
            if Infos (1).Kind = Struct then
               Append (Buf, "static int walk_" & RN & " (const " & RT
                 & " *root, walk_fn f, void *ctx) { return node_walk (root, NODE_"
                 & C_Ident (RN) & ", f, ctx); }" & LF);
               if Ast_Tools_On then
                  Append (Buf, "static size_t dump_" & RN & " (const " & RT
                    & " *root, char *buf, size_t cap) { return node_dump (root, "
                    & "NODE_" & C_Ident (RN) & ", buf, cap); }" & LF);
               end if;
            elsif Infos (1).Kind = List then
               Append (Buf, "static int walk_" & RN & " (const struct " & Pfx
                 & RN & "_list *root, walk_fn f, void *ctx) {" & LF
                 & "    const " & RT & " *e;" & LF
                 & "    " & L_Foreach ("e", "root", Rule => To_String (Rules (1).Name)) & LF
                 & "        if (!node_walk (e, NODE_" & C_Ident (RN)
                 & ", f, ctx)) return 0;" & LF
                 & "    return 1;" & LF & "}" & LF);
               if Parents_On then
                  Append (Buf, "static void link_" & RN & " (const struct "
                    & Pfx & RN & "_list *root) {" & LF
                    & "    const " & RT & " *e;" & LF
                    & "    " & L_Foreach ("e", "root", Rule => To_String (Rules (1).Name)) & LF
                    & "        node_link (e, NODE_" & C_Ident (RN) & ");" & LF
                    & "}" & LF);
               end if;
               if Ast_Tools_On then
               Append (Buf, "static size_t dump_" & RN & " (const struct " & Pfx & RN
                 & "_list *root, char *buf, size_t cap) {" & LF
                 & "    hbnf_dump_t d;  const " & RT & " *e;" & LF
                 & "    d.buf = buf;  d.cap = cap;  d.len = 0;" & LF
                 & "    hbnf_dput (&d, ""("", 1);  hbnf_dstr (&d, """ & RN
                 & """);" & LF
                 & "    " & L_Foreach ("e", "root", Rule => To_String (Rules (1).Name)) & " {" & LF
                 & "        hbnf_dput (&d, "" "", 1);" & LF
                 & "        hbnf_ddump (&d, e, NODE_" & C_Ident (RN) & ");" & LF
                 & "    }" & LF
                 & "    hbnf_dput (&d, "")"", 1);" & LF
                 & "    if (buf && cap) buf[d.len < cap ? d.len : cap - 1] = 0;"
                 & LF
                 & "    return d.len;" & LF
                 & "}" & LF);
               end if;
            end if;
         end;
      end Emit_Ast;

      --  Emit write_<root>: the tree as text, when the grammar was generated
      --  with --writer.  Canonical, not lossless: literals come from the
      --  grammar, tokens from their text, and a blank goes between two items
      --  only where they would run together (hbnf_wgap).  A rule's alternative
      --  is the one the parser recorded in `_alt`.  What it cannot write it
      --  says at run time, at the node (hbnf_wbad), so a shape that is not
      --  built yet is never written as something close.
      procedure Emit_Writer (Buf : in out U) is

         function Ref_Kind (Nm : String) return Class_Kind is
            J : constant Natural := Find (Alias_Target (Rules, Nm));
         begin
            if J = 0 then
               return Scalar;
            end if;
            return Infos (J).Kind;
         end Ref_Kind;

         --  A rule whose value came from the core `str` (so it is quoted
         --  again when written).
         function Has_Str (Nm : String; Depth : Natural := 0) return Boolean is
            J : constant Natural := Find (Nm);
         begin
            if Nm = "str" then
               return True;
            end if;
            if J = 0 or else Depth > 8 then
               return False;
            end if;
            for E of Rules (J).Pattern loop
               if E.Kind = HBNF_Grammar.Name
                 and then Has_Str (To_String (E.Name), Depth + 1)
               then
                  return True;
               end if;
            end loop;
            return False;
         end Has_Str;

         function Img (X : Natural) return String is
            S : constant String := Natural'Image (X);
         begin
            return S (S'First + 1 .. S'Last);
         end Img;

         function Bad (Why : String) return String is
           ("hbnf_wbad (w, """ & C_Escape (Why) & """);");

         --  The scanners the writer calls to see whether two items would
         --  read back as they were written (hbnf_wsep); declared ahead.
         Scans : String_Vectors.Vector;

         function Scan_Of (Fn : String) return String is
         begin
            if not Scans.Contains (To_Unbounded_String (Fn)) then
               Scans.Append (To_Unbounded_String (Fn));
            end if;
            return Fn;
         end Scan_Of;

         --  The scanner a core type reads with: the rule the grammar defines
         --  for it, or the built-in.
         function Core_Scan (Nm : String) return String is
            Core : constant String :=
              (if Nm = "str" then "str"
               elsif Nm = "int" then "int"
               elsif Scalar_C_Type (Nm) (Scalar_C_Type (Nm)'First) in 'u' | 'i'
                 and then Scalar_C_Type (Nm) /= "int" then "int"
               else "word");
            J : constant Natural := Find (Core);
         begin
            if J /= 0 and then Rules (J).Jet_Code /= Null_Unbounded_String then
               return Scan_Of ("jet_" & Core);
            end if;
            return Scan_Of ("scan_" & Core);
         end Core_Scan;

         --  The C statement writing the scalar Expr that the rule or core
         --  type Nm yields.
         function Leaf (Nm, Expr, Gap : String) return String is
            Core : constant String := Scalar_C_Type (Nm);
            Ty   : U;
            Scan : U := To_Unbounded_String ("NULL");
         begin
            if Core /= "" then
               Ty := To_Unbounded_String (Core);
               Scan := To_Unbounded_String (Core_Scan (Nm));
            else
               declare
                  T : U := To_Unbounded_String (Alias_Target (Rules, Nm));
                  J : Natural := Find (To_String (T));
                  R : constant String := Resolve_Type (Nm);
               begin
                  if J = 0 or else Infos (J).Kind /= Scalar then
                     return Bad ("`" & Nm & "` is not a value the writer "
                                 & "knows how to write");
                  end if;
                  --  An alias of an alias of a token reads with the token's
                  --  scanner and has its type.
                  for Hop in 1 .. 8 loop
                     exit when Natural (Rules (J).Pattern.Length) /= 1
                       or else Rules (J).Pattern (1).Kind /= HBNF_Grammar.Name
                       or else Rules (J).Jet_Code /= Null_Unbounded_String
                       or else Is_Char_Rule (Rules, To_String (T))
                       or else Find (To_String (Rules (J).Pattern (1).Name)) = 0
                       or else Scalar_C_Type
                                 (To_String (Rules (J).Pattern (1).Name)) /= "";
                     T := Rules (J).Pattern (1).Name;
                     J := Find (To_String (T));
                  end loop;
                  Ty := (if R /= "" then To_Unbounded_String (R)
                         elsif Infos (J).Kind = Scalar then Infos (J).Inline_Type
                         else To_Unbounded_String (""));
                  if Has_Str (Nm) then
                     Scan := To_Unbounded_String (Core_Scan ("str"));
                  elsif Is_Char_Rule (Rules, To_String (T)) then
                     Scan := To_Unbounded_String
                       (Scan_Of ((if Rules (J).Jet_Code /= Null_Unbounded_String
                                  then "jet_" else "scan_")
                                 & C_Name (To_String (T))));
                  end if;
               end;
            end if;
            declare
               T  : constant String := To_String (Ty);
               Sc : constant String := To_String (Scan);
            begin
               if T = "const char *" then
                  return (if Has_Str (Nm) then "hbnf_wstr" else "hbnf_wtok")
                    & " (w, " & Gap & ", " & Expr & ", " & Sc & ");";
               elsif T = "long long" or else (T'Length > 3
                       and then T (T'First .. T'First + 2) = "int")
               then
                  return "hbnf_wnum (w, " & Gap & ", (long long)(" & Expr
                    & "), " & Sc & ");";
               elsif T = "bool" then
                  return "hbnf_wtok (w, " & Gap & ", (" & Expr
                    & ") ? ""yes"" : ""no"", " & Core_Scan ("word") & ");";
               elsif T'Length > 4 and then T (T'First .. T'First + 3) = "uint"
               then
                  return "hbnf_wunum (w, " & Gap & ", (unsigned long long)("
                    & Expr & "), " & Sc & ");";
               end if;
               return Bad ("`" & Nm & "` has the type " & T
                           & ", which the writer cannot write");
            end;
         end Leaf;

         --  Write one element or run of elements, through accessor Acc.
         procedure Elements
           (Idx : Natural; Els : Element_Vectors.Vector; First, Last : Natural;
            Acc, Gap : String; Buf : in out U; Ind : String)
         is
            --  `x %as tag`: how the token x is written, for the `%same tag`
            --  that writes it again.
            Tags  : String_Vectors.Vector;
            Again : String_Vectors.Vector;
         begin
            for K in First .. Last loop
               declare
                  E : constant Element_Access := Els (K);
               begin
                  case E.Kind is
                     when Literal =>
                        Append (Buf, Ind & "hbnf_wlit (w, " & Gap & ", """
                          & C_Escape (To_String (E.Lit)) & """, "
                          & Img (To_String (E.Lit)'Length) & ");");
                        Append (Buf, LF);
                     when HBNF_Grammar.Name =>
                        declare
                           Nm : constant String := To_String (E.Name);
                           F  : constant String := C_Field (Nm);
                           T  : constant String := Alias_Target (Rules, Nm);
                           J  : constant Natural := Find (T);
                        begin
                           if E.Min /= 1 or else E.Max /= 1 then
                              Append (Buf, Ind & Bad ("a repeated name inside "
                                & "a sequence"));
                           elsif J = 0 and then Scalar_C_Type (Nm) = ""
                             and then HBNF_Grammar.Is_Wire_Rule (Nm)
                           then
                              --  A bit rule: its octets, written by its own
                              --  writer (which runs its %emit), go into the
                              --  text as they are.
                              Append (Buf, Ind & "{ static char e_[256]; "
                                & "size_t nb_; uint8_t *b_;");
                              Append (Buf, LF);
                              Append (Buf, Ind & "  bool emit_bits_"
                                & C_Name (Nm) & " (const "
                                & C_Type_Name (Nm) & " *, uint8_t *, size_t, "
                                & "size_t *, char *, size_t);");
                              Append (Buf, LF);
                              Append (Buf, Ind & "  if (!emit_bits_"
                                & C_Name (Nm) & " (&" & Acc & F
                                & ", NULL, 0, &nb_, e_, sizeof e_)) "
                                & "hbnf_wbad (w, e_);");
                              Append (Buf, LF);
                              Append (Buf, Ind & "  else if (nb_ % 8) hbnf_wbad "
                                & "(w, ""`" & Nm & "` does not end on an "
                                & "octet, so it cannot be written as text"");");
                              Append (Buf, LF);
                              Append (Buf, Ind & "  else if ((b_ = (uint8_t *)"
                                & "malloc (nb_ / 8 + 1)) == NULL) "
                                & "hbnf_wbad (w, ""out of memory"");");
                              Append (Buf, LF);
                              Append (Buf, Ind & "  else { if (!emit_bits_"
                                & C_Name (Nm) & " (&" & Acc & F
                                & ", b_, nb_ / 8, &nb_, e_, sizeof e_)) "
                                & "hbnf_wbad (w, e_); else hbnf_wput (w, "
                                & "(const char *)b_, nb_ / 8); free (b_); } }");
                           elsif Scalar_C_Type (Nm) /= "" or else J = 0 then
                              Append (Buf, Ind & Leaf (Nm, Acc & F, Gap));
                           else
                              case Infos (J).Kind is
                                 when Struct =>
                                    Append (Buf, Ind & "wr_" & C_Name (T)
                                      & " (w, "
                                      & (if Is_Back (Idx, Nm) then "" else "&")
                                      & Acc & F & ");");
                                 when List =>
                                    Append (Buf, Ind & "wr_" & C_Name (T)
                                      & " (w, &" & Acc & F & ");");
                                 when Enum =>
                                    Append (Buf, Ind & "wr_" & C_Name (T)
                                      & " (w, " & Acc & F & ");");
                                 when Scalar =>
                                    Append (Buf, Ind & Leaf (Nm, Acc & F, Gap));
                              end case;
                           end if;
                           Append (Buf, LF);
                        end;
                     when Group =>
                        if (for some X of E.Items => X.Kind = Alt) then
                           Append (Buf, Ind & Bad ("an alternation inside a "
                             & "group"));
                           Append (Buf, LF);
                        else
                           Elements (Idx, E.Items, 1, Natural (E.Items.Length),
                                     Acc, Gap, Buf, Ind);
                        end if;
                     when HBNF_Grammar.Block =>
                        --  a test or a binding writes nothing; a `%same` writes
                        --  the token its `%as` kept, again
                        if E.Op = B_As and then K > First
                          and then Els (K - 1).Kind = HBNF_Grammar.Name
                        then
                           declare
                              Nm : constant String := To_String (Els (K - 1).Name);
                           begin
                              Tags.Append (E.Ctx);
                              Again.Append (To_Unbounded_String
                                (Leaf (Nm, Acc & C_Field (Nm), Gap)));
                           end;
                        elsif E.Op = B_Same then
                           for T in 1 .. Natural (Tags.Length) loop
                              if Tags (T) = E.Ctx then
                                 Append (Buf, Ind & To_String (Again (T)));
                                 Append (Buf, LF);
                              end if;
                           end loop;
                        end if;
                     when others =>
                        Append (Buf, Ind & Bad ("an element the writer does "
                          & "not know"));
                        Append (Buf, LF);
                  end case;
               end;
            end loop;
         end Elements;

         --  The branches of a flat list of elements with Alt separators:
         --  `switch (Acc_alt)` over them, or the elements when there is one.
         procedure Branches
           (Idx : Natural; Els : Element_Vectors.Vector;
            Acc, Gap : String; Buf : in out U; Ind : String;
            Idents : String_Vectors.Vector)
         is
            Last : constant Natural := Natural (Els.Length);
            St   : Natural := 1;
            Br   : Natural := 0;
            Multi : constant Boolean := (for some X of Els => X.Kind = Alt);
         begin
            if not Multi then
               Elements (Idx, Els, 1, Last, Acc, Gap, Buf, Ind);
               return;
            end if;
            if Natural (Idents.Length) < Natural (Alt_Labels (Els).Length) then
               Append (Buf, Ind & Bad ("alternatives that are not recorded"));
               Append (Buf, LF);
               return;
            end if;
            Append (Buf, Ind & "switch (" & Acc & "_alt) {");
            Append (Buf, LF);
            for K in 1 .. Last + 1 loop
               if K > Last or else Els (K).Kind = Alt then
                  Br := Br + 1;
                  Append (Buf, Ind & "case " & To_String (Idents (Br)) & ":");
                  Append (Buf, LF);
                  Elements (Idx, Els, St, K - 1, Acc, Gap, Buf, Ind & "    ");
                  Append (Buf, Ind & "    break;");
                  Append (Buf, LF);
                  St := K + 1;
               end if;
            end loop;
            Append (Buf, Ind & "default: " & Bad ("no alternative was "
              & "recorded (generate with --writer)"));
            Append (Buf, LF);
            Append (Buf, Ind & "}");
            Append (Buf, LF);
         end Branches;

         procedure Define (Idx : Natural; Buf : in out U) is
            R    : constant Rule := Rules (Idx);
            NM   : constant String := To_String (R.Name);
            CN   : constant String := C_Name (NM);
            TN   : constant String := C_Type_Name (NM);
            Info : constant Rule_Info := Infos (Idx);
            Gap  : constant String :=
              (if R.Whitespace /= Null_Unbounded_String then "1" else "0");
         begin
            case Info.Kind is
               when Struct =>
                  Append (Buf, "static void wr_" & CN & " (hbnf_w *w, const "
                    & TN & " *n) {");
                  Append (Buf, LF);
                  Append (Buf, "    (void)n;");
                  Append (Buf, LF);
                  Append (Buf, "    hbnf_wopen (w, """ & NM & """);");
                  Append (Buf, LF);
                  if Natural (R.Pattern.Length) = 1
                    and then R.Pattern (1).Kind = Group
                  then
                     Branches (Idx, R.Pattern (1).Items, "n->", Gap, Buf,
                               "    ", String_Vectors.Empty_Vector);
                  else
                     Branches (Idx, R.Pattern, "n->", Gap, Buf, "    ",
                               Rule_Alts (R, False));
                  end if;
                  Append (Buf, "    hbnf_wclose (w, """ & NM & """);");
                  Append (Buf, LF);
                  Append (Buf, "}");
                  Append (Buf, LF);
               when List =>
                  Append (Buf, "static void wr_" & CN & " (hbnf_w *w, const "
                    & "struct " & Pfx & CN & "_list *head) {");
                  Append (Buf, LF);
                  Append (Buf, "    const " & TN & " *n;");
                  Append (Buf, LF);
                  Append (Buf, "    hbnf_wopen (w, """ & NM & """);");
                  Append (Buf, LF);
                  if R.Left_Bases > 0 then
                     Append (Buf, "    int first_ = 1;");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "    " & L_Foreach ("n", "head", Rule => NM) & " {");
                  Append (Buf, LF);
                  if R.Left_Bases > 0 then
                     --  The first node is a base, each later one a tail.
                     Append (Buf, "        if (first_) {");
                     Append (Buf, LF);
                     Branches (Idx, Base_Branches (R), "n->", Gap, Buf,
                               "            ",
                               Alt_Idents (CN, Base_Branches (R)));
                     Append (Buf, "        } else {");
                     Append (Buf, LF);
                     Branches (Idx, Tail_Branches (R), "n->", Gap, Buf,
                               "            ",
                               Alt_Idents
                                 (CN, Tail_Branches (R),
                                  Natural (Alt_Labels
                                    (Base_Branches (R)).Length) + 1));
                     Append (Buf, "        }");
                     Append (Buf, LF);
                     Append (Buf, "        first_ = 0;");
                     Append (Buf, LF);
                  elsif R.Pattern (1).Kind = Group then
                     Branches (Idx, R.Pattern (1).Items, "n->", Gap, Buf,
                               "        ", Rule_Alts (R, True));
                  elsif Info.Elem_Name /= Null_Unbounded_String then
                     declare
                        One : Element_Vectors.Vector;
                        E   : constant Element_Access :=
                          new HBNF_Grammar.Element'(R.Pattern (1).all);
                     begin
                        E.Min := 1;
                        E.Max := 1;
                        One.Append (E);
                        Elements (Idx, One, 1, 1, "n->", Gap, Buf, "        ");
                     end;
                  else
                     Append (Buf, "        hbnf_wtok (w, " & Gap
                       & ", n->value, NULL);");
                     Append (Buf, LF);
                  end if;
                  if Idx = 1 and then HBNF_Grammar.Statements then
                     --  A statement ends at a newline.
                     Append (Buf, "        hbnf_wlit (w, 0, ""\n"", 1);");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, "    }");
                  Append (Buf, LF);
                  Append (Buf, "    hbnf_wclose (w, """ & NM & """);");
                  Append (Buf, LF);
                  Append (Buf, "}");
                  Append (Buf, LF);
               when Enum =>
                  declare
                     Names : constant String_Vectors.Vector :=
                       Enum_Names (Info.Literals);
                  begin
                     Append (Buf, "static void wr_" & CN & " (hbnf_w *w, "
                       & TN & " v) {");
                     Append (Buf, LF);
                     Append (Buf, "    switch (v) {");
                     Append (Buf, LF);
                     for I in 1 .. Natural (Info.Literals.Length) loop
                        Append (Buf, "    case " & C_Ident (NM) & "_"
                          & To_String (Names (I)) & ": hbnf_wlit (w, " & Gap
                          & ", """ & C_Escape (To_String (Info.Literals (I)))
                          & """, "
                          & Img (To_String (Info.Literals (I))'Length)
                          & "); break;");
                        Append (Buf, LF);
                     end loop;
                     Append (Buf, "    default: break;");
                     Append (Buf, LF);
                     Append (Buf, "    }");
                     Append (Buf, LF);
                     Append (Buf, "}");
                     Append (Buf, LF);
                  end;
               when Scalar =>
                  null;
            end case;
         end Define;

      begin
         Append (Buf, "/* ---- write (the tree as text, canonical) ---- */");
         Append (Buf, LF);
         Append (Buf, "#include <stdio.h>" & LF & "#include <ctype.h>" & LF
           & "#include <string.h>");
         Append (Buf, LF);
         Append (Buf,
           "typedef size_t (*hbnf_wscan_fn) (const char *, size_t, size_t);" & LF
           & "typedef struct { char *buf; size_t cap, len; int last; "
           & "const char *bad; int trace;" & LF
           & "    char *ptxt; size_t plen, pcap; hbnf_wscan_fn pscan; } hbnf_w;"
           & LF
           & "static const char *hbnf_write_error;" & LF
           & "/* Set to 1 to write the tree's shape too: (rule ...) around each"
           & " node.  The tests compare it. */" & LF
           & "static int hbnf_write_trace;" & LF
           & "/* A pretty-printer's say (corpus/algol60/pp.c): called with ev 0 and "
           & "the text before each token or literal is written (it returns what "
           & "goes before it, NULL for the writer's own spacing), then with ev 3 "
           & "(it returns the text to write instead, NULL: as it is), and with "
           & "ev 1 and 2 on entering and leaving a node, with its rule's name. */" & LF
           & "typedef const char *(*hbnf_wlayout_fn) (void *ctx, int ev, "
           & "const char *s);" & LF
           & "static hbnf_wlayout_fn hbnf_write_layout;" & LF
           & "static void *hbnf_write_layout_ctx;" & LF
           & "static void hbnf_wbad (hbnf_w *w, const char *why) "
           & "{ if (!w->bad) w->bad = why; }" & LF
           & "static void hbnf_wput (hbnf_w *w, const char *s, size_t n) {" & LF
           & "    size_t i;" & LF
           & "    for (i = 0; i < n; i++)" & LF
           & "        if (w->buf && w->len + i + 1 < w->cap) "
           & "w->buf[w->len + i] = s[i];" & LF
           & "    w->len += n;" & LF
           & "    if (n) w->last = (unsigned char)s[n - 1];" & LF
           & "}" & LF
           & "static void hbnf_wopen (hbnf_w *w, const char *n) {" & LF
           & "    if (hbnf_write_layout) hbnf_write_layout (hbnf_write_layout_ctx, 1, n);" & LF
           & "    if (w->trace) { hbnf_wput (w, ""("", 1); hbnf_wput (w, n, "
           & "strlen (n)); hbnf_wput (w, "" "", 1); }" & LF
           & "}" & LF
           & "static void hbnf_wclose (hbnf_w *w, const char *n) {" & LF
           & "    if (hbnf_write_layout) hbnf_write_layout (hbnf_write_layout_ctx, 2, n);" & LF
           & "    if (w->trace) hbnf_wput (w, "")"", 1);" & LF
           & "}" & LF
           & "static int hbnf_wdelim (int c) "
           & "{ return c && strchr (""()[],;"", c) != NULL; }" & LF
           & "/* Would the item just written, with sep and s after it, still end"
           & " where it did when the grammar's own scanner reads it? */" & LF
           & "static int hbnf_wfits (hbnf_w *w, const char *sep, const char *s)"
           & " {" & LF
           & "    size_t b = strlen (sep), c = strlen (s);" & LF
           & "    char *t = (char *)malloc (w->plen + b + c + 1);" & LF
           & "    int ok;" & LF
           & "    if (!t) return 0;" & LF
           & "    memcpy (t, w->ptxt, w->plen);  memcpy (t + w->plen, sep, b);" & LF
           & "    memcpy (t + w->plen + b, s, c);  t[w->plen + b + c] = 0;" & LF
           & "    ok = w->pscan (t, 0, w->plen + b + c) == w->plen;" & LF
           & "    free (t);" & LF
           & "    return ok;" & LF
           & "}" & LF
           & "/* What goes between the last item and s: nothing, a blank or a"
           & " newline, the first that keeps the last item from reading on"
           & " into s. */" & LF
           & "static void hbnf_wsep (hbnf_w *w, int gap, const char *s) {" & LF
           & "    int a = w->last, b = (unsigned char)s[0];" & LF
           & "    const char *pref = """";" & LF
           & "    if (!w->len || !b) return;" & LF
           & "    if (gap && a > ' ' && b > ' ' && !hbnf_wdelim (a)" & LF
           & "        && !hbnf_wdelim (b)) pref = "" "";" & LF
           & "    if (w->pscan && a > ' ') {" & LF
           & "        const char *c[3];  int i;" & LF
           & "        c[0] = pref;  c[1] = "" "";  c[2] = ""\n"";" & LF
           & "        for (i = 0; i < (gap ? 3 : 1); i++)" & LF
           & "            if (hbnf_wfits (w, c[i], s)) {" & LF
           & "                hbnf_wput (w, c[i], strlen (c[i]));" & LF
           & "                return;" & LF
           & "            }" & LF
           & "        hbnf_wbad (w, ""two items cannot be written apart: the"
           & " first would read on into the second"");" & LF
           & "        return;" & LF
           & "    }" & LF
           & "    hbnf_wput (w, pref, strlen (pref));" & LF
           & "}" & LF
           & "static void hbnf_wtext (hbnf_w *w, int gap, const char *s, "
           & "size_t n, hbnf_wscan_fn scan) {" & LF
           & "    const char *sep = n && hbnf_write_layout"
           & " ? hbnf_write_layout (hbnf_write_layout_ctx, 0, s) : NULL;" & LF
           & "    if (sep) hbnf_wput (w, sep, strlen (sep));" & LF
           & "    else hbnf_wsep (w, gap, s);" & LF
           & "    if (n && hbnf_write_layout) {" & LF
           & "        const char *r = hbnf_write_layout (hbnf_write_layout_ctx, 3, s);" & LF
           & "        if (r) { s = r; n = strlen (r); }" & LF
           & "    }" & LF
           & "    hbnf_wput (w, s, n);" & LF
           & "    w->pscan = scan;" & LF
           & "    if (scan) {" & LF
           & "        if (n + 1 > w->pcap) {" & LF
           & "            w->pcap = n + 64;" & LF
           & "            w->ptxt = (char *)realloc (w->ptxt, w->pcap);" & LF
           & "            if (!w->ptxt) { w->pscan = NULL; return; }" & LF
           & "        }" & LF
           & "        memcpy (w->ptxt, s, n);  w->plen = n;" & LF
           & "    }" & LF
           & "}" & LF
           & "static void hbnf_wlit (hbnf_w *w, int gap, const char *s, "
           & "size_t n) { hbnf_wtext (w, gap, s, n, NULL); }" & LF
           & "static void hbnf_wtok (hbnf_w *w, int gap, const char *s, "
           & "hbnf_wscan_fn scan) { if (!s) s = """"; "
           & "hbnf_wtext (w, gap, s, strlen (s), scan); }" & LF
           & "static void hbnf_wstr (hbnf_w *w, int gap, const char *s, "
           & "hbnf_wscan_fn scan) {" & LF
           & "    size_t n = 2, k = 0;  const char *q;  char *t;" & LF
           & "    for (q = s; q && *q; q++) n += (*q == '""' || *q == '\\') "
           & "? 2 : 1;" & LF
           & "    t = (char *)malloc (n + 1);" & LF
           & "    if (!t) { hbnf_wbad (w, ""out of memory""); return; }" & LF
           & "    t[k++] = '""';" & LF
           & "    for (q = s; q && *q; q++) {" & LF
           & "        if (*q == '""' || *q == '\\') t[k++] = '\\';" & LF
           & "        t[k++] = *q;" & LF
           & "    }" & LF
           & "    t[k++] = '""';  t[k] = 0;" & LF
           & "    hbnf_wtext (w, gap, t, k, scan);" & LF
           & "    free (t);" & LF
           & "}" & LF
           & "static void hbnf_wnum (hbnf_w *w, int gap, long long v, "
           & "hbnf_wscan_fn scan) { char t[32]; snprintf (t, sizeof t, ""%lld"","
           & " v); hbnf_wtok (w, gap, t, scan); }" & LF
           & "static void hbnf_wunum (hbnf_w *w, int gap, unsigned long long v,"
           & " hbnf_wscan_fn scan) { char t[32]; snprintf (t, sizeof t, "
           & """%llu"", v); hbnf_wtok (w, gap, t, scan); }" & LF);
         for I in 1 .. N loop
            case Infos (I).Kind is
               when Struct =>
                  Append (Buf, "static void wr_"
                    & C_Name (To_String (Rules (I).Name)) & " (hbnf_w *w, "
                    & "const " & C_Type_Name (To_String (Rules (I).Name))
                    & " *n);" & LF);
               when List =>
                  Append (Buf, "static void wr_"
                    & C_Name (To_String (Rules (I).Name)) & " (hbnf_w *w, "
                    & "const struct " & Pfx
                    & C_Name (To_String (Rules (I).Name))
                    & "_list *head);" & LF);
               when Enum =>
                  Append (Buf, "static void wr_"
                    & C_Name (To_String (Rules (I).Name)) & " (hbnf_w *w, "
                    & C_Type_Name (To_String (Rules (I).Name)) & " v);" & LF);
               when Scalar =>
                  null;
            end case;
         end loop;
         declare
            Defs : U;
         begin
            for I in 1 .. N loop
               Define (I, Defs);
            end loop;
            for Fn of Scans loop
               Append (Buf, "static size_t " & To_String (Fn)
                 & " (const char *, size_t, size_t);" & LF);
            end loop;
            Append (Buf, Defs);
         end;
         declare
            Root : constant String := Root_Type (Rules);
            RN   : constant String := C_Name (To_String (Rules (1).Name));
            --  A root that is only another rule (`json = value`) is written by that rule.
            Tgt  : constant String :=
              Alias_Target (Rules, To_String (Rules (1).Name));
            TJ   : constant Natural := Find (Tgt);
            WN   : constant String := (if TJ /= 0 then C_Name (Tgt) else RN);
         begin
            if Infos (1).Kind in Struct | List
              or else (TJ /= 0 and then Infos (TJ).Kind in Struct | List)
            then
               Append (Buf,
                 "/* The tree as text: its length, with the text in buf up to"
                 & " cap - 1 bytes and a NUL (as snprintf), or (size_t)-1 and"
                 & " hbnf_write_error when a node cannot be written. */" & LF
                 & "static size_t write_" & RN & " (const " & Root
                 & " *root, char *buf, size_t cap) {" & LF
                 & "    hbnf_w w;" & LF
                 & "    memset (&w, 0, sizeof w);" & LF
                 & "    w.buf = buf;  w.cap = cap;  w.trace = hbnf_write_trace;"
                 & LF
                 & "    wr_" & WN & " (&w, root);" & LF
                 & "    free (w.ptxt);" & LF
                 & "    if (buf && cap) buf[w.len < cap ? w.len : cap - 1] = 0;"
                 & LF
                 & "    hbnf_write_error = w.bad;" & LF
                 & "    return w.bad ? (size_t)-1 : w.len;" & LF
                 & "}" & LF);
            end if;
         end;
      end Emit_Writer;


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
         --  string leaf, leave a numeric/enum leaf alone.  An ordinary child
         --  takes its full free_<child>, which never touches the arena; a
         --  back-edge child takes the _fields variant, for the reason below.
         procedure Free_Field (Idx : Natural; Name : String;
                               Buf : in out U; Ind : String) is
            F : constant String := C_Field (Name);
            T : constant String := C_Name (Alias_Target (Rules, Name));
            --  A back-edge struct field is a pointer into the arena: the
            --  walker follows it rather than addressing it.  Its children
            --  are released with the _fields variant, never the public
            --  free_<T>: a back edge can point straight back at the root
            --  rule, whose free_ calls free_arena(), and the backtracking
            --  reset calls this mid-parse -- that would release the tree
            --  the parse is still building.  The pointee itself is arena
            --  memory, released by free_arena() at the root.
            Back : constant Boolean :=
              Ref_Kind (Name) = Struct and then Is_Back (Idx, Name);
         begin
            case Ref_Kind (Name) is
               when Struct | List =>
                  --  A list that is the root is freed by its nodes alone here:
                  --  the public free_ of it releases the arena too, and the
                  --  backtracking reset calls this in the middle of a parse.
                  Append (Buf, Ind & "free_" & T
                    & (if Back then "_fields(n->" & F & ");"
                       elsif Ref_Kind (Name) = List and then Find (T) = 1
                       then "_nodes(&n->" & F & ");"
                       --  a struct that is the root, used inside another rule (the shell's
                       --  `$( program )`): its public free_ would release the arena in the
                       --  middle of a parse
                       elsif Ref_Kind (Name) = Struct and then Find (T) = 1
                       then "_fields(&n->" & F & ");"
                       else "(&n->" & F & ");"));
                  Append (Buf, LF);
                  --  The pointee is released with the arena, not here, so the
                  --  pointer must not outlive the walk: a failed branch is
                  --  freed by the backtracking reset, and the field it set
                  --  would otherwise read as set in the branch that matched.
                  if Back then
                     Append (Buf, Ind & "n->" & F & " = NULL;");
                     Append (Buf, LF);
                  end if;
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
            if Info.Kind = Struct and then Is_Choice (Rules (Idx)) then
               Append (Buf, "    switch (n->_alt) {" & LF);
               declare
                  K : Natural := 0;
               begin
                  for M of Info.Members loop
                     K := K + 1;
                     Append (Buf, "    case " & Img (K) & ":" & LF);
                     Free_Field (Idx, To_String (M.Name), Buf, "        ");
                     Append (Buf, "        break;" & LF);
                  end loop;
               end;
               Append (Buf, "    default: break;" & LF & "    }" & LF);
            elsif Info.Kind = Struct then
               for M of Info.Members loop
                  Free_Field (Idx, To_String (M.Name), Buf, "    ");
               end loop;
            elsif Info.Elem_Members.Is_Empty then
               if Info.Elem_Name /= Null_Unbounded_String then
                  Free_Field (Idx, To_String (Info.Elem_Name), Buf, "    ");
               end if;
            else
               for M of Info.Elem_Members loop
                  Free_Field (Idx, To_String (M.Name), Buf, "    ");
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
               Append (Buf, "static void free_" & CN & (if Idx = 1 then "_nodes" else "")
                 & "(struct " & Pfx & CN & "_list *head) {");
               Append (Buf, LF);
               Append (Buf, "    " & TN & " *n = " & L_First ("head", Rule => To_String (Rules (Idx).Name)) & ", *next;");
               Append (Buf, LF);
               Append (Buf, "    while (n) {");
               Append (Buf, LF);
               Append (Buf, "        next = " & L_Next ("n", Rule => To_String (Rules (Idx).Name)) & ";");
               Append (Buf, LF);
               Append (Buf, "        free_" & CN & "_fields(n);");
               Append (Buf, LF);
               Append (Buf, "        n = next;");
               Append (Buf, LF);
               Append (Buf, "    }");
               Append (Buf, LF);
               Append (Buf, "    " & L_Init ("head", Rule => To_String (Rules (Idx).Name)));
               Append (Buf, LF);
            end if;
            if Idx = 1 and then Info.Kind = Struct then
               Append (Buf, "    free_arena();");
               Append (Buf, LF);
            end if;
            Append (Buf, "}");
            Append (Buf, LF);
            if Idx = 1 and then Info.Kind = List then
               Append (Buf, "static void free_" & CN & "(struct " & Pfx & CN
                 & "_list *head) {");
               Append (Buf, LF);
               Append (Buf, "    free_" & CN & "_nodes(head);");
               Append (Buf, LF);
               Append (Buf, "    free_arena();");
               Append (Buf, LF);
               Append (Buf, "}");
               Append (Buf, LF);
            end if;
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
                     if I = 1 then
                        Append (Buf, "static void free_" & CN & "_nodes(struct "
                          & Pfx & CN & "_list *head);");
                        Append (Buf, LF);
                     end if;
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
         --  Does a rule hold a list, itself or through the structs it holds?
         --  Each rule is looked at once, so a grammar that refers back to
         --  itself (an expression through its parentheses) costs a walk of
         --  the graph, not a walk of every path through it.
         function Holds_List (Name : String) return Boolean is
            Seen : array (1 .. N) of Boolean := [others => False];

            function Visit (Nm : String) return Boolean is
               J : constant Natural := Find (Alias_Target (Rules, Nm));
            begin
               if J = 0 or else Seen (J) then
                  return False;
               end if;
               Seen (J) := True;
               case Infos (J).Kind is
                  when List =>
                     return True;
                  when Struct =>
                     declare
                        Info : constant Rule_Info := Infos (J);
                     begin
                        for M of Info.Members loop
                           if Visit (To_String (M.Name)) then
                              return True;
                           end if;
                        end loop;
                     end;
                     return False;
                  when others =>
                     return False;
               end case;
            end Visit;
         begin
            return Visit (Name);
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

         procedure Field (Idx : Positive; Name : String; Buf : in out U) is
         begin
            if Ref_Kind (Name) in Struct | List and then Holds_List (Name) then
               if Ref_Kind (Name) = Struct and then Is_Back (Idx, Name) then
                  --  A field that breaks a cycle is a pointer, and not always
                  --  set: the alternative that holds it may not have matched.
                  Append (Buf, "    if (n->" & C_Field (Name) & ") relink_"
                    & C_Name (Alias_Target (Rules, Name)) & "(n->"
                    & C_Field (Name) & ");");
               else
                  Append (Buf, "    relink_" & C_Name (Alias_Target (Rules, Name))
                    & "(&n->" & C_Field (Name) & ");");
               end if;
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
                     if Info.Kind = Struct and then Is_Choice (Rules (I)) then
                        Append (Buf, "    switch (n->_alt) {" & LF);
                        declare
                           K : Natural := 0;
                        begin
                           for M of Info.Members loop
                              K := K + 1;
                              Append (Buf, "    case " & Img (K) & ":" & LF);
                              Field (I, To_String (M.Name), Buf);
                              Append (Buf, "        break;" & LF);
                           end loop;
                        end;
                        Append (Buf, "    default: break;" & LF & "    }" & LF);
                     elsif Info.Kind = Struct then
                        for M of Info.Members loop
                           Field (I, To_String (M.Name), Buf);
                        end loop;
                     elsif Info.Elem_Members.Is_Empty then
                        if Info.Elem_Name /= Null_Unbounded_String then
                           Field (I, To_String (Info.Elem_Name), Buf);
                        end if;
                     else
                        for M of Info.Elem_Members loop
                           Field (I, To_String (M.Name), Buf);
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
                     Append (Buf, "    " & L_Relink ("head", Rule => To_String (Rules (I).Name)));
                     Append (Buf, LF);
                     if Elem_Holds_List (Info) then
                        Append (Buf, "    " & TN & " *n;");
                        Append (Buf, LF);
                        Append (Buf, "    " & L_Foreach ("n", "head", Rule => To_String (Rules (I).Name)) & " relink_"
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
        Hosted_Actions
        or else (for some I in 1 .. N =>
                   Rules (I).Action_Code /= Null_Unbounded_String);
   begin
      for I in 1 .. N loop
         Infos.Append (Analyze (I));
      end loop;

      Append (Res, "/* generated by hbnf -- do not edit */");
      Append (Res, LF);
      if Preamble ("C") /= "" then
         Append (Res, Preamble ("C"));
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
      if Views_On then
         Append (Res, "/* A string in the tree: a pointer and a length into the input, packed in 8 bytes so a");
         Append (Res, LF);
         Append (Res, "   field costs what a pointer does.  The tree borrows the text, which must outlive it.");
         Append (Res, LF);
         Append (Res, "   hbnf_sp(v) is the text and hbnf_sn(v) its length; a string of 65535 bytes or more is");
         Append (Res, LF);
         Append (Res, "   copied, NUL-terminated, and has the length 0xFFFF in the word. */");
         Append (Res, LF);
         Append (Res, "typedef uint64_t hbnf_str;   /* the address in the low 48 bits, the length in the high 16 */");
         Append (Res, LF);
      end if;
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
      Append (Res, "   The tree's string leaves live here; free_arena walks the chain once, and");
      Append (Res, LF);
      Append (Res, "   keeps one default-size chunk for the next tree: a statement-at-a-time parse");
      Append (Res, LF);
      Append (Res, "   frees its tree after each statement, and a malloc/free of a 64 KiB chunk");
      Append (Res, LF);
      Append (Res, "   per statement costs more than the parse on libcs that return it to the");
      Append (Res, LF);
      Append (Res, "   system (musl: 14 times, on a 100,000-line ntpd.conf). */");
      Append (Res, LF);
      Append (Res, "enum { HBNF_ARENA_CHUNK = 1 << 16 };");
      Append (Res, LF);
      Append (Res, "typedef struct hbnf_chunk hbnf_chunk;");
      Append (Res, LF);
      Append (Res, "struct hbnf_chunk { hbnf_chunk *next; size_t used, cap; void *map; size_t map_len; char data[]; };");
      Append (Res, LF);
      Append (Res, "static hbnf_chunk *hbnf_arena;");
      Append (Res, LF);
      Append (Res, "static hbnf_chunk *hbnf_spare;");
      Append (Res, LF);
      Append (Res, "/* A chunk past the first is 1 MiB and doubles up to 8 MiB.  On Linux those are mapped, not");
      Append (Res, LF);
      Append (Res, "   malloc'd: the kernel hands out zeroed pages, so the chunk needs no clearing, and it starts on a");
      Append (Res, LF);
      Append (Res, "   2 MiB boundary and asks for huge pages, so a tree of tens of megabytes costs a few dozen page");
      Append (Res, LF);
      Append (Res, "   faults and not one for every 4 KiB. */");
      Append (Res, LF);
      Append (Res, "#if defined(__linux__)");
      Append (Res, LF);
      Append (Res, "#include <sys/mman.h>");
      Append (Res, LF);
      Append (Res, "static hbnf_chunk *hbnf_map_chunk(size_t cap) {");
      Append (Res, LF);
      Append (Res, "    const size_t huge = (size_t)2 << 20;");
      Append (Res, LF);
      Append (Res, "    size_t len = (sizeof(hbnf_chunk) + cap + huge - 1) & ~(huge - 1);");
      Append (Res, LF);
      Append (Res, "    char *m = (char *)mmap(NULL, len + huge, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);");
      Append (Res, LF);
      Append (Res, "    if (m == (char *)MAP_FAILED) return NULL;");
      Append (Res, LF);
      Append (Res, "    hbnf_chunk *c = (hbnf_chunk *)(((uintptr_t)m + huge - 1) & ~(uintptr_t)(huge - 1));");
      Append (Res, LF);
      Append (Res, "#ifdef MADV_HUGEPAGE");
      Append (Res, LF);
      Append (Res, "    madvise(c, len, MADV_HUGEPAGE);");
      Append (Res, LF);
      Append (Res, "#endif");
      Append (Res, LF);
      Append (Res, "    c->map = m; c->map_len = len + huge;");
      Append (Res, LF);
      Append (Res, "    c->cap = len - sizeof(hbnf_chunk);");
      Append (Res, LF);
      Append (Res, "    return c;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, "#endif");
      Append (Res, LF);
      Append (Res, "/* Bump n zeroed bytes out of the arena, 8-byte aligned, never split");
      Append (Res, LF);
      Append (Res, "   across chunks. */");
      Append (Res, LF);
      Append (Res, "static void *hbnf_alloc_slow(size_t n) {");
      Append (Res, LF);
      Append (Res, "    size_t cap = n > (size_t)HBNF_ARENA_CHUNK ? n : (size_t)HBNF_ARENA_CHUNK;");
      Append (Res, LF);
      Append (Res, "    hbnf_chunk *c = NULL;");
      Append (Res, LF);
      Append (Res, "    if (hbnf_arena) {");
      Append (Res, LF);
      Append (Res, "        size_t grow = hbnf_arena->cap >= ((size_t)1 << 20) ? hbnf_arena->cap * 2 : ((size_t)1 << 20);");
      Append (Res, LF);
      Append (Res, "        if (grow > ((size_t)8 << 20)) grow = (size_t)8 << 20;");
      Append (Res, LF);
      Append (Res, "        if (grow > cap) cap = grow;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "#if defined(__linux__)");
      Append (Res, LF);
      Append (Res, "    if (cap >= ((size_t)1 << 20)) c = hbnf_map_chunk(cap);");
      Append (Res, LF);
      Append (Res, "#endif");
      Append (Res, LF);
      Append (Res, "    if (!c) {");
      Append (Res, LF);
      Append (Res, "        c = cap == (size_t)HBNF_ARENA_CHUNK && hbnf_spare");
      Append (Res, LF);
      Append (Res, "            ? hbnf_spare : (hbnf_chunk *)malloc(sizeof *c + cap);");
      Append (Res, LF);
      Append (Res, "        if (!c) hbnf_oom();");
      Append (Res, LF);
      Append (Res, "        if (c == hbnf_spare) hbnf_spare = NULL;");
      Append (Res, LF);
      Append (Res, "        memset(c->data, 0, cap);   /* a chunk is cleared once, as it is taken: no clearing per allocation */");
      Append (Res, LF);
      Append (Res, "        c->map = NULL; c->map_len = 0;");
      Append (Res, LF);
      Append (Res, "    } else {");
      Append (Res, LF);
      Append (Res, "        cap = c->cap;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    c->next = hbnf_arena; c->used = 0; c->cap = cap;");
      Append (Res, LF);
      Append (Res, "    hbnf_arena = c;");
      Append (Res, LF);
      Append (Res, "    void *p = c->data;");
      Append (Res, LF);
      Append (Res, "    c->used = n;");
      Append (Res, LF);
      Append (Res, "    return p;");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, "static inline void *hbnf_alloc(size_t n) {");
      Append (Res, LF);
      Append (Res, "    n = (n + 7u) & ~(size_t)7u;");
      Append (Res, LF);
      Append (Res, "    hbnf_chunk *c = hbnf_arena;");
      Append (Res, LF);
      Append (Res, "    if (__builtin_expect(c && c->used + n <= c->cap, 1)) {");
      Append (Res, LF);
      Append (Res, "        void *p = c->data + c->used;");
      Append (Res, LF);
      Append (Res, "        c->used += n;");
      Append (Res, LF);
      Append (Res, "        return p;");
      Append (Res, LF);
      Append (Res, "    }");
      Append (Res, LF);
      Append (Res, "    return hbnf_alloc_slow(n);");
      Append (Res, LF);
      Append (Res, "}");
      Append (Res, LF);
      Append (Res, "/* Copy a (non-NUL-terminated) token slice into the arena, NUL-terminated,");
      Append (Res, LF);
      Append (Res, "   and return it.  No per-string malloc. */");
      Append (Res, LF);
      Append (Res, "static const char *hbnf_str_append(const char *s, size_t n) {");
      Append (Res, LF);
      Append (Res, "    /* the bytes are written over at once: no need to clear them first */");
      Append (Res, LF);
      Append (Res, "    size_t m = (n + 1 + 7u) & ~(size_t)7u;");
      Append (Res, LF);
      Append (Res, "    char *p;");
      Append (Res, LF);
      Append (Res, "    if (!hbnf_arena || hbnf_arena->used + m > hbnf_arena->cap) p = (char *)hbnf_alloc(n + 1);");
      Append (Res, LF);
      Append (Res, "    else { p = hbnf_arena->data + hbnf_arena->used; hbnf_arena->used += m; }");
      Append (Res, LF);
      Append (Res, "    if (n) memcpy(p, s, n);");
      Append (Res, LF);
      Append (Res, "    p[n] = 0;");
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
      if Views_On then
         Append (Res, "static inline const char *hbnf_sp(hbnf_str v) { return (const char *)(uintptr_t)(v & 0xFFFFFFFFFFFFull); }" & LF
           & "static inline size_t hbnf_sn(hbnf_str v) { size_t n = (size_t)(v >> 48); return n == 0xFFFF ? strlen(hbnf_sp(v)) : n; }" & LF
           & "static inline hbnf_str hbnf_mkstr(const char *s, size_t n) {" & LF
           & "    if (n >= 0xFFFF) { s = hbnf_str_append(s, n); n = 0xFFFF; }" & LF
           & "    return (hbnf_str)(uintptr_t)s | ((hbnf_str)n << 48);" & LF
           & "}" & LF);
         Append (Res, "/* A quoted string s[0..n) as a view of its content: the text itself unless a" & LF
           & "   backslash has to be undone, the one case that is copied. */" & LF
           & "__attribute__((unused))" & LF
           & "static hbnf_str hbnf_str_value_v(const char *s, size_t n) {" & LF
           & "    size_t i, m;" & LF
           & "    const char *r;" & LF
           & "    for (i = 1; i + 1 < n; i++) if (s[i] == '\\') break;" & LF
           & "    if (i + 1 >= n) return hbnf_mkstr(s + 1, n >= 2 ? n - 2 : 0);" & LF
           & "    hbnf_scratch_len = 0;" & LF
           & "    for (i = 1; i + 1 < n; i++) {" & LF
           & "        if (s[i] == '\\') {" & LF
           & "            i++;" & LF
           & "            if (s[i] == '\n') continue;   /* backslash-newline: dropped */" & LF
           & "        }" & LF
           & "        hbnf_str_put(s[i]);" & LF
           & "    }" & LF
           & "    m = hbnf_scratch_len;" & LF
           & "    r = hbnf_str_append(hbnf_scratch, m);" & LF
           & "    hbnf_scratch_len = 0;" & LF
           & "    return hbnf_mkstr(r, m);" & LF
           & "}" & LF);
      elsif HBNF_Grammar.List_Override ("key") /= "" or else HBNF_Grammar.Layout = "tape" then
         --  A layout reads a string field as pointer and length (rb orders a list by one, the tape
         --  writes the text of a token); without the views a string is a NUL-terminated pointer, and
         --  hbnf_sp and hbnf_sn read both alike.
         Append (Res, "__attribute__((unused))" & LF
           & "static inline const char *hbnf_sp(const char *v) { return v; }" & LF
           & "__attribute__((unused))" & LF
           & "static inline size_t hbnf_sn(const char *v) { return strlen(v); }" & LF);
      end if;
      Append (Res, "static void free_arena(void) {");
      Append (Res, LF);
      Append (Res, "    while (hbnf_arena) {");
      Append (Res, LF);
      Append (Res, "        hbnf_chunk *n = hbnf_arena->next;");
      Append (Res, LF);
      Append (Res, "#if defined(__linux__)");
      Append (Res, LF);
      Append (Res, "        if (hbnf_arena->map) munmap(hbnf_arena->map, hbnf_arena->map_len);");
      Append (Res, LF);
      Append (Res, "        else");
      Append (Res, LF);
      Append (Res, "#endif");
      Append (Res, LF);
      Append (Res, "        if (!hbnf_spare && hbnf_arena->cap == (size_t)HBNF_ARENA_CHUNK)");
      Append (Res, LF);
      Append (Res, "            hbnf_spare = hbnf_arena;");
      Append (Res, LF);
      Append (Res, "        else");
      Append (Res, LF);
      Append (Res, "            free(hbnf_arena);");
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

      --  The bit rules' record types, declared ahead, so a text rule may be
      --  an alias of one (`doc = segwit`).
      if Hosted_Code /= Null_Unbounded_String then
         for R of HBNF_Grammar.Wire_Rules loop
            if not (for all E of R.Pattern =>
                      E.Kind = HBNF_Grammar.Alt
                      or else (E.Kind = HBNF_Grammar.Bit_Field
                               and then HBNF_Wire."=" (E.F_Kind, HBNF_Wire.S_Const)))
            then
               Append (Res, "typedef struct " & Pfx
                 & C_Tag (To_String (R.Name)) & " "
                 & C_Type_Name (To_String (R.Name)) & ";");
               Append (Res, LF);
            end if;
         end loop;
      end if;

      --  Forward-declare every struct and list node type; a list rule also
      --  gets its list head type.
      for I in 1 .. N loop
         if Is_By_Value (Infos (I)) or else Infos (I).Kind = List then
            Append (Res, "typedef struct " & Pfx
              & C_Tag (To_String (Rules (I).Name))
              & " " & C_Type_Name (To_String (Rules (I).Name)) & ";");
            Append (Res, LF);
            if Infos (I).Kind = List then
               Append (Res, L_Head
                 (Pfx & C_Name (To_String (Rules (I).Name)) & "_list",
                  Pfx & C_Tag (To_String (Rules (I).Name)),
                  Rule => To_String (Rules (I).Name)) & ";");
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

      --  The fields to emit indirectly, one per by-value cycle: the detector
      --  in HBNF_Compilable picks one field per cycle, and the types, free,
      --  walkers and parse code all ask Is_Back for it.  A cycle with no
      --  field to break (an all-alias cycle) is still refused, by Back_Edges
      --  itself.  This runs after the leaf sort, which is what keeps the
      --  alias chase inside Back_Edges_C finite.
      Backs := Back_Edges_C (Rules);

      --  The bit rules' own types (a text rule may hold one by value).
      Append (Res, Hosted_Types);

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
                 "a rule's value cannot contain itself: the tree types are structs "
                 & "by value, so this one would be infinitely sized.  Routing "
                 & "the recursion through a list does not help (a list node "
                 & "holds its element by value too); RFCPLAN.md step 9 adds "
                 & "the pointer that breaks the cycle";
            end if;
         end;
      end loop;

      --  What a container needs once for each list type, written after the structs are whole.
      if HBNF_Grammar.List_Override ("generate") /= "" then
         for I in 1 .. N loop
            if Infos (I).Kind = List then
               Append (Res, Subst (HBNF_Grammar.List_Override ("generate"),
                                   List_Name_Of (To_String (Rules (I).Name)),
                                   List_Elem_Of (To_String (Rules (I).Name)), "", "", ""));
               Append (Res, LF);
            end if;
         end loop;
      end if;

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

      if Walkers and then Ast_On then
         Emit_Ast (Res);
         Append (Res, LF);
      end if;

      if Writer_On then
         Emit_Writer (Res);
         Append (Res, LF);
      end if;

      return To_String (Res);
   end Emit;

   --  =====================================================================
   --  Parser emission: a self-contained recursive-descent parser that
   --  consumes a token stream and allocates/populates the structs above.
   --  =====================================================================

   --  The scanner a core scalar runs: `word`/`atom`/`bool`/`flag` read the
   --  `word` rule, `int`/`uN`/`iN` the `int` rule, `str` the `str` rule.  The
   --  core rule is a hand-written jet (`jet_*`) when the grammar does not
   --  define it (the injected built-in), else a char rule (`scan_*`).
   function Scalar_Scan_Fn (Rules : Rule_Vectors.Vector; Name : String)
      return String
   is
      Core : constant String :=
        (if Name = "str" then "str"
         elsif Name = "int" then "int"
         elsif Name'Length >= 2
           and then (Name (Name'First) = 'u' or else Name (Name'First) = 'i')
           and then (for all K in Name'First + 1 .. Name'Last
                     => Name (K) in '0' .. '9')
         then "int"
         else "word");
      J : constant Natural := Find (Rules, Core);
   begin
      if J /= 0 and then Rules (J).Jet_Code /= Null_Unbounded_String then
         return "jet_" & Core;
      end if;
      return "scan_" & Core;
   end Scalar_Scan_Fn;

   --  The scanner the `word` core rule runs (jet or scan), for a keyword read.
   function Word_Scanner (Rules : Rule_Vectors.Vector) return String is
     ((if Find (Rules, "word") /= 0
         and then Rules (Find (Rules, "word")).Jet_Code /= Null_Unbounded_String
       then "jet_word" else "scan_word"));

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

   --  The extra condition that rejects a matched bareword which is a keyword
   --  (`word`/`atom` must not swallow a directive's keyword).
   function Scalar_Reject (Name, N : String) return String is
   begin
      if Name = "atom" or else Name = "word" then
         return " || kw_lookup(p->text + p->pos, " & N & ") != KWID_NONE";
      end if;
      return "";
   end Scalar_Reject;

   --  The positive form of Scalar_Reject, for a branch that accepts on `n`:
   --  a matched bareword must not be a keyword either.
   function Scalar_Guard (Name, N : String) return String is
   begin
      if Name = "atom" or else Name = "word" then
         return " && kw_lookup(p->text + p->pos, " & N & ") == KWID_NONE";
      end if;
      return "";
   end Scalar_Guard;

   --  The C expression converting a matched scalar (length N, text at p->pos)
   --  into its value.
   function Scalar_Value (Name, N : String) return String is
   begin
      if Name = "str" then
         --  Unquote + unescape the matched quoted string.
         return (if Views_On then "hbnf_str_value_v(p->text + p->pos, " & N & ")"
                 else "hbnf_str_value(p->text + p->pos, " & N & ")");
      elsif Name = "atom" or else Name = "word" then
         return (if Views_On then "hbnf_mkstr(p->text + p->pos, " & N & ")"
                 else "hbnf_str_append(p->text + p->pos, " & N & ")");
      elsif Name = "int" then
         return "atoll(p->text + p->pos)";
      elsif Name = "bool" or else Name = "flag" then
         return "((" & N & "==3 && strncmp(p->text+p->pos,""yes"",3)==0) "
           & "|| (" & N & "==2 && strncmp(p->text+p->pos,""on"",2)==0) "
           & "|| (" & N & "==4 && strncmp(p->text+p->pos,""true"",4)==0))";
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
                    & "_t)strtoull(p->text + p->pos, NULL, 10)";
               else
                  return "(int" & R
                    & "_t)strtoll(p->text + p->pos, NULL, 10)";
               end if;
            end if;
         end;
      end if;
      return (if Views_On then "hbnf_mkstr(p->text + p->pos, " & N & ")"
              else "hbnf_str_append(p->text + p->pos, " & N & ")");
   end Scalar_Value;

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
      Noted : constant Boolean := Note_Root (Rules);

      N : constant Natural := Natural (Rules.Length);

      --  The rules a cycle of references goes back to (see where it is worked out).
      Cycle_Target : array (1 .. N) of Boolean := [others => False];

      --  What each rule can begin with, for the first-byte switch of an alternation.
      La : constant HBNF_Lookahead.Analysis := HBNF_Lookahead.Analyze (Rules);

      function Find (Name : String) return Natural is (Find (Rules, Name));

      function Is_Core (Name : String) return Boolean is
        (Scalar_C_Type (Name) /= "");

      --  The same fields Emit emits as pointers, so that here they are
      --  allocated and parsed through the pointer rather than written into.
      --  Two independent computations of one graph: Emit and Emit_Parser do
      --  not share state, and Back_Edges is a pure function of the rules.
      Backs : constant Edge_Vectors.Vector := Back_Edges_C (Rules);

      --  The rules that can add to a context, directly (`%bind`, `%scope`) or by naming a rule that
      --  can.  Only these need to put the contexts back when they give up; a rule that cannot bind
      --  and calls nothing that can has nothing to put back, and an expression parser that asks the
      --  question at every level would otherwise pay for it on every call.
      Binds : array (1 .. Natural (Rules.Length)) of Boolean := [others => False];

      function Pat_Binds (V : Element_Vectors.Vector) return Boolean is
      begin
         for E of V loop
            if E.Kind = Block and then E.Op in B_Bind | B_Bind_Code | B_Scope then
               return True;
            elsif E.Kind = Name then
               declare
                  J : constant Natural := Find (To_String (E.Name));
               begin
                  if J > 0 and then Binds (J) then
                     return True;
                  end if;
               end;
            elsif E.Kind = Group and then Pat_Binds (E.Items) then
               return True;
            end if;
         end loop;
         return False;
      end Pat_Binds;

      Binds_Ready : Boolean := False;

      function Rule_Binds (I : Natural) return Boolean is
      begin
         if not Binds_Ready then
            Binds_Ready := True;
            declare
               Changed : Boolean := True;
            begin
               while Changed loop
                  Changed := False;
                  for K in Binds'Range loop
                     if not Binds (K) and then Pat_Binds (Rules (K).Pattern) then
                        Binds (K) := True;
                        Changed := True;
                     end if;
                  end loop;
               end loop;
            end;
         end if;
         return I in Binds'Range and then Binds (I);
      end Rule_Binds;

      function Is_Back (Owner : Natural; Member : String) return Boolean is
      begin
         for E of Backs loop
            if E.Owner = Owner and then To_String (E.Member) = Member then
               return True;
            end if;
         end loop;
         return False;
      end Is_Back;

      --  True when the rule named Name is character-level: its pattern is a
      --  sequence/alternation of Char_Range terminals and references to other
      --  char-level rules, each matching code points.  Such a rule is a token
      --  definition (compiled to a scanner), not a tree-building rule, so it
      --  emits no struct and its references match a token instead of recursing.
      --  (The classification itself is the package-level Is_Char_Rule.)

      --  The C condition that the current code point (in `c`) lies in [Lo, Hi].
      --  `c >= 0` is a useless comparison for an unsigned code point, so the
      --  lower bound is dropped when Lo = 0.
      function Range_Cond (Lo, Hi : Natural) return String is
      begin
         if Lo = 0 then
            return "(c <= " & Img (Hi) & ")";
         else
            return "(c >= " & Img (Lo) & " && c <= " & Img (Hi) & ")";
         end if;
      end Range_Cond;

      function Has_Alt (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Alt then
               return True;
            end if;
         end loop;
         return False;
      end Has_Alt;

      --  The keywords the lexer interns against: the `keywords` table when
      --  there is one (every word in it, used or not, as parse.y reserves
      --  its whole lookup() table), else every letter-led literal in the
      --  grammar, deduped in first-appearance order.
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

      --  The words the grammar writes %i"..." (case-insensitive) and the
      --  ones it writes plain.  A keyword is interned one way or the other,
      --  so it may not be both (checked where the prologue is emitted).
      Nocase_Words, Case_Words : String_Vectors.Vector;

      procedure Collect_Case (Els : Element_Vectors.Vector) is
      begin
         for E of Els loop
            case E.Kind is
               when Literal =>
                  if E.No_Case then
                     if not Nocase_Words.Contains (E.Lit) then
                        Nocase_Words.Append (E.Lit);
                     end if;
                  elsif not Case_Words.Contains (E.Lit) then
                     Case_Words.Append (E.Lit);
                  end if;
               when Group =>
                  Collect_Case (E.Items);
               when others =>
                  null;
            end case;
         end loop;
      end Collect_Case;

      function Nocase_Keyword (K : String) return Boolean is
        (Nocase_Words.Contains (To_Unbounded_String (K)));

      --  A keyword's enumerator: KW_ and its C identifier, with a suffix
      --  when an earlier keyword maps to the same one (unwind's table has
      --  both `DoT` and `dot`; `-` and `_` both become `_`).
      function Kw_Name (S : String) return String is
         Id    : constant String := C_Ident (S);
         Count : Natural := 0;
      begin
         for K of Keywords loop
            exit when To_String (K) = S;
            if C_Ident (To_String (K)) = Id then
               Count := Count + 1;
            end if;
         end loop;
         return "KW_" & Id & (if Count = 0 then "" else "_" & Img (Count + 1));
      end Kw_Name;

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
            Append (Buf, ", " & Kw_Name (To_String (K)));
         end loop;
         Append (Buf, " } kwid_t;");
         Append (Buf, LF);
         Append (Buf, LF);

         Append (Buf, "static kwid_t kw_lookup(const char *s, size_t len) {");
         Append (Buf, LF);
         for K of Keywords loop
            if Nocase_Keyword (To_String (K)) then
               Append (Buf, "    if (len == " & Img (Len (K))
                 & " && strncasecmp(s, """ & C_Escape (To_String (K))
                 & """, " & Img (Len (K)) & ") == 0) return "
                 & Kw_Name (To_String (K)) & ";   /* %i */");
               Append (Buf, LF);
            end if;
         end loop;
         Append (Buf, "    switch (len) {");
         Append (Buf, LF);
         for L in 1 .. Max_Len loop
            declare
               Seen : array (Character) of Boolean := (others => False);
               Any  : Boolean := False;
            begin
               for K of Keywords loop
                  if Len (K) = L and then not Nocase_Keyword (To_String (K))
                  then
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
                     if Len (K) = L and then not Seen (First (K))
                       and then not Nocase_Keyword (To_String (K))
                     then
                        Seen (First (K)) := True;
                        Append (Buf, "        case '" & First (K) & "':");
                        Append (Buf, LF);
                        for K2 of Keywords loop
                           if Len (K2) = L and then First (K2) = First (K)
                             and then not Nocase_Keyword (To_String (K2))
                           then
                              Append (Buf, "            if (memcmp(s, """
                                & C_Escape (To_String (K2)) & """, " & Img (L)
                                & ") == 0) return " & Kw_Name (To_String (K2)) & ";");
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
               if Is_Char_Rule (Rules, N) then
                  return "const char *";
               end if;
               if Natural (P.Length) = 1
                 and then P (1).Kind = Literal
                 and then P (1).Min = 1
                 and then P (1).Max = 1
               then
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
         if Emit_Value_Type (R) /= "" then
            --  a rule with a value yields it, whatever shape its pattern has
            return C_Type_Name (To_String (R.Name)) & " *out";
         end if;
         if Is_Char_Rule (Rules, To_String (R.Name)) then
            return C_Type_Name (To_String (R.Name)) & " *out";
         end if;
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            return "struct " & Pfx & C_Name (To_String (R.Name)) & "_list *out";
         end if;
         return C_Type_Name (To_String (R.Name)) & " *out";
      end Out_Type;

      --  ---- Local forks (RFCPLAN.md decision 14), --forks only ----
      --
      --  A rule is forked when two of its alternatives can start alike, so
      --  the first to match may not be the one a later element needs.  What
      --  an alternative can start with is a list of texts: a literal's own,
      --  `?` for a token (a character rule or a core rule), `*` for anything
      --  not known.

      function Lead_Of (Els : Element_Vectors.Vector; St, En : Natural;
                        Depth : Natural) return String_Vectors.Vector;

      --  The leads of every alternative of Els, together.
      function Leads (Els : Element_Vectors.Vector; Depth : Natural)
        return String_Vectors.Vector
      is
         R  : String_Vectors.Vector;
         St : Natural := 1;
      begin
         for K in 1 .. Natural (Els.Length) + 1 loop
            if K > Natural (Els.Length) or else Els (K).Kind = Alt then
               for X of Lead_Of (Els, St, K - 1, Depth) loop
                  R.Append (X);
               end loop;
               St := K + 1;
            end if;
         end loop;
         return R;
      end Leads;

      function Lead_Of (Els : Element_Vectors.Vector; St, En : Natural;
                        Depth : Natural) return String_Vectors.Vector
      is
         R : String_Vectors.Vector;
      begin
         if St > En or else Depth > 6 or else Els (St).Min = 0 then
            R.Append (To_Unbounded_String ("*"));
            return R;
         end if;
         declare
            E : constant Element_Access := Els (St);
         begin
            case E.Kind is
               when Literal =>
                  R.Append (E.Lit);
               when Name =>
                  declare
                     NM : constant String := To_String (E.Name);
                     J  : constant Natural :=
                       (if Is_Core (NM) then 0 else Find (NM));
                  begin
                     if Is_Core (NM)
                       or else (J /= 0 and then Is_Char_Rule (Rules, NM))
                     then
                        R.Append (To_Unbounded_String ("?"));
                     elsif J = 0 then
                        R.Append (To_Unbounded_String ("*"));
                     else
                        return Leads (Rules (J).Pattern, Depth + 1);
                     end if;
                  end;
               when Group =>
                  return Leads (E.Items, Depth + 1);
               when others =>
                  R.Append (To_Unbounded_String ("*"));
            end case;
         end;
         return R;
      end Lead_Of;

      function Starts_Alike (A, B : String_Vectors.Vector) return Boolean is
         function Word_Led (S : String) return Boolean is
           (S'Length > 0 and then S (S'First) in
              'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');
      begin
         for X of A loop
            for Y of B loop
               declare
                  XS : constant String := To_String (X);
                  YS : constant String := To_String (Y);
               begin
                  if XS = "*" or else YS = "*" then
                     return True;
                  elsif XS = "?" and then YS = "?" then
                     return True;
                  elsif XS = "?" then
                     if Word_Led (YS) then
                        return True;
                     end if;
                  elsif YS = "?" then
                     if Word_Led (XS) then
                        return True;
                     end if;
                  elsif XS'Length <= YS'Length
                    and then YS (YS'First .. YS'First + XS'Length - 1) = XS
                  then
                     return True;
                  elsif YS'Length <= XS'Length
                    and then XS (XS'First .. XS'First + YS'Length - 1) = YS
                  then
                     return True;
                  end if;
               end;
            end loop;
         end loop;
         return False;
      end Starts_Alike;

      --  The rule is read as a struct alternation (the Has_Alt case of
      --  Emit_Rule_Parser), the only shape a fork can resume.
      function Fork_Capable (Idx : Natural) return Boolean is
         R : constant Rule := Rules (Idx);
         P : constant Element_Vectors.Vector := R.Pattern;
      begin
         if R.Jet_Code /= Null_Unbounded_String
           or else Is_Char_Rule (Rules, To_String (R.Name))
           or else not Has_Alt (P)
         then
            return False;
         end if;
         if Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1)
         then
            return False;                               --  a list
         end if;
         return not Is_Pure_Literal_Alt (P)
           and then Scalar_Union_Type (P) = ""
           and then not (Natural (P.Length) = 1
                         and then P (1).Kind in Name | Literal);
      end Fork_Capable;

      --  Alternatives I < J of the rule that can start alike (0, 0: none).
      procedure Fork_Pair (Idx : Natural; I, J : out Natural) is
         P  : constant Element_Vectors.Vector := Rules (Idx).Pattern;
         Ls : array (1 .. Natural (P.Length) + 1) of String_Vectors.Vector;
         N  : Natural := 0;
         St : Natural := 1;
      begin
         I := 0;  J := 0;
         if not Fork_Capable (Idx) then
            return;
         end if;
         for K in 1 .. Natural (P.Length) + 1 loop
            if K > Natural (P.Length) or else P (K).Kind = Alt then
               N := N + 1;
               Ls (N) := Lead_Of (P, St, K - 1, 0);
               St := K + 1;
            end if;
         end loop;
         for A in 1 .. N - 1 loop
            for B in A + 1 .. N loop
               if Starts_Alike (Ls (A), Ls (B)) then
                  I := A;  J := B;
                  return;
               end if;
            end loop;
         end loop;
      end Fork_Pair;

      Fork_Seq : Natural := 0;       --  numbers the retry blocks

      --  The rules that can match nothing: a character rule among them (an
      --  alias of an optional token, `blank_2 = blank`) succeeds on nothing.
      Null_Flags : constant HBNF_Lookahead.Flags :=
        HBNF_Lookahead.Nullable_Set (Rules);

      function Is_Forked (Idx : Natural) return Boolean is
         I, J : Natural;
      begin
         if not Forks_On or else Idx = 0 then
            return False;
         end if;
         Fork_Pair (Idx, I, J);
         return I /= 0;
      end Is_Forked;

      --  Emit matching + building for segment Els(First..Last), writing fields
      --  through the accessor Acc ("r." or "nn->").  On failure emits the
      --  `Fail` statement ("goto ..." or "p->pos = save; return false;").
      procedure Emit_Seq
        (Owner : Natural;
         Els : Element_Vectors.Vector; First, Last : Natural; Acc : String;
         Buf  : in out U; Fail : String; Ind : String := "    ";
         Ws   : Boolean := False; Lead_Ws : Boolean := True) is
         --  Lead_Ws is False when the caller has already skipped whitespace
         --  at this position (Emit_Linear hoists it out of an alternation,
         --  where every branch would otherwise re-skip the same run).
         At_First : Boolean := True;
         Stop     : Boolean := False;    --  a retry block took the rest
         procedure Ws_Skip is
         begin
            if Ws and then (Lead_Ws or else not At_First) then
               Append (Buf, Ind & "skip_ws(p);");
               Append (Buf, LF);
            end if;
         end Ws_Skip;

         --  The context operations in this segment: where it starts (for
         --  `%where` and `%bind { }`, which see the text matched so far),
         --  the scopes it opens, and the element a `? ctx` follows.
         Sid  : constant String := Ctx_Img (Ctx_Seq + 1);
         Seg  : constant String := "sg" & Sid & "_";
         Scopes : String_Vectors.Vector;
         Needs_Seg : constant Boolean :=
           (for some K in First .. Last =>
              Els (K).Kind = Block
              and then Els (K).Op in B_Where | B_Bind_Code);

         --  `Acc` is `r.` or `nn->`; the node as a pointer.
         function Node_Ptr return String is
           (if Acc'Length >= 2 and then Acc (Acc'Last) = '.'
            then "&" & Acc (Acc'First .. Acc'Last - 1)
            else Acc (Acc'First .. Acc'Last - 2));

         --  A field path `declarators.name` as members of the node.
         function Path_C (Path : String) return String is
            R : U := To_Unbounded_String (Acc);
            B : Natural := Path'First;
         begin
            for K in Path'Range loop
               if Path (K) = '.' then
                  Append (R, C_Field (Path (B .. K - 1)) & ".");
                  B := K + 1;
               end if;
            end loop;
            Append (R, C_Field (Path (B .. Path'Last)));
            return To_String (R);
         end Path_C;

         --  The statements that find where the text matched since Var starts,
         --  after the blanks, as `st_`, with the end in `k_`.
         function Span_Of (Var : String) return String is
           ("size_t k_ = p->pos, st_ = " & Var & "; "
            & (if Ws then "p->pos = " & Var & "; skip_ws(p); st_ = p->pos; "
                          & "p->pos = k_; " else ""));
      begin
         Ctx_Seq := Ctx_Seq + 1;
         for K in First .. Last loop
            if Els (K).Kind = Block and then Els (K).Op = B_As then
               Append (Buf, Ind & "size_t cp_"
                 & C_Ident_Lower (To_String (Els (K).Ctx)) & "_" & Sid
                 & " = 0, cl_" & C_Ident_Lower (To_String (Els (K).Ctx)) & "_"
                 & Sid & " = 0;");
               Append (Buf, LF);
            end if;
         end loop;
         if Needs_Seg then
            Append (Buf, Ind & "size_t " & Seg & ";  " & Seg & " = p->pos;");
            Append (Buf, LF);
         end if;
         for K in First .. Last loop
            exit when Stop;
            declare
               E : constant Element_Access := Els (K);
            begin
               --  A `? ctx` after this element asks about its text.
               if K < Last and then Els (K + 1).Kind = Block
                 and then Els (K + 1).Op in B_Test | B_Not_Test | B_As | B_Num
               then
                  Append (Buf, Ind & "size_t es" & Sid & "_" & Ctx_Img (K)
                    & ";  es" & Sid & "_" & Ctx_Img (K) & " = p->pos;");
                  Append (Buf, LF);
               end if;
               case E.Kind is
                  when Literal =>
                     declare
                        Lit : constant String := To_String (E.Lit);
                        Fn  : constant String :=
                          (if E.No_Case and then Is_Keyword_Lit (Lit)
                           then "expect_word_nocase"
                           elsif E.No_Case then "expect_lit_nocase"
                           elsif Is_Keyword_Lit (Lit) then "expect_word"
                           else "expect_lit");
                     begin
                        Ws_Skip;
                        Append (Buf, Ind & "if (!" & Fn & "(p, """
                          & C_Escape (Lit) & """, " & Img (Lit'Length)
                          & ")) { " & Fail & " }");
                        Append (Buf, LF);
                     end;
                  when Name =>
                     if Is_Core (To_String (E.Name)) then
                        declare
                           NM : constant String := To_String (E.Name);
                        begin
                           Ws_Skip;
                           Append (Buf, Ind & "{ size_t n = "
                             & Scalar_Scan_Fn (Rules, NM)
                             & "(p->text, p->pos, p->len); if (!n"
                             & Scalar_Reject (NM, "n")
                             & ") { fail(p, """ & Core_Desc (NM)
                             & """, 0, p->text + p->pos, 0); " & Fail & " } ");
                           if Is_Number (NM) then
                              Append (Buf, "num_" & C_Field (NM)
                                & " = p->text + p->pos; p->pos += n; }");
                           else
                              Append (Buf, Acc & C_Field (NM) & " = "
                                & Scalar_Value (NM, "n") & "; p->pos += n; }");
                           end if;
                           Append (Buf, LF);
                        end;
                     else
                        declare
                           NM : constant String := To_String (E.Name);

                           --  Decision 14: a forked rule followed by more of
                           --  this sequence is tried again, with its next
                           --  alternative, when the rest fails.
                           Forked : constant Boolean :=
                             Forks_On and then K < Last
                             and then not Is_Back (Owner, NM)
                             and then Is_Forked (Find (Alias_Target (Rules, NM)))
                             and then (for all X in K + 1 .. Last =>
                                         Els (X).Kind /= Block);
                           Fid : constant String := Ctx_Img (Fork_Seq + 1);
                           Frees : U;

                           procedure Collect (V : Element_Vectors.Vector;
                                              F, L : Natural) is
                           begin
                              for X in F .. L loop
                                 if V (X).Kind = Group then
                                    Collect (V (X).Items, 1,
                                             Natural (V (X).Items.Length));
                                 elsif V (X).Kind = Name
                                   and then not Is_Core (To_String (V (X).Name))
                                 then
                                    declare
                                       FN : constant String :=
                                         To_String (V (X).Name);
                                       T  : constant String :=
                                         Alias_Target (Rules, FN);
                                       J  : constant Natural := Find (T);
                                    begin
                                       if J /= 0 and then not Is_Back (Owner, FN)
                                         and then Analyze (Rules, J).Kind in
                                                    Struct | List
                                       then
                                          Append (Frees, Ind & "    free_"
                                            & C_Name (T)
                                            & (if J = 1 and then Analyze (Rules, J).Kind = List
                                               then "_nodes" else "") & "(&" & Acc
                                            & C_Field (FN) & ");  memset(&"
                                            & Acc & C_Field (FN) & ", 0, "
                                            & "sizeof " & Acc & C_Field (FN)
                                            & ");" & LF);
                                       end if;
                                    end;
                                 end if;
                              end loop;
                           end Collect;
                        begin
                           Ws_Skip;
                           if Is_Hidden (NM) and then Is_Char_Rule (Rules, NM)
                             and then Find (NM) /= 0
                             and then Rules (Find (NM)).Jet_Code = Null_Unbounded_String
                             and then E.Args = Null_Unbounded_String
                           then
                              --  A hidden token is run by its scanner, here: no call, no value.
                              declare
                                 J   : constant Natural := Find (NM);
                                 Opt : constant Boolean :=
                                   (Natural (Rules (J).Pattern.Length) = 1
                                    and then Rules (J).Pattern (1).Min = 0)
                                   or else Null_Flags (J);
                              begin
                                 Append (Buf, Ind & "{ size_t n_ = " & Rule_Scanner (Rules, NM)
                                   & "(p->text, p->pos, p->len);"
                                   & (if Opt then ""
                                      else " if (!n_) { fail(p, """ & NM & """, 0, p->text + p->pos, 0); "
                                           & Fail & " }")
                                   & " p->pos += n_; }");
                                 Append (Buf, LF);
                              end;
                           elsif Is_Hidden (NM) then
                              --  Matched into a scratch value: the tree has no field for it.
                              declare
                                 T : constant String := Out_Type (Find (NM));
                              begin
                              Append (Buf, Ind & "{ " & T (T'First .. T'Last - 5) & " h_; memset(&h_, 0, sizeof h_); "
                                & "if (!" & Rule_Call
                                    (To_String (Rules (Owner).Name), E,
                                     "parse_rule_" & C_Name (NM) & "(p, &h_)")
                                & ") { " & Fail & " } }");
                              Append (Buf, LF);
                              end;
                           elsif Forked then
                              Fork_Seq := Fork_Seq + 1;
                              Collect (Els, K, Last);
                              Append (Buf, Ind & "{ size_t fk" & Fid
                                & " = 0, fu" & Fid & " = 0, fsv" & Fid
                                & " = p->pos;"
                                & (if Ctx_On
                                   then "  hbnf_mark_t fm" & Fid
                                        & " = hbnf_mark();" else ""));
                              Append (Buf, LF);
                              Append (Buf, "fork" & Fid & ":" & LF);
                              Append (Buf, Ind & "  p->pos = fsv" & Fid
                                & ";  hbnf_fork_start = fk" & Fid & ";");
                              Append (Buf, LF);
                              Append (Buf, Ind & "  if (!parse_rule_" & C_Name (NM)
                                & "(p, &" & Acc & C_Field (NM) & ")) { "
                                & Fail & " }");
                              Append (Buf, LF);
                              Append (Buf, Ind & "  fu" & Fid
                                & " = hbnf_fork_used;");
                              Append (Buf, LF);
                              Emit_Seq (Owner, Els, K + 1, Last, Acc, Buf,
                                        "goto fkf" & Fid & ";", Ind & "  ", Ws);
                              Append (Buf, Ind & "  goto fkd" & Fid & ";");
                              Append (Buf, LF);
                              Append (Buf, "fkf" & Fid & ":" & LF);
                              Append (Buf, Ind & "  free_" & C_Name (Alias_Target (Rules, NM))
                                & "(&" & Acc & C_Field (NM) & ");  memset(&"
                                & Acc & C_Field (NM) & ", 0, sizeof " & Acc
                                & C_Field (NM) & ");" & LF);
                              Append (Buf, Frees);
                              if Ctx_On then
                                 Append (Buf, Ind & "  hbnf_reset (&fm" & Fid
                                   & ");" & LF);
                              end if;
                              Append (Buf, Ind & "  fk" & Fid & " = fu" & Fid
                                & ";  goto fork" & Fid & ";" & LF);
                              Append (Buf, "fkd" & Fid & ": ;" & LF);
                              Append (Buf, Ind & "}" & LF);
                              Stop := True;
                           else
                           --  A back-edge field is a pointer: allocate the
                           --  node from the arena, then parse into it.  The
                           --  callee takes a pointer already, so unlike the
                           --  by-value case there is no `&` -- and the `&`
                           --  literal in c_seq_ref is why this is a second
                           --  template rather than a hole.
                           Append (Buf, Fill
                             ((if Is_Back (Owner, NM)
                               then (if Compact_On then "c_seq_ref_cptr"
                                     else "c_seq_ref_ptr")
                               else "c_seq_ref"),
                              (H ("ind", Ind),
                               H ("call", Rule_Call
                                 (To_String (Rules (Owner).Name), E,
                                  "parse_rule_" & C_Name (NM)
                                  & (if Is_Back (Owner, NM)
                                     then (if Compact_On then "(p, &t_)"
                                           else "(p, " & Acc & C_Field (NM) & ")")
                                     else "(p, &" & Acc & C_Field (NM) & ")"))),
                               H ("acc", Acc),
                               H ("field", C_Field (NM)),
                               H ("fail", Fail))));
                           Append (Buf, LF);
                           end if;
                        end;
                     end if;
                  when Group =>
                     Emit_Seq (Owner, E.Items, 1, Natural (E.Items.Length),
                               Acc, Buf, Fail, Ind & "    ", Ws);
                  when Alt =>
                     null;
                  when Char_Range =>
                     null;
                  when Block =>
                     case E.Op is
                        when B_Emit =>
                           null;  --  refused before emission until it is generated
                        when B_Action =>
                           null;  --  lifted to a rule of its own before emission
                        when B_Test | B_Not_Test =>
                           Append (Buf, Ind & "{ " & Span_Of ("es" & Sid & "_"
                             & Ctx_Img (K - 1)));
                           Append (Buf, LF);
                           Append (Buf, Ind & "  if (" & (if E.Op = B_Test then "!" else "")
                             & "hbnf_ctx_has (CTX_"
                             & C_Ident_Lower (To_String (E.Ctx))
                             & ", p->text + st_, k_ - st_)) {");
                           Append (Buf, LF);
                           Append (Buf, Ind & "      p->pos = st_; fail(p, ""a name "
                             & (if E.Op = B_Test then "in `" else "not in `") & To_String (E.Ctx)
                             & "`"", 0, p->text + st_, 0); p->pos = k_; "
                             & Fail & " } }");
                           Append (Buf, LF);
                        when B_Bind =>
                           Append (Buf, Ind & "{ const char *v_ = "
                             & Path_C (To_String (E.Path)) & "; if (v_) "
                             & "hbnf_ctx_add (CTX_"
                             & C_Ident_Lower (To_String (E.Ctx))
                             & ", v_, strlen (v_)); }");
                           Append (Buf, LF);
                        when B_Bind_Code =>
                           Append (Buf, Ind & "{ " & Span_Of (Seg)
                             & "bindc_" & Ctx_Img (E.Id)
                             & " (p, p->text + st_, k_ - st_, " & Node_Ptr
                             & "); }");
                           Append (Buf, LF);
                        when B_Not | B_And =>
                           --  A test that consumes nothing: run x on a copy
                           --  of the parser, then go on from the copy's
                           --  start (a failure inside it leaves no trace).
                           declare
                              Desc : U;
                              Br   : Natural := 0;
                              First_El : Boolean;
                           begin
                              --  The first pass keeps no failures, so only the position needs
                              --  putting back; the second keeps them and puts all of the parser back.
                              Append (Buf, Ind & "{ parser_t sv_;  size_t sp_ = p->pos;  int hit_ = 0;"
                                & "  size_t h_;");
                              Append (Buf, LF);
                              Append (Buf, Ind & "  if (!p->quiet) sv_ = *p; else sv_.pos = 0;");
                              Append (Buf, LF);
                              if Ws then
                                 Append (Buf, Ind & "  skip_ws(p);");
                                 Append (Buf, LF);
                              end if;
                              Append (Buf, Ind & "  h_ = p->pos;");
                              Append (Buf, LF);
                              First_El := True;
                              Br := 1;
                              declare
                                 Opened : Boolean := False;

                                 procedure Open_Branch is
                                 begin
                                    Append (Buf, Ind & "  if (!hit_) { int ok_ = 1; "
                                      & "size_t n_ = 0;  p->pos = h_;");
                                    Append (Buf, LF);
                                    Opened := True;
                                    First_El := True;
                                 end Open_Branch;

                                 procedure Close_Branch is
                                 begin
                                    if Opened then
                                       Append (Buf, Ind & "    (void)n_;  if (ok_) "
                                         & "hit_ = 1; }");
                                       Append (Buf, LF);
                                       Opened := False;
                                    end if;
                                 end Close_Branch;
                              begin
                                 for X of E.Look loop
                                    if X.Kind = Alt then
                                       Close_Branch;
                                       Append (Desc, " or ");
                                       Br := Br + 1;
                                    else
                                       if not Opened then
                                          Open_Branch;
                                       end if;
                                       if not First_El and then Ws then
                                          Append (Buf, Ind & "    if (ok_) skip_ws(p);");
                                          Append (Buf, LF);
                                       end if;
                                       First_El := False;
                                       if X.Kind = Literal then
                                          declare
                                             Lit : constant String :=
                                               To_String (X.Lit);
                                             Fn  : constant String :=
                                               (if X.No_Case
                                                  and then Is_Keyword_Lit (Lit)
                                                then "expect_word_nocase"
                                                elsif X.No_Case
                                                then "expect_lit_nocase"
                                                elsif Is_Keyword_Lit (Lit)
                                                then "expect_word"
                                                else "expect_lit");
                                          begin
                                             Append (Desc, "`" & Lit & "`");
                                             Append (Buf, Ind & "    if (ok_) ok_ = "
                                               & Fn & "(p, """ & C_Escape (Lit)
                                               & """, " & Img (Lit'Length) & ");");
                                          end;
                                       else
                                          declare
                                             NM : constant String :=
                                               To_String (X.Name);
                                             Scan : constant String :=
                                               (if Is_Core (NM)
                                                then Scalar_Scan_Fn (Rules, NM)
                                                elsif Is_Char_Rule (Rules, NM)
                                                then Rule_Scanner (Rules, NM)
                                                else "");
                                          begin
                                             if Scan = "" then
                                                raise Parse_Error with
                                                  "a lookahead (`!` or `&`) "
                                                  & "looks at a literal or a "
                                                  & "token, and `" & NM
                                                  & "` is a phrase rule; make "
                                                  & "it a token (write it with "
                                                  & "characters only) or look "
                                                  & "for a literal";
                                             end if;
                                             Append (Desc, NM);
                                             Append (Buf, Ind & "    if (ok_) { n_ = "
                                               & Scan & "(p->text, p->pos, "
                                               & "p->len); if (n_) p->pos += n_; "
                                               & "else ok_ = 0; }");
                                          end;
                                       end if;
                                       Append (Buf, LF);
                                    end if;
                                 end loop;
                                 Close_Branch;
                              end;
                              Append (Buf, Ind & "  if (p->quiet) p->pos = sp_; else *p = sv_;");
                              Append (Buf, LF);
                              if E.Op = B_Not then
                                 Append (Buf, Ind & "  if (hit_) { fail(p, "
                                   & """something other than "
                                   & C_Escape (To_String (Desc))
                                   & """, 0, p->text + p->pos, 0); " & Fail
                                   & " } }");
                              else
                                 Append (Buf, Ind & "  if (!hit_) { fail(p, """
                                   & C_Escape (To_String (Desc))
                                   & """, 1, p->text + p->pos, 0); " & Fail
                                   & " } }");
                              end if;
                              Append (Buf, LF);
                           end;
                        when B_Scope =>
                           Scopes.Append (To_Unbounded_String
                             ("sc" & Sid & "_" & Ctx_Img (K)));
                           Append (Buf, Ind & "hbnf_mark_t sc" & Sid & "_"
                             & Ctx_Img (K) & ";  sc" & Sid & "_" & Ctx_Img (K)
                             & " = hbnf_mark();");
                           Append (Buf, LF);
                        when B_As =>
                           --  keep where the text of the element before began
                           --  and how long it is
                           Append (Buf, Ind & "{ " & Span_Of ("es" & Sid & "_"
                             & Ctx_Img (K - 1)) & "cp_"
                             & C_Ident_Lower (To_String (E.Ctx)) & "_" & Sid
                             & " = st_;  cl_"
                             & C_Ident_Lower (To_String (E.Ctx)) & "_" & Sid
                             & " = k_ - st_; }");
                           Append (Buf, LF);
                        when B_Same =>
                           Ws_Skip;
                           Append (Buf, Ind & "if (p->pos + cl_"
                             & C_Ident_Lower (To_String (E.Ctx)) & "_" & Sid
                             & " > p->len || memcmp (p->text + p->pos, p->text + cp_"
                             & C_Ident_Lower (To_String (E.Ctx)) & "_" & Sid
                             & ", cl_" & C_Ident_Lower (To_String (E.Ctx)) & "_"
                             & Sid & ")) { fail(p, ""the same text again, `"
                             & To_String (E.Ctx) & "`"", 0, p->text + p->pos, 0); "
                             & Fail & " }");
                           Append (Buf, LF);
                           Append (Buf, Ind & "p->pos += cl_"
                             & C_Ident_Lower (To_String (E.Ctx)) & "_" & Sid & ";");
                           Append (Buf, LF);
                        when B_Guard =>
                           --  the clause of a rule with numeric parameters applies
                           Append (Buf, Ind & "if (!" & HBNF_Grammar.Render_Guard
                             (To_String (E.Ctx), Guard_Slot'Access,
                              "&&", "||", "!", "==", ">=", "<=")
                             & ") { fail(p, ""a number the rule takes"", 0, p->text + p->pos, 0); "
                             & Fail & " }");
                           Append (Buf, LF);
                        when B_Spaces =>
                           --  exactly that many spaces
                           Append (Buf, Ind & "{ long n_ = "
                             & Frame_Expr (To_String (Rules (Owner).Name),
                                           To_String (E.Ctx))
                             & "; long i_ = 0; while (i_ < n_ && p->pos + (size_t)i_ < p->len"
                             & " && p->text[p->pos + (size_t)i_] == ' ') i_++;"
                             & " if (i_ != n_) { fail(p, ""the indentation"", 0, p->text + p->pos, 0); "
                             & Fail & " } p->pos += (size_t)n_; }");
                           Append (Buf, LF);
                        when B_Col =>
                           --  the column: the code points since the line began
                           Append (Buf, Ind & "{ size_t b_ = p->pos; long c_ = 0; "
                             & "while (b_ > 0 && p->text[b_ - 1] != '\n' && p->text[b_ - 1] != '\r') "
                             & "{ b_--; if ((p->text[b_] & 0xC0) != 0x80) c_++; } HF("
                             & Ctx_Img (Natural'Max (0, HBNF_Grammar.Slot_Of
                                 (To_String (Rules (Owner).Name), To_String (E.Ctx))))
                             & ") = c_; }");
                           Append (Buf, LF);
                        when B_Num =>
                           --  the number the element before matched
                           Append (Buf, Ind & "{ " & Span_Of ("es" & Sid & "_"
                             & Ctx_Img (K - 1)) & "long v_ = 0; size_t q_; "
                             & "for (q_ = st_; q_ < k_; q_++) v_ = v_ * 10 + (p->text[q_] - '0'); HF("
                             & Ctx_Img (Natural'Max (0, HBNF_Grammar.Slot_Of
                                 (To_String (Rules (Owner).Name), To_String (E.Ctx))))
                             & ") = v_; }");
                           Append (Buf, LF);
                        when B_Where =>
                           Append (Buf, Ind & "{ " & Span_Of (Seg));
                           Append (Buf, LF);
                           Append (Buf, Ind & "  if (!where_" & Ctx_Img (E.Id)
                             & " (p, p->text + st_, k_ - st_, " & Node_Ptr
                             & ")) {");
                           Append (Buf, LF);
                           Append (Buf, Ind & "      p->pos = st_; fail(p, ""a "
                             & "valid " & To_String (Rules (Owner).Name)
                             & """, 0, p->text + st_, 0); p->pos = k_; "
                             & Fail & " } }");
                           Append (Buf, LF);
                     end case;
                  when Bit_Field =>
                     null;     --  a rule with bit fields never reaches here (Split_Wire)
                  when Negation =>
                     null;   --  resolved into a rule of ranges before this runs
               end case;
               At_First := False;
            end;
         end loop;
         --  What a `%scope` bound ends with the segment.
         for I in reverse 1 .. Natural (Scopes.Length) loop
            Append (Buf, Ind & "hbnf_reset (&" & To_String (Scopes (I)) & ");");
            Append (Buf, LF);
         end loop;
      end Emit_Seq;

      --  FIRST-set computation for keyword dispatch: the literal keywords that
      --  can begin an element, transitively through rule references.  A core
      --  scalar (word / atom / int / str / …) or a jet has no bounded keyword
      --  set, so it makes the whole alternation fall back to linear probing.
      function Is_Keyword (S : String) return Boolean renames Is_Keyword_Lit;

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
            when Char_Range =>
               null;
            when Block =>
               null;  --  lifted to a rule of its own before emission
            when Bit_Field =>
               null;     --  a rule with bit fields never reaches here (Split_Wire)
            when Negation =>
               null;   --  resolved into a rule of ranges before this runs
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

      --  The FIRST set of each '|' branch, flattened into one vector: branch
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
        (Owner : Natural;
         Els : Element_Vectors.Vector; Acc, Free, Clears, Ok : String;
         Kind_Prefix : String := "";
         Buf : in out U; Ind : String := "    "; Label : String := "";
         Ws   : Boolean := False;
         Alts : String_Vectors.Vector := String_Vectors.Empty_Vector;
         Fork : Boolean := False) is
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

         --  The field names a branch writes (its Name elements and, when a
         --  keyword tag is set, `kind`), for a per-branch reset that zeroes
         --  only what the branch touched instead of the whole union-shaped
         --  struct.  Numbers are excluded: they write a deferred `num_<field>`
         --  pointer, cleared separately (Clears).
         function Written_Fields (Els : Element_Vectors.Vector;
                                  First, Last : Natural;
                                  Kind : Boolean) return String_Vectors.Vector is
            R : String_Vectors.Vector;
            procedure Add (S : String) is
               Present : Boolean := False;
            begin
               for X of R loop
                  if To_String (X) = S then
                     Present := True;
                  end if;
               end loop;
               if not Present then
                  R.Append (To_Unbounded_String (S));
               end if;
            end Add;
            procedure Walk (Els2 : Element_Vectors.Vector; F, L : Natural) is
            begin
               for K in F .. L loop
                  case Els2 (K).Kind is
                     when Literal => null;
                     when Name =>
                        declare
                           NM : constant String := To_String (Els2 (K).Name);
                        begin
                           if not Is_Number (NM) and then not Is_Hidden (NM) then
                              Add (C_Field (NM));
                           end if;
                        end;
                     when Group =>
                        Walk (Els2 (K).Items, 1, Natural (Els2 (K).Items.Length));
                     when Alt => null;
                     when Char_Range => null;
                     when Block => null;  --  lifted to a rule before emission
                     when Bit_Field =>
                        null;     --  a rule with bit fields never reaches here (Split_Wire)
                     when Negation =>
                        null;   --  resolved into a rule of ranges before this runs
                  end case;
               end loop;
            end Walk;
         begin
            Walk (Els, First, Last);
            if Kind then
               Add ("kind");
            end if;
            return R;
         end Written_Fields;

         --  The linear ordered-choice chain: try each branch in source order,
         --  restoring p->pos and resetting the struct between attempts.  After
         --  the last branch fails, control falls through to the caller's own
         --  failure handling.
         procedure Emit_Linear is
            LSt : Natural := 1;
            LBr : Natural := 0;
            --  The branch that has just failed: the fields it may have set
            --  are what the reset must clear.
            PSt, PEn : Natural := 0;
            --  Every branch starts at the same position, so each would skip
            --  the same whitespace run again.  Skip it once and move `save`
            --  past it, so a failed branch returns to the first real byte.
            --  skip_ws is a pure function of the position, so this is the
            --  same language, one call instead of one per branch.
            Hoist : constant Boolean := Ws and then Has_Alt (Els);
            Cx    : U;       --  the name of this alternation's context mark

            --  Where to start on a byte.  Each branch can begin with some bytes (what
            --  the analysis says its first code points are; a branch that can match
            --  nothing, or one that reads what an earlier element kept, can begin
            --  with any).  A byte goes to the first branch that can begin with it;
            --  the branches before that one cannot match, so they are not tried.
            --  Branch 1 is where the chain begins anyway.
            Bs   : constant HBNF_Lookahead.Bounds_Vectors.Vector :=
              HBNF_Lookahead.Branches (Els);
            NBr  : constant Natural := Natural (Bs.Length);
            Dsp  : array (0 .. 255) of Natural := [others => 0];
            Entry_Used : array (1 .. Natural'Max (1, NBr)) of Boolean :=
              [others => False];
            Plan_Ok : Boolean := False;

            procedure Plan is
               function Reads_Kept (F, L : Natural) return Boolean is
                 (for some K in F .. L =>
                    Els (K).Kind = Block
                    and then Els (K).Op in B_Same | B_Spaces);
               Used : Boolean := False;
            begin
               if NBr < 3 then
                  return;
               end if;
               for K in 1 .. NBr loop
                  declare
                     Set  : HBNF_Lookahead.Cp_Set;
                     Null_Branch : Boolean;
                     Any_Byte : Boolean;
                     Wide : Boolean := False;
                  begin
                     HBNF_Lookahead.Branch_First (La, Rules, Els, Bs (K), Set, Null_Branch);
                     Any_Byte := Null_Branch or else HBNF_Lookahead.Has_Any (Set)
                       or else Reads_Kept (Bs (K).First, Bs (K).Last);
                     for R in 1 .. HBNF_Lookahead.Range_Count (Set) loop
                        if HBNF_Lookahead.Range_Hi (Set, R) >= 128 then
                           Wide := True;
                        end if;
                     end loop;
                     for B in 0 .. 255 loop
                        if Dsp (B) = 0 then
                           declare
                              Can : Boolean := Any_Byte or else (B >= 128 and then Wide);
                           begin
                              if not Can and then B < 128 then
                                 for R in 1 .. HBNF_Lookahead.Range_Count (Set) loop
                                    if B >= HBNF_Lookahead.Range_Lo (Set, R)
                                      and then B <= HBNF_Lookahead.Range_Hi (Set, R)
                                    then
                                       Can := True;
                                    end if;
                                 end loop;
                              end if;
                              if Can then
                                 Dsp (B) := K;
                              end if;
                           end;
                        end if;
                     end loop;
                  end;
               end loop;
               for B in 0 .. 255 loop
                  if Dsp (B) > 1 then
                     Used := True;
                     Entry_Used (Dsp (B)) := True;
                  end if;
               end loop;
               Plan_Ok := Used;
            end Plan;

            --  A guarded choice is a plain chain: each branch's guard is
            --  checked where it succeeds.
            Disp : Boolean := False;

            --  What a failed branch leaves is put back: the position, what it set, the
            --  contexts it bound.
            procedure Emit_Reset is
               --  A branch of literals alone (a keyword of a choice among keywords) has bound and
               --  set nothing, whatever the place it failed: only the position goes back.
               Lits_Only : constant Boolean :=
                 PSt <= PEn and then (for all I in PSt .. PEn => Els (I).Kind = Literal);
            begin
               if Ctx_On and then Rule_Binds (Owner) and then not Lits_Only then
                  Append (Buf, Ind & "hbnf_reset (&" & To_String (Cx) & ");");
                  Append (Buf, LF);
               end if;
               Append (Buf, Ind & "p->pos = save; " & (if Lits_Only then "" else Free));
               --  Free releases what the failed branch set, and the fields
               --  are then zeroed so a later branch (or the caller, on a
               --  branch that matched) never sees them, and a later
               --  Free never releases them twice.  It is the failed
               --  branch's fields that are dirty, not the next one's.
               declare
                  Fs : constant String_Vectors.Vector :=
                    Written_Fields (Els, PSt, PEn,
                      Kind_Prefix /= "" and then PSt <= PEn
                        and then Els (PSt).Kind = Literal);
               begin
                  for F of Fs loop
                     Append (Buf, "; memset(&" & Acc & To_String (F)
                       & ", 0, sizeof " & Acc & To_String (F) & ")");
                  end loop;
               end;
               Append (Buf, Clears);
               Append (Buf, ";");
               Append (Buf, LF);
            end Emit_Reset;
         begin
            if not Fork and then not (for some E of Els =>
                                        E.Kind = Alt and then E.Guard /= 0)
            then
               Plan;
            end if;
            Disp := Plan_Ok;
            if Ctx_On and then Rule_Binds (Owner) then
               Ctx_Seq := Ctx_Seq + 1;
               Cx := To_Unbounded_String ("hm" & Ctx_Img (Ctx_Seq) & "_");
               Append (Buf, Ind & "hbnf_mark_t " & To_String (Cx) & ";  "
                 & To_String (Cx) & " = hbnf_mark();");
               Append (Buf, LF);
            end if;
            if Hoist then
               Append (Buf, Ind & "skip_ws(p);");
               Append (Buf, LF);
               Append (Buf, Ind & "save = p->pos;");
               Append (Buf, LF);
            end if;

            if Fork then
               --  A retry (decision 14): the caller says how many
               --  alternatives to skip, as the ones it already tried.
               declare
                  NB : Natural := 1;
               begin
                  for E of Els loop
                     if E.Kind = Alt then
                        NB := NB + 1;
                     end if;
                  end loop;
                  Append (Buf, Ind & "{ size_t fs_ = hbnf_fork_start;  "
                    & "hbnf_fork_start = 0;");
                  Append (Buf, LF);
                  Append (Buf, Ind & "  switch (fs_) { case 0: break;");
                  for B in 1 .. NB - 1 loop
                     Append (Buf, " case " & Img (B) & ": goto " & Label
                       & "alt_fail_" & Img (B) & ";");
                  end loop;
                  Append (Buf, " default: goto " & Label & "alt_fail_"
                    & Img (NB) & "; } }");
                  Append (Buf, LF);
               end;
            end if;

            if Disp then
               --  Jump straight to the first branch that can begin with the next byte.
               --  Only while the parse is quiet (the first pass of parse_text): a parse
               --  that fails is read again with the failures recorded and every branch
               --  tried in turn, so the error says everything that could have stood.
               Append (Buf, Ind & "if (p->quiet && p->pos < p->len) {");
               Append (Buf, LF);
               Append (Buf, Ind & "    switch ((unsigned char)p->text[p->pos]) {");
               Append (Buf, LF);
               for X in 2 .. NBr loop
                  declare
                     Any : Boolean := False;
                  begin
                     for B in 0 .. 255 loop
                        if Dsp (B) = X then
                           Append (Buf, Ind & "    case " & Img (B) & ":");
                           Append (Buf, LF);
                           Any := True;
                        end if;
                     end loop;
                     if Any then
                        Append (Buf, Ind & "        goto "
                          & Label & "alt_entry_" & Img (X) & ";");
                        Append (Buf, LF);
                     end if;
                  end;
               end loop;
               Append (Buf, Ind & "    }");
               Append (Buf, LF);
               Append (Buf, Ind & "}");
               Append (Buf, LF);
            end if;

            declare
            --  Adjacent branches that begin with the same elements (`x R | x`, `a b c | a b d`) would
            --  read those elements once for each branch; the first one that fails after them gives
            --  them back and the next reads them again, so a chain of such rules (the levels of an
            --  expression) doubles its work at every level.  HBNF_Lookahead.Factor says which
            --  branches begin alike and what they have in common (a run, which may hold runs in turn);
            --  the elements are read once, then each branch's own rest is tried in the order written:
            --  the same language and the same tree, the shared part read once.
            Skip_Until : Natural := 0;     --  elements up to here belong to a run that was written out
            Pl : constant HBNF_Lookahead.Plan :=
              (if Fork or else Disp then (Units => <>, Top => <>) else HBNF_Lookahead.Factor (Els));
            Run_Seq : Natural := 0;

            --  The top-level node of the plan that begins with alternative Br, 0 if none.
            function Top_At (Br : Natural) return Natural is
               At_Br : Natural := 1;
            begin
               for U of Pl.Top loop
                  if At_Br = Br then
                     return U;
                  end if;
                  At_Br := At_Br + HBNF_Lookahead.Leaves (Pl, U);
               end loop;
               return 0;
            end Top_At;

            --  The node U, reading its elements; Failg is where it goes when none of it matches, with
            --  the position and what was set put back by whoever owns the label.  A run reads the
            --  shared elements once, then tries its kids in turn, each given back to just after them.
            procedure Emit_Node (U : Positive; Failg : String; Top : Boolean := False) is
               Nd : constant HBNF_Lookahead.Unit := Pl.Units (U);
               Binds : constant Boolean := Ctx_On and then Rule_Binds (Owner);
            begin
               if Nd.Kind in HBNF_Lookahead.Leaf then
                  declare
                     Br : constant Natural := Nd.Br;
                  begin
                     if Nd.First <= Nd.Last then
                        Emit_Seq (Owner, Els, Nd.First, Nd.Last, Acc, Buf, Failg, Ind, Ws, Lead_Ws => True);
                     end if;
                     if (Ast_On or else (Owner > 0 and then Is_Choice (Rules (Owner))))
                       and then Natural (Alts.Length) >= Br
                     then
                        Append (Buf, Ind & Acc & "_alt = " & To_String (Alts (Br)) & ";");
                        Append (Buf, LF);
                     end if;
                     if Kind_Prefix /= "" and then Bs (Br).First <= Bs (Br).Last
                       and then Els (Bs (Br).First).Kind = Literal
                     then
                        Append (Buf, Fill ("c_alt_kind",
                          (H ("ind", Ind),
                           H ("acc", Acc),
                           H ("prefix", Kind_Prefix),
                           H ("tag", Tag_Name (Leading_Tags (Els), Els (Bs (Br).First).Lit)))));
                        Append (Buf, LF);
                     end if;
                     Append (Buf, Ind & "goto " & Ok & ";");
                     Append (Buf, LF);
                  end;
                  return;
               end if;
               Run_Seq := Run_Seq + 1;
               declare
                  Id : constant String := Label & "r" & Img (Run_Seq);
               begin
                  Append (Buf, Ind & "size_t pf_" & Id & "_ = 0;");
                  Append (Buf, LF);
                  if Binds then
                     Append (Buf, Ind & "hbnf_mark_t cm_" & Id & "_;");
                     Append (Buf, LF);
                  end if;
                  Emit_Seq (Owner, Els, Nd.First, Nd.Last, Acc, Buf, Failg, Ind, Ws,
                            Lead_Ws => not (Top and then Hoist));
                  Append (Buf, Ind & "pf_" & Id & "_ = p->pos;");
                  Append (Buf, LF);
                  if Binds then
                     Append (Buf, Ind & "cm_" & Id & "_ = hbnf_mark();");
                     Append (Buf, LF);
                  end if;
                  declare
                     Q : Natural := 0;
                     NK : constant Natural := Natural (Nd.Kids.Length);
                  begin
                     for Kid of Nd.Kids loop
                        Q := Q + 1;
                        if Q < NK then
                           declare
                              Fl : constant String := Label & "sfail_" & Id & "_" & Img (Q);
                              Rs : HBNF_Lookahead.Bounds_Vectors.Vector;
                           begin
                              Emit_Node (Kid, "goto " & Fl & ";");
                              --  this kid's rest failed: back to just after the shared part
                              Append (Buf, Fl & ":");
                              Append (Buf, LF);
                              Append (Buf, Ind & "p->pos = pf_" & Id & "_;");
                              if Binds then
                                 Append (Buf, " hbnf_reset (&cm_" & Id & "_);");
                              end if;
                              HBNF_Lookahead.Unit_Ranges (Pl, Kid, Rs);
                              --  (the kid's own shared part too: it is set again by the next kid's)
                              declare
                                 Done : String_Vectors.Vector;
                              begin
                                 for Rg of Rs loop
                                    if Rg.First <= Rg.Last then
                                       for F of Written_Fields (Els, Rg.First, Rg.Last, False) loop
                                          if not Done.Contains (F) then
                                             Done.Append (F);
                                             Append (Buf, " memset(&" & Acc & To_String (F) & ", 0, sizeof "
                                               & Acc & To_String (F) & ");");
                                          end if;
                                       end loop;
                                    end if;
                                 end loop;
                              end;
                              Append (Buf, Clears);
                              Append (Buf, ";");
                              Append (Buf, LF);
                           end;
                        else
                           Emit_Node (Kid, Failg);
                        end if;
                     end loop;
                  end;
               end;
            end Emit_Node;

            begin
            for K in 1 .. N + 1 loop
               if K <= Skip_Until then
                  null;                       --  written out already, with the run it belongs to
               elsif K > N or else Els (K).Kind = Alt then
                  LBr := LBr + 1;
                  if LBr > 1 then
                     Emit_Reset;
                     if Disp and then Entry_Used (LBr) then
                        --  The dispatch target: after the reset, so a branch
                        --  reached by the switch starts with a clean struct.
                        Append (Buf, Label & "alt_entry_" & Img (LBr) & ": ;");
                        Append (Buf, LF);
                     end if;
                  end if;
                  --  a run of branches with a shared beginning is written out once
                  if Bs (LBr).First = LSt and then Top_At (LBr) /= 0
                    and then Pl.Units (Top_At (LBr)).Kind in HBNF_Lookahead.Run
                  then
                     declare
                        U    : constant Positive := Top_At (LBr);
                        Last : constant Natural := LBr + HBNF_Lookahead.Leaves (Pl, U) - 1;
                     begin
                        Emit_Node (U, "goto " & Label & "alt_fail_" & Img (Last) & ";", Top => True);
                        Append (Buf, Label & "alt_fail_" & Img (Last) & ":");
                        Append (Buf, LF);
                        if Ctx_On and then Rule_Binds (Owner) then
                           --  the mark taken where the alternation began is for the branch after the run, if there is one
                           Append (Buf, Ind & "(void) " & To_String (Cx) & ";");
                           Append (Buf, LF);
                        end if;
                        PSt := Bs (Last).First;
                        PEn := Bs (Last).Last;
                        Skip_Until := Bs (Last).Last + 1;
                        LSt := Bs (Last).Last + 2;
                        LBr := Last;
                     end;
                  end if;
                  if Skip_Until >= K then
                     null;                    --  the run covers this branch
                  else
                  Emit_Seq (Owner, Els, LSt, K - 1, Acc, Buf,
                            "goto " & Label & "alt_fail_" & Img (LBr) & ";", Ind,
                            Ws, Lead_Ws => not Hoist);
                  if (Ast_On or else (Owner > 0 and then Is_Choice (Rules (Owner))))
                    and then Natural (Alts.Length) >= LBr
                  then
                     Append (Buf, Ind & Acc & "_alt = "
                       & To_String (Alts (LBr)) & ";");
                     Append (Buf, LF);
                  end if;
                  if Kind_Prefix /= "" and then LSt <= K - 1
                    and then Els (LSt).Kind = Literal
                  then
                     Append (Buf, Fill ("c_alt_kind",
                       (H ("ind", Ind),
                        H ("acc", Acc),
                        H ("prefix", Kind_Prefix),
                        H ("tag",
                          Tag_Name (Leading_Tags (Els), Els (LSt).Lit)))));
                     Append (Buf, LF);
                  end if;
                  --  First match wins: this branch is taken only if the next
                  --  code point can follow the choice.
                  if K <= N and then Els (K).Kind = Alt and then Els (K).Guard /= 0
                  then
                     Append (Buf, Ind & "{ size_t g_sv = p->pos;"
                       & (if Ws then " skip_ws(p);" else "")
                       & " bool g_ok = guard_" & Img (Els (K).Guard)
                       & "(p); p->pos = g_sv; if (!g_ok) goto " & Label
                       & "alt_fail_" & Img (LBr) & "; }");
                     Append (Buf, LF);
                  end if;
                  if Fork then
                     Append (Buf, Ind & "hbnf_fork_used = " & Img (LBr) & ";");
                     Append (Buf, LF);
                  end if;
                  Append (Buf, Ind & "goto " & Ok & ";");
                  Append (Buf, LF);
                  Append (Buf, Label & "alt_fail_" & Img (LBr) & ":");
                  Append (Buf, LF);
                  PSt := LSt;
                  PEn := K - 1;
                  LSt := K + 1;
                  end if;
               end if;
            end loop;
            end;
         end Emit_Linear;
      begin
         Branch_Firsts (Els, Flat, Offs);
         Emit_Linear;
      end Emit_Alternation;

      --  Deferred-number plumbing: a numeric field (`int` / `uN` / `iN`) is
      --  parsed into a `num_<field>` text pointer and converted only at the
      --  branch's commit point, so speculative branches skip the strtol/atoll.

      procedure Emit_Number_Deferrals
        (Nums : String_Vectors.Vector; Buf : in out U; Ind : String) is
      begin
         for N of Nums loop
            Append (Buf, Fill ("c_num_defer",
              (H ("ind", Ind),
               H ("field", C_Field (To_String (N))))));
            Append (Buf, LF);
         end loop;
      end Emit_Number_Deferrals;

      procedure Emit_Number_Converts
        (Nums : String_Vectors.Vector; Acc : String; Check : Boolean;
         Buf : in out U; Ind : String) is
      begin
         for N of Nums loop
            declare
               F : constant String := C_Field (To_String (N));
            begin
               Append (Buf, Fill ("c_num_convert",
                 (H ("ind", Ind),
                  H ("check",
                    (if Check then "if (num_" & F & ") " else "")),
                  H ("acc", Acc),
                  H ("field", F),
                  H ("convert",
                    Scalar_Convert (To_String (N), "num_" & F)))));
            end;
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

      --  A rule with an `%emit` or a `name :: type =` head (RFCPLAN.md step 15).  It is a function
      --  that runs its pattern as written and fills `*out` with its value: no struct, no list
      --  nodes.  Each element is a local named after its rule; an `%emit{ }` is the author's code
      --  at its place, `$$` the rule's value.  A rule runs once on the way to a result (the quiet
      --  first pass) and the emits only there, so the pass that reads a failure again runs none.
      procedure Emit_Valued (Idx : Natural; Buf : in out U; Quiet : Boolean) is
         R   : constant Rule := Rules (Idx);
         RN  : constant String := To_String (R.Name);
         Ws  : constant Boolean := R.Whitespace /= Null_Unbounded_String;
         Lbl : Natural := 0;
         --  The local of the name element generated last, which `$@` stands for
         Last_Name : U;
         --  What the emits change, put back when a part that has run some of them is given up
         --  (`rollback { }`): a mark is the value, and putting it back is one store each.
         Rb : constant String_Vectors.Vector :=
           (if Quiet then Rollback_Items else String_Vectors.Empty_Vector);

         function Save (Tag : String) return String is
            R : U;
         begin
            for K in 1 .. Natural (Rb.Length) loop
               Append (R, "__typeof__(" & To_String (Rb (K)) & ") rb" & Tag & "_" & Img (K) & " = "
                 & To_String (Rb (K)) & "; ");
            end loop;
            return To_String (R);
         end Save;

         function Restore (Tag : String) return String is
            R : U;
         begin
            for K in 1 .. Natural (Rb.Length) loop
               Append (R, To_String (Rb (K)) & " = rb" & Tag & "_" & Img (K) & "; ");
            end loop;
            return To_String (R);
         end Restore;

         --  True while the position is known to be past the blanks already, so the next token
         --  need not skip them again (after a dispatch, which skipped before choosing).
         Skip_Done : Boolean := False;
         Seen : String_Vectors.Vector;
         Look : constant HBNF_Lookahead.Analysis := HBNF_Lookahead.Analyze (Rules);

         procedure Unsupported (What : String) is
         begin
            raise Parse_Error with "rule `" & RN & "` runs an %emit, and " & What
              & " is not generated in such a rule yet";
         end Unsupported;

         function Fresh return String is
         begin
            Lbl := Lbl + 1;
            return Img (Lbl);
         end Fresh;

         --  `$$` is the value the rule is making; `$@` the value of the element just before the
         --  emit, whatever the local is called (a layout writes emits that need it).
         function Code_Of (Text : String) return String is
            Res : U;
            K   : Natural := Text'First;
         begin
            while K <= Text'Last loop
               if K < Text'Last and then Text (K) = '$' and then Text (K + 1) = '@' then
                  if Last_Name = Null_Unbounded_String then
                     Unsupported ("`$@`, which needs a name just before the emit");
                  end if;
                  Append (Res, Last_Name);
                  K := K + 2;
               elsif K < Text'Last and then Text (K) = '$' and then Text (K + 1) = '$' then
                  Append (Res, "(*out)");
                  K := K + 2;
               else
                  Append (Res, Text (K));
                  K := K + 1;
               end if;
            end loop;
            return To_String (Res);
         end Code_Of;

         --  A tree rule fills a struct it takes to be clear (its failure path frees the fields), so
         --  the local for one starts at zero; a token, an enum or a value is only written.
         function Needs_Clear (N : String) return Boolean is
            J : constant Natural := Find (N);
         begin
            return J /= 0 and then not Is_Core (N)
              and then Analyze (Rules, J).Kind not in Scalar | Enum;
         end Needs_Clear;

         --  Does an `%emit` of this rule name Id, as a word of its own?
         function Mentioned (Id : String) return Boolean is
            function In_Code (V : Element_Vectors.Vector) return Boolean is
            begin
               for E of V loop
                  if E.Kind = Block and then E.Op = B_Emit then
                     declare
                        T : constant String := To_String (E.Code);
                     begin
                        for K in T'First .. T'Last - Id'Length + 1 loop
                           if T (K .. K + Id'Length - 1) = Id
                             and then (K = T'First or else not (T (K - 1) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_'))
                             and then (K + Id'Length > T'Last
                                       or else not (T (K + Id'Length) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_'))
                           then
                              return True;
                           end if;
                        end loop;
                     end;
                  elsif E.Kind = Group and then In_Code (E.Items) then
                     return True;
                  end if;
               end loop;
               return False;
            end In_Code;
         begin
            return In_Code (R.Pattern);
         end Mentioned;

         procedure Locals (V : Element_Vectors.Vector) is
         begin
            for E of V loop
               if E.Kind = Group then
                  Locals (E.Items);
               elsif E.Kind = Name then
                  declare
                     N : constant String := To_String (E.Name);
                  begin
                     if not Seen.Contains (E.Name) then
                        Seen.Append (E.Name);
                        --  A variable the emit code names starts at zero, so an alternative that
                        --  did not run leaves it empty; one it never names is only a place for
                        --  the call to put its value.
                        Append (Buf, "    " & C_Type_Of (Rules, N) & " " & C_Field (N) & ";"
                          & (if Mentioned (C_Field (N)) or else Needs_Clear (N)
                             then "  memset(&" & C_Field (N) & ", 0, sizeof " & C_Field (N) & ");"
                             else "") & LF);
                     end if;
                  end;
               end if;
            end loop;
         end Locals;

         procedure Gen (V : Element_Vectors.Vector; F, L : Natural; Fail, Ind : String);

         --  The context operations (`%spaces`, `%col`, `%num`, lookahead, guards) are the
         --  sequence code's: it writes them for one element, the locals standing for the fields.
         procedure Element_Seq (E : Element_Access; Fail, Ind : String) is
         begin
            Emit_Seq (Idx, Element_Vectors.To_Vector (E, 1), 1, 1, "", Buf, Fail, Ind, Ws,
                      Lead_Ws => not Skip_Done);
            Skip_Done := False;
         end Element_Seq;

         --  One occurrence of E.
         procedure One (E : Element_Access; Fail, Ind : String) is
            procedure Skip is
            begin
               if Ws and then not Skip_Done then
                  Append (Buf, Ind & "skip_ws(p);" & LF);
               end if;
               Skip_Done := False;
            end Skip;
         begin
            case E.Kind is
               when Literal =>
                  declare
                     Lit : constant String := To_String (E.Lit);
                     Fn  : constant String :=
                       (if E.No_Case and then Is_Keyword_Lit (Lit) then "expect_word_nocase"
                        elsif E.No_Case then "expect_lit_nocase"
                        elsif Is_Keyword_Lit (Lit) then "expect_word"
                        else "expect_lit");
                  begin
                     Skip;
                     Append (Buf, Ind & "if (!" & Fn & "(p, """ & C_Escape (Lit) & """, "
                       & Img (Lit'Length) & ")) { " & Fail & " }" & LF);
                  end;
               when Name =>
                  declare
                     N : constant String := To_String (E.Name);
                  begin
                     Skip;
                     Last_Name := To_Unbounded_String (C_Field (N));
                     if Is_Core (N) then
                        Append (Buf, Ind & "{ size_t n = " & Scalar_Scan_Fn (Rules, N)
                          & "(p->text, p->pos, p->len); if (!n" & Scalar_Reject (N, "n")
                          & ") { fail(p, """ & Core_Desc (N) & """, 0, p->text + p->pos, 0); "
                          & Fail & " } " & C_Field (N) & " = " & Scalar_Value (N, "n")
                          & "; p->pos += n; }" & LF);
                     else
                        --  the quiet body calls the quiet bodies, which every rule that is called has
                        --  (but not one that puts the contexts back: that keeps its wrapper, and has
                        --  no prototype of its body)
                        Append (Buf, Ind & "if (!" & Rule_Call (RN, E,
                          (if Quiet and then Needs_Parse_Fn (Rules, N)
                             and then not (Ctx_On and then Find (N) > 0 and then Rule_Binds (Find (N)))
                           then "parse_body_" else "parse_rule_") & C_Name (N)
                          & "(p, &" & C_Field (N) & ")")
                          & ") { " & Fail & " }" & LF);
                     end if;
                  end;
               when Group =>
                  Gen (E.Items, 1, Natural (E.Items.Length), Fail, Ind);
               when Char_Range =>
                  if E.Hi > 127 then
                     Element_Seq (E, Fail, Ind);
                     return;
                  end if;
                  Skip;
                  Append (Buf, Ind & "if (p->pos >= p->len || (unsigned char)p->text[p->pos] < "
                    & Img (Natural (E.Lo)) & " || (unsigned char)p->text[p->pos] > "
                    & Img (Natural (E.Hi)) & ") { fail(p, ""a character in the range"", 0, "
                    & "p->text + p->pos, 0); " & Fail & " } p->pos++;" & LF);
               when Block =>
                  if E.Op = B_Emit then
                     --  the code runs in the quiet pass only: the body the pass that reads a
                     --  failure again uses has none
                     if Quiet then
                        Append (Buf, Ind & "{" & LF & Ind & "    "
                          & Code_Of (To_String (E.Code)) & LF & Ind & "}" & LF);
                     end if;
                  else
                     Element_Seq (E, Fail, Ind);
                  end if;
               when others =>
                  Element_Seq (E, Fail, Ind);
            end case;
         end One;

         --  E as often as its bounds say; one that stops short is not an error until the
         --  count is.  A part that fails gives back what it took, and the loop ends.
         --  The next byte says whether E is there: what it begins with is known exactly, is all
         --  ASCII, and E cannot be empty.  (A part whose first byte is not known is entered and,
         --  if it turns out not to be there, its emits are rolled back.)
         function Guardable (E : Element_Access) return Boolean is
            use HBNF_Lookahead;
            Req : constant Element_Access := new HBNF_Grammar.Element'(E.all);
         begin
            Req.Min := 1;
            Req.Max := 1;
            declare
               S : constant Cp_Set := First_Of (Look, Rules, E);
            begin
               return not Is_Empty (S) and then not Has_Any (S) and then not Has_Eoi (S)
                 and then Range_Hi (S, Range_Count (S)) <= 127
                 and then not El_Nullable (Rules, Look.Nullable, Req);
            end;
         end Guardable;

         procedure Elem (E : Element_Access; Fail, Ind : String) is
         begin
            if E.Min = 1 and then E.Max = 1 then
               One (E, Fail, Ind);
               return;
            end if;
            Skip_Done := False;
            declare
               Id : constant String := Fresh;
            begin
               Append (Buf, Ind & "{ size_t cnt" & Id & " = 0;" & LF
                 & Ind & "  for (;;) {" & LF
                 & Ind & "    size_t sv" & Id & " = p->pos;  " & Save ("l" & Id) & LF);
               if E.Max >= 0 then
                  Append (Buf, Ind & "    if (cnt" & Id & " >= " & Img (Natural (E.Max)) & ") break;" & LF);
               end if;
               --  A part that begins with an emit is entered only when the next byte can start
               --  it (the analysis has seen to it that the byte can say): the emit is the first
               --  thing it does, so it must not run on a part that is not there.
               if Quiet and then E.Kind in Name | Group
                 and then HBNF_Compilable.Leads_With_Emit (Rules, Element_Vectors.To_Vector (E, 1))
                 and then Guardable (E)
               then
                  declare
                     Set : constant HBNF_Lookahead.Cp_Set := HBNF_Lookahead.First_Of (Look, Rules, E);
                     Tab : U;
                  begin
                     for C in 0 .. 255 loop
                        declare
                           In_Set : Boolean := False;
                        begin
                           for Q in 1 .. HBNF_Lookahead.Range_Count (Set) loop
                              if C in HBNF_Lookahead.Range_Lo (Set, Q) .. HBNF_Lookahead.Range_Hi (Set, Q) then
                                 In_Set := True;
                              end if;
                           end loop;
                           Append (Tab, (if In_Set and then C <= 127 then "1," else "0,"));
                        end;
                     end loop;
                     if Ws then
                        Append (Buf, Ind & "    skip_ws(p);" & LF);
                     end if;
                     Append (Buf, Ind & "    { static const unsigned char gt_" & Id & "[256] = {" & To_String (Tab)
                       & "}; if (p->pos >= p->len || !gt_" & Id & "[(unsigned char)p->text[p->pos]]) { p->pos = sv"
                       & Id & "; break; } }" & LF);
                     Skip_Done := True;
                  end;
               end if;
               One (E, "{ p->pos = sv" & Id & "; " & Restore ("l" & Id) & "break; }", Ind & "    ");
               Append (Buf, Ind & "    cnt" & Id & "++;" & LF
                 & Ind & "    if (p->pos == sv" & Id & ") break;" & LF
                 & Ind & "  }" & LF);
               if E.Min > 0 then
                  Append (Buf, Ind & "  if (cnt" & Id & " < " & Img (E.Min) & ") { " & Fail & " }" & LF);
               end if;
               Append (Buf, Ind & "}" & LF);
            end;
            Skip_Done := False;
         end Elem;

         --  Elements St .. En of V in order.  An element that a `? ctx`, `%as` or `%num` follows is
         --  taken with it by the sequence code, which notes where the element began.
         procedure Seq_Range (V : Element_Vectors.Vector; St, En : Natural; Fail, Ind : String) is
            K : Natural := St;
         begin
            while K <= En loop
               if V (K).Kind = Block and then V (K).Op = B_Scope then
                  --  `%scope`: what the rest of this sequence binds ends with it
                  declare
                     Sc : constant String := "sc" & Fresh & "_";
                  begin
                     Append (Buf, Ind & "hbnf_mark_t " & Sc & " = hbnf_mark();" & LF);
                     Seq_Range (V, K + 1, En, Fail, Ind);
                     Append (Buf, Ind & "hbnf_reset (&" & Sc & ");" & LF);
                  end;
                  K := En + 1;
               elsif K < En and then V (K + 1).Kind = Block
                 and then V (K + 1).Op in B_Test | B_Not_Test | B_As | B_Num
               then
                  if V (K).Min /= 1 or else V (K).Max /= 1 then
                     Unsupported ("a repeated element that a context test or number follows");
                  end if;
                  Emit_Seq (Idx, V, K, K + 1, "", Buf, Fail, Ind, Ws, Lead_Ws => not Skip_Done);
                  Skip_Done := False;
                  --  a name read with its test is still the element `$@` stands for
                  if V (K).Kind = Name and then not Is_Core (To_String (V (K).Name)) then
                     Last_Name := To_Unbounded_String (C_Field (To_String (V (K).Name)));
                  end if;
                  K := K + 2;
               else
                  Elem (V (K), Fail, Ind);
                  K := K + 1;
               end if;
            end loop;
         end Seq_Range;

         --  V (F .. L): alternatives are tried in order; one that fails gives back its input.
         procedure Gen (V : Element_Vectors.Vector; F, L : Natural; Fail, Ind : String) is
            Alts : Natural := 1;
         begin
            for K in F .. L loop
               if V (K).Kind = Alt then
                  Alts := Alts + 1;
               end if;
            end loop;
            if Alts = 1 then
               Seq_Range (V, F, L, Fail, Ind);
               return;
            end if;
            declare
               Id : constant String := Fresh;
               St : Natural := F;
               N  : Natural := 0;
               Bs : constant HBNF_Lookahead.Bounds_Vectors.Vector := HBNF_Lookahead.Branches (V);
               Sets : array (1 .. Natural (Bs.Length)) of HBNF_Lookahead.Cp_Set;

               --  The alternatives begin with different ASCII characters, none can be empty: the
               --  first character says which one, and the quiet pass goes straight to it.  (The
               --  pass that reads a failure again tries them in order, to record what each wanted.)
               function Dispatchable return Boolean is
                  use HBNF_Lookahead;
                  Null_Branch : Boolean;
               begin
                  if Natural (Bs.Length) /= Alts or else F /= 1 or else L /= Natural (V.Length) then
                     return False;
                  end if;
                  for K in Sets'Range loop
                     Branch_First (Look, Rules, V, Bs (K), Sets (K), Null_Branch);
                     if Null_Branch or else Is_Empty (Sets (K)) or else Has_Any (Sets (K))
                       or else Has_Eoi (Sets (K))
                       or else Range_Hi (Sets (K), Range_Count (Sets (K))) > 127
                     then
                        return False;
                     end if;
                  end loop;
                  for K in Sets'Range loop
                     for J in K + 1 .. Sets'Last loop
                        if not Is_Empty (Meet (Sets (K), Sets (J))) then
                           return False;
                        end if;
                     end loop;
                  end loop;
                  return True;
               end Dispatchable;

               Dispatch : constant Boolean := Quiet and then Dispatchable;
            begin
               Append (Buf, Ind & "{ size_t as" & Id & " = p->pos;  " & Save ("a" & Id) & LF);
               if Dispatch then
                  if Ws and then not Skip_Done then
                     Append (Buf, Ind & "  skip_ws(p);" & LF);
                  end if;
                  Append (Buf, Ind & "  switch (p->pos < p->len ? (unsigned char)p->text[p->pos] : 256) {" & LF);
                  for K in Sets'Range loop
                     for Q in 1 .. HBNF_Lookahead.Range_Count (Sets (K)) loop
                        for Ch in HBNF_Lookahead.Range_Lo (Sets (K), Q) .. HBNF_Lookahead.Range_Hi (Sets (K), Q) loop
                           Append (Buf, Ind & "  case " & Img (Ch) & ": goto br" & Id & "_" & Img (K) & ";" & LF);
                        end loop;
                     end loop;
                  end loop;
                  Append (Buf, Ind & "  default: " & Fail & LF & Ind & "  }" & LF);
               end if;
               declare
                  --  Alternatives that begin alike read the shared elements once, then try their own rests
                  --  in the order written (HBNF_Lookahead.Factor; a run may hold runs).
                  Pl : constant HBNF_Lookahead.Plan := HBNF_Lookahead.Factor (V, F, L, Enable => not Dispatch);
                  NTop : constant Natural := Natural (Pl.Top.Length);
                  Pn : Natural := 0;

                  --  Node U; Failg is where it goes when none of it matches.
                  procedure Node (Un : Positive; Failg : String; Ind2 : String) is
                     Nd : constant HBNF_Lookahead.Unit := Pl.Units (Un);
                  begin
                     if Nd.Kind in HBNF_Lookahead.Leaf then
                        Append (Buf, Ind2 & "{" & LF);
                        Skip_Done := Dispatch;
                        Seq_Range (V, Nd.First, Nd.Last, Failg, Ind2 & "  ");
                        Skip_Done := False;
                        Append (Buf, Ind2 & "  goto done" & Id & ";" & LF);
                        Append (Buf, Ind2 & "}" & LF);
                        return;
                     end if;
                     Pn := Pn + 1;
                     declare
                        Pf : constant String := "pf" & Id & "_" & Img (Pn);
                        Ln : U;
                        Q  : Natural := 0;
                        NK : constant Natural := Natural (Nd.Kids.Length);
                        Mine : constant Natural := Pn;
                     begin
                        Append (Buf, Ind2 & "{" & LF);
                        Seq_Range (V, Nd.First, Nd.Last, Failg, Ind2 & "  ");
                        Ln := Last_Name;
                        Append (Buf, Ind2 & "  size_t " & Pf & " = p->pos;  " & Save ("p" & Id & "_" & Img (Mine)) & LF);
                        for Kid of Nd.Kids loop
                           Q := Q + 1;
                           Last_Name := Ln;
                           if Q < NK then
                              Node (Kid, "goto pn" & Id & "_" & Img (Mine) & "_" & Img (Q) & ";", Ind2 & "  ");
                              Append (Buf, Ind2 & "  pn" & Id & "_" & Img (Mine) & "_" & Img (Q) & ": p->pos = " & Pf & "; "
                                & Restore ("p" & Id & "_" & Img (Mine)) & LF);
                           else
                              Node (Kid, Failg, Ind2 & "  ");
                           end if;
                        end loop;
                        Append (Buf, Ind2 & "}" & LF);
                     end;
                  end Node;
               begin
                  for Tn of Pl.Top loop
                     N := N + 1;
                     declare
                        Last : constant Boolean := N = NTop;
                        Next : constant String := "goto alt" & Id & "_" & Img (N) & ";";
                     begin
                        if Dispatch then
                           Append (Buf, Ind & "  br" & Id & "_" & Img (N) & ": ;" & LF);
                        end if;
                        Node (Tn, (if Last or else Dispatch then Fail else Next), Ind & "  ");
                        if not Last and then not Dispatch then
                           Append (Buf, Ind & "  alt" & Id & "_" & Img (N) & ": p->pos = as"
                             & Id & "; " & Restore ("a" & Id) & LF);
                        end if;
                     end;
                  end loop;
               end;
               Append (Buf, Ind & "  done" & Id & ": ;" & LF & Ind & "}" & LF);
            end;
         end Gen;
      begin
         Append (Buf, "    size_t start_ = p->pos;" & LF);
         Locals (R.Pattern);
         Gen (R.Pattern, 1, Natural (R.Pattern.Length),
              "p->pos = start_; return false;", "    ");
         Append (Buf, "    return true;" & LF);
      end Emit_Valued;

      --  ---- ladders of binary operators ----
      --  A level is a rule `a = b *( op b )`: after the reader has lifted the repetition it is two names, the
      --  operand rule b and the list rule of what is repeated, whose last element is b again.  A level's operand
      --  may be another level, and so on down to a rule that is not one.  The levels are found from the
      --  references alone, so where the rules sit in the file, and what stands between them, does not matter.
      type Bit_Array is array (Natural range <>) of Boolean;

      type Level_Info is record
         Next : Natural := 0;     --  the operand's rule, 0 when the rule is no level
         List : Natural := 0;     --  the list rule of `*( op b )`
      end record;

      function Level (Idx : Natural) return Level_Info is
         R    : constant Rule := Rules (Idx);
         None : constant Level_Info := (0, 0);
      begin
         if not Ladder_On or else Spans_On or else Natural (R.Pattern.Length) /= 2
           or else R.Action_Code /= Null_Unbounded_String or else R.Jet_Code /= Null_Unbounded_String
           or else Is_Choice (R) or else Analyze (Rules, Idx).Kind /= Struct
         then
            return None;
         end if;
         declare
            A : constant Element_Access := R.Pattern (1);
            B : constant Element_Access := R.Pattern (2);
         begin
            if A.Kind /= Name or else B.Kind /= Name or else A.Min /= 1 or else A.Max /= 1
              or else B.Min /= 1 or else B.Max /= 1 or else Is_Core (To_String (A.Name))
              or else Is_Back (Idx, To_String (A.Name))      --  a pointer, not a struct in place
            then
               return None;
            end if;
            declare
               NJ : constant Natural := Find (To_String (A.Name));
               LJ : constant Natural := Find (To_String (B.Name));
            begin
               if NJ = 0 or else LJ = 0 or else NJ = Idx or else Analyze (Rules, LJ).Kind /= List
                 or else Natural (Rules (LJ).Pattern.Length) /= 1
               then
                  return None;
               end if;
               declare
                  E : constant Element_Access := Rules (LJ).Pattern (1);
               begin
                  if E.Kind /= Group or else E.Min /= 0 or else E.Max >= 0
                    or else Natural (E.Items.Length) < 2
                  then
                     return None;
                  end if;
                  declare
                     L : constant Element_Access := E.Items (E.Items.Last_Index);
                  begin
                     if L.Kind /= Name or else L.Name /= A.Name or else L.Min /= 1 or else L.Max /= 1 then
                        return None;
                     end if;
                  end;
               end;
               return (Next => NJ, List => LJ);
            end;
         end;
      end Level;

      type Chain_Array is array (1 .. 64) of Natural;

      --  The levels from Idx down: C (1) is Idx, C (2) its operand when that is a level held by value, and so
      --  on; Opd is the rule parsed as the first operand at the bottom.  M = 0 when Idx is no level.
      procedure Chain (Idx : Natural; C : out Chain_Array; M : out Natural; Opd : out Natural) is
         Cur : Natural := Idx;
         Lv  : Level_Info;
      begin
         C := [others => 0];
         M := 0;
         Opd := 0;
         loop
            Lv := Level (Cur);
            exit when Lv.Next = 0;
            M := M + 1;
            C (M) := Cur;
            Opd := Lv.Next;
            exit when M = C'Last
              or else Level (Lv.Next).Next = 0
              or else Is_Back (Cur, To_String (Rules (Cur).Pattern (1).Name))
              or else (for some K in 1 .. M => C (K) = Lv.Next);
            Cur := Lv.Next;
         end loop;
      end Chain;

      function Hex16 (Bits : Bit_Array) return String is
         Digits_Hex : constant String := "0123456789ABCDEF";
         R : String (1 .. 16);
      begin
         for J in 0 .. 15 loop
            declare
               V : Natural := 0;
            begin
               for I in 0 .. 3 loop
                  if Bits (Bits'First + 4 * J + I) then
                     V := V + 2 ** I;
                  end if;
               end loop;
               R (16 - J) := Digits_Hex (V + 1);
            end;
         end loop;
         return R;
      end Hex16;

      --  The start of the body of level Idx for the first pass: its first operand into the innermost
      --  struct, one look at the next byte, and the lists of the levels from the tightest out only if an
      --  operator of the ladder can begin there.  The second pass, which reads a failure again, takes the
      --  plain body that follows, so the rule paths of its messages are what they were.
      procedure Emit_Ladder (Idx : Natural; Ws : Boolean; CN : String; Buf : in out U) is
         C    : Chain_Array;
         M    : Natural;
         Opd  : Natural;
         Bits : Bit_Array (0 .. 127) := [others => False];
         Ok   : Boolean := True;
         Path : array (1 .. 64) of Unbounded_String;
         Fail : constant String :=
           "{ free_" & CN & "_fields(&r); memset(&r, 0, sizeof r); p->pos = save; return false; }";
      begin
         Chain (Idx, C, M, Opd);
         if M = 0 then
            return;
         end if;
         for K in 1 .. M loop
            declare
               E   : constant Element_Access := Rules (Level (C (K)).List).Pattern (1);
               Req : constant Element_Access := new HBNF_Grammar.Element'(E.all);
            begin
               Req.Min := 1;
               Req.Max := 1;
               declare
                  S : constant HBNF_Lookahead.Cp_Set := HBNF_Lookahead.First_Of (La, Rules, Req);
               begin
                  if HBNF_Lookahead.Is_Empty (S) or else HBNF_Lookahead.Has_Any (S)
                    or else HBNF_Lookahead.Has_Eoi (S)
                    or else HBNF_Lookahead.El_Nullable (Rules, La.Nullable, Req)
                  then
                     Ok := False;
                  else
                     for J in 1 .. HBNF_Lookahead.Range_Count (S) loop
                        if HBNF_Lookahead.Range_Hi (S, J) > 127 then
                           Ok := False;
                        else
                           for B in HBNF_Lookahead.Range_Lo (S, J) .. HBNF_Lookahead.Range_Hi (S, J) loop
                              Bits (B) := True;
                           end loop;
                        end if;
                     end loop;
                  end if;
               end;
            end;
         end loop;
         if not Ok then
            return;
         end if;
         Path (1) := To_Unbounded_String ("r");
         for K in 2 .. M loop
            Path (K) := Path (K - 1) & "." & C_Field (To_String (Rules (C (K)).Name));
         end loop;
         declare
            Lo : constant String := Hex16 (Bits (0 .. 63));
            Hi : constant String := Hex16 (Bits (64 .. 127));
            Skip : constant String := (if Ws then "        skip_ws(p);" & LF else "");
         begin
            Append (Buf, "    /* a ladder of " & Img (M) & " level" & (if M = 1 then "" else "s")
              & ": one look past the first operand */" & LF);
            Append (Buf, "    if (p->quiet) {" & LF);
            Append (Buf, Skip);
            Append (Buf, "        if (!parse_rule_" & C_Name (To_String (Rules (Opd).Name)) & "(p, &"
              & To_String (Path (M)) & "." & C_Field (To_String (Rules (Opd).Name)) & ")) " & Fail & LF);
            Append (Buf, Skip);
            Append (Buf, "        if (p->pos >= p->len) return true;" & LF);
            Append (Buf, "        { unsigned b_ = (unsigned char)p->text[p->pos];" & LF);
            Append (Buf, "          if (b_ >= 128 || !(((b_ < 64 ? 0x" & Lo & "ULL : 0x" & Hi
              & "ULL) >> (b_ & 63)) & 1ULL)) return true; }" & LF);
            for K in reverse 1 .. M loop
               Append (Buf, Skip);
               Append (Buf, "        if (!parse_rule_" & C_Name (To_String (Rules (Level (C (K)).List).Name))
                 & "(p, &" & To_String (Path (K)) & "."
                 & C_Field (To_String (Rules (Level (C (K)).List).Name)) & ")) " & Fail & LF);
            end loop;
            Append (Buf, "        return true;" & LF);
            Append (Buf, "    }" & LF);
         end;
      end Emit_Ladder;

      procedure Emit_Rule_Parser (Idx : Natural; Buf : in out U) is
         R  : constant Rule := Rules (Idx);
         P  : constant Element_Vectors.Vector := R.Pattern;
         NM : constant String := To_String (R.Name);
         CN : constant String := C_Name (NM);
         Is_List : constant Boolean := Natural (P.Length) = 1
           and then (P (1).Min /= 1 or else P (1).Max /= 1);
         Is_Enum : constant Boolean := not Is_List and then Is_Pure_Literal_Alt (P);
         SU : constant String := (if not Is_List then Scalar_Union_Type (P) else "");
         Ws : constant Boolean := R.Whitespace /= Null_Unbounded_String;
      begin
         if Emit_Value_Type (R) /= "" then
            Emit_Valued (Idx, Buf, True);
            return;
         end if;
         if R.Jet_Code /= Null_Unbounded_String then
            --  A jet: run its hand-written scanner and yield the matched text.
            Append (Buf, Fill ("c_rule_jet",
              (H ("scan", "jet_" & C_Name (NM)),
               H ("val", (if Views_On then "hbnf_mkstr(p->text + p->pos, n)"
                          else "hbnf_str_append(p->text + p->pos, n)")),
               H ("desc", "a " & NM))));
            Append (Buf, LF);
            return;
         end if;
         if Is_Char_Rule (Rules, NM) then
            --  A character-level rule: run its scanner and yield the text.
            --  A scanner that matches nothing fails the rule, unless the rule
            --  is a single `*X`: a run that may be empty (`*LF`) matches the
            --  empty string, and the phrase rule that named it goes on.
            Append (Buf, Fill
              ((if (Natural (P.Length) = 1 and then P (1).Min = 0)
                   or else Null_Flags (Idx)
                then "c_rule_scan_opt" else "c_rule_jet"),
               (H ("scan", "scan_" & C_Name (NM)),
                --  A hidden rule is matched and keeps nothing: its value is the
                --  empty string, which costs no allocation.
                H ("val", (if Is_Hidden (NM) then (if Views_On then "(hbnf_str)0" else """""")
                           elsif Views_On then "hbnf_mkstr(p->text + p->pos, n)"
                           else "hbnf_str_append(p->text + p->pos, n)")),
                H ("desc", NM))));
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
               if Keeps_Tail (NM) then
                  Append (Buf, "    " & L_Init ("&head", Rule => NM));
               else
                  --  the list is built with a tail of its own, and stored with its head alone
                  Append (Buf, "    struct " & Pfx & C_Tag (NM) & " *bh_ = NULL, **bt_ = &bh_;");
               end if;
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
               --  The node of an iteration is taken from the arena before the iteration is known to succeed,
               --  and the iteration that ends the list does not: its node, and whatever it read into it, is
               --  garbage that the arena would keep for the life of the tree.  Where the arena stood is
               --  noted, and it goes back there if the last iteration was not kept.
               Append (Buf, "    hbnf_chunk *ac_ = NULL; size_t au_ = 0; int open_ = 0;");
               Append (Buf, LF);
               --  The loop stops at the end of the text, unless what it repeats
               --  can match nothing: then an iteration there is still one
               --  (`1*x` over an empty `x` is satisfied by no input at all).
               declare
                  At_End : constant String :=
                    (if Repeated_Body_Nullable (Rules, E) then ""
                     else "p->pos < p->len");
               begin
                  if Max >= 0 then
                     Append (Buf, "    while ("
                       & (if At_End = "" then "" else At_End & " && ")
                       & "count < " & Img (Natural (Max)) & ") {");
                  else
                     Append (Buf, "    while ("
                       & (if At_End = "" then "1" else At_End) & ") {");
                  end if;
               end;
               Append (Buf, LF);
               Append (Buf, "        ac_ = hbnf_arena; au_ = ac_ ? ac_->used : 0; open_ = 1;");
               Append (Buf, LF);
               Append (Buf, "        " & C_Type_Name (NM) & " *nn ="
                 & " (" & C_Type_Name (NM) & " *)hbnf_alloc(sizeof(*nn));");
               Append (Buf, LF);
               Append (Buf, "        if (!nn) hbnf_oom();");
               Append (Buf, LF);
               Append (Buf, "        size_t save = p->pos;");
               if Ctx_On and then Rule_Binds (Idx) then
                  Append (Buf, LF);
                  Append (Buf, "        hbnf_mark_t lm_;  lm_ = hbnf_mark();");
               end if;
               if Spans_On then
                  Append (Buf, LF);
                  Append (Buf, "        " & Span_Start (Ws, "nn->", "save"));
               end if;
               Append (Buf, LF);
               --  Only the two template paths below need the skip here; the
               --  Emit_Alternation paths lead with it themselves (Emit_Seq)
               --  or hoist it over the branches (Emit_Linear), so emitting
               --  it for them too left two skip_ws calls in a row.
               if Ws and then E.Kind = Name then
                  Append (Buf, "        skip_ws(p);");
                  Append (Buf, LF);
               end if;
               Emit_Number_Deferrals (Nums, Buf, "        ");
               if E.Kind = Name and then Is_Core (To_String (E.Name)) then
                  --  A list of a core type (`1*word`): scan it in place;
                  --  there is no parse_rule_ function for a core type.
                  declare
                     NM : constant String := To_String (E.Name);
                  begin
                     Append (Buf, Fill ("c_rule_list_core",
                       (H ("scan", Scalar_Scan_Fn (Rules, NM)),
                        H ("reject", Scalar_Reject (NM, "n")),
                        H ("field", C_Field (NM)),
                        H ("expr", Scalar_Value (NM, "n")),
                        H ("desc", Core_Desc (NM)))));
                  end;
                  Append (Buf, LF);
               elsif E.Kind = Name then
                  Append (Buf, Fill ("c_rule_list_name",
                    (1 => H ("call", Rule_Call
                       (To_String (R.Name), E,
                        "parse_rule_" & C_Name (To_String (E.Name))
                        & "(p, &nn->" & C_Field (To_String (E.Name)) & ")")))));
                  Append (Buf, LF);
               elsif R.Left_Bases > 0 then
                  --  Left recursion, as a loop: the first entry is a base,
                  --  each later one a tail.  A tail sets its kind; the
                  --  base's stays 0, <CN>_BASE.
                  declare
                     Tags : constant String_Vectors.Vector := List_Tags (R);
                     Free : constant String := "free_" & CN & "_fields(nn)";
                     Clears : constant String := Num_Clears (Nums);
                  begin
                     Append (Buf, "        if (count == 0) {");
                     Append (Buf, LF);
                     Emit_Alternation
                       (Idx, Base_Branches (R), "nn->", Free, Clears, "have", "",
                        Buf, "            ", Label => "base_", Ws => Ws,
                        Alts => Alt_Idents (CN, Base_Branches (R)));
                     Append (Buf, "            "
                       & (if Ctx_On and then Rule_Binds (Idx) then "hbnf_reset (&lm_); " else "")
                       & "p->pos = save; break;");
                     Append (Buf, LF);
                     Append (Buf, "        }");
                     Append (Buf, LF);
                     Emit_Alternation
                       (Idx, Tail_Branches (R), "nn->", Free, Clears, "have",
                        (if Tags.Is_Empty then "" else C_Ident (CN)),
                        Buf, "        ", Ws => Ws,
                        Alts => Alt_Idents
                          (CN, Tail_Branches (R),
                           Natural (Alt_Labels (Base_Branches (R)).Length) + 1));
                  end;
               else
                  declare
                     Tags : constant String_Vectors.Vector :=
                       Leading_Tags (E.Items);
                  begin
                     Emit_Alternation
                       (Idx, E.Items, "nn->",
                        "free_" & CN & "_fields(nn)", Num_Clears (Nums),
                        "have",
                        (if Tags.Is_Empty then "" else C_Ident (CN)),
                        Buf, "        ", Ws => Ws,
                        Alts => Rule_Alts (R, True));
                  end;
               end if;
               Append (Buf, "        "
                 & (if Ctx_On and then Rule_Binds (Idx) then "hbnf_reset (&lm_); " else "")
                 & "p->pos = save; break;");
               Append (Buf, LF);
               Append (Buf, "have:");
               Append (Buf, LF);
               if Spans_On then
                  Append (Buf, "        nn->_end = p->pos;");
                  Append (Buf, LF);
               end if;
               Emit_Number_Converts (Nums, "nn->", True, Buf, "        ");
               if R.Action_Code /= Null_Unbounded_String then
                  Append (Buf, Fill ("c_rule_line",
                    (H ("ind", "        "),
                     H ("acc", "nn->"))));
                  Append (Buf, LF);
               end if;
               if Keeps_Tail (NM) then
                  Append (Buf, "        " & L_Append ("&head", "nn", Rule => NM));
               else
                  Append (Buf, "        *bt_ = nn; bt_ = &(nn)->_link;");
               end if;
               Append (Buf, LF);
               Append (Buf, "        open_ = 0;");
               Append (Buf, LF);
               if Bounded then
                  Append (Buf, "        count++;");
                  Append (Buf, LF);
               end if;
               --  What is repeated can match nothing: an iteration that did
               --  not advance would match the same nothing again, forever.
               if Repeated_Body_Nullable (Rules, E) then
                  Append (Buf, "        if (p->pos == save) break;");
                  Append (Buf, LF);
               end if;
               Append (Buf, "    }");
               Append (Buf, LF);
               --  (the arena hands out memory it cleared once, so what goes back is cleared again)
               Append (Buf, "    if (open_ && ac_ && hbnf_arena == ac_) { memset (ac_->data + au_, 0, ac_->used - au_); ac_->used = au_; }");
               Append (Buf, LF);
               if E.Min > 0 then
                  --  The root's free_ also frees the arena, which the
                  --  error message still reads: free just the nodes there.
                  if Idx = 1 then
                     Append (Buf, "    if (count < " & Img (E.Min) & ") { "
                       & C_Type_Name (NM) & " *dn = " & L_First ("&head", Rule => NM)
                       & ", *dx; while (dn) { dx = " & L_Next ("dn", Rule => NM)
                       & "; free_" & CN & "_fields(dn); dn = dx; }"
                       & " p->pos = start; return false; }");
                  else
                     Append (Buf, "    if (count < " & Img (E.Min) & ") { "
                       & (if Keeps_Tail (NM) then "" else "head.head = bh_; ")
                       & "free_" & CN & "(&head); p->pos = start; return false; }");
                  end if;
                  Append (Buf, LF);
               end if;
               if Keeps_Tail (NM) then
                  --  the head is copied out, and an empty list's tail pointed into the copy's frame
                  Append (Buf, "    *out = head; "
                    & (if Has_Listops then "" else L_Relink ("out", Rule => NM) & " ")
                    & "return true;");
               else
                  Append (Buf, "    head.head = bh_; *out = head; return true;");
               end if;
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

               --  Each alternative matches its literal at pos: a keyword by the
               --  `word` scanner (so `in` never matches `input`), any other
               --  literal by its bytes.
               Append (Buf, "    if (p->pos >= p->len) { fail(p, ""a " & CN
                 & """, 0, ""end of input"", 0); return false; }");
               Append (Buf, LF);
               declare
                  St     : Natural := 1;
                  Branch : Natural := 0;
               begin
                  for K in 1 .. Natural (P.Length) + 1 loop
                     if K > Natural (P.Length) or else P (K).Kind = Alt then
                        if St <= K - 1 and then P (St).Kind = Literal then
                           declare
                              L  : constant String := To_String (P (St).Lit);
                              NL : constant Natural := L'Length;
                              Fn : constant String :=
                                (if Is_Keyword_Lit (L) then Word_Scanner (Rules)
                                 else "");
                           begin
                              Append (Buf, (if Branch = 0 then "    if ("
                                            else "    else if ("));
                              if Fn /= "" then
                                 Append (Buf, "HBNF_WORD_AT(p, " & Fn & ") == "
                                   & Img (NL) & " && ");
                              else
                                 Append (Buf, "p->pos + " & Img (NL)
                                   & " <= p->len && ");
                              end if;
                              Append (Buf, (if P (St).No_Case then "strncasecmp"
                                            elsif Fn /= "" then "memcmp"
                                            else "strncmp")
                                & "(p->text + p->pos, """
                                & C_Escape (L) & """, " & Img (NL) & ") == 0) {");
                              Append (Buf, LF);
                              Append (Buf, "        p->pos += " & Img (NL)
                                & "; *out = " & C_Ident (NM) & "_"
                                & To_String (Names (Branch + 1))
                                & "; return true; }");
                              Append (Buf, LF);
                              Branch := Branch + 1;
                           end;
                        end if;
                        St := K + 1;
                     end if;
                  end loop;
               end;
               Append (Buf, "    else { fail(p, """);
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
               Append (Buf, """, 0, p->text + p->pos, 0); return false; }");
               Append (Buf, LF);
            end;
         elsif Natural (P.Length) = 1 and then P (1).Kind = Name then
            --  A scalar alias: scan a core scalar, or delegate to the rule.
            if Is_Core (To_String (P (1).Name)) then
               declare
                  PN : constant String := To_String (P (1).Name);
               begin
                  Append (Buf, Fill ("c_rule_alias_core",
                    (H ("scan", Scalar_Scan_Fn (Rules, PN)),
                     H ("reject", Scalar_Reject (PN, "n")),
                     H ("desc", Core_Desc (PN)),
                     H ("expr", Scalar_Value (PN, "n")))));
               end;
               Append (Buf, LF);
            elsif HBNF_Grammar.Except_Operand (NM) /= "" then
               --  `X = A - B` with a phrase on a side: parse A; then try B on
               --  exactly the text A matched (the input ends where A did, and B
               --  must end there too).  If it does, X does not match.
               declare
                  A  : constant String := To_String (P (1).Name);
                  B  : constant String := HBNF_Grammar.Except_Operand (NM);
                  JB : constant Natural := Find (Rules, B);
                  Ty : constant String := Out_Type (JB);   --  "T *out"
                  Decl : constant String := Ty (Ty'First .. Ty'Last - 5);

                  --  The statement that releases a value of rule Name at Addr.
                  function Free_Of (Name, Addr : String) return String is
                     T : constant String := Alias_Target (Rules, Name);
                     J : constant Natural := Find (Rules, T);
                  begin
                     if J = 0 then
                        return "";
                     end if;
                     case Analyze (Rules, J).Kind is
                        when Struct =>
                           return "free_" & C_Name (T) & "_fields(" & Addr & ");";
                        when List =>
                           return "free_" & C_Name (T) & "(" & Addr & ");";
                        when others =>
                           return "";
                     end case;
                  end Free_Of;
               begin
                  Append (Buf, "    size_t save = p->pos;" & LF);
                  Append (Buf, "    if (!parse_rule_" & C_Name (A)
                    & "(p, out)) return false;" & LF);
                  Append (Buf, "    {" & LF);
                  Append (Buf, "        size_t end = p->pos;" & LF);
                  Append (Buf, "        " & Decl & " tmp; parser_t keep = *p;"
                    & " bool ok, same;" & LF);
                  Append (Buf, "        memset(&tmp, 0, sizeof tmp);" & LF);
                  Append (Buf, "        p->pos = save; p->len = end;" & LF);
                  Append (Buf, "        ok = parse_rule_" & C_Name (B)
                    & "(p, &tmp);" & LF);
                  Append (Buf, "        same = ok && p->pos == end;" & LF);
                  if Free_Of (B, "&tmp") /= "" then
                     Append (Buf, "        if (ok) { " & Free_Of (B, "&tmp")
                       & " }" & LF);
                  end if;
                  Append (Buf, "        *p = keep;" & LF);
                  Append (Buf, "        if (same) {" & LF);
                  if Free_Of (A, "out") /= "" then
                     Append (Buf, "            " & Free_Of (A, "out") & LF);
                  end if;
                  Append (Buf, "            p->pos = save;" & LF);
                  Append (Buf, "            fail(p, ""`" & A
                    & "` that is not `" & B
                    & """, 0, p->text + save, 0);" & LF);
                  Append (Buf, "            return false;" & LF);
                  Append (Buf, "        }" & LF);
                  Append (Buf, "    }" & LF);
                  Append (Buf, "    return true;" & LF);
               end;
            else
               Append (Buf, Fill ("c_rule_alias_ref",
                 (1 => H ("call", Rule_Call
                    (To_String (R.Name), P (1),
                     "parse_rule_" & C_Name (To_String (P (1).Name))
                     & "(p, out)")))));
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
                              Append (Buf, "    { size_t n = "
                                & Scalar_Scan_Fn (Rules, To_String (E.Name))
                                & "(p->text, p->pos, p->len); if (n"
                                & Scalar_Guard (To_String (E.Name), "n")
                                & ") { *out = "
                                & Scalar_Value (To_String (E.Name), "n")
                                & "; p->pos += n; return true; } }");
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
            Append (Buf, "    fail(p, ""a " & NM & """, 0, p->text + p->pos, 0);");
            Append (Buf, LF);
            Append (Buf, "    return false;");
            Append (Buf, LF);
         elsif Natural (P.Length) = 1 and then P (1).Kind = Literal then
            --  A scalar that is a single literal (`ne = "!="`): match it and
            --  yield its text, as a char rule would.  (Not a char rule itself
            --  — no character class anchors it — so it is read here.)
            declare
               L  : constant String := To_String (P (1).Lit);
               Fn : constant String :=
                 (if P (1).No_Case and then Is_Keyword_Lit (L)
                  then "expect_word_nocase"
                  elsif P (1).No_Case then "expect_lit_nocase"
                  elsif Is_Keyword_Lit (L) then "expect_word"
                  else "expect_lit");
            begin
               Append (Buf, "    size_t start = p->pos;");
               Append (Buf, LF);
               Append (Buf, "    if (!" & Fn & "(p, """ & C_Escape (L)
                 & """, " & Img (L'Length) & ")) return false;");
               Append (Buf, LF);
               Append (Buf, "    *out = "
                 & (if Views_On then "hbnf_mkstr(p->text + start, " & Img (L'Length) & ");"
                    else "hbnf_str_append(p->text + start, " & Img (L'Length) & ");"));
               Append (Buf, LF);
               Append (Buf, "    return true;");
               Append (Buf, LF);
            end;
         elsif Has_Alt (P) then
            --  A struct alternation: try each branch with backtracking.
            declare
               Nums : constant String_Vectors.Vector := Numeric_Fields (P);
            begin
               Append (Buf, "    size_t save = p->pos;");
               Append (Buf, LF);
               --  The rule fills its caller's output directly: callers hand over a cleared
               --  value, and a rule that fails clears what it wrote.  No local copy, no
               --  clearing of it, no copying it out.
               Append (Buf, LF & "#define r (*out)" & LF);
               if Spans_On then
                  Append (Buf, "    " & Span_Start (Ws, "r.", "save"));
                  Append (Buf, LF);
               end if;
               Emit_Number_Deferrals (Nums, Buf, "    ");
               Emit_Alternation (Idx, P, "r.",
                                 "free_" & CN & "_fields(&r)", Num_Clears (Nums),
                                 "ok",
                                 (if Leading_Tags (P).Is_Empty then "" else C_Ident (CN)),
                                 Buf, Ws => Ws,
                                 Alts => Rule_Alts (R, False),
                                 Fork => Is_Forked (Idx));
               --  The last branch failed: free what it built (a list it
               --  had filled before a later token failed), as each
               --  earlier branch's failure does.
               Append (Buf, "    p->pos = save; free_" & CN
                 & "_fields(&r); memset(&r, 0, sizeof r); return false;");
               Append (Buf, LF);
               Append (Buf, "ok:");
               Append (Buf, LF);
               if Spans_On then
                  Append (Buf, "    r._end = p->pos;");
                  Append (Buf, LF);
               end if;
               Emit_Number_Converts (Nums, "r.", True, Buf, "    ");
               if R.Action_Code /= Null_Unbounded_String then
                  Append (Buf, Fill ("c_rule_line",
                    (H ("ind", "    "),
                     H ("acc", "r."))));
                  Append (Buf, LF);
               end if;
               Append (Buf, "    return true;");
               Append (Buf, LF);
            end;
         else
            --  A struct sequence: match literals and references in order.
            declare
               Nums : constant String_Vectors.Vector := Numeric_Fields (P);
            begin
               Append (Buf, "    size_t save = p->pos;");
               Append (Buf, LF);
               --  The rule fills its caller's output directly: callers hand over a cleared
               --  value, and a rule that fails clears what it wrote.  No local copy, no
               --  clearing of it, no copying it out.
               Append (Buf, LF & "#define r (*out)" & LF);
               if Spans_On and then Analyze (Rules, Idx).Kind = Struct then
                  Append (Buf, "    " & Span_Start (Ws, "r.", "save"));
                  Append (Buf, LF);
               end if;
               Emit_Number_Deferrals (Nums, Buf, "    ");
               if Nums.Is_Empty then
                  Emit_Ladder (Idx, Ws, CN, Buf);
               end if;
               --  On failure, free what the sequence built so far (its
               --  lists): the caller only restores the position.  The
               --  _fields variant, since the root's free_ also frees the
               --  arena, which the error message still reads.
               Emit_Seq (Idx, P, 1, Natural (P.Length), "r.", Buf,
                         (if Analyze (Rules, Idx).Kind = Struct
                          then "free_" & CN & "_fields(&r); "
                          else "")
                         & "memset(&r, 0, sizeof r); p->pos = save; return false;",
                         Ws => Ws);
               if Spans_On and then Analyze (Rules, Idx).Kind = Struct then
                  Append (Buf, "    r._end = p->pos;");
                  Append (Buf, LF);
               end if;
               Emit_Number_Converts (Nums, "r.", False, Buf, "    ");
               if R.Action_Code /= Null_Unbounded_String then
                  Append (Buf, Fill ("c_rule_line",
                    (H ("ind", "    "),
                     H ("acc", "r."))));
                  Append (Buf, LF);
               end if;
               Append (Buf, "    return true;");
               Append (Buf, LF);
            end;
         end if;
      end Emit_Rule_Parser;

      --  A rule with an action jet gets a bind walk; without one the walk is
      --  dead code, so it is emitted only when some rule has an action.
      Has_Action : constant Boolean :=
        Hosted_Actions
        or else (for some I in 1 .. N =>
                   Rules (I).Action_Code /= Null_Unbounded_String);

      --  The root is `doc = rule`, an alias of a bit rule: its actions run
      --  from the entry point, as the bind walk would.
      Wire_Alias_Root : constant String :=
        (if Hosted_Actions and then Natural (Rules (1).Pattern.Length) = 1
           and then Rules (1).Pattern (1).Kind = Name
           and then Rules (1).Pattern (1).Min = 1
           and then Rules (1).Pattern (1).Max = 1
           and then HBNF_Grammar.Is_Wire_Rule
                      (To_String (Rules (1).Pattern (1).Name))
         then C_Name (To_String (Rules (1).Pattern (1).Name)) else "");

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
         --  A char-model parse of one rule over s[0..len): returns whether
         --  the rule matched the whole text.
         procedure Whole (Fn, Name, Ret : String) is
            J    : constant Natural := Find (Name);
            T    : constant String := Alias_Target (Rules, Name);
            K    : constant Natural := Find (T);
            Decl : constant String := Out_Type (J);
         begin
            Line ("static " & Ret & Fn & "(const char *s, size_t len) {");
            Line ("    parser_t p = { s, len, 0, (size_t)-1, 0, 0, NULL,"
                  & " NULL, 0, 0 };");
            Line ("    " & Decl (Decl'First .. Decl'Last - 4) & "v;");
            Line ("    bool whole;");
            Line ("");
            Line ("    memset(&v, 0, sizeof v);");
            Line ("    whole = parse_rule_" & C_Name (Name) & "(&p, &v);");
            Line ("    if (whole) { "
                 & (if Whitespace_Rule_Name (Rules) = Null_Unbounded_String
                    then "" else "skip_ws(&p); ")
                 & "whole = p.pos == p.len; }");
            if K /= 0 and then Analyze (Rules, K).Kind in Struct | List then
               Line ("    free_" & C_Name (T) & "(&v);");
            end if;
            Line ("    return whole;");
            Line ("}");
            Line ("");
         end Whole;

         --  The last non-blank string a rule names: the filename the includes
         --  rule read, copied out of the arena into the caller's heap.
         procedure Include_Name is
            J    : constant Natural := Find (HBNF_Grammar.Includes_Rule);
            T    : constant String := Alias_Target (Rules, HBNF_Grammar.Includes_Rule);
            K    : constant Natural := Find (T);
            Info : constant Rule_Info := Analyze (Rules, K);
            Decl : constant String := Out_Type (J);
         begin
            if Info.Kind = Struct and then not Info.Members.Is_Empty then
               declare
                  Fld : constant String := C_Field (To_String (Info.Members (1).Name));
               begin
                  Line ("static char *hbnf_include_name(const char *s,"
                        & " size_t len) {");
                  Line ("    parser_t p = { s, len, 0, (size_t)-1, 0, 0, NULL,"
                        & " NULL, 0, 0 };");
                  Line ("    " & Decl (Decl'First .. Decl'Last - 4) & "v;");
                  Line ("    char *r = NULL;");
                  Line ("    memset(&v, 0, sizeof v);");
                  Line ("    if (parse_rule_" & C_Name (T) & "(&p, &v)) {");
                  if Whitespace_Rule_Name (Rules) /= Null_Unbounded_String then
                     Line ("        skip_ws(&p);");
                  end if;
                  Line ("        if (p.pos == p.len) r = hbnf_strndup(v."
                        & Fld & ", strlen(v." & Fld & "));");
                  Line ("    }");
                  Line ("    free_" & C_Name (T) & "(&v);");
                  Line ("    return r;");
                  Line ("}");
                  Line ("");
               end;
            else
               Line ("static char *hbnf_include_name(const char *s,"
                     & " size_t len) {");
               Line ("    (void)s; (void)len; return NULL;");
               Line ("}");
               Line ("");
            end if;
         end Include_Name;
      begin
         Line ("");
         Line ("/* ---- statements: the grammar's side of the driver ---- */");
         Line ("static void hbnf_part_init(" & RH & " *h) { "
               & L_Init ("h", Rule => To_String (Rules (1).Name)) & " }");
         Line ("");
         Line ("/* Move a statement's entries to the end of the config. */");
         Line ("static void hbnf_part_move(" & RH & " *dst, " & RH
               & " *src) {");
         Line ("    " & RE & " *n = " & L_First ("src", Rule => To_String (Rules (1).Name)) & ", *next;");
         Line ("    while (n) {");
         Line ("        next = " & L_Next ("n", Rule => To_String (Rules (1).Name)) & ";");
         Line ("        " & L_Append ("dst", "n", Rule => To_String (Rules (1).Name)));
         Line ("        n = next;");
         Line ("    }");
         Line ("    " & L_Init ("src", Rule => To_String (Rules (1).Name)));
         Line ("}");
         Line ("");
         Line ("/* A failed statement's entries go; the strings they point to"
               & " stay in the");
         Line ("   arena with the rest of the config's. */");
         Line ("static void hbnf_part_drop(" & RH & " *h) {");
         Line ("    " & RE & " *n = " & L_First ("h", Rule => To_String (Rules (1).Name)) & ", *next;");
         Line ("    while (n) {");
         Line ("        next = " & L_Next ("n", Rule => To_String (Rules (1).Name)) & ";");
         Line ("        free_" & RC & "_fields(n);");
         Line ("        n = next;");
         Line ("    }");
         Line ("    " & L_Init ("h", Rule => To_String (Rules (1).Name)));
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
            Line ("/* The macro driver's copy-out helper, defined below. */");
            Line ("static char *hbnf_strndup(const char *s, size_t n);");
            Line ("");
         end if;
         if HBNF_Grammar.Includes_Rule /= "" then
            Line ("/* `includes " & HBNF_Grammar.Includes_Rule
                  & "`: this statement includes the file its string names. */");
            Include_Name;
         else
            Line ("static char *hbnf_include_name(const char *s,"
                  & " size_t len) {");
            Line ("    (void)s; (void)len; return NULL;");
            Line ("}");
            Line ("");
         end if;
         if HBNF_Grammar.Macros_Rule /= "" then
            Line ("/* `macros " & HBNF_Grammar.Macros_Rule
                  & "`: this statement defines a macro. */");
            Whole ("hbnf_is_macro", HBNF_Grammar.Macros_Rule, "bool ");
         end if;
      end Emit_Statement_Hooks;

      Res : U;

      --  True when a repetition's DNF is a flat ASCII character class: every
      --  branch is a single code-point range below 0x80.  Such a class can be
      --  matched as raw bytes (a multi-byte UTF-8 lead byte is >= 0x80 and so
      --  never matches), so the scanner skips the per-code-point
      --  hbnf_decode_utf8 the general path emits -- one call per range, per
      --  position: a ten-way `wordchars` decodes each byte ten times.
      function Is_Ascii_Class (Sub : Cp_Branch_Vectors.Vector) return Boolean is
      begin
         if Sub.Is_Empty then
            return False;
         end if;
         for B of Sub loop
            if Natural (B.Length) /= 1 or else B (1).Hi >= 16#80# then
               return False;
            end if;
         end loop;
         return True;
      end Is_Ascii_Class;

      --  The byte test for an ASCII class: `(b >= lo && b <= hi) || ...`.
      function Class_Cond (Sub : Cp_Branch_Vectors.Vector) return String is
         Buf   : U;
         First : Boolean := True;
      begin
         for B of Sub loop
            if not First then
               Append (Buf, " || ");
            end if;
            First := False;
            Append (Buf, "(b >= " & Img (B (1).Lo) & " && b <= "
              & Img (B (1).Hi) & ")");
         end loop;
         return To_String (Buf);
      end Class_Cond;

      --  A byte test for one ASCII code point: `b <= hi` when lo is 0, else
      --  `b >= lo && b <= hi` (b is `unsigned char`).
      function Byte_Cond (Lo, Hi : Natural) return String is
      begin
         if Lo = 0 then
            return "(b <= " & Img (Hi) & ")";
         else
            return "(b >= " & Img (Lo) & " && b <= " & Img (Hi) & ")";
         end if;
      end Byte_Cond;

      --  Emit one single code point: a direct byte compare when it is ASCII,
      --  else a UTF-8 decode (the code point may be multi-byte).
      procedure Emit_Single (A : Cp_Atom; Ind : String; Fail : String) is
      begin
         if A.Hi < 16#80# then
            Append (Res, Ind & "if (pos + off >= len) " & Fail & ";");
            Append (Res, LF);
            Append (Res, Ind & "{ unsigned char b = (unsigned char)s[pos + off];");
            Append (Res, LF);
            Append (Res, Ind & "  if (!" & Byte_Cond (A.Lo, A.Hi) & ") "
              & Fail & "; }");
            Append (Res, LF);
            Append (Res, Ind & "off++;");
            Append (Res, LF);
         else
            Append (Res, Ind & "{ uint32_t c; size_t n = hbnf_decode_utf8(s,"
              & " pos + off, len, &c); if (!n || !"
              & Range_Cond (A.Lo, A.Hi) & ") " & Fail & "; off += n; }");
            Append (Res, LF);
         end if;
      end Emit_Single;

      --  "own" when a rule is the own-line comment, "eol" when it is the
      --  same-line comment (chasing single-name aliases such as
      --  `trailing = eol_comment`), "" otherwise.
      function Comment_Kind (Rules : Rule_Vectors.Vector; Nm : String;
                             Depth : Natural := 0) return String is
         J : Natural;
      begin
         if Nm = "comment" then
            return "own";
         end if;
         if Nm = "eol_comment" then
            return "eol";
         end if;
         if Depth >= 8 then
            return "";
         end if;
         J := Find (Rules, Nm);
         if J /= 0 then
            declare
               P : constant Element_Vectors.Vector := Rules (J).Pattern;
            begin
               if Natural (P.Length) = 1 and then P (1).Kind = Name
                 and then P (1).Min = 1 and then P (1).Max = 1
               then
                  return Comment_Kind (Rules, To_String (P (1).Name),
                                       Depth + 1);
               end if;
            end;
         end if;
         return "";
      end Comment_Kind;

      --  Emit the greedy loop for a repetition: match one full branch of the
      --  DNF (the longest one) as many times as Max allows (0 = unbounded),
      --  then require Min.  A branch is a sequence of decoded code points.
      procedure Emit_Repeat (A : Cp_Atom; Ind : String; Fail : String) is
         procedure Emit_Branch (B : Cp_Range_Vectors.Vector) is
         begin
            Append (Res, Ind & "        { size_t o = 0; int ok = 1;");
            Append (Res, LF);
            for Rg of B loop
               Append (Res, Ind & "          if (ok) { uint32_t c; size_t n = hbnf_decode_utf8(s,"
                 & " pos + off + o, len, &c); if (!n || !"
                 & Range_Cond (Rg.Lo, Rg.Hi) & ") ok = 0; else o += n; }");
               Append (Res, LF);
            end loop;
            Append (Res, Ind & "          if (ok && o > br) br = o; }");
            Append (Res, LF);
         end Emit_Branch;
         Needs_Cnt : constant Boolean := A.Max /= 0 or else A.Min > 0;
      begin
         if Is_Ascii_Class (A.Sub) then
            --  A flat ASCII class: match it as raw bytes in one tight loop,
            --  no per-code-point decode.
            Append (Res, Ind & "{" & (if Needs_Cnt then " size_t cnt = 0;" else ""));
            Append (Res, LF);
            if A.Max = 0 then
               Append (Res, Ind & "    for (;;) {");
            else
               Append (Res, Ind & "    while (cnt < " & Img (A.Max) & ") {");
            end if;
            Append (Res, LF);
            Append (Res, Ind & "        if (pos + off >= len) break;");
            Append (Res, LF);
            Append (Res, Ind & "        { unsigned char b = (unsigned char)s[pos + off];");
            Append (Res, LF);
            Append (Res, Ind & "          if (!(" & Class_Cond (A.Sub)
              & ")) break; }");
            Append (Res, LF);
            Append (Res, Ind & "        off++;" & (if Needs_Cnt then " cnt++;" else ""));
            Append (Res, LF);
            Append (Res, Ind & "    }");
            Append (Res, LF);
            if A.Min > 0 then
               Append (Res, Ind & "    if (cnt < " & Img (A.Min) & ") " & Fail
                 & ";");
               Append (Res, LF);
            end if;
            Append (Res, Ind & "}");
            Append (Res, LF);
         else
            Append (Res, Ind & "{" & (if Needs_Cnt then " size_t cnt = 0;" else ""));
            Append (Res, LF);
            if A.Max = 0 then
               Append (Res, Ind & "    for (;;) {");
            else
               Append (Res, Ind & "    while (cnt < " & Img (A.Max) & ") {");
            end if;
            Append (Res, LF);
            Append (Res, Ind & "        size_t br = 0;");
            Append (Res, LF);
            for B of A.Sub loop
               Emit_Branch (B);
            end loop;
            Append (Res, Ind & "        if (br == 0) break;");
            Append (Res, LF);
            Append (Res, Ind & "        off += br;" & (if Needs_Cnt then " cnt++;" else ""));
            Append (Res, LF);
            Append (Res, Ind & "    }");
            Append (Res, LF);
            if A.Min > 0 then
               Append (Res, Ind & "    if (cnt < " & Img (A.Min) & ") " & Fail
                 & ";");
               Append (Res, LF);
            end if;
            Append (Res, Ind & "}");
            Append (Res, LF);
         end if;
      end Emit_Repeat;
   begin
      for R of Rules loop
         Collect_Case (R.Pattern);
      end loop;
      for W of Nocase_Words loop
         if Case_Words.Contains (W) and then Is_Keyword_Lit (To_String (W))
         then
            raise HBNF_Grammar.Parse_Error with
              "the keyword `" & To_String (W) & "` is written both with %i "
              & "and without; a keyword matches one way or the other";
         end if;
      end loop;
      declare
         Scanners   : U;  -- forward declarations of the scanners the parser calls
         Word_Match : U;  -- expect_word: a keyword matched through the `word` scanner
         Ws_Skip    : U;  -- skip_ws: skip the `whitespace` rule at phrase level
         Nocase     : U;
         Kw         : U;
         Ws_Name    : Unbounded_String := Null_Unbounded_String;
         Has_Word   : Boolean := False;
         Strings_H  : constant String :=
           (if Nocase_Words.Is_Empty then "" else "#include <strings.h>" & LF);
      begin
         --  The rule the `whitespace` directive names (one value, else the
         --  reader reports it).
         for I in 1 .. N loop
            if Rules (I).Whitespace /= Null_Unbounded_String then
               Ws_Name := Rules (I).Whitespace;
               exit;
            end if;
         end loop;
         --  Forward declarations for every scanner the parser may call, so the
         --  parse functions (and expect_word/skip_ws) can precede the scanner
         --  bodies emitted later.
         for I in 1 .. N loop
            if Rules (I).Jet_Code /= Null_Unbounded_String then
               Append (Scanners, "static size_t jet_"
                 & C_Name (To_String (Rules (I).Name))
                 & "(const char *s, size_t pos, size_t len);" & LF);
               if To_String (Rules (I).Name) = "word" then
                  Has_Word := True;
               end if;
            elsif Is_Char_Rule (Rules, To_String (Rules (I).Name)) then
               declare
                  NM : constant String := To_String (Rules (I).Name);
               begin
                  if Is_Char_Token (Rules, NM)
                    or else NM = To_String (Ws_Name)
                  then
                     Append (Scanners, "static size_t scan_" & C_Name (NM)
                       & "(const char *s, size_t pos, size_t len);" & LF);
                     if NM = "word" then
                        Has_Word := True;
                     end if;
                  end if;
               end;
            end if;
         end loop;

         Emit_Keywords (Kw);

         --  A keyword is matched by scanning `word` and comparing its length and
         --  bytes, so `in` never matches `input` (the boundary is grammar).
         if Has_Word then
            Append (Word_Match, "__attribute__((unused))" & LF);
            --  The failing case is the common one (a choice among keywords asks one word many
            --  times), so it is cheap: the first byte before the compare, and no call to `fail`
            --  in the first pass, which records nothing.
            Append (Word_Match, "static bool expect_word_fail(parser_t *p, const char *lit,"
              & " size_t n) {" & LF);
            Append (Word_Match, "    fail(p, lit, 1, p->text + p->pos,"
              & " n ? n : (p->pos < p->len ? 1 : 0)); return false;" & LF);
            Append (Word_Match, "}" & LF);
            Append (Word_Match, "__attribute__((unused))" & LF);
            Append (Word_Match, "static inline bool expect_word(parser_t *p,"
              & " const char *lit, size_t lit_len) {" & LF);
            Append (Word_Match, "    size_t n = HBNF_WORD_AT(p, " & Word_Scanner (Rules)
              & ");" & LF);
            Append (Word_Match, "    if (n == lit_len && p->text[p->pos] == lit[0]"
              & " && memcmp(p->text + p->pos, lit, lit_len) == 0)"
              & " { p->pos += n; return true; }" & LF);
            Append (Word_Match, "    if (p->quiet) return false;" & LF);
            Append (Word_Match, "    return expect_word_fail(p, lit, n);" & LF);
            Append (Word_Match, "}" & LF & LF);
         end if;

         --  Skip the file's `whitespace` rule as many times as it matches.
         --  The scanner tries every alternative of the rule and returns one
         --  match, so skipping a run of blanks through it costs one call and
         --  one pass over the alternatives per character.  A run is almost
         --  all single blanks, so the rule's own single-code-point ASCII
         --  alternatives are coalesced into one byte test and consumed
         --  inline; the scanner is called only where a longer alternative (a
         --  comment, a backslash continuation) could begin.  The test is
         --  derived from the grammar, so a file whose `ws` is something else
         --  gets its own, and a rule with no single-code-point alternative
         --  falls back to the scanner alone.
         if Ws_Name /= Null_Unbounded_String then
            declare
               DNF   : constant Cp_Branch_Atom_Vectors.Vector :=
                 (if Is_Dfa_Token (Rules, To_String (Ws_Name))
                  then Cp_Branch_Atom_Vectors.Empty_Vector   --  scanner only
                  else Char_DNF (Rules, To_String (Ws_Name)));
               Fast  : U;
               Rest  : Boolean := False;
               First : Boolean := True;
            begin
               for B of DNF loop
                  if Natural (B.Length) = 1 and then B (1).Kind = Single
                    and then B (1).Hi < 16#80#
                  then
                     if not First then
                        Append (Fast, " || ");
                     end if;
                     First := False;
                     Append (Fast, "(b >= " & Img (B (1).Lo) & " && b <= "
                       & Img (B (1).Hi) & ")");
                  else
                     Rest := True;
                  end if;
               end loop;
               if First and then Is_Dfa_Token (Rules, To_String (Ws_Name)) then
                  --  The scanner is an automaton: the bytes its first state reads
                  --  are the only ones whitespace can begin with, and a byte that
                  --  is not one of them (the common case, between two tokens)
                  --  needs no call, and no function: the test is inline.
                  declare
                     D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
                     Ok  : Boolean;
                     Why : Unbounded_String;
                     Row : array (0 .. 127) of Boolean := [others => False];
                     Wide : Boolean := False;
                     Plain_Ws : Boolean := False;
                     Tab  : Unbounded_String;
                  begin
                     HBNF_Lookahead.Token_Dfa (Rules, To_String (Ws_Name), D, Ok, Why);
                     if Ok and then not D.Is_Empty then
                        for E of D (1).Edges loop
                           for C in E.Lo .. Natural'Min (E.Hi, 127) loop
                              Row (C) := True;
                           end loop;
                           if E.Hi >= 128 then
                              Wide := True;
                           end if;
                        end loop;
                        --  White space that is a run of single bytes (blanks and newlines): the first
                        --  state goes to one that accepts and loops on the same bytes and nothing else.
                        --  Then skipping it is a loop over a table of bytes, with no call.
                        declare
                           One   : constant Boolean :=
                             not Wide and then Natural (D.Length) = 1 and then D (1).Accepting
                             and then (for all E of D (1).Edges => E.To = 1);
                           Plain : Boolean :=
                             One or else
                             (not Wide and then Natural (D.Length) = 2
                              and then not D (1).Accepting and then D (2).Accepting);
                           Same  : array (0 .. 127) of Boolean := [others => False];
                        begin
                           if Plain and then not One then
                              for E of D (1).Edges loop
                                 if E.To /= 2 then
                                    Plain := False;
                                 end if;
                              end loop;
                              for E of D (2).Edges loop
                                 if E.To /= 2 or else E.Hi >= 128 then
                                    Plain := False;
                                 else
                                    for C in E.Lo .. E.Hi loop
                                       Same (C) := True;
                                    end loop;
                                 end if;
                              end loop;
                              for C in Row'Range loop
                                 if Row (C) /= Same (C) then
                                    Plain := False;
                                 end if;
                              end loop;
                           end if;
                           if Plain then
                              declare
                                 Run : Unbounded_String;
                              begin
                                 for C in 0 .. 255 loop
                                    Append (Run, (if C <= 127 and then Row (C) then "1," else "0,"));
                                 end loop;
                                 Append (Ws_Skip, "static const unsigned char ws_run[256] = {" & To_String (Run) & "};" & LF);
                                 Append (Ws_Skip, "__attribute__((unused))" & LF);
                                 Append (Ws_Skip, "static inline void skip_ws(parser_t *p) {" & LF);
                                 Append (Ws_Skip, "    const unsigned char *t = (const unsigned char *)p->text;" & LF);
                                 Append (Ws_Skip, "    size_t i = p->pos;" & LF);
                                 Append (Ws_Skip, "    if (!ws_run[t[i]]) return;" & LF);
                                 Append (Ws_Skip, "    do i++; while (ws_run[t[i]]);" & LF);
                                 Append (Ws_Skip, "    p->pos = i > p->len ? p->len : i;" & LF);
                                 Plain_Ws := True;
                              end;
                           end if;
                        end;
                        if not Plain_Ws then
                        for C in Row'Range loop
                           Append (Tab, (if Row (C) then "1," else "0,"));
                        end loop;
                        Append (Ws_Skip, "static const unsigned char ws_starts[128] = {"
                          & To_String (Tab) & "};" & LF);
                        Append (Ws_Skip, "__attribute__((unused))" & LF);
                        Append (Ws_Skip, "static void skip_ws_slow(parser_t *p) {" & LF);
                        Append (Ws_Skip, "    for (;;) {" & LF);
                        Append (Ws_Skip, "        unsigned char b; size_t n;" & LF);
                        Append (Ws_Skip, "        if (p->pos >= p->len) return;" & LF);
                        Append (Ws_Skip, "        b = (unsigned char)p->text[p->pos];" & LF);
                        Append (Ws_Skip, "        if (b < 128 ? !ws_starts[b] : "
                          & (if Wide then "0" else "1") & ") return;" & LF);
                        Append (Ws_Skip, "        n = " & Rule_Scanner (Rules, To_String (Ws_Name))
                          & "(p->text, p->pos, p->len);" & LF);
                        Append (Ws_Skip, "        if (n == 0) return;" & LF);
                        Append (Ws_Skip, "        p->pos += n;" & LF);
                        Append (Ws_Skip, "    }" & LF);
                        Append (Ws_Skip, "}" & LF);
                        Append (Ws_Skip, "__attribute__((unused))" & LF);
                        Append (Ws_Skip, "static inline void skip_ws(parser_t *p) {" & LF);
                        Append (Ws_Skip, "    unsigned char b;" & LF);
                        Append (Ws_Skip, "    if (p->pos >= p->len) return;" & LF);
                        Append (Ws_Skip, "    b = (unsigned char)p->text[p->pos];" & LF);
                        Append (Ws_Skip, "    if (b < 128 ? !ws_starts[b] : "
                          & (if Wide then "0" else "1") & ") return;" & LF);
                        Append (Ws_Skip, "    skip_ws_slow(p);" & LF);
                        end if;
                     else
                        Append (Ws_Skip, Scanner_Skip (Rule_Scanner (Rules, To_String (Ws_Name))));
                     end if;
                  end;
               elsif First then
                  --  No single-code-point alternative: the scanner alone.
                  Append (Ws_Skip, Scanner_Skip (Rule_Scanner (Rules, To_String (Ws_Name))));
               else
                  Append (Ws_Skip, "__attribute__((unused))" & LF);
                  Append (Ws_Skip, "static void skip_ws(parser_t *p) {" & LF);
                  Append (Ws_Skip, "    for (;;) {" & LF);
                  Append (Ws_Skip, "        while (p->pos < p->len) {" & LF);
                  Append (Ws_Skip, "            unsigned char b = "
                    & "(unsigned char)p->text[p->pos];" & LF);
                  Append (Ws_Skip, "            if (!(" & To_String (Fast)
                    & ")) break;" & LF);
                  Append (Ws_Skip, "            p->pos++;" & LF);
                  Append (Ws_Skip, "        }" & LF);
                  if Rest then
                     Append (Ws_Skip, "        { size_t n = "
                       & Rule_Scanner (Rules, To_String (Ws_Name))
                       & "(p->text, p->pos, p->len);" & LF);
                     Append (Ws_Skip, "          if (n == 0) break;" & LF);
                     Append (Ws_Skip, "          p->pos += n; }" & LF);
                  else
                     --  Every alternative is one of the bytes above, so the
                     --  loop has already consumed the whole run.
                     Append (Ws_Skip, "        break;" & LF);
                  end if;
                  Append (Ws_Skip, "    }" & LF);
               end if;
               Append (Ws_Skip, "}" & LF & LF);
            end;
         end if;

         if not Nocase_Words.Is_Empty then
            Append (Nocase, "__attribute__((unused))" & LF);
            Append (Nocase, "static bool expect_word_nocase(parser_t *p,"
              & " const char *lit, size_t lit_len) {" & LF);
            Append (Nocase, "    size_t n = HBNF_WORD_AT(p, " & Word_Scanner (Rules)
              & ");" & LF);
            Append (Nocase, "    if (n == lit_len && strncasecmp(p->text + p->pos,"
              & " lit, lit_len) == 0) { p->pos += n; return true; }" & LF);
            Append (Nocase, "    fail(p, lit, 1, p->text + p->pos,"
              & " n ? n : (p->pos < p->len ? 1 : 0)); return false;" & LF);
            Append (Nocase, "}" & LF & LF);
            --  A case-insensitive literal that is not a keyword (a grammar with
            --  no words, as an RFC's ABNF): its characters, in either case.
            Append (Nocase, "__attribute__((unused))" & LF);
            Append (Nocase, "static bool expect_lit_nocase(parser_t *p,"
              & " const char *lit, size_t lit_len) {" & LF);
            Append (Nocase, "    if (p->pos + lit_len <= p->len && strncasecmp("
              & "p->text + p->pos, lit, lit_len) == 0) {"
              & " p->pos += lit_len; return true; }" & LF);
            Append (Nocase, "    fail(p, lit, 1, p->pos < p->len ? p->text + p->pos"
              & " : ""end of input"", p->pos < p->len ? 1 : 0); return false;" & LF);
            Append (Nocase, "}" & LF & LF);
         end if;
         --  The guards `/` set where a union needs backtracking: the next code
         --  point, if one more can follow, must be in the set that can follow
         --  the choice (first match wins, as RFC 3986 section 3.2.2 settles
         --  `host`).  Self-contained: a UTF-8 decode, then the ranges.
         for G in 1 .. HBNF_Grammar.Guard_Count loop
            declare
               Rs  : constant HBNF_Grammar.Guard_Range_Array :=
                 HBNF_Grammar.Guard_Ranges (G);
               Gid : constant String := Natural'Image (G);
            begin
               Append (Nocase, "__attribute__((unused))" & LF);
               Append (Nocase, "static bool guard_" & Gid (Gid'First + 1 .. Gid'Last)
                 & "(parser_t *p) {" & LF);
               Append (Nocase, "    if (p->pos >= p->len) return "
                 & (if HBNF_Grammar.Guard_Eoi (G) then "true" else "false")
                 & ";" & LF);
               if Rs'Length = 0 then
                  Append (Nocase, "    return false;" & LF & "}" & LF & LF);
                  goto Next_Guard_C;
               end if;
               Append (Nocase, "    unsigned char b = (unsigned char)p->text[p->pos];" & LF);
               Append (Nocase, "    size_t n = b < 0x80 ? 1 : b < 0xE0 ? 2 : b < 0xF0 ? 3 : 4;" & LF);
               Append (Nocase, "    if (p->pos + n > p->len) return false;" & LF);
               Append (Nocase, "    uint32_t c = n == 1 ? b : n == 2 ? (b & 0x1F) : n == 3 ? (b & 0x0F) : (b & 0x07);" & LF);
               Append (Nocase, "    for (size_t i = 1; i < n; i++) c = (c << 6) | ((unsigned char)p->text[p->pos + i] & 0x3F);" & LF);
               Append (Nocase, "    return false");
               for R of Rs loop
                  Append (Nocase, " || (c >= " & Natural'Image (R.Lo) & "u && c <= "
                    & Natural'Image (R.Hi) & "u)");
               end loop;
               Append (Nocase, ";" & LF & "}" & LF & LF);
               <<Next_Guard_C>> null;
            end;
         end loop;
         Append (Res, Fill ("c_parser",
           (H ("strings_h", Strings_H),
            H ("keywords", To_String (Kw)),
            H ("scanners", To_String (Scanners)),
            H ("word_matcher", To_String (Word_Match)),
            H ("ws_skip", To_String (Ws_Skip)),
            H ("nocase", To_String (Nocase)),
            H ("bit_field",
               (if Hosted_Code = Null_Unbounded_String then ""
                else "    unsigned bit;   /* where in the octet at pos a bit "
                     & "rule is: 0 to 7 */" & ASCII.LF
                     & "    size_t lim;     /* bits to read when a bit rule "
                     & "reads the words of a text (bitsof), else 0 */"
                     & ASCII.LF
                     & "    unsigned unit;  /* the width of one word, then */"
                     & ASCII.LF
                     & "    struct { const char *text; size_t pos, len, lim, "
                     & "start; unsigned bit, unit; int active; } sv;"
                     & ASCII.LF)),
            H ("path_field",
               "    unsigned depth, err_depth;   /* the rules being read, "
               & "and when the farthest error was seen */"
               & ASCII.LF
               & "    unsigned short stk[24], err_stk[24];" & ASCII.LF
               & "    size_t stkpos[24], err_stkpos[24];   /* where each began */"
               & ASCII.LF),
            H ("path_fail",
               "    { unsigned i_, n_ = p->depth < 24 ? p->depth : 24;"
               & " for (i_ = 0; i_ < n_; i_++) { p->err_stk[i_] = "
               & "p->stk[i_]; p->err_stkpos[i_] = p->stkpos[i_]; }"
               & " p->err_depth = n_; }" & ASCII.LF))));
      end;
      Append (Res, LF);
      Append (Res, LF);

      --  Forward declarations of every parse function.  A core-type char rule
      --  (str/int/word) is read as a scalar in place, and a building block is
      --  inlined into a token's scanner; neither is parsed by name.
      for I in 1 .. N loop
         declare
            NM : constant String := To_String (Rules (I).Name);
         begin
            if Needs_Parse_Fn (Rules, NM) then
               Append (Res, Fill ("c_rule_decl",
                 (H ("name", C_Name (NM)),
                  H ("type", Out_Type (I)))));
               Append (Res, LF);
               --  The first pass keeps no path of rules and counts no depth, so a call goes
               --  straight to the body; the second pass, which reads them, goes through the
               --  rule.  (A rule that puts the contexts back keeps its wrapper.)
               if not (Ctx_On and then not Is_Char_Rule (Rules, NM)
                       and then Rules (I).Jet_Code = Null_Unbounded_String
                       and then Rule_Binds (I))
               then
                  Append (Res, "static bool parse_body_" & C_Name (NM)
                    & "(parser_t *p, " & Out_Type (I) & ");" & LF
                    & "#define parse_rule_" & C_Name (NM) & "(p_, o_) ((p_)->quiet ? parse_body_"
                    & C_Name (NM) & "((p_), (o_)) : (parse_rule_" & C_Name (NM) & ")((p_), (o_)))" & LF);
               end if;
            end if;
         end;
      end loop;
      Append (Res, LF);
      Append (Res, Hosted_Code);       --  the readers of the bit rules
      if Ctx_On then
         Append (Res, Context_Runtime (Rules));
      end if;
      if HBNF_Grammar.Uses_Frames then
         Append (Res, HBNF_Template.Get ("c_frames"));
      end if;
      if Forks_On then
         --  The retry state: which alternative of a forked rule to start
         --  at, and which one matched (decision 14).  Listed once each.
         declare
            Any : Boolean := False;
         begin
            for I in 1 .. N loop
               declare
                  A, B : Natural;
               begin
                  Fork_Pair (I, A, B);
                  if A /= 0 then
                     Any := True;
                     if not Quiet_Forks then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "hbnf: fork: rule " & To_String (Rules (I).Name)
                           & ": alternatives" & Natural'Image (A) & " and"
                           & Natural'Image (B) & " can start alike; a later"
                           & " failure retries the next one");
                     end if;
                  end if;
               end;
            end loop;
            if Any then
               Append (Res, "static _Thread_local size_t hbnf_fork_start, "
                 & "hbnf_fork_used;" & LF & LF);
            end if;
         end;
      end if;

      declare
         --  The rules a cycle of references goes back to (the target of a back edge of a
         --  depth-first walk): every cycle has one.  Only they can recurse without end, so
         --  only their bodies ask whether the stack is nearly used up.
         Color : array (1 .. N) of Natural := [others => 0];

         procedure Visit (I : Positive);

         procedure Refs (Els : Element_Vectors.Vector) is
         begin
            for E of Els loop
               case E.Kind is
                  when Name =>
                     if not Is_Core (To_String (E.Name)) then
                        declare
                           J : constant Natural := Find (To_String (E.Name));
                        begin
                           if J /= 0 then
                              if Color (J) = 1 then
                                 Cycle_Target (J) := True;
                              elsif Color (J) = 0 then
                                 Visit (J);
                              end if;
                           end if;
                        end;
                     end if;
                  when Group =>
                     Refs (E.Items);
                  when Block =>
                     Refs (E.Look);
                  when others =>
                     null;
               end case;
            end loop;
         end Refs;

         procedure Visit (I : Positive) is
         begin
            Color (I) := 1;
            Refs (Rules (I).Pattern);
            Color (I) := 2;
         end Visit;
      begin
         for I in 1 .. N loop
            if Color (I) = 0 then
               Visit (I);
            end if;
         end loop;
      end;

      --  The check costs a few instructions in every call of a rule that has it, so it belongs
      --  on the rules called least.  Where a guarded rule is named in more places in the grammar
      --  than the rules it calls on its cycles, those are guarded instead (a `value` that an
      --  `object` and an `array` hold, a thousand calls to the one for every two to the others),
      --  provided that no cycle is left without a guard.
      declare
         type Rule_Flags is array (1 .. N) of Boolean;
         Weight : array (1 .. N) of Natural := [others => 0];

         procedure Count (Els : Element_Vectors.Vector) is
         begin
            for E of Els loop
               case E.Kind is
                  when Name =>
                     if not Is_Core (To_String (E.Name)) then
                        declare
                           J : constant Natural := Find (To_String (E.Name));
                        begin
                           if J /= 0 then
                              Weight (J) := Weight (J) + 1;
                           end if;
                        end;
                     end if;
                  when Group =>
                     Count (E.Items);
                  when Block =>
                     Count (E.Look);
                  when others =>
                     null;
               end case;
            end loop;
         end Count;

         procedure Named (Els : Element_Vectors.Vector; Into : in out Rule_Flags) is
         begin
            for E of Els loop
               case E.Kind is
                  when Name =>
                     if not Is_Core (To_String (E.Name)) then
                        declare
                           J : constant Natural := Find (To_String (E.Name));
                        begin
                           if J /= 0 then
                              Into (J) := True;
                           end if;
                        end;
                     end if;
                  when Group =>
                     Named (E.Items, Into);
                  when Block =>
                     Named (E.Look, Into);
                  when others =>
                     null;
               end case;
            end loop;
         end Named;

         function Reaches (From, To : Positive) return Boolean is
            Seen  : Rule_Flags := [others => False];
            Found : Boolean := False;
            procedure Walk (I : Positive) is
               Out_Of : Rule_Flags := [others => False];
            begin
               if Found or else Seen (I) then
                  return;
               end if;
               Seen (I) := True;
               Named (Rules (I).Pattern, Out_Of);
               for J in 1 .. N loop
                  if Out_Of (J) then
                     if J = To then
                        Found := True;
                     else
                        Walk (J);
                     end if;
                  end if;
               end loop;
            end Walk;
         begin
            Walk (From);
            return Found;
         end Reaches;

         --  No cycle of references is left once the rules in Guarded are taken out.
         function Acyclic (Guarded : Rule_Flags) return Boolean is
            Color : array (1 .. N) of Natural := [others => 0];
            Ok    : Boolean := True;
            procedure Walk (I : Positive) is
               Out_Of : Rule_Flags := [others => False];
            begin
               Color (I) := 1;
               Named (Rules (I).Pattern, Out_Of);
               for J in 1 .. N loop
                  if Out_Of (J) and then not Guarded (J) then
                     if Color (J) = 1 then
                        Ok := False;
                     elsif Color (J) = 0 then
                        Walk (J);
                     end if;
                  end if;
               end loop;
               Color (I) := 2;
            end Walk;
         begin
            for I in 1 .. N loop
               if Color (I) = 0 and then not Guarded (I) then
                  Walk (I);
               end if;
            end loop;
            return Ok;
         end Acyclic;
      begin
         for R of Rules loop
            Count (R.Pattern);
         end loop;
         for T in 1 .. N loop
            if Cycle_Target (T) then
               declare
                  Calls : Rule_Flags := [others => False];
                  Trial : Rule_Flags;
                  Total : Natural := 0;
                  Any   : Boolean := False;
               begin
                  Named (Rules (T).Pattern, Calls);
                  for K in 1 .. N loop
                     Trial (K) := Cycle_Target (K);
                  end loop;
                  Trial (T) := False;
                  for K in 1 .. N loop
                     if Calls (K) and then K /= T and then not Cycle_Target (K)
                       and then Reaches (K, T)
                     then
                        Trial (K) := True;
                        Total := Total + Weight (K);
                        Any := True;
                     end if;
                  end loop;
                  if Any and then Total < Weight (T) and then Acyclic (Trial) then
                     for K in 1 .. N loop
                        Cycle_Target (K) := Trial (K);
                     end loop;
                  end if;
               end;
            end if;
         end loop;
      end;

      for I in 1 .. N loop
         declare
            R  : constant Rule := Rules (I);
            NM : constant String := To_String (R.Name);
         begin
            if Needs_Parse_Fn (Rules, NM) then
               declare
                  --  A rule that can bind puts the contexts back when it
                  --  fails (a token is a scanner and binds nothing).
                  Valued : constant Boolean := Emit_Value_Type (R) /= "";
                  Wrap_Ctx : constant Boolean :=
                    Ctx_On and then not Is_Char_Rule (Rules, NM)
                    and then R.Jet_Code = Null_Unbounded_String
                    and then Rule_Binds (I);
               begin
                  --  A rule that runs emits has two bodies: the quiet one, the first pass, which is
                  --  all the emits and none of the bookkeeping, and the loud one, which a pass that
                  --  reads a failure again takes, which records what each alternative wanted.
                  if Valued then
                     Append (Res, "static bool parse_loud_" & C_Name (NM)
                       & "(parser_t *p, " & Out_Type (I) & ") {" & LF);
                     Emit_Valued (I, Res, False);
                     Append (Res, "}" & LF & LF);
                  end if;
                  if Wrap_Ctx or else True then
                     Append (Res, "static bool parse_body_" & C_Name (NM)
                       & "(parser_t *p, " & Out_Type (I) & ");" & LF
                       & "static bool (parse_rule_" & C_Name (NM)
                       & ")(parser_t *p, " & Out_Type (I) & ") {" & LF
                       & "    bool ok_;" & LF
                       & (if Wrap_Ctx
                          then "    hbnf_mark_t m_;  m_ = hbnf_mark();" & LF
                          else "")
                       --  A token cannot nest, and the path of rules is only read when a parse
                       --  has failed and is read again, so the first pass goes straight to it.
                       & (if Is_Char_Rule (Rules, NM) or else R.Jet_Code /= Null_Unbounded_String
                          then "    if (p->quiet) return parse_body_" & C_Name (NM) & "(p, out);" & LF
                          else "")
                       & "    if (p->depth >= HBNF_MAX_DEPTH) {"
                       & " fail (p, ""shallower nesting"", 0,"
                       & " p->text + p->pos, p->pos < p->len ? 1 : 0);"
                       & " return false; }" & LF
                       & "    if (!p->quiet && p->depth < 24) { p->stk[p->depth] = "
                       & Natural'Image (I) & "; p->stkpos[p->depth] = p->pos; }"
                       & LF
                       & "    p->depth++;" & LF
                       & "    ok_ = " & (if Valued then "parse_loud_" else "parse_body_")
                       & C_Name (NM) & "(p, out);" & LF
                       & "    p->depth--;" & LF
                       & (if Wrap_Ctx
                          then "    if (!ok_) hbnf_reset (&m_);" & LF else "")
                       & "    return ok_;" & LF & "}" & LF
                       & (if Cycle_Target (I) then "static bool" else "static inline bool")
                       & " parse_body_" & C_Name (NM)
                       & "(parser_t *p, " & Out_Type (I) & ") {" & LF
                       & (if Cycle_Target (I)
                          then (if Valued then "    HBNF_STACK_GUARD(p);" & LF
                                else "    if (p->quiet) HBNF_STACK_GUARD(p);" & LF)
                          else ""));
                  else
                     Append (Res, Fill ("c_rule_head",
                       (H ("name", C_Name (NM)),
                        H ("type", Out_Type (I)))));
                     Append (Res, LF);
                  end if;
               end;
               Emit_Rule_Parser (I, Res);
               Append (Res, "}");
               Append (Res, LF);
               Append (Res, "#undef r" & LF);
               Append (Res, LF);
            end if;
         end;
      end loop;

      if True then
         Append (Res, "/* The rules a path names, by number (a rule the reader"
           & " made up for a group or an option is left out). */" & LF
           & "static const char *const hbnf_rn[] = { NULL," & LF);
         for I in 1 .. N loop
            declare
               NM   : constant String := To_String (Rules (I).Name);
               Cut  : Natural := 0;
               Hidden : Boolean := False;
            begin
               for K in reverse NM'Range loop
                  if NM (K) = '_' then
                     Cut := K;
                     exit;
                  end if;
               end loop;
               if Cut > NM'First and then Cut < NM'Last
                 and then (for all C of NM (Cut + 1 .. NM'Last) =>
                             C in '0' .. '9')
                 and then Find (Rules, NM (NM'First .. Cut - 1)) /= 0
               then
                  Hidden := True;
               end if;
               Append (Res, (if Hidden or else not Needs_Parse_Fn (Rules, NM)
                             then "NULL" else """" & NM & """") & "," & LF);
            end;
         end loop;
         Append (Res, "};" & LF
           & "__attribute__((unused))" & LF
           & "static void hbnf_path_str(const parser_t *p, char *buf, "
           & "size_t n) {" & LF
           & "    size_t o = 0;  unsigned i;" & LF
           & "    buf[0] = 0;" & LF
           & "    for (i = 0; i < p->err_depth; i++) {" & LF
           & "        const char *s = hbnf_rn[p->err_stk[i]];" & LF
           & "        size_t l;" & LF
           & "        if (!s) continue;" & LF
           & "        l = strlen(s);" & LF
           & "        if (o + l + 4 >= n) break;" & LF
           & "        if (o) { memcpy(buf + o, "" > "", 3);  o += 3; }" & LF
           & "        memcpy(buf + o, s, l);  o += l;  buf[o] = 0;" & LF
           & "    }" & LF
           & "}" & LF & LF
           & "/* An error in something that takes more than a line: where the"
           & " innermost" & LF
           & "   enclosing rule that began on an earlier line began, with its"
           & " line. */" & LF
           & "static void hbnf_open_note(parser_t *p, char *err, "
           & "size_t errlen, int at_end) {" & LF
           & "    unsigned i;  size_t el = strlen(err);" & LF
           & "    for (i = p->err_depth; i-- > 0; ) {" & LF
           & "        const char *s = hbnf_rn[p->err_stk[i]];" & LF
           & "        size_t sp = p->err_stkpos[i], l, c, ls, le;" & LF
           & "        if (!s) continue;" & LF
           & "        while (sp < p->len && (p->text[sp] == ' ' || p->text[sp] "
           & "== '\t' || p->text[sp] == '\n' || p->text[sp] == '\r')) sp++;" & LF
           & "        line_col(p, sp, &l, &c);" & LF
           & "        if (l + (at_end ? 1 : 3) > p->err_line) continue;" & LF
           & "        for (ls = sp; ls > 0 && p->text[ls - 1] != '\n'; ls--) ;" & LF
           & "        for (le = sp; le < p->len && p->text[le] != '\n'; le++) ;" & LF
           & "        snprintf(err + el, errlen - el," & LF
           & "                 at_end ? ""\n  %zu:%zu:%zu: the %s that begins here is not finished:\n  %.*s\n  %*s^""" & LF
           & "                        : ""\n  %zu:%zu:%zu: inside the %s that begins here:\n  %.*s\n  %*s^""," & LF
           & "                 l, c, sp, s, (int)(le - ls), p->text + ls, (int)(sp - ls), """");" & LF
           & "        return;" & LF
           & "    }" & LF
           & "}" & LF & LF);
      end if;

      --  The entry point: parse the root rule, then reject trailing input.
      --  With `statements` the statement driver calls this per statement as
      --  hbnf_parse; otherwise it is the public parse_text.
      if HBNF_Grammar.Frame_Of (To_String (Rules (1).Name)).Arity > 0 then
         raise HBNF_Grammar.Parse_Error with
           "`" & To_String (Rules (1).Name) & "` has parameters that are "
           & "numbers, so a parse cannot start with it; start with a rule "
           & "that gives them (`--root=` another rule)";
      end if;
      declare
         Entry_Nm : constant String :=
           (if HBNF_Grammar.Statements then "hbnf_parse" else "parse_text");
         Root_Out : constant String := Out_Type (1);
         Root_Decl : constant String :=
           Root_Out (Root_Out'First .. Root_Out'Last - 4);
      begin
         --  declared first, so a build that asks for a prototype of every function is quiet
         Append (Res, "bool " & Entry_Nm & "(const char *text, " & Root_Decl & "*out,"
           & " char *err, size_t errlen, size_t *err_line, size_t *err_col);" & LF);
         Append (Res, "bool " & Entry_Nm & "(const char *text, "
           & Root_Decl & "*out,");
         Append (Res, LF);
         Append (Res, "                  char *err, size_t errlen,"
           & " size_t *err_line, size_t *err_col) {");
         Append (Res, LF);
         Append (Res, (if Ctx_On then "    hbnf_ctx_clear();" & LF else "")
           & (if HBNF_Grammar.Uses_Frames
              then "    hbnf_fsp = 0; hbnf_fb = 0;" & LF else "")
           & "    parser_t p = { text, strlen(text), 0, (size_t)-1,"
           & " 0, 0, NULL, NULL, 0, 0 };" & LF
           & "    memset(out, 0, sizeof *out);   /* the rules fill it directly and expect it clear */" & LF
           & "    p.quiet = 1;   /* the first pass records no failures; one that fails is read again */" & LF
           & "    p.stack_lim = (const char *)__builtin_frame_address(0) - (size_t)HBNF_MAX_DEPTH * 256;" & LF
           & "start_:");
         Append (Res, LF);
         Append (Res, "    if (!parse_rule_" & C_Name (To_String (Rules (1).Name))
           & "(&p, out)) goto fail_;");
         Append (Res, LF);
         --  The text after the root may be whitespace, if the root's file skips
         --  any (`whitespace none`, as an RFC's ABNF reads, does not: an
         --  included file's own whitespace is not the root's), as the other
         --  backends decide it.
         if Rules (1).Whitespace /= Null_Unbounded_String then
            Append (Res, "    skip_ws(&p);");
            Append (Res, LF);
         end if;
         --  Input left over: with `statements`, nothing on the line was a
         --  statement, or something follows one.
         Append (Res, "    if (p.pos != p.len) { fail(&p, "
           & (if HBNF_Grammar.Statements
              then "p.pos == 0 ? ""a statement"" : ""end of statement"""
              else """end of config""")
           & ", 0, p.text + p.pos, 1); goto fail_; }");
         Append (Res, LF);
         if Analyze (Rules, 1).Kind in Struct | List and then Has_Relink then
            Append (Res, "    relink_" & C_Name (To_String (Rules (1).Name))
              & "(out);");
            Append (Res, LF);
         end if;
         if (Analyze (Rules, 1).Kind in Struct | List
             or else Wire_Alias_Root /= "") and then Has_Action
         then
            Append (Res, "    bind_errors = 0; bind_line = 0; bind_err_line = 0;"
              & " bind_err_msg[0] = '\0';"
              & (if Hosted_Actions then " bnf_act_nwarn = 0;" else ""));
            Append (Res, LF);
            Append (Res, (if Wire_Alias_Root /= ""
                          then "    walk_" & Wire_Alias_Root
                          else "    bind_" & C_Name (To_String (Rules (1).Name)))
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
         Append (Res, "fail_:" & LF
           & "    if (p.quiet) {" & LF
           & (if Ctx_On then "        hbnf_ctx_clear();" & LF else "")
           & (if HBNF_Grammar.Uses_Frames
              then "        hbnf_fsp = 0; hbnf_fb = 0;" & LF else "")
           & "        p = (parser_t){ text, strlen(text), 0, (size_t)-1, 0, 0, NULL, NULL, 0, 0 };" & LF
           & "        goto start_;" & LF
           & "    }" & LF
           & "    goto err;" & LF
           & "err:");
         Append (Res, LF);
         Append (Res, "    if (p.err_pos != (size_t)-1)"
           & " line_col(&p, p.err_pos, &p.err_line, &p.err_col);");
         Append (Res, LF);
         --  Found at the end of the input: say what ends there (a statement,
         --  with `statements`; else the input).
         Append (Res, "    { const char *f = p.err_found ? p.err_found"
           & " : ""end of input"";");
         Append (Res, LF);
         Append (Res, "      int at_end = p.err_pos >= p.len;");
         Append (Res, LF);
         Append (Res, "      if (at_end) f = """
           & (if HBNF_Grammar.Statements then "end of statement"
              else "end of input") & """;");
         Append (Res, LF);
         Append (Res, "      size_t fl = at_end ? strlen(f) : p.err_found_len;");
         Append (Res, LF);
         Append (Res, "      char want[640];");
         Append (Res, LF);
         if Paths_On then
            Append (Res, "      char inb[300];  inb[0] = 0;");
            Append (Res, LF);
            Append (Res, "      { char pth[256];  hbnf_path_str(&p, pth, "
              & "sizeof pth);  if (pth[0]) snprintf(inb, sizeof inb, "
              & """ (in %s)"", pth); }");
            Append (Res, LF);
         end if;
         Append (Res, "      want_text(&p, want, sizeof want);");
         Append (Res, LF);
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
         if Paths_On then
            Append (Res, "          snprintf(err, errlen,"
              & " ""%zu:%zu:%zu: expected %s, found %.*s%s\n  %.*s\n  %s^"", p.err_line, p.err_col, p.err_pos, want, (int)fl, f, inb, (int)ll, l, pad);");
         else
            Append (Res, "          snprintf(err, errlen,"
              & " ""%zu:%zu:%zu: expected %s, found %.*s\n  %.*s\n  %s^"", p.err_line, p.err_col, p.err_pos, want, (int)fl, f, (int)ll, l, pad);");
         end if;
         Append (Res, LF);
         Append (Res, "          hbnf_open_note(&p, err, errlen, at_end);");
         Append (Res, LF);
         Append (Res, "      } else {");
         Append (Res, LF);
         if Paths_On then
            Append (Res, "          snprintf(err, errlen, ""expected %s, found %.*s%s"","
              & " want, (int)fl, f, inb);");
         else
            Append (Res, "          snprintf(err, errlen, ""expected %s, found %.*s"","
              & " want, (int)fl, f);");
         end if;
         Append (Res, LF);
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
      end;

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

      --  Character-layer scanners: each char-level rule compiles to a scanner
      --  over its code points (one position for a single code point or an
      --  alternation, several for a sequence).  The scanners match decoded
      --  UTF-8 code points, so a token may begin with a multi-byte sequence;
      --  the shared decoder is emitted once, only when some rule is char-level.
      declare
         Has_Char : Boolean := False;
      begin
         for I in 1 .. N loop
            if Is_Char_Rule (Rules, To_String (Rules (I).Name)) then
               Has_Char := True;
            end if;
         end loop;
         if Has_Char then
            Append (Res, "static size_t hbnf_decode_utf8(const char *s, size_t pos,"
              & " size_t len, uint32_t *cp) {");
            Append (Res, LF);
            Append (Res, "    if (pos >= len) return 0;");
            Append (Res, LF);
            Append (Res, "    unsigned char b0 = (unsigned char)s[pos];");
            Append (Res, LF);
            Append (Res, "    uint32_t c; size_t n;");
            Append (Res, LF);
            Append (Res, "    if (b0 < 0x80) { *cp = b0; return 1; }");
            Append (Res, LF);
            Append (Res, "    else if ((b0 & 0xE0) == 0xC0) { n = 2; c = b0 & 0x1F; }");
            Append (Res, LF);
            Append (Res, "    else if ((b0 & 0xF0) == 0xE0) { n = 3; c = b0 & 0x0F; }");
            Append (Res, LF);
            Append (Res, "    else if ((b0 & 0xF8) == 0xF0) { n = 4; c = b0 & 0x07; }");
            Append (Res, LF);
            Append (Res, "    else return 0;");
            Append (Res, LF);
            Append (Res, "    if (pos + n > len) return 0;");
            Append (Res, LF);
            Append (Res, "    for (size_t k = 1; k < n; k++) {");
            Append (Res, LF);
            Append (Res, "        unsigned char b = (unsigned char)s[pos + k];");
            Append (Res, LF);
            Append (Res, "        if ((b & 0xC0) != 0x80) return 0;");
            Append (Res, LF);
            Append (Res, "        c = (c << 6) | (b & 0x3F);");
            Append (Res, LF);
            Append (Res, "    }");
            Append (Res, LF);
            Append (Res, "    *cp = c; return n;");
            Append (Res, LF);
            Append (Res, "}");
            Append (Res, LF);
            Append (Res, LF);
         end if;
      end;
      for I in 1 .. N loop
         if Is_Char_Rule (Rules, To_String (Rules (I).Name))
           and then (Is_Char_Token (Rules, To_String (Rules (I).Name))
                     or else To_String (Rules (I).Name)
                             = To_String (Whitespace_Rule_Name (Rules)))
         then
            declare
               NM  : constant String := To_String (Rules (I).Name);
               DNF : constant Cp_Branch_Atom_Vectors.Vector := (if Is_Dfa_Token (Rules, NM)
                       or else HBNF_Grammar.Except_Operand (NM) /= ""
                    then Cp_Branch_Atom_Vectors.Empty_Vector
                    else Char_DNF (Rules, NM));
            begin
               if HBNF_Grammar.Except_Operand (NM) /= "" then
Append (Res, "static size_t scan_" & C_Name (NM)
  & "(const char *s, size_t pos, size_t len) {" & LF);
Append (Res, "    size_t n = scan_" & C_Name (HBNF_Grammar.Except_Base (NM))
  & "(s, pos, len);" & LF);
Append (Res, "    if (n == 0 || scan_" & C_Name (HBNF_Grammar.Except_Operand (NM))
  & "(s, pos, pos + n) == n) return 0;" & LF);
Append (Res, "    return n;" & LF & "}" & LF & LF);
elsif Is_Dfa_Token (Rules, NM) then
declare
   D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
   Ok  : Boolean;
   Why : Unbounded_String;
   Lo, Hi, To, First, Acc : Unbounded_String;
   Ascii_Dfa : Boolean := False;
   Run_Code  : Unbounded_String;
begin
   HBNF_Lookahead.Token_Dfa (Rules, NM, D, Ok, Why);
   HBNF_Lookahead.Dfa_Tables (D, Lo, Hi, To, First, Acc);
   if Ok and then Natural (D.Length) in 1 .. 48 then
      --  A small machine is written out: a label for each state, and the byte tested against the
      --  ranges that leave it.  No tables are read, and no state is carried in a variable.
      declare
         function N (X : Natural) return String is
           (Ada.Strings.Fixed.Trim (Natural'Image (X), Ada.Strings.Left));
         Wide : Boolean := False;
      begin
         for St in 1 .. Natural (D.Length) loop
            for E of D (St).Edges loop
               if E.Hi >= 128 then
                  Wide := True;
               end if;
            end loop;
         end loop;
         --  A token that is an opening character, a run of ordinary bytes and a closing character
         --  (a quoted string) gets a short way in front of the machine: when the first bytes
         --  after the opening one hold the closing one, before any byte that needs a state of
         --  its own, the match is found with one wide step and no call.  Anything else, and a
         --  string longer than that, goes to the machine.
         declare
            Open_C  : Natural := 0;
            Close_C : Natural := 0;
            Fast    : Boolean := False;
            Temps   : Unbounded_String;
            Tests   : Unbounded_String;
         begin
            if not D (1).Accepting and then Natural (D (1).Edges.Length) = 1
              and then D (1).Edges.First_Element.Lo = D (1).Edges.First_Element.Hi
              and then D (1).Edges.First_Element.Hi <= 127
              and then D (1).Edges.First_Element.To /= 1
            then
               declare
                  S1    : constant Positive := D (1).Edges.First_Element.To;
                  Loops : array (0 .. 255) of Boolean := [others => False];
                  Count : Natural := 0;
                  Ranges : Natural := 0;
                  C     : Natural := 0;
               begin
                  Open_C := D (1).Edges.First_Element.Lo;
                  for E of D (S1).Edges loop
                     if E.To = S1 then
                        for B in E.Lo .. Natural'Min (E.Hi, 127) loop
                           Loops (B) := True;
                           Count := Count + 1;
                        end loop;
                     end if;
                  end loop;
                  if Count >= 20 and then not Loops (0) and then not D (S1).Accepting then
                     --  the bytes that leave the run, as the wide step of the machine tests them
                     while C <= 255 loop
                        if not Loops (C) then
                           declare
                              Lo_B : constant Natural := C;
                           begin
                              while C <= 255 and then not Loops (C) loop
                                 C := C + 1;
                              end loop;
                              Ranges := Ranges + 1;
                              declare
                                 Hi_B : constant Natural := C - 1;
                              begin
                                 if Lo_B = Hi_B then
                                    Append (Tests, (if Ranges = 1 then "" else " | ")
                                      & "_mm_cmpeq_epi8(v, _mm_set1_epi8((char)" & N (Lo_B) & "))");
                                 else
                                    Append (Temps, ", x" & N (Ranges));
                                    Append (Tests, (if Ranges = 1 then "" else " | ")
                                      & "(x" & N (Ranges) & " = _mm_sub_epi8(v, _mm_set1_epi8((char)" & N (Lo_B)
                                      & ")), _mm_cmpeq_epi8(_mm_min_epu8(x" & N (Ranges)
                                      & ", _mm_set1_epi8((char)" & N (Hi_B - Lo_B) & ")), x" & N (Ranges) & "))");
                                 end if;
                              end;
                           end;
                        else
                           C := C + 1;
                        end if;
                     end loop;
                     --  one edge out of the run that is not a byte of it and ends the token
                     for E of D (S1).Edges loop
                        if E.To /= S1 and then E.Lo = E.Hi and then E.Hi <= 127
                          and then D (E.To).Accepting and then D (E.To).Edges.Is_Empty
                        then
                           Fast := Ranges <= 5;
                           Close_C := E.Lo;
                        end if;
                     end loop;
                  end if;
               end;
            end if;
            if Fast then
               Append (Res, "static size_t scan_" & C_Name (NM) & "_full(const char *s, size_t pos, size_t len);" & LF
                 & "static inline size_t scan_" & C_Name (NM)
                 & "(const char *s, size_t pos, size_t len) {" & LF
                 & "#if defined(__SSE2__)" & LF
                 & "    if (pos + 17 <= len && s[pos] == " & N (Open_C) & ") {" & LF
                 & "        __m128i v = _mm_loadu_si128((const __m128i *)(s + pos + 1))" & To_String (Temps) & ";" & LF
                 & "        unsigned mk = (unsigned)_mm_movemask_epi8(" & To_String (Tests) & ");" & LF
                 & "        if (mk) {" & LF
                 & "            size_t j = pos + 1 + (size_t)__builtin_ctz(mk);" & LF
                 & "            if (s[j] == " & N (Close_C) & ") return j + 1 - pos;" & LF
                 & "        }" & LF
                 & "    }" & LF
                 & "#endif" & LF
                 & "    return scan_" & C_Name (NM) & "_full(s, pos, len);" & LF
                 & "}" & LF);
            end if;
            Append (Res, "static size_t scan_" & C_Name (NM) & (if Fast then "_full" else "")
              & "(const char *s, size_t pos, size_t len) {" & LF
              & "    size_t i = pos, best = 0;" & LF
              & (if Wide then "    uint32_t c; size_t n;" & LF else "    unsigned c;" & LF));
         end;
         --  the runs: a state that loops on itself over ASCII bytes
         for St in 1 .. Natural (D.Length) loop
            declare
               Loops : array (0 .. 255) of Boolean := [others => False];
               Count : Natural := 0;
               Tab   : Unbounded_String;
            begin
               for E of D (St).Edges loop
                  if E.To = St then
                     for B in E.Lo .. Natural'Min (E.Hi, 127) loop
                        Loops (B) := True;
                        Count := Count + 1;
                     end loop;
                  end if;
               end loop;
               if Count >= 8 and then not Loops (0) then
                  for B in 0 .. 255 loop
                     Append (Tab, (if Loops (B) then "1," else "0,"));
                  end loop;
                  Append (Res, "    static const unsigned char run" & N (St - 1) & "[256] = {"
                    & To_String (Tab) & "};" & LF);
               end if;
            end;
         end loop;
         for St in 1 .. Natural (D.Length) loop
            declare
               Loops : array (0 .. 255) of Boolean := [others => False];
               Count : Natural := 0;
               Tests : Unbounded_String;
               Temps : Unbounded_String;
               Ranges : Natural := 0;
               C : Natural := 0;
               Run : Boolean;
            begin
               for E of D (St).Edges loop
                  if E.To = St then
                     for B in E.Lo .. Natural'Min (E.Hi, 127) loop
                        Loops (B) := True;
                        Count := Count + 1;
                     end loop;
                  end if;
               end loop;
               Run := Count >= 8 and then not Loops (0);
               --  a label only where an edge leads to the state (the start state often has none)
               if (for some S2 in 1 .. Natural (D.Length) =>
                     (for some E of D (S2).Edges => E.To = St))
               then
                  Append (Res, "S" & N (St - 1) & ":" & LF);
               end if;
               if D (St).Accepting and then D (St).Edges.Is_Empty then
                  --  a state that accepts and leads nowhere ends the match: no byte to read
                  Append (Res, "    return i - pos;" & LF);
               else
               if D (St).Accepting and then not Run then
                  Append (Res, "    best = i - pos;" & LF);
               end if;
               if Run then
                  if Count >= 20 then
                     while C <= 255 loop
                        if not Loops (C) then
                           declare
                              Lo_B : constant Natural := C;
                           begin
                              while C <= 255 and then not Loops (C) loop
                                 C := C + 1;
                              end loop;
                              Ranges := Ranges + 1;
                              declare
                                 Hi_B : constant Natural := C - 1;
                                 T : constant String :=
                                   (if Lo_B = Hi_B
                                    then "_mm_cmpeq_epi8(v, _mm_set1_epi8((char)" & N (Lo_B) & "))"
                                    else "(x" & N (Ranges) & " = _mm_sub_epi8(v, _mm_set1_epi8((char)" & N (Lo_B)
                                         & ")), _mm_cmpeq_epi8(_mm_min_epu8(x" & N (Ranges)
                                         & ", _mm_set1_epi8((char)" & N (Hi_B - Lo_B) & ")), x" & N (Ranges) & "))");
                              begin
                                 if Lo_B /= Hi_B then
                                    Append (Temps, ", x" & N (Ranges));
                                 end if;
                                 Append (Tests, (if Ranges = 1 then "" else " | ") & T);
                              end;
                           end;
                        else
                           C := C + 1;
                        end if;
                     end loop;
                     if Ranges <= 5 then
                        Append (Res,
                          "#if defined(__SSE2__)" & LF
                          & "    for (; i + 16 <= len; i += 16) {" & LF
                          & "        __m128i v = _mm_loadu_si128((const __m128i *)(s + i))" & To_String (Temps) & ";" & LF
                          & "        unsigned mk = (unsigned)_mm_movemask_epi8(" & To_String (Tests) & ");" & LF
                          & "        if (mk) { i += (size_t)__builtin_ctz(mk); goto RS" & N (St - 1) & "; }" & LF
                          & "    }" & LF
                          & "#endif" & LF);
                     end if;
                  end if;
                  --  The wide step stops on the byte that is not in the run, inside the text: that
                  --  case goes straight past the byte-at-a-time loop and the clamp.
                  Append (Res, "    while (run" & N (St - 1) & "[(unsigned char)s[i]]) i++;" & LF
                    & "    if (i > len) i = len;" & LF
                    & (if Count >= 20 and then Ranges <= 5
                       then "RS" & N (St - 1) & ": __attribute__((unused));" & LF
                       else ""));
                  if D (St).Accepting then
                     Append (Res, "    best = i - pos;" & LF);
                  end if;
               end if;
               Append (Res, "    if (i >= len) return best;" & LF);
               Append (Res, "    c = (unsigned char)s[i];" & LF);
               Append (Res, "    if (c < 128) {" & LF);
               for E of D (St).Edges loop
                  if E.Lo <= 127 and then not (E.To = St and then Run) then
                     Append (Res, "        if (c "
                       & (if E.Lo = Natural'Min (E.Hi, 127)
                          then "== " & N (E.Lo)
                          else ">= " & N (E.Lo) & " && c <= " & N (Natural'Min (E.Hi, 127)))
                       & ") { i++; goto S" & N (E.To - 1) & "; }" & LF);
                  end if;
               end loop;
               Append (Res, "        return best;" & LF & "    }" & LF);
               if Wide then
                  Append (Res, "    n = hbnf_decode_utf8(s, i, len, &c);" & LF
                    & "    if (!n) return best;" & LF);
                  for E of D (St).Edges loop
                     if E.Hi >= 128 then
                        Append (Res, "    if (c >= " & N (E.Lo) & "u && c <= " & N (E.Hi) & "u) { i += n; goto S"
                          & N (E.To - 1) & "; }" & LF);
                     end if;
                  end loop;
               end if;
               Append (Res, "    return best;" & LF);
               end if;
            end;
         end loop;
         Append (Res, "}" & LF & LF);
      end;
   else
   HBNF_Lookahead.Dfa_Tables (D, Lo, Hi, To, First, Acc);
   Append (Res, "static size_t scan_" & C_Name (NM)
     & "(const char *s, size_t pos, size_t len) {" & LF);
   --  The ASCII bytes go through a table of their own (a state and a byte give the next
   --  state, 255 for none), without decoding or looking through the ranges; the rest of
   --  the code points through the ranges.
   declare
      Ascii_Ok : constant Boolean := Natural (D.Length) in 1 .. 255;
      At_Table : Unbounded_String;
   begin
      if Ascii_Ok then
         for St in 1 .. Natural (D.Length) loop
            declare
               Row : array (0 .. 127) of Natural := [others => 255];
            begin
               for E of D (St).Edges loop
                  for C in E.Lo .. Natural'Min (E.Hi, 127) loop
                     Row (C) := E.To - 1;
                  end loop;
               end loop;
               for C in Row'Range loop
                  Append (At_Table, Natural'Image (Row (C)) (2 .. Natural'Image (Row (C))'Last) & ",");
               end loop;
               Append (At_Table, LF);
            end;
         end loop;
         Append (Res, "    static const unsigned char at[] = {" & LF & To_String (At_Table) & "};" & LF);
         --  A state that loops on itself over ASCII bytes (the body of a string, a run of digits) is
         --  left by one table lookup a byte: the table says which bytes keep the state, and the
         --  text ends in a NUL (parse_text reads to its end), which keeps nothing, so no bound is
         --  tested in the loop; a scan that stops short of the NUL is clamped after it.  A long run
         --  is left 16 bytes at a time first (SSE2, where the compiler has it): the bytes that
         --  end the run are a few ranges, each tested with a subtract and a compare.
         declare
            Shown : Natural := 0;
         begin
            for St in 1 .. Natural (D.Length) loop
               declare
                  Loops : array (0 .. 255) of Boolean := [others => False];
                  Count : Natural := 0;
                  Tests : Unbounded_String;
                  Temps : Unbounded_String;
                  Ranges : Natural := 0;
                  C : Natural := 0;
                  Tab : Unbounded_String;
                  function N (X : Natural) return String is
                    (Ada.Strings.Fixed.Trim (Natural'Image (X), Ada.Strings.Left));
                  Name : constant String := N (St - 1);
               begin
                  for E of D (St).Edges loop
                     if E.To = St then
                        for B in E.Lo .. Natural'Min (E.Hi, 127) loop
                           Loops (B) := True;
                           Count := Count + 1;
                        end loop;
                     end if;
                  end loop;
                  if Count >= 8 and then Loops (0) = False and then Shown < 4 then
                     Shown := Shown + 1;
                     for B in 0 .. 255 loop
                        Append (Tab, (if Loops (B) then "1," else "0,"));
                     end loop;
                     Append (Res, "    static const unsigned char run" & Name & "[256] = {"
                       & To_String (Tab) & "};" & LF);
                     if Count >= 20 then
                        while C <= 255 loop
                           if not Loops (C) then
                              declare
                                 Lo : constant Natural := C;
                              begin
                                 while C <= 255 and then not Loops (C) loop
                                    C := C + 1;
                                 end loop;
                                 Ranges := Ranges + 1;
                                 declare
                                    Hi : constant Natural := C - 1;
                                    T : constant String :=
                                      (if Lo = Hi
                                       then "_mm_cmpeq_epi8(v, _mm_set1_epi8((char)" & N (Lo) & "))"
                                       else "(x" & N (Ranges) & " = _mm_sub_epi8(v, _mm_set1_epi8((char)" & N (Lo)
                                            & ")), _mm_cmpeq_epi8(_mm_min_epu8(x" & N (Ranges)
                                            & ", _mm_set1_epi8((char)" & N (Hi - Lo) & ")), x" & N (Ranges) & "))");
                                 begin
                                    if Lo /= Hi then
                                       Append (Temps, ", x" & N (Ranges));
                                    end if;
                                    Append (Tests, (if Ranges = 1 then "" else " | ") & T);
                                 end;
                              end;
                           else
                              C := C + 1;
                           end if;
                        end loop;
                     end if;
                     Append (Run_Code, "                if (st == " & Name & ") {" & LF);
                     if Count >= 20 and then Ranges <= 5 then
                        --  16 bytes at a time from the start: a short run (the usual one) is
                        --  one load, a few compares and a mask, and the byte that ends it is
                        --  then found by count.  The scalar loop after it reads the tail.
                        Append (Run_Code,
                          "#if defined(__SSE2__)" & LF
                          & "                    for (; i + 16 <= len; i += 16) {" & LF
                          & "                        __m128i v = _mm_loadu_si128((const __m128i *)(s + i))"
                          & To_String (Temps) & ";" & LF
                          & "                        unsigned mk = (unsigned)_mm_movemask_epi8("
                          & To_String (Tests) & ");" & LF
                          & "                        if (mk) { i += (size_t)__builtin_ctz(mk); break; }" & LF
                          & "                    }" & LF
                          & "#endif" & LF);
                     end if;
                     Append (Run_Code,
                       "                    while (run" & Name & "[(unsigned char)s[i]]) i++;" & LF
                       & "                    if (i > len) i = len;" & LF
                       & "                    continue;" & LF
                       & "                }" & LF);
                  end if;
               end;
            end loop;
         end;
      end if;
      Ascii_Dfa := Ascii_Ok;
   end;
   Append (Res, "    static const uint32_t lo[] = {" & To_String (Lo) & "};" & LF);
   Append (Res, "    static const uint32_t hi[] = {" & To_String (Hi) & "};" & LF);
   Append (Res, "    static const uint16_t to[] = {" & To_String (To) & "};" & LF);
   Append (Res, "    static const uint16_t first[] = {" & To_String (First) & "};" & LF);
   Append (Res, "    static const unsigned char acc[] = {" & To_String (Acc) & "};" & LF);
   Append (Res, "    size_t i = pos, best = 0; unsigned st = 0;" & LF);
   Append (Res, "    for (;;) {" & LF);
   Append (Res, "        uint32_t c; size_t n; unsigned k;" & LF);
   Append (Res, "        if (acc[st]) best = i - pos;" & LF);
   Append (Res, "        if (i >= len) break;" & LF);
   if Ascii_Dfa then
      Append (Res, "        c = (unsigned char)s[i];" & LF);
      Append (Res, "        if (c < 128) {" & LF);
      Append (Res, "            unsigned t = at[st * 128 + c];" & LF);
      Append (Res, "            if (t == 255) break;" & LF);
      Append (Res, "            i++;" & LF);
      Append (Res, "            if (t == st) {" & LF);
      Append (Res, To_String (Run_Code));
      Append (Res, "                while (i < len && (c = (unsigned char)s[i]) < 128 && at[st * 128 + c] == st) i++;" & LF);
      Append (Res, "                continue;" & LF);
      Append (Res, "            }" & LF);
      Append (Res, "            st = t; continue;" & LF);
      Append (Res, "        }" & LF);
   end if;
   Append (Res, "        n = hbnf_decode_utf8(s, i, len, &c);" & LF);
   Append (Res, "        if (!n) break;" & LF);
   Append (Res, "        for (k = first[st]; k < first[st + 1]; k++)" & LF);
   Append (Res, "            if (c >= lo[k] && c <= hi[k]) break;" & LF);
   Append (Res, "        if (k == first[st + 1]) break;" & LF);
   Append (Res, "        st = to[k]; i += n;" & LF);
   Append (Res, "    }" & LF);
   Append (Res, "    return best;" & LF & "}" & LF & LF);
   end if;
end;
else
Append (Res, "static size_t scan_" & C_Name (NM)
                 & "(const char *s, size_t pos, size_t len) {");
               Append (Res, LF);
               if Comment_Kind (Rules, NM) = "own" then
                  --  An own-line comment: only blanks between it and the
                  --  previous newline (or the start of the text).
                  Append (Res, "    { size_t i = pos;");
                  Append (Res, LF);
                  Append (Res, "      while (i > 0) { char c = s[i - 1];");
                  Append (Res, LF);
                  Append (Res, "        if (c == '\n') break;");
                  Append (Res, LF);
                  Append (Res, "        if (c != ' ' && c != '\t' && c != '\r') return 0;");
                  Append (Res, LF);
                  Append (Res, "        i--; } }");
                  Append (Res, LF);
               elsif Comment_Kind (Rules, NM) = "eol" then
                  --  A same-line comment: some non-blank precedes it on the
                  --  line it sits on.
                  Append (Res, "    { size_t i = pos; int own = 1;");
                  Append (Res, LF);
                  Append (Res, "      while (i > 0) { char c = s[i - 1];");
                  Append (Res, LF);
                  Append (Res, "        if (c == '\n') break;");
                  Append (Res, LF);
                  Append (Res, "        if (c != ' ' && c != '\t' && c != '\r') { own = 0; break; }");
                  Append (Res, LF);
                  Append (Res, "        i--; } if (own) return 0; }");
                  Append (Res, LF);
               end if;
               if Natural (DNF.Length) = 1 then
                  --  One branch: a sequence of code points, decoded in turn,
                  --  ending at most in one repetition.
                  Append (Res, "    size_t off = 0;");
                  Append (Res, LF);
                  for A of DNF (1) loop
                     case A.Kind is
                        when Single =>
                           Emit_Single (A, "    ", "return 0");
                        when Repeat =>
                           Emit_Repeat (A, "    ", "return 0");
                     end case;
                  end loop;
                  Append (Res, "    return off;");
                  Append (Res, LF);
               else
                  --  Alternation: try each branch, keep the longest match.
                  Append (Res, "    size_t best = 0;");
                  Append (Res, LF);
                  for B of DNF loop
                     Append (Res, "    do {");
                     Append (Res, LF);
                     Append (Res, "        size_t off = 0;");
                     Append (Res, LF);
                     for A of B loop
                        case A.Kind is
                           when Single =>
                              Emit_Single (A, "        ", "break");
                           when Repeat =>
                              Emit_Repeat (A, "        ", "break");
                        end case;
                     end loop;
                     Append (Res, "        if (off > best) best = off;");
                     Append (Res, LF);
                     Append (Res, "    } while (0);");
                     Append (Res, LF);
                  end loop;
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

      if HBNF_Grammar.Statements then
         Emit_Statement_Hooks (Res);
      end if;

      return To_String (Res);
   end Emit_Parser;

   function Emit_Lexer (Rules : Rule_Vectors.Vector) return String is
      Root_T : constant String := Root_Type (Rules);
      Res    : U;

      procedure Add (Tmpl : String) is
      begin
         Append (Res, LF);
         Append (Res, Fill (Tmpl, (1 => H ("root_type", Root_T))));
      end Add;
   begin
      if HBNF_Grammar.Statements then
         --  The statement driver, the macro expansion (or its stubs), and
         --  parse_text over the driver.
         Add ("c_statements");
         Add (if HBNF_Grammar.Macros_Rule /= "" then "c_macros"
              else "c_no_macros");
         Add ("c_stmt_text");
      end if;
      if Epilogue ("C") /= "" then
         Append (Res, LF);
         Append (Res, Epilogue ("C"));
      end if;
      return To_String (Res);
   end Emit_Lexer;

   --  =====================================================================
   --  Emit_Serializer: a pre-order walk of the tree Emit declares that
   --  assigns ids in traversal order and emits one flat, typed record per
   --  object through an abstract `emit` callback.  Cross-references are ids,
   --  never pointers, so the output can cross a process boundary.
   function Emit_Serializer (Rules : Rule_Vectors.Vector) return String is
      Noted : constant Boolean := Note_Root (Rules);
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
            Append (Buf, "    " & L_Foreach ("n", "head", Rule => To_String (Rules (Idx).Name)) & " n_++;");
            Append (Buf, LF);
            Append (Buf, "    emit(MSG_COUNT, &n_, sizeof n_);");
            Append (Buf, LF);
            Append (Buf, "    " & L_Foreach ("n", "head", Rule => To_String (Rules (Idx).Name)) & " {");
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
      Noted : constant Boolean := Note_Root (Rules);
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
            if Keeps_Tail (To_String (Rules (Idx).Name)) then
               Append (Buf, "    " & L_Init ("head", Rule => To_String (Rules (Idx).Name)));
            else
               Append (Buf, "    struct " & Pfx & C_Tag (To_String (Rules (Idx).Name))
                 & " **bt_ = &head->head;  head->head = NULL;");
            end if;
            Append (Buf, LF);
            Append (Buf, "    for (uint32_t _i = 0; _i < _n; _i++) {");
            Append (Buf, LF);
            Append (Buf, "        " & TN & " *nn = (" & TN & " *)hbnf_alloc(sizeof *nn);");
            Append (Buf, LF);
            Append (Buf, "        if (!nn) hbnf_oom();");
            Append (Buf, LF);
            Append (Buf, "        decode_" & CN & "(rd, nn);");
            Append (Buf, LF);
            if Keeps_Tail (To_String (Rules (Idx).Name)) then
               Append (Buf, "        " & L_Append ("head", "nn", Rule => To_String (Rules (Idx).Name)));
            else
               Append (Buf, "        *bt_ = nn; bt_ = &(nn)->_link;");
            end if;
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
      Noted : constant Boolean := Note_Root (Rules);
      N     : constant Natural := Natural (Rules.Length);
      Infos : Info_Vectors.Vector;

      --  The fields held by pointer (a cycle's, and --compact's): compared
      --  through the pointer, equal when both are absent.
      Backs : constant Edge_Vectors.Vector := Back_Edges_C (Rules);

      function Is_Back (Owner : Natural; Member : String) return Boolean is
      begin
         for E of Backs loop
            if E.Owner = Owner and then To_String (E.Member) = Member then
               return True;
            end if;
         end loop;
         return False;
      end Is_Back;

      function Ref_Kind (Name : String) return Class_Kind is
         J : constant Natural := Find (Rules, Alias_Target (Rules, Name));
      begin
         if J = 0 then
            return Scalar;
         end if;
         return Infos (J).Kind;
      end Ref_Kind;

      --  A string leaf: a rule that resolves to `const char *`, directly or
      --  as a union of such rules (obconf's `string = str | word |
      --  wildcard`), which Resolve_Type leaves unresolved.
      function Is_String (Name : String) return Boolean is
         J : constant Natural := Find (Rules, Alias_Target (Rules, Name));
      begin
         return Resolve_Type (Rules, Name) = "const char *"
           or else (J /= 0
                    and then Scalar_Union_Type (Rules, Rules (J).Pattern)
                             = "const char *");
      end Is_String;

      --  Compare one member field of two nodes named A and B.
      procedure Cmp_Field (Owner : Natural; Name : String; A, B : String;
                           Buf : in out U; Ind : String) is
         F : constant String := C_Field (Name);
      begin
         case Ref_Kind (Name) is
            when Struct | List =>
               if Ref_Kind (Name) = Struct and then Is_Back (Owner, Name) then
                  Append (Buf, Ind & "if ((" & A & "->" & F & " == NULL) != ("
                    & B & "->" & F & " == NULL)) return false;");
                  Append (Buf, LF);
                  Append (Buf, Ind & "if (" & A & "->" & F & " && !compare_"
                    & C_Name (Alias_Target (Rules, Name)) & "(" & A & "->" & F
                    & ", " & B & "->" & F & ")) return false;");
                  Append (Buf, LF);
               else
               Append (Buf, Ind & "if (!compare_"
                 & C_Name (Alias_Target (Rules, Name))
                 & "(&" & A & "->" & F & ", &" & B & "->" & F
                 & ")) return false;");
               Append (Buf, LF);
               end if;
            when Enum | Scalar =>
               --  A scalar that resolves to `const char *` is a string
               --  (strcmp, NULL handled); anything else (numbers, bools,
               --  enums) by value.
               if Is_String (Name) then
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
      procedure Cmp_Elem (Owner : Natural; Info : Rule_Info; A, B : String;
                          Buf : in out U; Ind : String) is
      begin
         if Info.Elem_Members.Is_Empty then
            if Info.Elem_Name /= Null_Unbounded_String then
               Cmp_Field (Owner, To_String (Info.Elem_Name), A, B, Buf, Ind);
            end if;
         else
            for M of Info.Elem_Members loop
               Cmp_Field (Owner, To_String (M.Name), A, B, Buf, Ind);
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
               Cmp_Field (Idx, To_String (M.Name), "a", "b", Buf, "    ");
            end loop;
         else
            Cmp_Elem (Idx, Info, "a", "b", Buf, "    ");
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
            Append (Buf, "    const " & TN & " *na = " & L_First ("a", Rule => To_String (Rules (Idx).Name))
              & ", *nb = " & L_First ("b", Rule => To_String (Rules (Idx).Name)) & ";");
            Append (Buf, LF);
            Append (Buf, "    while (na && nb) {");
            Append (Buf, LF);
            Append (Buf, "        if (!compare_" & CN & "_fields(na, nb)) return false;");
            Append (Buf, LF);
            Append (Buf, "        na = " & L_Next ("na", Rule => To_String (Rules (Idx).Name)) & "; nb = " & L_Next ("nb", Rule => To_String (Rules (Idx).Name)) & ";");
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
