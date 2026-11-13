--  a driver for the emit tests whose root has no value of its own: the calls the emits made, in order
with Ada.Text_IO; with Ada.Command_Line;
with Emit_State; with Er; with Er.Parser;
procedure Trace_Check is
   V : Er.Top_Type;
begin
   V := Er.Parser.Parse_Text (Ada.Command_Line.Argument (1));
   Ada.Text_IO.Put_Line (Emit_State.Trace (1 .. Emit_State.Trace_Len));
exception
   when Er.Parser.Parse_Error => Ada.Text_IO.Put_Line ("error");
end Trace_Check;
