--  tests/recursive.sh's Ada driver for tests/abnf/recursive-via-list.hbnf:
--  parse the expression on the command line, then free the tree.  Built with
--  AddressSanitizer, so a node Free_Sum misses is reported as a leak, and one
--  it frees twice or should not own as an error.
with Ada.Command_Line;
with Ada.Text_IO;
with Rvl;
with Rvl.Parser;

procedure Rvl_Main is
   R : Rvl.Sum_Type;
begin
   R := Rvl.Parser.Parse_Text (Ada.Command_Line.Argument (1));
   Rvl.Parser.Free_Sum (R);
   Ada.Text_IO.Put_Line ("OK");
exception
   when Rvl.Parser.Parse_Error =>
      Ada.Text_IO.Put_Line ("REJECT");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Rvl_Main;
