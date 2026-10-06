--  tests/schema.sh's Ada driver: read each file named on the command line
--  and say whether hbnf_schema.hbnf's generated parser accepts it.
with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Schema;
with Schema.Parser;

procedure Schema_Main is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;

   function Slurp (Path : String) return String is
      F   : File_Type;
      Buf : Unbounded_String;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Append (Buf, Get_Line (F));
         Append (Buf, Character'Val (10));
      end loop;
      Close (F);
      return To_String (Buf);
   end Slurp;
begin
   for K in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Path : constant String := Ada.Command_Line.Argument (K);
         R    : Schema.Config_Type;
         pragma Unreferenced (R);
      begin
         R := Schema.Parser.Parse_Text (Slurp (Path));
         Put_Line (Path & ": OK");
      exception
         when Schema.Parser.Parse_Error =>
            Put_Line (Path & ": REJECT");
      end;
   end loop;
end Schema_Main;
