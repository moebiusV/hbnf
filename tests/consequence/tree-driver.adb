--  tree-driver.adb: parses the two texts on the command line with the grammar (package Tr, root `cond`) and says
--  whether their trees are the same (the dump of each, from --ast), different, or whether neither is a sentence.
--  The same test as tree-driver.c, for the Ada backend.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Tr;
with Tr.Parser; use Tr.Parser;

procedure Tree_Driver is
   function One (T : String; Dump : out String; Last : out Natural) return Boolean is
      V : Tr.Cond_Type;
   begin
      V := Parse_Text (T);
      declare
         D : constant String := Dump_Cond (V);
      begin
         Last := D'Length;
         Dump (Dump'First .. Dump'First + Last - 1) := D;
      end;
      return True;
   exception
      when Parse_Error =>
         Last := 0;
         return False;
   end One;

   A, B   : String (1 .. 4096);
   LA, LB : Natural;
   RA : constant Boolean := One (Ada.Command_Line.Argument (1), A, LA);
   RB : constant Boolean := One (Ada.Command_Line.Argument (2), B, LB);
begin
   if not RA and then not RB then
      Put_Line ("error");
   elsif RA and then RB and then A (1 .. LA) = B (1 .. LB) then
      Put_Line ("same");
   else
      Put_Line ("different: " & A (1 .. LA) & " | " & B (1 .. LB));
   end if;
end Tree_Driver;
