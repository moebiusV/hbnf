pragma Ada_2022;

with Ada.Characters.Handling;
with Ada.Environment_Variables;
with HBNF_Lookahead;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Containers.Ordered_Maps;
with System.Storage_Elements;
with Ada.Strings.Hash;
with Ada.Directories;
with Ada.Text_IO;
with GNAT.OS_Lib;

package body HBNF_Grammar is

   --  Labels of alternatives, by the address of the element they sit on.
   package Label_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => System.Storage_Elements.Integer_Address,
      Element_Type => Unbounded_String,
      "<" => System.Storage_Elements."<");
   Label_Table : Label_Maps.Map;

   function Key (E : Element_Access) return System.Storage_Elements.Integer_Address
   is (System.Storage_Elements.To_Integer (E.all'Address));

   function Label_Of (E : Element_Access) return String is
      C : constant Label_Maps.Cursor := Label_Table.Find (Key (E));
   begin
      return (if Label_Maps.Has_Element (C)
              then To_String (Label_Maps.Element (C)) else "");
   end Label_Of;

   procedure Set_Label (E : Element_Access; Name : String) is
   begin
      Label_Table.Include (Key (E), To_Unbounded_String (Name));
   end Set_Label;

   --  Schema-level metadata gathered by Parse.  A directive is one of two
   --  kinds (RFCPLAN.md decision 5):
   --  - per file: `language`, the language of the file's own code blocks;
   --  - whole parser: the rest.  Any file may set one; two settings that
   --    differ are refused (Set_Directive), `keywords` lists merge, and
   --    code blocks are joined in include order.
   --  Schema_Language is the language of the file read last, which is the
   --  top-level one (its includes are read before it).
   Schema_Language : Unbounded_String := To_Unbounded_String ("C");

   --  The state `%emit` changes, which a retry puts back (`rollback { tape_n }`).
   Rollback_Text : Unbounded_String;

   --  `layout ast|tape|NAME` (or --layout=): the data structure the parser builds.  A NAME other than
   --  tree and tape is a directory layouts/NAME of the layouts directory (layout.hbnf), which a grammar fragment reads
   --  as an include: its prologue, its layout_ops, its epilogue.
   Layout_Text  : Unbounded_String := To_Unbounded_String ("ast");
   Layout_Given : Boolean := False;
   Layout_Dir   : Unbounded_String;
   In_Layout    : Natural := 0;     --  while a layout file (or what it includes) is being read

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

   Type_Prefix_Code : Unbounded_String := Null_Unbounded_String;
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
   --  The line of the last `include` in the file being read; a code block after it, before any
   --  rule, belongs to the end of the file (the included rules come first), not the start.
   Epilogue_After_Line : Natural := 0;
   Context_Words   : Word_Vectors.Vector;
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

   --  =====================================================================
   --  Warnings (see the spec).  A warning goes to standard error and is
   --  counted; Werror makes the caller fail at the end rather than here, so
   --  every warning in a schema is reported before anything stops.
   --  =====================================================================

   package Key_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   Warn_Count : Natural := 0;
   Warn_Keys  : Key_Sets.Set;

   --  The rules declared `hidden`: by the name they were written with (a
   --  hyperrule's family) and by the name of each instance made from one.
   Hidden_Bases : Key_Sets.Set;

   --  The rules declared `flat`: under `layout tape` they keep their children and write no node.
   Flat_Bases : Key_Sets.Set;

   --  The C type of the value a rule has (`name :: type = ...`, RFCPLAN.md step 15), by rule name
   --  with its parameters left off.
   package Value_Type_Maps is new
     Ada.Containers.Indefinite_Hashed_Maps (String, String, Ada.Strings.Hash, "=");
   Value_Types : Value_Type_Maps.Map;
   Hidden_Rules : Key_Sets.Set;

   function Value_Type (Rule_Name : String) return String is
      Base : Natural := Rule_Name'First;
   begin
      while Base <= Rule_Name'Last and then Rule_Name (Base) /= '(' loop
         Base := Base + 1;
      end loop;
      return (if Value_Types.Contains (Rule_Name (Rule_Name'First .. Base - 1))
              then Value_Types.Element (Rule_Name (Rule_Name'First .. Base - 1)) else "");
   end Value_Type;

   function Is_Hidden (Nm : String) return Boolean is
     (Hidden_Rules.Contains (Nm) or else Hidden_Bases.Contains (Nm));
   Werror_On  : Boolean := False;

   procedure Warn (Where, Text : String) is
   begin
      Warn_Count := Warn_Count + 1;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hbnf: " & (if Where = "" then "" else Where & ": ")
         & "warning: " & Text);
   end Warn;

   procedure Warn_Once (Key, Where, Text : String) is
   begin
      if Warn_Keys.Contains (Key) then
         return;
      end if;
      Warn_Keys.Insert (Key);
      Warn (Where, Text);
   end Warn_Once;

   function Warnings return Natural is (Warn_Count);

   procedure Reset_Warnings is
   begin
      Warn_Count := 0;
      Warn_Keys.Clear;
      Hidden_Bases.Clear;
      Flat_Bases.Clear;
      Value_Types.Clear;
      Hidden_Rules.Clear;
   end Reset_Warnings;

   procedure Set_Werror (On : Boolean) is
   begin
      Werror_On := On;
   end Set_Werror;

   function Werror return Boolean is (Werror_On);

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

   --  Each whole-parser directive set so far (`layout_ops init` for one list
   --  operation), with its value and where it was set.
   type Setting is record
      Value : Unbounded_String;
      File  : Unbounded_String;
      Line  : Positive := 1;
      Weak  : Boolean := False;   --  set by a layout file: another file, or the grammar, may change it
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
            if To_String (Was.Value) /= Value and then Was.Weak and then In_Layout = 0 then
               --  the grammar changes what a layout set: the layout is specialised
               Settings.Replace
                 (Name, Setting'(Value => To_Unbounded_String (Value), File => Current_File,
                                 Line => Line, Weak => False));
            elsif To_String (Was.Value) /= Value and then not Was.Weak and then In_Layout > 0 then
               return;        --  a layout does not undo what the grammar said
            elsif To_String (Was.Value) /= Value and then Was.Weak then
               Settings.Replace      --  a layout over a layout: the later one
                 (Name, Setting'(Value => To_Unbounded_String (Value), File => Current_File,
                                 Line => Line, Weak => True));
            elsif To_String (Was.Value) /= Value then
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
                           Line  => Line,
                           Weak  => In_Layout > 0));
      end if;
      Target := To_Unbounded_String (Value);
   end Set_Directive;

   --  A rule's place in a rule list, by name (0 where Finish finds more
   --  than one).
   package Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Natural, Ada.Strings.Hash, "=");

   --  The named domains of a file: `level ::= 1..17`.  The body is
   --  kept as written (comments out); Expand_Params reads it where a parameter
   --  says `N in level`.
   package Domain_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, String, Ada.Strings.Hash, "=");
   Domain_Bodies : Domain_Maps.Map;
   Domains_Used  : Index_Maps.Map;        --  the domains a parameter names
   --  A context named where none is declared (`%bind C += x`, `x ? C`), with where it was first
   --  named: it is a rule parameter, until the expansion of the hyperrules says it is not.
   package Pending_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, String);
   Ctx_Pending   : Pending_Maps.Map;

   --  Where a literal stood among its rule's alternatives as written, for a
   --  rule whose alternatives the reader put in another order to match them
   --  (`/`, longest first).  Key: rule NUL literal.  See Enum_Rank.
   package Rank_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Natural, Ada.Strings.Hash, "=");
   Enum_Ranks : Rank_Maps.Map;

   --  Code and declarations of the bit layer (see Split_Wire).
   package Text_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, String, Ada.Strings.Hash, "=");
   Emit_Table      : Text_Maps.Map;      --  rule -> its %emit code
   Wire_Store      : Rule_Vectors.Vector;
   Wire_Root_Flag  : Boolean := False;

   function Is_Wire_Rule (Name : String) return Boolean is
   begin
      for R of Wire_Store loop
         if To_String (R.Name) = Name then
            return True;
         end if;
      end loop;
      return False;
   end Is_Wire_Rule;

   function Wire_Rules return Rule_Vectors.Vector is (Wire_Store);
   function Wire_Root return Boolean is (Wire_Root_Flag);

   function Emit_Code (Rule_Name : String) return String is
     (if Emit_Table.Contains (Rule_Name) then Emit_Table (Rule_Name) else "");

   function Enum_Value (Rule_Name, Literal : String) return Integer is
      C : constant Rank_Maps.Cursor :=
        Enum_Ranks.Find (Rule_Name & ASCII.NUL & Literal);
   begin
      return (if Rank_Maps.Has_Element (C) then Rank_Maps.Element (C) else -1);
   end Enum_Value;

   function Enum_Order (Values : Value_Array) return Order_Array is
      Result : Order_Array (Values'Range) :=
        [for K in Values'Range => K - Values'First + 1];
   begin
      if Values'Length = 0 or else Values (Values'First) < 0 then
         return Result;
      end if;
      --  A stable insertion sort by value; the lists are dense and nearly in
      --  order when they are long.
      for K in Values'First + 1 .. Values'Last loop
         declare
            Item : constant Positive := Result (K);
            J    : Integer := K - 1;
         begin
            while J >= Values'First
              and then Values (Values'First + Result (J) - 1)
                       > Values (Values'First + Item - 1)
            loop
               Result (J + 1) := Result (J);
               J := J - 1;
            end loop;
            Result (J + 1) := Item;
         end;
      end loop;
      return Result;
   end Enum_Order;

   function Enum_Init
     (Values : Value_Array; Order : Order_Array; J : Positive) return String
   is
      First : constant Integer := Values'First;
   begin
      if Values'Length = 0 or else Values (First) < 0 then
         return "";
      end if;
      declare
         V    : constant Integer := Values (First + Order (Order'First + J - 1) - 1);
         Prev : constant Integer :=
           (if J = 1 then 0
            else Values (First + Order (Order'First + J - 2) - 1) + 1);
      begin
         return (if V = Prev then "" else " =" & Integer'Image (V));
      end;
   end Enum_Init;

   function Enum_Sparse (Values : Value_Array; Order : Order_Array)
     return Boolean is
   begin
      for J in 1 .. Values'Length loop
         if Enum_Init (Values, Order, J) /= "" then
            return True;
         end if;
      end loop;
      return False;
   end Enum_Sparse;

   function Enum_Max (Values : Value_Array) return Natural is
      M : Natural := 0;
   begin
      for V of Values loop
         M := Natural'Max (M, Natural'Max (V, 0));
      end loop;
      return M;
   end Enum_Max;

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

   --  Per file, from its `whitespace ws` line: the char rule a phrase rule
   --  in this file skips between its elements.  "" when the file sets none.
   File_Whitespace : Unbounded_String := Null_Unbounded_String;

   --  Some rule names `word` or `atom`, as of the last schema read.
   Words_Used : Boolean := False;

   --  `--abnf` (Set_Abnf): files read as RFC 5234 reads them by default.
   Abnf_Mode : Boolean := False;

   --  `--ebnf` (Set_Ebnf): files read as ISO 14977 reads them.
   Ebnf_Mode : Boolean := False;

   --  `--dialect=bnf|ebnf|ybnf`: `|` is the union, as in those notations.
   Union_Bar_Mode : Boolean := False;

   --  The rule to start from instead of the first one (Set_Root), or "".
   Root_Rule : Unbounded_String := Null_Unbounded_String;

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

   --  A rule written `<table reference>` in a BNF file is the rule
   --  `table-reference`; the spelling the author used, for the messages.
   package Spelling_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, String, Ada.Strings.Hash, "=");
   Bnf_Spellings : Spelling_Maps.Map;

   --  Scanners written for other backends (`name = Rust { ... }`).
   type Jet_Entry is record
      Rust, Zig, Ada : Unbounded_String := Null_Unbounded_String;
   end record;
   package Jet_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, Jet_Entry, Ada.Strings.Hash, "=");
   Jets : Jet_Maps.Map;

   --  Exception rules, `X = A - B`: X to its B, and to its A, for the check.
   package Except_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (String, String, Ada.Strings.Hash, "=");
   Excepts       : Except_Maps.Map;   --  X -> B
   Except_Bases  : Except_Maps.Map;   --  X -> A
   Pending_Except_A : Unbounded_String;   --  set by Parse_Body for its rule
   Pending_Except_B : Unbounded_String;

   --  The dialect, for the prefix on generated identifiers: the one a flag
   --  named (kept across files), else the first a file's `dialect` line named.
   Flag_Dialect : Unbounded_String;
   --  `prefix none` in a file, `--prefix=none` on the command line: the
   --  generated identifiers keep the names of the rules.
   No_Name_Prefix : Boolean := False;
   Token_Yes, Token_No : Path_Sets.Set;   --  Except_Is_Token, per rule count
   Text_Yes, Text_No   : Path_Sets.Set;   --  Is_Text_Rule, per rule count
   Flag_No_Prefix : Boolean := False;
   Emitted_Rules : Path_Sets.Set;
   File_Dialect : Unbounded_String;

   --  A rule by name.  A grammar with parameterised rules has thousands, and the
   --  checks ask for them hundreds of thousands of times, so the names are kept
   --  in a table that is made again when the number of rules is not the one it
   --  was made for.  A hit is checked against the rule it names, and a miss
   --  falls back to looking through the rules, so a table that is out of date
   --  costs time and never gives a wrong answer.
   package Name_Index_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, Natural);
   Name_Index     : Name_Index_Maps.Map;
   Name_Index_Len : Natural := 0;

   function Index_Of (Rules : Rule_Vectors.Vector; Name : String)
      return Natural is
      N : constant Natural := Natural (Rules.Length);
   begin
      if N /= Name_Index_Len then
         Name_Index.Clear;
         for I in 1 .. N loop
            declare
               Nm : constant String := To_String (Rules (I).Name);
            begin
               if not Name_Index.Contains (Nm) then
                  Name_Index.Insert (Nm, I);
               end if;
            end;
         end loop;
         Name_Index_Len := N;
      end if;
      declare
         C : constant Name_Index_Maps.Cursor := Name_Index.Find (Name);
      begin
         if Name_Index_Maps.Has_Element (C) then
            declare
               J : constant Natural := Name_Index_Maps.Element (C);
            begin
               if J <= N and then To_String (Rules (J).Name) = Name then
                  return J;
               end if;
            end;
         end if;
      end;
      for I in 1 .. N loop
         if To_String (Rules (I).Name) = Name then
            Name_Index_Len := 0;       --  the table is out of date
            return I;
         end if;
      end loop;
      return 0;
   end Index_Of;

   function Is_Char_Rule_Plain (Rules : Rule_Vectors.Vector; Nm : String)
      return Boolean;
   --  The scanner shapes (a sequence of code points ending in one repetition),
   --  without the exception rules and their operands.

   --  yacc's %token declarations (see the parser): each name, with the
   --  spelling the comment under it gives, if any.
   type Declared_Token is record
      Name     : Unbounded_String;
      Spelling : Unbounded_String;
      Line     : Positive;
   end record;
   package Declared_Vectors is new Ada.Containers.Vectors
     (Positive, Declared_Token);
   Declared_Tokens : Declared_Vectors.Vector;
   package String_Lists is new Ada.Containers.Vectors
     (Positive, Unbounded_String);

   --  The sets Alt.Guard names (see Guard_Ranges).
   package Range_Lists is new Ada.Containers.Vectors (Positive, Guard_Range);
   type Guard_Set is record
      Ranges : Range_Lists.Vector;
      Eoi    : Boolean := False;
   end record;
   package Guard_Vectors is new Ada.Containers.Vectors (Positive, Guard_Set);
   Guards : Guard_Vectors.Vector;

   Union_Sites : Site_Vectors.Vector;
   Greedy_Sites : Site_Vectors.Vector;   --  elements that repeat a variable number of times

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
      Rollback_Text := Null_Unbounded_String;
      if not Layout_Given then
         Layout_Text := To_Unbounded_String ("ast");
      end if;
      Domain_Bodies.Clear;
      Domains_Used.Clear;
      Preamble_Pieces.Clear;
      Epilogue_Pieces.Clear;
      Type_Prefix_Code := Null_Unbounded_String;
      List_Head_Code := Null_Unbounded_String;
      List_Entry_Code := Null_Unbounded_String;
      List_Init_Code := Null_Unbounded_String;
      List_Append_Code := Null_Unbounded_String;
      List_Foreach_Code := Null_Unbounded_String;
      List_First_Code := Null_Unbounded_String;
      List_Next_Code := Null_Unbounded_String;
      List_Relink_Code := Null_Unbounded_String;
      Statements_On := False;
      Context_Words.Clear;
      Ctx_Pending.Clear;
      Macros_Name := Null_Unbounded_String;
      Includes_Name := Null_Unbounded_String;
      Keyword_Words.Clear;
      Pending_Actions.Clear;
      Settings.Clear;
      Seen_Files.Clear;
      Current_File := Null_Unbounded_String;
      First_Rule_Line := 0;
      Prose_Sites.Clear;
      Bnf_Spellings.Clear;
      Jets.Clear;
      Guards.Clear;
      Excepts.Clear;
      Except_Bases.Clear;
      File_Dialect := Null_Unbounded_String;
      No_Name_Prefix := False;
      Token_Yes.Clear;
      Token_No.Clear;
      Text_Yes.Clear;
      Text_No.Clear;
      Pending_Except_B := Null_Unbounded_String;
      Declared_Tokens.Clear;
      Union_Sites.Clear;
      Greedy_Sites.Clear;
      Standing.Clear;
      Enum_Ranks.Clear;
      Emit_Table.Clear;
      Wire_Store.Clear;
      Wire_Root_Flag := False;
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
                     T_Prose, T_Tilde, T_At, T_Colon, T_Octets, T_Count, T_Bits,
                     T_Guard, T_Hash, T_Meta, T_EOF);

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

   --  The value of a number as the lexer reads it, whatever its form: decimal, `0x` hex, `0b` binary, `0o` octal.
   --  Every place that takes a number (an enum value, a bit position, a width, a repeat count) goes through this one
   --  function, so no spelling works in one place and not another.
   function Number_Value (S : String) return Long_Long_Integer is
      Base  : Long_Long_Integer := 10;
      First : Positive := S'First;
      V     : Long_Long_Integer := 0;
      D     : Integer;
   begin
      if S'Length > 2 and then S (S'First) = '0' then
         case S (S'First + 1) is
            when 'x' | 'X' => Base := 16;  First := S'First + 2;
            when 'b' | 'B' => Base := 2;   First := S'First + 2;
            when 'o' | 'O' => Base := 8;   First := S'First + 2;
            when others    => null;
         end case;
      end if;
      for I in First .. S'Last loop
         D := Hex_Digit (S (I));
         if D < 0 or else Long_Long_Integer (D) >= Base then
            raise Constraint_Error with "bad digit in the number " & S;
         end if;
         V := V * Base + Long_Long_Integer (D);
      end loop;
      return V;
   end Number_Value;

   --  The rule a `<...>` names: its words joined with `-`, so `<table
   --  reference>` is `table-reference` and `<pchar>` is `pchar`.  Text that is
   --  not a name (`<host, see [URI], Section 3.2.2>`) keeps its characters as
   --  `_` and a checksum, so it is a rule of its own that nothing defines.
   function Prose_Id (S : String) return String is
      R       : Unbounded_String;
      Gap     : Boolean := False;
      Altered : Boolean := False;
      Sum     : Natural := 0;
      Hex     : constant String := "0123456789abcdef";
   begin
      for C of S loop
         Sum := (Sum * 31 + Character'Pos (C)) mod 65536;
         if C = ' ' or else C = ASCII.HT then
            Gap := Length (R) > 0;
         else
            if Gap then
               Append (R, '-');
               Gap := False;
            end if;
            if C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' then
               Append (R, C);
            else
               Append (R, '_');
               Altered := True;
            end if;
         end if;
      end loop;
      if Length (R) = 0 then
         return "";
      end if;
      if To_String (R) (1) in '0' .. '9' | '-' then
         R := To_Unbounded_String ("n-") & R;
      end if;
      if Altered then
         Append (R, "_" & Hex (Sum / 4096 + 1) & Hex (Sum / 256 mod 16 + 1)
                 & Hex (Sum / 16 mod 16 + 1) & Hex (Sum mod 16 + 1));
      end if;
      return To_String (R);
   end Prose_Id;

   --  True when the text is words and nothing else: a rule's name, not a
   --  description with punctuation in it.
   function Plain_Words (S : String) return Boolean is
     (S'Length > 0
      and then (for all C of S =>
                  C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-'
                       | ' ' | ASCII.HT));

   --  What to add to "unexpected character" when it is another notation's
   --  symbol: how that notation writes it and how hbnf does.
   function Character_Hint (C : Character) return String is
      LF2 : constant String := (1 => ASCII.LF) & "  ";
   begin
      case C is
         when ',' =>
            return LF2 & "In EBNF (ISO 14977) `,` joins the elements of a "
              & "rule, and `{ x }` repeats `x`.  hbnf joins elements by "
              & "writing them in a row, and repeats with `*x`: `a , { b }` is "
              & "`a *b`.  (`[ x ]` and `( x )` mean the same in both.)  To "
              & "read a file as EBNF, put a line `ebnf` in it, or pass "
              & "`--ebnf`.";
         when '.' =>
            return LF2 & "In Wirth's EBNF a rule ends with `.`.  hbnf's rule "
              & "ends at the end of the line (a line that goes on is "
              & "indented), so leave the `.` out.  (In BNF `...` abbreviates "
              & "a list of terminals: write them out, or a range such as "
              & "`%x30-39`.)";
         when '>' =>
            return LF2 & "`>` closes a BNF rule name `<name>`, and no `<` "
              & "opened one here.";
         when others =>
            return LF2 & "If this is a terminal, hbnf writes it in quotes, "
              & "`""x""`, or as `'x'` for one character"
              & ".";
      end case;
   end Character_Hint;

   function Lex (Text : String) return Token_Vectors.Vector is
      Toks : Token_Vectors.Vector;
      I    : Natural  := Text'First;
      Line : Positive := 1;
      Col  : Positive := 1;
      Lang : constant Lang_Kind := Detect_Language (Text);

      --  `dialect abnf | ebnf | ...`, a directive on a line of its own, or
      --  `--dialect=` / `--abnf` / `--ebnf`.  The lexer needs two of them
      --  ahead of the lexing they change: ABNF reads a backslash in a string
      --  as a backslash; ISO 14977 ends a rule with `;`, repeats with
      --  `{ x }`, joins with `,`, and reads `n * x` as exactly n.
      function Dialect_Is (Name : String) return Boolean is
         K : Natural := Text'First;
      begin
         while K <= Text'Last loop
            declare
               L : Natural := K;
               E : Natural;
            begin
               while L <= Text'Last and then Text (L) in ' ' | ASCII.HT loop
                  L := L + 1;
               end loop;
               E := L;
               while E <= Text'Last and then Text (E) /= ASCII.LF loop
                  E := E + 1;
               end loop;
               if E - L > 8 and then Text (L .. L + 7) = "dialect "
               then
                  declare
                     V : Natural := L + 8;
                     W : Natural;
                  begin
                     while V < E and then Text (V) in ' ' | ASCII.HT loop
                        V := V + 1;
                     end loop;
                     W := V;
                     while W < E and then Text (W) not in ' ' | ASCII.HT
                       | ';' | ASCII.CR
                     loop
                        W := W + 1;
                     end loop;
                     if Text (V .. W - 1) = Name then
                        return True;
                     end if;
                  end;
               end if;
               K := E + 1;
            end;
         end loop;
         return False;
      end Dialect_Is;

      Abnf_Here : constant Boolean := Abnf_Mode or else Dialect_Is ("abnf");
      Ebnf_Here : constant Boolean := Ebnf_Mode or else Dialect_Is ("ebnf");

      --  In BNF, EBNF and YBNF (yacc) a bar is the union, as `/` is in ABNF.
      Bar_Is_Union : constant Boolean :=
        Union_Bar_Mode or else Dialect_Is ("bnf") or else Dialect_Is ("ebnf")
        or else Dialect_Is ("ybnf");

      --  A backslash in a string is a backslash, in ABNF and in EBNF.
      Raw_Strings : constant Boolean := Abnf_Here or else Ebnf_Here;

      --  In hbnf `=` defines a rule, `:=` a rule with parameters (a hyperrule)
      --  and `::=` a domain (a metarule), as in the ALGOL 68 Report's `:` and
      --  `::`.  A file that names another notation (`dialect bnf`, `ybnf`,
      --  `ebnf`, `abnf`) reads every operator as the one that defines a rule.
      Legacy_Ops : constant Boolean := Bar_Is_Union or else Raw_Strings;

      --  First_Col is the token's first column, for a token Emit sees
      --  only once it has been read past (a quoted string); 0 means Col.
      procedure Emit
        (K : Tok_Kind; S : String := ""; First_Col : Natural := 0) is
      begin
         Token_Vectors.Append
           (Toks, Token'(K, Line, (if First_Col = 0 then Col else First_Col),
                         To_Unbounded_String (S)));
      end Emit;

      --  The index of the bracket that closes the one at From (`(`, `[`),
      --  0 if none does; quoted strings are skipped.
      function Matching (From : Positive) return Natural is
         Depth : Natural := 0;
         K     : Natural := From;
      begin
         while K <= Text'Last loop
            case Text (K) is
               when '(' | '[' =>
                  Depth := Depth + 1;
               when ')' | ']' =>
                  Depth := Depth - 1;
                  if Depth = 0 then
                     return K;
                  end if;
               when '"' =>
                  K := K + 1;
                  while K <= Text'Last and then Text (K) /= '"' loop
                     K := K + 1;
                  end loop;
               when others =>
                  null;
            end case;
            K := K + 1;
         end loop;
         return 0;
      end Matching;

      --  The text of a bit field's expression is kept as written, for the wire
      --  layer's own expression reader: from the bracket at I to its mate.
      procedure Take_Raw (K : Tok_Kind) is
         M : constant Natural := Matching (I);
      begin
         if M = 0 then
            raise Parse_Error with
              Integer'Image (Line) & ":" & Integer'Image (Col)
              & ": this `" & Text (I) & "` is never closed";
         end if;
         Emit (K, Text (I + 1 .. M - 1));
         for J in I .. M loop
            if Text (J) = ASCII.LF then
               Line := Line + 1;
               Col := 1;
            else
               Col := Col + 1;
            end if;
         end loop;
         I := M + 1;
      end Take_Raw;

      --  A `:` glued to the name (or the number of `name@K`) before it is a
      --  width.  The `:` after a rule's name in column 1 is the operator.
      function Glued_Width_Colon return Boolean is
      begin
         if Toks.Is_Empty or else I >= Text'Last then
            return False;
         end if;
         if Text (I + 1) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR | '=' | ':'
         then
            return False;
         end if;
         declare
            P : constant Token := Toks.Last_Element;
         begin
            if P.Line /= Line then
               return False;
            elsif P.Kind = T_Name then
               return P.Col /= 1 and then P.Col + Length (P.Text) = Col;
            elsif P.Kind = T_Number and then Natural (Toks.Length) >= 2 then
               return Toks (Toks.Last_Index - 1).Kind = T_At
                 and then P.Col + Length (P.Text) = Col;
            end if;
            return False;
         end;
      end Glued_Width_Colon;

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

      --  A block comment, `/* ... */` (C, yacc, POSIX BNF) or `(* ... *)`
      --  (Wirth, ISO 14977), read alongside `;` (RFCPLAN.md step 7a).  I is
      --  at the opening `/` or `(`; Close is the two characters that end it.
      --  Neither form nests.  The comment is white space: the lines inside
      --  it are counted but no T_Newline is emitted for them, which is yacc's
      --  reading and what a pasted grammar needs.  A comment that opened and
      --  closed on one line becomes a T_Comment, exactly as `;` does, so a
      --  trailing comment still round-trips into the generated output; one
      --  that spanned lines is dropped, because there is no single line for
      --  it to trail.
      procedure Block_Comment (Close : String) is
         Open_Line : constant Positive := Line;
         CC        : constant Positive := Col;
         Start     : constant Positive := I + 2;
      begin
         I := I + 2;
         Col := Col + 2;
         loop
            if I > Text'Last then
               raise Parse_Error with
                 Integer'Image (Open_Line) & ":" & Integer'Image (CC)
                 & ": a `" & Text (Start - 2 .. Start - 1)
                 & "` comment is never closed; it needs a `" & Close & "`";
            end if;
            exit when I < Text'Last
              and then Text (I) = Close (Close'First)
              and then Text (I + 1) = Close (Close'Last);
            if Text (I) = ASCII.LF then
               Line := Line + 1;
               Col := 1;
            else
               Col := Col + 1;
            end if;
            I := I + 1;
         end loop;
         declare
            Body_Text : constant String := Text (Start .. I - 1);
         begin
            I := I + 2;
            Col := Col + 2;
            --  Inside ( ) or [ ] a comment is part of the rule and is
            --  dropped, as a `;` comment there is.
            if Group_Depth = 0 and then Line = Open_Line then
               Token_Vectors.Append
                 (Toks, Token'(T_Comment, Open_Line, CC,
                               To_Unbounded_String (Trim (Body_Text))));
            end if;
         end;
      end Block_Comment;

   begin
      while I <= Text'Last loop
         case Text (I) is
            when ' ' | ASCII.HT =>
               I := I + 1;  Col := Col + 1;
            when ASCII.LF =>
               if Ebnf_Here then
                  --  A line end is white space; only `;` ends a rule.  But a
                  --  directive (`ebnf`, `include "x"`, `language C`) is a line.
                  declare
                     K : Natural := Natural (Toks.Length);
                  begin
                     while K > 1 and then Toks (K - 1).Line = Line loop
                        K := K - 1;
                     end loop;
                     if K >= 1 and then Natural (Toks.Length) >= K
                       and then Toks (K).Line = Line
                       and then Toks (K).Kind = T_Name
                       and then To_String (Toks (K).Text) in
                                  "dialect" | "include" | "language"
                                  | "sensitivity" | "whitespace" | "keywords"
                                  | "statements" | "macros" | "includes"
                                  | "context" | "rollback" | "layout" | "layout_ops" | "flat"
                                  | "prefix" | "wordchars"
                     then
                        Emit (T_Newline);
                     elsif K >= 1 and then Natural (Toks.Length) >= K
                       and then Toks (K).Line = Line
                       and then Toks (K).Kind = T_Name
                       and then To_String (Toks (K).Text) = "hidden"
                       and then not (for some J in K .. Natural (Toks.Length) =>
                                       Toks (J).Kind in T_Eq | T_Eq_Slash)
                     then
                        --  `hidden nl gap`: a directive line.  `hidden nl = ...`
                        --  is a rule and goes on to its end.
                        Emit (T_Newline);
                     end if;
                  end;
                  I := I + 1;  Line := Line + 1;  Col := 1;
               else
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
               end if;
            when ASCII.CR =>
               I := I + 1;
            when ';' =>
               if Ebnf_Here then
                  --  ISO 14977: `;` ends a rule.
                  Emit (T_Newline);  I := I + 1;  Col := Col + 1;
               else
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
               end if;
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
                     elsif Text (I) = '\' and then not Raw_Strings then
                        --  (Under `--abnf` a backslash is a backslash, as
                        --  RFC 5234 reads `"\"`.)
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
                     elsif Text (I) = ASCII.LF then
                        --  A literal does not run onto the next line.  The
                        --  usual cause is ABNF's `"\"`, the one-character
                        --  string: here a backslash starts an escape, so
                        --  `\"` is a quote inside the string and it goes on.
                        raise Parse_Error with
                          Integer'Image (Line) & ":" & Integer'Image (At_Col) &
                          ": this string literal does not end on its line.  "
                          & "A backslash in ""..."" starts an escape, so `\""` "
                          & "is a quote inside the string and `""\""` never "
                          & "closes: write a backslash as `\\` or %x5C";
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
                  --  `%spaces(k + 1)`: the number is an expression in
                  --  parentheses, one name for the parser (`%spaces k` is a name).
                  if Text (Start .. I - 1) in "spaces" | "col" | "num"
                    and then I <= Text'Last and then Text (I) = '('
                  then
                     declare
                        Depth : Natural := 0;
                        J     : Positive := I;
                     begin
                        while J <= Text'Last loop
                           if Text (J) = ASCII.LF then
                              raise Parse_Error with
                                Integer'Image (Line) & ":" & Integer'Image (Col)
                                & ": `%" & Text (Start .. I - 1) & "(`: the "
                                & "expression ends with `)` on the same line";
                           elsif Text (J) = '(' then
                              Depth := Depth + 1;
                           elsif Text (J) = ')' then
                              Depth := Depth - 1;
                              exit when Depth = 0;
                           end if;
                           J := J + 1;
                        end loop;
                        if J > Text'Last then
                           raise Parse_Error with
                             Integer'Image (Line) & ":" & Integer'Image (Col)
                             & ": `%" & Text (Start .. I - 1) & "(`: the "
                             & "expression ends with `)`";
                        end if;
                        Emit (T_Name, Text (I + 1 .. J - 1));
                        Col := Col + (J + 1 - I);
                        I := J + 1;
                     end;
                  end if;
                  --  `%bind types += declarators.name`: the context, then the
                  --  path of the field to add.  (`%bind { code }` is code.)
                  if Text (Start .. I - 1) = "bind" then
                     declare
                        J : Natural := I;
                        function Word_Char (C : Character; Dot : Boolean)
                          return Boolean is
                          (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-'
                           or else (Dot and then C = '.'));
                        procedure Skip is
                        begin
                           while J <= Text'Last
                             and then Text (J) in ' ' | ASCII.HT
                           loop
                              J := J + 1;
                           end loop;
                        end Skip;
                        Ctx_First, Ctx_Last, Path_First, Path_Last : Natural;
                     begin
                        Skip;
                        if J <= Text'Last and then Word_Char (Text (J), False)
                        then
                           Ctx_First := J;
                           while J <= Text'Last
                             and then Word_Char (Text (J), False)
                           loop
                              J := J + 1;
                           end loop;
                           Ctx_Last := J - 1;
                           Skip;
                           if J + 1 > Text'Last
                             or else Text (J .. J + 1) /= "+="
                           then
                              raise Parse_Error with
                                Integer'Image (Line) & ":" & Integer'Image (Col)
                                & ": `%bind` adds a field to a context: "
                                & "`%bind types += declarators.name`";
                           end if;
                           J := J + 2;
                           Skip;
                           Path_First := J;
                           while J <= Text'Last
                             and then Word_Char (Text (J), True)
                           loop
                              J := J + 1;
                           end loop;
                           Path_Last := J - 1;
                           if Path_Last < Path_First then
                              raise Parse_Error with
                                Integer'Image (Line) & ":" & Integer'Image (Col)
                                & ": `%bind " & Text (Ctx_First .. Ctx_Last)
                                & " +=` needs the field to add: "
                                & "`%bind types += declarators.name`";
                           end if;
                           Emit (T_Name, Text (Ctx_First .. Ctx_Last));
                           Emit (T_Name, Text (Path_First .. Path_Last));
                           Col := Col + (J - I);
                           I := J;
                        end if;
                     end;
                  end if;
               end;
            when '@' =>
               --  `"icmp"@1`: the value of an enum's literal.
               Emit (T_At);  I := I + 1;  Col := Col + 1;
            when '=' =>
               --  `=/` adds alternatives to a rule (RFC 5234 §3.3).
               if I < Text'Last and then Text (I + 1) = '/' then
                  Emit (T_Eq_Slash);  I := I + 2;  Col := Col + 2;
               else
                  Emit (T_Eq, (if Legacy_Ops then "" else "="));
                  I := I + 1;  Col := Col + 1;
               end if;
            when ':' =>
               --  The other notations' assignment operators, so a grammar
               --  lifted out of a spec reads as written (RFCPLAN.md step
               --  7a): `::=` is Naur's and ALGOL 60's, `:=` is Wirth's,
               --  and a bare `:` is yacc's and POSIX's.  All three are `=`.
               --
               --  When wire widths land (step 7b) a width is a `:` glued to
               --  a name and followed by a digit; nothing here may consume
               --  that, so the `:` cases stay as narrow as they are.
               if not Legacy_Ops and then I + 2 <= Text'Last
                 and then Text (I .. I + 2) = "::="
                 and then not Toks.Is_Empty
                 and then Toks.Last_Element.Kind = T_Name
                 and then Toks.Last_Element.Col = 1
               then
                  --  A metarule (`level ::= 1..17`): it defines a domain, a set
                  --  of values, and its body is kept as written, through the
                  --  lines that continue it.
                  declare
                     J    : Positive := I + 3;
                     Raw  : Unbounded_String;
                     In_Q : Boolean := False;
                  begin
                     loop
                        while J <= Text'Last and then Text (J) /= ASCII.LF loop
                           if Text (J) = '"' then
                              In_Q := not In_Q;
                              Append (Raw, '"');
                           elsif Text (J) = ';' and then not In_Q then
                              while J <= Text'Last and then Text (J) /= ASCII.LF loop
                                 J := J + 1;
                              end loop;
                              exit;
                           else
                              Append (Raw, Text (J));
                           end if;
                           J := J + 1;
                        end loop;
                        exit when J >= Text'Last;
                        if Text (J + 1) in ' ' | ASCII.HT | '|' | '/' then
                           Append (Raw, ' ');
                           J := J + 1;
                           Line := Line + 1;
                           Col := 1;
                        else
                           exit;
                        end if;
                     end loop;
                     Emit (T_Meta, To_String (Raw));
                     I := J;
                  end;
               elsif not Legacy_Ops and then I + 2 <= Text'Last
                 and then Text (I + 1) = ':'
                 and then Text (I + 2) in ' ' | ASCII.HT
               then
                  --  `name :: type = ...`: the type of the value a rule has (RFCPLAN.md
                  --  step 15).  A word of its own, `::`, which the rule head reads.
                  Emit (T_Name, "::");  I := I + 2;  Col := Col + 2;
               elsif I + 1 < Text'Last and then Text (I + 1) = ':'
                 and then Text (I + 2) = '='
               then
                  Emit (T_Eq);  I := I + 3;  Col := Col + 3;
               elsif I < Text'Last and then Text (I + 1) = '=' then
                  Emit (T_Eq, (if Legacy_Ops then "" else ":="));
                  I := I + 2;  Col := Col + 2;
               elsif Glued_Width_Colon then
                  --  `ttl:8`, `data:[len]`, `src:(n)*rec`, `n:bits(w)`: the
                  --  bit layer.  An expression is kept as the text written.
                  Emit (T_Colon);  I := I + 1;  Col := Col + 1;
                  if Text (I) = '[' then
                     Take_Raw (T_Octets);
                  elsif Text (I) = '(' then
                     declare
                        M : constant Natural := Matching (I);
                        K : Natural := M + 1;
                     begin
                        while M /= 0 and then K <= Text'Last
                          and then Text (K) in ' ' | ASCII.HT
                        loop
                           K := K + 1;
                        end loop;
                        if M /= 0 and then K <= Text'Last
                          and then Text (K) = '*'
                        then
                           Take_Raw (T_Count);
                        end if;
                     end;
                  elsif I + 4 <= Text'Last and then Text (I .. I + 4) = "bits("
                  then
                     I := I + 4;  Col := Col + 4;
                     Take_Raw (T_Bits);
                  end if;
               else
                  --  A bare `:` is yacc's, and yacc's `|` is unordered: its
                  --  tables resolve the choice.  hbnf's `|` is PEG
                  --  first-match, so a pasted yacc grammar compiles and can
                  --  mean something else.  Say so once per file — silently
                  --  changing a grammar's meaning is the one outcome 7a
                  --  must not produce.
                  if not Bar_Is_Union then
                  Warn_Once
                    ("yacc-colon:" & To_String (Current_File),
                     (if Current_File = Null_Unbounded_String then ""
                      else To_String (Current_File) & ":")
                     & Img (Line),
                     "`:` is yacc's assignment operator, and yacc's `|` is "
                     & "unordered — its tables resolve the choice.  hbnf's "
                     & "`|` is ordered: the first branch that matches wins, "
                     & "so write the longer alternative first.  Where order "
                     & "should not matter (yacc's `|`, BNF's, EBNF's), write "
                     & "`/`: hbnf finds an order that gives the same language, "
                     & "or says why none does.  Or name the notation: the line "
                     & "`dialect ybnf` reads `|` as the union.");
                  end if;
                  Emit (T_Eq);  I := I + 1;  Col := Col + 1;
               end if;
            --  `|` separates alternatives, as in BNF, EBNF and yacc, and
            --  means ordered choice.  `/` is ABNF's union (RFCPLAN.md,
            --  decision 1); the reader takes it where the two mean the same.
            when '|' =>
               Emit (if Bar_Is_Union then T_Slash else T_Bar);
               I := I + 1;  Col := Col + 1;
            when '/' =>
               if I < Text'Last and then Text (I + 1) = '*' then
                  Block_Comment ("*/");
               else
                  Emit (T_Slash);  I := I + 1;  Col := Col + 1;
               end if;
            when '(' | '[' =>
               --  `(*` opens a Wirth comment only when a blank follows it.
               --  `(*word)` is a group holding a repetition and stays one;
               --  ISO 14977 writes `(* text *)`, so the blank is the whole
               --  of the difference and it is cheap to require.
               if Text (I) = '(' and then I + 1 < Text'Last
                 and then Text (I + 1) = '*'
                 and then Text (I + 2) in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
               then
                  Block_Comment ("*)");
               else
                  Emit (if Text (I) = '(' then T_LParen else T_LBrack);
                  Group_Depth := Group_Depth + 1;
                  I := I + 1;  Col := Col + 1;
               end if;
            when ')' | ']' =>
               Emit (if Text (I) = ')' then T_RParen else T_RBrack);
               if Group_Depth > 0 then
                  Group_Depth := Group_Depth - 1;
               end if;
               I := I + 1;  Col := Col + 1;
            when '<' =>
               --  `<...>` names a rule, and may have spaces, as a section
               --  does in literate programming: `<table reference>` is the
               --  rule `table-reference`, and `<pchar>` is `pchar`.  At the
               --  start of a line it is a rule's name; anywhere else it is a
               --  reference, which Finish resolves, or reports as a rule that
               --  is not written yet (what ABNF calls a prose-val: words
               --  for a rule).  It ends at the `>` on the same line.
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
                       & ": a `<...>` rule name ends with `>` on the same "
                       & "line";
                  end if;
                  if At_Col = 1 then
                     declare
                        Id : constant String := Prose_Id (Text (Start .. I - 1));
                     begin
                        if Id = "" then
                           raise Parse_Error with
                             Integer'Image (Line) & ": 1: `<>` names no rule";
                        end if;
                        if not Bnf_Spellings.Contains (Id) then
                           Bnf_Spellings.Insert
                             (Id, Text (Start - 1 .. I));
                        end if;
                        Emit (T_Name, Id, At_Col);
                     end;
                  else
                     Emit (T_Prose, Text (Start .. I - 1), At_Col);
                  end if;
                  I := I + 1;  Col := Col + 1;
               end;
            when '*' =>
               if Ebnf_Here and then not Toks.Is_Empty
                 and then Toks.Last_Element.Kind = T_Number
               then
                  --  ISO 14977's `n * x` is exactly n, which is `nx` here.
                  I := I + 1;  Col := Col + 1;
               elsif I > Text'First and then Text (I - 1) in ' ' | ASCII.HT
                 and then not Toks.Is_Empty
                 and then Toks.Last_Element.Kind = T_Number
                 and then Toks.Last_Element.Line = Line
               then
                  raise Parse_Error with
                    Integer'Image (Line) & ":" & Integer'Image (Col)
                    & ": `" & To_String (Toks.Last_Element.Text) & " * x` is "
                    & "EBNF's way of writing exactly "
                    & To_String (Toks.Last_Element.Text) & ", which neither "
                    & "ABNF nor hbnf spells that way" & ASCII.LF
                    & "  Write `" & To_String (Toks.Last_Element.Text)
                    & "x` for exactly " & To_String (Toks.Last_Element.Text)
                    & " (`" & To_String (Toks.Last_Element.Text)
                    & "*x` is that many or more), or read the file as EBNF: "
                    & "a line `ebnf` in it, or `--ebnf`";
               else
                  Emit (T_Star);   I := I + 1;  Col := Col + 1;
               end if;
            when '-' => Emit (T_Dash);   I := I + 1;  Col := Col + 1;
            when '~' => Emit (T_Tilde);  I := I + 1;  Col := Col + 1;
            when '#' =>
               --  `n#m x`: x, comma, x ... (decision 12).
               Emit (T_Hash);  I := I + 1;  Col := Col + 1;
            when '!' =>
               --  `!x`: x must not match here (nothing is consumed).
               Emit (T_Pct, "not");  I := I + 1;  Col := Col + 1;
            when '&' =>
               --  `&x`: x must match here (nothing is consumed).
               Emit (T_Pct, "and");  I := I + 1;  Col := Col + 1;
            when ''' =>
               if Ebnf_Here then
                  --  ISO 14977: 'abc' is a string, as "abc" is.
                  declare
                     At_Col : constant Positive := Col;
                     Start  : constant Positive := I + 1;
                  begin
                     I := I + 1;  Col := Col + 1;
                     while I <= Text'Last and then Text (I) not in ''' | ASCII.LF
                     loop
                        I := I + 1;  Col := Col + 1;
                     end loop;
                     if I > Text'Last or else Text (I) /= ''' then
                        raise Parse_Error with
                          Integer'Image (Line) & ":" & Integer'Image (At_Col)
                          & ": this string does not end on its line";
                     end if;
                     Emit (T_String, Text (Start .. I - 1), At_Col);
                     I := I + 1;  Col := Col + 1;
                  end;
               else
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
               end if;
            when '{' =>
               if Ebnf_Here
                 and then not (not Toks.Is_Empty
                               and then Toks.Last_Element.Kind = T_Pct)
               then
                  --  ISO 14977: `{ x }` repeats x, zero or more times.
                  Emit (T_Star);  Emit (T_LParen);
                  I := I + 1;  Col := Col + 1;
               else
                  --  A raw code block (preamble, jet, or epilogue): capture the
                  --  text between matching braces.  Braces nest, and a `"` string
                  --  literal is copied verbatim so a `}` inside one is not taken
                  --  as the block's close.
                  declare
                     Depth : Natural := 1;
                     Buf   : Unbounded_String := Null_Unbounded_String;

                     --  `<name> = Rust { ... }`: the block is that language's,
                     --  whatever the file's `language` is.
                     Block_Lang : Lang_Kind := Lang;
                  begin
                     if Natural (Toks.Length) >= 2
                       and then Toks.Last_Element.Kind = T_Name
                       and then Toks (Toks.Last_Index - 1).Kind = T_Eq
                     then
                        declare
                           Tag : constant String :=
                             Ada.Characters.Handling.To_Lower
                               (To_String (Toks.Last_Element.Text));
                        begin
                           if Tag = "c" then Block_Lang := C_Lang;
                           elsif Tag = "rust" then Block_Lang := Rust_Lang;
                           elsif Tag = "zig" then Block_Lang := Zig_Lang;
                           elsif Tag = "ada" then Block_Lang := Ada_Lang;
                           end if;
                        end;
                     end if;
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
                              if Block_Lang = Ada_Lang and then I > Text'First
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
                              if (Block_Lang = C_Lang or else Block_Lang = Rust_Lang)
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
                              elsif Block_Lang /= Ada_Lang
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
                              if Block_Lang = Ada_Lang and then I < Text'Last
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
               end if;
            when '}' =>
               if Ebnf_Here then
                  Emit (T_RParen);  I := I + 1;  Col := Col + 1;
               else
                  raise Parse_Error with
                    Integer'Image (Line) & ":" & Integer'Image (Col) &
                    ": unexpected character '}'" & Character_Hint ('}');
               end if;
            when ',' =>
               if Ebnf_Here then
                  I := I + 1;  Col := Col + 1;   --  concatenation
               else
                  raise Parse_Error with
                    Integer'Image (Line) & ":" & Integer'Image (Col) &
                    ": unexpected character ','" & Character_Hint (',');
               end if;
            when '?' =>
               if not Ebnf_Here and then I < Text'Last
                 and then Text (I + 1) = '('
               then
                  --  `?(cond)`: a condition on what has been read.
                  I := I + 1;  Col := Col + 1;
                  Take_Raw (T_Guard);
               elsif Ebnf_Here then
                  --  ISO 14977's special sequence `? words ?`: a rule
                  --  described in words, so a rule not written yet.
                  declare
                     At_Col : constant Positive := Col;
                     Start  : constant Positive := I + 1;
                  begin
                     I := I + 1;  Col := Col + 1;
                     while I <= Text'Last and then Text (I) not in '?' | ASCII.LF
                     loop
                        I := I + 1;  Col := Col + 1;
                     end loop;
                     if I > Text'Last or else Text (I) /= '?' then
                        raise Parse_Error with
                          Integer'Image (Line) & ":" & Integer'Image (At_Col)
                          & ": a special sequence `? ... ?` ends with `?` on "
                          & "the same line";
                     end if;
                     Emit (T_Prose, Text (Start .. I - 1), At_Col);
                     I := I + 1;  Col := Col + 1;
                  end;
               elsif I < Text'Last
                 and then Text (I + 1) in ' ' | ASCII.HT
                 and then (for some K in I + 1 .. Text'Last =>
                             (for all J in I + 1 .. K - 1 =>
                                Text (J) in ' ' | ASCII.HT)
                             and then Text (K) in 'a' .. 'z' | 'A' .. 'Z')
               then
                  --  `identifier ? types`: the text just matched is in a
                  --  context (RFCPLAN.md decision 13).
                  Emit (T_Pct, "test");
                  I := I + 1;  Col := Col + 1;
               elsif I + 2 <= Text'Last and then Text (I + 1) = '!'
                 and then Text (I + 2) in ' ' | ASCII.HT
               then
                  --  `identifier ?! types`: the text just matched is not in it.
                  Emit (T_Pct, "nottest");
                  I := I + 2;  Col := Col + 2;
               else
                  raise Parse_Error with
                    Integer'Image (Line) & ":" & Integer'Image (Col) &
                    ": unexpected character '?'" & Character_Hint ('?');
               end if;
            when '0' .. '9' =>
               declare
                  Start : constant Positive := I;
               begin
                  if Text (I) = '0' and then I + 2 <= Text'Last
                    and then Text (I + 1) in 'x' | 'X'
                    and then Hex_Digit (Text (I + 2)) >= 0
                  then
                     --  0x86DD: an enum value (`"ipv6"@0x86DD`), or a constant
                     --  of the bit layer, as wide as its digits.
                     I := I + 2;
                     while I <= Text'Last and then Hex_Digit (Text (I)) >= 0
                     loop
                        I := I + 1;
                     end loop;
                  elsif Text (I) = '0' and then I + 2 <= Text'Last
                    and then Text (I + 1) in 'o' | 'O'
                    and then Text (I + 2) in '0' .. '7'
                  then
                     --  0o17: octal, three bits to a digit in the bit layer.
                     I := I + 2;
                     while I <= Text'Last and then Text (I) in '0' .. '7' loop
                        I := I + 1;
                     end loop;
                  elsif Text (I) = '0' and then I + 2 <= Text'Last
                    and then Text (I + 1) in 'b' | 'B'
                    and then Text (I + 2) in '0' | '1'
                  then
                     --  0b101: a constant of the bit layer, a bit to a digit.
                     I := I + 2;
                     while I <= Text'Last and then Text (I) in '0' | '1' loop
                        I := I + 1;
                     end loop;
                  else
                     while I <= Text'Last and then Text (I) in '0' .. '9' loop
                        I := I + 1;
                     end loop;
                  end if;
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
                     --  `name(args)` with the parenthesis against the name is a
                     --  parameterised rule's head or a use of one: the whole
                     --  call is one name, read by Expand_Params.
                     if I <= Text'Last and then Text (I) = '('
                       and then Text (Start .. I - 1) not in "bitsof" | "bits"
                       and then not (not Toks.Is_Empty
                                     and then Toks.Last_Element.Kind = T_Colon)
                     then
                        declare
                           Depth : Natural := 0;
                           In_Q  : Boolean := False;
                        begin
                           while I <= Text'Last loop
                              if Text (I) = ASCII.LF then
                                 raise Parse_Error with
                                   Integer'Image (Line) & ":" & Integer'Image (Col)
                                   & ": `" & Text (Start .. I - 1) & "`: the "
                                   & "arguments of a parameterised rule end with "
                                   & "`)` on the same line";
                              end if;
                              if Text (I) = '"' then
                                 In_Q := not In_Q;
                              elsif not In_Q then
                                 if Text (I) = '(' then
                                    Depth := Depth + 1;
                                 elsif Text (I) = ')' then
                                    Depth := Depth - 1;
                                    if Depth = 0 then
                                       I := I + 1;
                                       exit;
                                    end if;
                                 end if;
                              end if;
                              I := I + 1;
                           end loop;
                           if Depth /= 0 then
                              raise Parse_Error with
                                Integer'Image (Line) & ":" & Integer'Image (Col)
                                & ": `" & Text (Start .. Text'Last)
                                & "`: the arguments of a parameterised rule "
                                & "end with `)`";
                           end if;
                        end;
                     end if;
                     Emit (T_Name, Text (Start .. I - 1));
                     Col := Col + (I - Start);
                  end;
               else
                  raise Parse_Error with
                    Integer'Image (Line) & ":" & Integer'Image (Col) &
                    ": unexpected character '" & Text (I) & "'"
                    & Character_Hint (Text (I));
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
      N : constant String := "layout_ops " & Op;
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
         raise Parse_Error with "layout_ops: unknown operation `" & Op & "`";
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

   --  True when a literal has a letter, so that case could tell two spellings
   --  of it apart.  `"1"` is `"1"` whatever the file's `sensitivity`, and a
   --  literal that is no different either way is a plain one, which also lets
   --  a rule made of such literals be a character rule.
   function Has_Letter (S : Unbounded_String) return Boolean is
     (for some C of To_String (S) => C in 'a' .. 'z' | 'A' .. 'Z');

   --  How many ASCII letters a literal has: a case-insensitive one is that many
   --  more branches in a scanner (each letter in both cases), so a long one
   --  stays a phrase rule.
   function Letter_Count (S : Unbounded_String) return Natural is
      N : Natural := 0;
   begin
      for C of To_String (S) loop
         if C in 'a' .. 'z' | 'A' .. 'Z' then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Letter_Count;

   --  A field of the bit layer, after its name: `ttl:8`, `version@0:4`,
   --  `options:[ihl*4 - 20]`, `payload:*u8`, `src:addr`, `body:(n)*rec`,
   --  `payload:( ?(t == 6) tcp | rest:*u8 )`.  The name token was read; the
   --  caller has seen that a `:` or a `@` is glued to it.
   function Parse_Field (P : in out Parser; Name_Tok : Token)
     return Element_Access
   is
      F : constant Element_Access :=
        new Element'(Kind => Bit_Field, Min => 1, Max => 1,
                     F_Name => Name_Tok.Text, F_Line => Name_Tok.Line,
                     F_Col => Name_Tok.Col, others => <>);

      procedure Bad (T : Token; Msg : String) is
      begin
         raise Parse_Error with
           Integer'Image (T.Line) & ":" & Integer'Image (T.Col) & ": " & Msg;
      end Bad;

      --  A number is a number, in whatever form it is written (Number_Value).
      function Is_Plain_Decimal (T : Token) return Boolean is
        (T.Kind = T_Number);
   begin
      if Cur (P).Kind = T_At then
         Next (P);
         if not Is_Plain_Decimal (Cur (P)) then
            Bad (Cur (P), "expected the bit the field starts at after `@` "
                 & "(`" & To_String (Name_Tok.Text) & "@0:4`)");
         end if;
         F.F_At := Integer (Number_Value (To_String (Cur (P).Text)));
         Next (P);
         if Cur (P).Kind /= T_Colon then
            Bad (Cur (P), "`" & To_String (Name_Tok.Text) & "@"
                 & Integer'Image (F.F_At) & "` needs its width: `"
                 & To_String (Name_Tok.Text) & "@K:W`");
         end if;
      end if;
      Next (P);                                  --  the `:`
      declare
         T : constant Token := Cur (P);
      begin
         case T.Kind is
            when T_Number =>
               if not Is_Plain_Decimal (T) then
                  Bad (T, "a width is a decimal number of bits; "
                       & To_String (T.Text) & " is a constant (write it as an "
                       & "item of its own)");
               end if;
               Next (P);
               if Cur (P).Kind = T_Star then
                  --  `n*rule`, `n*m rule`
                  Next (P);
                  F.F_Min := Natural (Number_Value (To_String (T.Text)));
                  F.F_Max := -1;
                  if Is_Plain_Decimal (Cur (P)) then
                     F.F_Max := Integer (Number_Value (To_String (Cur (P).Text)));
                     Next (P);
                  end if;
                  if Cur (P).Kind /= T_Name then
                     Bad (Cur (P), "expected a rule name after `*`");
                  end if;
                  F.F_Kind := HBNF_Wire.S_Array;
                  F.F_Ref := Cur (P).Text;
                  Next (P);
                  if To_String (F.F_Ref) = "u8" then
                     Bad (T, "`*u8` is octets; a count of them is "
                          & "`name:[count]`");
                  end if;
               else
                  declare
                     W : constant Long_Long_Integer :=
                       Number_Value (To_String (T.Text));
                  begin
                     if W = 0 or else W > 64 then
                        Bad (T, "a field of" & Long_Long_Integer'Image (W)
                             & " bits: fields are 1 to 64 bits; for more, say "
                             & "how many octets with `name:["
                             & Integer'Image (Integer (W) / 8) & "]`");
                     end if;
                     F.F_Kind := HBNF_Wire.S_Bits;
                     F.F_Bits := Natural (W);
                  end;
                  if Cur (P).Kind = T_Name
                    and then Cur (P).Line = T.Line
                    and then Cur (P).Col = T.Col + Length (T.Text)
                  then
                     declare
                        M : constant String := To_String (Cur (P).Text);
                     begin
                        if not HBNF_Wire.Is_Modifier (M) then
                           Bad (Cur (P), "`" & M & "` after a width: the "
                                & "modifiers are `s` (signed), `le` and `be` "
                                & "(byte order, big the default), as in "
                                & "`ttl:8`, `delta:8s`, `port:16le`");
                        end if;
                        F.F_Signed := M (M'First) = 's';
                        F.F_Little := M'Length >= 2
                          and then M (M'Last - 1 .. M'Last) = "le";
                        Next (P);
                     end;
                  end if;
               end if;
            when T_Octets =>
               F.F_Kind := HBNF_Wire.S_Octets;
               F.F_Expr := T.Text;
               Next (P);
            when T_Bits =>
               F.F_Kind := HBNF_Wire.S_Bit_Expr;
               F.F_Expr := T.Text;
               Next (P);
            when T_Star =>
               Next (P);
               if Cur (P).Kind /= T_Name then
                  Bad (Cur (P), "expected a rule name after `*`");
               end if;
               F.F_Ref := Cur (P).Text;
               Next (P);
               if To_String (F.F_Ref) = "u8" then
                  F.F_Kind := HBNF_Wire.S_Rest;
               else
                  F.F_Kind := HBNF_Wire.S_Array;
                  F.F_Min := 0;
                  F.F_Max := -1;
               end if;
            when T_Count =>
               Next (P);
               if Cur (P).Kind /= T_Star then
                  Bad (Cur (P), "expected `*` and a rule after the count");
               end if;
               Next (P);
               if Cur (P).Kind /= T_Name then
                  Bad (Cur (P), "expected a rule name after `*`");
               end if;
               F.F_Kind := HBNF_Wire.S_Array;
               F.F_Expr := T.Text;
               F.F_Ref := Cur (P).Text;
               Next (P);
            when T_LParen =>
               Next (P);
               F.F_Kind := HBNF_Wire.S_Choice;
               F.F_Alts := Parse_Alternation (P);
               Expect (P, T_RParen, "')'");
            when T_Name =>
               declare
                  Is_Fixed : Boolean;
                  Bits     : Natural;
                  Sg, Lt   : Boolean;
               begin
                  HBNF_Wire.Fixed_Type (To_String (T.Text), Is_Fixed, Bits, Sg, Lt);
                  Next (P);
                  if To_String (T.Text) = "bitsof"
                    and then Cur (P).Kind = T_LParen
                  then
                     --  `name:bitsof(rule)`
                     Next (P);
                     if Cur (P).Kind /= T_Name then
                        Bad (Cur (P), "expected a text rule after `bitsof(`");
                     end if;
                     F.F_Kind := HBNF_Wire.S_Ref;
                     F.F_Ref := Cur (P).Text;
                     F.F_Bitsof := True;
                     Next (P);
                     Expect (P, T_RParen, "')'");
                  elsif Is_Fixed then
                     F.F_Kind := HBNF_Wire.S_Bits;
                     F.F_Bits := Bits;
                     F.F_Signed := Sg;
                     F.F_Little := Lt;
                  else
                     F.F_Kind := HBNF_Wire.S_Ref;
                     F.F_Ref := T.Text;
                  end if;
               end;
            when others =>
               Bad (T, "expected a width after `:`, found `"
                    & To_String (T.Text) & "`");
         end case;
      end;
      if Cur (P).Kind = T_At and then Cur (P).Line = Name_Tok.Line then
         Bad (Cur (P), "the place comes before the width: write `"
              & To_String (Name_Tok.Text) & "@K:W`, `@` the bit it starts at "
              & "and `:` how many bits");
      end if;
      return F;
   end Parse_Field;

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
                                   Lit => Lit, Has_Value => False, Value => 0,
                                   No_Case => File_No_Case
                                              and then Has_Letter (Lit));
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
                                         Lit => Lit, Has_Value => False,
                                         Value => 0,
                                         No_Case => W = "i" and then Has_Letter (Lit));
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
               T : constant Token := Cur (P);
               N : constant Unbounded_String := Expect_Name (P);
            begin
               --  `name:8`, `name@4:4`: a field of the bit layer.
               if Cur (P).Kind in T_Colon | T_At
                 and then Cur (P).Line = T.Line
                 and then Cur (P).Col = T.Col + Length (T.Text)
               then
                  return Parse_Field (P, T);
               end if;
               return new Element'
                 (Kind => Name, Min => 1, Max => 1, Name => N,
                  Fold => File_Fold_Names, Args => Null_Unbounded_String);
            end;
         when T_Guard =>
            --  `?(cond)` (with `"words"` after it for a check that has them):
            --  a condition on what has been read.
            declare
               T   : constant Token := Cur (P);
               Msg : Unbounded_String;
            begin
               Next (P);
               if Cur (P).Kind = T_String then
                  Msg := Cur (P).Text;
                  Next (P);
               end if;
               return new Element'
                 (Kind => Bit_Field, Min => 1, Max => 1,
                  F_Kind => HBNF_Wire.S_Assert, F_Expr => T.Text,
                  F_Message => Msg, F_Line => T.Line, F_Col => T.Col,
                  others => <>);
            end;
         when T_Prose =>
            --  `<...>` in a rule: a reference to the rule it names.  Plain
            --  words (`<table reference>`, `<pchar>`) are the name they
            --  spell, as a bare `pchar` is, so a rule may refer to itself and
            --  Finish finds what defines it.  Anything else (`<host, see
            --  [URI]>`) stands as a reference to "<n>", a name no rule can
            --  have, which Finish resolves against a rule of that spelling
            --  or reports.  Either way the position is kept for the message.
            declare
               T  : constant Token := Cur (P);
               Id : constant String := Prose_Id (To_String (T.Text));
            begin
               Next (P);
               if Id /= "" and then Plain_Words (To_String (T.Text)) then
                  declare
                     E : constant Element_Access := new Element'
                       (Kind => Name, Min => 1, Max => 1,
                        Name => To_Unbounded_String (Id), Fold => False, Args => Null_Unbounded_String);
                  begin
                     Prose_Sites.Append
                       (Here (T.Line, T.Col, To_String (T.Text), E));
                     if not Bnf_Spellings.Contains (Id) then
                        Bnf_Spellings.Insert (Id, "<" & To_String (T.Text) & ">");
                     end if;
                     return E;
                  end;
               end if;
               Prose_Sites.Append (Here (T.Line, T.Col, To_String (T.Text)));
               return new Element'
                 (Kind => Name, Min => 1, Max => 1,
                  Name => To_Unbounded_String
                            ("<" & Img (Natural (Prose_Sites.Length)) & ">"),
                  Fold => False, Args => Null_Unbounded_String);
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
                 ": expected a literal, name, or group"
                 & (if T.Kind = T_Number then
                      ASCII.LF & "  A bare number: Backus-Naur form writes a "
                      & "terminal bare, but hbnf writes it in quotes, `"""
                      & To_String (T.Text) & """`.  (A number in front of an "
                      & "element repeats it: `3DIGIT`.)"
                    else "");
            end;
      end case;
   end Parse_Atom;

   function Parse_Element (P : in out Parser) return Element_Access is
      Start      : constant Token := Cur (P);
      Min        : Natural := 1;
      Max        : Integer := 1;
      Has_Prefix : Boolean := False;
   begin
      --  A constant of the bit layer, as wide as its digits: 0x0800, 0b101.
      if Cur (P).Kind = T_Number and then Length (Cur (P).Text) > 2
        and then Ada.Strings.Unbounded.Element (Cur (P).Text, 1) = '0'
        and then Ada.Strings.Unbounded.Element (Cur (P).Text, 2) in 'x' | 'X' | 'b' | 'B' | 'o' | 'O'
      then
         declare
            T      : constant Token := Cur (P);
            S      : constant String := To_String (T.Text);
            Hexa   : constant Boolean := S (S'First + 1) in 'x' | 'X';
            Octal  : constant Boolean := S (S'First + 1) in 'o' | 'O';
            Dgs    : constant String := S (S'First + 2 .. S'Last);
            Bits   : constant Natural := Dgs'Length * (if Hexa then 4 elsif Octal then 3 else 1);
         begin
            Next (P);
            if Bits > 64 then
               raise Parse_Error with
                 Integer'Image (T.Line) & ":" & Integer'Image (T.Col)
                 & ": a constant of" & Natural'Image (Bits)
                 & " bits: constants are at most 64 bits";
            end if;
            return new Element'
              (Kind => Bit_Field, Min => 1, Max => 1,
               F_Kind => HBNF_Wire.S_Const, F_Bits => Bits,
               F_Value => Interfaces.Unsigned_64'Value
                            ((if Hexa then "16#" elsif Octal then "8#" else "2#") & Dgs & "#"),
               F_Line => T.Line, F_Col => T.Col, others => <>);
         end;
      end if;
      --  A comma list, `#x`, `n#x`, `n#m x`: x and then, each after a comma,
      --  more of it, in all at least n and at most m (decision 12).  It is
      --  `x *("," x)`, and a list that may be empty is `[ x *("," x) ]`.
      if Cur (P).Kind = T_Hash
        or else (Cur (P).Kind = T_Number
                 and then P.Toks (P.Pos + 1).Kind = T_Hash)
      then
         declare
            At_T  : constant Token := Cur (P);
            N     : Natural := 1;
            M     : Integer := -1;
            One   : Element_Access;
            Tail  : Element_Access;
            Outer : Element_Access;
         begin
            if Cur (P).Kind = T_Number then
               N := Natural (Number_Value (To_String (Cur (P).Text)));
               Next (P);
            end if;
            Next (P);                                   --  the #
            if Cur (P).Kind = T_Number
              and then P.Toks (P.Pos + 1).Kind in
                         T_Name | T_String | T_LParen | T_LBrack | T_Pct
                         | T_Char | T_Prose | T_Tilde
            then
               M := Integer (Number_Value (To_String (Cur (P).Text)));
               Next (P);
            end if;
            if M >= 0 and then M < N then
               raise Parse_Error with
                 Integer'Image (At_T.Line) & ":" & Integer'Image (At_T.Col)
                 & ": a list of at least" & Natural'Image (N) & " and at most"
                 & Integer'Image (M) & " elements";
            end if;
            One := Parse_Atom (P);
            if M = 1 then
               One.Min := N;  One.Max := 1;
               return One;
            end if;
            Tail := new Element'(Kind => Group, Min => (if N > 1 then N - 1 else 0),
                                 Max => (if M < 0 then -1 else M - 1),
                                 Items => Element_Vectors.Empty_Vector);
            Tail.Items.Append
              (new Element'(Kind => Literal, Min => 1, Max => 1,
                            Lit => To_Unbounded_String (","), No_Case => False,
                            Has_Value => False, Value => 0));
            Tail.Items.Append (new Element'(One.all));
            Outer := new Element'(Kind => Group, Min => (if N = 0 then 0 else 1),
                                  Max => 1,
                                  Items => Element_Vectors.Empty_Vector);
            Outer.Items.Append (One);
            Outer.Items.Append (Tail);
            return Outer;
         end;
      end if;
      --  ABNF prefix repetition:  *elem, 1*elem, n*melem, nelem.
      if Cur (P).Kind = T_Star then
         Min := 0;  Max := -1;  Has_Prefix := True;  Next (P);
         --  `*m`: at most m (`*2DIGIT`).
         if Cur (P).Kind = T_Number then
            Max := Integer (Number_Value (To_String (Cur (P).Text)));  Next (P);
         end if;
      elsif Cur (P).Kind = T_Number then
         Min := Natural (Number_Value (To_String (Cur (P).Text)));
         --  A number with nothing to repeat is a bare terminal, as Backus-Naur
         --  form writes `0`; hbnf writes it in quotes.
         if P.Toks (P.Pos + 1).Kind in T_Bar | T_Slash | T_Newline | T_EOF
           | T_RParen | T_RBrack | T_Comment | T_Code
         then
            raise Parse_Error with
              Integer'Image (Cur (P).Line) & ":" & Integer'Image (Cur (P).Col)
              & ": a bare number" & ASCII.LF
              & "  Backus-Naur form writes a terminal bare, `"
              & To_String (Cur (P).Text) & "`; hbnf writes it in quotes, `"""
              & To_String (Cur (P).Text) & """`.  (A number in front of an "
              & "element repeats it: `3DIGIT`.  In a rule of bit fields a "
              & "constant is as wide as its digits: 0x05, or 0b101.)";
         end if;
         Next (P);
         if Cur (P).Kind = T_Star then
            Next (P);
            if Cur (P).Kind = T_Number then
               Max := Integer (Number_Value (To_String (Cur (P).Text)));  Next (P);
            else
               Max := -1;
            end if;
         else
            Max := Min;
         end if;
         Has_Prefix := True;
      end if;

      declare
         E : Element_Access;
      begin
         if Cur (P).Kind = T_Tilde then
            --  `~x`, or `*~x`: one code point not in the set x matches.
            declare
               --  `~~x` is the class x again, written so it reads in order.
               function Negated return Element_Access is
                  N : Element_Access;
               begin
                  Next (P);
                  N := new Element'(Kind => Negation, Min => 1, Max => 1,
                                    Operand => Element_Vectors.Empty_Vector);
                  N.Operand.Append
                    (if Cur (P).Kind = T_Tilde then Negated
                     else Parse_Atom (P));
                  return N;
               end Negated;
            begin
               E := Negated;
            end;
         else
            E := Parse_Atom (P);
         end if;
         --  `"icmp"@1`: this literal's value as an enum constant.
         if E.Kind = Literal and then Cur (P).Kind = T_At
           and then P.Toks (P.Pos + 1).Kind = T_Number
         then
            declare
               T : constant String := To_String (P.Toks (P.Pos + 1).Text);
               V : Long_Long_Integer;
            begin
               V := Number_Value (T);
               if V > 2_147_483_647 then
                  raise Parse_Error with
                    Integer'Image (P.Toks (P.Pos + 1).Line) & ":"
                    & Integer'Image (P.Toks (P.Pos + 1).Col)
                    & ": " & T & " does not fit an enum constant (31 bits)";
               end if;
               E.Has_Value := True;
               E.Value := Natural (V);
               P.Pos := P.Pos + 2;
            end;
         end if;
         if Has_Prefix then
            E.Min := Min;  E.Max := Max;
         end if;
         if E.Min /= E.Max then
            Greedy_Sites.Append (Here (Start.Line, Start.Col, "", E));
         end if;
         return E;
      end;
   end Parse_Element;

   --  One of the context operations (RFCPLAN.md decision 13): `? types`,
   --  `%bind types += field.path` or `%bind { code }`, `%scope`,
   --  `%where { code }`.  They stay in the sequence where they are written.
   Backref_Seen : Boolean := False;
   function Uses_Backref return Boolean is (Backref_Seen);

   --  The frames of rules with parameters that are numbers worked out while
   --  parsing, by rule name.
   Frames_Seen : Boolean := False;
   package Frame_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (String, Frame_Info);
   Frame_Table : Frame_Maps.Map;

   function Uses_Frames return Boolean is
     (Frames_Seen or else not Frame_Table.Is_Empty);

   function Frame_Of (Rule_Name : String) return Frame_Info is
      C : constant Frame_Maps.Cursor := Frame_Table.Find (Rule_Name);
   begin
      return (if Frame_Maps.Has_Element (C) then Frame_Maps.Element (C)
              else (others => <>));
   end Frame_Of;

   procedure Set_Frame (Rule_Name : String; F : Frame_Info) is
   begin
      Frame_Table.Include (Rule_Name, F);
   end Set_Frame;

   Params_Mode_Now : Params_Mode := Auto;
   procedure Set_Params_Mode (Mode : Params_Mode) is
   begin
      Params_Mode_Now := Mode;
   end Set_Params_Mode;

   function Render_Guard
     (Text : String; Slot : Slot_Fn;
      And_Op, Or_Op, Not_Op, Eq_Op, Ge_Op, Le_Op : String) return String
   is
      Pos : Natural := Text'First;

      procedure Skip is
      begin
         while Pos <= Text'Last and then Text (Pos) = ' ' loop
            Pos := Pos + 1;
         end loop;
      end Skip;

      function Term return String is
      begin
         Skip;
         if Text (Pos) = '$' then
            declare
               Start : constant Positive := Pos + 1;
            begin
               Pos := Start;
               while Pos <= Text'Last and then Text (Pos) in '0' .. '9' loop
                  Pos := Pos + 1;
               end loop;
               return Slot (Natural'Value (Text (Start .. Pos - 1)));
            end;
         elsif Text (Pos) = '(' then
            declare
               Start : constant Positive := Pos + 1;
               Op    : Unbounded_String;
               Parts : Unbounded_String;
               Count : Natural := 0;
            begin
               Pos := Start;
               while Text (Pos) /= ' ' loop
                  Pos := Pos + 1;
               end loop;
               Op := To_Unbounded_String (Text (Start .. Pos - 1));
               loop
                  Skip;
                  exit when Text (Pos) = ')';
                  declare
                     T : constant String := Term;
                  begin
                     if Count > 0 then
                        Append (Parts, ASCII.NUL);
                     end if;
                     Append (Parts, T);
                     Count := Count + 1;
                  end;
               end loop;
               Pos := Pos + 1;
               declare
                  P : constant String := To_String (Parts);
                  Items : array (1 .. Count) of Unbounded_String;
                  K, B : Natural := 1;
                  Joiner : constant String :=
                    (if To_String (Op) = "and" then " " & And_Op & " "
                     elsif To_String (Op) = "or" then " " & Or_Op & " "
                     elsif To_String (Op) = "eq" then " " & Eq_Op & " "
                     elsif To_String (Op) = "ge" then " " & Ge_Op & " "
                     elsif To_String (Op) = "le" then " " & Le_Op & " "
                     else "");
                  R : Unbounded_String;
               begin
                  for I in P'Range loop
                     if P (I) = ASCII.NUL then
                        Items (K) := To_Unbounded_String (P (B .. I - 1));
                        K := K + 1;
                        B := I + 1;
                     end if;
                  end loop;
                  if Count > 0 then
                     Items (K) := To_Unbounded_String (P (B .. P'Last));
                  end if;
                  if To_String (Op) = "not" then
                     return "(" & Not_Op & To_String (Items (1)) & ")";
                  end if;
                  for I in 1 .. Count loop
                     if I > 1 then
                        Append (R, Joiner);
                     end if;
                     Append (R, Items (I));
                  end loop;
                  return "(" & To_String (R) & ")";
               end;
            end;
         else
            declare
               Start : constant Positive := Pos;
            begin
               while Pos <= Text'Last and then Text (Pos) not in ' ' | ')' loop
                  Pos := Pos + 1;
               end loop;
               return Text (Start .. Pos - 1);
            end;
         end if;
      end Term;
   begin
      return Term;
   end Render_Guard;

   function Slot_Of (Rule_Name, Var : String) return Integer is
      S     : constant String := To_String (Frame_Of (Rule_Name).Slots);
      Start : Positive := S'First;
      N     : Integer := 0;
   begin
      for I in S'First .. S'Last + 1 loop
         if I > S'Last or else S (I) = ' ' then
            if I > Start and then S (Start .. I - 1) = Var then
               return N;
            end if;
            if I > Start then
               N := N + 1;
            end if;
            Start := I + 1;
         end if;
      end loop;
      return -1;
   end Slot_Of;

   function Parse_Context_Op (P : in out Parser) return Element_Access is
      T : constant Token := Cur (P);
      W : constant String := To_String (T.Text);

      function Where return String is
        (Integer'Image (T.Line) & ":" & Integer'Image (T.Col) & ": ");

      procedure Declared (Name : Token) is
      begin
         if not (for some C of Context_Words => C = Name.Text)
           and then not Ctx_Pending.Contains (To_String (Name.Text))
         then
            --  not yet an error: a parameter of a hyperrule may stand here
            Ctx_Pending.Insert
              (To_String (Name.Text),
               Integer'Image (Name.Line) & ":" & Integer'Image (Name.Col));
         end if;
      end Declared;

      E : constant Element_Access :=
        new Element'(Kind => Block, Min => 1, Max => 1, Op => B_Scope,
                     Ctx => <>, Path => <>, Id => 0, Look => <>, Code => <>);
   begin
      Next (P);
      if W = "not" or else W = "and" then
         --  `!x`, `&x`: x is a literal, a token, or a group of those.
         declare
            A : constant Element_Access := Parse_Atom (P);
         begin
            E.Op := (if W = "not" then B_Not else B_And);
            if A.Kind = Group then
               E.Look := A.Items;
            else
               E.Look.Append (A);
            end if;
            for X of E.Look loop
               if not (X.Kind in Literal | Name | Alt)
                 or else (X.Kind in Literal | Name
                          and then (X.Min /= 1 or else X.Max /= 1))
               then
                  raise Parse_Error with
                    Where & "`" & (if W = "not" then "!" else "&")
                    & "` looks at a literal, a token or alternatives of "
                    & "those: `!"":""`, `&("";"" / ""}"")`";
               end if;
            end loop;
         end;
      elsif W = "as" or else W = "same" then
         --  `x %as tag` keeps the text x matched; `%same tag` is that text
         --  again.  The tag is local to the sequence they stand in.
         if Cur (P).Kind /= T_Name then
            raise Parse_Error with
              Where & "`%" & W & "` takes a tag: `name %as tag` ... `%same tag`";
         end if;
         E.Op := (if W = "as" then B_As else B_Same);
         E.Ctx := Cur (P).Text;
         Backref_Seen := True;
         Next (P);
      elsif W = "spaces" or else W = "col" or else W = "num" then
         --  `%spaces n`, `%spaces(k + 1)`: exactly that many spaces.
         --  `%col j`: j is the column the parser is at.
         --  `x %num j`: j is the decimal number the element before it matched.
         --  The numbers are the frame of the rule they stand in (a rule with a
         --  parameter `k in 0..`).
         if Cur (P).Kind not in T_Name | T_Number then
            raise Parse_Error with
              Where & "`%" & W & "` takes "
              & (if W = "spaces" then "a number: `%spaces k` or `%spaces(k + 1)`"
                 else "a name for the number: `%" & W & " j`");
         end if;
         E.Op := (if W = "spaces" then B_Spaces
                  elsif W = "col" then B_Col else B_Num);
         E.Ctx := Cur (P).Text;
         Frames_Seen := True;
         Next (P);
      elsif W = "scope" then
         E.Op := B_Scope;
      elsif W = "test" or else W = "nottest" then
         if Cur (P).Kind /= T_Name then
            raise Parse_Error with
              Where & "`?` takes the context to ask: `identifier ? types`";
         end if;
         Declared (Cur (P));
         E.Op := (if W = "test" then B_Test else B_Not_Test);
         E.Ctx := Cur (P).Text;
         Next (P);
      elsif W = "where" then
         if Cur (P).Kind /= T_Code then
            raise Parse_Error with
              Where & "`%where` takes code that decides: "
              & "`%where { return ok (text, len); }`";
         end if;
         E.Op := B_Where;
         E.Code := Cur (P).Text;
         Next (P);
      else
         if Cur (P).Kind = T_Code then
            E.Op := B_Bind_Code;
            E.Code := Cur (P).Text;
            Next (P);
         elsif Cur (P).Kind = T_Name
           and then P.Toks (P.Pos + 1).Kind = T_Name
         then
            Declared (Cur (P));
            E.Op := B_Bind;
            E.Ctx := Cur (P).Text;
            Next (P);
            E.Path := Cur (P).Text;
            Next (P);
         else
            raise Parse_Error with
              Where & "`%bind` adds a field to a context: "
              & "`%bind types += declarators.name`, or code: `%bind { ... }`";
         end if;
      end if;
      return E;
   end Parse_Context_Op;

   --  Parse a sequence of elements up to any structural token.  The caller
   --  inspects what stopped it.
   function Parse_Pattern (P : in out Parser) return Element_Vectors.Vector is
      V : Element_Vectors.Vector;

      --  True when the token at K ends this sequence (or ends the rule): the
      --  elements after it — if any — belong to something else.
      function Ends_Pattern (K : Positive) return Boolean is
        (P.Toks (K).Kind in
           T_Newline | T_RParen | T_RBrack | T_Bar | T_Slash | T_Comment
           | T_Code | T_EOF
         or else (P.Toks (K).Kind = T_Pct
                  and then To_String (P.Toks (K).Text)
                           in "scan" | "action" | "emit" | "label"));
      --  True when what follows the block at K, past line ends, closes the alternative: the
      --  next alternative (`|`, `/`), the end of a group or an option.  An `%emit` before one
      --  of these belongs to its alternative; the end of the rule is read by the rule.
      function Emit_Ends_Alternative (K : Positive) return Boolean is
         J : Positive := K;
      begin
         while P.Toks (J).Kind in T_Newline | T_Comment loop
            J := J + 1;
         end loop;
         return P.Toks (J).Kind in T_Bar | T_Slash | T_RParen | T_RBrack;
      end Emit_Ends_Alternative;
   begin
      loop
         --  A block *between* elements is lifted into a rule of its own (Lift
         --  names it `<owner>_<n>`), which is what gives a multi-alternative
         --  rule one block per alternative.  A block that ends the sequence
         --  stays the rule's own action, read by the caller.  `%scan` is
         --  never lifted: it takes the place of a pattern.
         if Cur (P).Kind = T_Pct
           and then To_String (Cur (P).Text) = "action"
           and then P.Toks (P.Pos + 1).Kind = T_Code
           and then not Ends_Pattern (P.Pos + 2)
         then
            Element_Vectors.Append
              (V, new Element'(Kind => Block, Min => 1, Max => 1,
                               Op => B_Action, Ctx => <>, Path => <>, Id => 0,
                               Look => <>,
                               Code => P.Toks (P.Pos + 1).Text));
            P.Pos := P.Pos + 2;
         elsif Cur (P).Kind = T_Pct
           and then To_String (Cur (P).Text) = "emit"
           and then P.Toks (P.Pos + 1).Kind = T_Code
           and then (not Ends_Pattern (P.Pos + 2) or else Emit_Ends_Alternative (P.Pos + 2))
         then
            Element_Vectors.Append
              (V, new Element'(Kind => Block, Min => 1, Max => 1,
                               Op => B_Emit, Ctx => <>, Path => <>, Id => 0,
                               Look => <>,
                               Code => P.Toks (P.Pos + 1).Text));
            P.Pos := P.Pos + 2;
         elsif Cur (P).Kind = T_Pct
           and then To_String (Cur (P).Text)
                    in "test" | "nottest" | "bind" | "scope" | "where" | "not" | "and"
                       | "as" | "same" | "spaces" | "col" | "num"
         then
            Element_Vectors.Append (V, Parse_Context_Op (P));
         elsif Cur (P).Kind = T_Code
           and then not Ends_Pattern (P.Pos + 1)
         then
            Element_Vectors.Append
              (V, new Element'(Kind => Block, Min => 1, Max => 1,
                               Op => B_Action, Ctx => <>, Path => <>, Id => 0,
                               Look => <>,
                               Code => Cur (P).Text));
            Next (P);
         else
            exit when Ends_Pattern (P.Pos);
            if Cur (P).Kind = T_Pct
              and then (for some C of To_String (Cur (P).Text) => C = '.')
            then
               --  `%d13.10` is two elements of this sequence.
               Append_All (V, Parse_Atom (P).Items);
            else
               Element_Vectors.Append (V, Parse_Element (P));
            end if;
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

      --  One alternative, and its `%label name` if it has one.
      function Branch return Element_Vectors.Vector is
         B : constant Element_Vectors.Vector := Parse_Pattern (P);
      begin
         if Cur (P).Kind = T_Pct and then To_String (Cur (P).Text) = "label"
         then
            declare
               T : constant Token := Cur (P);
            begin
               Next (P);
               if Cur (P).Kind /= T_Name then
                  raise Parse_Error with
                    Integer'Image (T.Line) & ":" & Integer'Image (T.Col)
                    & ": `%label` takes a name for the alternative: "
                    & "`... %label assign`";
               end if;
               if B.Is_Empty then
                  raise Parse_Error with
                    Integer'Image (T.Line) & ":" & Integer'Image (T.Col)
                    & ": `%label " & To_String (Cur (P).Text)
                    & "` labels an alternative, and this one is empty";
               end if;
               Set_Label (B.First_Element, To_String (Cur (P).Text));
               Next (P);
            end;
         end if;
         return B;
      end Branch;
   begin
      Append_All (V, Branch);
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
                           Guard => 0, Union => T.Kind = T_Slash);
         begin
            if A.Union then
               Union_Sites.Append (Here (T.Line, T.Col, "/", A));
            end if;
            Next (P);
            Element_Vectors.Append (V, A);
         end;
         Append_All (V, Branch);
      end loop;
      return V;
   end Parse_Alternation;

   --  The text of a file, for `%grammar`.
   function Read_Text (Path : String) return String is
      F   : Ada.Text_IO.File_Type;
      Buf : Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Append (Buf, Ada.Text_IO.Get_Line (F));
         Append (Buf, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (F);
      return To_String (Buf);
   end Read_Text;

   --  Where `%grammar "path"` finds its file: `~/x` in the home directory, an
   --  absolute path as it is, anything else beside the file that names it.
   function Grammar_Path (Given : String) return String is
      Cur : constant String := To_String (Current_File);
      Dir : Unbounded_String;
   begin
      if Given'Length >= 2 and then Given (Given'First .. Given'First + 1) = "~/"
      then
         return Ada.Environment_Variables.Value ("HOME", "")
           & Given (Given'First + 1 .. Given'Last);
      elsif Given'Length > 0 and then Given (Given'First) = '/' then
         return Given;
      end if;
      for K in reverse Cur'Range loop
         if Cur (K) = '/' then
            Dir := To_Unbounded_String (Cur (Cur'First .. K));
            exit;
         end if;
      end loop;
      return To_String (Dir) & Given;
   end Grammar_Path;

   --  What follows a rule's `=`: a pattern, or `%grammar "file"`, a pattern
   --  kept in a file of its own (a section of a literate grammar): the file
   --  holds the rule's body, as the rest of this line would.
   function Parse_Body (P : in out Parser) return Element_Vectors.Vector is
   begin
      --  `A - B`, the whole of a rule: A except what B matches (ISO 14977).
      if Cur (P).Kind = T_Name
        and then P.Toks (P.Pos + 1).Kind = T_Dash
        and then P.Toks (P.Pos + 2).Kind = T_Name
        and then P.Toks (P.Pos + 3).Kind in T_Newline | T_EOF | T_Comment
      then
         declare
            V : Element_Vectors.Vector;
         begin
            Pending_Except_A := Cur (P).Text;
            Pending_Except_B := P.Toks (P.Pos + 2).Text;
            V.Append
              (new Element'(Kind => Name, Min => 1, Max => 1,
                            Name => Cur (P).Text, Fold => File_Fold_Names, Args => Null_Unbounded_String));
            Next (P);
            Next (P);
            Next (P);
            return V;
         end;
      end if;
      if Cur (P).Kind = T_Pct and then To_String (Cur (P).Text) = "grammar" then
         if P.Toks (P.Pos + 1).Kind /= T_String then
            raise Parse_Error with
              Integer'Image (Cur (P).Line) & ":" & Integer'Image (Cur (P).Col)
              & ": %grammar takes the file the rule's body is in: "
              & "name = %grammar ""file.hbnf""";
         end if;
         declare
            Given : constant String := To_String (P.Toks (P.Pos + 1).Text);
            Path  : constant String := Grammar_Path (Given);
            Line  : constant Positive := Cur (P).Line;
         begin
            Next (P);
            Next (P);
            declare
               Sub : Parser := (Toks => Lex (Read_Text (Path)), Pos => 1);
               V   : constant Element_Vectors.Vector := Parse_Alternation (Sub);
            begin
               while Cur (Sub).Kind in T_Newline | T_Comment loop
                  Next (Sub);
               end loop;
               if Cur (Sub).Kind /= T_EOF then
                  raise Parse_Error with
                    Integer'Image (Line) & ": " & Path & ":"
                    & Integer'Image (Cur (Sub).Line) & ": the file is a "
                    & "rule's body (what follows `=`), and this is not part "
                    & "of one; a file of whole rules is `include`d";
               end if;
               return V;
            end;
         exception
            when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error =>
               raise Parse_Error with
                 Integer'Image (Line) & ": %grammar """ & Given
                 & """: no such file (looked for " & Path & ")";
         end;
      end if;
      return Parse_Alternation (P);
   end Parse_Body;

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
                  when Block   => A.Code = B.Code,
                  when Alt     => True,
                  when Negation => Same_Elements (A.Operand, B.Operand),
                  when Bit_Field => False));

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
                                   Guard => 0, Union => False));
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
               --  The alternative keeps its label when its first word goes.
               if Label_Of (Pattern (St)) /= ""
                 and then Label_Of (Pattern (St + 1)) = ""
               then
                  Set_Label (Pattern (St + 1), Label_Of (Pattern (St)));
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
                                       Guard => 0, Union => False));
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
   --  - a <prose-val> the parser would use stops generation;
   --  - in a rule that is not a character rule, a single code point (`','`,
   --    `%x2C`) becomes the one-character literal (`","`), which is how the
   --    backends match it until the character model (RFCPLAN.md step 4),
   --    and a range there is refused, since they would drop it.
   --  The checks look only at the rules the parser uses (Reachable), so a
   --  grammar can include an RFC's rules and replace the ones it needs.
   --  Parameterised rules (RFCPLAN.md; METACOMPILERS.md, "W-grammars").  A rule
   --  head with its parameters against the name,
   --
   --      list(X) = X *( "," X )
   --      binary(N in 1..17) = binary(N+1) *( op(N) binary(N+1) )
   --      binary(17) = unary
   --      op(1) = "||"      op(2) = "&&"
   --
   --  is a template; a use `list(expr)`, `binary(1)` is a name that stands for the
   --  rule made from the template by putting the arguments in.  Every distinct
   --  use becomes an ordinary rule when the grammar is read, so a backend never
   --  sees a parameter.  A parameter that is a number ranges over a domain
   --  (`N in 1..17`, or `K in "int" | "string"`), a use outside it is an error
   --  here and not a failed parse, and of the clauses of a name the one that
   --  gives constants for the arguments wins over the general one.  What a
   --  chain of uses may not do is grow: an instance that needs a bigger instance of
   --  itself has no end, and is refused with the chain.
   procedure Expand_Params (Rules : in out Rule_Vectors.Vector) is
      use Ada.Characters.Handling;

      subtype U is Unbounded_String;
      package Key_Name_Sets is new Ada.Containers.Indefinite_Ordered_Sets (String);
      package Natural_Vectors is new Ada.Containers.Vectors (Positive, Natural);
      type Long_Long_Integer_Array is array (Positive range <>) of Long_Long_Integer;

      type Value_Kind is (V_Int, V_Lit, V_Name);
      type Value is record
         Kind : Value_Kind := V_Name;
         Int  : Long_Long_Integer := 0;
         Text : U;
      end record;
      package Value_Vectors is new Ada.Containers.Vectors (Positive, Value);

      type Domain_Kind is (D_None, D_Range, D_Set);
      package Text_Vectors is new Ada.Containers.Vectors (Positive, U);
      type Interval is record
         Lo, Hi : Long_Long_Integer;
      end record;
      package Interval_Vectors is new Ada.Containers.Vectors (Positive, Interval);

      type Param is record
         Name   : U;
         Domain : Domain_Kind := D_None;
         Spans  : Interval_Vectors.Vector;     --  D_Range: the numbers
         Words  : Text_Vectors.Vector;         --  D_Set: the words
         Runtime  : Boolean := False;         --  `k in 0..`: a number worked out while parsing
         Is_Const : Boolean := False;         --  a clause for one value
         Const    : Value;
         Text     : U;                        --  as written, for messages
      end record;
      package Param_Vectors is new Ada.Containers.Vectors (Positive, Param);

      type Template is record
         Base   : U;
         Params : Param_Vectors.Vector;
         R      : Rule;
         Head   : U;                          --  as written
      end record;
      package Template_Vectors is new Ada.Containers.Vectors (Positive, Template);

      type Binding is record
         Name : U;
         Val  : Value;
      end record;
      package Binding_Vectors is new Ada.Containers.Vectors (Positive, Binding);

      Templates : Template_Vectors.Vector;
      Ordinary  : Rule_Vectors.Vector;
      Instances : Rule_Vectors.Vector;          --  the rules the uses make
      Made      : Index_Maps.Map;               --  instance name -> made
      Limit     : constant := 20_000;

      --  The chain of instances being made, for the message of a loop.
      type Frame is record
         Base : U;
         Name : U;
         Size : Natural;
      end record;
      package Frame_Vectors is new Ada.Containers.Vectors (Positive, Frame);
      Stack : Frame_Vectors.Vector;

      function Img (N : Long_Long_Integer) return String is
         T : constant String := Long_Long_Integer'Image (N);
      begin
         return (if T (T'First) = ' ' then T (T'First + 1 .. T'Last) else T);
      end Img;

      procedure Fail (Msg : String) is
      begin
         raise Parse_Error with Msg;
      end Fail;

      function Trim (S : String) return String is
         F : Natural := S'First;
         L : Natural := S'Last;
      begin
         while F <= L and then S (F) in ' ' | ASCII.HT loop
            F := F + 1;
         end loop;
         while L >= F and then S (L) in ' ' | ASCII.HT loop
            L := L - 1;
         end loop;
         return S (F .. L);
      end Trim;

      function Is_Call (S : String) return Boolean is
        (for some C of S => C = '(');

      --  The text before the first `(`, and the text between the outer ones.
      function Base_Of (S : String) return String is
      begin
         for I in S'Range loop
            if S (I) = '(' then
               return S (S'First .. I - 1);
            end if;
         end loop;
         return S;
      end Base_Of;

      function Args_Of (S : String) return String is
         F : Natural := 0;
      begin
         for I in S'Range loop
            if S (I) = '(' then
               F := I;
               exit;
            end if;
         end loop;
         if F = 0 or else S (S'Last) /= ')' then
            return "";
         end if;
         return S (F + 1 .. S'Last - 1);
      end Args_Of;

      --  Split on commas that are not inside parentheses or a string.
      function Split (S : String) return Text_Vectors.Vector is
         R     : Text_Vectors.Vector;
         Start : Natural := S'First;
         Depth : Natural := 0;
         In_Q  : Boolean := False;
      begin
         if Trim (S) = "" then
            return R;
         end if;
         for I in S'Range loop
            if S (I) = '"' then
               In_Q := not In_Q;
            elsif not In_Q then
               if S (I) = '(' then
                  Depth := Depth + 1;
               elsif S (I) = ')' then
                  Depth := Depth - 1;
               elsif S (I) = ',' and then Depth = 0 then
                  R.Append (To_Unbounded_String (Trim (S (Start .. I - 1))));
                  Start := I + 1;
               end if;
            end if;
         end loop;
         R.Append (To_Unbounded_String (Trim (S (Start .. S'Last))));
         return R;
      end Split;

      function Slug (S : String) return String is
         R : U;
      begin
         for C of S loop
            if C in 'a' .. 'z' | '0' .. '9' then
               Append (R, C);
            elsif C in 'A' .. 'Z' then
               Append (R, To_Lower (C));
            elsif C in '-' | '_' then
               Append (R, '_');
            else
               Append (R, "x" & Img (Long_Long_Integer (Character'Pos (C))));
            end if;
         end loop;
         return To_String (R);
      end Slug;

      function Text_Of (V : Value) return String is
        (case V.Kind is
            when V_Int  => Img (V.Int),
            when V_Lit  => """" & To_String (V.Text) & """",
            when V_Name => To_String (V.Text));

      function Part_Of (V : Value) return String is
        (case V.Kind is
            when V_Int  => (if V.Int < 0 then "m" & Img (-V.Int) else Img (V.Int)),
            when V_Lit  => Slug (To_String (V.Text)),
            when V_Name => To_String (V.Text));

      function Instance_Name (Base : String; Vals : Value_Vectors.Vector)
        return String
      is
         R : U := To_Unbounded_String (Base);
      begin
         for V of Vals loop
            Append (R, "-" & Part_Of (V));
         end loop;
         return To_String (R);
      end Instance_Name;

      --  As the author writes the use: binary(4), list(item, pair).
      function Call_Text (Base : String; Vals : Value_Vectors.Vector) return String is
         R : U := To_Unbounded_String (Base & "(");
         First : Boolean := True;
      begin
         for V of Vals loop
            if not First then
               Append (R, ", ");
            end if;
            First := False;
            Append (R, Text_Of (V));
         end loop;
         return To_String (R) & ")";
      end Call_Text;

      function Size_Of (Vals : Value_Vectors.Vector) return Natural is
         N : Natural := 0;
      begin
         for V of Vals loop
            if V.Kind /= V_Int then
               N := N + Length (V.Text);
            end if;
         end loop;
         return N;
      end Size_Of;

      ---------------------------------------------------------------------
      --  Heads
      ---------------------------------------------------------------------

      function In_Spans (P : Param; V : Long_Long_Integer) return Boolean is
        (for some S of P.Spans => V >= S.Lo and then V <= S.Hi);

      --  The domain of a parameter: numbers (`1..17`, `4`), words (`"int"`), or
      --  the name of a domain defined with `::=`, joined by `|`.
      procedure Read_Domain
        (D : String; P : in out Param; Head : String; Depth : Natural)
      is
         Start : Natural := D'First;
         In_Q  : Boolean := False;

         procedure Item (S : String) is
            W : constant String := Trim (S);
         begin
            if W = "" then
               Fail ("`" & Head & "`: the domain `" & D & "` has an empty "
                     & "alternative");
            elsif W (W'First) = '"' then
               if W'Length < 2 or else W (W'Last) /= '"' then
                  Fail ("`" & Head & "`: the word " & W & " has no closing `""`");
               end if;
               if P.Domain = D_Range then
                  Fail ("`" & Head & "`: the domain `" & D & "` mixes numbers "
                        & "and words");
               end if;
               P.Domain := D_Set;
               P.Words.Append (To_Unbounded_String (W (W'First + 1 .. W'Last - 1)));
            elsif W (W'First) in '0' .. '9' or else W (W'First) = '-' then
               declare
                  Dots : Natural := 0;
                  Lo, Hi : Long_Long_Integer;
               begin
                  for I in W'First .. W'Last - 1 loop
                     if W (I .. I + 1) = ".." then
                        Dots := I;
                        exit;
                     end if;
                  end loop;
                  if Dots > 0 and then Trim (W (Dots + 2 .. W'Last)) = "" then
                     --  `0..`: any number from 0 up, which no list of rules
                     --  can stand for: the parameter is a number the parser
                     --  works out as it reads.
                     Lo := Long_Long_Integer'Value (Trim (W (W'First .. Dots - 1)));
                     Hi := Long_Long_Integer'Last;
                     P.Runtime := True;
                  elsif Dots > 0 then
                     Lo := Long_Long_Integer'Value (Trim (W (W'First .. Dots - 1)));
                     Hi := Long_Long_Integer'Value (Trim (W (Dots + 2 .. W'Last)));
                  else
                     Lo := Long_Long_Integer'Value (W);
                     Hi := Lo;
                  end if;
                  if Lo > Hi then
                     Fail ("`" & Head & "`: the range `" & W & "` is empty");
                  end if;
                  if P.Domain = D_Set then
                     Fail ("`" & Head & "`: the domain `" & D & "` mixes "
                           & "numbers and words");
                  end if;
                  P.Domain := D_Range;
                  P.Spans.Append (Interval'(Lo, Hi));
               exception
                  when Constraint_Error =>
                     Fail ("`" & Head & "`: `" & W & "` is not a whole "
                           & "number or a range of them, `1..17`");
               end;
            else
               --  a domain by name
               if not Domain_Bodies.Contains (W) then
                  Fail ("`" & Head & "`: `" & W & "` is not a domain; define "
                        & "it with `" & W & " ::= 1..17`, or write the "
                        & "numbers `1..17` or the words `""a"" | ""b""` here");
               end if;
               if Depth >= 8 then
                  Fail ("`" & Head & "`: the domain `" & W & "` names itself, "
                        & "which would be an infinite set; hbnf expands only "
                        & "finite domains");
               end if;
               Domains_Used.Include (W, 1);
               Read_Domain (Domain_Bodies.Element (W), P, Head, Depth + 1);
            end if;
         end Item;
      begin
         for I in D'Range loop
            if D (I) = '"' then
               In_Q := not In_Q;
            elsif not In_Q and then D (I) in '|' | '/' then
               Item (D (Start .. I - 1));
               Start := I + 1;
            end if;
         end loop;
         Item (D (Start .. D'Last));
      end Read_Domain;

      function Parse_Param (Text : String; Head : String) return Param is
         P : Param;
         T : constant String := Trim (Text);
      begin
         P.Text := To_Unbounded_String (T);
         if T = "" then
            Fail ("`" & Head & "`: an empty parameter");
         elsif T (T'First) = '"' then
            P.Is_Const := True;
            P.Const := (V_Lit, 0, To_Unbounded_String (T (T'First + 1 .. T'Last - 1)));
         elsif T (T'First) in '0' .. '9' or else T (T'First) = '-' then
            P.Is_Const := True;
            begin
               P.Const := (V_Int, Long_Long_Integer'Value (T), Null_Unbounded_String);
            exception
               when Constraint_Error =>
                  Fail ("`" & Head & "`: `" & T & "` is not a number");
            end;
         else
            declare
               Sp : Natural := 0;
            begin
               for I in T'Range loop
                  if T (I) in ' ' | ASCII.HT then
                     Sp := I;
                     exit;
                  end if;
               end loop;
               if Sp = 0 then
                  P.Name := To_Unbounded_String (T);
               else
                  P.Name := To_Unbounded_String (T (T'First .. Sp - 1));
                  declare
                     Rest : constant String := Trim (T (Sp + 1 .. T'Last));
                  begin
                     if Rest'Length < 3 or else Rest (Rest'First .. Rest'First + 1) /= "in"
                     then
                        Fail ("`" & Head & "`: after the parameter `"
                              & To_String (P.Name) & "` write `in` and its domain, "
                              & "`" & To_String (P.Name) & " in 1..17` or `"
                              & To_String (P.Name) & " in ""a"" | ""b""`");
                     end if;
                     Read_Domain (Trim (Rest (Rest'First + 2 .. Rest'Last)), P,
                                  Head, 0);
                  end;
               end if;
            end;
         end if;
         return P;
      end Parse_Param;

      ---------------------------------------------------------------------
      --  Values
      ---------------------------------------------------------------------

      function Lookup
        (B : Binding_Vectors.Vector; Name : String; Found : out Boolean)
         return Value
      is
      begin
         for X of B loop
            if To_String (X.Name) = Name then
               Found := True;
               return X.Val;
            end if;
         end loop;
         Found := False;
         return (V_Name, 0, To_Unbounded_String (Name));
      end Lookup;

      procedure Make_Instance
        (Base : String; Vals : Value_Vectors.Vector; Name : out U;
         Via : String);

      --  An argument: a number (+ and - over numbers, parentheses), a quoted word,
      --  a rule name, or a use of a parameterised rule.
      function Eval
        (Text : String; B : Binding_Vectors.Vector; Where : String) return Value
      is
         S : constant String := Trim (Text);
         Pos : Natural := S'First;

         procedure Skip is
         begin
            while Pos <= S'Last and then S (Pos) in ' ' | ASCII.HT loop
               Pos := Pos + 1;
            end loop;
         end Skip;

         function Expr return Value;

         function Term return Value is
            R : Value;
         begin
            Skip;
            if Pos > S'Last then
               Fail (Where & ": the argument `" & S & "` ends too soon");
            elsif S (Pos) = '(' then
               Pos := Pos + 1;
               R := Expr;
               Skip;
               if Pos > S'Last or else S (Pos) /= ')' then
                  Fail (Where & ": the argument `" & S & "` has a `(` "
                        & "with no `)`");
               end if;
               Pos := Pos + 1;
               return R;
            elsif S (Pos) = '"' then
               declare
                  F : constant Natural := Pos + 1;
               begin
                  Pos := F;
                  while Pos <= S'Last and then S (Pos) /= '"' loop
                     Pos := Pos + 1;
                  end loop;
                  if Pos > S'Last then
                     Fail (Where & ": the word in `" & S & "` has no closing `""`");
                  end if;
                  Pos := Pos + 1;
                  return (V_Lit, 0, To_Unbounded_String (S (F .. Pos - 2)));
               end;
            elsif S (Pos) in '0' .. '9' then
               declare
                  F : constant Natural := Pos;
               begin
                  while Pos <= S'Last and then S (Pos) in '0' .. '9' loop
                     Pos := Pos + 1;
                  end loop;
                  return (V_Int, Long_Long_Integer'Value (S (F .. Pos - 1)),
                          Null_Unbounded_String);
               end;
            elsif S (Pos) in 'a' .. 'z' | 'A' .. 'Z' | '_' then
               declare
                  F : constant Natural := Pos;
                  Found : Boolean;
               begin
                  while Pos <= S'Last
                    and then (S (Pos) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
                              | '_' | '-' | '.')
                  loop
                     Pos := Pos + 1;
                  end loop;
                  if Pos <= S'Last and then S (Pos) = '(' then
                     --  a use of a parameterised rule inside the argument
                     declare
                        Depth : Natural := 0;
                        Start : constant Natural := F;
                     begin
                        while Pos <= S'Last loop
                           if S (Pos) = '(' then
                              Depth := Depth + 1;
                           elsif S (Pos) = ')' then
                              Depth := Depth - 1;
                              if Depth = 0 then
                                 Pos := Pos + 1;
                                 exit;
                              end if;
                           end if;
                           Pos := Pos + 1;
                        end loop;
                        declare
                           Call : constant String := S (Start .. Pos - 1);
                           Args : constant Text_Vectors.Vector := Split (Args_Of (Call));
                           Vals : Value_Vectors.Vector;
                           Nm   : U;
                        begin
                           for A of Args loop
                              Vals.Append (Eval (To_String (A), B, Where));
                           end loop;
                           Make_Instance (Base_Of (Call), Vals, Nm, Where);
                           return (V_Name, 0, Nm);
                        end;
                     end;
                  end if;
                  declare
                     V : constant Value := Lookup (B, S (F .. Pos - 1), Found);
                  begin
                     return V;
                  end;
               end;
            else
               Fail (Where & ": `" & S (Pos .. S'Last) & "` is not an argument "
                     & "(a number, a quoted word, or a rule)");
               return (V_Name, 0, Null_Unbounded_String);
            end if;
         end Term;

         function Expr return Value is
            L : Value := Term;
         begin
            loop
               Skip;
               exit when Pos > S'Last or else S (Pos) not in '+' | '-';
               declare
                  Op : constant Character := S (Pos);
                  R  : Value;
               begin
                  Pos := Pos + 1;
                  R := Term;
                  if L.Kind /= V_Int or else R.Kind /= V_Int then
                     Fail (Where & ": `" & S & "`: `" & Op & "` is between "
                           & "numbers, and `" & Text_Of (L) & "` or `"
                           & Text_Of (R) & "` is not one");
                  end if;
                  L.Int := (if Op = '+' then L.Int + R.Int else L.Int - R.Int);
               end;
            end loop;
            return L;
         end Expr;

         V : constant Value := Expr;
      begin
         Skip;
         if Pos <= S'Last then
            Fail (Where & ": `" & S (Pos .. S'Last) & "` follows the "
                  & "argument `" & S (S'First .. Pos - 1) & "` and is not "
                  & "part of it");
         end if;
         return V;
      end Eval;

      ---------------------------------------------------------------------
      --  Elements: copy, with the parameters put in and the uses made
      ---------------------------------------------------------------------

      function Subst
        (V : Element_Vectors.Vector; B : Binding_Vectors.Vector;
         In_Rule : String) return Element_Vectors.Vector;

      function Number_Use_Ok
        (Base : String; Vals : Long_Long_Integer_Array) return Boolean;
      function Number_Names_Of (Base : String) return String;

      --  An argument of a rule whose parameters are numbers worked out while
      --  parsing, with the names of this rule's own (compile-time) parameters
      --  replaced by their numbers.
      function Bound_Text (S : String; B : Binding_Vectors.Vector) return String is
         R : U;
         I : Natural := S'First;
      begin
         while I <= S'Last loop
            if S (I) in 'a' .. 'z' | 'A' .. 'Z' | '_' then
               declare
                  J     : Natural := I;
                  Found : Boolean;
               begin
                  while J <= S'Last
                    and then S (J) in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_'
                  loop
                     J := J + 1;
                  end loop;
                  declare
                     V : constant Value := Lookup (B, S (I .. J - 1), Found);
                  begin
                     if Found and then V.Kind = V_Int then
                        Append (R, Img (V.Int));
                     else
                        Append (R, S (I .. J - 1));
                     end if;
                  end;
                  I := J;
               end;
            else
               Append (R, S (I));
               I := I + 1;
            end if;
         end loop;
         return To_String (R);
      end Bound_Text;

      function Subst_One
        (E : Element_Access; B : Binding_Vectors.Vector; In_Rule : String)
         return Element_Access
      is
      begin
         case E.Kind is
            when Name =>
               declare
                  T : constant String := To_String (E.Name);
                  Found : Boolean;
               begin
                  if Is_Call (T) and then Frame_Table.Contains (Base_Of (T)) then
                     --  A rule whose parameters are numbers worked out while
                     --  parsing: it is not made in as many copies as there are
                     --  values; the use keeps its arguments for the parser.
                     declare
                        Base : constant String := Base_Of (T);
                        Args : constant Text_Vectors.Vector := Split (Args_Of (T));
                        X    : constant Element_Access := new Element'(E.all);
                        Text : U;
                     begin
                        if Natural (Args.Length) /= Frame_Of (Base).Arity then
                           Fail ("rule `" & In_Rule & "`: `" & T & "`: `" & Base
                                 & "` takes " & Img (Long_Long_Integer (Frame_Of (Base).Arity))
                                 & " argument(s), this gives "
                                 & Img (Long_Long_Integer (Args.Length)));
                        end if;
                        for A of Args loop
                           if Length (Text) > 0 then
                              Append (Text, ", ");
                           end if;
                           Append (Text, Bound_Text (To_String (A), B));
                        end loop;
                        --  numbers written out are checked against the clauses now
                        declare
                           Lits : Long_Long_Integer_Array (1 .. Natural (Args.Length));
                           All_Lit : Boolean := True;
                           K : Natural := 0;
                        begin
                           for A of Args loop
                              K := K + 1;
                              declare
                                 W : constant String := Trim (Bound_Text (To_String (A), B));
                              begin
                                 if W'Length > 0
                                   and then (for all C of W => C in '0' .. '9')
                                 then
                                    Lits (K) := Long_Long_Integer'Value (W);
                                 else
                                    All_Lit := False;
                                 end if;
                              end;
                           end loop;
                           if All_Lit and then not Number_Use_Ok (Base, Lits) then
                              Fail ("rule `" & In_Rule & "`, `" & T & "`: "
                                    & Img (Lits (1)) & " is outside the domain of "
                                    & Number_Names_Of (Base) & " in `" & Base
                                    & "`; no clause of it takes these numbers");
                           end if;
                        end;
                        X.Name := To_Unbounded_String (Base);
                        X.Args := Text;
                        return X;
                     end;
                  elsif Is_Call (T) then
                     declare
                        Args : constant Text_Vectors.Vector := Split (Args_Of (T));
                        Vals : Value_Vectors.Vector;
                        Nm   : U;
                        X    : constant Element_Access := new Element'(E.all);
                     begin
                        for A of Args loop
                           Vals.Append (Eval (To_String (A), B, "rule `" & In_Rule & "`, `" & T & "`"));
                        end loop;
                        Make_Instance (Base_Of (T), Vals, Nm, "rule `" & In_Rule & "`, `" & T & "`");
                        X.Name := Nm;
                        return X;
                     end;
                  end if;
                  declare
                     V : constant Value := Lookup (B, T, Found);
                  begin
                     if not Found then
                        return new Element'(E.all);
                     end if;
                     case V.Kind is
                        when V_Name =>
                           declare
                              X : constant Element_Access := new Element'(E.all);
                           begin
                              X.Name := V.Text;
                              return X;
                           end;
                        when V_Lit =>
                           return new Element'
                             (Kind => Literal, Min => E.Min, Max => E.Max,
                              Lit => V.Text, No_Case => False,
                              Has_Value => False, Value => 0);
                        when V_Int =>
                           Fail ("rule `" & In_Rule & "`: `" & T & "` is the "
                                 & "number " & Img (V.Int) & ", and a number "
                                 & "can be an argument (`op(" & T & ")`) but "
                                 & "not stand where a rule is");
                     end case;
                  end;
               end;
            when Group =>
               declare
                  X : constant Element_Access := new Element'(E.all);
               begin
                  X.Items := Subst (E.Items, B, In_Rule);
                  return X;
               end;
            when Negation =>
               declare
                  X : constant Element_Access := new Element'(E.all);
               begin
                  X.Operand := Subst (E.Operand, B, In_Rule);
                  return X;
               end;
            when Block =>
               declare
                  X : constant Element_Access := new Element'(E.all);
               begin
                  X.Look := Subst (E.Look, B, In_Rule);
                  if E.Op in B_Bind | B_Test | B_Not_Test then
                     --  a context named by a parameter: the value is its name
                     declare
                        Found : Boolean;
                        V     : constant Value := Lookup (B, To_String (E.Ctx), Found);
                     begin
                        if Found then
                           if V.Kind = V_Int then
                              Fail ("rule `" & In_Rule & "`: `" & To_String (E.Ctx)
                                    & "` is a number, and a context is a name");
                           end if;
                           X.Ctx := V.Text;
                        end if;
                     end;
                  end if;
                  return X;
               end;
            when others =>
               return new Element'(E.all);
         end case;
         return null;
      end Subst_One;

      function Subst
        (V : Element_Vectors.Vector; B : Binding_Vectors.Vector;
         In_Rule : String) return Element_Vectors.Vector
      is
         R : Element_Vectors.Vector;
      begin
         for E of V loop
            R.Append (Subst_One (E, B, In_Rule));
         end loop;
         return R;
      end Subst;

      ---------------------------------------------------------------------
      --  Instances
      ---------------------------------------------------------------------

      function Domain_Text (P : Param) return String is
         R : U;
      begin
         case P.Domain is
            when D_None =>
               return "any";
            when D_Set =>
               return "one of the words listed";
            when D_Range =>
               for S of P.Spans loop
                  if Length (R) > 0 then
                     Append (R, ", ");
                  end if;
                  Append (R, Img (S.Lo) & (if S.Hi = S.Lo then ""
                                           else " .. " & Img (S.Hi)));
               end loop;
               return To_String (R);
         end case;
      end Domain_Text;

      function Chain return String is
         R : U;
      begin
         for F of Stack loop
            Append (R, "`" & To_String (F.Name) & "` -> ");
         end loop;
         return To_String (R);
      end Chain;

      procedure Make_Instance
        (Base : String; Vals : Value_Vectors.Vector; Name : out U;
         Via : String)
      is
         Best      : Natural := 0;
         Best_Rank : Integer := -1;
         Arity     : Natural := 0;
         Any       : Boolean := False;
         Why       : U;
         N         : constant String := Instance_Name (Base, Vals);
         C         : constant String := Call_Text (Base, Vals);
      begin
         Name := To_Unbounded_String (N);
         if Hidden_Bases.Contains (Base) then
            Hidden_Rules.Include (N);
         end if;
         for I in 1 .. Natural (Templates.Length) loop
            declare
               T : constant Template := Templates (I);
            begin
               if To_String (T.Base) = Base then
                  Any := True;
                  Arity := Natural (T.Params.Length);
                  if Natural (T.Params.Length) /= Natural (Vals.Length) then
                     Fail (Via & ": `" & Base & "` takes "
                           & Img (Long_Long_Integer (T.Params.Length))
                           & " argument(s), `" & To_String (T.Head) & "`; this "
                           & "gives " & Img (Long_Long_Integer (Vals.Length))
                           & ": " & C);
                  end if;
               end if;
            end;
         end loop;
         if not Any then
            Fail (Via & ": no parameterised rule `" & Base & "` is "
                  & "defined; write `" & Base & "(X) = ...`");
         end if;
         if Made.Contains (N) then
            return;
         end if;
         --  the clause that matches, and of those the one with most constants
         for I in 1 .. Natural (Templates.Length) loop
            declare
               T  : constant Template := Templates (I);
               Ok : Boolean := To_String (T.Base) = Base;
               Rank : Integer := 0;
            begin
               if Ok then
                  for K in 1 .. Arity loop
                     declare
                        P : constant Param := T.Params (K);
                        V : constant Value := Vals (K);
                     begin
                        if P.Is_Const then
                           if V.Kind /= P.Const.Kind or else V.Int /= P.Const.Int
                             or else V.Text /= P.Const.Text
                           then
                              Ok := False;
                           else
                              Rank := Rank + 1;
                           end if;
                        elsif P.Domain = D_Range then
                           if V.Kind /= V_Int then
                              Ok := False;
                              Why := To_Unbounded_String
                                ("`" & Text_Of (V) & "` is not a number, and "
                                 & To_String (P.Name) & " in `"
                                 & To_String (T.Head) & "` is one");
                           elsif not In_Spans (P, V.Int) then
                              Ok := False;
                              Why := To_Unbounded_String
                                (Img (V.Int) & " is outside the domain of "
                                 & To_String (P.Name) & " in `"
                                 & To_String (T.Head) & "` (" & Domain_Text (P)
                                 & ")");
                           end if;
                        elsif P.Domain = D_Set then
                           if V.Kind /= V_Lit
                             or else not (for some W of P.Words => W = V.Text)
                           then
                              Ok := False;
                              Why := To_Unbounded_String
                                ("`" & Text_Of (V) & "` is not one of the words "
                                 & To_String (P.Name) & " in `"
                                 & To_String (T.Head) & "` allows");
                           end if;
                        end if;
                     end;
                  end loop;
                  if Ok and then Rank > Best_Rank then
                     Best := I;
                     Best_Rank := Rank;
                  end if;
               end if;
            end;
         end loop;
         if Best = 0 then
            Fail (Via & ": `" & C & "`: "
                  & (if Why /= Null_Unbounded_String then To_String (Why)
                     else "no clause of `" & Base & "` has these arguments")
                  & ".  " & Chain
                  & "A use of a parameterised rule must be in the domain of its "
                  & "parameters (or have a clause of its own for the value "
                  & "that is outside, one that does not use the next one)");
         end if;
         --  a chain of uses of the same rule must not grow
         for F of Stack loop
            if To_String (F.Base) = Base and then Size_Of (Vals) > F.Size then
               Fail (Via & ": `" & To_String (F.Name) & "` needs `" & C
                     & "`, which is `" & Base & "` with a bigger argument, and "
                     & "that needs a bigger one again: there is no finite set "
                     & "of instances.  " & Chain & "`" & C & "` ...  A "
                     & "parameterised rule may use itself only with an "
                     & "argument that comes from a finite set (a number in a "
                     & "domain, a word from a list, or the same rule)");
            end if;
         end loop;
         if Natural (Made.Length) >= Limit then
            Fail (Via & ": more than" & Integer'Image (Limit) & " instances "
                  & "of parameterised rules are needed; " & Chain & "`" & C & "`");
         end if;
         --  put the arguments in, and make the rule
         declare
            T : constant Template := Templates (Best);
            B : Binding_Vectors.Vector;
            R : Rule := T.R;
         begin
            for K in 1 .. Arity loop
               if not T.Params (K).Is_Const then
                  B.Append (Binding'(Name => T.Params (K).Name, Val => Vals (K)));
               end if;
            end loop;
            Made.Insert (N, 1);
            Stack.Append (Frame'(Base => To_Unbounded_String (Base),
                                 Name => To_Unbounded_String (N),
                                 Size => Size_Of (Vals)));
            R.Name := To_Unbounded_String (N);
            R.Pattern := Subst (T.R.Pattern, B, N);
            Instances.Append (R);
            Stack.Delete_Last;
         end;
      end Make_Instance;

      --  The values each rule made by Make_Number_Rule takes: for each clause, what
      --  each of its parameters must be (a constant, or spans; no spans for a
      --  parameter with no end), so a use with numbers written out is checked as
      --  the grammar is read.
      type Number_Test is record
         Is_Const : Boolean := False;
         Const    : Long_Long_Integer := 0;
         Open     : Boolean := True;        --  anything
         Spans    : Interval_Vectors.Vector;
      end record;
      package Test_Vectors is new Ada.Containers.Vectors (Positive, Number_Test);
      package Clause_Vectors is new Ada.Containers.Vectors
        (Positive, Test_Vectors.Vector, Test_Vectors."=");
      package Clause_Maps is new Ada.Containers.Indefinite_Ordered_Maps
        (String, Clause_Vectors.Vector, "<", Clause_Vectors."=");
      Number_Clauses : Clause_Maps.Map;
      package Name_Maps is new Ada.Containers.Indefinite_Ordered_Maps (String, String);
      Number_Names : Name_Maps.Map;      --  the slots of each, as written

      --  What a clause with one number parameter takes, and what it calls: kept
      --  until every such rule is known, then each call is checked against the
      --  clauses of what it calls.
      type Pending is record
         Param : U;
         Eff   : Interval_Vectors.Vector;     --  the numbers the clause is chosen for
         Text  : Element_Vectors.Vector;
         Base  : U;
      end record;
      package Pending_Vectors is new Ada.Containers.Vectors (Positive, Pending);
      Pendings : Pending_Vectors.Vector;

      function Test_Holds (T : Number_Test; V : Long_Long_Integer) return Boolean is
        (T.Open
         or else (if T.Is_Const then V = T.Const
                  else (for some S of T.Spans => V >= S.Lo and then V <= S.Hi)));

      procedure Make_Number_Rule
        (Base : String; Clauses : Template_Vectors.Vector)
      is
         A     : constant Natural := Natural (Clauses.First_Element.Params.Length);
         Names : array (1 .. A) of U;
         Order : Natural_Vectors.Vector;
         Rule0 : constant Rule := Clauses.First_Element.R;
         Pat   : Element_Vectors.Vector;
         Seen_Incs : Text_Vectors.Vector;
         Infos : Clause_Vectors.Vector;
         Slots : U;
         Rank  : array (1 .. Natural (Clauses.Length)) of Natural := [others => 0];
         Reached_All : Boolean := False;

         function Inc (T : Template) return String is
            Parts : Text_Vectors.Vector;
            R     : U;
         begin
            for K in 1 .. A loop
               declare
                  P : constant Param := T.Params (K);
                  Sl : constant String := "$" & Img (Long_Long_Integer (K - 1));
               begin
                  if P.Is_Const then
                     Parts.Append (To_Unbounded_String
                       ("(eq " & Sl & " " & Img (P.Const.Int) & ")"));
                  elsif P.Runtime then
                     null;     --  an open end: the number is not checked
                  else
                     declare
                        Any : U;
                        N   : Natural := 0;
                     begin
                        for Sp of P.Spans loop
                           N := N + 1;
                           Append (Any, (if N > 1 then " " else "")
                             & (if Sp.Hi = Long_Long_Integer'Last
                                then "(ge " & Sl & " " & Img (Sp.Lo) & ")"
                                else "(and (ge " & Sl & " " & Img (Sp.Lo)
                                     & ") (le " & Sl & " " & Img (Sp.Hi) & "))"));
                        end loop;
                        Parts.Append (To_Unbounded_String
                          (if N = 1 then To_String (Any) else "(or " & To_String (Any) & ")"));
                     end;
                  end if;
               end;
            end loop;
            if Parts.Is_Empty then
               return "";
            elsif Natural (Parts.Length) = 1 then
               return To_String (Parts.First_Element);
            end if;
            for X of Parts loop
               Append (R, " " & To_String (X));
            end loop;
            return "(and" & To_String (R) & ")";
         end Inc;

         function Info_Of (T : Template) return Test_Vectors.Vector is
            V : Test_Vectors.Vector;
         begin
            for P of T.Params loop
               declare
                  X : Number_Test;
               begin
                  if P.Is_Const then
                     X := (Is_Const => True, Const => P.Const.Int, Open => False, Spans => <>);
                  elsif P.Runtime then
                     X := (Is_Const => False, Const => 0, Open => True, Spans => <>);
                  else
                     X := (Is_Const => False, Const => 0, Open => False, Spans => P.Spans);
                  end if;
                  V.Append (X);
               end;
            end loop;
            return V;
         end Info_Of;
      begin
         --  the same name for the same place in every general clause
         for K in 1 .. A loop
            for T of Clauses loop
               if not T.Params (K).Is_Const then
                  if Names (K) = Null_Unbounded_String then
                     Names (K) := T.Params (K).Name;
                  elsif Names (K) /= T.Params (K).Name then
                     Fail ("`" & To_String (T.Head) & "`: the clauses of `" & Base
                           & "` name the parameter `" & To_String (Names (K))
                           & "` and `" & To_String (T.Params (K).Name)
                           & "`; give it one name");
                  end if;
               end if;
            end loop;
            if Names (K) = Null_Unbounded_String then
               Names (K) := To_Unbounded_String ("p" & Img (Long_Long_Integer (K)));
            end if;
            if K > 1 then
               Append (Slots, " ");
            end if;
            Append (Slots, Names (K));
         end loop;
         --  the clause with the most constants first; of equal ones, the first written
         for I in 1 .. Natural (Clauses.Length) loop
            for P of Clauses (I).Params loop
               if P.Is_Const then
                  Rank (I) := Rank (I) + 1;
               end if;
            end loop;
         end loop;
         for R_Level in reverse 0 .. A loop
            for I in 1 .. Natural (Clauses.Length) loop
               if Rank (I) = R_Level then
                  Order.Append (I);
               end if;
            end loop;
         end loop;
         for Idx of Order loop
            declare
               T    : constant Template := Clauses (Idx);
               Mine : constant String := Inc (T);
               Not_Earlier : U;
               Guard : U;
            begin
               if not Reached_All then
                  --  not what a clause before it takes
                  for E of Seen_Incs loop
                     Append (Not_Earlier, " " & To_String (E));
                  end loop;
                  if Length (Not_Earlier) > 0 then
                     Guard := To_Unbounded_String
                       (if Mine = ""
                        then "(not (or" & To_String (Not_Earlier) & "))"
                        else "(and " & Mine & " (not (or" & To_String (Not_Earlier) & ")))");
                  else
                     Guard := To_Unbounded_String (Mine);
                  end if;
                  if Mine = "" then
                     Reached_All := True;   --  takes everything the rest would
                  else
                     Seen_Incs.Append (To_Unbounded_String (Mine));
                  end if;
                  Infos.Append (Info_Of (T));
                  if not Pat.Is_Empty then
                     Pat.Append (new Element'(Kind => Alt, Min => 1, Max => 1,
                                              Guard => 0, Union => False));
                  end if;
                  if Guard = Null_Unbounded_String then
                     for E of T.R.Pattern loop
                        Pat.Append (E);
                     end loop;
                  else
                     Pat.Append (new Element'(Kind => Block, Min => 1, Max => 1,
                                              Op => B_Guard, Ctx => Guard,
                                              Path => <>, Id => 0, Look => <>,
                                              Code => <>));
                     Pat.Append (new Element'(Kind => Group, Min => 1, Max => 1,
                                              Items => T.R.Pattern));
                  end if;
               end if;
            end;
         end loop;
         declare
            X : Rule := Rule0;
         begin
            X.Name := To_Unbounded_String (Base);
            X.Pattern := Pat;
            Ordinary.Append (X);
         end;
         Frame_Table.Include
           (Base, (Slots => Slots, Arity => A, Shares => False));
         Number_Clauses.Include (Base, Infos);
         Number_Names.Include (Base, To_String (Slots));
         --  with one parameter: the numbers each clause is chosen for
         if A = 1 then
            declare
               Taken : Interval_Vectors.Vector;     --  by clauses before it
            begin
               for Idx of Order loop
                  declare
                     T    : constant Template := Clauses (Idx);
                     P    : constant Param := T.Params (1);
                     Eff  : Interval_Vectors.Vector;
                  begin
                     if P.Is_Const then
                        Taken.Append (Interval'(P.Const.Int, P.Const.Int));
                        Eff.Append (Interval'(P.Const.Int, P.Const.Int));
                     elsif not P.Runtime then
                        for Sp of P.Spans loop
                           --  the span without the points before-hand clauses took
                           declare
                              Cur : Interval_Vectors.Vector;
                           begin
                              Cur.Append (Sp);
                              for Tk of Taken loop
                                 declare
                                    Next : Interval_Vectors.Vector;
                                 begin
                                    for C of Cur loop
                                       if Tk.Hi < C.Lo or else Tk.Lo > C.Hi then
                                          Next.Append (C);
                                       else
                                          if Tk.Lo > C.Lo then
                                             Next.Append (Interval'(C.Lo, Tk.Lo - 1));
                                          end if;
                                          if Tk.Hi < C.Hi then
                                             Next.Append (Interval'(Tk.Hi + 1, C.Hi));
                                          end if;
                                       end if;
                                    end loop;
                                    Cur := Next;
                                 end;
                              end loop;
                              for C of Cur loop
                                 Eff.Append (C);
                              end loop;
                           end;
                        end loop;
                        for Sp of P.Spans loop
                           Taken.Append (Sp);
                        end loop;
                     end if;
                     if not P.Runtime then
                        Pendings.Append
                          (Pending'(Param => P.Name, Eff => Eff,
                                    Text => T.R.Pattern,
                                    Base => To_Unbounded_String (Base)));
                     end if;
                  end;
               end loop;
            end;
         end if;
      end Make_Number_Rule;

      function Number_Names_Of (Base : String) return String is
        (if Number_Names.Contains (Base) then Number_Names.Element (Base) else "");

      --  Is a use of Base with these numbers written out in some clause?
      function Number_Use_Ok
        (Base : String; Vals : Long_Long_Integer_Array) return Boolean is
      begin
         if not Number_Clauses.Contains (Base) then
            return True;
         end if;
         for Cl of Number_Clauses.Element (Base) loop
            if (for all K in Vals'Range => Test_Holds (Cl (K), Vals (K))) then
               return True;
            end if;
         end loop;
         return False;
      end Number_Use_Ok;
      --  Does every number a clause can pass on lie in the clauses of the rule it
      --  calls?  Of a use like `binary(n + 1)` in a clause chosen for n in 1 .. 3.
      procedure Check_Number_Calls is
         procedure Walk (Pn : Pending; V : Element_Vectors.Vector) is
         begin
            for E of V loop
               if E.Kind = Group then
                  Walk (Pn, E.Items);
               elsif E.Kind = Name and then Is_Call (To_String (E.Name)) then
                  declare
                     T    : constant String := To_String (E.Name);
                     Callee : constant String := Base_Of (T);
                     Arg  : constant String := Trim (Args_Of (T));
                     Param : constant String := To_String (Pn.Param);
                     Delta_V : Long_Long_Integer := 0;
                     Lit   : Boolean := False;
                     Ok    : Boolean := True;
                     P     : Natural := Arg'First;
                  begin
                     if Number_Clauses.Contains (Callee)
                       and then Natural (Number_Clauses.Element (Callee).First_Element.Length) = 1
                       and then Natural (Split (Args_Of (T)).Length) = 1
                     then
                        --  the argument: a number, the parameter, or the parameter
                        --  plus or minus a number
                        if Arg'Length > 0 and then (for all C of Arg => C in '0' .. '9') then
                           Lit := True;
                           Delta_V := Long_Long_Integer'Value (Arg);
                        elsif Arg'Length >= Param'Length
                          and then Arg (Arg'First .. Arg'First + Param'Length - 1) = Param
                        then
                           P := Arg'First + Param'Length;
                           while P <= Arg'Last and then Arg (P) = ' ' loop
                              P := P + 1;
                           end loop;
                           if P > Arg'Last then
                              Delta_V := 0;
                           elsif Arg (P) in '+' | '-' then
                              declare
                                 Sign : constant Long_Long_Integer :=
                                   (if Arg (P) = '+' then 1 else -1);
                                 Q : Natural := P + 1;
                              begin
                                 while Q <= Arg'Last and then Arg (Q) = ' ' loop
                                    Q := Q + 1;
                                 end loop;
                                 if Q <= Arg'Last and then (for all C of Arg (Q .. Arg'Last) => C in '0' .. '9') then
                                    Delta_V := Sign * Long_Long_Integer'Value (Arg (Q .. Arg'Last));
                                 else
                                    Ok := False;       --  another form: not looked at
                                 end if;
                              end;
                           else
                              Ok := False;
                           end if;
                        else
                           Ok := False;
                        end if;
                        if Ok then
                           declare
                              Callee_Clauses : constant Clause_Vectors.Vector :=
                                Number_Clauses.Element (Callee);
                              Open_Callee : constant Boolean :=
                                (for some Cl of Callee_Clauses => Cl.First_Element.Open);
                              Ranges : constant Interval_Vectors.Vector :=
                                (if Lit then Interval_Vectors.To_Vector (Interval'(Delta_V, Delta_V), 1)
                                 else Pn.Eff);
                           begin
                              if not Open_Callee then
                                 for R of Ranges loop
                                    for V0 in R.Lo .. Long_Long_Integer'Min (R.Hi, R.Lo + 100_000) loop
                                       declare
                                          X : constant Long_Long_Integer :=
                                            (if Lit then V0 else V0 + Delta_V);
                                       begin
                                          if not (for some Cl of Callee_Clauses =>
                                                    Test_Holds (Cl.First_Element, X))
                                          then
                                             Fail ("rule `" & To_String (Pn.Base) & "`, `" & T
                                                   & "`: " & Img (X) & " is outside the domain of "
                                                   & Number_Names.Element (Callee)
                                                   & " in `" & Callee & "`, and a clause that "
                                                   & "calls it with that number is chosen for "
                                                   & Param);
                                          end if;
                                       end;
                                       exit when Lit;
                                    end loop;
                                 end loop;
                              end if;
                           end;
                        end if;
                     end if;
                  end;
               end if;
            end loop;
         end Walk;
      begin
         for Pn of Pendings loop
            Walk (Pn, Pn.Text);
         end loop;
      end Check_Number_Calls;
   begin
      --  the templates, and the rules that are not
      for R of Rules loop
         if Is_Call (To_String (R.Name)) then
            declare
               H     : constant String := To_String (R.Name);
               T     : Template;
            begin
               T.Base := To_Unbounded_String (Base_Of (H));
               T.Head := To_Unbounded_String (H);
               T.R := R;
               for A of Split (Args_Of (H)) loop
                  T.Params.Append (Parse_Param (To_String (A), H));
               end loop;
               if T.Params.Is_Empty then
                  Fail ("`" & H & "`: a parameterised rule has at least one "
                        & "parameter");
               end if;
               --  the same names for the same place in every clause
               for Other of Templates loop
                  if Other.Base = T.Base
                    and then Natural (Other.Params.Length) /= Natural (T.Params.Length)
                  then
                     Fail ("`" & H & "` and `" & To_String (Other.Head)
                           & "` take different numbers of arguments");
                  end if;
               end loop;
               Templates.Append (T);
            end;
         else
            Ordinary.Append (R);
         end if;
      end loop;
      --  A rule whose parameters are all numbers is one rule, run in a frame of
      --  them, however many values the parameters take; its clauses are
      --  alternatives that each begin with a test of the numbers.
      declare
         Kept : Template_Vectors.Vector;
         Done : Key_Name_Sets.Set;

         function Is_Number_Param (P : Param) return Boolean is
           ((P.Is_Const and then P.Const.Kind = V_Int)
            or else (not P.Is_Const and then P.Domain = D_Range));
      begin
         for T0 of Templates loop
            declare
               Base : constant String := To_String (T0.Base);
               Mine : Template_Vectors.Vector;
               Eligible : Boolean := True;
            begin
               if Done.Contains (Base) then
                  null;
               else
                  Done.Insert (Base);
                  for T of Templates loop
                     if T.Base = T0.Base then
                        Mine.Append (T);
                        if not (for all P of T.Params => Is_Number_Param (P)) then
                           Eligible := False;
                        end if;
                     end if;
                  end loop;
                  if (for some T of Mine => (for some P of T.Params => P.Runtime))
                    and then not Eligible
                  then
                     Fail ("`" & To_String (T0.Head) & "`: a parameter that is a "
                           & "number worked out while parsing (`k in 0..`) goes "
                           & "with numbers; the other parameters of `" & Base
                           & "` are not");
                  end if;
                  declare
                     Open : constant Boolean :=
                       (for some T of Mine => (for some P of T.Params => P.Runtime));
                     --  a table: a few values, and a clause for particular ones
                     Small_Table : Boolean := False;
                  begin
                     if Eligible and then not Open then
                        declare
                           Has_Const : constant Boolean :=
                             (for some T of Mine => (for some P of T.Params => P.Is_Const));
                           Size : Long_Long_Integer := 1;
                        begin
                           for T of Mine loop
                              declare
                                 This : Long_Long_Integer := 1;
                              begin
                                 for P of T.Params loop
                                    if not P.Is_Const then
                                       declare
                                          Span_Total : Long_Long_Integer := 0;
                                       begin
                                          for Sp of P.Spans loop
                                             Span_Total := Span_Total + (Sp.Hi - Sp.Lo + 1);
                                          end loop;
                                          This := This * Long_Long_Integer'Max (1, Span_Total);
                                       end;
                                    end if;
                                 end loop;
                                 Size := Long_Long_Integer'Max (Size, This);
                              end;
                           end loop;
                           Small_Table := Has_Const and then Size <= 16;
                        end;
                     end if;
                     if not Eligible
                       or else (Params_Mode_Now = Expand)
                       or else (Params_Mode_Now = Auto and then Small_Table)
                     then
                        if Open then
                           Fail ("`" & To_String (T0.Head) & "`: `k in 0..` cannot be "
                                 & "expanded into a rule for each value");
                        end if;
                        for T of Mine loop
                           Kept.Append (T);
                        end loop;
                     else
                        Make_Number_Rule (Base, Mine);
                     end if;
                  end;
               end if;
            end;
         end loop;
         Templates := Kept;
         Check_Number_Calls;
      end;
      declare
         C : Domain_Maps.Cursor := Domain_Bodies.First;
      begin
         --  A domain nothing names is most likely a BNF rule in a file that does
         --  not say it is BNF.
         while Domain_Maps.Has_Element (C) loop
            declare
               N : constant String := Domain_Maps.Key (C);
            begin
               if not Domains_Used.Contains (N) then
                  Warn_Once ("domain:" & N, "",
                             "`" & N & " ::= " & Domain_Maps.Element (C)
                             & "` defines a domain, which no parameter uses "
                             & "(in hbnf `::=` is a metarule, `=` a rule).  If "
                             & "this was BNF, begin the file with the line "
                             & "`dialect bnf`");
               end if;
            end;
            Domain_Maps.Next (C);
         end loop;
      end;
      if Templates.Is_Empty and then Frame_Table.Is_Empty then
         --  a use with nothing to expand is still a mistake worth naming
         for R of Rules loop
            declare
               procedure Look (V : Element_Vectors.Vector) is
               begin
                  for E of V loop
                     if E.Kind = Name and then Is_Call (To_String (E.Name)) then
                        Fail ("rule `" & To_String (R.Name) & "`: `"
                              & To_String (E.Name) & "`: no parameterised rule `"
                              & Base_Of (To_String (E.Name)) & "` is defined; write `"
                              & Base_Of (To_String (E.Name)) & "(X) = ...`");
                     elsif E.Kind = Group then
                        Look (E.Items);
                     end if;
                  end loop;
               end Look;
            begin
               Look (R.Pattern);
            end;
         end loop;
         return;
      end if;
      --  the uses in the rules that are not templates
      declare
         Plain : constant Rule_Vectors.Vector := Ordinary;
         Empty : Binding_Vectors.Vector;
      begin
         Ordinary.Clear;
         for R of Plain loop
            declare
               X : Rule := R;
            begin
               X.Pattern := Subst (R.Pattern, Empty, To_String (R.Name));
               Ordinary.Append (X);
            end;
         end loop;
      end;
      for R of Instances loop
         Ordinary.Append (R);
      end loop;
      Rules := Ordinary;
      --  The names `%col` and `%num` set join the numbers of the frame of the
      --  rule they stand in.
      for R of Rules loop
         declare
            F : Frame_Info := Frame_Of (To_String (R.Name));

            procedure Collect (V : Element_Vectors.Vector) is
            begin
               for E of V loop
                  if E.Kind = Block and then E.Op in B_Col | B_Num then
                     if Slot_Of (To_String (R.Name), To_String (E.Ctx)) < 0 then
                        if Length (F.Slots) > 0 then
                           Append (F.Slots, " ");
                        end if;
                        Append (F.Slots, E.Ctx);
                        Set_Frame (To_String (R.Name), F);
                     end if;
                  elsif E.Kind = Group then
                     Collect (E.Items);
                  end if;
               end loop;
            end Collect;
         begin
            if Length (F.Slots) > 0 and then not F.Shares then
               Collect (R.Pattern);
            end if;
         end;
      end loop;
      --  Every number a rule uses is one of its frame, and every use of a rule
      --  with a frame gives it its arguments.
      for R of Rules loop
         declare
            Owner : constant String := To_String (R.Name);

            --  Do the names in Expr all belong to the frame?
            procedure Names_In (Expr, Where : String) is
               I : Natural := Expr'First;
            begin
               while I <= Expr'Last loop
                  if Expr (I) in 'a' .. 'z' | 'A' .. 'Z' | '_' then
                     declare
                        J : Natural := I;
                     begin
                        while J <= Expr'Last
                          and then Expr (J) in 'a' .. 'z' | 'A' .. 'Z'
                                              | '0' .. '9' | '_'
                        loop
                           J := J + 1;
                        end loop;
                        if Slot_Of (Owner, Expr (I .. J - 1)) < 0 then
                           Fail ("rule `" & Owner & "`, " & Where & ": `"
                                 & Expr (I .. J - 1) & "` is not a number of "
                                 & "this rule: its parameters are ("
                                 & (if Length (Frame_Of (Owner).Slots) = 0
                                    then "none"
                                    else To_String (Frame_Of (Owner).Slots))
                                 & "), and `%col j` and `x %num j` add more");
                        end if;
                        I := J;
                     end;
                  else
                     I := I + 1;
                  end if;
               end loop;
            end Names_In;

            procedure Walk (V : Element_Vectors.Vector) is
            begin
               for E of V loop
                  if E.Kind = Name then
                     declare
                        C : constant Frame_Info := Frame_Of (To_String (E.Name));
                     begin
                        if Length (C.Slots) > 0 and then not C.Shares then
                           if Length (E.Args) = 0 then
                              Fail ("rule `" & Owner & "`: `" & To_String (E.Name)
                                    & "` has parameters that are numbers; use it "
                                    & "with its arguments, `" & To_String (E.Name)
                                    & "(...)`");
                           end if;
                           Names_In (To_String (E.Args),
                                     "`" & To_String (E.Name) & "(" & To_String (E.Args) & ")`");
                        end if;
                     end;
                  elsif E.Kind = Block and then E.Op = B_Spaces then
                     Names_In (To_String (E.Ctx), "`%spaces`");
                  elsif E.Kind = Group then
                     Walk (E.Items);
                  end if;
               end loop;
            end Walk;
         begin
            Walk (R.Pattern);
         end;
      end loop;
   end Expand_Params;

   --  After the hyperrules are expanded, every context a rule names is one that was declared; one that is
   --  not was neither a context nor a parameter.
   procedure Check_Contexts (Rules : Rule_Vectors.Vector) is
      procedure Look (V : Element_Vectors.Vector) is
      begin
         for E of V loop
            case E.Kind is
               when Group => Look (E.Items);
               when Negation => Look (E.Operand);
               when Block =>
                  Look (E.Look);
                  if E.Op in B_Bind | B_Test | B_Not_Test
                    and then not (for some C of Context_Words => C = E.Ctx)
                  then
                     raise Parse_Error with
                       (if Ctx_Pending.Contains (To_String (E.Ctx))
                        then Ctx_Pending.Element (To_String (E.Ctx))
                        else Ctx_Pending.First_Element)
                       & ": `" & To_String (E.Ctx) & "` is not a context; declare "
                       & "it first with `context " & To_String (E.Ctx) & "`";
                  end if;
               when others => null;
            end case;
         end loop;
      end Look;
   begin
      if Ctx_Pending.Is_Empty then
         return;
      end if;
      for R of Rules loop
         Look (R.Pattern);
      end loop;
   end Check_Contexts;

   --  A rule that holds text and bit fields in one sequence
   --  (`req = "GET " len:8 payload:[len] %d13.10`) is read as runs: each run of
   --  bit fields, and each run of text, becomes a hidden rule `<owner>_<n>` of
   --  its own, and the owner becomes a sequence naming them, which is the form
   --  the two kinds already call each other in.  A name that refers to a rule
   --  belongs to the run before it.
   procedure Split_Mixed (Rules : in out Rule_Vectors.Vector) is
      type Run_Kind is (Neutral, Bit, Text);

      function Has_Bit (V : Element_Vectors.Vector) return Boolean is
      begin
         for E of V loop
            if E.Kind = Bit_Field
              or else (E.Kind = Group and then Has_Bit (E.Items))
            then
               return True;
            end if;
         end loop;
         return False;
      end Has_Bit;

      function Has_Text (V : Element_Vectors.Vector) return Boolean is
      begin
         for E of V loop
            case E.Kind is
               when Literal | Char_Range | Negation =>
                  return True;
               when Name =>
                  if Is_Core_Name (To_String (E.Name)) then
                     return True;
                  end if;
               when Group =>
                  if Has_Text (E.Items) then
                     return True;
                  end if;
               when others =>
                  null;
            end case;
         end loop;
         return False;
      end Has_Text;

      function Kind_Of (E : Element_Access; Owner : String) return Run_Kind is
      begin
         case E.Kind is
            when Bit_Field =>
               return Bit;
            when Literal | Char_Range | Negation =>
               return Text;
            when Name =>
               return (if Is_Core_Name (To_String (E.Name)) then Text
                       else Neutral);
            when Group =>
               if Has_Bit (E.Items) and then Has_Text (E.Items) then
                  raise Parse_Error with
                    "rule `" & Owner & "`: text and bit fields inside one "
                    & "group are not read together yet; split the group into "
                    & "rules of text and rules of bit fields";
               end if;
               return (if Has_Bit (E.Items) then Bit
                       elsif Has_Text (E.Items) then Text else Neutral);
            when others =>
               return Neutral;
         end case;
      end Kind_Of;

      Result : Rule_Vectors.Vector;
   begin
      for R of Rules loop
         if R.Jet_Code /= Null_Unbounded_String
           or else not (Has_Bit (R.Pattern) and then Has_Text (R.Pattern))
         then
            Result.Append (R);
         else
            declare
               Owner       : constant String := To_String (R.Name);
               P           : constant Element_Vectors.Vector := R.Pattern;
               Hidden      : Rule_Vectors.Vector;
               New_Pattern : Element_Vectors.Vector;
               Count       : Natural := 0;

               --  P (First .. Last) is one alternative.
               procedure Branch (First, Last : Natural) is
                  Kinds : array (First .. Last) of Run_Kind :=
                    [others => Neutral];
                  Prev  : Run_Kind := Neutral;
                  Runs  : Natural := 0;
                  Start : Natural := First;
               begin
                  for K in First .. Last loop
                     Kinds (K) := Kind_Of (P (K), Owner);
                  end loop;
                  --  A name follows the run before it; one that opens the
                  --  alternative takes the kind of the first element that has
                  --  one.
                  for K in First .. Last loop
                     if Kinds (K) = Neutral then
                        if Prev /= Neutral then
                           Kinds (K) := Prev;
                        else
                           for J in K + 1 .. Last loop
                              if Kinds (J) /= Neutral then
                                 Kinds (K) := Kinds (J);
                                 exit;
                              end if;
                           end loop;
                        end if;
                     end if;
                     Prev := Kinds (K);
                  end loop;
                  for K in First .. Last loop
                     if K = First or else Kinds (K) /= Kinds (K - 1) then
                        Runs := Runs + 1;
                     end if;
                  end loop;
                  --  Fields that end inside an octet, then text.
                  declare
                     Off : Integer := 0;
                  begin
                     for K in First .. Last loop
                        if Kinds (K) = Bit then
                           if P (K).Kind = Bit_Field
                             and then P (K).F_Kind in HBNF_Wire.S_Bits
                                                    | HBNF_Wire.S_Const
                             and then Off >= 0
                           then
                              Off := (Off + P (K).F_Bits) mod 8;
                           elsif P (K).Kind /= Name then
                              Off := -1;
                           end if;
                        elsif Kinds (K) = Text and then Off > 0 then
                           HBNF_Wire.Note_Shift (Owner, Off);
                           exit;
                        end if;
                     end loop;
                  end;
                  if Runs <= 1 then
                     for K in First .. Last loop
                        New_Pattern.Append (P (K));
                     end loop;
                     return;
                  end if;
                  for K in First .. Last + 1 loop
                     if K = Last + 1 or else (K > First
                                              and then Kinds (K) /= Kinds (K - 1))
                     then
                        Count := Count + 1;
                        declare
                           H   : constant Unbounded_String :=
                             To_Unbounded_String (Owner & "_" & Img (Count));
                           Run : Element_Vectors.Vector;
                        begin
                           for J in Start .. K - 1 loop
                              Run.Append (P (J));
                           end loop;
                           Hidden.Append
                             (Rule'(Name             => H,
                                    Pattern          => Run,
                                    Leading_Comment  => Null_Unbounded_String,
                                    Trailing_Comment => Null_Unbounded_String,
                                    Jet_Code         => Null_Unbounded_String,
                                    Action_Code      => Null_Unbounded_String,
                                    Left_Bases       => 0,
                                    Whitespace       => R.Whitespace));
                           New_Pattern.Append
                             (new Element'(Kind => Name, Min => 1, Max => 1,
                                           Name => H, Fold => False, Args => Null_Unbounded_String));
                        end;
                        Start := K;
                     end if;
                  end loop;
               end Branch;

               First : Natural := 1;
            begin
               for K in 1 .. Natural (P.Length) + 1 loop
                  if K > Natural (P.Length) or else P (K).Kind = Alt then
                     Branch (First, K - 1);
                     if K <= Natural (P.Length) then
                        New_Pattern.Append (P (K));
                     end if;
                     First := K + 1;
                  end if;
               end loop;
               Result.Append
                 (Rule'(Name             => R.Name,
                        Pattern          => New_Pattern,
                        Leading_Comment  => R.Leading_Comment,
                        Trailing_Comment => R.Trailing_Comment,
                        Jet_Code         => R.Jet_Code,
                        Action_Code      => R.Action_Code,
                        Left_Bases       => R.Left_Bases,
                        Whitespace       => R.Whitespace));
               for H of Hidden loop
                  Result.Append (H);
               end loop;
            end;
         end if;
      end loop;
      Rules := Result;
   end Split_Mixed;

   --  The rules that hold bit fields are not the text backends' business.  A
   --  rule is a bit rule when it holds a Bit_Field; those are set aside here, in
   --  the order written, before Finish's text analyses.  A rule that only names
   --  a bit rule stays a text rule: its reference is the call across.
   procedure Split_Wire (Rules : in out Rule_Vectors.Vector) is
      Is_Wire : array (1 .. Natural (Rules.Length)) of Boolean :=
        [others => False];

      function Mentions_Wire (V : Element_Vectors.Vector) return Boolean is
      begin
         for E of V loop
            case E.Kind is
               when Bit_Field =>
                  return True;
               when Name =>
                  null;
               when Group =>
                  if Mentions_Wire (E.Items) then
                     return True;
                  end if;
               when others =>
                  null;
            end case;
         end loop;
         return False;
      end Mentions_Wire;

      Changed : Boolean := True;
      Text    : Rule_Vectors.Vector;
   begin
      while Changed loop
         Changed := False;
         for K in Is_Wire'Range loop
            if not Is_Wire (K) and then Mentions_Wire (Rules (K).Pattern) then
               Is_Wire (K) := True;
               Changed := True;
            end if;
         end loop;
      end loop;
      if Is_Wire'Length > 0 and then Is_Wire (1) then
         Wire_Root_Flag := True;
      end if;
      for K in Is_Wire'Range loop
         if Is_Wire (K) then
            Wire_Store.Append (Rules (K));
         else
            Text.Append (Rules (K));
         end if;
      end loop;
      Rules := Text;
   end Split_Wire;

   --  `"foo"@7` in an enum: give every literal of the rule its number, as C
   --  does (an alternative without one is the one before plus 1, the first is
   --  0), and refuse a number anywhere that is not an enum.
   procedure Assign_Enum_Values (Rules : Rule_Vectors.Vector) is

      function Has_Value_Inside (V : Element_Vectors.Vector) return Boolean is
      begin
         for E of V loop
            if E.Kind = Literal and then E.Has_Value then
               return True;
            elsif E.Kind = Group and then Has_Value_Inside (E.Items) then
               return True;
            end if;
         end loop;
         return False;
      end Has_Value_Inside;

      function Plain (E : Element_Access) return Boolean is
        (E.Kind = Literal and then E.Min = 1 and then E.Max = 1
         and then not E.No_Case);
   begin
      for R of Rules loop
         declare
            Name : constant String := To_String (R.Name);
            Bs   : constant HBNF_Lookahead.Bounds_Vectors.Vector :=
              HBNF_Lookahead.Branches (R.Pattern);
            Any  : Boolean := False;
            V    : Long_Long_Integer := -1;
            Seen : Key_Sets.Set;
         begin
            for E of R.Pattern loop
               if E.Kind = Literal and then E.Has_Value then
                  Any := True;
               end if;
            end loop;
            if not Any then
               for E of R.Pattern loop
                  if E.Kind = Group and then Has_Value_Inside (E.Items) then
                     raise Parse_Error with
                       "rule `" & Name & "`: a number after a literal "
                       & "(`""foo""@7`) gives an enum value, and only a rule "
                       & "whose alternatives are all plain literals is an "
                       & "enum; this one has the number inside a group";
                  end if;
               end loop;
            else
               for B of Bs loop
                  if B.First /= B.Last or else not Plain (R.Pattern (B.First))
                  then
                     raise Parse_Error with
                       "rule `" & Name & "`: a number after a literal "
                       & "(`""foo""@7`) gives an enum value, and only a rule "
                       & "whose alternatives are all plain literals is an "
                       & "enum, as `proto = ""icmp""@1 | ""tcp""@6`.  "
                       & "Here an alternative is something else.";
                  end if;
                  declare
                     E : constant Element_Access := R.Pattern (B.First);
                  begin
                     V := (if E.Has_Value then Long_Long_Integer (E.Value)
                           else V + 1);
                     if V > 2_147_483_647 then
                        raise Parse_Error with
                          "rule `" & Name & "`: the value " & V'Image
                          & " of `""" & To_String (E.Lit) & """` does not fit "
                          & "an enum constant (31 bits)";
                     end if;
                     if Seen.Contains (V'Image) then
                        raise Parse_Error with
                          "rule `" & Name & "`: two literals have the value"
                          & V'Image & ", so a value could not be written "
                          & "back as the one that was read; give one of them "
                          & "another number";
                     end if;
                     Seen.Include (V'Image);
                     Enum_Ranks.Include
                       (Name & ASCII.NUL & To_String (E.Lit), Natural (V));
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Assign_Enum_Values;

   procedure Finish (Rules : in out Rule_Vectors.Vector) is
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
         elsif E.Kind = Literal then
            --  ABNF writes a one-character class as "0" / "1" as often as %x30
            --  / %x31: a string of one code point is one, in UTF-8 as in ASCII.
            declare
               S : constant String := To_String (E.Lit);
               B : constant Natural :=
                 (if S'Length = 0 then 0 else Character'Pos (S (S'First)));
            begin
               return S'Length = 1
                 or else (S'Length = 2 and then B in 16#C0# .. 16#DF#)
                 or else (S'Length = 3 and then B in 16#E0# .. 16#EF#)
                 or else (S'Length = 4 and then B in 16#F0# .. 16#F7#);
            end;
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

      --  A separated run written the other way round, `*n( A S ) A` (the
      --  RFC 3986 `IPv6address` has `*1( h16 ":" ) h16`), is `A *n( S A )`: the
      --  same strings, one `A` first and then `S A` as often as before.  The
      --  first form takes an `A S` greedily and cannot give it back when the
      --  `A` after it is what the text needed; the second has nothing to give
      --  back.  Write it the second way, so the author need not.
      procedure Rewrite_Separated (V : in out Element_Vectors.Vector) is
         Bs : constant HBNF_Lookahead.Bounds_Vectors.Vector :=
           HBNF_Lookahead.Branches (V);

         --  An `%emit` runs where it is written, so a repeated part that holds one is left as
         --  written; the overlap is then reported, and the author writes the shared part first.
         function Holds_Emit (Items : Element_Vectors.Vector) return Boolean is
         begin
            for E of Items loop
               if (E.Kind = Block and then E.Op = B_Emit)
                 or else (E.Kind = Group and then Holds_Emit (E.Items))
               then
                  return True;
               end if;
            end loop;
            return False;
         end Holds_Emit;
      begin
         for B of Bs loop
            for P in B.First .. B.Last loop
               if V (P).Kind = Group then
                  Rewrite_Separated (V (P).Items);
               end if;
               if P < B.Last and then V (P).Kind = Group
                 and then V (P).Min /= V (P).Max
                 and then Natural (V (P).Items.Length) >= 2
                 and then not (for some E of V (P).Items => E.Kind = Alt)
                 and then not Holds_Emit (V (P).Items)
                 and then V (P).Items (1).Min = 1 and then V (P).Items (1).Max = 1
                 and then V (P + 1).Min = 1 and then V (P + 1).Max = 1
                 and then Same_Element (V (P).Items (1), V (P + 1))
               then
                  declare
                     Old   : constant Element_Access := V (P);
                     Fresh : constant Element_Access :=
                       new Element'(Kind => Group, Min => Old.Min,
                                    Max => Old.Max,
                                    Items => Element_Vectors.Empty_Vector);
                  begin
                     for I in 2 .. Natural (Old.Items.Length) loop
                        Fresh.Items.Append (Old.Items (I));
                     end loop;
                     Fresh.Items.Append (V (P + 1));
                     V.Replace_Element (P, V (P + 1));
                     V.Replace_Element (P + 1, Fresh);
                  end;
               end if;
            end loop;
         end loop;
      end Rewrite_Separated;

      --  `/` is ABNF's union, and a parser that chooses in order and commits
      --  accepts the same language only where no alternative can take input a
      --  later one needed.  Alternatives that are each one code point are a
      --  set, and so is a union in a character rule (its scanner takes the
      --  longest branch).  Elsewhere HBNF_Lookahead looks for an order of the
      --  alternatives that works (longest first, the one that can match
      --  nothing last) and the reader writes the choice in that order, so the
      --  grammar need not be.  Only a union that needs backtracking (two
      --  alternatives that match the same text, `IPv4address / reg-name`) is
      --  refused, naming the two.  Follow_Here is what comes after the choice.
      type Analysis_Access is access HBNF_Lookahead.Analysis;
      Look : Analysis_Access;   --  made once the rules are all in

      procedure Check_Unions
        (V           : in out Element_Vectors.Vector;
         Owner       : Natural;
         Follow_Here : HBNF_Lookahead.Cp_Set;
         Char_Rule   : Boolean)
      is
         use HBNF_Lookahead;
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
            end if;
         end loop;
         Fits := Fits and then N = 1;

         --  A union of plain words (a word list: the 2048 of BIP-39) needs no
         --  search.  Longest first puts every word before the words that begin
         --  it; that is the same language wherever no word's rest, after a
         --  shorter word in the set, can begin what follows the choice (then
         --  ABNF would take the shorter and go on, and the search below says
         --  what to do).  The general search is quadratic and recursive; this
         --  is a sort.
         if Union /= null and then not Fits and then not Char_Rule
           and then not HBNF_Lookahead.Has_Any (Follow_Here)
         then
            declare
               Bs    : constant HBNF_Lookahead.Bounds_Vectors.Vector :=
                 HBNF_Lookahead.Branches (V);
               Words : Key_Sets.Set;
               Pure  : Boolean := Natural (Bs.Length) > 1;

               function Word (K : Positive) return String is
                 (To_String (V (Bs (K).First).Lit));

               function In_Follow (Cp : Natural) return Boolean is
                 (for some R in 1 .. HBNF_Lookahead.Range_Count (Follow_Here)
                  => Cp in HBNF_Lookahead.Range_Lo (Follow_Here, R)
                           .. HBNF_Lookahead.Range_Hi (Follow_Here, R));

               --  The code point that starts at S (I), or 16#10FFFF#+1 when
               --  S (I) is not the start of one.
               function Cp_At (S : String; I : Positive) return Natural is
                  B : constant Natural := Character'Pos (S (I));
               begin
                  if B < 16#80# then
                     return B;
                  elsif B in 16#80# .. 16#BF# then
                     return 16#110000#;
                  elsif B in 16#C0# .. 16#DF# and then I + 1 <= S'Last then
                     return (B - 16#C0#) * 64
                       + (Character'Pos (S (I + 1)) - 16#80#);
                  elsif B in 16#E0# .. 16#EF# and then I + 2 <= S'Last then
                     return ((B - 16#E0#) * 64
                             + (Character'Pos (S (I + 1)) - 16#80#)) * 64
                       + (Character'Pos (S (I + 2)) - 16#80#);
                  elsif B >= 16#F0# and then I + 3 <= S'Last then
                     return (((B - 16#F0#) * 64
                              + (Character'Pos (S (I + 1)) - 16#80#)) * 64
                             + (Character'Pos (S (I + 2)) - 16#80#)) * 64
                       + (Character'Pos (S (I + 3)) - 16#80#);
                  end if;
                  return 16#110000#;
               end Cp_At;
            begin
               for K in 1 .. Natural (Bs.Length) loop
                  if Bs (K).First /= Bs (K).Last
                    or else V (Bs (K).First).Kind /= Literal
                    or else V (Bs (K).First).Min /= 1
                    or else V (Bs (K).First).Max /= 1
                    or else V (Bs (K).First).No_Case
                    or else Words.Contains (Word (K))
                  then
                     Pure := False;
                     exit;
                  end if;
                  Words.Include (Word (K));
               end loop;
               if Pure then
                  for K in 1 .. Natural (Bs.Length) loop
                     declare
                        W : constant String := Word (K);
                     begin
                        for L in W'First .. W'Last - 1 loop
                           if Words.Contains (W (W'First .. L))
                             and then Cp_At (W, L + 1) < 16#110000#
                             and then In_Follow (Cp_At (W, L + 1))
                           then
                              Pure := False;
                              exit;
                           end if;
                        end loop;
                     end;
                     exit when not Pure;
                  end loop;
               end if;
               if Pure then
                  declare
                     Order : Order_Vectors.Vector;
                     Done  : array (1 .. Natural (Bs.Length)) of Boolean :=
                       [others => False];
                     Longest : Natural := 0;
                  begin
                     for K in 1 .. Natural (Bs.Length) loop
                        Longest := Natural'Max (Longest, Word (K)'Length);
                     end loop;
                     --  A stable counting sort by length, longest first.
                     for Len in reverse 0 .. Longest loop
                        for K in 1 .. Natural (Bs.Length) loop
                           if Word (K)'Length = Len then
                              Order.Append (K);
                              Done (K) := True;
                           end if;
                        end loop;
                     end loop;
                     if (for some K in 1 .. Natural (Order.Length) =>
                           Order (K) /= K)
                     then
                        declare
                           Reordered : Element_Vectors.Vector;
                        begin
                           for K of Order loop
                              if not Reordered.Is_Empty then
                                 Reordered.Append (Union);
                              end if;
                              Reordered.Append (V (Bs (K).First));
                              if not Enum_Ranks.Contains
                                       (To_String (Rules (Owner).Name)
                                        & ASCII.NUL & Word (K))
                              then
                                 Enum_Ranks.Include
                                   (To_String (Rules (Owner).Name) & ASCII.NUL
                                    & Word (K), K - 1);
                              end if;
                           end loop;
                           V := Reordered;
                        end;
                     end if;
                     Fits := True;   --  decided: no search needed
                  end;
               end if;
            end;
         end if;

         if Union /= null and then not Fits and then not Char_Rule then
            declare
               Ok      : Boolean;
               Message : Unbounded_String;
               Order   : Order_Vectors.Vector;
               Bs      : constant Bounds_Vectors.Vector :=
                 HBNF_Lookahead.Branches (V);
            begin
               Check_Choice
                 (Look.all, Rules, Owner, V, Follow_Here, Ok, Message, Order);
               if not Ok then
                  for S of Union_Sites loop
                     if S.Alt = Union then
                        if HBNF_Lookahead.Has_Any (Follow_Here) then
                           --  What follows is not known (a scanner, a core
                           --  type): no guard can be written.
                           Report
                             (S, "`" & To_String (S.Text) & "` is ABNF's "
                              & "union, and here hbnf cannot compile it"
                              & ASCII.LF
                              & "  ABNF tries every alternative and goes back "
                              & "if what follows does not fit.  hbnf chooses "
                              & "once and does not go back, so it writes a "
                              & "union as an ordered choice in whatever order "
                              & "gives the same language; here no order does: "
                              & To_String (Message));
                        else
                           --  First match wins, as RFC 3986 section 3.2.2
                           --  settles `host`: the first alternative that
                           --  matches and is followed by something that can
                           --  follow the choice.
                           declare
                              G : Guard_Set;
                              K : Positive;
                           begin
                              for R in 1 .. HBNF_Lookahead.Range_Count
                                             (Follow_Here)
                              loop
                                 G.Ranges.Append
                                   (Guard_Range'
                                      (Lo => HBNF_Lookahead.Range_Lo
                                               (Follow_Here, R),
                                       Hi => HBNF_Lookahead.Range_Hi
                                               (Follow_Here, R)));
                              end loop;
                              G.Eoi := HBNF_Lookahead.Has_Eoi (Follow_Here);
                              Guards.Append (G);
                              K := Positive (Guards.Length);
                              for E of V loop
                                 if E.Kind = Alt then
                                    E.Guard := K;
                                 end if;
                              end loop;
                           end;
                           Warn
                             ((if S.File = Null_Unbounded_String then ""
                               else To_String (S.File) & ":")
                              & Img (S.Line) & ":" & Img (S.Col),
                              "`" & To_String (S.Text) & "` is ABNF's union, "
                              & "and here it needs backtracking: "
                              & To_String (Message) & ASCII.LF
                              & "  hbnf takes the first alternative that "
                              & "matches and is followed by something that "
                              & "can follow the choice (first match wins, as "
                              & "RFC 3986 section 3.2.2 settles `host`).  "
                              & "Where ABNF's backtracking would choose "
                              & "differently, write `|` with the one to "
                              & "prefer first, or change an alternative so "
                              & "that it cannot match what another does");
                        end if;
                        exit;
                     end if;
                  end loop;
               elsif (for some K in 1 .. Natural (Order.Length) =>
                        Order (K) /= K)
               then
                  declare
                     Reordered : Element_Vectors.Vector;
                  begin
                     for K of Order loop
                        if not Reordered.Is_Empty then
                           Reordered.Append (Union);
                        end if;
                        for I in Bs (K).First .. Bs (K).Last loop
                           Reordered.Append (V (I));
                        end loop;
                     end loop;
                     V := Reordered;
                  end;
               end if;
            end;
         end if;
         --  Now the groups, each followed by what follows it here.
         declare
            Bs : constant Bounds_Vectors.Vector := HBNF_Lookahead.Branches (V);
         begin
            for B of Bs loop
               for P in B.First .. B.Last loop
                  if V (P).Kind = Group then
                     Check_Unions
                       (V (P).Items, Owner,
                        Follow_After (Look.all, Rules, V, B, P, Follow_Here),
                        Char_Rule);
                  end if;
               end loop;
            end loop;
         end;
      end Check_Unions;

      --  A repetition (`*x`, `[ x ]`, `1*4x`) is read greedily: as many as
      --  match, and none given back.  ABNF gives one back if what follows
      --  needed it, so where what follows can begin the way one more
      --  repetition does, the same text can parse differently.  Say so,
      --  and how to write it.
      --  Cont is what follows V's group in the sequences around it.
      procedure Check_Greedy
        (V : Element_Vectors.Vector; Owner : Natural;
         Cont : Element_Vectors.Vector) is
      begin
         for B of HBNF_Lookahead.Branches (V) loop
            for P in B.First .. B.Last loop
               declare
                  E    : constant Element_Access := V (P);
                  Rest : Element_Vectors.Vector;
               begin
                  for I in P + 1 .. B.Last loop
                     Rest.Append (V (I));
                  end loop;
                  for X of Cont loop
                     Rest.Append (X);
                  end loop;
                  if E.Kind = Group then
                     Check_Greedy (E.Items, Owner, Rest);
                  end if;
                  if E.Min /= E.Max and then not Rest.Is_Empty then
                     for S of Greedy_Sites loop
                        if S.Alt = E then
                           declare
                              Found : Boolean;
                              Text  : Unbounded_String;
                           begin
                              HBNF_Lookahead.Greedy_Overlap
                                (Rules, Owner, E, Rest, 1,
                                 Natural (Rest.Length), Found, Text);
                              if Found then
                                 Report
                                   (S, "this repetition is matched greedily, "
                                    & "unlike ABNF's" & ASCII.LF
                                    & "  ABNF gives a repetition back if "
                                    & "what follows needs it.  hbnf takes as "
                                    & "many as match and keeps them.  What "
                                    & "follows here can begin the way one "
                                    & "more repetition does (text such as `"
                                    & To_String (Text) & "`), so text ABNF "
                                    & "accepts can be refused.  Write the "
                                    & "part they share before the repetition: "
                                    & "`[ *( x "","" ) x ]` is "
                                    & "`[ x *( "","" x ) ]`");
                              end if;
                           end;
                           exit;
                        end if;
                     end loop;
                  end if;
               end;
            end loop;
         end loop;
      end Check_Greedy;



      --  A `<...>` that names a rule written in the file is that rule:
      --  `<pchar>` is `pchar`.  One that names none stays what it was, a rule
      --  not written yet, which Check_Prose reports.
      procedure Resolve_Brackets (V : Element_Vectors.Vector) is
      begin
         for E of V loop
            if E.Kind = Name and then Length (E.Name) > 0
              and then Slice (E.Name, 1, 1) = "<"
            then
               declare
                  S  : constant String := To_String (E.Name);
                  N  : constant Positive :=
                    Positive'Value (S (S'First + 1 .. S'Last - 1));
                  Id : constant String :=
                    Prose_Id (To_String (Prose_Sites (N).Text));
               begin
                  if Id /= "" and then By_Name.Contains (Id) then
                     E.Name := To_Unbounded_String (Id);
                     if not Bnf_Spellings.Contains (Id) then
                        Bnf_Spellings.Insert
                          (Id, "<" & To_String (Prose_Sites (N).Text) & ">");
                     end if;
                  end if;
               end;
            elsif E.Kind = Group then
               Resolve_Brackets (E.Items);
            end if;
         end loop;
      end Resolve_Brackets;

      --  The message for a rule written between brackets that nothing
      --  defines: T is what is between them, Max the repetition in front of
      --  it, Only whether it is the whole of the rule it is in.
      function Not_Written
        (T : String; Max : Integer; Only : Boolean; In_Rule : String)
         return String
      is
         Last : Natural := 0;
      begin
         while Last < T'Length
           and then (T (T'First + Last) in 'a' .. 'z' | 'A' .. 'Z'
                     | '0' .. '9' | '-')
         loop
            Last := Last + 1;
         end loop;
         declare
            --  A rule name: the whole description, or its first word before
            --  a comma (`<host, see ...>`); not the start of a sentence
            --  (`<to be written>`).
            Guess : constant String :=
              (if Last > 0
                 and then (Last = T'Length or else T (T'First + Last) = ',')
               then T (T'First .. T'First + Last - 1) else "");
         begin
            return
              "not written yet, in `" & In_Rule & "`: <" & T & ">"
              & ASCII.LF
              & "  `<...>` names a rule, as Backus and Naur write a "
              & "nonterminal (ABNF also uses it to describe a rule in "
              & "words), and no rule of that name is written.  Write it: `<"
              & T & "> = ...` at the start of a line, or `" & Prose_Id (T)
              & " = ...`."
              & (if Max = 0 then
                   ASCII.LF & "  `0<" & T & ">` repeats a description zero "
                   & "times, which is to say it matches nothing: write it `0"
                   & Guess & "`, or leave it out"
                 elsif Guess = In_Rule then
                   ASCII.LF & "  This says `" & In_Rule & "` is defined "
                   & "elsewhere, and this rule has the same name: `include` "
                   & "the file that defines it and delete this line.  (A "
                   & "later `=` replaces an earlier one, so keeping it would "
                   & "replace the real rule with nothing.)"
                 elsif Guess'Length > 0 then
                   ASCII.LF & "  This probably means the rule `" & Guess
                   & "`, defined elsewhere: "
                   & (if Only then "write `" & In_Rule & " = " & Guess & "`"
                      else "write `" & Guess & "` here")
                   & ", and `include` the file that defines it"
                 else "");
         end;
      end Not_Written;

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
                     Not_Written
                       (To_String (Prose_Sites (N).Text), E.Max,
                        Natural (V.Length) = 1 and then V.First_Element = E
                        and then E.Min = 1 and then E.Max = 1,
                        In_Rule));
               end;
            elsif E.Kind = Group then
               Check_Prose (E.Items, In_Rule);
            end if;
         end loop;
      end Check_Prose;

      --  A name nothing defines.  Backus and Naur write a terminal bare, and
      --  ABNF a rule bare, so a bare word may be either; hbnf says a terminal
      --  is quoted, and only a rule is a bare name.  One written between
      --  brackets is a rule not written yet.
      Told_Tokens : String_Lists.Vector;   --  declared tokens already said

      procedure Check_Undefined (V : Element_Vectors.Vector; In_Rule : String)
      is
      begin
         for E of V loop
            if E.Kind = Name and then Length (E.Name) > 0
              and then Slice (E.Name, 1, 1) /= "<"
              and then not By_Name.Contains (To_String (E.Name))
              and then not Is_Core_Name (To_String (E.Name))
              and then not Is_Wire_Rule (To_String (E.Name))
            then
               declare
                  Sited : Boolean := False;
               begin
                  for S of Prose_Sites loop
                     if S.Alt = E then
                        Sited := True;
                        Report
                          (S, Not_Written
                                (To_String (S.Text), E.Max,
                                 Natural (V.Length) = 1
                                 and then V.First_Element = E
                                 and then E.Min = 1 and then E.Max = 1,
                                 In_Rule));
                        exit;
                     end if;
                  end loop;
                  if not Sited then
                     for T of Declared_Tokens loop
                        if T.Name = E.Name then
                           Sited := True;
                           if not (for some X of Told_Tokens => X = E.Name)
                           then
                              Told_Tokens.Append (E.Name);
                           Report
                             ("in rule `" & In_Rule & "`: `"
                              & To_String (E.Name) & "` is declared `%token` "
                              & "(line" & Natural'Image (T.Line) & ") but "
                              & "nothing defines it" & ASCII.LF
                              & "  yacc leaves a token to its lexer.  hbnf "
                              & "reads characters, so a token is a rule: "
                              & (if T.Spelling /= Null_Unbounded_String then
                                   "the standard spells it `"
                                   & To_String (T.Spelling) & "`, so write `"
                                   & To_String (E.Name) & " = """
                                   & To_String (T.Spelling) & """`"
                                 else
                                   "this one is a class of text, so write `"
                                   & To_String (E.Name) & " = ...` as a rule "
                                   & "of characters, for example `NAME = "
                                   & "ALPHA *( ALPHA / DIGIT / ""_"" )`"));
                           end if;
                           exit;
                        end if;
                     end loop;
                  end if;
                  if not Sited then
                     Report ("in rule `" & In_Rule & "`: `" & To_String (E.Name)
                             & "` is not defined as a rule" & ASCII.LF
                             & "  Backus-Naur form writes a terminal bare, `"
                             & To_String (E.Name) & "`; hbnf writes it in "
                             & "quotes, `""" & To_String (E.Name) & """`, and "
                             & "a bare name is a rule.  If it is a rule, "
                             & "write `" & To_String (E.Name) & " = ...`");
                  end if;
               end;
            elsif E.Kind = Group then
               Check_Undefined (E.Items, In_Rule);
            end if;
         end loop;
      end Check_Undefined;
   begin
      --  --root=: the named rule goes first, which is what makes it the root.
      --  Every later step (the checks, the lifting, the emitters) then sees
      --  the grammar as that rule's, and what it does not reach is dropped.
      if Root_Rule /= Null_Unbounded_String then
         declare
            J : Natural := 0;
         begin
            for K in 1 .. Natural (Rules.Length) loop
               if To_String (Rules (K).Name) = To_String (Root_Rule) then
                  J := K;
                  exit;
               end if;
            end loop;
            if J = 0 then
               raise Parse_Error with
                 "--root=" & To_String (Root_Rule) & ": the schema has no rule"
                 & " of that name";
            end if;
            if J > 1 then
               declare
                  R : constant Rule := Rules (J);
               begin
                  Rules.Delete (J);
                  Rules.Insert (1, R);
               end;
            end if;
         end;
      end if;

      --  `~x`: every negation becomes a reference to a rule of the ranges the
      --  complement of x covers, before anything else looks at the rules.  x
      --  matches one code point (a class), so its complement is a set of
      --  ranges, and a rule of ranges is a character rule like any other: the
      --  scanners, the lookahead and the four backends need no new case.
      declare
         type Pair is record
            Lo, Hi : Natural;
         end record;
         package Pair_Vectors is new Ada.Containers.Vectors (Positive, Pair);
         Max_Cp : constant := 16#10FFFF#;
         Made   : Rule_Vectors.Vector;

         function Hex (C : Natural) return String is
            D : constant String := "0123456789ABCDEF";
         begin
            if C < 16 then
               return [D (C + 1)];
            end if;
            return Hex (C / 16) & D (C mod 16 + 1);
         end Hex;

         function Find_Rule (N : String) return Natural is
         begin
            for K in 1 .. Natural (Rules.Length) loop
               if To_String (Rules (K).Name) = N then
                  return K;
               end if;
            end loop;
            return 0;
         end Find_Rule;

         --  Does the string hold exactly one UTF-8 code point?
         function One_Cp (S : String) return Boolean is
            B : constant Natural :=
              (if S'Length = 0 then 0 else Character'Pos (S (S'First)));
         begin
            return S'Length = 1
              or else (S'Length = 2 and then B in 16#C0# .. 16#DF#)
              or else (S'Length = 3 and then B in 16#E0# .. 16#EF#)
              or else (S'Length = 4 and then B in 16#F0# .. 16#F7#);
         end One_Cp;

         function Code_Point (S : String) return Natural is
            function B (K : Natural) return Natural is
              (Character'Pos (S (S'First + K)));
         begin
            if B (0) < 16#80# then
               return B (0);
            elsif B (0) < 16#E0# then
               return (B (0) - 16#C0#) * 64 + B (1) mod 64;
            elsif B (0) < 16#F0# then
               return (B (0) - 16#E0#) * 4096 + (B (1) mod 64) * 64
                      + B (2) mod 64;
            else
               return (B (0) - 16#F0#) * 262144 + (B (1) mod 64) * 4096
                      + (B (2) mod 64) * 64 + B (3) mod 64;
            end if;
         end Code_Point;

         procedure Refuse (Owner, Why : String) is
         begin
            raise Parse_Error with
              "in rule `" & Owner & "`: " & Why & ASCII.LF
              & "  `~x` is one code point that is not in x, and `*~x` a run of "
              & "them; x is a class: a one-character string, a range, a rule "
              & "of those, or alternatives of those";
         end Refuse;

         procedure Add_Cp (Acc : in out Pair_Vectors.Vector; Lo, Hi : Natural) is
         begin
            Acc.Append (Pair'(Lo => Lo, Hi => Hi));
         end Add_Cp;

         procedure Add (Owner : String; E : Element_Access;
                        Acc : in out Pair_Vectors.Vector; Depth : Natural);

         procedure Add_Branches (Owner : String; Els : Element_Vectors.Vector;
                                 Acc : in out Pair_Vectors.Vector;
                                 Depth : Natural) is
            In_Branch : Natural := 0;
            Pending   : Element_Access;
         begin
            for E of Els loop
               if E.Kind = Alt then
                  if In_Branch /= 1 then
                     Refuse (Owner, "an alternative of the class is not one "
                             & "character");
                  end if;
                  Add (Owner, Pending, Acc, Depth);
                  In_Branch := 0;
               else
                  In_Branch := In_Branch + 1;
                  Pending := E;
               end if;
            end loop;
            if In_Branch /= 1 then
               Refuse (Owner, "an alternative of the class is not one "
                       & "character");
            end if;
            Add (Owner, Pending, Acc, Depth);
         end Add_Branches;

         function Normalized (Acc : Pair_Vectors.Vector)
           return Pair_Vectors.Vector is
            Sorted : Pair_Vectors.Vector := Acc;
            Result : Pair_Vectors.Vector;
         begin
            for I in 1 .. Natural (Sorted.Length) loop
               for J in 1 .. Natural (Sorted.Length) - I loop
                  if Sorted (J + 1).Lo < Sorted (J).Lo then
                     declare
                        T : constant Pair := Sorted (J);
                     begin
                        Sorted.Replace_Element (J, Sorted (J + 1));
                        Sorted.Replace_Element (J + 1, T);
                     end;
                  end if;
               end loop;
            end loop;
            for P of Sorted loop
               if not Result.Is_Empty
                 and then P.Lo <= Result.Last_Element.Hi + 1
               then
                  if P.Hi > Result.Last_Element.Hi then
                     Result.Replace_Element
                       (Result.Last_Index,
                        Pair'(Lo => Result.Last_Element.Lo, Hi => P.Hi));
                  end if;
               else
                  Result.Append (P);
               end if;
            end loop;
            return Result;
         end Normalized;

         function Complement (Acc : Pair_Vectors.Vector)
           return Pair_Vectors.Vector is
            Set    : constant Pair_Vectors.Vector := Normalized (Acc);
            Result : Pair_Vectors.Vector;
            Next   : Natural := 0;
         begin
            for P of Set loop
               if P.Lo > Next then
                  Result.Append (Pair'(Lo => Next, Hi => P.Lo - 1));
               end if;
               Next := P.Hi + 1;
            end loop;
            if Next <= Max_Cp then
               Result.Append (Pair'(Lo => Next, Hi => Max_Cp));
            end if;
            return Result;
         end Complement;

         procedure Add (Owner : String; E : Element_Access;
                        Acc : in out Pair_Vectors.Vector; Depth : Natural) is
         begin
            if Depth = 0 then
               Refuse (Owner, "a class refers to itself");
            elsif E.Min /= 1 or else E.Max /= 1 then
               Refuse (Owner, "the class repeats something");
            end if;
            case E.Kind is
               when Char_Range =>
                  Add_Cp (Acc, E.Lo, E.Hi);
               when Literal =>
                  declare
                     L : constant String := To_String (E.Lit);
                  begin
                     if not One_Cp (L) then
                        Refuse (Owner, "`""" & L & """` is more than one "
                                & "character");
                     end if;
                     declare
                        C : constant Natural := Code_Point (L);
                     begin
                        Add_Cp (Acc, C, C);
                        if E.No_Case and then C in 65 .. 90 then
                           Add_Cp (Acc, C + 32, C + 32);
                        elsif E.No_Case and then C in 97 .. 122 then
                           Add_Cp (Acc, C - 32, C - 32);
                        end if;
                     end;
                  end;
               when Group =>
                  Add_Branches (Owner, E.Items, Acc, Depth - 1);
               when Bit_Field =>
                  null;     --  a rule with bit fields never reaches here (Split_Wire)
               when Negation =>
                  declare
                     Inner : Pair_Vectors.Vector;
                  begin
                     Add_Branches (Owner, E.Operand, Inner, Depth - 1);
                     for P of Complement (Inner) loop
                        Acc.Append (P);
                     end loop;
                  end;
               when Name =>
                  declare
                     N : constant String := To_String (E.Name);
                     J : constant Natural := Find_Rule (N);
                  begin
                     if Is_Core_Name (N) then
                        Refuse (Owner, "`" & N & "` is a built-in type, not "
                                & "a class of one character");
                     elsif J = 0 then
                        Refuse (Owner, "`" & N & "` is not defined");
                     elsif Rules (J).Jet_Code /= Null_Unbounded_String then
                        Refuse (Owner, "`" & N & "` is code, and its "
                                & "characters are not known");
                     end if;
                     Add_Branches (Owner, Rules (J).Pattern, Acc, Depth - 1);
                  end;
               when others =>
                  Refuse (Owner, "that is not a class of characters");
            end case;
         end Add;

         --  The rule of the complement's ranges, made once per set.
         function Rule_For (Owner : String; Ranges : Pair_Vectors.Vector)
           return String is
            Name : Unbounded_String := To_Unbounded_String ("not-x");
            Pat  : Element_Vectors.Vector;
         begin
            if Ranges.Is_Empty then
               Refuse (Owner, "the class is every character, so its "
                       & "complement matches nothing");
            end if;
            for K in 1 .. Natural (Ranges.Length) loop
               if K > 1 then
                  Append (Name, "_");
                  Pat.Append (new Element'(Kind => Alt, Min => 1, Max => 1,
                                           Guard => 0, Union => False));
               end if;
               Append (Name, Hex (Ranges (K).Lo));
               if Ranges (K).Hi /= Ranges (K).Lo then
                  Append (Name, "-" & Hex (Ranges (K).Hi));
               end if;
               Pat.Append (new Element'(Kind => Char_Range, Min => 1, Max => 1,
                                        Lo => Ranges (K).Lo,
                                        Hi => Ranges (K).Hi));
            end loop;
            if Find_Rule (To_String (Name)) = 0
              and then not (for some R of Made => R.Name = Name)
            then
               Made.Append
                 (Rule'(Name => Name, Pattern => Pat,
                        Leading_Comment => Null_Unbounded_String,
                        Trailing_Comment => Null_Unbounded_String,
                        Jet_Code => Null_Unbounded_String,
                        Action_Code => Null_Unbounded_String,
                        Left_Bases => 0,
                        Whitespace => Null_Unbounded_String));
            end if;
            return To_String (Name);
         end Rule_For;

         procedure Walk (Owner : String; V : in out Element_Vectors.Vector) is
         begin
            for I in 1 .. Natural (V.Length) loop
               declare
                  E : constant Element_Access := V (I);
               begin
                  if E.Kind = Negation then
                     declare
                        Set : Pair_Vectors.Vector;
                     begin
                        Add_Branches (Owner, E.Operand, Set, 20);
                        V.Replace_Element
                          (I, new Element'
                                (Kind => Name, Min => E.Min, Max => E.Max,
                                 Name => To_Unbounded_String
                                           (Rule_For (Owner, Complement (Set))),
                                 Fold => False, Args => Null_Unbounded_String));
                     end;
                  elsif E.Kind = Group then
                     Walk (Owner, E.Items);
                  end if;
               end;
            end loop;
         end Walk;
      begin
         for J in 1 .. Natural (Rules.Length) loop
            declare
               Pat : Element_Vectors.Vector := Rules (J).Pattern;
            begin
               Walk (To_String (Rules (J).Name), Pat);
               Rules (J).Pattern := Pat;
            end;
         end loop;
         for R of Made loop
            Rules.Append (R);
         end loop;
      end;

      --  Do keywords exist here?  (See Keywords_Apply.)  Said first: whether a
      --  rule is a character rule depends on it.
      declare
         function Names_Word (Els : Element_Vectors.Vector) return Boolean is
           (for some E of Els =>
              (E.Kind = Name
               and then (To_String (E.Name) = "word"
                         or else To_String (E.Name) = "atom"))
              or else (E.Kind = Group and then Names_Word (E.Items)));
      begin
         Words_Used := (for some R of Rules => Names_Word (R.Pattern));
      end;

      --  The built-in lexical jets: the classic word/int/str scanners and the
      --  default whitespace, as hand-written `%scan{}` code a grammar
      --  (obconf) may override.  A grammar that defines its own rule keeps
      --  it; `Reachable` drops an injected jet nothing references.
      declare
         procedure Inject_Jet (Name, Code : String) is
            Present : Boolean := False;
         begin
            for R of Rules loop
               if To_String (R.Name) = Name then
                  Present := True;
                  exit;
               end if;
            end loop;
            if not Present then
               Rules.Append
                 (Rule'(Name            => To_Unbounded_String (Name),
                        Pattern         => Element_Vectors.Empty_Vector,
                        Leading_Comment => Null_Unbounded_String,
                        Trailing_Comment => Null_Unbounded_String,
                        Jet_Code        => To_Unbounded_String (Code),
                        Action_Code     => Null_Unbounded_String,
                        Left_Bases      => 0,
                        Whitespace      => Null_Unbounded_String));
            end if;
         end Inject_Jet;
      begin
         Inject_Jet ("word",
           "size_t i = pos;" & ASCII.LF &
           "if (i >= len" & ASCII.LF &
           "    || !((s[i] >= 'a' && s[i] <= 'z')" & ASCII.LF &
           "         || (s[i] >= 'A' && s[i] <= 'Z')" & ASCII.LF &
           "         || s[i] == '_' || s[i] == '-'))" & ASCII.LF &
           "    return 0;" & ASCII.LF &
           "i++;" & ASCII.LF &
           "while (i < len" & ASCII.LF &
           "       && ((s[i] >= 'a' && s[i] <= 'z')" & ASCII.LF &
           "           || (s[i] >= 'A' && s[i] <= 'Z')" & ASCII.LF &
           "           || (s[i] >= '0' && s[i] <= '9')" & ASCII.LF &
           "           || s[i] == '_' || s[i] == '-'" & ASCII.LF &
           "           || s[i] == '.'))" & ASCII.LF &
           "    i++;" & ASCII.LF &
           "return i - pos;");
         Inject_Jet ("int",
           "size_t i = pos, start;" & ASCII.LF &
           "if (i < len && s[i] == '-' && i + 1 < len" & ASCII.LF &
           "    && s[i + 1] >= '0' && s[i + 1] <= '9')" & ASCII.LF &
           "    i++;" & ASCII.LF &
           "start = i;" & ASCII.LF &
           "while (i < len && s[i] >= '0' && s[i] <= '9')" & ASCII.LF &
           "    i++;" & ASCII.LF &
           "return i > start ? i - pos : 0;");
         Inject_Jet ("str",
           "size_t i;" & ASCII.LF &
           "if (pos >= len || s[pos] != '""')" & ASCII.LF &
           "    return 0;" & ASCII.LF &
           "i = pos + 1;" & ASCII.LF &
           "while (i < len && s[i] != '""') {" & ASCII.LF &
           "    if (s[i] == '\\' && i + 1 < len)" & ASCII.LF &
           "        i++;" & ASCII.LF &
           "    i++;" & ASCII.LF &
           "}" & ASCII.LF &
           "if (i >= len || s[i] != '""')" & ASCII.LF &
           "    return 0;" & ASCII.LF &
           "return i + 1 - pos;");
         Inject_Jet ("ws",
           "if (pos < len) {" & ASCII.LF &
           "    char c = s[pos];" & ASCII.LF &
           "    if (c == ' ' || c == '\t' || c == '\r'" & ASCII.LF &
           "        || c == '\n')" & ASCII.LF &
           "        return 1;" & ASCII.LF &
           "}" & ASCII.LF &
           "return 0;");
      end;

      --  An RFC may define a rule with the name of one of hbnf's built-in
      --  types (RFC 5322 defines `atom` and `word` as structures).  In hbnf
      --  such a name reads as a value, in every backend, so the reader gives
      --  the rule another name, `atom-rule`, here and everywhere it is
      --  referred to, and says so.
      declare
         procedure Rename_In
           (V : Element_Vectors.Vector; Old : String; Fresh : Unbounded_String)
         is
         begin
            for E of V loop
               if E.Kind = Name and then To_String (E.Name) = Old then
                  E.Name := Fresh;
               elsif E.Kind = Group then
                  Rename_In (E.Items, Old, Fresh);
               end if;
            end loop;
         end Rename_In;
      begin
         for J in 1 .. Natural (Rules.Length) loop
            declare
               Old : constant String := To_String (Rules (J).Name);
            begin
               --  Exactly a built-in's name, building a structure; or the same
               --  name in another case (yacc's `WORD` token): the generated
               --  code makes one name of the two.
               if Rules (J).Jet_Code = Null_Unbounded_String
                 and then
                   ((Is_Core_Name (Old)
                     and then not Is_Char_Rule (Rules, Old)
                     and then (for some E of Rules (J).Pattern =>
                                 E.Kind = Name or else E.Kind = Group))
                    or else (Old /= To_Lower (Old)
                             and then Is_Core_Name (To_Lower (Old))
                             --  A dialect's prefix already keeps `WORD`
                             --  and `word` apart.
                             and then Flag_Dialect = Null_Unbounded_String
                             and then File_Dialect = Null_Unbounded_String))
               then
                  declare
                     Fresh : constant Unbounded_String :=
                       To_Unbounded_String (Old & "-rule");
                  begin
                     for K in 1 .. Natural (Rules.Length) loop
                        Rename_In (Rules (K).Pattern, Old, Fresh);
                     end loop;
                     declare
                        R : Rule := Rules (J);
                     begin
                        R.Name := Fresh;
                        Rules.Replace_Element (J, R);
                     end;
                     if not Bnf_Spellings.Contains (To_String (Fresh)) then
                        Bnf_Spellings.Insert (To_String (Fresh), Old);
                     end if;
                     Warn_Once
                       ("core-name:" & Old, "",
                        "the rule `" & Old & "` has the name of a built-in "
                        & "type, which hbnf reads as one value in every "
                        & "backend, so here it is called `" & To_String (Fresh)
                        & "` (in the tree too) wherever the grammar refers to "
                        & "it");
                  end;
               end if;
            end;
         end loop;
      end;

      --  A notation whose names are case-sensitive (yacc's: `name` the rule, `NAME` the token)
      --  may use two names that differ only in case; here they would be one name, and so
      --  would the identifiers of the generated code.  The reader gives the one with more
      --  capitals (the token) another name, `NAME-token`, here and everywhere it is used,
      --  and says so.
      if Flag_Dialect /= Null_Unbounded_String
        or else File_Dialect /= Null_Unbounded_String
      then
         declare
            procedure Rename_In
              (V : Element_Vectors.Vector; Old : String; Fresh : Unbounded_String)
            is
            begin
               for E of V loop
                  if E.Kind = Name and then To_String (E.Name) = Old then
                     E.Name := Fresh;
                  elsif E.Kind = Group then
                     Rename_In (E.Items, Old, Fresh);
                  end if;
               end loop;
            end Rename_In;

            function Capitals (S : String) return Natural is
               N : Natural := 0;
            begin
               for C of S loop
                  if C in 'A' .. 'Z' then
                     N := N + 1;
                  end if;
               end loop;
               return N;
            end Capitals;
         begin
            for J in 1 .. Natural (Rules.Length) loop
               for K in 1 .. Natural (Rules.Length) loop
                  declare
                     A : constant String := To_String (Rules (J).Name);
                     B : constant String := To_String (Rules (K).Name);
                  begin
                     if J /= K and then A /= B
                       and then To_Lower (A) = To_Lower (B)
                       and then Capitals (A) > Capitals (B)
                     then
                        declare
                           Fresh : constant Unbounded_String :=
                             To_Unbounded_String (A & "-token");
                           R : Rule := Rules (J);
                        begin
                           for X in 1 .. Natural (Rules.Length) loop
                              Rename_In (Rules (X).Pattern, A, Fresh);
                           end loop;
                           R.Name := Fresh;
                           Rules.Replace_Element (J, R);
                           if not Bnf_Spellings.Contains (To_String (Fresh)) then
                              Bnf_Spellings.Insert (To_String (Fresh), A);
                           end if;
                           Warn_Once
                             ("case-name:" & A, "",
                              "`" & A & "` and `" & B & "` differ only in case, and "
                              & "hbnf's names ignore case, so here `" & A
                              & "` is called `" & To_String (Fresh) & "` (in the tree "
                              & "too) wherever the grammar refers to it");
                        end;
                     end if;
                  end;
               end loop;
            end loop;
         end;
      end if;

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
         Resolve_Brackets (R.Pattern);
      end loop;
      for R of Rules loop
         Resolve (R.Pattern, To_String (R.Name));
      end loop;
      for J in 1 .. Natural (Rules.Length) loop
         declare
            Pat : Element_Vectors.Vector := Rules (J).Pattern;
         begin
            Rewrite_Separated (Pat);
            declare
               R : Rule := Rules (J);
            begin
               R.Pattern := Pat;
               Rules.Replace_Element (J, R);
            end;
         end;
      end loop;
      Assign_Enum_Values (Rules);
      Look := new HBNF_Lookahead.Analysis'(HBNF_Lookahead.Analyze (Rules));
      declare
         Used  : constant Rule_Vectors.Vector := Reachable (Rules);
         Lower : Index_Maps.Map;

         --  Is some name in a rule the parser uses defined nowhere?
         function Undefined_In (V : Element_Vectors.Vector) return Boolean is
           (for some E of V =>
              (E.Kind = Name and then Length (E.Name) > 0
               and then Slice (E.Name, 1, 1) /= "<"
               and then not By_Name.Contains (To_String (E.Name))
               and then not Is_Core_Name (To_String (E.Name))
               and then not Is_Wire_Rule (To_String (E.Name)))
              or else (E.Kind = Group and then Undefined_In (E.Items)));

         Any_Undefined : constant Boolean :=
           (for some R of Used => Undefined_In (R.Pattern));
      begin
         for J in 1 .. Natural (Used.Length) loop
            declare
               At_Rule : constant Natural :=
                 By_Name (To_String (Used (J).Name));
               Pat     : Element_Vectors.Vector := Rules (At_Rule).Pattern;
            begin
               --  A name nothing defines matches anything as far as a union
               --  can tell, so while one is missing the unions are left alone;
               --  the missing name is what is reported.
               if not Any_Undefined then
                  Check_Unions
                    (Pat, At_Rule, Look.Follow (At_Rule),
                     Is_Char_Rule (Rules, To_String (Used (J).Name)));
                  if not Element_Vectors."=" (Pat, Rules (At_Rule).Pattern)
                  then
                     declare
                        R : Rule := Rules (At_Rule);
                     begin
                        R.Pattern := Pat;
                        Rules.Replace_Element (At_Rule, R);
                     end;
                  end if;
               end if;
            end;
            --  Only where nothing is skipped between elements: with `ws`
            --  skipped as well, what text can follow what is not decided here.
            if Rules (By_Name (To_String (Used (J).Name))).Whitespace
              = Null_Unbounded_String
            then
               Check_Greedy
                 (Rules (By_Name (To_String (Used (J).Name))).Pattern,
                  By_Name (To_String (Used (J).Name)),
                  Element_Vectors.Empty_Vector);
            end if;
            --  An exception with a phrase on one side parses that side as a
            --  rule; a built-in type has no rule to parse.
            if Excepts.Contains (To_String (Used (J).Name))
              and then not Except_Is_Token (Rules, To_String (Used (J).Name))
            then
               declare
                  X : constant String := To_String (Used (J).Name);
               begin
                  for Side in 1 .. 2 loop
                     declare
                        Op : constant String :=
                          (if Side = 1 then Except_Bases.Element (X)
                           else Excepts.Element (X));
                     begin
                        if Is_Core_Name (Op) then
                           Report ("in rule `" & X & "`: `" & Op & "` is a "
                                   & "built-in type, and `"
                                   & Except_Bases.Element (X) & " - "
                                   & Excepts.Element (X) & "` has a phrase "
                                   & "(a rule that skips whitespace, or is "
                                   & "code) on the other side" & ASCII.LF
                                   & "  In `a - b` that has a phrase on a "
                                   & "side, both sides are parsed as rules: "
                                   & "give the built-in a rule of its own, "
                                   & "`w = " & Op & "`, and write `w`");
                        end if;
                     end;
                  end loop;
               end;
            end if;
            Check_Prose (Used (J).Pattern, To_String (Used (J).Name));
            Check_Undefined (Used (J).Pattern, To_String (Used (J).Name));
            --  `str`, `atom`, `word`, `int`, `bool`, `flag`, `uN` and `iN` are
            --  the built-in types: a reference to one is a scalar, in every
            --  backend.  A character rule of that name is a scanner for the
            --  same scalar and is the way to widen one (obconf does), but a
            --  rule that builds a struct under such a name would be read as the
            --  scalar in some places and as the struct in others.
            if Is_Core_Name (To_String (Used (J).Name))
              and then Used (J).Jet_Code = Null_Unbounded_String
              and then not Is_Char_Rule (Rules, To_String (Used (J).Name))
              and then (for some E of Used (J).Pattern =>
                          E.Kind = Name or else E.Kind = Group)
            then
               Report ("rule `" & To_String (Used (J).Name) & "` has the name "
                       & "of a built-in type" & ASCII.LF
                       & "  In an RFC, `" & To_String (Used (J).Name)
                       & "` is an ordinary rule, and may build a structure "
                       & "(RFC 5322: `atom = [CFWS] 1*atext [CFWS]`).  In "
                       & "hbnf `str`, `atom`, `word`, `int`, `bool`, `flag` "
                       & "and the sized `u8`..`i64` are built-in types "
                       & "that read as one value, so a rule with such a name "
                       & "cannot be a structure.  Give the rule another name, "
                       & "`" & To_String (Used (J).Name) & "-rule`, and use "
                       & "that name wherever the grammar refers to it");
            end if;
            --  ABNF's rule names ignore case, and so do the identifiers
            --  the backends make of them (TOK_DIGIT, Digit): two rules
            --  whose names differ only in case would be one name there.
            declare
               K : constant String := To_Lower (To_String (Used (J).Name));
            begin
               if Lower.Contains (K)
                 --  A dialect's prefix keeps a rule `WORD` apart from the
                 --  built-in `word`, which has none.
                 and then not ((Flag_Dialect /= Null_Unbounded_String
                                or else File_Dialect /= Null_Unbounded_String)
                               and then
                                 (Is_Core_Name (To_String (Used (J).Name))
                                  or else Is_Core_Name
                                    (To_String (Used (Lower (K)).Name))))
               then
                  Report ("rules `" & To_String (Used (Lower (K)).Name)
                          & "` and `" & To_String (Used (J).Name)
                          & "` differ only in case; ABNF reads them as one "
                          & "name, and so would the generated code");
               else
                  Lower.Include (K, J);
               end if;
            end;
         end loop;
      end;
      --  Single code points in the other rules, now the checks are done.
      declare
         Used : Path_Sets.Set;

         --  A character rule, as HBNF_Compilable.Is_Char_Rule decides: a
         --  sequence/alternation of ranges, plain literals and references
         --  to other character rules (repetition allowed).  Its Char_Range
         --  terminals stay ranges; a single code point elsewhere becomes a
         --  literal.
         function Is_Char (N : String; Depth : Natural) return Boolean is
            --  A character class: every branch matches one code point, with
            --  no repetition.  Repetition is valid only over a class.
            function Is_Class (N : String; Depth : Natural) return Boolean is
            begin
               if Depth = 0 or else not By_Name.Contains (N) then
                  return False;
               end if;
               declare
                  R : constant Rule := Rules (By_Name (N));
               begin
                  if R.Jet_Code /= Null_Unbounded_String
                    or else R.Pattern.Is_Empty
                  then
                     return False;
                  end if;
                  declare
                     In_Branch : Natural := 0;
                  begin
                     for E of R.Pattern loop
                        if E.Kind = Alt then
                           In_Branch := 0;
                        else
                           if E.Min /= 1 or else E.Max /= 1 then
                              return False;   --  a class has no repetition
                           end if;
                           In_Branch := In_Branch + 1;
                           if In_Branch > 1 then
                              return False;   --  more than one code point
                           end if;
                           case E.Kind is
                              when Char_Range =>
                                 null;
                              when Literal =>
                                 if E.No_Case
                                   or else To_String (E.Lit)'Length /= 1
                                 then
                                    return False;
                                 end if;
                              when Name =>
                                 if not Is_Class
                                   (To_String (E.Name), Depth - 1)
                                 then
                                    return False;
                                 end if;
                              when others =>
                                 return False;
                           end case;
                        end if;
                     end loop;
                     return In_Branch = 1;
                  end;
               end;
            end Is_Class;
         begin
            if Depth = 0 or else not By_Name.Contains (N) then
               return False;
            end if;
            declare
               R : constant Rule := Rules (By_Name (N));
            begin
               if R.Jet_Code /= Null_Unbounded_String or else R.Pattern.Is_Empty
               then
                  return False;
               end if;
               declare
                  Has_Anchor : Boolean := False;
               begin
                  for E of R.Pattern loop
                     case E.Kind is
                        when Char_Range =>
                           Has_Anchor := True;
                        when Alt =>
                           null;
                        when Literal =>
                           if E.No_Case and then Letter_Count (E.Lit) > 4 then
                              return False;
                           end if;
                           --  A repeated literal is a run of that one code
                           --  point; a longer one stays a list.
                           if (E.Min /= 1 or else E.Max /= 1)
                             and then To_String (E.Lit)'Length /= 1
                           then
                              return False;
                           end if;
                        when Name =>
                           if not Is_Char (To_String (E.Name), Depth - 1) then
                              return False;
                           end if;
                           Has_Anchor := True;
                           --  A repeated reference is a run of a character
                           --  class; a longer sequence stays a list.
                           if (E.Min /= 1 or else E.Max /= 1)
                             and then not Is_Class
                               (To_String (E.Name), Depth - 1)
                           then
                              return False;
                           end if;
                        when others =>
                           return False;
                     end case;
                  end loop;
                  return Has_Anchor;
               end;
            end;
         end Is_Char;

         function UTF8 (C : Natural) return String is
            function B (X : Natural) return Character is (Character'Val (X));
         begin
            if C < 16#80# then
               return [1 => B (C)];
            elsif C < 16#800# then
               return [B (16#C0# + C / 64), B (16#80# + C mod 64)];
            elsif C < 16#10000# then
               return [B (16#E0# + C / 4096), B (16#80# + (C / 64) mod 64),
                       B (16#80# + C mod 64)];
            else
               return [B (16#F0# + C / 262144),
                       B (16#80# + (C / 4096) mod 64),
                       B (16#80# + (C / 64) mod 64), B (16#80# + C mod 64)];
            end if;
         end UTF8;

         function Hex (C : Natural) return String is
            D : constant String := "0123456789ABCDEF";
         begin
            if C < 16 then
               return [D (C + 1)];
            end if;
            return Hex (C / 16) & D (C mod 16 + 1);
         end Hex;

         Lifted_Ranges : Rule_Vectors.Vector;

         procedure Literalize (V : in out Element_Vectors.Vector;
                               In_Rule : String; Is_Used : Boolean) is
         begin
            for I in 1 .. Natural (V.Length) loop
               declare
                  E : constant Element_Access := V (I);
               begin
                  if E.Kind = Char_Range then
                     if E.Lo = E.Hi then
                        V.Replace_Element
                          (I, new Element'(Kind => Literal, Min => E.Min,
                                           Max => E.Max,
                                           Has_Value => False, Value => 0,
                                           Lit => To_Unbounded_String
                                                    (UTF8 (E.Lo)),
                                           No_Case => False));
                     elsif Is_Used then
                        --  A range in a rule that also names other rules is
                        --  not matched there; it is a rule of its own, and
                        --  the reader writes that rule: `dtext = %x21-5A /
                        --  obs-dtext` is `dtext = dtext-x21-5A / obs-dtext`
                        --  with `dtext-x21-5A = %x21-5A`.
                        declare
                           Fresh : constant String :=
                             In_Rule & "-x" & Hex (E.Lo) & "-" & Hex (E.Hi);
                        begin
                           if not By_Name.Contains (Fresh)
                             and then not (for some R of Lifted_Ranges =>
                                             To_String (R.Name) = Fresh)
                           then
                              declare
                                 Pat : Element_Vectors.Vector;
                              begin
                                 Pat.Append
                                   (new Element'(Kind => Char_Range, Min => 1,
                                                 Max => 1, Lo => E.Lo,
                                                 Hi => E.Hi));
                                 Lifted_Ranges.Append
                                   (Rule'(Name => To_Unbounded_String (Fresh),
                                          Pattern => Pat,
                                          Leading_Comment => Null_Unbounded_String,
                                          Trailing_Comment => Null_Unbounded_String,
                                          Jet_Code => Null_Unbounded_String,
                                          Action_Code => Null_Unbounded_String,
                                          Left_Bases => 0,
                                          Whitespace => Null_Unbounded_String));
                              end;
                           end if;
                           V.Replace_Element
                             (I, new Element'(Kind => Name, Min => E.Min,
                                              Max => E.Max,
                                              Name => To_Unbounded_String (Fresh),
                                              Fold => False, Args => Null_Unbounded_String));
                        end;
                     end if;
                  elsif E.Kind = Group then
                     Literalize (E.Items, In_Rule, Is_Used);
                  end if;
               end;
            end loop;
         end Literalize;
      begin
         for R of Reachable (Rules) loop
            Used.Include (To_String (R.Name));
         end loop;
         for J in 1 .. Natural (Rules.Length) loop
            declare
               N : constant String := To_String (Rules (J).Name);
            begin
               if not Is_Char (N, 32) then
                  Literalize (Rules (J).Pattern, N, Used.Contains (N));
               end if;
            end;
         end loop;
         for R of Lifted_Ranges loop
            Rules.Append (R);
            By_Name.Include (To_String (R.Name), Natural (Rules.Length));
         end loop;
      end;
      if Problems /= Null_Unbounded_String then
         Fail (To_String (Problems));
      end if;


      --  A hidden rule is matched and keeps nothing; that is a text rule's way of
      --  being read, so a rule that builds structure cannot be one.
      for R of Rules loop
         if Is_Hidden (To_String (R.Name)) then
            if R.Name = Rules (1).Name then
               raise Parse_Error with
                 "`" & To_String (R.Name) & "` is hidden, and it is the rule the "
                 & "grammar starts from: the tree would be empty";
            elsif R.Jet_Code = Null_Unbounded_String
              and then not Is_Char_Rule (Rules, To_String (R.Name))
            then
               raise Parse_Error with
                 "`" & To_String (R.Name) & "` is hidden, but it builds structure, "
                 & "and only a rule that is just text can keep nothing.  Hide the "
                 & "text rules it is made of, or leave `hidden` off it";
            end if;
         end if;
      end loop;
      for N of Hidden_Bases loop
         if Index_Of (Rules, N) = 0
           and then not (for some R of Rules =>
                           (To_String (R.Name)'Length > N'Length
                            and then To_String (R.Name)
                                       (1 .. N'Length + 1) = N & "_"))
         then
            Warn_Once ("hidden:" & N, "",
                       "`hidden " & N & "` names no rule in this grammar");
         end if;
      end loop;

      --  A rule that is only text except for a lookahead is read a character at a time:
      --  the lookahead keeps it from being one token, so the parser makes a tree node
      --  for each piece instead of scanning the whole run.  Say so where the author
      --  can still change it.
      declare
         function Has_Block (Els : Element_Vectors.Vector) return Boolean is
         begin
            for E of Els loop
               if (E.Kind = Block and then not E.Look.Is_Empty)
                 or else (E.Kind = Group and then Has_Block (E.Items))
               then
                  return True;
               end if;
            end loop;
            return False;
         end Has_Block;

         --  Only a rule that repeats text costs a node per piece.
         function Repeats (Els : Element_Vectors.Vector) return Boolean is
         begin
            for E of Els loop
               if E.Kind in Name | Literal | Char_Range | Group
                 and then (E.Min /= 1 or else E.Max /= 1)
               then
                  return True;
               end if;
               if E.Kind = Group and then Repeats (E.Items) then
                  return True;
               end if;
            end loop;
            return False;
         end Repeats;

         function Text_Shaped (Els : Element_Vectors.Vector) return Boolean is
         begin
            for E of Els loop
               case E.Kind is
                  when Literal | Char_Range | Alt =>
                     null;
                  when Block =>
                     if E.Look.Is_Empty then
                        return False;     --  a test or %spaces, not text
                     end if;
                  when Group =>
                     if not Text_Shaped (E.Items) then
                        return False;
                     end if;
                  when Name =>
                     if E.Args /= Null_Unbounded_String
                       or else not (Is_Core_Name (To_String (E.Name))
                                    or else Is_Char_Rule (Rules, To_String (E.Name)))
                     then
                        return False;
                     end if;
                  when others =>
                     return False;
               end case;
            end loop;
            return True;
         end Text_Shaped;
      begin
         for R of Rules loop
            if R.Jet_Code = Null_Unbounded_String
              and then R.Whitespace = Null_Unbounded_String
              and then Has_Block (R.Pattern)
              and then Repeats (R.Pattern)
              and then Text_Shaped (R.Pattern)
              and then not Is_Char_Rule (Rules, To_String (R.Name))
            then
               Warn_Once ("text-lookahead:" & To_String (R.Name), "",
                          "`" & To_String (R.Name) & "` is only text, but its lookahead "
                          & "(`&` or `!`) keeps it from being one token, so it is read a "
                          & "character at a time and builds a tree node for each.  "
                          & "Write the character it looks at as part of the rule "
                          & "(`"":"" safe` for `"":"" &safe`) to make it a token");
            end if;
         end loop;
      end;
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
           new Element'(Kind => Alt, Min => 1, Max => 1, Guard => 0, Union => True);
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
      Jet_Tag   : Unbounded_String := Null_Unbounded_String;   --  c, rust, zig, ada
      --  This file's own: its `language` (C when it has none) and the line
      --  that set it, its header code blocks, and the keywords it lists.
      File_Lang : Unbounded_String := To_Unbounded_String ("C");
      Lang_Line : Natural := 0;
      Head_Code : Word_Vectors.Vector;
      Late_Code : Word_Vectors.Vector;   --  after the file's last `include`: its epilogue
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
      File_No_Case := Abnf_Mode;
      File_Fold_Names := False;
      --  `ws` (the classic blanks) is the default until a `whitespace`
      --  directive names another rule; the C emitter generates a built-in
      --  `ws` scanner when the grammar does not define one of its own.
      --  Under `--abnf` nothing is skipped, as in RFC 5234.
      File_Whitespace :=
        (if Abnf_Mode then Null_Unbounded_String
         else To_Unbounded_String ("ws"));
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
           or else (Cur (P).Kind = T_Pct
                    and then To_String (Cur (P).Text) in "token" | "start" | "")
           or else (Cur (P).Kind = T_Name
                    and then (To_String (Cur (P).Text) = "language"
                              or else To_String (Cur (P).Text) = "prefix"
                              or else To_String (Cur (P).Text) = "rollback"
                              or else To_String (Cur (P).Text) = "layout"
                              or else To_String (Cur (P).Text) = "layout_ops"
                              or else To_String (Cur (P).Text) = "flat"
                              or else To_String (Cur (P).Text) = "statements"
                              or else To_String (Cur (P).Text) = "context"
                              or else To_String (Cur (P).Text) = "macros"
                              or else To_String (Cur (P).Text) = "includes"
                              or else To_String (Cur (P).Text) = "sensitivity"
                              or else To_String (Cur (P).Text) = "dialect"
                              or else To_String (Cur (P).Text) = "whitespace"
                              or else To_String (Cur (P).Text) = "keywords"
                              or else (To_String (Cur (P).Text) = "hidden"
                                       and then P.Pos + 2 <= Natural (P.Toks.Length)
                                       and then P.Toks (P.Pos + 1).Kind = T_Name
                                       and then P.Toks (P.Pos + 2).Kind
                                                  not in T_Eq | T_Eq_Slash)))
         then
            P.Pos := Mark;
            loop
               while Cur (P).Kind in T_Newline | T_Comment loop
                  Next (P);
               end loop;
               if Cur (P).Kind = T_Code then
                  if Epilogue_After_Line > 0 and then Cur (P).Line > Epilogue_After_Line then
                     Late_Code.Append (Cur (P).Text);
                  else
                     Head_Code.Append (Cur (P).Text);
                  end if;
                  Next (P);
               elsif Cur (P).Kind = T_Pct
                 and then To_String (Cur (P).Text) = "token"
               then
                  --  yacc's `%token NAME ...`: names the parser's lexer is
                  --  to supply.  hbnf reads characters, so each is a rule;
                  --  the declaration is remembered so that a name nothing
                  --  defines can be told how to be.  POSIX writes each
                  --  token's spelling in a comment under the line
                  --  (`/* '&&' '||' */`), which is taken for the message.
                  declare
                     First_Of_Line : constant Natural :=
                       Natural (Declared_Tokens.Length) + 1;
                     Line_No       : constant Positive := Cur (P).Line;
                  begin
                     Next (P);
                     while Cur (P).Kind = T_Name
                       and then Cur (P).Line = Line_No
                     loop
                        Declared_Tokens.Append
                          (Declared_Token'
                             (Name     => Cur (P).Text,
                              Spelling => Null_Unbounded_String,
                              Line     => Cur (P).Line));
                        Next (P);
                     end loop;
                     if Cur (P).Kind = T_Newline
                       and then P.Toks (P.Pos + 1).Kind = T_Comment
                     then
                        declare
                           C   : constant String :=
                             To_String (P.Toks (P.Pos + 1).Text);
                           N   : Natural := 0;
                           K   : Natural := C'First;
                           All_Quoted : Boolean := True;
                           Words : String_Lists.Vector;
                        begin
                           while K <= C'Last loop
                              if C (K) = ''' then
                                 declare
                                    E : Natural := K + 1;
                                 begin
                                    while E <= C'Last and then C (E) /= ''' loop
                                       E := E + 1;
                                    end loop;
                                    exit when E > C'Last;
                                    Words.Append
                                      (To_Unbounded_String (C (K + 1 .. E - 1)));
                                    N := N + 1;
                                    K := E + 1;
                                 end;
                              elsif C (K) in ' ' | ASCII.HT then
                                 K := K + 1;
                              else
                                 All_Quoted := False;
                                 exit;
                              end if;
                           end loop;
                           if All_Quoted
                             and then N = Natural (Declared_Tokens.Length)
                                           - First_Of_Line + 1
                           then
                              for W in 1 .. N loop
                                 Declared_Tokens.Reference
                                   (First_Of_Line + W - 1).Spelling :=
                                   Words (W);
                              end loop;
                              Next (P);
                              Next (P);
                           end if;
                        end;
                     end if;
                  end;
               elsif Cur (P).Kind = T_Pct
                 and then To_String (Cur (P).Text) = "start"
               then
                  --  yacc's `%start NAME`: the rule the grammar starts from.
                  --  `--root=` still wins.
                  Next (P);
                  if Cur (P).Kind /= T_Name then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":"
                       & Integer'Image (Cur (P).Col)
                       & ": %start takes the name of the rule to start from";
                  end if;
                  if Root_Rule = Null_Unbounded_String then
                     Root_Rule := Cur (P).Text;
                  end if;
                  Next (P);
               elsif Cur (P).Kind = T_Pct and then Cur (P).Text = Null_Unbounded_String
                 and then P.Toks (P.Pos + 1).Kind = T_Pct
                 and then P.Toks (P.Pos + 1).Text = Null_Unbounded_String
               then
                  --  yacc's `%%`, which ends the declarations: nothing to do.
                  Next (P);
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
                 and then P.Toks (P.Pos + 1).Kind = T_Meta
               then
                  declare
                     N : constant String := To_String (Cur (P).Text);
                  begin
                     if Domain_Bodies.Contains (N) then
                        raise Parse_Error with
                          Integer'Image (Cur (P).Line) & ": 1: the domain `" & N
                          & "` is defined twice";
                     end if;
                     --  What follows `::=` is numbers, words and other domains
                     --  joined by `|`; anything else is a rule written for a
                     --  notation that uses `::=` as `=` does.
                     declare
                        B   : constant String := To_String (P.Toks (P.Pos + 1).Text);
                        Pos : Natural := B'First;
                        Ok  : Boolean := True;
                        In_Q : Boolean := False;
                        Item_Start : Boolean := True;
                     begin
                        while Pos <= B'Last loop
                           declare
                              C : constant Character := B (Pos);
                           begin
                              if C = '"' then
                                 In_Q := not In_Q;
                              elsif not In_Q then
                                 if C in '|' | '/' then
                                    Item_Start := True;
                                 elsif C in ' ' | ASCII.HT then
                                    null;
                                 else
                                    if Item_Start
                                      and then C not in '0' .. '9' | '-' | '"'
                                        | 'a' .. 'z' | 'A' .. 'Z' | '_'
                                    then
                                       Ok := False;
                                    elsif C in '<' | '>' | '(' | ')' | '[' | ']'
                                      | '*' | '%' | '{' | '}' | '~' | '!' | '&'
                                    then
                                       Ok := False;
                                    end if;
                                    Item_Start := False;
                                 end if;
                              end if;
                           end;
                           Pos := Pos + 1;
                        end loop;
                        if not Ok or else In_Q then
                           raise Parse_Error with
                             Integer'Image (Cur (P).Line) & ": 1: `" & N
                             & " ::=` defines a domain in hbnf (numbers, "
                             & "words, other domains), and this is not one.  "
                             & "For BNF, where `::=` defines a rule, begin "
                             & "the file with the line `dialect bnf`";
                        end if;
                     end;
                     Domain_Bodies.Insert (N, To_String (P.Toks (P.Pos + 1).Text));
                  end;
                  Next (P);
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "dialect"
               then
                  --  `dialect bnf | ebnf | abnf | ybnf | hbnf`: the notation
                  --  this file is written in, one notation read in its
                  --  dialects.  The lexer has read abnf and ebnf already (a
                  --  backslash, a `;`, a `{`); here `abnf` also says nothing
                  --  is skipped between a rule's elements and a string is
                  --  case-insensitive, which later directives may still
                  --  change.  The others change nothing more: their
                  --  spellings are read in every file.
                  Next (P);
                  if Cur (P).Kind /= T_Name
                    or else To_String (Cur (P).Text)
                            not in "bnf" | "ebnf" | "abnf" | "ybnf" | "hbnf"
                  then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":"
                       & Integer'Image (Cur (P).Col)
                       & ": `dialect` takes `bnf`, `ebnf` (ISO 14977), "
                       & "`abnf` (RFC 5234), `ybnf` (yacc and bison) or "
                       & "`hbnf` (this notation, the default)";
                  end if;
                  if File_Dialect = Null_Unbounded_String then
                     File_Dialect := Cur (P).Text;
                  end if;
                  if To_String (Cur (P).Text) = "abnf" then
                     File_No_Case := True;
                     File_Whitespace := Null_Unbounded_String;
                  end if;
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
                 and then To_String (Cur (P).Text) = "flat"
                 and then P.Pos + 1 <= Natural (P.Toks.Length)
                 and then P.Toks (P.Pos + 1).Kind = T_Name
               then
                  --  `flat ikey mapent`: under `layout tape` these rules keep their children and
                  --  write no node of their own.  The tree is as it was.
                  Next (P);
                  while Cur (P).Kind = T_Name loop
                     declare
                        Fl : constant String := To_String (Cur (P).Text);
                        Stop : Natural := Fl'First;
                     begin
                        while Stop <= Fl'Last and then Fl (Stop) /= '(' loop
                           Stop := Stop + 1;
                        end loop;
                        Flat_Bases.Include (Fl (Fl'First .. Stop - 1));
                     end;
                     Next (P);
                  end loop;
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "hidden"
                 and then P.Pos + 1 <= Natural (P.Toks.Length)
                 and then P.Toks (P.Pos + 1).Kind = T_Name
                 and then not (P.Pos + 2 <= Natural (P.Toks.Length)
                               and then P.Toks (P.Pos + 2).Kind in T_Eq | T_Eq_Slash)
               then
                  --  `hidden nl gap sep`: these rules are matched and keep nothing
                  --  in the tree.  Each is hidden, with every instance of it if it
                  --  is a hyperrule.
                  Next (P);
                  while Cur (P).Kind = T_Name loop
                     declare
                        Hd : constant String := To_String (Cur (P).Text);
                        Stop : Natural := Hd'First;
                     begin
                        while Stop <= Hd'Last and then Hd (Stop) /= '(' loop
                           Stop := Stop + 1;
                        end loop;
                        Hidden_Bases.Include (Hd (Hd'First .. Stop - 1));
                     end;
                     Next (P);
                  end loop;
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "whitespace"
                 and then Ends_Directive (P, 2)
               then
                  --  `whitespace ws`, per file: phrase rules in this file skip
                  --  the char rule ws between their elements; char rules never
                  --  do.  RFC grammars that write their whitespace explicitly say
                  --  `whitespace none`, since the default is `ws`.
                  Next (P);
                  if Cur (P).Kind /= T_Name then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" &
                       Integer'Image (Cur (P).Col) &
                       ": expected a char-rule name after `whitespace`";
                  end if;
                  --  `whitespace none`: this file's phrase rules skip nothing,
                  --  as an RFC's ABNF reads: where a space counts, it is written.
                  File_Whitespace :=
                    (if To_String (Cur (P).Text) = "none"
                     then Null_Unbounded_String else Cur (P).Text);
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "prefix"
               then
                  --  `prefix "pf_"`: put in front of every generated type
                  --  and struct tag, keeping them out of the system's names.
                  --  `prefix none`: generated identifiers keep the rules'
                  --  names (no `bnf_` or dialect prefix).
                  Next (P);
                  if Cur (P).Kind = T_Name
                    and then To_String (Cur (P).Text) = "none"
                  then
                     No_Name_Prefix := True;
                     Next (P);
                  else
                     if Cur (P).Kind /= T_String
                       or else not Valid_Prefix (To_String (Cur (P).Text))
                     then
                        raise Parse_Error with
                          Integer'Image (Cur (P).Line) & ":" &
                          Integer'Image (Cur (P).Col) &
                          ": expected a quoted C identifier prefix or `none` "
                          & "after `prefix`";
                     end if;
                     --  --prefix= wins over it (Set_Type_Prefix).
                     Set_Directive (Type_Prefix_Code, "prefix",
                                    To_String (Cur (P).Text), Cur (P).Line);
                     Next (P);
                  end if;
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "layout"
               then
                  --  `layout tape`: the parser writes a flat tape, not the tree (RFCPLAN.md step 17);
                  --  `layout ast` is what it does without.  --layout= wins over the directive.
                  Next (P);
                  if Cur (P).Kind /= T_Name then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" & Integer'Image (Cur (P).Col)
                       & ": expected the name of a layout after `layout`: `ast`, `tape`, or a "
                       & "directory layouts/NAME (layout.hbnf)";
                  end if;
                  if not Layout_Given then
                     Layout_Text := Cur (P).Text;
                  end if;
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "rollback"
               then
                  --  `rollback { tape_n }`: the state the grammar's `%emit` blocks change, as C
                  --  lvalues separated by commas.  An emit is undone by putting these back to
                  --  what they were, so a part that is tried and given up costs one store each,
                  --  as dropping what is on a Forth stack does.
                  Next (P);
                  if Cur (P).Kind /= T_Code then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" & Integer'Image (Cur (P).Col)
                       & ": expected a code block after `rollback`, the state that an "
                       & "%emit changes: `rollback { tape_n }`";
                  end if;
                  if Length (Rollback_Text) > 0 then
                     Append (Rollback_Text, ",");
                  end if;
                  Append (Rollback_Text, Cur (P).Text);
                  Next (P);
               elsif Cur (P).Kind = T_Name
                 and then To_String (Cur (P).Text) = "layout_ops"
               then
                  --  `layout_ops { head { … } entry { … } … }`: the raw C for each list operation.  The block is re-lexed to read the
                  --  `op { … }` pairs; each op is optional.
                  Next (P);
                  if Cur (P).Kind /= T_Code then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" &
                       Integer'Image (Cur (P).Col) &
                       ": expected a code block after `layout_ops`";
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
                             "layout_ops: expected an operation name (head, "
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
                                "layout_ops: expected a code block after `"
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
                 and then To_String (Cur (P).Text) = "context"
               then
                  --  `context types templates`: names of contexts.
                  declare
                     At_Line : constant Positive := Cur (P).Line;
                  begin
                     Next (P);
                     if Cur (P).Kind /= T_Name or else Cur (P).Line /= At_Line
                     then
                        raise Parse_Error with
                          Integer'Image (At_Line) & ": `context` takes the "
                          & "names of the contexts: `context types`";
                     end if;
                     while Cur (P).Kind = T_Name and then Cur (P).Line = At_Line
                     loop
                        Context_Words.Append (Cur (P).Text);
                        Next (P);
                     end loop;
                  end;
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
                           or else To_String (Cur (P).Text) = "includes")
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
                          & "a rule name"
                          & " after `" & D & "`";
                     end if;
                     if D = "macros" then
                        Set_Directive (Macros_Name, D,
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
      for C of Late_Code loop
         Epilogue_Pieces.Append (Code_Piece'(Lang => File_Lang, Code => C));
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
            --  `hidden nl = ...`: the rule keeps nothing in the tree (see the
            --  `hidden` directive).
            if Cur (P).Kind = T_Name and then To_String (Cur (P).Text) = "hidden"
              and then P.Pos + 2 <= Natural (P.Toks.Length)
              and then P.Toks (P.Pos + 1).Kind = T_Name
              and then P.Toks (P.Pos + 2).Kind in T_Eq | T_Eq_Slash
            then
               declare
                  Hd   : constant String := To_String (P.Toks (P.Pos + 1).Text);
                  Stop : Natural := Hd'First;
               begin
                  while Stop <= Hd'Last and then Hd (Stop) /= '(' loop
                     Stop := Stop + 1;
                  end loop;
                  Hidden_Bases.Include (Hd (Hd'First .. Stop - 1));
               end;
               Next (P);
            end if;

            --  `name :: type = ...`: the rule has a value of that C type.  The type is the words
            --  and `*`s up to the `=`, or one `{ }` block; it is taken out of the token stream
            --  here, so the rest of the head reads as `name =`.
            if Cur (P).Kind = T_Name
              and then P.Pos + 2 <= Natural (P.Toks.Length)
              and then P.Toks (P.Pos + 1).Kind = T_Name
              and then To_String (P.Toks (P.Pos + 1).Text) = "::"
            then
               declare
                  Nm   : constant String := To_String (Cur (P).Text);
                  Stop : Natural := Nm'First;
                  K    : Positive := P.Pos + 2;
                  Ty   : Unbounded_String;
               begin
                  while Stop <= Nm'Last and then Nm (Stop) /= '(' loop
                     Stop := Stop + 1;
                  end loop;
                  while P.Toks (K).Kind not in T_Eq | T_Eq_Slash | T_Newline | T_EOF loop
                     case P.Toks (K).Kind is
                        when T_Name | T_Code =>
                           if Ty /= Null_Unbounded_String then
                              Append (Ty, " ");
                           end if;
                           Append (Ty, P.Toks (K).Text);
                        when T_Star =>
                           Append (Ty, "*");
                        when others =>
                           raise Parse_Error with
                             Integer'Image (P.Toks (K).Line) & ":" & Integer'Image (P.Toks (K).Col)
                             & ": expected the C type of the value after `::`";
                     end case;
                     K := K + 1;
                  end loop;
                  if Ty = Null_Unbounded_String or else P.Toks (K).Kind not in T_Eq | T_Eq_Slash then
                     raise Parse_Error with
                       Integer'Image (Cur (P).Line) & ":" & Integer'Image (Cur (P).Col)
                       & ": expected `name :: type =`, the type then the `=`";
                  end if;
                  Value_Types.Include (Nm (Nm'First .. Stop - 1), To_String (Ty));
                  P.Toks.Delete (P.Pos + 1, Ada.Containers.Count_Type (K - (P.Pos + 1)));
               end;
            end if;

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
            declare
               Op : constant String := To_String (P.Toks (P.Pos + 1).Text);
               Hd : constant String := To_String (Name);
            begin
               if Op = "=" and then (for some C of Hd => C = '(') then
                  raise Parse_Error with
                    Integer'Image (Cur (P).Line) & ":" & Integer'Image (Cur (P).Col)
                    & ": `" & Hd & "` has parameters, and a rule with "
                    & "parameters is defined with `:=`, as the ALGOL 68 Report "
                    & "writes a hyperrule: `" & Hd & " := ...`";
               elsif Op = ":=" and then not (for some C of Hd => C = '(') then
                  raise Parse_Error with
                    Integer'Image (Cur (P).Line) & ":" & Integer'Image (Cur (P).Col)
                    & ": `:=` defines a rule with parameters (a hyperrule), "
                    & "and `" & Hd & "` has none; write `" & Hd & " = ...`.  "
                    & "To read BNF, where `:=` or `::=` defines an ordinary "
                    & "rule, begin the file with the line `dialect bnf`";
               end if;
            end;
            Next (P);
            Next (P);   --  the '='

            --  `name = %scan{ code }` is a jet, as `name = { code }` is.
            if Cur (P).Kind = T_Pct and then To_String (Cur (P).Text) = "scan"
              and then P.Pos + 1 <= Natural (P.Toks.Length)
              and then P.Toks (P.Pos + 1).Kind = T_Code
            then
               Next (P);
            end if;
            --  `<name> = Rust { code }`: a scanner for one backend.  C, Rust,
            --  Zig and Ada may each be given, as separate lines.
            Jet_Tag := Null_Unbounded_String;
            declare
               Tag : Unbounded_String := Null_Unbounded_String;
            begin
               if Cur (P).Kind = T_Name
                 and then P.Pos + 1 <= Natural (P.Toks.Length)
                 and then P.Toks (P.Pos + 1).Kind = T_Code
                 and then Ada.Characters.Handling.To_Lower
                            (To_String (Cur (P).Text))
                          in "c" | "rust" | "zig" | "ada"
               then
                  Tag := To_Unbounded_String
                    (Ada.Characters.Handling.To_Lower
                       (To_String (Cur (P).Text)));
                  Next (P);
               end if;
               Jet_Tag := Tag;
            end;
            if Cur (P).Kind = T_Code then
               --  A jet: `name = { <code> }` — a hand-written scanner.
               if Jet_Tag /= "c" and then Jet_Tag /= Null_Unbounded_String then
                  declare
                     Ent : Jet_Entry :=
                       (if Jets.Contains (To_String (Name))
                        then Jets.Element (To_String (Name)) else (others => <>));
                  begin
                     if Jet_Tag = "rust" then Ent.Rust := Cur (P).Text;
                     elsif Jet_Tag = "zig" then Ent.Zig := Cur (P).Text;
                     else Ent.Ada := Cur (P).Text;
                     end if;
                     Jets.Include (To_String (Name), Ent);
                  end;
               end if;
               Define
                 (Rules, Index,
                  Rule'(Name            => Name,
                        Pattern         => Element_Vectors.Empty_Vector,
                        Leading_Comment => Leading,
                        Trailing_Comment => Trailing,
                        Jet_Code        =>
                          (if Jet_Tag = "c" or else Jet_Tag = Null_Unbounded_String
                           then Cur (P).Text
                           elsif Index.Contains (To_String (Name))
                             and then Rules (Index (To_String (Name))).Jet_Code
                                      /= Null_Unbounded_String
                           then Rules (Index (To_String (Name))).Jet_Code
                           else To_Unbounded_String (No_C_Code)),
                        Action_Code     => Null_Unbounded_String,
                        Left_Bases      => 0,
                        Whitespace      => File_Whitespace));
               Standing.Include
                 (To_String (Name),
                  Standing_Rule'(R   => Rules (Index (To_String (Name))),
                                 Raw => Element_Vectors.Empty_Vector));
               Next (P);
            else
               declare
                  Action  : Unbounded_String := Null_Unbounded_String;
                  Pattern : Element_Vectors.Vector := Parse_Body (P);
                  Raw     : constant Element_Vectors.Vector := Pattern;
                  Bases   : Natural;
               begin
                  Rewrite_Left_Recursion (Name, Name_Line, Pattern, Bases);
                  --  An action jet: `name = pattern { code }` — the code
                  --  block after the pattern is run in the bind walk, not
                  --  during parsing.  A trailing comment sits after it.
                  while Cur (P).Kind = T_Pct
                    and then To_String (Cur (P).Text) = "emit"
                    and then P.Toks (P.Pos + 1).Kind = T_Code
                  loop
                     --  `pattern %emit{ code }`: what the bit layer runs when
                     --  it writes the record.
                     Next (P);
                     if (for some E of Pattern => E.Kind = Bit_Field) then
                        Emit_Table.Include (To_String (Name),
                                            To_String (Cur (P).Text));
                     else
                        Pattern.Append
                          (new Element'(Kind => Block, Min => 1, Max => 1,
                                        Op => B_Emit, Ctx => <>, Path => <>, Id => 0,
                                        Look => <>,
                                        Code => Cur (P).Text));
                     end if;
                     Next (P);
                  end loop;
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
                  while Cur (P).Kind = T_Pct
                    and then To_String (Cur (P).Text) = "emit"
                    and then P.Toks (P.Pos + 1).Kind = T_Code
                  loop
                     Next (P);
                     if (for some E of Pattern => E.Kind = Bit_Field) then
                        Emit_Table.Include (To_String (Name),
                                            To_String (Cur (P).Text));
                     else
                        Pattern.Append
                          (new Element'(Kind => Block, Min => 1, Max => 1,
                                        Op => B_Emit, Ctx => <>, Path => <>, Id => 0,
                                        Look => <>,
                                        Code => Cur (P).Text));
                     end if;
                     Next (P);
                  end loop;
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
                           Left_Bases      => Bases,
                           Whitespace      => File_Whitespace));
                  Standing.Include
                    (To_String (Name),
                     Standing_Rule'(R   => Rules (Index (To_String (Name))),
                                    Raw => Raw));
                  if Pending_Except_B /= Null_Unbounded_String then
                     Excepts.Include (To_String (Name),
                                      To_String (Pending_Except_B));
                     Except_Bases.Include (To_String (Name),
                                           To_String (Pending_Except_A));
                     Pending_Except_B := Null_Unbounded_String;
                  else
                     Excepts.Exclude (To_String (Name));
                     Except_Bases.Exclude (To_String (Name));
                  end if;
               end;
            end if;
         end;
         <<Next_Item>>
      end loop;
      if File_Depth = 0 then
         Expand_Params (Rules);
         Check_Contexts (Rules);
         Split_Mixed (Rules);
         Split_Wire (Rules);
         Finish (Rules);
      end if;
      return Rules;
   end Parse;

   function Is_File_Layout (Name : String) return Boolean is (Name not in "ast" | "tape" | "");

   procedure Set_Layout_Dir (Dir : String) is
   begin
      Layout_Dir := To_Unbounded_String (Dir);
   end Set_Layout_Dir;

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

      --  The file of a layout, read as an include would be (once), its settings weak so that a later
      --  file, or the grammar's own, may change them.
      procedure Include_Layout (Name : String; Acc : in out Rule_Vectors.Vector;
                                Acc_Index : in out Index_Maps.Map) is
         Path : constant String := To_String (Layout_Dir) & "/" & Name & "/layout.hbnf";
      begin
         if To_String (Layout_Dir) = "" or else not Ada.Directories.Exists (Path) then
            raise Parse_Error with
              "layout `" & Name & "`: no file " & Name & "/layout.hbnf in the layouts directory"
              & (if To_String (Layout_Dir) = "" then "" else " (" & To_String (Layout_Dir) & ")")
              & "; the layouts are ast, tape, and those files";
         end if;
         if not Seen_Files.Contains (Resolved (Path)) then
            In_Layout := In_Layout + 1;
            for R of Parse_File (Path) loop
               Define (Acc, Acc_Index, R);
            end loop;
            In_Layout := In_Layout - 1;
         end if;
      end Include_Layout;

      --  `layout NAME` on a line, for a NAME that is a file: the name, else "".
      function Layout_Target (Line : String) return String is
         I : Natural := Line'First;
      begin
         while I <= Line'Last and then Line (I) in ' ' | ASCII.HT loop I := I + 1; end loop;
         if I + 6 > Line'Last or else Line (I .. I + 6) /= "layout " then
            return "";
         end if;
         I := I + 7;
         while I <= Line'Last and then Line (I) in ' ' | ASCII.HT loop I := I + 1; end loop;
         declare
            S : constant Natural := I;
         begin
            while I <= Line'Last and then Line (I) not in ' ' | ASCII.HT | ';' loop I := I + 1; end loop;
            return (if Is_File_Layout (Line (S .. I - 1)) then Line (S .. I - 1) else "");
         end;
      end Layout_Target;

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
                  Lay    : constant String := Layout_Target (Line);
               begin
                  if Lay /= "" then
                     --  a `layout NAME` line reads the layout's file, and stays, to be read as a directive
                     Include_Layout (Lay, Acc, Acc_Index);
                     Append (Kept, Line);
                     Append (Kept, ASCII.LF);
                  elsif Target /= Null_Unbounded_String then
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
      --  --layout=NAME, for a file layout, is read before the grammar is
      if File_Depth = 1 and then Layout_Given and then Is_File_Layout (To_String (Layout_Text)) then
         Include_Layout (To_String (Layout_Text), Included, Inc_Index);
      end if;
      Expand (Read_File (Path), Dir_Of (Path), Included, Inc_Index, Incs,
              Out_Text);
      Current_File := To_Unbounded_String (Path);
      Epilogue_After_Line := 0;
      for I of Incs loop
         Epilogue_After_Line := Natural'Max (Epilogue_After_Line, I.Line);
      end loop;
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
         Expand_Params (Result);
         Check_Contexts (Result);
         Split_Mixed (Result);
         Split_Wire (Result);
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
            --  becomes "grammars/obconf_ntpd.hbnf: 3: 7: …".
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
      --  A bit rule is not in Rules, but the text rules it names are needed.
      Wire_Seen : array (1 .. Natural (Wire_Store.Length)) of Boolean :=
        [others => False];

      procedure Mark (Name : Unbounded_String);

      procedure Walk (V : Element_Vectors.Vector) is
      begin
         for E of V loop
            case E.Kind is
               when Name =>
                  Mark (E.Name);
               when Group =>
                  Walk (E.Items);
               when Block =>
                  Walk (E.Look);       --  a lookahead (!x, &x) scans these
               when Bit_Field =>
                  if E.F_Ref /= Null_Unbounded_String then
                     Mark (E.F_Ref);
                  end if;
                  Walk (E.F_Alts);
               when others =>
                  null;
            end case;
         end loop;
      end Walk;

      procedure Mark (Name : Unbounded_String) is
      begin
         for K in 1 .. Natural (Wire_Store.Length) loop
            if Wire_Store (K).Name = Name then
               if not Wire_Seen (K) then
                  Wire_Seen (K) := True;
                  Walk (Wire_Store (K).Pattern);
               end if;
               return;
            end if;
         end loop;
         for I in 1 .. N loop
            if Rules (I).Name = Name then
               if not Seen (I) then
                  Seen (I) := True;
                  Walk (Rules (I).Pattern);
                  --  An exception's second operand is in no pattern.
                  if Excepts.Contains (To_String (Rules (I).Name)) then
                     Mark (To_Unbounded_String
                             (Excepts.Element (To_String (Rules (I).Name))));
                  end if;
                  --  The file's `whitespace ws` rule is needed too (the
                  --  parser scans it), even though no pattern names it.
                  if Rules (I).Whitespace /= Null_Unbounded_String then
                     Mark (Rules (I).Whitespace);
                  end if;
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

   --  A name reserved as a core type (`int`, `str`, `word`, `u8`, …).  A char
   --  rule with such a name is a token (the lexer's `int`/`str`/`word`), not a
   --  building block to inline: a rule referencing one is a phrase rule.
   function Is_Core_Name (N : String) return Boolean is
   begin
      if N = "str" or else N = "atom" or else N = "word"
        or else N = "int" or else N = "bool" or else N = "flag"
        or else N = "dec" or else N = "float"
      then
         return True;
      end if;
      return N'Length >= 2
        and then (N (N'First) = 'u' or else N (N'First) = 'i')
        and then (for all K in N'First + 1 .. N'Last => N (K) in '0' .. '9');
   end Is_Core_Name;

   --  True when S holds exactly one UTF-8 code point (a lone ASCII byte or
   --  one 2-4-byte sequence), so a literal can repeat as a run of that one
   --  character rather than a list of it.
   function Single_Code_Point (S : String) return Boolean is
      Len : Natural;
   begin
      if S'Length = 0 then
         return False;
      end if;
      declare
         B : constant Natural := Character'Pos (S (S'First));
      begin
         if B < 16#80# then
            Len := 1;
         elsif B < 16#E0# then
            Len := 2;
         elsif B < 16#F0# then
            Len := 3;
         else
            Len := 4;
         end if;
      end;
      return S'Length = Len;
   end Single_Code_Point;

   --  True when the named rule is a character class: every branch matches
   --  exactly one code point (a Char_Range, a one-code-point literal, or a
   --  reference to another class), with no repetition.  A repeated reference
   --  to a class is a run of one code point (a scanner); over anything
   --  longer it stays a list.
   function Is_Char_Class (Rules : Rule_Vectors.Vector; Nm : String)
      return Boolean is
      function Rec (N : String; Depth : Natural) return Boolean is
         J : Natural := 0;
      begin
         for I in 1 .. Natural (Rules.Length) loop
            if To_String (Rules (I).Name) = N then
               J := I;
               exit;
            end if;
         end loop;
         if J = 0 or else Depth = 0 then
            return False;
         end if;
         declare
            R : constant Rule := Rules (J);
         begin
            if R.Jet_Code /= Null_Unbounded_String
              or else Natural (R.Pattern.Length) = 0
            then
               return False;
            end if;
            declare
               In_Branch : Natural := 0;
            begin
               for E of R.Pattern loop
                  if E.Kind = Alt then
                     In_Branch := 0;
                  else
                     if E.Min /= 1 or else E.Max /= 1 then
                        return False;   --  a class has no repetition
                     end if;
                     In_Branch := In_Branch + 1;
                     if In_Branch > 1 then
                        return False;   --  more than one code point a branch
                     end if;
                     case E.Kind is
                        when Char_Range =>
                           null;
                        when Literal =>
                           --  A case-insensitive letter is still one code point
                           --  an iteration: `A` or `a`.
                           if not Single_Code_Point (To_String (E.Lit)) then
                              return False;
                           end if;
                        when Name =>
                           if not Rec (To_String (E.Name), Depth - 1) then
                              return False;
                           end if;
                        when others =>
                           return False;
                     end case;
                  end if;
               end loop;
               --  The trailing run is a branch too; it must be one code point
               --  (In_Branch is 0 only for an empty pattern, guarded above).
               return In_Branch = 1;
            end;
         end;
      end Rec;
   begin
      return Rec (Nm, 20);
   end Is_Char_Class;

   --  Is Name an operand of an exception rule (`X = A - B`: A or B)?
   function Is_Except_Operand (Name : String) return Boolean is
   begin
      for C in Excepts.Iterate loop
         if Except_Maps.Element (C) = Name
           or else Except_Bases.Element (Except_Maps.Key (C)) = Name
         then
            return True;
         end if;
      end loop;
      return False;
   end Is_Except_Operand;

   package Name_Sets is new Ada.Containers.Indefinite_Ordered_Sets (String);
   Plain_Yes, Plain_No : Name_Sets.Set;   --  Is_Char_Rule_Plain, per rule count

   function Is_Char_Rule_Plain (Rules : Rule_Vectors.Vector; Nm : String)
      return Boolean is
      Key : constant String := Nm & "#" & Natural'Image (Natural (Rules.Length));
      --  Rec of a name at a depth, kept for the call: a rule reached by many
      --  paths (a grammar whose rules refer to the ones below by several
      --  names) is looked at once, not once per path.
      Memo_Yes, Memo_No : Name_Sets.Set;

      function Rec_Raw (N : String; Depth : Natural) return Boolean;

      function Rec (N : String; Depth : Natural) return Boolean is
         K : constant String := N & "#" & Natural'Image (Depth);
      begin
         if Memo_Yes.Contains (K) then
            return True;
         elsif Memo_No.Contains (K) then
            return False;
         end if;
         declare
            Result : constant Boolean := Rec_Raw (N, Depth);
         begin
            if Result then
               Memo_Yes.Include (K);
            else
               Memo_No.Include (K);
            end if;
            return Result;
         end;
      end Rec;

      function Rec_Raw (N : String; Depth : Natural) return Boolean is
         J : constant Natural := Index_Of (Rules, N);
      begin
         if J = 0 or else Depth = 0 then
            return False;
         end if;
         declare
            R : constant Rule := Rules (J);
            --  The core scanners `int`/`str`/`word` may repeat a multi-code-point
            --  building block (`str`'s `*str_char`); a repetition over a longer
            --  sequence in any other rule stays a list.
            Core_Scanner : constant Boolean := Is_Core_Name (N);
         begin
            if R.Jet_Code /= Null_Unbounded_String
              or else Natural (R.Pattern.Length) = 0
            then
               return False;
            end if;
            declare
               Has_Anchor : Boolean := False;
            begin
               for E of R.Pattern loop
                  case E.Kind is
                     when Char_Range =>
                        Has_Anchor := True;
                     when Alt =>
                        null;
                     when Literal =>
                        if E.No_Case and then Letter_Count (E.Lit) > 4 then
                           return False;
                        end if;
                        --  A letter/underscore-led literal is a word (a keyword
                        --  or a word matched by text), not a run of code
                        --  points; a rule with one is a phrase rule
                        --  (`rtable = "rtable" int`).  A punctuation or
                        --  digit-led literal (`"-"`, `"0x"`) stays char-level.
                        declare
                           S : constant String := To_String (E.Lit);
                        begin
                           if Keywords_Apply
                             and then S'Length > 0
                             and then (S (S'First) in 'a' .. 'z'
                                       or else S (S'First) in 'A' .. 'Z'
                                       or else (S (S'First) = '_'
                                                and then S'Length > 1))
                           then
                              return False;
                           end if;
                           --  A repeated multi-code-point literal is a list
                           --  (`1*"0x"`); a one-code-point one a run.
                           if not Core_Scanner
                             and then (E.Min /= 1 or else E.Max /= 1)
                             and then not Single_Code_Point (S)
                           then
                              return False;
                           end if;
                        end;
                     when Name =>
                        if Is_Core_Name (To_String (E.Name)) then
                           return False;
                        end if;
                        --  An exception (`X = A - B`) is a token scanned by a
                        --  function of its own; a rule that refers to it is a
                        --  phrase rule that calls it, not one whose scanner
                        --  would inline A and lose the exception.
                        if Excepts.Contains (To_String (E.Name)) then
                           return False;
                        end if;
                        if not Rec (To_String (E.Name), Depth - 1) then
                           return False;
                        end if;
                        Has_Anchor := True;
                        if not Core_Scanner
                          and then (E.Min /= 1 or else E.Max /= 1)
                          and then not Is_Char_Class
                            (Rules, To_String (E.Name))
                        then
                           return False;
                        end if;
                     when Group =>
                        return False;
                     when Block =>
                        --  A character rule is code points; a `%action{ }` in
                        --  one is not char-level.
                        return False;
                     when Bit_Field =>
                        null;     --  a rule with bit fields never reaches here (Split_Wire)
                     when Negation =>
                        null;   --  resolved into a rule of ranges before this runs
                  end case;
               end loop;
               return Has_Anchor;
            end;
         end;
      end Rec_Raw;
   begin
      if Plain_Yes.Contains (Key) then
         return True;
      elsif Plain_No.Contains (Key) then
         return False;
      end if;
      declare
         Result : constant Boolean := Rec (Nm, 20);
      begin
         if Result then
            Plain_Yes.Include (Key);
         else
            Plain_No.Include (Key);
         end if;
         return Result;
      end;
   end Is_Char_Rule_Plain;

   --  Does a rule, or any rule it reaches, skip whitespace between elements?
   function Skips_Whitespace
     (Rules : Rule_Vectors.Vector; Nm : String) return Boolean is
      Seen : Path_Sets.Set;

      function Rec (N : String) return Boolean;

      function Rec_Els
        (Els : Element_Vectors.Vector; Ws : Boolean) return Boolean is
      begin
         for E of Els loop
            --  A phrase rule skips whitespace between the entries of a
            --  repetition as it does between the elements of a sequence.
            if Ws and then E.Kind /= Alt and then E.Max /= 1 then
               return True;
            end if;
            case E.Kind is
               when Name =>
                  if Rec (To_String (E.Name)) then
                     return True;
                  end if;
               when Group =>
                  if (Ws and then Natural (E.Items.Length) > 1)
                    or else Rec_Els (E.Items, Ws)
                  then
                     return True;
                  end if;
               when others =>
                  null;
            end case;
         end loop;
         return False;
      end Rec_Els;

      function Rec (N : String) return Boolean is
         J : constant Natural := Index_Of (Rules, N);
      begin
         --  A rule of characters never skips whitespace, whatever its file
         --  says; its elements are code points of one token.
         if J = 0 or else Is_Core_Name (N) or else Seen.Contains (N)
           or else Is_Char_Rule_Plain (Rules, N)
           --  The whitespace rule is what is skipped; it does not skip.
           or else (for some R of Rules => To_String (R.Whitespace) = N)
         then
            return False;
         end if;
         Seen.Insert (N);
         declare
            Ws : constant Boolean :=
              Rules (J).Whitespace /= Null_Unbounded_String;
         begin
            if Ws and then Natural (Rules (J).Pattern.Length) > 1 then
               return True;
            end if;
            return Rec_Els (Rules (J).Pattern, Ws);
         end;
      end Rec;
   begin
      return Rec (Nm);
   end Skips_Whitespace;

   --  Is Op text hbnf can scan exactly, as one token?
   function Operand_Is_Text
     (Rules : Rule_Vectors.Vector; Op : String) return Boolean is
      J   : constant Natural := Index_Of (Rules, Op);
      D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
      Ok  : Boolean;
      Why : Unbounded_String;
   begin
      if Is_Core_Name (Op) then
         return True;
      end if;
      if J = 0 or else Rules (J).Jet_Code /= Null_Unbounded_String then
         return False;
      end if;
      if Is_Char_Rule_Plain (Rules, Op) then
         return True;
      end if;
      HBNF_Lookahead.Token_Dfa (Rules, Op, D, Ok, Why);
      return Ok and then not Skips_Whitespace (Rules, Op);
   end Operand_Is_Text;

   function Except_Is_Token
     (Rules : Rule_Vectors.Vector; X : String) return Boolean is
      Key : constant String :=
        X & "#" & Natural'Image (Natural (Rules.Length));
   begin
      if not Excepts.Contains (X) then
         return False;
      end if;
      if Token_Yes.Contains (Key) then
         return True;
      elsif Token_No.Contains (Key) then
         return False;
      end if;
      if Operand_Is_Text (Rules, Except_Bases.Element (X))
        and then Operand_Is_Text (Rules, Excepts.Element (X))
      then
         Token_Yes.Include (Key);
         return True;
      end if;
      Token_No.Include (Key);
      return False;
   end Except_Is_Token;

   function Is_Text_Rule
     (Rules : Rule_Vectors.Vector; Nm : String) return Boolean is
      J : constant Natural := Index_Of (Rules, Nm);

      --  Does the rule, or one it reaches, name a built-in type (a number or a
      --  word is a typed value, not text), or hold a letter-led literal in a
      --  grammar that has keywords (it is matched as a word there, with its
      --  boundary, not as characters)?
      Seen : Path_Sets.Set;

      function Typed (N : String) return Boolean;

      function Typed_Els (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            case E.Kind is
               when Name =>
                  --  A built-in, or an exception (the automaton would read it
                  --  as its first operand and lose the exception), is not text.
                  --  A rule run in a frame of numbers (or a reference with
                  --  arguments) is not text either: it reads the numbers.
                  if Is_Core_Name (To_String (E.Name))
                    or else Excepts.Contains (To_String (E.Name))
                    or else Length (E.Args) > 0
                    or else Length (Frame_Of (To_String (E.Name)).Slots) > 0
                    or else Typed (To_String (E.Name))
                  then
                     return True;
                  end if;
               when Literal =>
                  declare
                     L : constant String := To_String (E.Lit);
                  begin
                     if Keywords_Apply and then L'Length > 0
                       and then (L (L'First) in 'a' .. 'z'
                                 or else L (L'First) in 'A' .. 'Z'
                                 or else (L (L'First) = '_'
                                          and then L'Length > 1))
                     then
                        return True;
                     end if;
                  end;
               when Group =>
                  if Typed_Els (E.Items) then
                     return True;
                  end if;
               when Block =>
                  --  A lookahead or a test is not text: the automaton built
                  --  from the rule would drop it, and the rule would match
                  --  what it was written not to.
                  return True;
               when others =>
                  null;
            end case;
         end loop;
         return False;
      end Typed_Els;

      function Typed (N : String) return Boolean is
         K : constant Natural := Index_Of (Rules, N);
      begin
         if K = 0 or else Seen.Contains (N) then
            return False;
         end if;
         Seen.Insert (N);
         return Typed_Els (Rules (K).Pattern);
      end Typed;

      --  An enum (`dir = "in" | "out"`) or a lone literal already has a good
      --  type: the tag, or the string.
      function Literal_Only (Els : Element_Vectors.Vector) return Boolean is
         In_Branch : Natural := 0;
      begin
         for E of Els loop
            if E.Kind = Alt then
               if In_Branch /= 1 then
                  return False;
               end if;
               In_Branch := 0;
            elsif E.Kind = Literal and then E.Min = 1 and then E.Max = 1 then
               In_Branch := In_Branch + 1;
            else
               return False;
            end if;
         end loop;
         return In_Branch = 1;
      end Literal_Only;
      Key    : constant String := Nm & "#" & Natural'Image (Natural (Rules.Length));
      Result : Boolean;
   begin
      if Text_Yes.Contains (Key) then
         return True;
      elsif Text_No.Contains (Key) then
         return False;
      end if;
      Result :=
        J > 0
        and then not Is_Core_Name (Nm)
        and then not Excepts.Contains (Nm)      --  an exception has its own kind
        and then Length (Frame_Of (Nm).Slots) = 0
        and then not Literal_Only (Rules (J).Pattern)
        and then not Typed (Nm)
        and then Operand_Is_Text (Rules, Nm);
      if Result then
         Text_Yes.Include (Key);
      else
         Text_No.Include (Key);
      end if;
      return Result;
   end Is_Text_Rule;

   --  Is Nm an operand of an exception that is a token?
   function Is_Token_Operand
     (Rules : Rule_Vectors.Vector; Nm : String) return Boolean is
   begin
      for C in Excepts.Iterate loop
         declare
            X : constant String := Except_Maps.Key (C);
         begin
            if (Except_Maps.Element (C) = Nm or else Except_Bases.Element (X) = Nm)
              and then Except_Is_Token (Rules, X)
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Is_Token_Operand;

   --  A rule that is only text, or an operand of a token exception, and is not
   --  a scanner already is a token whatever it is made of (groups, nested
   --  repetitions, alternatives of words): its scanner is a deterministic
   --  automaton built from its text, and its value is the text it matched.
   function Is_Dfa_Token (Rules : Rule_Vectors.Vector; Nm : String)
      return Boolean is
      J : constant Natural := Index_Of (Rules, Nm);
   begin
      return (Is_Token_Operand (Rules, Nm) or else Is_Text_Rule (Rules, Nm))
        and then not Is_Core_Name (Nm)
        and then J /= 0
        and then Rules (J).Jet_Code = Null_Unbounded_String
        and then not Is_Char_Rule_Plain (Rules, Nm);
   end Is_Dfa_Token;

   function Is_Char_Rule (Rules : Rule_Vectors.Vector; Nm : String)
      return Boolean is
     ((Excepts.Contains (Nm) and then Except_Is_Token (Rules, Nm))
      or else Is_Dfa_Token (Rules, Nm)
      or else Is_Char_Rule_Plain (Rules, Nm));

   function Is_Char_Token (Rules : Rule_Vectors.Vector; Nm : String)
      return Boolean is
      --  True when a phrase rule's pattern references Nm, at any depth: a
      --  group (a list entry's alternation) may hold the reference, and Lift
      --  keeps a list's group inline rather than giving it a rule of its own.
      function Refers (Els : Element_Vectors.Vector) return Boolean is
      begin
         for E of Els loop
            if E.Kind = Name and then To_String (E.Name) = Nm then
               return True;
            elsif E.Kind = Group and then Refers (E.Items) then
               return True;
            elsif E.Kind = Bit_Field
              and then (To_String (E.F_Ref) = Nm or else Refers (E.F_Alts))
            then
               return True;     --  a bit rule names it: it is read by name
            elsif E.Kind = Block and then Refers (E.Look) then
               return True;     --  a lookahead (!x, &x) scans it
            end if;
         end loop;
         return False;
      end Refers;
   begin
      if Is_Core_Name (Nm) then
         return True;
      end if;
      for R of Wire_Store loop
         if Refers (R.Pattern) then
            return True;
         end if;
      end loop;
      if Natural (Rules.Length) > 0
        and then To_String (Rules (1).Name) = Nm
      then
         return True;
      end if;
      --  The operands of a token exception are scanned by the rule that excepts.
      if Is_Token_Operand (Rules, Nm) then
         return True;
      end if;
      for R of Rules loop
         if not Is_Char_Rule (Rules, To_String (R.Name)) then
            if Refers (R.Pattern) then
               return True;
            end if;
         end if;
      end loop;
      return False;
   end Is_Char_Token;

   --  A rule with an `%emit` of its own, or a declared value, is generated as a function that
   --  runs its pattern as written (RFCPLAN.md step 15): no list nodes for its repetitions, no
   --  rule made up for a group, so an emit runs where it is written and sees the whole rule.
   function Runs_Emits (R : Rule) return Boolean is
      function Holds (V : Element_Vectors.Vector) return Boolean is
      begin
         for E of V loop
            if (E.Kind = Block and then E.Op = B_Emit)
              or else (E.Kind = Group and then Holds (E.Items))
            then
               return True;
            end if;
         end loop;
         return False;
      end Holds;
   begin
      return Value_Type (To_String (R.Name)) /= "" or else Holds (R.Pattern);
   end Runs_Emits;

   --  `layout tape` (RFCPLAN.md step 17): the rules are rewritten to the ones the author would write
   --  with %emit to have the parser write a flat tape, as the tape grammars of corpus/ do by hand.
   --  A rule that holds fields is opened where it begins and closed where it ends; a token is one
   --  entry with its text; an enum is one entry with its value; a literal, a hidden rule, a
   --  choice of other rules and a rule that is one other rule write nothing of their own, so a
   --  choice or an alias adds no node.  Every phrase rule yields a value (it is a function and builds
   --  no struct), and the tape is put back to where it was when a form is given up (`rollback`).
   function Tape_Layout (Rules : Rule_Vectors.Vector) return Rule_Vectors.Vector is
      Result : Rule_Vectors.Vector := Rules;
      N      : constant Natural := Natural (Rules.Length);
      type Role is (Nothing, Token, Enum, Num, Opener, Span, Pass);
      Roles  : array (1 .. N) of Role := [others => Nothing];
      Tags   : array (1 .. N) of Natural := [others => 0];
      Tag_Count : Natural := 0;
      Decls  : Unbounded_String;
      Used   : array (1 .. N) of Boolean := [others => False];
      Info   : array (1 .. N) of Boolean := [others => False];   --  the rule writes something

      function Img (X : Natural) return String is
        (Natural'Image (X) (Natural'Image (X)'First + 1 .. Natural'Image (X)'Last));

      --  u8 .. u64 and i8 .. i64, the fixed-width numbers
      function Is_Core_Name (Nm : String) return Boolean is
        (Nm'Length >= 2 and then Nm (Nm'First) in 'u' | 'i'
         and then (for all C of Nm (Nm'First + 1 .. Nm'Last) => C in '0' .. '9'));

      function Find_Rule (Nm : String) return Natural is
      begin
         for I in 1 .. N loop
            if To_String (Rules (I).Name) = Nm then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Rule;

      function C_Id (Nm : String) return String is
         R : String := Nm;
      begin
         for I in R'Range loop
            if R (I) not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' then
               R (I) := '_';
            end if;
         end loop;
         return R;
      end C_Id;

      --  The branches of a pattern: how many, and whether each is one element of the kind asked.
      function Every_Branch_Is (V : Element_Vectors.Vector; K : Element_Kind) return Boolean is
         Count : Natural := 0;
         Ok    : Boolean := True;
      begin
         for E of V loop
            if E.Kind = Alt then
               if Count /= 1 then Ok := False; end if;
               Count := 0;
            else
               Count := Count + 1;
               if E.Kind /= K or else E.Min /= 1 or else E.Max /= 1 then Ok := False; end if;
            end if;
         end loop;
         return Ok and then Count = 1;
      end Every_Branch_Is;

      function Branch_Count (V : Element_Vectors.Vector) return Natural is
         C : Natural := 1;
      begin
         for E of V loop
            if E.Kind = Alt then C := C + 1; end if;
         end loop;
         return C;
      end Branch_Count;

      function Emit (Code : String) return Element_Access is
        (new Element'(Kind => Block, Min => 1, Max => 1, Op => B_Emit, Ctx => <>, Path => <>,
                      Id => 0, Look => <>, Code => To_Unbounded_String (Code)));

      function Tag_Of (J : Natural) return String is ("T_" & C_Id (To_String (Rules (J).Name)));

      procedure Mark_Used (V : Element_Vectors.Vector) is
      begin
         for E of V loop
            if E.Kind = Name then
               declare
                  J : constant Natural := Find_Rule (To_String (E.Name));
               begin
                  if J /= 0 then
                     Used (J) := True;
                  end if;
               end;
            elsif E.Kind = Group then
               Mark_Used (E.Items);
            end if;
         end loop;
      end Mark_Used;

      function Rewrite (V : Element_Vectors.Vector) return Element_Vectors.Vector is
         Out_V : Element_Vectors.Vector;
      begin
         for E of V loop
            case E.Kind is
               when Name =>
                  declare
                     J : constant Natural := Find_Rule (To_String (E.Name));
                     R : constant Role := (if J = 0 then Nothing else Roles (J));
                  begin
                     if R in Token | Enum | Num then
                        declare
                           Code : constant String :=
                             (if R = Token
                              then "tape_text_of (" & Tag_Of (J) & ", p->pos, hbnf_sn ($@));"
                              elsif R = Num
                              then "tape_put (TAPE_TAG (" & Tag_Of (J) & ") | ((uint64_t) $@ & 0xFFFFFFFFFFull));"
                              else "tape_put (TAPE_TAG (" & Tag_Of (J) & ") | (uint64_t) $@);");
                        begin
                           if E.Min = 1 and then E.Max = 1 then
                              Out_V.Append (E);
                              Out_V.Append (Emit (Code));
                           else
                              --  a repeated name: the entry belongs to each repetition
                              declare
                                 Once : constant Element_Access := new Element'(E.all);
                                 Items : Element_Vectors.Vector;
                              begin
                                 Once.Min := 1;
                                 Once.Max := 1;
                                 Items.Append (Once);
                                 Items.Append (Emit (Code));
                                 Out_V.Append (new Element'(Kind => Group, Min => E.Min, Max => E.Max,
                                                            Items => Items));
                              end;
                           end if;
                        end;
                     else
                        Out_V.Append (E);
                     end if;
                  end;
               when Group =>
                  declare
                     C : constant Element_Access := new Element'(E.all);
                  begin
                     C.Items := Rewrite (E.Items);
                     Out_V.Append (C);
                  end;
               when others =>
                  Out_V.Append (E);
            end case;
         end loop;
         return Out_V;
      end Rewrite;

      Openers, Texts : Unbounded_String;
      Names_Tab      : Unbounded_String;
   begin
      for I in 1 .. N loop
         Mark_Used (Rules (I).Pattern);
      end loop;
      Used (1) := True;
      for J in 1 .. N loop
         declare
            R  : Rule renames Rules (J);
            Nm : constant String := To_String (R.Name);
         begin
            if R.Left_Bases > 0 then
               raise Parse_Error with
                 "rule `" & Nm & "`: `layout tape` does not take a left-recursive rule yet";
            elsif Is_Wire_Rule (Nm)
              or else (R.Pattern.Is_Empty and then R.Jet_Code = Null_Unbounded_String)
            then
               Roles (J) := Nothing;
            elsif Nm = "word" then
               Roles (J) := (if Used (J) then Token else Nothing);        --  a bareword: its text
            elsif Nm = "int" then
               Roles (J) := (if Used (J) then Num else Nothing);          --  its value, 40 bits
            elsif Nm in "str" | "atom" | "bool" | "flag" or else Is_Core_Name (Nm) then
               Roles (J) := Nothing;      --  not recorded yet (a `str` is unquoted: its offset is not the text's)
            elsif R.Jet_Code /= Null_Unbounded_String or else Is_Char_Rule (Rules, Nm) then
               --  a token the grammar's phrases name; the rest of the character rules are the
               --  pieces of those, inside their scanners
               Roles (J) := (if Is_Hidden (Nm) or else not Is_Char_Token (Rules, Nm)
                             then Nothing else Token);
            elsif Branch_Count (R.Pattern) = 1 and then Every_Branch_Is (R.Pattern, Literal) then
               Roles (J) := (if Is_Hidden (Nm) then Nothing else Token);   --  `kw = "true"`: its text
            elsif Branch_Count (R.Pattern) >= 2 and then Every_Branch_Is (R.Pattern, Literal) then
               Roles (J) := Enum;
            else
               Roles (J) := Pass;       --  until the fixpoint below says it holds more than one thing
            end if;
         end;
      end loop;

      --  A rule that can only ever hold one node of its own (a choice of other rules, a rule that is
      --  one other thing between punctuation) writes none: its child stands for it.  A rule that
      --  holds several, or a repeated one, or none that writes anything, is a node.  What a rule
      --  holds depends on what the rules it names write, and those on theirs, so this is found by
      --  going round until nothing changes: a rule only ever goes from writing nothing to a node.
      declare
         Changed : Boolean := True;

         --  How many nodes the most that a branch of V can hold: 0, 1, or 2 for two or more or any
         --  number (a repeated part).
         function Count (V : Element_Vectors.Vector) return Natural is
            Best, Here : Natural := 0;

            function Of_Element (E : Element_Access) return Natural is
               C : Natural := 0;
            begin
               case E.Kind is
                  when Name =>
                     declare
                        J : constant Natural := Find_Rule (To_String (E.Name));
                     begin
                        if J /= 0 and then Info (J) then C := 1; end if;
                     end;
                  when Group =>
                     C := Count (E.Items);
                  when others =>
                     C := 0;
               end case;
               if C > 0 and then (E.Max < 0 or else E.Max > 1) then
                  C := 2;
               end if;
               return C;
            end Of_Element;
         begin
            for E of V loop
               if E.Kind = Alt then
                  Best := Natural'Max (Best, Here);
                  Here := 0;
               else
                  Here := Natural'Min (2, Here + Of_Element (E));
               end if;
            end loop;
            return Natural'Max (Best, Here);
         end Count;

         --  Does the pattern consume text of its own, a literal: what a rule matches that nothing
         --  else shows?  A rule of hidden and zero-width parts (a gap, a lookahead) has none.
         function Has_Literal (V : Element_Vectors.Vector) return Boolean is
         begin
            for E of V loop
               if E.Kind = Literal or else (E.Kind = Group and then Has_Literal (E.Items)) then
                  return True;
               end if;
            end loop;
            return False;
         end Has_Literal;
      begin
         for J in 1 .. N loop
            Info (J) := Roles (J) in Token | Enum | Num;
         end loop;
         while Changed loop
            Changed := False;
            for J in 1 .. N loop
               if Roles (J) = Pass then
                  declare
                     C : constant Natural := Count (Rules (J).Pattern);
                  begin
                     if C >= 2 then
                        Roles (J) := Opener;
                        Info (J) := True;
                        Changed := True;
                     elsif C = 1 and then not Info (J) then
                        Info (J) := True;
                        Changed := True;
                     end if;
                  end;
               end if;
            end loop;
            if not Changed then
               --  what still holds nothing that is written is a node of its own if it matched text
               --  (a literal), so that it is seen; with none, there is nothing to see
               for J in 1 .. N loop
                  if Roles (J) = Pass and then not Info (J) and then Has_Literal (Rules (J).Pattern) then
                     Roles (J) := Opener;
                     Info (J) := True;
                     Changed := True;
                  end if;
               end loop;
            end if;
         end loop;
      end;
      --  A rule whose parts that are written are all text, and between whose elements nothing is
      --  skipped, is one entry with the text of the whole match, as a hand-written tape has one for a
      --  scalar that runs over several lines: not a node with a text in it for each line.
      declare
         Changed : Boolean := True;

         function Text_Only (V : Element_Vectors.Vector; Found : in out Boolean) return Boolean is
         begin
            for E of V loop
               if E.Kind = Name then
                  declare
                     J : constant Natural := Find_Rule (To_String (E.Name));
                  begin
                     if J /= 0 then
                        if Roles (J) = Token then
                           Found := True;
                        elsif Info (J) then        --  a text rule inside would write its text twice
                           return False;     --  a value, a number, a node, or a rule standing for one
                        end if;
                     end if;
                  end;
               elsif E.Kind = Group then
                  if not Text_Only (E.Items, Found) then
                     return False;
                  end if;
               end if;
            end loop;
            return True;
         end Text_Only;
      begin
         while Changed loop
            Changed := False;
            for J in 1 .. N loop
               if Roles (J) = Opener and then Rules (J).Whitespace = Null_Unbounded_String then
                  declare
                     Found : Boolean := False;
                  begin
                     if Text_Only (Rules (J).Pattern, Found) and then Found then
                        Roles (J) := Span;
                        Changed := True;
                     end if;
                  end;
               end if;
            end loop;
         end loop;
      end;
      --  a rule the grammar declares `flat` writes no node of its own, whatever it holds
      for J in 1 .. N loop
         if Roles (J) in Opener | Span then
            declare
               Nm : constant String := To_String (Rules (J).Name);
               Stop : Natural := Nm'First;
            begin
               while Stop <= Nm'Last and then Nm (Stop) /= '(' loop
                  Stop := Stop + 1;
               end loop;
               if Flat_Bases.Contains (Nm (Nm'First .. Stop - 1)) then
                  Roles (J) := Pass;
               end if;
            end;
         end if;
      end loop;
      for J in 1 .. N loop
         if Roles (J) in Token | Enum | Num | Opener | Span then
            Tag_Count := Tag_Count + 1;
            Tags (J) := Tag_Count;
         end if;
      end loop;
      if Tag_Count > 255 then
         raise Parse_Error with
           "`layout tape` has " & Img (Tag_Count) & " kinds of node; a tape tag is one byte, 255 at most";
      end if;
      for J in 1 .. N loop
         if Tags (J) > 0 then
            Append (Decls, (if Length (Decls) = 0 then "enum { " else ", ")
                    & Tag_Of (J) & (if Tags (J) = 1 then " = 1" else ""));
            Append (Names_Tab, ", """ & To_String (Rules (J).Name) & """");
            if Roles (J) = Opener then
               Append (Openers, (if Length (Openers) = 0 then "" else " || ") & "(t) == " & Tag_Of (J));
            elsif Roles (J) in Token | Span then
               Append (Texts, (if Length (Texts) = 0 then "" else " || ") & "(t) == " & Tag_Of (J));
            end if;
         end if;
      end loop;
      for J in 1 .. N loop
         declare
            R : Rule := Rules (J);
            Nm : constant String := To_String (R.Name);
            Base : Natural := Nm'First;
         begin
            if Roles (J) in Opener | Span | Pass then
               while Base <= Nm'Last and then Nm (Base) /= '(' loop
                  Base := Base + 1;
               end loop;
               if Roles (J) = Span then
                  --  one entry with the text of the whole match
                  Value_Types.Include (Nm (Nm'First .. Base - 1), "uint64_t");
                  declare
                     Inner : constant Element_Access :=
                       new Element'(Kind => Group, Min => 1, Max => 1, Items => R.Pattern);
                     P : Element_Vectors.Vector;
                  begin
                     P.Append (Emit ("$$ = p->pos;"));
                     P.Append (Inner);
                     P.Append (Emit ("tape_text_of (" & Tag_Of (J) & ", p->pos, p->pos - $$);"));
                     R.Pattern := P;
                  end;
               elsif Roles (J) = Opener then
                  Value_Types.Include (Nm (Nm'First .. Base - 1), "uint64_t");
                  declare
                     Body_Items : constant Element_Vectors.Vector := Rewrite (R.Pattern);
                     Inner : constant Element_Access :=
                       new Element'(Kind => Group, Min => 1, Max => 1, Items => Body_Items);
                     P : Element_Vectors.Vector;
                  begin
                     P.Append (Emit ("$$ = tape_open (" & Tag_Of (J) & ");"));
                     P.Append (Inner);
                     P.Append (Emit ("tape_close ($$);"));
                     R.Pattern := P;
                  end;
               else
                  Value_Types.Include (Nm (Nm'First .. Base - 1), "int");
                  R.Pattern := Rewrite (R.Pattern);
               end if;
               Result.Replace_Element (J, R);
            end if;
         end;
      end loop;
      Preamble_Pieces.Append
        (Code_Piece'(Lang => To_Unbounded_String ("C"),
                     Code => To_Unbounded_String
                       (To_String (Decls) & " };" & ASCII.LF
                        & "#define TAPE_IS_OPENER(t) (" & (if Length (Openers) = 0 then "0" else To_String (Openers)) & ")" & ASCII.LF
                        & "#define TAPE_IS_TEXT(t) (" & (if Length (Texts) = 0 then "0" else To_String (Texts)) & ")" & ASCII.LF
                        & "static const char *const tape_tag_names[] = { """"" & To_String (Names_Tab) & " };" & ASCII.LF
                        & "#include ""hbnf_tape.h""" & ASCII.LF)));
      if Length (Rollback_Text) = 0 then
         Rollback_Text := To_Unbounded_String ("tape_n");
      end if;
      return Result;
   end Tape_Layout;

   --  The rules the layout asks for: the tape rewrites them; any other layout is a file (its operations,
   --  its prologue and epilogue, read when the grammar was), and the tree is what they leave.
   function Layout_Rules (Rules : Rule_Vectors.Vector) return Rule_Vectors.Vector is
   begin
      if To_String (Layout_Text) = "tape" then
         return Tape_Layout (Rules);
      end if;
      return Rules;
   end Layout_Rules;

   function Lift (Rules : Rule_Vectors.Vector) return Rule_Vectors.Vector is
      Result : Rule_Vectors.Vector := Layout_Rules (Rules);
      Names  : Path_Sets.Set;

      --  An element the backends take inside a sequence as it is.
      function Simple (E : Element_Access) return Boolean is
        (E.Kind = Alt
         or else (E.Kind = Block and then E.Op /= B_Action)
         or else (E.Min = 1 and then E.Max = 1
                  and then (E.Kind in Literal | Name | Char_Range
                            or else (E.Kind = Group
                                     and then (for all X of E.Items =>
                                                 X.Kind /= Alt)))));

      procedure Lift_Rule (J : Positive);

      --  Make every element of V's branches one the backends take inside a
      --  sequence: a plain `( a b )` is spliced in, and an optional, a
      --  repetition or an alternation group becomes a new rule, named
      --  `<rule>_<n>`, that the branch refers to.
      procedure Flatten (V : in out Element_Vectors.Vector; Owner : String;
                         N : in out Natural; Ws : Unbounded_String) is
         Out_V : Element_Vectors.Vector;
      begin
         for E of V loop
            if E.Kind = Block and then E.Op = B_Action then
               --  A block between elements: a rule of its own that matches
               --  nothing and runs the code.  `expr = term "+" %action{ … }
               --  term` then runs the action at its own point in the tree,
               --  and an alternative's own block belongs to the rule lifted
               --  for that alternative.  The rule is empty, so there is
               --  nothing to recurse into.
               declare
                  H : Unbounded_String;
               begin
                  loop
                     N := N + 1;
                     H := To_Unbounded_String (Owner & "_" & Img (N));
                     exit when not Names.Contains (To_String (H));
                  end loop;
                  Names.Include (To_String (H));
                  Result.Append
                    (Rule'(Name             => H,
                           Pattern          => Element_Vectors.Empty_Vector,
                           Leading_Comment  => Null_Unbounded_String,
                           Trailing_Comment => Null_Unbounded_String,
                           Jet_Code         => Null_Unbounded_String,
                           Action_Code      => E.Code,
                           Left_Bases       => 0,
                           Whitespace       => Ws));
                  Out_V.Append
                    (new Element'(Kind => Name, Min => 1, Max => 1,
                                  Name => H, Fold => False, Args => Null_Unbounded_String));
               end;
            elsif Simple (E) and then E.Kind /= Group then
               Out_V.Append (E);
            elsif Simple (E) then
               --  `( a b )`: the same as `a b`.
               declare
                  Inner : Element_Vectors.Vector := E.Items;
               begin
                  Flatten (Inner, Owner, N, Ws);
                  for X of Inner loop
                     Out_V.Append (X);
                  end loop;
               end;
            else
               declare
                  H : Unbounded_String;
                  P : Element_Vectors.Vector;
               begin
                  loop
                     N := N + 1;
                     H := To_Unbounded_String (Owner & "_" & Img (N));
                     exit when not Names.Contains (To_String (H));
                  end loop;
                  Names.Include (To_String (H));
                  --  A rule lifted from a rule that has a frame runs in it.
                  if Length (Frame_Of (Owner).Slots) > 0 then
                     Set_Frame (To_String (H),
                                (Slots  => Frame_Of (Owner).Slots,
                                 Arity  => Frame_Of (Owner).Arity,
                                 Shares => True));
                  end if;
                  if E.Kind = Group and then E.Min = 1 and then E.Max = 1 then
                     --  `( a | b )`: a rule of the alternation.
                     P := E.Items;
                  else
                     --  `[ x ]`, `*x`, `1*( a b )`: a rule that is the
                     --  optional or the list, as a rule of its own is.
                     P.Append (E);
                     --  What repeats or is optional is as hidden as what it repeats.
                     if (E.Kind = Name and then Is_Hidden (To_String (E.Name)))
                       or else (E.Kind = Group and then Natural (E.Items.Length) = 1
                                and then E.Items (1).Kind = Name
                                and then Is_Hidden (To_String (E.Items (1).Name)))
                     then
                        Hidden_Rules.Include (To_String (H));
                     end if;
                  end if;
                  Result.Append
                    (Rule'(Name             => H,
                           Pattern          => P,
                           Leading_Comment  => Null_Unbounded_String,
                           Trailing_Comment => Null_Unbounded_String,
                           Jet_Code         => Null_Unbounded_String,
                           Action_Code      => Null_Unbounded_String,
                           Left_Bases       => 0,
                           Whitespace       => Ws));
                  Lift_Rule (Natural (Result.Length));
                  Out_V.Append
                    (new Element'(Kind => Name, Min => 1, Max => 1,
                                  Name => H, Fold => False, Args => Null_Unbounded_String));
                  --  An alternative that starts with the lifted element keeps
                  --  its %label (the label sits on its first element).
                  if Label_Of (E) /= "" then
                     Set_Label (Out_V.Last_Element, Label_Of (E));
                  end if;
               end;
            end if;
         end loop;
         V := Out_V;
      end Flatten;

      procedure Lift_Rule (J : Positive) is
         R : Rule := Result (J);
         N : Natural := 0;
      begin
         if R.Jet_Code /= Null_Unbounded_String or else R.Pattern.Is_Empty
           or else Runs_Emits (R)
         then
            return;
         end if;
         --  A char rule is a scanner (compiled by Char_DNF), not lifted: its
         --  repetitions are greedy scanner loops, not lists.
         if Is_Char_Rule (Result, To_String (R.Name)) then
            return;
         end if;
         if Natural (R.Pattern.Length) = 1
           and then R.Pattern (1).Kind = Group
         then
            --  A rule that is one group: a list, an optional or a grouped
            --  alternation, which the backends take whole.  Its branches
            --  are sequences like any other.  The group is copied, so a
            --  pattern the reader shares (left recursion's raw form) is
            --  not changed under it.
            declare
               G : constant Element_Access := new Element'(R.Pattern (1).all);
            begin
               Flatten (G.Items, To_String (R.Name), N, R.Whitespace);
               R.Pattern.Replace_Element (1, G);
            end;
         elsif Natural (R.Pattern.Length) = 1 then
            --  One element: `x = *y` is a list, `x = y` an alias.
            return;
         else
            Flatten (R.Pattern, To_String (R.Name), N, R.Whitespace);
         end if;
         Result.Replace_Element (J, R);
      end Lift_Rule;

      --  `expr = term '+' term` names one rule twice in one alternative.  A
      --  tree field is named after the rule it references and after nothing
      --  else, so the two references would collide on one field — which is
      --  why the backends used to refuse the shape.  The grammar is
      --  well-formed and the case is the canonical expression production, so
      --  instead of refusing it the second and later references become alias
      --  rules: `expr = term '+' term_2` with `term_2 = term`.  The first
      --  reference keeps the bare name, so no field that exists today moves,
      --  and the suffix follows the `<rule>_<n>` convention `Flatten` uses
      --  for the rules it lifts.  The alias resolves to the same type, so
      --  the two fields differ only in name.
      procedure Split_Repeats (J : Positive) is
         R : Rule := Result (J);

         --  How many elements before K in the same alternative (back to the
         --  last Alt, or the start) reference the same rule.  Counted on the
         --  original sequence, since rewriting replaces a reference by its
         --  alias.
         function Earlier (Orig : Element_Vectors.Vector; K : Positive;
                           Nm : Unbounded_String) return Natural is
            C : Natural := 0;
            I : Natural := K - 1;
         begin
            while I >= 1 loop
               exit when Orig (I).Kind = Alt;
               if Orig (I).Kind = Name and then Orig (I).Name = Nm then
                  C := C + 1;
               end if;
               I := I - 1;
            end loop;
            return C;
         end Earlier;

         procedure Walk (V : in out Element_Vectors.Vector) is
            Orig : constant Element_Vectors.Vector := V;
         begin
            for K in 1 .. Natural (Orig.Length) loop
               if Orig (K).Kind = Name then
                  declare
                     Occ : constant Natural := Earlier (Orig, K, Orig (K).Name);
                  begin
                     if Occ > 0 then
                        --  The (Occ + 1)-th reference: `term_2`, `term_3`, …,
                        --  bumped past any rule that already has the name.
                        declare
                           H      : Unbounded_String;
                           Suffix : Natural := Occ + 1;
                           P      : Element_Vectors.Vector;
                        begin
                           loop
                              H := To_Unbounded_String
                                (To_String (Orig (K).Name) & "_"
                                 & Img (Suffix));
                              exit when not Names.Contains (To_String (H));
                              Suffix := Suffix + 1;
                           end loop;
                           Names.Include (To_String (H));
                           if Length (Frame_Of (To_String (R.Name)).Slots) > 0 then
                              Set_Frame (To_String (H),
                                         (Slots  => Frame_Of (To_String (R.Name)).Slots,
                                          Arity  => Frame_Of (To_String (R.Name)).Arity,
                                          Shares => True));
                           end if;
                           P.Append
                             (new Element'(Kind => Name, Min => 1, Max => 1,
                                           Name => Orig (K).Name,
                                           Fold => False, Args => Orig (K).Args));
                           Result.Append
                             (Rule'(Name             => H,
                                    Pattern          => P,
                                    Leading_Comment  => Null_Unbounded_String,
                                    Trailing_Comment => Null_Unbounded_String,
                                    Jet_Code         => Null_Unbounded_String,
                                    Action_Code      => Null_Unbounded_String,
                                    Left_Bases       => 0,
                                    Whitespace       => R.Whitespace));
                           V.Replace_Element
                             (K, new Element'(Kind => Name, Min => 1, Max => 1,
                                              Name => H, Fold => False, Args => Null_Unbounded_String));
                           if Label_Of (Orig (K)) /= "" then
                              Set_Label (V (K), Label_Of (Orig (K)));
                           end if;
                        end;
                     end if;
                  end;
               elsif Orig (K).Kind = Group then
                  --  A group's branches are a scope of their own, and it is
                  --  copied so a shared pattern is not changed under it.
                  declare
                     G : constant Element_Access := new Element'(Orig (K).all);
                  begin
                     Walk (G.Items);
                     V.Replace_Element (K, G);
                     if Label_Of (Orig (K)) /= "" then
                        Set_Label (G, Label_Of (Orig (K)));
                     end if;
                  end;
               end if;
            end loop;
         end Walk;
      begin
         if R.Pattern.Is_Empty
           or else R.Jet_Code /= Null_Unbounded_String
         then
            return;
         end if;
         --  A char rule is a scanner, not a tree: the same character class
         --  twice (`string = DQUOTE *( … ) DQUOTE`) is the normal spelling
         --  and has no fields to collide.
         if Is_Char_Rule (Result, To_String (R.Name)) then
            return;
         end if;
         Walk (R.Pattern);
         Result.Replace_Element (J, R);
      end Split_Repeats;
   begin
      for R of Rules loop
         Names.Include (To_String (R.Name));
      end loop;
      for J in 1 .. Natural (Rules.Length) loop
         Lift_Rule (J);
      end loop;
      --  After lifting, and over the rules it made as well as the ones it
      --  was given, so the elements a lifted rule holds are seen too (the
      --  second `expression` of  1#( expression ":" expression )  is in one).
      declare
         J : Natural := 1;
      begin
         while J <= Natural (Result.Length) loop
            if not Runs_Emits (Result (J)) then
               Split_Repeats (J);
            end if;
            J := J + 1;
         end loop;
      end;
      return Result;
   end Lift;

   function Language return String is (To_String (Schema_Language));

   function Rollback_State return String is (To_String (Rollback_Text));

   procedure Set_Layout (Mode : String) is
   begin
      if Mode = "" then
         raise Parse_Error with "--layout= takes the name of a layout: ast, tape, or a directory of the layouts directory";
      end if;
      Layout_Text := To_Unbounded_String (Mode);
      Layout_Given := True;
   end Set_Layout;

   function Layout return String is (To_String (Layout_Text));

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

   function Statements return Boolean is (Statements_On);

   function Context_Count return Natural is (Natural (Context_Words.Length));
   function Context_Name (K : Positive) return String is
     (To_String (Context_Words (K)));

   function Macros_Rule return String is (To_String (Macros_Name));

   function Includes_Rule return String is (To_String (Includes_Name));

   function Keyword_Table return Word_Vectors.Vector is (Keyword_Words);

   function Keywords_Apply return Boolean is
     (Words_Used or else not Keyword_Words.Is_Empty);

   function Jet_Body (Name : String; T : Target) return String is
   begin
      if T = C_Target or else not Jets.Contains (Name) then
         return "";
      end if;
      declare
         E : constant Jet_Entry := Jets.Element (Name);
      begin
         return To_String (case T is
                              when Rust_Target => E.Rust,
                              when Zig_Target  => E.Zig,
                              when others      => E.Ada);
      end;
   end Jet_Body;

   function Except_Base (Name : String) return String is
     (if Except_Bases.Contains (Name) then Except_Bases.Element (Name) else "");

   function Except_Operand (Name : String) return String is
     (if Excepts.Contains (Name) then Excepts.Element (Name) else "");

   function Guard_Count return Natural is (Natural (Guards.Length));

   function Guard_Ranges (Id : Positive) return Guard_Range_Array is
      G : constant Guard_Set := Guards (Id);
      R : Guard_Range_Array (1 .. Natural (G.Ranges.Length));
   begin
      for K in R'Range loop
         R (K) := G.Ranges (K);
      end loop;
      return R;
   end Guard_Ranges;

   function Guard_Eoi (Id : Positive) return Boolean is (Guards (Id).Eoi);

   function Spelled (Name : String) return String is
     (if Bnf_Spellings.Contains (Name) then Bnf_Spellings.Element (Name)
      else Name);

   procedure Set_Ebnf (On : Boolean) is
   begin
      Ebnf_Mode := On;
      if On and then Flag_Dialect = Null_Unbounded_String then
         Flag_Dialect := To_Unbounded_String ("ebnf");
      end if;
   end Set_Ebnf;

   procedure Set_Dialect (Name : String) is
   begin
      if Name in "bnf" | "ebnf" | "abnf" | "ybnf" | "hbnf" then
         Flag_Dialect := To_Unbounded_String (Name);
      end if;
      if Name = "abnf" then
         Abnf_Mode := True;
      elsif Name = "ebnf" then
         Ebnf_Mode := True;
         Union_Bar_Mode := True;
      elsif Name in "bnf" | "ybnf" then
         Union_Bar_Mode := True;
      elsif Name /= "hbnf" then
         raise Parse_Error with
           "--dialect= takes bnf, ebnf, abnf, ybnf or hbnf";
      end if;
   end Set_Dialect;

   procedure Set_Abnf (On : Boolean) is
   begin
      Abnf_Mode := On;
      if On and then Flag_Dialect = Null_Unbounded_String then
         Flag_Dialect := To_Unbounded_String ("abnf");
      end if;
   end Set_Abnf;

   procedure Note_Rule_Names (Rules : Rule_Vectors.Vector) is
   begin
      Emitted_Rules.Clear;
      for R of Rules loop
         Emitted_Rules.Include (To_String (R.Name));
      end loop;
   end Note_Rule_Names;

   function Prefixed (S : String) return String is
      D : constant Unbounded_String :=
        (if Flag_Dialect /= Null_Unbounded_String then Flag_Dialect
         elsif File_Dialect /= Null_Unbounded_String then File_Dialect
         else To_Unbounded_String ("bnf"));
   begin
      if No_Name_Prefix or else Flag_No_Prefix
        or else Is_Core_Name (S) or else S = "ws"
        or else not Emitted_Rules.Contains (S)
      then
         return S;
      end if;
      return To_String (D) & "_" & S;
   end Prefixed;

   function Name_Prefix return String is
      D : constant Unbounded_String :=
        (if Flag_Dialect /= Null_Unbounded_String then Flag_Dialect
         elsif File_Dialect /= Null_Unbounded_String then File_Dialect
         else To_Unbounded_String ("bnf"));
   begin
      if No_Name_Prefix or else Flag_No_Prefix then
         return "";
      elsif Type_Prefix_Code /= Null_Unbounded_String then
         return To_String (Type_Prefix_Code);
      end if;
      return To_String (D) & "_";
   end Name_Prefix;

   procedure Set_Root (Name : String) is
   begin
      Root_Rule := To_Unbounded_String (Name);
   end Set_Root;

   procedure Set_Type_Prefix (Prefix : String) is
   begin
      if Prefix = "none" then
         Flag_No_Prefix := True;
         return;
      end if;
      if not Valid_Prefix (Prefix) then
         raise Parse_Error with "--prefix: not a C identifier prefix: " & Prefix;
      end if;
      Type_Prefix_Code := To_Unbounded_String (Prefix);
   end Set_Type_Prefix;

end HBNF_Grammar;
