--  tests/recursive.sh's Ada driver: parse one expression from the command
--  line and say whether it was accepted, the way tests/abnf.sh's generated C
--  driver does.  The grammar is tests/abnf/recursive.hbnf, whose tree type
--  contains itself, so this is the fixture that proves a backend breaks the
--  cycle with a pointer rather than refusing.
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;
with Recursive;
with Recursive.Parser;

procedure Recursive_Main is
   use Ada.Text_IO;
   use type Recursive.Prim_Access;   --  `=` for the back-edge member

   Text : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1)
      else "");
   R : Recursive.Prim_Type;
begin
   R := Recursive.Parser.Parse_Text (Text);
   --  `expr` is the back-edge member: for `(1)` the first branch set it,
   --  and reading it here is what proves the field is real, not just typed.
   Put_Line ("OK expr=" & (if R.Expr = null then "null" else "set"));
exception
   when E : Recursive.Parser.Parse_Error =>
      Put_Line ("REJECT " & Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Recursive_Main;
