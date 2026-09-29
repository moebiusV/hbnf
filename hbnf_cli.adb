pragma Ada_2022;

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
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
   Conf         : Boolean := False;
   Idref        : Boolean := False;
   Compare      : Boolean := False;
   Prefix       : Unbounded_String;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: hbnf <schema.hbnf> --backend=c|rust|zig|ada [--package=NAME] [--conf] [--idref] [--compare] [--prefix=NAME_]");
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
end Hbnf_Cli;
