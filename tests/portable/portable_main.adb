--  tests/portable.sh's Ada driver: parse each file and print what it holds,
--  as main.c, main.rs and main.zig do.
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Portable;
with Portable.Parser;

procedure Portable_Main is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Portable;

   function Slurp (Path : String) return String is
      F : File_Type;
      S : Unbounded_String;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Append (S, Get_Line (F) & ASCII.LF);
      end loop;
      Close (F);
      return To_String (S);
   end Slurp;

   function Img (N : Long_Long_Integer) return String is
     (Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (N), Ada.Strings.Left));

   --  The error message begins "line N: "; print just N.
   function Line_Of (Msg : String) return String is
      I : Natural := Msg'First + 5;   --  past "line "
   begin
      if Msg'Length < 6 or else Msg (Msg'First .. Msg'First + 4) /= "line " then
         return "?";
      end if;
      declare
         J : Natural := I;
      begin
         while J <= Msg'Last and then Msg (J) in '0' .. '9' loop
            J := J + 1;
         end loop;
         return Msg (I .. J - 1);
      end;
   end Line_Of;
begin
   for A in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Path : constant String := Ada.Command_Line.Argument (A);
      begin
         declare
            C   : constant Config_Type := Parser.Parse_Text (Slurp (Path));
            Acc : Long_Long_Integer := 0;
         begin
            Put (Path & ": hosts");
            for H of C.Host_list loop
               Put (" " & To_String (H.Host));
            end loop;
            Put ("; calc");
            for K in C.Sum.First_Index .. C.Sum.Last_Index loop
               declare
                  S : constant Sum_Entry := C.Sum (K);
               begin
                  if K = C.Sum.First_Index then   --  the base
                     Acc := S.Int;
                     Put (" " & Img (S.Int));
                  elsif S.Op = Op_Op_1 then
                     Acc := Acc + S.Int;
                     Put (" + " & Img (S.Int));
                  else
                     Acc := Acc - S.Int;
                     Put (" - " & Img (S.Int));
                  end if;
               end;
            end loop;
            Put (" = " & Img (Acc)
                 & (if C.Loud.Is_Empty then "" else " loudly") & "; modes");
            for M of C.Modes loop
               Put (if M.Mode = Mode_Fast then " fast" else " slow");
            end loop;
            Put ("; pair");
            for P of C.Pair loop
               Put (" " & To_String (P));
            end loop;
            Put ("; words");
            for W of C.Words loop
               Put (" " & To_String (W));
            end loop;
            New_Line;
         end;
      exception
         when E : Parser.Parse_Error =>
            Put_Line (Path & ": rejected at line "
                      & Line_Of (Ada.Exceptions.Exception_Message (E)));
      end;
   end loop;
end Portable_Main;
