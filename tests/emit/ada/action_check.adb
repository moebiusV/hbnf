--  a driver for tests/emit/action-ada.hbnf: whether the text is read, the line and message of the error, and how many actions ran
with Ada.Text_IO; with Ada.Command_Line; with Ada.Exceptions; with Action_State;
with Er; with Er.Parser;
procedure Action_Check is
   Text : String := Ada.Command_Line.Argument (1);
   Last : Natural := Text'First - 1;
   I    : Natural := Text'First;
   Buf  : String (1 .. Text'Length);
   function Img (X : Natural) return String is (Natural'Image (X) (2 .. Natural'Image (X)'Last));
begin
   while I <= Text'Last loop
      if Text (I) = '\' and then I < Text'Last and then Text (I + 1) = 'n' then
         Last := Last + 1; Buf (Last - Text'First + 1) := ASCII.LF; I := I + 2;
      else
         Last := Last + 1; Buf (Last - Text'First + 1) := Text (I); I := I + 1;
      end if;
   end loop;
   declare
      T : constant Er.Config_Type := Er.Parser.Parse_Text (Buf (1 .. Last - Text'First + 1));
      pragma Unreferenced (T);
   begin
      Ada.Text_IO.Put_Line ("ok " & Img (Action_State.Seen));
   end;
exception
   when E : Er.Parser.Parse_Error =>
      declare
         M : constant String := Ada.Exceptions.Exception_Message (E);
         C : Natural := M'First;
      begin
         while C <= M'Last and then M (C) /= ':' loop C := C + 1; end loop;
         Ada.Text_IO.Put_Line ("error " & M (M'First .. C - 1) & M (C + 3 .. M'Last) & " " & Img (Action_State.Seen));
      end;
end Action_Check;
