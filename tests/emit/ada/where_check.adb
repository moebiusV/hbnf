--  a driver for tests/emit/where-ada.hbnf: whether the text is read, and what %bind { } added up
with Ada.Text_IO; with Ada.Command_Line; with Where_State;
with Er; with Er.Parser;
procedure Where_Check is
   Ok : Boolean := True;
begin
   begin
      declare
         T : constant Er.Top_Type := Er.Parser.Parse_Text (Ada.Command_Line.Argument (1));
         pragma Unreferenced (T);
      begin
         null;
      end;
   exception
      when Er.Parser.Parse_Error => Ok := False;
   end;
   Ada.Text_IO.Put_Line ((if Ok then "true " else "false ") & Natural'Image (Where_State.Bound) (2 .. Natural'Image (Where_State.Bound)'Last));
end Where_Check;
