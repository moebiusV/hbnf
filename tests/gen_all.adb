pragma Ada_2022;

with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with ASTBNF;
with ASTBNF_C;
with ASTBNF_Rust;
with ASTBNF_Zig;
with ASTBNF_Ada;

--  Dump every backend's declarations + parser for a schema (arg 1) into the
--  current directory under fixed names, for the cross-language compile smoke
--  test in e2e.sh.
procedure Gen_All is

   function Read_File (Path : String) return String is
      F   : Ada.Text_IO.File_Type;
      Buf : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Ada.Strings.Unbounded.Append (Buf, Ada.Text_IO.Get_Line (F));
         if not Ada.Text_IO.End_Of_File (F) then
            Ada.Strings.Unbounded.Append (Buf, ASCII.LF);
         end if;
      end loop;
      Ada.Text_IO.Close (F);
      return Ada.Strings.Unbounded.To_String (Buf);
   end Read_File;

   procedure Write (Path : String; Text : String) is
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (F, Text);
      Ada.Text_IO.Close (F);
   end Write;

   Rules : constant ASTBNF.Rule_Vectors.Vector :=
     ASTBNF.Parse (Read_File (Ada.Command_Line.Argument (1)));

   Conf : constant Boolean := Ada.Command_Line.Argument_Count >= 2
     and then Ada.Command_Line.Argument (2) = "--conf";

   Ada_Parser : constant String :=
     ASTBNF_Ada.Emit_Parser (Rules, "Server_Schema", Conf);
   Split      : constant Natural :=
     Ada.Strings.Fixed.Index (Ada_Parser, "with Interfaces;");
begin
   Write ("server.c",
          ASTBNF_C.Emit (Rules) & ASCII.LF & ASTBNF_C.Emit_Parser (Rules));
   Write ("server.rs",
          ASTBNF_Rust.Emit (Rules) & ASCII.LF & ASTBNF_Rust.Emit_Parser (Rules));
   Write ("server.zig",
          ASTBNF_Zig.Emit (Rules) & ASCII.LF & ASTBNF_Zig.Emit_Parser (Rules));
   Write ("server_schema.ads", ASTBNF_Ada.Emit (Rules, "Server_Schema"));
   Write ("server_schema-parser.ads",
          Ada_Parser (Ada_Parser'First .. Split - 1));
   Write ("server_schema-parser.adb",
          Ada_Parser (Split .. Ada_Parser'Last));
end Gen_All;
