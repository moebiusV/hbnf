pragma Ada_2022;

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Mustache;
with HBNF_Grammar;
with HBNF_Compilable;
with HBNF_Tree_Sitter;
with HBNF_C;
with HBNF_Rust;
with HBNF_Zig;
with HBNF_Ada;
with HBNF_Wire.C;
with HBNF_Wire.Lower;
with HBNF_Wire.Rust;
with HBNF_Wire.Zig;

--  hbnf: read a schema and emit a self-contained parser (declarations +
--  lexer + parser) in the chosen backend language.
--
--    hbnf schema.hbnf --backend=c|rust|zig|ada [--package=NAME] [--root=RULE] [--abnf] [--conf] [--idref] [--compare]
--
--  c/rust/zig print one compilable file to stdout; ada prints the parent
--  package spec, then the child package spec+body (split them apart yourself).
--  --conf adds the OpenBSD parse_config(filename) entry: for C it prints the
--  conf.h/conf.c pair (delimited by "===== conf.h =====" and "===== conf.c ====="
--  markers); for rust/zig/ada it appends the conf wrapper to the single file.
--  --abnf reads every file as RFC 5234 reads ABNF: nothing is skipped between
--  a rule's elements and a string is case-insensitive, so an RFC's text
--  compiles as pasted.
--  --root=RULE starts the grammar at that rule instead of the first one, so a
--  collected ABNF (an RFC's appendix) can generate a parser for any of its rules.
--  --idref (C only) adds an id-ref serializer and rebuild side, for a privsep
--  (imsg) consumer: the tree cross-references by id instead of pointer.
--  --compare (C only) appends the deep-compare walk (compare_tree), for
--  byte-identity checks between two parses.
procedure Hbnf is

   use Ada.Strings.Unbounded;

   Backend      : Unbounded_String := To_Unbounded_String ("c");
   Package_Name : Unbounded_String := To_Unbounded_String ("Schema");
   Schema_Path  : Unbounded_String;
   Template_Dir : Unbounded_String;
   Conf         : Boolean := False;
   Idref        : Boolean := False;
   Compare      : Boolean := False;
   Forks        : Boolean := False;
   Ts_Conflicts : Unbounded_String;
   Ts_Ordered   : Boolean := False;
   Ts_Scanner   : Unbounded_String;
   Quiet        : Boolean := False;
   Prefix       : Unbounded_String;

   --  The directory the .tmpl templates load from: --templates=DIR, else the
   --  first XDG data dir that holds a hbnf/ subdirectory -- $XDG_DATA_HOME or
   --  ~/.local/share, then each $XDG_DATA_DIRS entry (/usr/local/share and
   --  /usr/share by default).  "" when none is found.
   function Template_Directory return String is
      use type Ada.Directories.File_Kind;

      function Env (Name : String) return String is
      begin
         if Ada.Environment_Variables.Exists (Name) then
            return Ada.Environment_Variables.Value (Name);
         end if;
         return "";
      end Env;

      function Is_Dir (Path : String) return Boolean is
      begin
         return Ada.Directories.Exists (Path)
           and then Ada.Directories.Kind (Path) = Ada.Directories.Directory;
      exception
         when others => return False;
      end Is_Dir;

      Xdg_Home : constant String := Env ("XDG_DATA_HOME");
      Xdg_Dirs : constant String := Env ("XDG_DATA_DIRS");
      Home     : constant String := Env ("HOME");
      Tmpl_Env : constant String := Env ("HBNF_TEMPLATES");
      Data_Home : constant String :=
        (if Xdg_Home /= "" then Xdg_Home
         elsif Home /= "" then Home & "/.local/share" else "");
      Data_Dirs : constant String :=
        (if Xdg_Dirs /= "" then Xdg_Dirs
         else "/usr/local/share:/usr/share");
      Start : Natural := Data_Dirs'First;
   begin
      if Template_Dir /= Null_Unbounded_String then
         return To_String (Template_Dir);
      end if;
      if Tmpl_Env /= "" then
         return Tmpl_Env;
      end if;
      if Data_Home /= "" and then Is_Dir (Data_Home & "/hbnf") then
         return Data_Home & "/hbnf";
      end if;
      for I in Data_Dirs'Range loop
         if I = Data_Dirs'Last or else Data_Dirs (I) = ':' then
            declare
               Last : constant Natural :=
                 (if I = Data_Dirs'Last then Data_Dirs'Last else I - 1);
               D    : constant String := Data_Dirs (Start .. Last);
            begin
               if D /= "" and then Is_Dir (D & "/hbnf") then
                  return D & "/hbnf";
               end if;
            end;
            Start := I + 1;
         end if;
      end loop;
      return "";
   end Template_Directory;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: hbnf <schema.hbnf> --backend=c|rust|zig|ada|tree-sitter [--package=NAME] [--conf] [--idref] [--ast] [--ast-tools] [--paths] [--spans] [--parents] [--forks] [--quiet-forks] [--ts-conflicts=a,b;c,d] [--ts-ordered] [--ts-scanner=FILE] [--writer] [--compare] [--root=RULE] [--dialect=NAME] [--abnf] [--ebnf] [--prefix=NAME_] [--templates=DIR]");
   end Usage;

begin
   if Ada.Command_Line.Argument_Count = 0 then
      Usage;
      return;
   end if;

   for I in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         A : constant String := Ada.Command_Line.Argument (I);
      begin
         if A'Length >= 10 and then A (1 .. 10) = "--backend=" then
            Backend := To_Unbounded_String (A (11 .. A'Last));
         elsif A'Length >= 10 and then A (1 .. 10) = "--package=" then
            Package_Name := To_Unbounded_String (A (11 .. A'Last));
         elsif A = "--conf" then
            Conf := True;
         elsif A'Length >= 7 and then A (1 .. 7) = "--root=" then
            HBNF_Grammar.Set_Root (A (8 .. A'Last));
         elsif A'Length >= 10 and then A (1 .. 10) = "--dialect=" then
            HBNF_Grammar.Set_Dialect (A (11 .. A'Last));
         elsif A = "--abnf" then
            HBNF_Grammar.Set_Abnf (True);
         elsif A = "--ebnf" then
            HBNF_Grammar.Set_Ebnf (True);
         elsif A = "--spans" then
            HBNF_C.Set_Spans (True);
         elsif A = "--parents" then
            HBNF_C.Set_Parents (True);
         elsif A'Length >= 14 and then A (1 .. 14) = "--ts-conflicts" then
            Ts_Conflicts := To_Unbounded_String
              ((if A'Length > 15 and then A (15) = '=' then A (16 .. A'Last) else ""));
         elsif A = "--ts-ordered" then
            Ts_Ordered := True;
         elsif A'Length >= 13 and then A (1 .. 13) = "--ts-scanner=" then
            Ts_Scanner := To_Unbounded_String (A (14 .. A'Last));
         elsif A = "--forks" then
            Forks := True;
         elsif A = "--quiet-forks" then
            Quiet := True;
         elsif A = "--paths" then
            HBNF_C.Set_Paths (True);
         elsif A = "--ast-tools" then
            HBNF_C.Set_Ast_Tools (True);
         elsif A = "--ast" then
            HBNF_C.Set_Ast (True);
         elsif A = "--writer" then
            HBNF_C.Set_Writer (True);
         elsif A = "--idref" then
            Idref := True;
         elsif A = "--compare" then
            Compare := True;
         elsif A = "--werror" then
            HBNF_Grammar.Set_Werror (True);
         elsif A'Length >= 9 and then A (1 .. 9) = "--prefix=" then
            Prefix := To_Unbounded_String (A (10 .. A'Last));
         elsif A'Length >= 12 and then A (1 .. 12) = "--templates=" then
            Template_Dir := To_Unbounded_String (A (13 .. A'Last));
         elsif A (A'First) /= '-' then
            Schema_Path := To_Unbounded_String (A);
         end if;
      end;
   end loop;

   if Schema_Path = Null_Unbounded_String then
      Usage;
      return;
   end if;

   declare
      Dir : constant String := Template_Directory;
   begin
      if Dir = "" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "hbnf: no template directory found; use --templates=DIR");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Mustache.Load (Dir);
   end;

   --  One schema per run, so the warning count starts clean.  A process that
   --  reads several schemas calls Reset_Warnings between them; the reader does
   --  not do it itself, because Parse_File recurses for includes and a reset
   --  there would drop the including file's warnings and re-arm its
   --  once-per-file keys.
   HBNF_Grammar.Reset_Warnings;

   --  A grammar whose first rule holds bit fields (RFCPLAN.md step 7b) goes to
   --  the wire emitters; the text rules it keeps (those `bitsof` names) are
   --  read from the same grammar.
   declare
      Parsed : constant HBNF_Grammar.Rule_Vectors.Vector :=
        HBNF_Grammar.Parse_File (To_String (Schema_Path));
   begin
      if Forks and then To_String (Backend) /= "c" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "hbnf: --forks is C only so far (" & To_String (Backend)
            & " follows; RFCPLAN.md decision 14)");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      HBNF_C.Set_Forks (Forks, Quiet);
      HBNF_Compilable.Allow_Shadowing (Forks);
      if HBNF_Grammar.Uses_Backref
        and then To_String (Backend) not in "c" | "tree-sitter"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "hbnf: a grammar with `%as` / `%same` can be emitted in C so far ("
            & To_String (Backend) & " follows; RFCPLAN.md, W-grammars)");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      if HBNF_Grammar.Context_Count > 0
        and then To_String (Backend) not in "c" | "tree-sitter"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "hbnf: a grammar with `context` can be emitted in C so far ("
            & To_String (Backend) & " follows; RFCPLAN.md decision 13)");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      if HBNF_Grammar.Wire_Root then
         if To_String (Backend) not in "c" | "rust" | "zig" then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "hbnf: a grammar of bit fields can be emitted in C, Rust and Zig "
               & "so far (" & To_String (Backend)
               & " follows; RFCPLAN.md step 7b)");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
         declare
            G : constant HBNF_Wire.Grammar :=
              HBNF_Wire.Lower.Lower
                (HBNF_Grammar.Wire_Rules, Parsed, To_String (Schema_Path));
            Out_Text : constant String :=
              (if To_String (Backend) = "rust" then HBNF_Wire.Rust.Emit (G)
               elsif To_String (Backend) = "zig" then HBNF_Wire.Zig.Emit (G)
               else HBNF_Wire.C.Emit (G));
         begin
            Ada.Text_IO.Put (Out_Text);
         end;
         return;
      end if;
      --  Text rules that hold bit rules: the C text parser reads the bit rules
      --  too, from its own state.
      if not HBNF_Grammar.Wire_Rules.Is_Empty then
         if To_String (Backend) /= "c" then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "hbnf: a grammar with text rules and bit rules together can "
               & "be emitted in C so far (" & To_String (Backend)
               & " follows; RFCPLAN.md step 7b)");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
         declare
            G : constant HBNF_Wire.Grammar :=
              HBNF_Wire.Lower.Lower
                (HBNF_Grammar.Wire_Rules, Parsed, To_String (Schema_Path));
            Types, Code : Unbounded_String;
         begin
            HBNF_Wire.C.Emit_Hosted (G, Types, Code);
            HBNF_C.Set_Hosted
              (To_String (Types), To_String (Code),
               Actions => (for some R of G.Rules =>
                             R.Action /= Null_Unbounded_String));
            if HBNF_Wire.Shift_Note /= Null_Unbounded_String then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "hbnf: note: " & To_String (HBNF_Wire.Shift_Note));
            end if;
         end;
      end if;
   end;

   declare
      --  The rules the parser uses, with what the backends do not take
      --  inside a sequence given a rule of its own.
      Rules : constant HBNF_Grammar.Rule_Vectors.Vector :=
        HBNF_Grammar.Lift
          (HBNF_Grammar.Reachable
             (HBNF_Grammar.Parse_File (To_String (Schema_Path))));
      B     : constant String := To_String (Backend);
      --  tree-sitter reads the grammar as written (a group is a group), not
      --  with the groups lifted into rules of their own.
      Raw   : constant HBNF_Grammar.Rule_Vectors.Vector :=
        (if B = "tree-sitter"
         then HBNF_Grammar.Reachable
                (HBNF_Grammar.Parse_File (To_String (Schema_Path)))
         else Rules);
      Output : Unbounded_String;

      --  The grammar's name for tree-sitter: --package=, else the file's.
      function Language return String is
         P : constant String := To_String (Schema_Path);
         First : Natural := P'First;
         Last  : Natural := P'Last;
      begin
         if Package_Name /= To_Unbounded_String ("Schema") then
            return To_String (Package_Name);
         end if;
         for K in P'Range loop
            if P (K) = '/' then
               First := K + 1;
            end if;
         end loop;
         for K in reverse First .. P'Last loop
            if P (K) = '.' then
               Last := K - 1;
               exit;
            end if;
         end loop;
         declare
            R : String := P (First .. Last);
         begin
            for C of R loop
               if C not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' then
                  C := '_';
               end if;
            end loop;
            return R;
         end;
      end Language;

      procedure Put (S : String) is
      begin
         Append (Output, S);
      end Put;

      procedure Put_Line (S : String) is
      begin
         Append (Output, S & ASCII.LF);
      end Put_Line;
   begin
      if Prefix /= Null_Unbounded_String then
         HBNF_Grammar.Set_Type_Prefix (To_String (Prefix));
      end if;
      HBNF_Grammar.Note_Rule_Names (Rules);
      if B /= "tree-sitter" then
         HBNF_Compilable.Check (Rules, B);
      end if;
      if B = "tree-sitter" then
         Put (HBNF_Tree_Sitter.Emit
                (Raw, Language, To_String (Ts_Conflicts), Ts_Ordered,
                 Scanner => Ts_Scanner /= Null_Unbounded_String));
         if Ts_Scanner /= Null_Unbounded_String
           and then HBNF_Tree_Sitter.Scanner_Source'Length > 0
         then
            declare
               F : Ada.Text_IO.File_Type;
            begin
               Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, To_String (Ts_Scanner));
               Ada.Text_IO.Put (F, HBNF_Tree_Sitter.Scanner_Source);
               Ada.Text_IO.Close (F);
            end;
         end if;
      elsif B = "c" then
         if Conf then
            Put_Line ("===== conf.h =====");
            Put (HBNF_C.Emit_Conf_Header (Rules));
            Put_Line ("===== conf.c =====");
            Put (HBNF_C.Emit_Conf_Source (Rules));
         else
            Put (HBNF_C.Emit (Rules, Idref));
            Put (HBNF_C.Emit_Parser (Rules));
            Put (HBNF_C.Emit_Lexer (Rules));
            if Idref then
               Put (HBNF_C.Emit_Serializer (Rules));
               Put (HBNF_C.Emit_Rebuild (Rules));
            end if;
            if Compare then
               Put (HBNF_C.Emit_Compare (Rules));
            end if;
         end if;
      elsif B = "rust" then
         Put (HBNF_Rust.Emit (Rules));
         Put (HBNF_Rust.Emit_Parser (Rules));
         Put (HBNF_Rust.Emit_Lexer (Rules));
         if Conf then
            Put ([1 => ASCII.LF]);
            Put (HBNF_Rust.Emit_Conf (Rules));
         end if;
      elsif B = "zig" then
         Put (HBNF_Zig.Emit (Rules));
         Put (HBNF_Zig.Emit_Parser (Rules));
         Put (HBNF_Zig.Emit_Lexer (Rules));
         if Conf then
            Put ([1 => ASCII.LF]);
            Put (HBNF_Zig.Emit_Conf (Rules));
         end if;
      elsif B = "ada" then
         Put (HBNF_Ada.Emit (Rules, To_String (Package_Name)));
         Put
           (HBNF_Ada.Emit_Parser (Rules, To_String (Package_Name), Conf));
      else
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "unknown backend: " & B);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
      --  Written only once all of it is made, so a schema a backend
      --  refuses part way leaves no half a file.
      Ada.Text_IO.Put (To_String (Output));
   end;
exception
   when E : HBNF_Grammar.Parse_Error =>
      --  A schema error: the whole message (it can quote the line, with a
      --  caret, and run past the 200 characters GNAT keeps).
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hbnf: " & HBNF_Grammar.Error_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when Storage_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hbnf: ran out of stack while checking the grammar.  The usual "
         & "cause is a union (`/`) of very many alternatives that something "
         & "can follow directly, so that hbnf has to tell them apart by what "
         & "comes next: a word list repeated with no separator is that, since "
         & "one word's end can be the start of another.  Put a separator "
         & "between them, or write the choice with `|` in the order to "
         & "prefer.");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when E : HBNF_Wire.Wire_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hbnf: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when E : Mustache.Template_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hbnf: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Hbnf;
