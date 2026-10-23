--  main.adb -- time a generated Ada parser over a corpus's own good files (bench/stage-zigada.sh).  MODULE and
--  ROOT are filled in by the stage.  Every file is parsed reps times and every tree is kept, so the memory is
--  the trees'.  Prints ok BYTES COUNT SUM MS RSS_KIB.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Calendar;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with MODULE;
with MODULE.Parser; use MODULE.Parser;

procedure Main is
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

   function Rss_Kib return Natural is
      F : File_Type;
   begin
      Open (F, In_File, "/proc/self/status");
      while not End_Of_File (F) loop
         declare
            L : constant String := Get_Line (F);
         begin
            if L'Length > 6 and then L (L'First .. L'First + 5) = "VmHWM:" then
               declare
                  V : Natural := 0;
               begin
                  for C of L (L'First + 6 .. L'Last) loop
                     if C in '0' .. '9' then
                        V := V * 10 + Character'Pos (C) - 48;
                     end if;
                  end loop;
                  Close (F);
                  return V;
               end;
            end if;
         end;
      end loop;
      Close (F);
      return 0;
   end Rss_Kib;

   type Tree_Access is access ROOT_Type;
   N_Files : constant Natural := Ada.Command_Line.Argument_Count - 1;
   Reps    : constant Natural := Natural'Value (Ada.Command_Line.Argument (1));
   type Text_Array is array (1 .. N_Files) of access String;
   Texts   : Text_Array;
   Bytes   : Natural := 0;
   Ok      : Natural := 0;
   Keep    : array (1 .. Reps * N_Files) of Tree_Access;
   T0      : Ada.Calendar.Time;
   use type Ada.Calendar.Time;
begin
   for I in 1 .. N_Files loop
      Texts (I) := new String'(Slurp (Ada.Command_Line.Argument (I + 1)));
   end loop;
   T0 := Ada.Calendar.Clock;
   for R in 0 .. Reps - 1 loop
      for I in 1 .. N_Files loop
         Bytes := Bytes + Texts (I)'Length;
         begin
            Keep (R * N_Files + I) := new ROOT_Type'(Parse_Text (Texts (I).all));
            Ok := Ok + 1;
         exception
            when Parse_Error => null;
         end;
      end loop;
   end loop;
   declare
      Ms : constant Duration := (Ada.Calendar.Clock - T0) * 1000;
   begin
      Put_Line ((if Ok = Reps * N_Files then "ok " else "FAIL ")
                & Natural'Image (Bytes) & Natural'Image (Ok) & " 0 "
                & Duration'Image (Ms) & Natural'Image (Rss_Kib));
   end;
end Main;
