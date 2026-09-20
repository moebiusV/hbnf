pragma Ada_2022;

--  Conformance driver for the hbnf grammar.
--
--  Usage: hbnf_check <file> accept|reject
--
--  "accept" requires the file to parse, and to round-trip: print, re-parse,
--  and re-print must be stable (the printer is idempotent).  "reject"
--  requires the parse to fail.  Any disagreement prints a diagnostic and
--  exits non-zero.

with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Text_IO.Unbounded_IO;
with HBNF;

procedure Hbnf_Check is

   function Slurp (Path : String) return String is
      F    : File_Type;
      Line : Unbounded_String;
      Buf  : Unbounded_String := Null_Unbounded_String;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Ada.Text_IO.Unbounded_IO.Get_Line (F, Line);
         Append (Buf, Line);
         Append (Buf, Character'Val (10));
      end loop;
      Close (F);
      return To_String (Buf);
   end Slurp;

   procedure Reject (Path, Why : String; R : HBNF.Parse_Result) is
   begin
      Put_Line (Standard_Error, Why & ": " & Path);
      if not R.Success then
         Put_Line (Standard_Error,
                   "  " & Positive'Image (R.Line) & ":" &
                   Positive'Image (R.Col) & ": " & To_String (R.Msg));
      end if;
      Ada.Command_Line.Set_Exit_Status (1);
   end Reject;

begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Put_Line (Standard_Error, "usage: hbnf_check <file> accept|reject");
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;

   declare
      Path : constant String := Ada.Command_Line.Argument (1);
      Mode : constant String := Ada.Command_Line.Argument (2);
      Text : constant String := Slurp (Path);
      R    : constant HBNF.Parse_Result := HBNF.Parse (Text);
   begin
      if Mode = "accept" then
         if not R.Success then
            Reject (Path, "UNEXPECTED REJECT", R);
            return;
         end if;
         declare
            P1 : constant String := HBNF.Print (R.Root);
            R2 : constant HBNF.Parse_Result := HBNF.Parse (P1);
         begin
            if not R2.Success then
               Reject (Path, "ROUNDTRIP REJECT", R2);
               return;
            end if;
            declare
               P2 : constant String := HBNF.Print (R2.Root);
            begin
               if P1 /= P2 then
                  Put_Line (Standard_Error, "NOT IDEMPOTENT: " & Path);
                  Ada.Command_Line.Set_Exit_Status (1);
                  return;
               end if;
            end;
         end;
         Put_Line ("accept  " & Path);
      elsif Mode = "reject" then
         if R.Success then
            Reject (Path, "UNEXPECTED ACCEPT", R);
         else
            Put_Line ("reject  " & Path);
         end if;
      else
         Put_Line (Standard_Error, "unknown mode: " & Mode);
         Ada.Command_Line.Set_Exit_Status (2);
      end if;
   end;
end Hbnf_Check;
