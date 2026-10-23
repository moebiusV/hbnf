--  check.adb -- for the POSIX shell grammar in Ada: say whether the generated parser accepts each file named
--  on the command line ("ok FILE" or "bad FILE").  MODULE is filled in by tests/posix.sh.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with MODULE;
with MODULE.Parser; use MODULE.Parser;

procedure Check is
   use MODULE;

   function Slurp (Path : String) return String is
      F : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Open (F, Ada.Streams.Stream_IO.In_File, Path);
      declare
         N : constant Natural := Natural (Ada.Streams.Stream_IO.Size (F));
         S : String (1 .. N);
      begin
         String'Read (Ada.Streams.Stream_IO.Stream (F), S);
         Ada.Streams.Stream_IO.Close (F);
         return S;
      end;
   end Slurp;

   Bad : Boolean := False;
begin
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Path : constant String := Ada.Command_Line.Argument (I);
         Text : constant String := Slurp (Path);
         T    : ROOT_Type;
      begin
         T := Parse_Text (Text);
         Put_Line ("ok " & Path);
      exception
         when Parse_Error =>
            Put_Line ("bad " & Path);
            Bad := True;
      end;
   end loop;
   if Bad then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Check;
