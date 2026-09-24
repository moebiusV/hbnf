pragma Ada_2022;

with Ada.Text_IO;

package body HBNF_Grammar is

   --  Schema-level metadata gathered by Parse: the declared language (default
   --  "C") and the optional raw `%{ ... %}` preamble and epilogue blocks.
   Schema_Language : Unbounded_String := To_Unbounded_String ("C");
   Preamble_Code   : Unbounded_String := Null_Unbounded_String;
   Epilogue_Code   : Unbounded_String := Null_Unbounded_String;
   Word_Chars_Code : Unbounded_String := Null_Unbounded_String;
   Type_Prefix_Code : Unbounded_String := Null_Unbounded_String;
   Conf_Type_Code  : Unbounded_String := Null_Unbounded_String;
   List_Head_Code    : Unbounded_String := Null_Unbounded_String;
   List_Entry_Code   : Unbounded_String := Null_Unbounded_String;
   List_Init_Code    : Unbounded_String := Null_Unbounded_String;
   List_Append_Code  : Unbounded_String := Null_Unbounded_String;
   List_Foreach_Code : Unbounded_String := Null_Unbounded_String;
   List_First_Code   : Unbounded_String := Null_Unbounded_String;
   List_Next_Code    : Unbounded_String := Null_Unbounded_String;
   List_Relink_Code  : Unbounded_String := Null_Unbounded_String;

   --  `action name { code }` directives waiting for their rule: a binding
   --  file attaches actions to rules an included grammar defines, so they
   --  are resolved once the includes are merged (Parse_File).
   type Attach is record
      Name : Unbounded_String;
      Code : Unbounded_String;
      Line : Positive := 1;
   end record;
   package Attach_Vectors is new Ada.Containers.Vectors (Positive, Attach);
   Pending_Actions : Attach_Vectors.Vector;

   --  Parse_File nesting: 0 outside any call, 1 for the top-level schema.
   File_Depth : Natural := 0;

   --  ====================================================================
   --  Lexer
   --  ====================================================================

   type Tok_Kind is (T_Name, T_String, T_Number, T_Eq, T_Slash, T_LParen,
                     T_RParen, T_LBrack, T_RBrack, T_Star, T_Code,
                     T_Comment, T_Newline, T_EOF);

   type Token is record
      Kind : Tok_Kind;
      Line : Positive         := 1;
      Col  : Positive         := 1;
      Text : Unbounded_String := Null_Unbounded_String;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors (Positive, Token);

   type Lang_Kind is (C_Lang, Rust_Lang, Zig_Lang, Ada_Lang);

   --  Find the `language X` declaration (the first word "language" followed
   --  by a name); defaults to C.  Drives the brace counter's comment/char
   --  handling inside `{ }` code blocks, which differs per language.
   function Detect_Language (Text : String) return Lang_Kind is
      Lang : Lang_Kind := C_Lang;
      I    : Natural  := Text'First;
   begin
      while I <= Text'Last loop
         if Text (I) in 'a' .. 'z' or else Text (I) in 'A' .. 'Z'
           or else Text (I) = '_'
         then
            declare
               S : constant Natural := I;
            begin
               while I <= Text'Last
                 and then (Text (I) in 'a' .. 'z' or else Text (I) in 'A' .. 'Z'
                   or else Text (I) in '0' .. '9' or else Text (I) = '_'
                   or else Text (I) = '-')
               loop
                  I := I + 1;
               end loop;
               if Text (S .. I - 1) = "language" then
                  while I <= Text'Last
                    and then Text (I) in ' ' | ASCII.HT
                  loop
                     I := I + 1;
                  end loop;
                  if I <= Text'Last
                    and then (Text (I) in 'a' .. 'z'
                      or else Text (I) in 'A' .. 'Z')
                  then
                     declare
                        S2 : constant Natural := I;
                     begin
                        while I <= Text'Last
                          and then (Text (I) in 'a' .. 'z'
                            or else Text (I) in 'A' .. 'Z')
                        loop
                           I := I + 1;
                        end loop;
                        if Text (S2 .. I - 1) = "Rust" then
                           Lang := Rust_Lang;
                        elsif Text (S2 .. I - 1) = "Zig" then
                           Lang := Zig_Lang;
                        elsif Text (S2 .. I - 1) = "Ada" then
                           Lang := Ada_Lang;
                        end if;
                        return Lang;
                     end;
                  end if;
               end if;
            end;
         else
            I := I + 1;
         end if;
      end loop;
      return Lang;
   end Detect_Language;

   function Trim (S : String) return String is
      First : Natural := S'First;
      Last  : Natural := S'Last;
   begin
      while First <= Last
        and then (S (First) = ' ' or else S (First) = ASCII.HT)
      loop
         First := First + 1;
      end loop;
      while Last >= First
        and then (S (Last) = ' ' or else S (Last) = ASCII.HT)
      loop
         Last := Last - 1;
      end loop;
      if First > Last then
         return "";
      end if;
      return S (First .. Last);
   end Trim;

   function Hex_Digit (C : Character) return Integer is
   begin
      if C in '0' .. '9' then
         return Character'Pos (C) - Character'Pos ('0');
      elsif C in 'a' .. 'f' then
         return Character'Pos (C) - Character'Pos ('a') + 10;
      elsif C in 'A' .. 'F' then
         return Character'Pos (C) - Character'Pos ('A') + 10;
      else
         return -1;
      end if;
   end Hex_Digit;

   function Lex (Text : String) return Token_Vectors.Vector is
      Toks : Token_Vectors.Vector;
      I    : Natural  := Text'First;
      Line : Positive := 1;
      Col  : Positive := 1;
      Lang : constant Lang_Kind := Detect_Language (Text);

      procedure Emit (K : Tok_Kind; S : String := "") is
      begin
         Token_Vectors.Append
           (Toks, Token'(K, Line, Col, To_Unbounded_String (S)));
      end Emit;

      function Name_Start (C : Character) return Boolean is
         ((C in 'a' .. 'z') or (C in 'A' .. 'Z') or C = '_');

      function Name_Char (C : Character) return Boolean is
         (Name_Start (C) or (C in '0' .. '9') or C = '-');

   begin
      while I <= Text'Last loop
         case Text (I) is
            when ' ' | ASCII.HT =>
               I := I + 1;  Col := Col + 1;
            when ASCII.LF =>
               Emit (T_Newline);  I := I + 1;  Line := Line + 1;  Col := 1;
            when ASCII.CR =>
               I := I + 1;
            when ';' =>
               declare
                  CL    : constant Positive := Line;
                  CC    : constant Positive := Col;
                  Start : constant Positive := I + 1;
               begin
                  I := I + 1;
                  while I <= Text'Last and then Text (I) /= ASCII.LF loop
                     I := I + 1;
                  end loop;
                  Token_Vectors.Append
                    (Toks, Token'(T_Comment, CL, CC,
                                  To_Unbounded_String
                                    (Trim (Text (Start .. I - 1)))));
               end;
            when '"' =>
               declare
                  Buf    : Unbounded_String := Null_Unbounded_String;
                  Closed : Boolean := False;
               begin
                  I := I + 1;
                  Col := Col + 1;
                  while I <= Text'Last loop
                     if Text (I) = '"' then
                        I := I + 1;
                        Col := Col + 1;
                        Closed := True;
                        exit;
                     elsif Text (I) = '\' then
                        --  Decode a C-style escape: "\n" is the newline token
                        --  and "\xHH" any byte.
                        I := I + 1;
                        Col := Col + 1;
                        if I > Text'Last then
                           raise Parse_Error with
                             Integer'Image (Line) & ":" & Integer'Image (Col) &
                             ": escape at end of string";
                        end if;
                        if Text (I) = 'x' then
                           declare
                              Val : Natural := 0;
                              N   : Natural := 0;
                           begin
                              I := I + 1;
                              Col := Col + 1;
                              while I <= Text'Last
                                and then Hex_Digit (Text (I)) >= 0
                              loop
                                 Val := Val * 16 + Hex_Digit (Text (I));
                                 N := N + 1;
                                 I := I + 1;
                                 Col := Col + 1;
                              end loop;
                              if N = 0 or else Val > 255 then
                                 raise Parse_Error with
                                   Integer'Image (Line) & ":" &
                                   Integer'Image (Col) & ": bad hex escape";
                              end if;
                              Append (Buf, Character'Val (Val));
                           end;
                        else
                           declare
                              Ch : Character;
                           begin
                              case Text (I) is
                                 when 'a' => Ch := Character'Val (7);
                                 when 'b' => Ch := Character'Val (8);
                                 when 'f' => Ch := Character'Val (12);
                                 when 'n' => Ch := Character'Val (10);
                                 when 'r' => Ch := Character'Val (13);
                                 when 't' => Ch := Character'Val (9);
                                 when 'v' => Ch := Character'Val (11);
                                 when '\' => Ch := '\';
                                 when '"' => Ch := '"';
                                 when ''' => Ch := ''';
                                 when others =>
                                    raise Parse_Error with
                                      Integer'Image (Line) & ":" &
                                      Integer'Image (Col) &
                                      ": unknown escape '" & Text (I) & "'";
                              end case;
                              Append (Buf, Ch);
                              I := I + 1;
                              Col := Col + 1;
                           end;
                        end if;
                     else
                        Append (Buf, Text (I));
                        I := I + 1;
                        Col := Col + 1;
                     end if;
                  end loop;
                  if not Closed then
                     raise Parse_Error with
                       Integer'Image (Line) & ":" & Integer'Image (Col) &
                       ": unterminated string literal";
                  end if;
                  Emit (T_String, To_String (Buf));
               end;
            when '=' => Emit (T_Eq);     I := I + 1;  Col := Col + 1;
            when '/' => Emit (T_Slash);  I := I + 1;  Col := Col + 1;
            when '(' => Emit (T_LParen); I := I + 1;  Col := Col + 1;
            when ')' => Emit (T_RParen); I := I + 1;  Col := Col + 1;
            when '[' => Emit (T_LBrack); I := I + 1;  Col := Col + 1;
            when ']' => Emit (T_RBrack); I := I + 1;  Col := Col + 1;
            when '*' => Emit (T_Star);   I := I + 1;  Col := Col + 1;
            when '{' =>
               --  A raw code block (preamble, jet, or epilogue): capture the
               --  text between matching braces.  Braces nest, and a `"` string
               --  literal is copied verbatim so a `}` inside one is not taken
               --  as the block's close.
               declare
                  Depth : Natural := 1;
                  Buf   : Unbounded_String := Null_Unbounded_String;
               begin
                  I := I + 1;  Col := Col + 1;
                  while I <= Text'Last loop
                     case Text (I) is
                        when '{' =>
                           Depth := Depth + 1;
                           Append (Buf, Text (I));
                           I := I + 1;  Col := Col + 1;
                        when '}' =>
                           Depth := Depth - 1;
                           if Depth = 0 then
                              I := I + 1;  Col := Col + 1;
                              exit;
                           end if;
                           Append (Buf, Text (I));
                           I := I + 1;  Col := Col + 1;
                        when '"' =>
                           Append (Buf, Text (I));
                           I := I + 1;  Col := Col + 1;
                           while I <= Text'Last and then Text (I) /= '"' loop
                              if Text (I) = '\' and then I < Text'Last then
                                 Append (Buf, Text (I));
                                 I := I + 1;  Col := Col + 1;
                              end if;
                              Append (Buf, Text (I));
                              I := I + 1;  Col := Col + 1;
                           end loop;
                           if I <= Text'Last then
                              Append (Buf, Text (I));
                              I := I + 1;  Col := Col + 1;
                           end if;
                        when ''' =>
                           if Lang = Ada_Lang and then I > Text'First
                             and then (Text (I - 1) in 'a' .. 'z'
                               or else Text (I - 1) in 'A' .. 'Z'
                               or else Text (I - 1) in '0' .. '9'
                               or else Text (I - 1) = '_')
                           then
                              --  Ada attribute (X'Pos): skip quote + name.
                              Append (Buf, Text (I));
                              I := I + 1;  Col := Col + 1;
                              while I <= Text'Last
                                and then (Text (I) in 'a' .. 'z'
                                  or else Text (I) in 'A' .. 'Z'
                                  or else Text (I) in '0' .. '9'
                                  or else Text (I) = '_')
                              loop
                                 Append (Buf, Text (I));
                                 I := I + 1;  Col := Col + 1;
                              end loop;
                           else
                              --  Char literal 'x': copied verbatim.
                              Append (Buf, Text (I));
                              I := I + 1;  Col := Col + 1;
                              while I <= Text'Last and then Text (I) /= ''' loop
                                 if Text (I) = '\' and then I < Text'Last then
                                    Append (Buf, Text (I));
                                    I := I + 1;  Col := Col + 1;
                                 end if;
                                 Append (Buf, Text (I));
                                 I := I + 1;  Col := Col + 1;
                              end loop;
                              if I <= Text'Last then
                                 Append (Buf, Text (I));
                                 I := I + 1;  Col := Col + 1;
                              end if;
                           end if;
                        when '/' =>
                           if (Lang = C_Lang or else Lang = Rust_Lang)
                             and then I < Text'Last and then Text (I + 1) = '*'
                           then
                              --  Block comment: skip to */.
                              Append (Buf, Text (I));
                              Append (Buf, Text (I + 1));
                              I := I + 2;  Col := Col + 2;
                              while I <= Text'Last loop
                                 if Text (I) = '*' and then I < Text'Last
                                   and then Text (I + 1) = '/'
                                 then
                                    Append (Buf, Text (I));
                                    Append (Buf, Text (I + 1));
                                    I := I + 2;  Col := Col + 2;
                                    exit;
                                 end if;
                                 if Text (I) = ASCII.LF then
                                    Line := Line + 1;  Col := 1;
                                 else
                                    Col := Col + 1;
                                 end if;
                                 Append (Buf, Text (I));
                                 I := I + 1;
                              end loop;
                           elsif Lang /= Ada_Lang
                             and then I < Text'Last and then Text (I + 1) = '/'
                           then
                              --  Line comment: skip to newline.
                              while I <= Text'Last and then Text (I) /= ASCII.LF loop
                                 Append (Buf, Text (I));
                                 I := I + 1;  Col := Col + 1;
                              end loop;
                           else
                              Append (Buf, Text (I));
                              I := I + 1;  Col := Col + 1;
                           end if;
                        when '-' =>
                           if Lang = Ada_Lang and then I < Text'Last
                             and then Text (I + 1) = '-'
                           then
                              --  Ada line comment: skip to newline.
                              while I <= Text'Last and then Text (I) /= ASCII.LF loop
                                 Append (Buf, Text (I));
                                 I := I + 1;  Col := Col + 1;
                              end loop;
                           else
                              Append (Buf, Text (I));
                              I := I + 1;  Col := Col + 1;
                           end if;
                        when ASCII.LF =>
                           Append (Buf, Text (I));
                           I := I + 1;  Line := Line + 1;  Col := 1;
                        when others =>
                           Append (Buf, Text (I));
                           I := I + 1;  Col := Col + 1;
                     end case;
                  end loop;
                  if Depth > 0 then
                     raise Parse_Error with
                       Integer'Image (Line) & ":" & Integer'Image (Col) &
                       ": unterminated code block (missing '}')";
                  end if;
                  Emit (T_Code, To_String (Buf));
               end;
            when '0' .. '9' =>
               declare
                  Start : constant Positive := I;
               begin
                  while I <= Text'Last and then Text (I) in '0' .. '9' loop
                     I := I + 1;
                  end loop;
                  Emit (T_Number, Text (Start .. I - 1));
                  Col := Col + (I - Start);
               end;
            when others =>
               if Name_Start (Text (I)) then
                  declare
                     Start : constant Positive := I;
                  begin
                     while I <= Text'Last and then Name_Char (Text (I)) loop
                        I := I + 1;
                     end loop;
                     Emit (T_Name, Text (Start .. I - 1));
                     Col := Col + (I - Start);
                  end;
               else
                  raise Parse_Error with
                    Integer'Image (Line) & ":" & Integer'Image (Col) &
                    ": unexpected character '" & Text (I) & "'";
               end if;
         end case;
      end loop;
      Emit (T_EOF);
      return Toks;
   end Lex;

   --  ====================================================================
   --  Parser
   --  ====================================================================

   type Parser is record
      Toks : Token_Vectors.Vector;
      Pos  : Positive := 1;
   end record;

   function Cur (P : Parser) return Token is (P.Toks (P.Pos));

   --  Store the raw C for one list operation ("head", "entry", "init",
   --  "append", "foreach", "first", "next", "relink").
   procedure Set_List_Override (Op : String; Code : String) is
      V : constant Unbounded_String := To_Unbounded_String (Code);
   begin
      if Op = "head" then
         List_Head_Code := V;
      elsif Op = "entry" then
         List_Entry_Code := V;
      elsif Op = "init" then
         List_Init_Code := V;
      elsif Op = "append" then
         List_Append_Code := V;
      elsif Op = "foreach" then
         List_Foreach_Code := V;
      elsif Op = "first" then
         List_First_Code := V;
      elsif Op = "next" then
         List_Next_Code := V;
      elsif Op = "relink" then
         List_Relink_Code := V;
      else
         raise Parse_Error with "listops: unknown operation `" & Op & "`";
      end if;
   end Set_List_Override;

   --  The lexical spelling of a token: the text for names/numbers/strings/
   --  code, the punctuation character itself otherwise (so a bare C type
   --  like `char[16]` reconstructs its brackets and stars).
   function Lexical (T : Token) return String is
   begin
      case T.Kind is
         when T_Eq => return "=";
         when T_Slash => return "/";
         when T_LParen => return "(";
         when T_RParen => return ")";
         when T_LBrack => return "[";
         when T_RBrack => return "]";
         when T_Star => return "*";
         when others => return To_String (T.Text);
      end case;
   end Lexical;

   --  A prefix must start a C identifier and continue one.
   function Valid_Prefix (S : String) return Boolean is
     (S'Length > 0
      and then (S (S'First) in 'a' .. 'z' | 'A' .. 'Z' | '_')
      and then (for all C of S => C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_'));

   procedure Next (P : in out Parser) is
   begin
      P.Pos := P.Pos + 1;
   end Next;

   procedure Expect (P : in out Parser; K : Tok_Kind; What : String) is
      T : constant Token := Cur (P);
   begin
      if T.Kind /= K then
         raise Parse_Error with
           Integer'Image (T.Line) & ":" & Integer'Image (T.Col) &
           ": expected " & What;
      end if;
      Next (P);
   end Expect;

   function Expect_Name (P : in out Parser) return Unbounded_String is
      T : constant Token := Cur (P);
   begin
      if T.Kind /= T_Name then
         raise Parse_Error with
           Integer'Image (T.Line) & ":" & Integer'Image (T.Col) &
           ": expected a name";
      end if;
      Next (P);
      return T.Text;
   end Expect_Name;

   function Parse_Atom (P : in out Parser) return Element_Access;
   function Parse_Element (P : in out Parser) return Element_Access;
   function Parse_Pattern (P : in out Parser) return Element_Vectors.Vector;
   function Parse_Alternation (P : in out Parser)
     return Element_Vectors.Vector;

   procedure Append_All
     (Dst : in out Element_Vectors.Vector; Src : Element_Vectors.Vector) is
   begin
      for E of Src loop
         Element_Vectors.Append (Dst, E);
      end loop;
   end Append_All;

   function Parse_Atom (P : in out Parser) return Element_Access is
   begin
      case Cur (P).Kind is
         when T_String =>
            declare
               Lit : constant Unbounded_String := Cur (P).Text;
            begin
               Next (P);
               return new Element'(Kind => Literal, Min => 1, Max => 1,
                                   Lit => Lit);
            end;
         when T_Name =>
            declare
               N : constant Unbounded_String := Expect_Name (P);
            begin
               return new Element'
                 (Kind => Name, Min => 1, Max => 1, Name => N);
            end;
         when T_LParen =>
            Next (P);
            declare
               Items : constant Element_Vectors.Vector :=
                 Parse_Alternation (P);
            begin
               Expect (P, T_RParen, "')'");
               return new Element'
                 (Kind => Group, Min => 1, Max => 1, Items => Items);
            end;
         when T_LBrack =>
            Next (P);
            declare
               Items : constant Element_Vectors.Vector :=
                 Parse_Alternation (P);
            begin
               Expect (P, T_RBrack, "']'");
               return new Element'
                 (Kind => Group, Min => 0, Max => 1, Items => Items);
            end;
         when others =>
            declare
               T : constant Token := Cur (P);
            begin
               raise Parse_Error with
                 Integer'Image (T.Line) & ":" & Integer'Image (T.Col) &
                 ": expected a literal, name, or group";
            end;
      end case;
   end Parse_Atom;

   function Parse_Element (P : in out Parser) return Element_Access is
      Min        : Natural := 1;
      Max        : Integer := 1;
      Has_Prefix : Boolean := False;
   begin
      --  ABNF prefix repetition:  *elem, 1*elem, n*melem, nelem.
      if Cur (P).Kind = T_Star then
         Min := 0;  Max := -1;  Has_Prefix := True;  Next (P);
      elsif Cur (P).Kind = T_Number then
         Min := Natural'Value (To_String (Cur (P).Text));  Next (P);
         if Cur (P).Kind = T_Star then
            Next (P);
            if Cur (P).Kind = T_Number then
               Max := Integer'Value (To_String (Cur (P).Text));  Next (P);
            else
               Max := -1;
            end if;
         else
            Max := Min;
         end if;
         Has_Prefix := True;
      end if;

      declare
         E : constant Element_Access := Parse_Atom (P);
      begin
         if Has_Prefix then
            E.Min := Min;  E.Max := Max;
         end if;
         return E;
      end;
   end Parse_Element;

   --  Parse a sequence of elements up to any structural token.  The caller
   --  inspects what stopped it.
   function Parse_Pattern (P : in out Parser) return Element_Vectors.Vector is
      V : Element_Vectors.Vector;
   begin
      loop
         exit when Cur (P).Kind in
           T_Newline | T_RParen | T_RBrack | T_Slash | T_Comment | T_Code
           | T_EOF;
         Element_Vectors.Append (V, Parse_Element (P));
      end loop;
      return V;
   end Parse_Pattern;

   --  ABNF "alternation": concatenation *( "/" concatenation ), flattened
   --  with Alt separator elements, used for a group/bracket's inside and a
   --  rule's whole RHS; the caller checks the terminating token.
   function Parse_Alternation (P : in out Parser)
     return Element_Vectors.Vector is
      V : Element_Vectors.Vector;
   begin
      Append_All (V, Parse_Pattern (P));
      loop
         --  A newline before `/` is a continuation, not the end of the rule:
         --  allow a multi-line alternation (`x = a` newline `/ b`).  Peek
         --  past the newline run and commit only if the next token is `/`.
         declare
            Pos : Positive := P.Pos;
         begin
            while P.Toks (Pos).Kind in T_Newline | T_Comment loop
               Pos := Pos + 1;
            end loop;
            exit when P.Toks (Pos).Kind /= T_Slash;
            P.Pos := Pos;
         end;
         Next (P);
         Element_Vectors.Append
           (V, new Element'(Kind => Alt, Min => 1, Max => 1));
         Append_All (V, Parse_Pattern (P));
      end loop;
      return V;
   end Parse_Alternation;

   function Parse (Text : String) return Rule_Vectors.Vector is
      P     : Parser := (Toks => Lex (Text), Pos => 1);
      Rules : Rule_Vectors.Vector;
      Name  : Unbounded_String;
   begin
      --  Header: an optional `%{ ... %}` preamble and/or `language X`, each
      --  preceded by blank lines and `;` comment lines (which are discarded
      --  as header material).  Lookahead keeps a leading comment block that
      --  belongs to the first rule instead.
      declare
         Mark : Natural;
      begin
         Mark := P.Pos;
         while Cur (P).Kind in T_Newline | T_Comment loop
            Next (P);
         end loop;
         if Cur (P).Kind = T_Code
           or else (Cur (P).Kind = T_Name
                    and then (To_String (Cur (P).Text) = "language"
                              or else To_String (Cur (P).Text) = "wordchars"
                              or else To_String (Cur (P).Text) = "prefix"
                              or else To_String (Cur (P).Text) = "conf"
                              or else To_String (Cur (P).Text) = "listops"))
         then
            P.Pos := Mark;
            loop
               while Cur (P).Kind in T_Newline | T_Comment loop
                  Next (P);
               end loop;
               if Cur (P).Kind = T_Code then
                  if Preamble_Code = Null_Unbounded_String then
                     Preamble_Code := Cur (P).Text;
                  end if;
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "language"
               then
                  Next (P);
                  if Cur (P).Kind /= T_Name then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" &
                       Integer'Image (Cur (P).Col) &
                       ": expected a language name (C, Rust, Zig, or Ada)";
                  end if;
                  Schema_Language := Cur (P).Text;
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "wordchars"
               then
                  Next (P);
                  if Cur (P).Kind /= T_String then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" &
                       Integer'Image (Cur (P).Col) &
                       ": expected a quoted character set after `wordchars`";
                  end if;
                  Word_Chars_Code := Cur (P).Text;
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "prefix"
               then
                  --  `prefix "pf_"`: put in front of every generated type
                  --  and struct tag, keeping them out of the system's names.
                  Next (P);
                  if Cur (P).Kind /= T_String
                    or else not Valid_Prefix (To_String (Cur (P).Text))
                  then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" &
                       Integer'Image (Cur (P).Col) &
                       ": expected a quoted C identifier prefix after `prefix`";
                  end if;
                  --  Includes are parsed first, so the including file's
                  --  directive, seen last, wins; --prefix= wins over both.
                  Type_Prefix_Code := Cur (P).Text;
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "conf"
               then
                  --  `conf struct ntpd_conf`: the daemon's own conf struct
                  --  the C --conf wrapper fills (instead of an AST-shaped
                  --  one).  The type is the bare C spelling, joined with
                  --  single spaces (`struct ntpd_conf`).
                  Next (P);
                  declare
                     Buf : Unbounded_String := Null_Unbounded_String;
                  begin
                     while Cur (P).Kind = T_Name loop
                        if Buf /= Null_Unbounded_String then
                           Append (Buf, " ");
                        end if;
                        Append (Buf, Cur (P).Text);
                        Next (P);
                     end loop;
                     if Buf = Null_Unbounded_String then
                        raise Parse_Error with
                          Integer'Image (Cur (P).Line) & ":" &
                          Integer'Image (Cur (P).Col) &
                          ": expected a C struct type after `conf`";
                     end if;
                     Conf_Type_Code := Buf;
                  end;
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "listops"
               then
                  --  `listops { head { … } entry { … } … }`: the raw C for
                  --  each list operation.  The block is re-lexed to read the
                  --  `op { … }` pairs; each op is optional.
                  Next (P);
                  if Cur (P).Kind /= T_Code then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" &
                       Integer'Image (Cur (P).Col) &
                       ": expected a code block after `listops`";
                  end if;
                  declare
                     Tks : constant Token_Vectors.Vector :=
                       Lex (To_String (Cur (P).Text));
                     J   : Natural := 1;
                  begin
                     while J <= Natural (Tks.Length) loop
                        while J <= Natural (Tks.Length)
                          and then Tks (J).Kind in T_Newline | T_Comment
                        loop
                           J := J + 1;
                        end loop;
                        exit when J > Natural (Tks.Length)
                          or else Tks (J).Kind = T_EOF;
                        if Tks (J).Kind /= T_Name then
                           raise Parse_Error with
                             "listops: expected an operation name (head, "
                             & "entry, init, append, foreach, first, next, "
                             & "relink)";
                        end if;
                        declare
                           Op : constant String := To_String (Tks (J).Text);
                        begin
                           J := J + 1;
                           if J > Natural (Tks.Length)
                             or else Tks (J).Kind /= T_Code
                           then
                              raise Parse_Error with
                                "listops: expected a code block after `"
                                & Op & "`";
                           end if;
                           Set_List_Override (Op, To_String (Tks (J).Text));
                           J := J + 1;
                        end;
                     end loop;
                  end;
                  Next (P);
               else
                  exit;
               end if;
            end loop;
         else
            P.Pos := Mark;
         end if;
      end;

      loop
         while Cur (P).Kind = T_Newline loop
            Next (P);
         end loop;
         exit when Cur (P).Kind = T_EOF;

         declare
            Leading  : Unbounded_String := Null_Unbounded_String;
            Trailing : Unbounded_String := Null_Unbounded_String;
            C_Type   : Unbounded_String := Null_Unbounded_String;
         begin
            --  A leading comment block: `;` comment lines before the rule.
            --  Blank lines between them do not break the block.
            loop
               while Cur (P).Kind = T_Newline loop
                  Next (P);
               end loop;
               exit when Cur (P).Kind /= T_Comment;
               if Leading /= Null_Unbounded_String then
                  Append (Leading, ASCII.LF);
               end if;
               Append (Leading, Cur (P).Text);
               Next (P);
            end loop;

            --  Epilogue: a raw code block after the rules.
            if Cur (P).Kind = T_Code then
               Epilogue_Code := Cur (P).Text;
               Next (P);
               exit;
            end if;
            exit when Cur (P).Kind = T_EOF;

            --  `action name { code }`: an action jet for a rule defined here
            --  or in an included file.  A binding file uses it to keep a
            --  daemon's actions (and its C headers) out of the grammar.
            if Cur (P).Kind = T_Name
              and then To_String (Cur (P).Text) = "action"
              and then P.Pos + 2 <= Natural (P.Toks.Length)
              and then P.Toks (P.Pos + 1).Kind = T_Name
              and then P.Toks (P.Pos + 2).Kind = T_Code
            then
               Pending_Actions.Append
                 (Attach'(Name => P.Toks (P.Pos + 1).Text,
                          Code => P.Toks (P.Pos + 2).Text,
                          Line => Cur (P).Line));
               Next (P);
               Next (P);
               Next (P);
               if Cur (P).Kind = T_Comment then
                  Next (P);
               end if;
               goto Next_Item;
            end if;

            --  `[ C-type ] name =`: the name is the last identifier before
            --  `=`; any tokens before it are the storage class, joined with
            --  single spaces (`int port`, `struct pf_rule_addr src`,
            --  `char[IFNAMSIZ] ifname`).  Untyped rules have a single name.
            declare
               Head : Token_Vectors.Vector;
            begin
               while Cur (P).Kind not in T_Eq | T_EOF loop
                  Head.Append (Cur (P));
                  Next (P);
               end loop;
               if Cur (P).Kind /= T_Eq then
                  raise Parse_Error with
                    Integer'Image (Cur (P).Line) & ":" &
                    Integer'Image (Cur (P).Col) & ": expected '='";
               end if;
               if Head.Is_Empty or else Head.Last_Element.Kind /= T_Name then
                  raise Parse_Error with
                    Integer'Image (Cur (P).Line) & ":" &
                    Integer'Image (Cur (P).Col) & ": expected a rule name";
               end if;
               Name := Head.Last_Element.Text;
               C_Type := Null_Unbounded_String;
               for I in 1 .. Natural (Head.Length) - 1 loop
                  if C_Type /= Null_Unbounded_String then
                     Append (C_Type, " ");
                  end if;
                  Append (C_Type, Lexical (Head (I)));
               end loop;
               Next (P);   --  the '='
            end;

            if Cur (P).Kind = T_Code then
               --  A jet: `name = %{ <code> %}` — a hand-written scanner.
               Rule_Vectors.Append
                 (Rules,
                  Rule'(Name            => Name,
                        Pattern         => Element_Vectors.Empty_Vector,
                        Leading_Comment => Leading,
                        Trailing_Comment => Trailing,
                        Jet_Code        => Cur (P).Text,
                        C_Type          => C_Type,
                        Action_Code     => Null_Unbounded_String));
               Next (P);
            else
               declare
                  Action  : Unbounded_String := Null_Unbounded_String;
                  Pattern : constant Element_Vectors.Vector :=
                    Parse_Alternation (P);
               begin
                  --  An action jet: `name = pattern { code }` — the code
                  --  block after the pattern is run in the bind walk, not
                  --  during parsing.  A trailing comment sits after it.
                  if Cur (P).Kind = T_Code then
                     Action := Cur (P).Text;
                     Next (P);
                  end if;
                  --  A trailing comment sits on the rule's own line, after
                  --  the pattern (Parse_Pattern stops at T_Comment).
                  if Cur (P).Kind = T_Comment then
                     Trailing := Cur (P).Text;
                     Next (P);
                  end if;
                  Rule_Vectors.Append
                    (Rules,
                     Rule'(Name            => Name,
                           Pattern         => Pattern,
                           Leading_Comment => Leading,
                           Trailing_Comment => Trailing,
                           Jet_Code        => Null_Unbounded_String,
                           C_Type          => C_Type,
                           Action_Code     => Action));
               end;
            end if;
         end;
         <<Next_Item>>
      end loop;
      return Rules;
   end Parse;

   function Parse_File (Path : String) return Rule_Vectors.Vector is

      function Read_File (P : String) return String is
         F   : Ada.Text_IO.File_Type;
         Buf : Unbounded_String;
      begin
         Ada.Text_IO.Open (F, Ada.Text_IO.In_File, P);
         while not Ada.Text_IO.End_Of_File (F) loop
            Append (Buf, Ada.Text_IO.Get_Line (F));
            Append (Buf, ASCII.LF);
         end loop;
         Ada.Text_IO.Close (F);
         return To_String (Buf);
      end Read_File;

      --  The directory of Path ("" when it has no slash), so nested includes
      --  resolve relative to the including file, not the process cwd.
      function Dir_Of (P : String) return String is
      begin
         for I in reverse P'Range loop
            if P (I) = '/' then
               return P (P'First .. I - 1);
            end if;
         end loop;
         return "";
      end Dir_Of;

      function Join (Dir, Name : String) return String is
      begin
         if Dir = "" then
            return Name;
         end if;
         return Dir & "/" & Name;
      end Join;

      --  The quoted path if Line is `include "path"` (leading whitespace
      --  tolerated); Null_Unbounded_String otherwise.
      function Include_Target (Line : String) return Unbounded_String is
         I : Natural := Line'First;
         procedure Skip_WS is
         begin
            while I <= Line'Last and then Line (I) in ' ' | ASCII.HT loop
               I := I + 1;
            end loop;
         end Skip_WS;
      begin
         Skip_WS;
         declare
            W : constant String := "include";
         begin
            if I > Line'Last - W'Length + 1
              or else Line (I .. I + W'Length - 1) /= W
            then
               return Null_Unbounded_String;
            end if;
            I := I + W'Length;
         end;
         if I > Line'Last or else Line (I) not in ' ' | ASCII.HT then
            return Null_Unbounded_String;
         end if;
         Skip_WS;
         if I > Line'Last or else Line (I) /= '"' then
            return Null_Unbounded_String;
         end if;
         I := I + 1;
         declare
            S : constant Natural := I;
         begin
            while I <= Line'Last and then Line (I) /= '"' loop
               I := I + 1;
            end loop;
            if I > Line'Last then
               return Null_Unbounded_String;
            end if;
            return To_Unbounded_String (Line (S .. I - 1));
         end;
      end Include_Target;

      --  Walk Text (a file in directory Dir) line by line: `include` lines are
      --  loaded recursively into Acc; every other line is kept verbatim in Out.
      procedure Expand (Text : String; Dir : String;
                        Acc : in out Rule_Vectors.Vector;
                        Kept : in out Unbounded_String)
      is
         Start : Natural := Text'First;
      begin
         while Start <= Text'Last loop
            declare
               Stop : Natural := Start;
            begin
               while Stop <= Text'Last and then Text (Stop) /= ASCII.LF loop
                  Stop := Stop + 1;
               end loop;
               declare
                  Line   : constant String := Text (Start .. Stop - 1);
                  Target : constant Unbounded_String := Include_Target (Line);
               begin
                  if Target /= Null_Unbounded_String then
                     declare
                        Sub : constant Rule_Vectors.Vector :=
                          Parse_File (Join (Dir, To_String (Target)));
                     begin
                        for R of Sub loop
                           Acc.Append (R);
                        end loop;
                     end;
                  else
                     Append (Kept, Line);
                     Append (Kept, ASCII.LF);
                  end if;
               end;
               Start := Stop + 1;
            end;
         end loop;
      end Expand;

      --  The top file's rules come first (its first rule is the root).  A
      --  local rule with an included rule's name overrides it; the remaining
      --  included rules append after.
      function Override (Local, Included : Rule_Vectors.Vector)
        return Rule_Vectors.Vector
      is
         Result : Rule_Vectors.Vector := Local;

         function Has (Name : Unbounded_String) return Boolean is
         begin
            for R of Result loop
               if R.Name = Name then
                  return True;
               end if;
            end loop;
            return False;
         end Has;
      begin
         for R of Included loop
            if not Has (R.Name) then
               Result.Append (R);
            end if;
         end loop;
         return Result;
      end Override;

      --  Included code first, then this file's, like C's #include.
      function Join_Code (Inc, Own : Unbounded_String)
        return Unbounded_String is
      begin
         if Inc = Null_Unbounded_String then
            return Own;
         elsif Own = Null_Unbounded_String then
            return Inc;
         else
            return Inc & ASCII.LF & Own;
         end if;
      end Join_Code;

      --  Attach each pending `action name { code }` whose rule is now known.
      procedure Apply_Actions (Result : in out Rule_Vectors.Vector) is
         Left : Attach_Vectors.Vector;
         Hit  : Natural;
      begin
         for A of Pending_Actions loop
            Hit := 0;
            for J in 1 .. Natural (Result.Length) loop
               if Result (J).Name = A.Name then
                  Hit := J;
                  exit;
               end if;
            end loop;
            if Hit = 0 then
               Left.Append (A);
            elsif Result (Hit).Action_Code /= Null_Unbounded_String then
               raise Parse_Error with
                 Integer'Image (A.Line) & ": rule `" & To_String (A.Name)
                 & "` already has an action";
            else
               Result (Hit).Action_Code := A.Code;
            end if;
         end loop;
         Pending_Actions := Left;
      end Apply_Actions;

      Included : Rule_Vectors.Vector;
      Local    : Rule_Vectors.Vector;
      Result   : Rule_Vectors.Vector;
      Out_Text : Unbounded_String;
   begin
      if File_Depth = 0 then
         --  A new top-level schema: nothing carries over from the last one
         --  parsed in this process.
         Schema_Language := To_Unbounded_String ("C");
         Preamble_Code := Null_Unbounded_String;
         Epilogue_Code := Null_Unbounded_String;
         Word_Chars_Code := Null_Unbounded_String;
         Type_Prefix_Code := Null_Unbounded_String;
         Conf_Type_Code := Null_Unbounded_String;
         List_Head_Code := Null_Unbounded_String;
         List_Entry_Code := Null_Unbounded_String;
         List_Init_Code := Null_Unbounded_String;
         List_Append_Code := Null_Unbounded_String;
         List_Foreach_Code := Null_Unbounded_String;
         List_First_Code := Null_Unbounded_String;
         List_Next_Code := Null_Unbounded_String;
         List_Relink_Code := Null_Unbounded_String;
         Pending_Actions.Clear;
      end if;
      File_Depth := File_Depth + 1;
      Expand (Read_File (Path), Dir_Of (Path), Included, Out_Text);
      declare
         Inc_Pre : constant Unbounded_String := Preamble_Code;
         Inc_Epi : constant Unbounded_String := Epilogue_Code;
      begin
         Preamble_Code := Null_Unbounded_String;
         Epilogue_Code := Null_Unbounded_String;
         Local := Parse (To_String (Out_Text));
         Preamble_Code := Join_Code (Inc_Pre, Preamble_Code);
         Epilogue_Code := Join_Code (Inc_Epi, Epilogue_Code);
      end;
      Result := Override (Local, Included);
      Apply_Actions (Result);
      File_Depth := File_Depth - 1;
      if File_Depth = 0 and then not Pending_Actions.Is_Empty then
         raise Parse_Error with
           Integer'Image (Pending_Actions.First_Element.Line)
           & ": action for `" & To_String (Pending_Actions.First_Element.Name)
           & "`, which no rule defines";
      end if;
      return Result;
   exception
      when others =>
         File_Depth := 0;
         raise;
   end Parse_File;

   function Reachable (Rules : Rule_Vectors.Vector) return Rule_Vectors.Vector
   is
      N    : constant Natural := Natural (Rules.Length);
      Seen : array (1 .. N) of Boolean := [others => False];

      procedure Mark (Name : Unbounded_String);

      procedure Walk (V : Element_Vectors.Vector) is
      begin
         for E of V loop
            case E.Kind is
               when Name =>
                  Mark (E.Name);
               when Group =>
                  Walk (E.Items);
               when others =>
                  null;
            end case;
         end loop;
      end Walk;

      procedure Mark (Name : Unbounded_String) is
      begin
         for I in 1 .. N loop
            if Rules (I).Name = Name then
               if not Seen (I) then
                  Seen (I) := True;
                  Walk (Rules (I).Pattern);
               end if;
               return;
            end if;
         end loop;
      end Mark;

      Result : Rule_Vectors.Vector;
   begin
      if N = 0 then
         return Rules;
      end if;
      Mark (Rules (1).Name);
      for I in 1 .. N loop
         if Seen (I) or else Rules (I).Jet_Code /= Null_Unbounded_String then
            Result.Append (Rules (I));
         end if;
      end loop;
      return Result;
   end Reachable;

   function Language return String is (To_String (Schema_Language));

   function Preamble return String is (To_String (Preamble_Code));

   function Epilogue return String is (To_String (Epilogue_Code));

   function Word_Chars return String is (To_String (Word_Chars_Code));

   function List_Override (Op : String) return String is
   begin
      if Op = "head" then
         return To_String (List_Head_Code);
      elsif Op = "entry" then
         return To_String (List_Entry_Code);
      elsif Op = "init" then
         return To_String (List_Init_Code);
      elsif Op = "append" then
         return To_String (List_Append_Code);
      elsif Op = "foreach" then
         return To_String (List_Foreach_Code);
      elsif Op = "first" then
         return To_String (List_First_Code);
      elsif Op = "next" then
         return To_String (List_Next_Code);
      elsif Op = "relink" then
         return To_String (List_Relink_Code);
      end if;
      return "";
   end List_Override;

   function Type_Prefix return String is (To_String (Type_Prefix_Code));

   function Conf_Type return String is (To_String (Conf_Type_Code));

   procedure Set_Type_Prefix (Prefix : String) is
   begin
      if not Valid_Prefix (Prefix) then
         raise Parse_Error with "--prefix: not a C identifier prefix: " & Prefix;
      end if;
      Type_Prefix_Code := To_Unbounded_String (Prefix);
   end Set_Type_Prefix;

end HBNF_Grammar;
