pragma Ada_2022;

with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Hash;
with Ada.Text_IO;
with GNAT.OS_Lib;

package body HBNF_Grammar is

   --  Schema-level metadata gathered by Parse.  A directive is one of two
   --  kinds (RFCPLAN.md decision 5):
   --  - per file: `language`, the language of the file's own code blocks;
   --  - whole parser: the rest.  Any file may set one; two settings that
   --    differ are refused (Set_Directive), `keywords` lists merge, and
   --    code blocks are joined in include order.
   --  Schema_Language is the language of the file read last, which is the
   --  top-level one (its includes are read before it).
   Schema_Language : Unbounded_String := To_Unbounded_String ("C");

   --  The `{ ... }` code blocks before the rules (preamble) and after them
   --  (epilogue), each with the language of the file it came from, in
   --  include order.
   type Code_Piece is record
      Lang : Unbounded_String;
      Code : Unbounded_String;
   end record;
   package Piece_Vectors is new Ada.Containers.Vectors (Positive, Code_Piece);
   Preamble_Pieces : Piece_Vectors.Vector;
   Epilogue_Pieces : Piece_Vectors.Vector;

   Word_Chars_Code : Unbounded_String := Null_Unbounded_String;
   Type_Prefix_Code : Unbounded_String := Null_Unbounded_String;
   Conf_Type_Code  : Unbounded_String := Null_Unbounded_String;
   Entry_Code      : Unbounded_String := Null_Unbounded_String;
   List_Head_Code    : Unbounded_String := Null_Unbounded_String;
   List_Entry_Code   : Unbounded_String := Null_Unbounded_String;
   List_Init_Code    : Unbounded_String := Null_Unbounded_String;
   List_Append_Code  : Unbounded_String := Null_Unbounded_String;
   List_Foreach_Code : Unbounded_String := Null_Unbounded_String;
   List_First_Code   : Unbounded_String := Null_Unbounded_String;
   List_Next_Code    : Unbounded_String := Null_Unbounded_String;
   List_Relink_Code  : Unbounded_String := Null_Unbounded_String;

   --  `statements`, `macros <rule>`, `includes <rule>`: how the C parser
   --  reads a config (see the spec).
   Statements_On   : Boolean := False;
   Macros_Name     : Unbounded_String := Null_Unbounded_String;
   Includes_Name   : Unbounded_String := Null_Unbounded_String;

   --  `keywords { ... }`: the reserved words (empty: every letter-led
   --  literal is one).
   Keyword_Words   : Word_Vectors.Vector;

   --  `action name { code }` directives waiting for their rule: a binding
   --  file attaches actions to rules an included grammar defines, so they
   --  are resolved once the includes are merged (Parse_File).
   type Attach is record
      Name : Unbounded_String;
      Code : Unbounded_String;
      File : Unbounded_String;   --  where it is written, for messages
      Line : Positive := 1;
   end record;
   package Attach_Vectors is new Ada.Containers.Vectors (Positive, Attach);
   Pending_Actions : Attach_Vectors.Vector;

   --  Parse_File nesting: 0 outside any call, 1 for the top-level schema.
   File_Depth : Natural := 0;

   --  The whole text of the last schema error.  GNAT keeps only the first
   --  200 characters of an exception's message, and a message that quotes
   --  its line, or lists several problems, runs longer (Error_Message).
   Full_Error : Unbounded_String := Null_Unbounded_String;

   procedure Fail (Msg : String) with No_Return;

   procedure Fail (Msg : String) is
   begin
      Full_Error := To_Unbounded_String (Msg);
      raise Parse_Error with Msg;
   end Fail;

   function Error_Message (E : Ada.Exceptions.Exception_Occurrence)
     return String
   is
      M : constant String := Ada.Exceptions.Exception_Message (E);
   begin
      if Length (Full_Error) >= M'Length
        and then Slice (Full_Error, 1, M'Length) = M
      then
         return To_String (Full_Error);
      end if;
      return M;
   end Error_Message;

   --  The file Parse is reading ("" for Parse (Text)), for messages, and
   --  the line of its first rule (0 before one), which no include may
   --  follow.
   Current_File    : Unbounded_String := Null_Unbounded_String;
   First_Rule_Line : Natural := 0;

   --  The first rule the file Parse read defines with `=` that no file
   --  read before it defines ("" when there is none): its root.
   First_Defined : Unbounded_String := Null_Unbounded_String;

   --  Include once: the files read so far, by resolved path.
   package Path_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (String, Ada.Strings.Hash, "=");
   Seen_Files : Path_Sets.Set;

   --  Each whole-parser directive set so far (`listops init` for one list
   --  operation), with its value and where it was set.
   type Setting is record
      Value : Unbounded_String;
      File  : Unbounded_String;
      Line  : Positive := 1;
   end record;
   package Setting_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (String, Setting);
   Settings : Setting_Maps.Map;

   --  Set a whole-parser directive: Target gets Value unless another file,
   --  or this one, already set Name to something else.
   procedure Set_Directive
     (Target : in out Unbounded_String; Name, Value : String; Line : Positive)
   is
      C : constant Setting_Maps.Cursor := Settings.Find (Name);

      function Where (F : Unbounded_String; L : Positive) return String is
        ((if F = Null_Unbounded_String then "line " else To_String (F) & ":")
         & Integer'Image (L) (2 .. Integer'Image (L)'Last));
   begin
      if Setting_Maps.Has_Element (C) then
         declare
            Was : constant Setting := Setting_Maps.Element (C);
         begin
            if To_String (Was.Value) /= Value then
               raise Parse_Error with
                 Integer'Image (Line) & ": `" & Name & "` is set here to `"
                 & Value & "` and at " & Where (Was.File, Was.Line)
                 & " to `" & To_String (Was.Value) & "`; it describes the "
                 & "one generated parser, so it can have one value";
            end if;
         end;
      else
         Settings.Insert
           (Name, Setting'(Value => To_Unbounded_String (Value),
                           File  => Current_File,
                           Line  => Line));
      end if;
      Target := To_Unbounded_String (Value);
   end Set_Directive;

   --  A rule's place in a rule list, by name (0 where Finish finds more
   --  than one).
   package Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Natural, Ada.Strings.Hash, "=");

   --  Add R to Rules.  A later `=` overrides: a rule already there with
   --  R's name is replaced in its place, so an overridden root is still
   --  the root.
   procedure Define (Rules : in out Rule_Vectors.Vector;
                     Index : in out Index_Maps.Map;
                     R     : Rule)
   is
      C : constant Index_Maps.Cursor := Index.Find (To_String (R.Name));
   begin
      if Index_Maps.Has_Element (C) then
         Rules.Replace_Element (Index_Maps.Element (C), R);
      else
         Rules.Append (R);
         Index.Insert (To_String (R.Name), Natural (Rules.Length));
      end if;
   end Define;

   --  Per file, from its `sensitivity` line, for Parse_Atom: a bare
   --  literal matches any case (File_No_Case); a rule reference finds its
   --  rule whatever the case (File_Fold_Names).
   File_No_Case    : Boolean := False;
   File_Fold_Names : Boolean := False;

   --  The text of the file Parse is reading, and where each of its lines
   --  starts, for a message that quotes a line.
   Current_Source : Unbounded_String := Null_Unbounded_String;
   package Natural_Vectors is new Ada.Containers.Vectors (Positive, Natural);
   Line_Starts : Natural_Vectors.Vector;

   function Source_Line (N : Positive) return String is
      S : constant String := To_String (Current_Source);
      I : Natural;
      J : Natural;
   begin
      if N > Natural (Line_Starts.Length) then
         return "";
      end if;
      I := Line_Starts (N);
      J := I;
      while J <= S'Last and then S (J) not in ASCII.LF | ASCII.CR loop
         J := J + 1;
      end loop;
      return S (I .. J - 1);
   end Source_Line;

   --  Where something was written, for a message that quotes its line
   --  with a caret under it: a <prose-val> (Text is its words) or a `/`
   --  (Alt is the separator it became; Text is "/" or "=/").
   type Site is record
      File : Unbounded_String;
      Line : Positive := 1;
      Col  : Positive := 1;
      Src  : Unbounded_String;
      Text : Unbounded_String;
      Alt  : Element_Access;
   end record;
   package Site_Vectors is new Ada.Containers.Vectors (Positive, Site);
   Prose_Sites : Site_Vectors.Vector;
   Union_Sites : Site_Vectors.Vector;

   function Here (Line, Col : Positive; Text : String;
                  Alt : Element_Access := null) return Site is
     (Site'(File => Current_File, Line => Line, Col => Col,
            Src  => To_Unbounded_String (Source_Line (Line)),
            Text => To_Unbounded_String (Text), Alt => Alt));

   function Img (N : Natural) return String is
     (Integer'Image (N) (2 .. Integer'Image (N)'Last));

   --  "file:line:col: Msg", then the line, and a caret under the column
   --  (a tab in the line stays a tab, so the caret lines up).
   function Pointed (S : Site; Msg : String) return String is
      Src : constant String := To_String (S.Src);
      Pad : Unbounded_String;
   begin
      for I in Src'First .. Src'First + S.Col - 2 loop
         exit when I > Src'Last;
         Append (Pad, (if Src (I) = ASCII.HT then ASCII.HT else ' '));
      end loop;
      return (if S.File = Null_Unbounded_String then ""
              else To_String (S.File) & ":")
        & Img (S.Line) & ":" & Img (S.Col) & ": " & Msg & ASCII.LF
        & "  " & Src & ASCII.LF & "  " & To_String (Pad) & "^";
   end Pointed;

   --  The definition that stands for each rule name so far, in the order
   --  the files are read, with its pattern as written (before left
   --  recursion is rewritten into a loop), which `=/` extends.
   type Standing_Rule is record
      R   : Rule;
      Raw : Element_Vectors.Vector;
   end record;
   package Standing_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Standing_Rule, Ada.Strings.Hash, "=");
   Standing : Standing_Maps.Map;

   --  A new top-level schema: nothing carries over from the last one read
   --  in this process.
   procedure Reset is
   begin
      Schema_Language := To_Unbounded_String ("C");
      Preamble_Pieces.Clear;
      Epilogue_Pieces.Clear;
      Word_Chars_Code := Null_Unbounded_String;
      Type_Prefix_Code := Null_Unbounded_String;
      Conf_Type_Code := Null_Unbounded_String;
      Entry_Code := Null_Unbounded_String;
      List_Head_Code := Null_Unbounded_String;
      List_Entry_Code := Null_Unbounded_String;
      List_Init_Code := Null_Unbounded_String;
      List_Append_Code := Null_Unbounded_String;
      List_Foreach_Code := Null_Unbounded_String;
      List_First_Code := Null_Unbounded_String;
      List_Next_Code := Null_Unbounded_String;
      List_Relink_Code := Null_Unbounded_String;
      Statements_On := False;
      Macros_Name := Null_Unbounded_String;
      Includes_Name := Null_Unbounded_String;
      Keyword_Words.Clear;
      Pending_Actions.Clear;
      Settings.Clear;
      Seen_Files.Clear;
      Current_File := Null_Unbounded_String;
      First_Rule_Line := 0;
      Prose_Sites.Clear;
      Union_Sites.Clear;
      Standing.Clear;
   end Reset;

   --  ====================================================================
   --  Lexer
   --  ====================================================================

   --  T_Pct: `%` and the word after it (`%i`, `%s`, `%scan`, `%action`,
   --  `%x20-7E`); its Text is the word without the `%`.
   --  T_Eq_Slash: `=/`, ABNF's incremental alternatives.  T_Slash: `/`,
   --  ABNF's union.  T_Prose: a <prose-val>; its Text is what is between
   --  the angle brackets.
   type Tok_Kind is (T_Name, T_String, T_Number, T_Eq, T_Eq_Slash, T_Bar,
                     T_Slash, T_LParen, T_RParen, T_LBrack, T_RBrack, T_Star,
                     T_Code, T_Comment, T_Newline, T_Pct, T_Char, T_Dash,
                     T_Prose, T_EOF);

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

      --  First_Col is the token's first column, for a token Emit sees
      --  only once it has been read past (a quoted string); 0 means Col.
      procedure Emit
        (K : Tok_Kind; S : String := ""; First_Col : Natural := 0) is
      begin
         Token_Vectors.Append
           (Toks, Token'(K, Line, (if First_Col = 0 then Col else First_Col),
                         To_Unbounded_String (S)));
      end Emit;

      function Name_Start (C : Character) return Boolean is
         ((C in 'a' .. 'z') or (C in 'A' .. 'Z') or C = '_');

      function Name_Char (C : Character) return Boolean is
         (Name_Start (C) or (C in '0' .. '9') or C = '-');

      --  Open `(` and `[`: inside them a newline is only white space.
      Group_Depth : Natural := 0;

      --  J starts a line.  The start of the next line with content when
      --  that line is indented, skipping indented comment-only lines, so
      --  the rule goes on there (ABNF's c-wsp); 0 when it is not: the next
      --  line is blank, starts in column 1, or there is none.  Skipped
      --  counts the lines passed over.
      function Continuation (J : Natural; Skipped : out Natural)
        return Natural
      is
         K       : Natural := J;
         L_Start : Natural;
      begin
         Skipped := 0;
         loop
            if K > Text'Last or else Text (K) not in ' ' | ASCII.HT then
               return 0;
            end if;
            L_Start := K;
            while K <= Text'Last and then Text (K) in ' ' | ASCII.HT loop
               K := K + 1;
            end loop;
            if K > Text'Last or else Text (K) in ASCII.LF | ASCII.CR then
               return 0;
            elsif Text (K) = ';' then
               while K <= Text'Last and then Text (K) /= ASCII.LF loop
                  K := K + 1;
               end loop;
               K := K + 1;
               Skipped := Skipped + 1;
            else
               return L_Start;
            end if;
         end loop;
      end Continuation;

   begin
      while I <= Text'Last loop
         case Text (I) is
            when ' ' | ASCII.HT =>
               I := I + 1;  Col := Col + 1;
            when ASCII.LF =>
               declare
                  Skipped : Natural;
                  Next_At : constant Natural :=
                    (if Group_Depth > 0 then 0
                     else Continuation (I + 1, Skipped));
               begin
                  if Group_Depth > 0 or else Next_At /= 0 then
                     --  The rule goes on: inside ( ) or [ ], or on an
                     --  indented line.  A comment at the end of this line
                     --  is inside the rule, and is dropped.
                     if not Toks.Is_Empty
                       and then Toks.Last_Element.Kind = T_Comment
                       and then Toks.Last_Element.Line = Line
                     then
                        Toks.Delete_Last;
                     end if;
                     I := I + 1;  Line := Line + 1;  Col := 1;
                     if Next_At /= 0 then
                        I := Next_At;
                        Line := Line + Skipped;
                     end if;
                  else
                     Emit (T_Newline);  I := I + 1;  Line := Line + 1;
                     Col := 1;
                  end if;
               end;
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
                  --  Inside ( ) or [ ] a comment is part of the rule and
                  --  is dropped.
                  if Group_Depth = 0 then
                     Token_Vectors.Append
                       (Toks, Token'(T_Comment, CL, CC,
                                     To_Unbounded_String
                                       (Trim (Text (Start .. I - 1)))));
                  end if;
               end;
            when '"' =>
               declare
                  Buf    : Unbounded_String := Null_Unbounded_String;
                  Closed : Boolean := False;
                  At_Col : constant Natural := Col;
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
                        --  Decode a C escape, as a C string literal has them:
                        --  \a \b \f \n \r \t \v \\ \" \' \?, \ooo (one to
                        --  three octal digits) and \xHH (hex digits, greedy).
                        I := I + 1;
                        Col := Col + 1;
                        if I > Text'Last then
                           raise Parse_Error with
                             Integer'Image (Line) & ":" & Integer'Image (Col) &
                             ": escape at end of string";
                        end if;
                        if Text (I) in '0' .. '7' then
                           --  C's octal escape: one to three digits.
                           declare
                              Val : Natural := 0;
                              N   : Natural := 0;
                           begin
                              while N < 3 and then I <= Text'Last
                                and then Text (I) in '0' .. '7'
                              loop
                                 Val := Val * 8
                                   + (Character'Pos (Text (I))
                                      - Character'Pos ('0'));
                                 N := N + 1;
                                 I := I + 1;
                                 Col := Col + 1;
                              end loop;
                              if Val > 255 then
                                 raise Parse_Error with
                                   Integer'Image (Line) & ":" &
                                   Integer'Image (Col) & ": bad octal escape";
                              end if;
                              Append (Buf, Character'Val (Val));
                           end;
                        elsif Text (I) = 'x' then
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
                                 when '?' => Ch := '?';
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
                  Emit (T_String, To_String (Buf), At_Col);
               end;
            when '%' =>
               declare
                  Start : constant Positive := I + 1;
               begin
                  I := I + 1;
                  while I <= Text'Last
                    and then (Text (I) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
                                        | '.' | '-')
                  loop
                     I := I + 1;
                  end loop;
                  Emit (T_Pct, Text (Start .. I - 1));
                  Col := Col + (I - Start + 1);
               end;
            when '=' =>
               --  `=/` adds alternatives to a rule (RFC 5234 §3.3).
               if I < Text'Last and then Text (I + 1) = '/' then
                  Emit (T_Eq_Slash);  I := I + 2;  Col := Col + 2;
               else
                  Emit (T_Eq);  I := I + 1;  Col := Col + 1;
               end if;
            --  `|` separates alternatives, as in BNF, EBNF and yacc, and
            --  means ordered choice.  `/` is ABNF's union (RFCPLAN.md,
            --  decision 1); the reader takes it where the two mean the same.
            when '|' => Emit (T_Bar);    I := I + 1;  Col := Col + 1;
            when '/' => Emit (T_Slash);  I := I + 1;  Col := Col + 1;
            when '(' | '[' =>
               Emit (if Text (I) = '(' then T_LParen else T_LBrack);
               Group_Depth := Group_Depth + 1;
               I := I + 1;  Col := Col + 1;
            when ')' | ']' =>
               Emit (if Text (I) = ')' then T_RParen else T_RBrack);
               if Group_Depth > 0 then
                  Group_Depth := Group_Depth - 1;
               end if;
               I := I + 1;  Col := Col + 1;
            when '<' =>
               --  A <prose-val> (RFC 5234 §4): a rule described in words,
               --  not written yet.  It ends at the `>` on the same line.
               declare
                  At_Col : constant Positive := Col;
                  Start  : constant Positive := I + 1;
               begin
                  I := I + 1;  Col := Col + 1;
                  while I <= Text'Last and then Text (I) not in '>' | ASCII.LF
                  loop
                     I := I + 1;  Col := Col + 1;
                  end loop;
                  if I > Text'Last or else Text (I) /= '>' then
                     raise Parse_Error with
                       Integer'Image (Line) & ":" & Integer'Image (At_Col)
                       & ": a <prose-val> ends with `>` on the same line";
                  end if;
                  Emit (T_Prose, Text (Start .. I - 1), At_Col);
                  I := I + 1;  Col := Col + 1;
               end;
            when '*' => Emit (T_Star);   I := I + 1;  Col := Col + 1;
            when '-' => Emit (T_Dash);   I := I + 1;  Col := Col + 1;
            when ''' =>
               --  A character literal 'c' (or a C escape): one code point.
               declare
                  At_Col : constant Natural := Col;
                  Buf    : Unbounded_String := Null_Unbounded_String;
               begin
                  I := I + 1;  Col := Col + 1;
                  if I > Text'Last then
                     raise Parse_Error with
                       Integer'Image (Line) & ":" & Integer'Image (Col) &
                       ": unterminated character literal";
                  end if;
                  if Text (I) = ''' then
                     raise Parse_Error with
                       Integer'Image (Line) & ":" & Integer'Image (Col) &
                       ": empty character literal";
                  end if;
                  if Text (I) = '\' then
                     I := I + 1;  Col := Col + 1;
                     if I > Text'Last then
                        raise Parse_Error with
                          Integer'Image (Line) & ":" & Integer'Image (Col) &
                          ": escape at end of character literal";
                     end if;
                     if Text (I) in '0' .. '7' then
                        declare
                           Val : Natural := 0;
                           N   : Natural := 0;
                        begin
                           while N < 3 and then I <= Text'Last
                             and then Text (I) in '0' .. '7' loop
                              Val := Val * 8
                                + (Character'Pos (Text (I))
                                   - Character'Pos ('0'));
                              N := N + 1;  I := I + 1;  Col := Col + 1;
                           end loop;
                           if Val > 255 then
                              raise Parse_Error with
                                Integer'Image (Line) & ":" &
                                Integer'Image (Col) & ": bad octal escape";
                           end if;
                           Append (Buf, Character'Val (Val));
                        end;
                     elsif Text (I) = 'x' then
                        declare
                           Val : Natural := 0;
                           N   : Natural := 0;
                        begin
                           I := I + 1;  Col := Col + 1;
                           while I <= Text'Last
                             and then Hex_Digit (Text (I)) >= 0 loop
                              Val := Val * 16 + Hex_Digit (Text (I));
                              N := N + 1;  I := I + 1;  Col := Col + 1;
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
                              when '?' => Ch := '?';
                              when others =>
                                 raise Parse_Error with
                                   Integer'Image (Line) & ":" &
                                   Integer'Image (Col) & ": unknown escape '"
                                   & Text (I) & "'";
                           end case;
                           Append (Buf, Ch);
                           I := I + 1;  Col := Col + 1;
                        end;
                     end if;
                  else
                     Append (Buf, Text (I));
                     I := I + 1;  Col := Col + 1;
                  end if;
                  if I > Text'Last or else Text (I) /= ''' then
                     raise Parse_Error with
                       Integer'Image (Line) & ":" & Integer'Image (Col) &
                       ": character literal must be one character";
                  end if;
                  I := I + 1;  Col := Col + 1;   --  closing quote
                  Emit (T_Char, To_String (Buf), At_Col);
               end;
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
   procedure Set_List_Override (Op : String; Code : String; Line : Positive)
   is
      N : constant String := "listops " & Op;
   begin
      if Op = "head" then
         Set_Directive (List_Head_Code, N, Code, Line);
      elsif Op = "entry" then
         Set_Directive (List_Entry_Code, N, Code, Line);
      elsif Op = "init" then
         Set_Directive (List_Init_Code, N, Code, Line);
      elsif Op = "append" then
         Set_Directive (List_Append_Code, N, Code, Line);
      elsif Op = "foreach" then
         Set_Directive (List_Foreach_Code, N, Code, Line);
      elsif Op = "first" then
         Set_Directive (List_First_Code, N, Code, Line);
      elsif Op = "next" then
         Set_Directive (List_Next_Code, N, Code, Line);
      elsif Op = "relink" then
         Set_Directive (List_Relink_Code, N, Code, Line);
      else
         raise Parse_Error with "listops: unknown operation `" & Op & "`";
      end if;
   end Set_List_Override;

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
               --  A bare literal takes its file's `sensitivity string`.
               return new Element'(Kind => Literal, Min => 1, Max => 1,
                                   Lit => Lit, No_Case => File_No_Case);
            end;
         when T_Pct =>
            declare
               T  : constant Token := Cur (P);
               --  ABNF's own strings are case-insensitive, so `%X41` and
               --  `%I"..."` are the same as `%x41` and `%i"..."`.
               W  : constant String :=
                 Ada.Characters.Handling.To_Lower (To_String (T.Text));
            begin
               if W = "i" or else W = "s" then
                  --  RFC 7405's case markers.  hbnf literals are
                  --  case-sensitive, so %s is the default spelled out.
                  Next (P);
                  if Cur (P).Kind /= T_String then
                     raise Parse_Error with
                       Integer'Image (T.Line) & ":" & Integer'Image (T.Col)
                       & ": expected a quoted literal after %" & W;
                  end if;
                  declare
                     Lit : constant Unbounded_String := Cur (P).Text;
                  begin
                     Next (P);
                     return new Element'(Kind => Literal, Min => 1, Max => 1,
                                         Lit => Lit, No_Case => W = "i");
                  end;
               end if;
               if W'Length > 0
                 and then W (W'First) in 'b' | 'd' | 'o' | 'u' | 'x'
               then
                  --  %b.. / %d.. / %o.. / %x.., each with an optional
                  --  -suffix for a range: a single code point or a range, in
                  --  binary/decimal/octal/hex (RFC 5234 §2.3's numeric
                  --  terminals, plus %o as C's octal spelling).  These are
                  --  the character-layer terminals.
                  declare
                     Base : constant Positive :=
                       (if W (W'First) = 'b' then 2
                        elsif W (W'First) = 'o' then 8
                        elsif W (W'First) = 'd' then 10
                        else 16);

                     function Num_Val (S : String) return Natural is
                        V : Natural := 0;
                        D : Integer;
                     begin
                        for C of S loop
                           D := Hex_Digit (C);
                           if D < 0 or else D >= Base then
                              raise Parse_Error with
                                Integer'Image (T.Line) & ":" &
                                Integer'Image (T.Col) & ": bad digit in %"
                                & W;
                           end if;
                           V := V * Base + D;
                        end loop;
                        return V;
                     end Num_Val;

                     Dash : Natural := 0;
                     Lo   : Natural;
                     Hi   : Natural;
                  begin
                     if W'Length = 1 then
                        raise Parse_Error with
                          Integer'Image (T.Line) & ":" & Integer'Image (T.Col)
                          & ": %" & W & " needs digits";
                     end if;
                     if (for some C of W => C = '.') then
                        --  `%d13.10`: the code points in sequence (RFC 5234
                        --  §2.3), returned as a group that Parse_Pattern
                        --  splices into the sequence around it.
                        if (for some C of W => C = '-') then
                           raise Parse_Error with
                             Integer'Image (T.Line) & ":"
                             & Integer'Image (T.Col) & ": %" & W
                             & ": a numeric value is a range or a sequence, "
                             & "not both";
                        end if;
                        declare
                           Items : Element_Vectors.Vector;
                           St    : Positive := W'First + 1;
                        begin
                           for I in W'First + 1 .. W'Last + 1 loop
                              if I > W'Last or else W (I) = '.' then
                                 if I = St then
                                    raise Parse_Error with
                                      Integer'Image (T.Line) & ":"
                                      & Integer'Image (T.Col) & ": %" & W
                                      & ": empty value between dots";
                                 end if;
                                 declare
                                    V : constant Natural :=
                                      Num_Val (W (St .. I - 1));
                                 begin
                                    Items.Append
                                      (new Element'(Kind => Char_Range,
                                                    Min => 1, Max => 1,
                                                    Lo => V, Hi => V));
                                 end;
                                 St := I + 1;
                              end if;
                           end loop;
                           Next (P);
                           return new Element'(Kind => Group, Min => 1,
                                               Max => 1, Items => Items);
                        end;
                     end if;
                     for I in W'First + 1 .. W'Last loop
                        if W (I) = '-' then
                           Dash := I;
                           exit;
                        end if;
                     end loop;
                     if Dash = 0 then
                        Lo := Num_Val (W (W'First + 1 .. W'Last));
                        Hi := Lo;
                     else
                        Lo := Num_Val (W (W'First + 1 .. Dash - 1));
                        Hi := Num_Val (W (Dash + 1 .. W'Last));
                     end if;
                     if Lo > Hi then
                        --  The endpoint order does not matter: %x39-30 is the
                        --  range [30, 39], the same as %x30-39.
                        declare
                           T : constant Natural := Lo;
                        begin
                           Lo := Hi;
                           Hi := T;
                        end;
                     end if;
                     if W (W'First) = 'u' and then Hi > 16#10FFFF# then
                        raise Parse_Error with
                          Integer'Image (T.Line) & ":" & Integer'Image (T.Col)
                          & ": code point out of Unicode range in %" & W;
                     end if;
                     Next (P);
                     return new Element'
                       (Kind => Char_Range, Min => 1, Max => 1,
                        Lo => Lo, Hi => Hi);
                  end;
               end if;

               raise Parse_Error with
                 Integer'Image (T.Line) & ":" & Integer'Image (T.Col)
                 & ": %" & W & ": expected %i or %s before a literal, or a "
                 & "%b/%d/%o/%u/%x numeric terminal";
            end;
         when T_Char =>
            --  A character literal 'c': a single code point, or with a
            --  following '-' a code-point range ('a'-'c').
            declare
               S   : constant String := To_String (Cur (P).Text);
               Cp1 : constant Natural := Character'Pos (S (S'First));
            begin
               Next (P);
               if Cur (P).Kind = T_Dash then
                  Next (P);
                  if Cur (P).Kind /= T_Char then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" &
                       Integer'Image (Cur (P).Col) &
                       ": expected a character literal after '-'";
                  end if;
                  declare
                     S2  : constant String := To_String (Cur (P).Text);
                     Cp2 : constant Natural := Character'Pos (S2 (S2'First));
                  begin
                     Next (P);
                     return new Element'
                       (Kind => Char_Range, Min => 1, Max => 1,
                        Lo => Natural'Min (Cp1, Cp2),
                        Hi => Natural'Max (Cp1, Cp2));
                  end;
               end if;
               return new Element'
                 (Kind => Char_Range, Min => 1, Max => 1,
                  Lo => Cp1, Hi => Cp1);
            end;
         when T_Name =>
            declare
               N : constant Unbounded_String := Expect_Name (P);
            begin
               return new Element'
                 (Kind => Name, Min => 1, Max => 1, Name => N,
                  Fold => File_Fold_Names);
            end;
         when T_Prose =>
            --  A <prose-val>: a rule nobody has written yet.  It stands
            --  as a reference to "<n>", a name no rule can have; Finish
            --  reports it, with its line, if the parser would use it.
            declare
               T : constant Token := Cur (P);
            begin
               Prose_Sites.Append (Here (T.Line, T.Col, To_String (T.Text)));
               Next (P);
               return new Element'
                 (Kind => Name, Min => 1, Max => 1,
                  Name => To_Unbounded_String
                            ("<" & Img (Natural (Prose_Sites.Length)) & ">"),
                  Fold => False);
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
         --  `*m`: at most m (`*2DIGIT`).
         if Cur (P).Kind = T_Number then
            Max := Integer'Value (To_String (Cur (P).Text));  Next (P);
         end if;
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
           T_Newline | T_RParen | T_RBrack | T_Bar | T_Slash | T_Comment
           | T_Code | T_EOF;
         exit when Cur (P).Kind = T_Pct
           and then To_String (Cur (P).Text) in "scan" | "action";
         if Cur (P).Kind = T_Pct
           and then (for some C of To_String (Cur (P).Text) => C = '.')
         then
            --  `%d13.10` is two elements of this sequence.
            Append_All (V, Parse_Atom (P).Items);
         else
            Element_Vectors.Append (V, Parse_Element (P));
         end if;
      end loop;
      return V;
   end Parse_Pattern;

   --  An alternation: concatenation *( "|" concatenation ), flattened
   --  with Alt separator elements, used for a group/bracket's inside and a
   --  rule's whole RHS; the caller checks the terminating token.
   function Parse_Alternation (P : in out Parser)
     return Element_Vectors.Vector is
      V : Element_Vectors.Vector;
   begin
      Append_All (V, Parse_Pattern (P));
      loop
         --  A newline before `|` is a continuation, not the end of the rule:
         --  allow a multi-line alternation (`x = a` newline `/ b`).  Peek
         --  past the newline run and commit only if the next token is `|`.
         declare
            Pos : Positive := P.Pos;
         begin
            while P.Toks (Pos).Kind in T_Newline | T_Comment loop
               Pos := Pos + 1;
            end loop;
            exit when P.Toks (Pos).Kind not in T_Bar | T_Slash;
            P.Pos := Pos;
         end;
         declare
            T : constant Token := Cur (P);
            A : constant Element_Access :=
              new Element'(Kind => Alt, Min => 1, Max => 1,
                           Union => T.Kind = T_Slash);
         begin
            if A.Union then
               Union_Sites.Append (Here (T.Line, T.Col, "/", A));
            end if;
            Next (P);
            Element_Vectors.Append (V, A);
         end;
         Append_All (V, Parse_Pattern (P));
      end loop;
      return V;
   end Parse_Alternation;

   function Same_Element (A, B : Element_Access) return Boolean;

   function Same_Elements (A, B : Element_Vectors.Vector) return Boolean is
     (Natural (A.Length) = Natural (B.Length)
      and then (for all I in 1 .. Natural (A.Length) =>
                  Same_Element (A (I), B (I))));

   function Same_Element (A, B : Element_Access) return Boolean is
     (A.Kind = B.Kind and then A.Min = B.Min and then A.Max = B.Max
      and then (case A.Kind is
                  when Literal => A.Lit = B.Lit and then A.No_Case = B.No_Case,
                  when Name    => A.Name = B.Name,
                  when Group   => Same_Elements (A.Items, B.Items),
                  when Char_Range   => A.Lo = B.Lo and then A.Hi = B.Hi,
                  when Alt     => True));

   --  Direct left recursion, `a = a t1 | a t2 | b1 | b2`, becomes the list
   --  `1*( b1 | b2 | t1 | t2 )` with Bases = 2: the first entry is read
   --  from the bases, each later one from the tails.  That is b (t)*, what
   --  the recursion derives, read in a loop instead of by recursion, and
   --  each entry is one step of the recursion, so an operator rule
   --  (`sum = sum "-" n | n`) leaves its entries in left-to-right order
   --  for the caller to fold.  Ordered choice holds among the bases and
   --  among the tails.
   --
   --  Two shapes come out as a plain list, Bases = 0: an empty base
   --  (`config = config entry |`, parse.y's `grammar : /* empty */ |
   --  grammar entry`) gives `*( entry )`, and bases the same as the tails
   --  (`string = string word | word`) give `1*( word )`.
   --
   --  Pattern is left as it is when no branch begins with the rule itself.
   --  Left recursion through another rule, or behind something that can
   --  match nothing, is not rewritten; HBNF_Compilable refuses it.
   procedure Rewrite_Left_Recursion
     (Name    : Unbounded_String;
      Line    : Positive;
      Pattern : in out Element_Vectors.Vector;
      Bases   : out Natural)
   is
      Len        : constant Natural := Natural (Pattern.Length);
      Base_V     : Element_Vectors.Vector;
      Tail_V     : Element_Vectors.Vector;
      N_Base     : Natural := 0;
      N_Tail     : Natural := 0;
      Empty_Base : Boolean := False;
      St         : Positive := 1;

      function Here return String is
        (Integer'Image (Line) & ": " & To_String (Name) & ": ");

      procedure Add (V : in out Element_Vectors.Vector; N : in out Natural;
                     First, Last : Natural) is
      begin
         if N > 0 then
            V.Append (new Element'(Kind => Alt, Min => 1, Max => 1,
                                   Union => False));
         end if;
         for I in First .. Last loop
            V.Append (Pattern (I));
         end loop;
         N := N + 1;
      end Add;
   begin
      Bases := 0;
      for K in 1 .. Len + 1 loop
         if K > Len or else Pattern (K).Kind = Alt then
            if St > K - 1 then
               Empty_Base := True;
            elsif Pattern (St).Kind = HBNF_Grammar.Name
              and then (Pattern (St).Name = Name
                        or else (Pattern (St).Fold
                                 and then Ada.Characters.Handling.To_Lower
                                            (To_String (Pattern (St).Name))
                                          = Ada.Characters.Handling.To_Lower
                                              (To_String (Name))))
              and then Pattern (St).Min = 1 and then Pattern (St).Max = 1
            then
               if St = K - 1 then
                  raise Parse_Error with
                    Here & "the alternative `" & To_String (Name)
                    & "` is the rule itself, and adds nothing";
               end if;
               Add (Tail_V, N_Tail, St + 1, K - 1);
            else
               Add (Base_V, N_Base, St, K - 1);
            end if;
            St := K + 1;
         end if;
      end loop;
      if N_Tail = 0 then
         return;
      end if;
      if N_Base = 0 and then not Empty_Base then
         raise Parse_Error with
           Here & "every alternative begins with `" & To_String (Name)
           & "`, so it can never start; add one that does not (`"
           & To_String (Name) & " = " & To_String (Name) & " x | x`)";
      end if;
      if Empty_Base and then N_Base > 0 then
         raise Parse_Error with
           Here & "an empty alternative beside the other bases; drop it "
           & "and write `[ " & To_String (Name) & " ]` where the rule is "
           & "used";
      end if;
      declare
         Items : Element_Vectors.Vector;
      begin
         if Empty_Base or else Same_Elements (Base_V, Tail_V) then
            Items := Tail_V;
         else
            Items := Base_V;
            Items.Append (new Element'(Kind => Alt, Min => 1, Max => 1,
                                       Union => False));
            for E of Tail_V loop
               Items.Append (E);
            end loop;
            Bases := N_Base;
         end if;
         Pattern.Clear;
         Pattern.Append
           (new Element'(Kind => Group, Min => (if Empty_Base then 0 else 1),
                         Max => -1, Items => Items));
      end;
   end Rewrite_Left_Recursion;

   function Left_Part (R : Rule; Tails : Boolean)
     return Element_Vectors.Vector is
      V  : Element_Vectors.Vector;
      Br : Positive := 1;
   begin
      for E of R.Pattern (1).Items loop
         if E.Kind = Alt then
            Br := Br + 1;
         end if;
         --  The Alt between the last base and the first tail is in neither.
         if not (E.Kind = Alt and then Br = R.Left_Bases + 1)
           and then (Br > R.Left_Bases) = Tails
         then
            V.Append (E);
         end if;
      end loop;
      return V;
   end Left_Part;

   function Base_Branches (R : Rule) return Element_Vectors.Vector is
     (Left_Part (R, Tails => False));

   function Tail_Branches (R : Rule) return Element_Vectors.Vector is
     (Left_Part (R, Tails => True));

   function Has_No_Case (Rules : Rule_Vectors.Vector) return Boolean is
      function In_Seq (V : Element_Vectors.Vector) return Boolean is
        (for some E of V =>
           (E.Kind = Literal and then E.No_Case)
           or else (E.Kind = Group and then In_Seq (E.Items)));
   begin
      return (for some R of Rules => In_Seq (R.Pattern));
   end Has_No_Case;

   --  The words of a `keywords { ... }` block, added to Keyword_Words.  A
   --  keyword is what the lexer can intern: letter- or underscore-led, then
   --  letters, digits, `_`, `-` and `.`.
   --  Own: the words this file has listed, for the listed-twice check;
   --  lists from several files merge.
   procedure Add_Keywords (Block : String; Line : Positive;
                           Own : in out Word_Vectors.Vector)
   is
      I : Natural := Block'First;

      procedure Add (W : String) is
         function Word_Char (C : Character) return Boolean is
           (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '.');
      begin
         if not (W (W'First) in 'a' .. 'z' | 'A' .. 'Z' | '_')
           or else (for some C of W => not Word_Char (C))
         then
            raise Parse_Error with
              Integer'Image (Line) & ": keywords: `" & W
              & "` is not a word (a letter or `_`, then letters, digits, "
              & "`_`, `-`, `.`)";
         end if;
         if Own.Contains (To_Unbounded_String (W)) then
            raise Parse_Error with
              Integer'Image (Line) & ": keywords: `" & W & "` listed twice";
         end if;
         Own.Append (To_Unbounded_String (W));
         if not Keyword_Words.Contains (To_Unbounded_String (W)) then
            Keyword_Words.Append (To_Unbounded_String (W));
         end if;
      end Add;
   begin
      while I <= Block'Last loop
         if Block (I) = ';' then
            while I <= Block'Last and then Block (I) /= ASCII.LF loop
               I := I + 1;
            end loop;
         elsif Block (I) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            I := I + 1;
         else
            declare
               J : Natural := I;
            begin
               while J <= Block'Last
                 and then Block (J) not in ' ' | ASCII.HT | ASCII.LF
                                         | ASCII.CR | ';'
               loop
                  J := J + 1;
               end loop;
               Add (Block (I .. J - 1));
               I := J;
            end;
         end if;
      end loop;
   end Add_Keywords;

   --  True when the token K after the current one ends a line: a header
   --  word followed by `=` (or a name and `=`) starts a rule, not a
   --  directive, so a grammar can still name a rule `macros`.
   function Ends_Directive (P : Parser; K : Positive) return Boolean is
     (P.Pos + K > Natural (P.Toks.Length)
      or else P.Toks (P.Pos + K).Kind in T_Newline | T_Comment | T_EOF);

   --  Once every file is read (Parse_File, or Parse on its own):
   --  - a reference from a file with `sensitivity rule-name %i` takes the
   --    spelling of the one rule it names when case is ignored;
   --  - a `/` is accepted where union and ordered choice mean the same:
   --    between alternatives that each match exactly one code point;
   --  - a <prose-val> the parser would use stops generation.
   --  The last two look only at the rules the parser uses (Reachable), so
   --  a grammar can include an RFC's rules and replace the ones it needs.
   procedure Finish (Rules : Rule_Vectors.Vector) is
      use Ada.Characters.Handling;

      By_Name : Index_Maps.Map;   --  exact name -> place
      Folded  : Index_Maps.Map;   --  lower-case name -> place (0: several)

      procedure Resolve (V : Element_Vectors.Vector; In_Rule : String) is
      begin
         for E of V loop
            if E.Kind = Name and then E.Fold then
               declare
                  C : constant Index_Maps.Cursor :=
                    Folded.Find (To_Lower (To_String (E.Name)));
               begin
                  if Index_Maps.Has_Element (C) then
                     if Index_Maps.Element (C) = 0 then
                        raise Parse_Error with
                          "rule `" & In_Rule & "`: `" & To_String (E.Name)
                          & "` names more than one rule when case is "
                          & "ignored (`sensitivity rule-name %i`)";
                     end if;
                     E.Name := Rules (Index_Maps.Element (C)).Name;
                  end if;
               end;
            elsif E.Kind = Group then
               Resolve (E.Items, In_Rule);
            end if;
         end loop;
      end Resolve;

      --  True when E matches exactly one code point: a range, or a rule
      --  whose every alternative is one element that does.
      function One_Point (E : Element_Access; Depth : Natural)
        return Boolean
      is
      begin
         if E.Min /= 1 or else E.Max /= 1 or else Depth = 0 then
            return False;
         elsif E.Kind = Char_Range then
            return True;
         elsif E.Kind /= Name
           or else not By_Name.Contains (To_String (E.Name))
         then
            return False;
         end if;
         declare
            R : constant Rule := Rules (By_Name (To_String (E.Name)));
            N : Natural := 0;   --  elements in the current alternative
         begin
            if R.Jet_Code /= Null_Unbounded_String or else R.Pattern.Is_Empty
            then
               return False;
            end if;
            for X of R.Pattern loop
               if X.Kind = Alt then
                  if N /= 1 then
                     return False;
                  end if;
                  N := 0;
               else
                  N := N + 1;
                  if N > 1 or else not One_Point (X, Depth - 1) then
                     return False;
                  end if;
               end if;
            end loop;
            return N = 1;
         end;
      end One_Point;

      Problems : Unbounded_String;

      procedure Report (Msg : String) is
      begin
         if Problems /= Null_Unbounded_String then
            Append (Problems, ASCII.LF);
         end if;
         Append (Problems, Msg);
      end Report;

      procedure Report (S : Site; Msg : String) is
      begin
         Report (Pointed (S, Msg));
      end Report;

      procedure Check_Unions (V : Element_Vectors.Vector) is
         Union : Element_Access := null;
         N     : Natural := 0;
         Fits  : Boolean := True;
      begin
         for E of V loop
            if E.Kind = Alt then
               if E.Union and then Union = null then
                  Union := E;
               end if;
               Fits := Fits and then N = 1;
               N := 0;
            else
               N := N + 1;
               Fits := Fits and then One_Point (E, 32);
               if E.Kind = Group then
                  Check_Unions (E.Items);
               end if;
            end if;
         end loop;
         Fits := Fits and then N = 1;
         if Union /= null and then not Fits then
            for S of Union_Sites loop
               if S.Alt = Union then
                  Report
                    (S, "`" & To_String (S.Text) & "` is ABNF's union, "
                     & "which hbnf takes only between alternatives that "
                     & "each match one code point (a %x value, a 'c' "
                     & "literal, or a rule of them) so far (RFCPLAN.md step "
                     & "5); write `|`, ordered choice, longest first");
                  exit;
               end if;
            end loop;
         end if;
      end Check_Unions;

      procedure Check_Prose (V : Element_Vectors.Vector; In_Rule : String) is
      begin
         for E of V loop
            if E.Kind = Name and then Length (E.Name) > 0
              and then Slice (E.Name, 1, 1) = "<"
            then
               declare
                  S : constant String := To_String (E.Name);
                  N : constant Positive :=
                    Positive'Value (S (S'First + 1 .. S'Last - 1));
               begin
                  Report
                    (Prose_Sites (N),
                     "not written yet, in `" & In_Rule & "`: <"
                     & To_String (Prose_Sites (N).Text) & ">");
               end;
            elsif E.Kind = Group then
               Check_Prose (E.Items, In_Rule);
            end if;
         end loop;
      end Check_Prose;
   begin
      for J in 1 .. Natural (Rules.Length) loop
         declare
            K : constant String := To_Lower (To_String (Rules (J).Name));
         begin
            By_Name.Include (To_String (Rules (J).Name), J);
            if Folded.Contains (K) then
               Folded.Replace (K, 0);
            else
               Folded.Insert (K, J);
            end if;
         end;
      end loop;
      for R of Rules loop
         Resolve (R.Pattern, To_String (R.Name));
      end loop;
      declare
         Used  : constant Rule_Vectors.Vector := Reachable (Rules);
         Lower : Index_Maps.Map;
      begin
         for J in 1 .. Natural (Used.Length) loop
            Check_Unions (Used (J).Pattern);
            Check_Prose (Used (J).Pattern, To_String (Used (J).Name));
            --  ABNF's rule names ignore case, and so do the identifiers
            --  the backends make of them (TOK_DIGIT, Digit): two rules
            --  whose names differ only in case would be one name there.
            declare
               K : constant String := To_Lower (To_String (Used (J).Name));
            begin
               if Lower.Contains (K) then
                  Report ("rules `" & To_String (Used (Lower (K)).Name)
                          & "` and `" & To_String (Used (J).Name)
                          & "` differ only in case; ABNF reads them as one "
                          & "name, and so would the generated code");
               else
                  Lower.Insert (K, J);
               end if;
            end;
         end loop;
      end;
      if Problems /= Null_Unbounded_String then
         Fail (To_String (Problems));
      end if;
   end Finish;

   --  `name =/ alternatives` (RFC 5234 §3.3): add alternatives to the
   --  definition that stands, which may be in another file, joined with
   --  `/`, ABNF's union.  P is at the name.  The rule keeps its comments
   --  and action, and left recursion is read again over the whole.  In a
   --  file with `sensitivity rule-name %i` the name is found whatever its
   --  case.
   procedure Extend (P     : in out Parser;
                     Rules : in out Rule_Vectors.Vector;
                     Index : in out Index_Maps.Map;
                     Name  : Unbounded_String;
                     Line  : Positive)
   is
      use Ada.Characters.Handling;
      Op  : constant Token := P.Toks (P.Pos + 1);
      Where_Op : constant String :=
        Integer'Image (Op.Line) & ":" & Integer'Image (Op.Col) & ": ";
      Key : Unbounded_String := Name;
   begin
      if File_Fold_Names and then not Standing.Contains (To_String (Name))
      then
         declare
            Hits : Natural := 0;
         begin
            for C in Standing.Iterate loop
               if To_Lower (Standing_Maps.Key (C))
                  = To_Lower (To_String (Name))
               then
                  Hits := Hits + 1;
                  Key := To_Unbounded_String (Standing_Maps.Key (C));
               end if;
            end loop;
            if Hits > 1 then
               raise Parse_Error with
                 Where_Op & "`" & To_String (Name) & "` names more than one "
                 & "rule when case is ignored";
            end if;
         end;
      end if;
      if not Standing.Contains (To_String (Key)) then
         raise Parse_Error with
           Where_Op & "`=/` adds alternatives to `" & To_String (Name)
           & "`, which no `=` before it defines";
      end if;
      Next (P);
      Next (P);   --  the `=/`
      declare
         Old     : constant Standing_Rule := Standing (To_String (Key));
         Sep     : constant Element_Access :=
           new Element'(Kind => Alt, Min => 1, Max => 1, Union => True);
         Raw     : Element_Vectors.Vector := Old.Raw;
         Pattern : Element_Vectors.Vector;
         Bases   : Natural;
         R       : Rule := Old.R;
      begin
         if Old.R.Jet_Code /= Null_Unbounded_String then
            raise Parse_Error with
              Where_Op & "`" & To_String (Key) & "` is a jet; `=/` cannot add "
              & "alternatives to it";
         end if;
         if Cur (P).Kind = T_Code
           or else (Cur (P).Kind = T_Pct
                    and then To_String (Cur (P).Text) in "scan" | "action")
         then
            raise Parse_Error with
              Where_Op & "`=/` takes alternatives; a jet or an action goes "
              & "with the `=` definition";
         end if;
         Union_Sites.Append (Here (Op.Line, Op.Col, "=/", Sep));
         Raw.Append (Sep);
         Append_All (Raw, Parse_Alternation (P));
         if Cur (P).Kind in T_Code | T_Pct then
            --  Parse_Alternation stops at a %action or a code block.
            raise Parse_Error with
              Integer'Image (Cur (P).Line) & ":" & Integer'Image (Cur (P).Col)
              & ": an action goes with the `=` definition, or in "
              & "`action " & To_String (Key) & " { }`";
         end if;
         if Cur (P).Kind = T_Comment then
            Next (P);
         end if;
         Pattern := Raw;
         Rewrite_Left_Recursion (R.Name, Line, Pattern, Bases);
         R.Pattern := Pattern;
         R.Left_Bases := Bases;
         Define (Rules, Index, R);
         Standing.Include
           (To_String (Key), Standing_Rule'(R => R, Raw => Raw));
      end;
   end Extend;

   function Parse (Text : String) return Rule_Vectors.Vector is
      P     : Parser := (Toks => Lex (Text), Pos => 1);
      Rules : Rule_Vectors.Vector;
      Index : Index_Maps.Map;
      Name  : Unbounded_String;
      Name_Line : Positive := 1;
      --  This file's own: its `language` (C when it has none) and the line
      --  that set it, its header code blocks, and the keywords it lists.
      File_Lang : Unbounded_String := To_Unbounded_String ("C");
      Lang_Line : Natural := 0;
      Head_Code : Word_Vectors.Vector;
      Own_Words : Word_Vectors.Vector;
      --  The lines that set this file's `sensitivity`, per axis (0: none).
      Names_Line   : Natural := 0;
      Strings_Line : Natural := 0;
   begin
      if File_Depth = 0 then
         Reset;
      end if;
      First_Rule_Line := 0;
      First_Defined := Null_Unbounded_String;
      File_No_Case := False;
      File_Fold_Names := False;
      Current_Source := To_Unbounded_String (Text);
      Line_Starts.Clear;
      Line_Starts.Append (Text'First);
      for I in Text'Range loop
         if Text (I) = ASCII.LF then
            Line_Starts.Append (I + 1);
         end if;
      end loop;
      --  Header: an optional `{ ... }` preamble and/or `language X`, each
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
                              or else To_String (Cur (P).Text) = "listops"
                              or else To_String (Cur (P).Text) = "statements"
                              or else To_String (Cur (P).Text) = "macros"
                              or else To_String (Cur (P).Text) = "entry"
                              or else To_String (Cur (P).Text) = "includes"
                              or else To_String (Cur (P).Text) = "sensitivity"
                              or else To_String (Cur (P).Text) = "keywords"))
         then
            P.Pos := Mark;
            loop
               while Cur (P).Kind in T_Newline | T_Comment loop
                  Next (P);
               end loop;
               if Cur (P).Kind = T_Code then
                  Head_Code.Append (Cur (P).Text);
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
                  --  Per file: the language of this file's code blocks.
                  if Lang_Line /= 0 and then Cur (P).Text /= File_Lang then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ": `language` is "
                       & To_String (File_Lang) & " already (line"
                       & Integer'Image (Lang_Line) & "); a file's code "
                       & "blocks are in one language";
                  end if;
                  File_Lang := Cur (P).Text;
                  Lang_Line := Cur (P).Line;
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "sensitivity"
               then
                  --  Per file: `sensitivity [rule-name | string] %i | %s`.
                  --  %i makes rule references (`digit` finds `DIGIT`),
                  --  bare literals (`"HTTP"` matches `http`), or both,
                  --  ignore case; %s, the default, does not.  A literal's
                  --  own %i or %s wins.
                  declare
                     At_Line : constant Positive := Cur (P).Line;
                     Axis    : Unbounded_String := To_Unbounded_String ("");
                  begin
                     Next (P);
                     if Cur (P).Kind = T_Name then
                        Axis := Cur (P).Text;
                        if To_String (Axis) not in "rule-name" | "string" then
                           raise Parse_Error with
                             Integer'Image (Cur (P).Line) & ":"
                             & Integer'Image (Cur (P).Col)
                             & ": `sensitivity` takes `rule-name`, `string` "
                             & "or neither, then %i or %s";
                        end if;
                        Next (P);
                     end if;
                     if Cur (P).Kind /= T_Pct
                       or else Ada.Characters.Handling.To_Lower
                                 (To_String (Cur (P).Text)) not in "i" | "s"
                     then
                        raise Parse_Error with
                          Integer'Image (Cur (P).Line) & ":"
                          & Integer'Image (Cur (P).Col)
                          & ": expected %i or %s after `sensitivity`";
                     end if;
                     declare
                        No_Case : constant Boolean :=
                          Ada.Characters.Handling.To_Lower
                            (To_String (Cur (P).Text)) = "i";

                        procedure Set (V : in out Boolean;
                                       Set_At : in out Natural;
                                       What : String) is
                        begin
                           if Set_At /= 0 and then V /= No_Case then
                              raise Parse_Error with
                                Integer'Image (At_Line) & ": `sensitivity"
                                & What & "` is set otherwise already (line"
                                & Integer'Image (Set_At) & ")";
                           end if;
                           V := No_Case;
                           Set_At := At_Line;
                        end Set;
                     begin
                        if To_String (Axis) /= "string" then
                           Set (File_Fold_Names, Names_Line, " rule-name");
                        end if;
                        if To_String (Axis) /= "rule-name" then
                           Set (File_No_Case, Strings_Line, " string");
                        end if;
                     end;
                     Next (P);
                  end;
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
                  Set_Directive (Word_Chars_Code, "wordchars",
                                 To_String (Cur (P).Text), Cur (P).Line);
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
                  --  --prefix= wins over it (Set_Type_Prefix).
                  Set_Directive (Type_Prefix_Code, "prefix",
                                 To_String (Cur (P).Text), Cur (P).Line);
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
                     At_Line : constant Positive := Cur (P).Line;
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
                     Set_Directive (Conf_Type_Code, "conf", To_String (Buf),
                                    At_Line);
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
                           Set_List_Override
                             (Op, To_String (Tks (J).Text), Cur (P).Line);
                           J := J + 1;
                        end;
                     end loop;
                  end;
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "keywords"
                 and then P.Pos + 1 <= Natural (P.Toks.Length)
                 and then P.Toks (P.Pos + 1).Kind = T_Code
               then
                  --  `keywords { all any anchor ... }`: the reserved words,
                  --  as parse.y's lookup() table has them, separated by
                  --  blanks; `;` starts a comment to the end of the line.
                  Next (P);
                  Add_Keywords (To_String (Cur (P).Text), Cur (P).Line,
                                Own_Words);
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "statements"
                 and then Ends_Directive (P, 1)
               then
                  --  `statements`: the root list's entries are read one
                  --  statement at a time (C backend).
                  Statements_On := True;
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then (To_String (Cur (P).Text) = "macros"
                           or else To_String (Cur (P).Text) = "includes"
                           or else To_String (Cur (P).Text) = "entry")
                 and then Ends_Directive (P, 2)
               then
                  --  `macros varset` / `includes include`: the rule whose
                  --  statements define a macro / include a file.
                  declare
                     D : constant String := To_String (Cur (P).Text);
                  begin
                     Next (P);
                     if Cur (P).Kind /= T_Name then
                        raise Parse_Error with
                          Integer'Image (Cur (P).Line) & ":" &
                          Integer'Image (Cur (P).Col) &
                          ": expected "
                          & (if D = "entry" then "a C function name"
                             else "a rule name")
                          & " after `" & D & "`";
                     end if;
                     if D = "macros" then
                        Set_Directive (Macros_Name, D,
                                       To_String (Cur (P).Text), Cur (P).Line);
                     elsif D = "entry" then
                        Set_Directive (Entry_Code, D,
                                       To_String (Cur (P).Text), Cur (P).Line);
                     else
                        Set_Directive (Includes_Name, D,
                                       To_String (Cur (P).Text), Cur (P).Line);
                     end if;
                     Next (P);
                  end;
               else
                  exit;
               end if;
            end loop;
         else
            P.Pos := Mark;
         end if;
      end;
      Schema_Language := File_Lang;
      for C of Head_Code loop
         Preamble_Pieces.Append (Code_Piece'(Lang => File_Lang, Code => C));
      end loop;

      loop
         while Cur (P).Kind = T_Newline loop
            Next (P);
         end loop;
         exit when Cur (P).Kind = T_EOF;

         declare
            Leading  : Unbounded_String := Null_Unbounded_String;
            Trailing : Unbounded_String := Null_Unbounded_String;
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
               Epilogue_Pieces.Append
                 (Code_Piece'(Lang => File_Lang, Code => Cur (P).Text));
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
                          File => Current_File,
                          Line => Cur (P).Line));
               Next (P);
               Next (P);
               Next (P);
               if Cur (P).Kind = T_Comment then
                  Next (P);
               end if;
               goto Next_Item;
            end if;

            --  `name =`: a rule's head is its name alone, as in RFC 5234.
            --  Anything else before the `=` is a mistake worth naming: a
            --  C type (hbnf once read `char[IFNAMSIZ] ifname =`; a
            --  binding's %action now converts the value into the daemon's
            --  type), or a line of elements that is not a rule (a rule
            --  goes on to an indented line, or one that starts with `|`).
            if Cur (P).Kind /= T_Name
              or else P.Toks (P.Pos + 1).Kind not in T_Eq | T_Eq_Slash
            then
               declare
                  K      : Positive := P.Pos;
                  Has_Eq : Boolean := False;
               begin
                  while P.Toks (K).Kind not in T_Newline | T_EOF loop
                     if P.Toks (K).Kind in T_Eq | T_Eq_Slash then
                        Has_Eq := True;
                        exit;
                     end if;
                     K := K + 1;
                  end loop;
                  raise Parse_Error with
                    Integer'Image (Cur (P).Line) & ":" &
                    Integer'Image (Cur (P).Col) & ": expected `name =`"
                    & (if Has_Eq
                       then "; a rule's head is its name alone (a C type "
                            & "before it is not read: an %action converts "
                            & "the value to the daemon's type)"
                       else "; a rule goes on to the next line only when "
                            & "that line is indented or starts with `|`");
               end;
            end if;
            Name := Cur (P).Text;
            Name_Line := Cur (P).Line;
            if First_Rule_Line = 0 then
               First_Rule_Line := Name_Line;
            end if;
            if P.Toks (P.Pos + 1).Kind = T_Eq_Slash then
               Extend (P, Rules, Index, Name, Name_Line);
               goto Next_Item;
            end if;
            if First_Defined = Null_Unbounded_String
              and then not Standing.Contains (To_String (Name))
            then
               First_Defined := Name;
            end if;
            Next (P);
            Next (P);   --  the '='

            --  `name = %scan{ code }` is a jet, as `name = { code }` is.
            if Cur (P).Kind = T_Pct and then To_String (Cur (P).Text) = "scan"
              and then P.Pos + 1 <= Natural (P.Toks.Length)
              and then P.Toks (P.Pos + 1).Kind = T_Code
            then
               Next (P);
            end if;
            if Cur (P).Kind = T_Code then
               --  A jet: `name = { <code> }` — a hand-written scanner.
               Define
                 (Rules, Index,
                  Rule'(Name            => Name,
                        Pattern         => Element_Vectors.Empty_Vector,
                        Leading_Comment => Leading,
                        Trailing_Comment => Trailing,
                        Jet_Code        => Cur (P).Text,
                        Action_Code     => Null_Unbounded_String,
                        Left_Bases      => 0));
               Standing.Include
                 (To_String (Name),
                  Standing_Rule'(R   => Rules (Index (To_String (Name))),
                                 Raw => Element_Vectors.Empty_Vector));
               Next (P);
            else
               declare
                  Action  : Unbounded_String := Null_Unbounded_String;
                  Pattern : Element_Vectors.Vector := Parse_Alternation (P);
                  Raw     : constant Element_Vectors.Vector := Pattern;
                  Bases   : Natural;
               begin
                  Rewrite_Left_Recursion (Name, Name_Line, Pattern, Bases);
                  --  An action jet: `name = pattern { code }` — the code
                  --  block after the pattern is run in the bind walk, not
                  --  during parsing.  A trailing comment sits after it.
                  if Cur (P).Kind = T_Pct then
                     --  `pattern %action{ code }`, the explicit spelling.
                     --  A %scan after a pattern is not supported yet.
                     if To_String (Cur (P).Text) /= "action"
                       or else P.Toks (P.Pos + 1).Kind /= T_Code
                     then
                        raise Parse_Error with
                          Integer'Image (Cur (P).Line) & ":"
                          & Integer'Image (Cur (P).Col) & ": "
                          & (if To_String (Cur (P).Text) = "scan"
                             then "%scan{ } takes the place of a pattern "
                                  & "(name = %scan{ ... })"
                             else "expected %action{ ... } after the pattern");
                     end if;
                     Next (P);
                  end if;
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
                  Define
                    (Rules, Index,
                     Rule'(Name            => Name,
                           Pattern         => Pattern,
                           Leading_Comment => Leading,
                           Trailing_Comment => Trailing,
                           Jet_Code        => Null_Unbounded_String,
                           Action_Code     => Action,
                           Left_Bases      => Bases));
                  Standing.Include
                    (To_String (Name),
                     Standing_Rule'(R   => Rules (Index (To_String (Name))),
                                    Raw => Raw));
               end;
            end if;
         end;
         <<Next_Item>>
      end loop;
      if File_Depth = 0 then
         Finish (Rules);
      end if;
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
         if Dir = "" or else (Name'Length > 0 and then Name (Name'First) = '/')
         then
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

      --  Where a path leads, links resolved, so a file included twice by
      --  different paths is still read once.
      function Resolved (P : String) return String is
        (GNAT.OS_Lib.Normalize_Pathname (P, Resolve_Links => True));

      --  An `include` line: the file it names and the line it is on.
      type Include_Line is record
         Target : Unbounded_String;
         Line   : Positive := 1;
      end record;
      package Include_Vectors is new
        Ada.Containers.Vectors (Positive, Include_Line);

      --  Walk Text (a file in directory Dir) line by line.  An `include`
      --  line reads the file it names into Acc, the first time that file
      --  is included, and is recorded in Incs; every other line is kept
      --  verbatim in Kept.  Of two included files, the later one's rule
      --  overrides the earlier one's.
      procedure Expand (Text : String; Dir : String;
                        Acc : in out Rule_Vectors.Vector;
                        Acc_Index : in out Index_Maps.Map;
                        Incs : in out Include_Vectors.Vector;
                        Kept : in out Unbounded_String)
      is
         Start : Natural := Text'First;
         Line_No : Positive := 1;
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
                     Incs.Append (Include_Line'(Target, Line_No));
                     declare
                        Sub_Path : constant String :=
                          Join (Dir, To_String (Target));
                     begin
                        if not Seen_Files.Contains (Resolved (Sub_Path)) then
                           for R of Parse_File (Sub_Path) loop
                              Define (Acc, Acc_Index, R);
                           end loop;
                        end if;
                     end;
                     --  Keep the line (empty), so errors in the rest of the
                     --  file report the line numbers the author sees.
                     Append (Kept, ASCII.LF);
                  else
                     Append (Kept, Line);
                     Append (Kept, ASCII.LF);
                  end if;
               end;
               Start := Stop + 1;
               Line_No := Line_No + 1;
            end;
         end loop;
      end Expand;

      --  The file's own rules come first, in the order it writes them (so a
      --  jet's place among the jets is where it is written).  Its includes
      --  are read before it, so its own rule overrides an included one of
      --  the same name; the remaining included rules append after.  The
      --  root, put first, is the file's first new rule: the first it
      --  defines with `=` that it does not override.  A file with none (a
      --  binding that only adds actions, or fills in an RFC's rules with
      --  overrides and `=/`) keeps the root of what it includes.
      function Override (Local, Included : Rule_Vectors.Vector;
                         First : Unbounded_String)
        return Rule_Vectors.Vector
      is
         Result : Rule_Vectors.Vector := Local;
         Names  : Path_Sets.Set;
         Root   : Natural := 0;
         Want   : constant Unbounded_String :=
           (if First /= Null_Unbounded_String then First
            elsif not Included.Is_Empty then Included.First_Element.Name
            else Null_Unbounded_String);
      begin
         for R of Local loop
            Names.Include (To_String (R.Name));
         end loop;
         for R of Included loop
            if not Names.Contains (To_String (R.Name)) then
               Result.Append (R);
            end if;
         end loop;
         for J in 1 .. Natural (Result.Length) loop
            if Result (J).Name = Want then
               Root := J;
               exit;
            end if;
         end loop;
         if Root > 1 then
            declare
               Top : constant Rule := Result (Root);
            begin
               Result.Delete (Root);
               Result.Prepend (Top);
            end;
         end if;
         return Result;
      end Override;

      --  Attach each pending `action name { code }` to its rule, once every
      --  file is read, so an action goes with the definition that stands.
      procedure Apply_Actions (Result : in out Rule_Vectors.Vector) is
         Hit : Natural;
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
               raise Parse_Error with
                 To_String (A.File) & ":" & Integer'Image (A.Line)
                 & ": action for `" & To_String (A.Name)
                 & "`, which no rule defines";
            elsif Result (Hit).Action_Code /= Null_Unbounded_String then
               raise Parse_Error with
                 To_String (A.File) & ":" & Integer'Image (A.Line)
                 & ": rule `" & To_String (A.Name)
                 & "` already has an action";
            else
               Result (Hit).Action_Code := A.Code;
            end if;
         end loop;
         Pending_Actions.Clear;
      end Apply_Actions;

      Included : Rule_Vectors.Vector;
      Inc_Index : Index_Maps.Map;
      Incs     : Include_Vectors.Vector;
      Local    : Rule_Vectors.Vector;
      Result   : Rule_Vectors.Vector;
      Out_Text : Unbounded_String;
   begin
      if File_Depth = 0 then
         Reset;
      end if;
      File_Depth := File_Depth + 1;
      Seen_Files.Include (Resolved (Path));
      Expand (Read_File (Path), Dir_Of (Path), Included, Inc_Index, Incs,
              Out_Text);
      Current_File := To_Unbounded_String (Path);
      Local := Parse (To_String (Out_Text));
      --  An include goes before the file's rules, so that "a later `=`
      --  overrides" holds: the file's own rules come after what it
      --  includes.
      for I of Incs loop
         if First_Rule_Line /= 0 and then I.Line > First_Rule_Line then
            raise Parse_Error with
              Integer'Image (I.Line) & ": include """ & To_String (I.Target)
              & """ after the first rule (line"
              & Integer'Image (First_Rule_Line) & "); includes go before "
              & "the rules, so the file's own rules override what it "
              & "includes";
         end if;
      end loop;
      Result := Override (Local, Included, First_Defined);
      if File_Depth = 1 then
         Apply_Actions (Result);
         Finish (Result);
      end if;
      File_Depth := File_Depth - 1;
      return Result;
   exception
      when E : Parse_Error =>
         File_Depth := 0;
         declare
            M : constant String := Error_Message (E);
         begin
            --  Name the file once, at the innermost one: " 3: 7: …"
            --  becomes "grammars/ntpd.hbnf: 3: 7: …".
            if M'Length > 0 and then M (M'First) = ' ' then
               Fail (Path & ":" & M);
            end if;
            Fail (M);
         end;
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

   --  The pieces in language Lang, joined with a newline.
   function Joined (Pieces : Piece_Vectors.Vector; Lang : String)
     return String
   is
      Buf : Unbounded_String;
   begin
      for P of Pieces loop
         if To_String (P.Lang) = Lang then
            if Buf /= Null_Unbounded_String then
               Append (Buf, ASCII.LF);
            end if;
            Append (Buf, P.Code);
         end if;
      end loop;
      return To_String (Buf);
   end Joined;

   function Preamble (Lang : String) return String is
     (Joined (Preamble_Pieces, Lang));

   function Epilogue (Lang : String) return String is
     (Joined (Epilogue_Pieces, Lang));

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

   function Entry_Name return String is
     (if Entry_Code = Null_Unbounded_String then "parse_config"
      else To_String (Entry_Code));

   function Statements return Boolean is (Statements_On);

   function Macros_Rule return String is (To_String (Macros_Name));

   function Includes_Rule return String is (To_String (Includes_Name));

   function Keyword_Table return Word_Vectors.Vector is (Keyword_Words);

   procedure Set_Type_Prefix (Prefix : String) is
   begin
      if not Valid_Prefix (Prefix) then
         raise Parse_Error with "--prefix: not a C identifier prefix: " & Prefix;
      end if;
      Type_Prefix_Code := To_Unbounded_String (Prefix);
   end Set_Type_Prefix;

end HBNF_Grammar;
