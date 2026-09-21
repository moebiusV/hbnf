pragma Ada_2022;

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with ASTBNF;
with ASTBNF_C;
with ASTBNF_Rust;
with ASTBNF_Zig;
with ASTBNF_Ada;

--  astbnf: read a schema and emit a self-contained parser (declarations +
--  lexer + parser) in the chosen backend language.
--
--    astbnf schema.astbnf --backend=c|rust|zig|ada [--package=NAME]
--
--  c/rust/zig print one compilable file to stdout; ada prints the parent
--  package spec, then the child package spec+body (split them apart yourself).
procedure Astbnf_Cli is

   use Ada.Strings.Unbounded;

   Backend      : Unbounded_String := To_Unbounded_String ("c");
   Package_Name : Unbounded_String := To_Unbounded_String ("Schema");
   Schema_Path  : Unbounded_String;

   function Read_File (Path : String) return String is
      F   : Ada.Text_IO.File_Type;
      Buf : Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Append (Buf, Ada.Text_IO.Get_Line (F));
         if not Ada.Text_IO.End_Of_File (F) then
            Append (Buf, ASCII.LF);
         end if;
      end loop;
      Ada.Text_IO.Close (F);
      return To_String (Buf);
   end Read_File;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("usage: astbnf <schema.astbnf> --backend=c|rust|zig|ada [--package=NAME]");
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
      Rules : constant ASTBNF.Rule_Vectors.Vector :=
        ASTBNF.Parse (Read_File (To_String (Schema_Path)));
      B     : constant String := To_String (Backend);
   begin
      if B = "c" then
         Ada.Text_IO.Put (ASTBNF_C.Emit (Rules));
         Ada.Text_IO.Put (ASTBNF_C.Emit_Parser (Rules));
         Ada.Text_IO.Put (ASTBNF_C.Emit_Lexer (Rules));
      elsif B = "rust" then
         Ada.Text_IO.Put (ASTBNF_Rust.Emit (Rules));
         Ada.Text_IO.Put (ASTBNF_Rust.Emit_Parser (Rules));
         Ada.Text_IO.Put (ASTBNF_Rust.Emit_Lexer (Rules));
      elsif B = "zig" then
         Ada.Text_IO.Put (ASTBNF_Zig.Emit (Rules));
         Ada.Text_IO.Put (ASTBNF_Zig.Emit_Parser (Rules));
         Ada.Text_IO.Put (ASTBNF_Zig.Emit_Lexer (Rules));
      elsif B = "ada" then
         Ada.Text_IO.Put (ASTBNF_Ada.Emit (Rules, To_String (Package_Name)));
         Ada.Text_IO.Put (ASTBNF_Ada.Emit_Parser (Rules, To_String (Package_Name)));
      else
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "unknown backend: " & B);
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end;
end Astbnf_Cli;
