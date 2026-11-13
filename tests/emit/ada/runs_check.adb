--  a driver for tests/emit/runs-ada.hbnf: the value, the depth of the stack and the sum of what is on it
with Ada.Text_IO; with Ada.Command_Line; with Ada.Exceptions; with Ada.Strings.Fixed; with Ada.Strings;
with Emit_State; with Er; with Er.Parser;
procedure Runs_Check is
   function T (N : Integer) return String is (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Both));
   V   : Integer;
   Sum : Integer := 0;
begin
   V := Er.Parser.Parse_Text (Ada.Command_Line.Argument (1));
   for I in 1 .. Emit_State.Depth loop
      Sum := Sum + Emit_State.Stack (I);
   end loop;
   Ada.Text_IO.Put_Line (T (V) & " " & T (Emit_State.Depth) & " " & T (Sum));
exception
   when E : Er.Parser.Parse_Error =>
      declare
         M : constant String := Ada.Exceptions.Exception_Message (E);
         C : Natural := M'First;
      begin
         --  "line:column:offset: expected ..." as `error line:column`
         for K in 1 .. 2 loop
            while C <= M'Last and then M (C) /= ':' loop
               C := C + 1;
            end loop;
            C := C + 1;
         end loop;
         Ada.Text_IO.Put_Line ("error " & M (M'First .. C - 2));
      end;
end Runs_Check;
