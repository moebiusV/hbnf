pragma Ada_2022;

with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Strings.Unbounded;
with HBNF;
with ASTBNF;

--  Equivalence check: parse one config file with hbnf's own hand-written
--  parser and with the astbnf matcher/binder (HBNF.Parse_Astbnf), and assert
--  they agree — both succeed and produce the same tree (accept), or both fail
--  (reject).  The tree comparison is Print for Print, which includes comment
--  placement, so it also verifies comments land in the same places.
--  Usage: hbnf_match_check <schema.astbnf> <config.conf> <accept|reject>
procedure HBNF_Match_Check is

   use Ada.Strings.Unbounded;

   function Read_File (Path : String) return String is
      F   : Ada.Text_IO.File_Type;
      Buf : Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Append (Buf, Ada.Text_IO.Get_Line (F));
         Append (Buf, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (F);
      return To_String (Buf);
   end Read_File;

begin
   declare
      Schema : constant ASTBNF.Rule_Vectors.Vector :=
        ASTBNF.Parse (Read_File (Ada.Command_Line.Argument (1)));
      Path   : constant String := Ada.Command_Line.Argument (2);
      Mode   : constant String := Ada.Command_Line.Argument (3);
      Text   : constant String := Read_File (Path);
      P1     : constant HBNF.Parse_Result := HBNF.Parse (Text);
      P2     : constant HBNF.Parse_Result := HBNF.Parse_Astbnf (Text, Schema);
      Pass   : Boolean;
   begin
      Pass :=
        (Mode = "accept" and then P1.Success and then P2.Success
           and then HBNF.Print (P1.Root) = HBNF.Print (P2.Root))
        or else
        (Mode = "reject" and then not P1.Success and then not P2.Success);

      if Pass then
         Ada.Text_IO.Put_Line ("ok: " & Path);
      else
         Ada.Text_IO.Put_Line ("FAIL: " & Path & " (mode " & Mode & ")");
         if Mode = "accept" then
            if not P1.Success then
               Ada.Text_IO.Put_Line ("   hbnf parser rejected");
            elsif not P2.Success then
               Ada.Text_IO.Put_Line ("   astbnf binder rejected");
            else
               Ada.Text_IO.Put_Line ("   trees differ");
            end if;
         else
            if P1.Success then
               Ada.Text_IO.Put_Line ("   hbnf parser accepted");
            elsif P2.Success then
               Ada.Text_IO.Put_Line ("   astbnf binder accepted");
            end if;
         end if;
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end;
end HBNF_Match_Check;
