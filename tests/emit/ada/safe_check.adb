--  a driver for tests/emit/safe-ada.hbnf: the calls the emits made, in order
with Ada.Text_IO; with Ada.Command_Line; with Ada.Exceptions;
with Emit_State; with Er; with Er.Parser;
procedure Safe_Check is
   V : Natural;
begin
   V := Er.Parser.Parse_Text (Ada.Command_Line.Argument (1));
   Ada.Text_IO.Put_Line (Emit_State.Trace (1 .. Emit_State.Trace_Len));
exception
   when E : Er.Parser.Parse_Error => Ada.Text_IO.Put_Line ("error");
end Safe_Check;
