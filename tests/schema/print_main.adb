--  tests/schema.sh's round-trip driver: what tests/hbnf_check.adb used to
--  assert of the hand-written reader, asserted of the generated one.  Each file
--  named on the command line is parsed, printed, re-parsed and re-printed, and
--  the second print must equal the first: the printer is idempotent, so what it
--  prints is a fixed point of the grammar.
--
--  The printer works from the generated tree (hbnf_schema.hbnf through the Ada
--  backend), so it prints what the tree keeps.  Comments are not kept (the
--  grammar skips them) and neither is `;` against a newline, and a quoted
--  string that is also a bareword prints as the bareword.
with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Schema;
with Schema.Parser;

procedure Print_Main is
   use Ada.Strings.Unbounded;
   use Ada.Text_IO;
   use Schema;

   NL : constant Character := ASCII.LF;
   Show : Boolean := False;

   function Slurp (Path : String) return String is
      F   : File_Type;
      Buf : Unbounded_String;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Append (Buf, Get_Line (F));
         Append (Buf, NL);
      end loop;
      Close (F);
      return To_String (Buf);
   end Slurp;

   function Is_Word (S : String) return Boolean is
     (S'Length > 0
      and then S (S'First) in 'a' .. 'z' | 'A' .. 'Z' | '_' | '-'
      and then (for all C of S =>
                  C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' | '.'));

   function Quote (S : String) return String is
      R : Unbounded_String := To_Unbounded_String ("""");
   begin
      for C of S loop
         if C = '"' or else C = '\' then
            Append (R, '\');
         end if;
         Append (R, C);
      end loop;
      Append (R, '"');
      return To_String (R);
   end Quote;

   --  A qualifier is a string or a word and the tree does not say which, so
   --  it prints as a word when it can be one.
   function Value (S : String) return String is
     (if Is_Word (S) then S else Quote (S));

   function Text (S : String_Type) return String is
   begin
      if Length (S.Word) > 0 then
         return To_String (S.Word);
      elsif Length (S.Wildcard) > 0 then
         return To_String (S.Wildcard);
      end if;
      return Quote (To_String (S.Str));
   end Text;

   function Arg_Text (A : Arg_Type) return String is
      Pct : constant String :=
        (if not A.Arg_1.Is_Empty or else not A.Arg_2.Is_Empty then "%" else "");
   begin
      if A.String /= null then
         return Text (A.String.all) & Pct;
      end if;
      return Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (A.Int),
                                     Ada.Strings.Left) & Pct;
   end Arg_Text;

   procedure Put_Entry (E : Entry_Type; Indent : Natural; Out_Text : in out Unbounded_String);

   procedure Put_Entry (E : Entry_Type; Indent : Natural; Out_Text : in out Unbounded_String) is
      Pad : constant String (1 .. Indent) := [others => ' '];
   begin
      if E.Block /= null then
         Append (Out_Text, Pad & To_String (E.Block.Word));
         for Q of E.Block.Block_1 loop
            Append (Out_Text, " " & Value (To_String (Q)));
         end loop;
         Append (Out_Text, " {" & NL);
         for El of E.Block.Block_2 loop
            if El.Entry_F /= null then
               Put_Entry (El.Entry_F.all, Indent + 4, Out_Text);
            end if;
         end loop;
         Append (Out_Text, Pad & "}" & NL);
      elsif E.Statement /= null then
         Append (Out_Text, Pad & To_String (E.Statement.Word));
         for A of E.Statement.Statement_1 loop
            Append (Out_Text, " " & Arg_Text (A.all));
         end loop;
         Append (Out_Text, NL);
      end if;
   end Put_Entry;

   function Print (C : Config_Type) return String is
      R : Unbounded_String;
   begin
      for El of C loop
         if El.Entry_F /= null then
            Put_Entry (El.Entry_F.all, 0, R);
         end if;
      end loop;
      return To_String (R);
   end Print;
begin
   for K in 1 .. Ada.Command_Line.Argument_Count loop
      declare
         Path : constant String := Ada.Command_Line.Argument (K);
      begin
         if Path = "--print" then
            Show := True;   --  also print each tree, for a look at it
            goto Next;
         end if;
         declare
            P1 : constant String := Print (Schema.Parser.Parse_Text (Slurp (Path)));
         begin
            if Show then
               Put (P1);
            end if;
            begin
               declare
                  P2 : constant String :=
                    Print (Schema.Parser.Parse_Text (P1));
               begin
                  if P1 = P2 then
                     Put_Line (Path & ": OK");
                  else
                     Put_Line (Path & ": NOT IDEMPOTENT");
                  end if;
               end;
            exception
               when Schema.Parser.Parse_Error =>
                  Put_Line (Path & ": ROUNDTRIP REJECT");
            end;
         end;
         <<Next>> null;
      exception
         when Schema.Parser.Parse_Error =>
            Put_Line (Path & ": REJECT");
      end;
   end loop;
end Print_Main;
