--  a driver for tests/emit/run-ada.hbnf: the value of the list, or where the read stopped
with Ada.Text_IO; with Ada.Command_Line; with Ada.Exceptions; with Ada.Strings.Fixed; with Ada.Strings;
with Er; with Er.Parser;
procedure Run_Check is
   V : Integer;
begin
   V := Er.Parser.Parse_Text (Ada.Command_Line.Argument (1));
   Ada.Text_IO.Put_Line (Ada.Strings.Fixed.Trim (Integer'Image (V), Ada.Strings.Both));
exception
   when E : Er.Parser.Parse_Error =>
      declare
         M : constant String := Ada.Exceptions.Exception_Message (E);
         C : Natural := M'First;
      begin
         for K in 1 .. 2 loop
            while C <= M'Last and then M (C) /= ':' loop
               C := C + 1;
            end loop;
            C := C + 1;
         end loop;
         Ada.Text_IO.Put_Line ("error " & M (M'First .. C - 2));
      end;
end Run_Check;
