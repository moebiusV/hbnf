--  tests/schema.sh's Ada driver: read each file named on the command line
--  and say whether hbnf_schema.hbnf's generated parser accepts it.
with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Schema;
with Schema.Parser;

procedure Schema_Main is
   use Ada.Text_IO;

   --  The file exactly as it is: no newline is added.  An RFC's input may be
   --  empty, or end in a space, or in a CR, and a parser must see just that.
   function Slurp (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      F : SIO.File_Type;
   begin
      SIO.Open (F, SIO.In_File, Path);
      declare
         Text : String (1 .. Natural (SIO.Size (F)));
      begin
         String'Read (SIO.Stream (F), Text);
         SIO.Close (F);
         return Text;
      end;
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
