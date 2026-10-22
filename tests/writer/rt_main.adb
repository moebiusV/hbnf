--  The writer's gate in Ada (tests/writer.sh): for each file, parse it, write the tree, parse what
--  was written, write again.  The first write must re-parse to the same tree (the same dump), and the
--  second write must be the same text as the first.  MODULE and ROOT are filled in by the script.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with MODULE;
with MODULE.Parser; use MODULE.Parser;

procedure Rt_Main is
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

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   Bad : Natural := 0;

   procedure Roundtrip (Path : String) is
      Text : constant String := Slurp (Path);
      T1   : ROOT_Type;
      T2   : ROOT_Type;
      T3   : ROOT_Type;
      A, B : Unbounded_String;
      Ok   : Boolean;
      Msg  : Unbounded_String;
   begin
      begin
         T1 := Parse_Text (Text);
      exception
         when Parse_Error =>
            Put_Line (Path & ": SKIP (does not parse)");
            return;
      end;
      Write_ROOT (T1, A, Ok, Msg);
      if not Ok then
         Put_Line (Path & ": FAIL (cannot write: " & To_String (Msg) & ")");
         Bad := Bad + 1;
         return;
      end if;
      begin
         T2 := Parse_Text (To_String (A));
      exception
         when E : Parse_Error =>
            Put_Line (Path & ": FAIL (the written text does not parse: "
                      & Ada.Exceptions.Exception_Message (E) & ")");
            Put_Line ("--- written ---" & Character'Val (10) & To_String (A) & Character'Val (10) & "---");
            Bad := Bad + 1;
            return;
      end;
      Write_ROOT (T2, B, Ok, Msg);
      if not Ok then
         Put_Line (Path & ": FAIL (cannot write again: " & To_String (Msg) & ")");
         Bad := Bad + 1;
         return;
      end if;
      --  the written text reads as a tree that dumps the same when its text is read again (a
      --  comment the first parse took, as an empty entry, is gone from the text)
      begin
         T3 := Parse_Text (To_String (B));
      exception
         when Parse_Error =>
            Put_Line (Path & ": FAIL (the second written text does not parse)");
            Bad := Bad + 1;
            return;
      end;
      if Dump_ROOT (T2) /= Dump_ROOT (T3) then
         Put_Line (Path & ": FAIL (the written text reads as a different tree)");
         Put_Line ("--- before ---" & Character'Val (10) & Dump_ROOT (T2));
         Put_Line ("--- after ---" & Character'Val (10) & Dump_ROOT (T3));
         Bad := Bad + 1;
         return;
      end if;
      if A /= B then
         Put_Line (Path & ": FAIL (not idempotent)");
         Put_Line ("--- first ---" & Character'Val (10) & To_String (A));
         Put_Line ("--- second ---" & Character'Val (10) & To_String (B));
         Bad := Bad + 1;
         return;
      end if;
      Put_Line (Path & ": ok (" & Img (Length (A)) & " bytes)");
   end Roundtrip;
begin
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      Roundtrip (Ada.Command_Line.Argument (I));
   end loop;
   if Bad /= 0 then
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Rt_Main;
