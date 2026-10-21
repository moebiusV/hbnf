--  Parse each file and print what the parser says (the files sit beside this one).
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Block.Parser; use Block.Parser;

procedure Main is
   function Slurp (Name : String) return String is
      F : File_Type;
      R : String (1 .. 4096);
      N : Natural := 0;
      C : Character;
   begin
      Open (F, In_File, Name);
      while not End_Of_File (F) loop
         if End_Of_Line (F) then
            Skip_Line (F);
            N := N + 1;
            R (N) := ASCII.LF;
         else
            Get (F, C);
            N := N + 1;
            R (N) := C;
         end if;
      end loop;
      Close (F);
      N := N + 1;
      R (N) := ASCII.LF;   --  Text_IO does not show the last line's end
      return R (1 .. N);
   end Slurp;

   procedure Show (Name : String) is
      T : constant String := Slurp (Name);
   begin
      Put_Line ("== " & Name);
      declare
         X : constant Block.Prog_Type := Parse_Text (T);
         pragma Unreferenced (X);
      begin
         Put_Line ("ok");
      end;
   exception
      when E : Parse_Error =>
         Put_Line (Ada.Exceptions.Exception_Message (E));
   end Show;
begin
   Show ("open.blk");
   Show ("stray.blk");
end Main;
