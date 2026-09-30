pragma Ada_2022;

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Templates;
with HBNF_Grammar;
with HBNF_Compilable;
with HBNF_C;
with HBNF_Rust;
with HBNF_Zig;
with HBNF_Ada;

--  hbnf: read a schema and emit a self-contained parser (declarations +
--  lexer + parser) in the chosen backend language.
--
--    hbnf schema.hbnf --backend=c|rust|zig|ada [--package=NAME] [--conf] [--idref] [--compare]
--
--  c/rust/zig print one compilable file to stdout; ada prints the parent
--  package spec, then the child package spec+body (split them apart yourself).
--  --conf adds the OpenBSD parse_config(filename) entry: for C it prints the
--  conf.h/conf.c pair (delimited by "===== conf.h =====" and "===== conf.c ====="
--  markers); for rust/zig/ada it appends the conf wrapper to the single file.
--  --idref (C only) adds an id-ref serializer and rebuild side, for a privsep
--  (imsg) consumer: the tree cross-references by id instead of pointer.
--  --compare (C only) appends the deep-compare walk (compare_tree), for
--  byte-identity checks between two parses.
procedure Hbnf_Cli is

   use Ada.Strings.Unbounded;

   Backend      : Unbounded_String := To_Unbounded_String ("c");
   Package_Name : Unbounded_String := To_Unbounded_String ("Schema");
   Schema_Path  : Unbounded_String;
   Template_Dir : Unbounded_String;
   Conf         : Boolean := False;
   Idref        : Boolean := False;
   Compare      : Boolean := False;
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
        ("usage: hbnf <schema.hbnf> --backend=c|rust|zig|ada [--package=NAME] [--conf] [--idref] [--compare] [--prefix=NAME_] [--templates=DIR]");
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
         elsif A = "--idref" then
            Idref := True;
         elsif A = "--compare" then
            Compare := True;
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
      Templates.Load (Dir);
   end;

   declare
      --  The rules the parser uses, with what the backends do not take
      --  inside a sequence given a rule of its own.
      Rules : constant HBNF_Grammar.Rule_Vectors.Vector :=
        HBNF_Grammar.Lift
          (HBNF_Grammar.Reachable
             (HBNF_Grammar.Parse_File (To_String (Schema_Path))));
      B     : constant String := To_String (Backend);
      Output : Unbounded_String;

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
      HBNF_Compilable.Check (Rules, B);
      if B = "c" then
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
         "hbnf_cli: " & HBNF_Grammar.Error_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when E : Templates.Template_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "hbnf: " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Hbnf_Cli;
