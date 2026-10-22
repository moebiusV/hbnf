--  Back-references in Ada: a closing tag repeats the opening one (tests/backref/tags.hbnf); the
--  lines tests/backref/expected.txt has for C.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Tags;
with Tags.Parser; use Tags.Parser;

procedure Main is
   function First_Line (S : String) return String is
   begin
      for I in S'Range loop
         if S (I) = Character'Val (10) then
            return S (S'First .. I - 1);
         end if;
      end loop;
      return S;
   end First_Line;

   procedure Run (Text : String) is
      Pad : constant String := (1 .. Natural'Max (0, 26 - Text'Length) => ' ');
   begin
      declare
         Doc : Tags.Doc_Type := Parse_Text (Text);
      begin
         Put_Line (Text & Pad & " accepted");
         Free_Doc (Doc);
      end;
   exception
      when E : Parse_Error =>
         Put_Line (Text & Pad & " " & First_Line (Ada.Exceptions.Exception_Message (E)));
   end Run;
begin
   Run ("<a></a>");
   Run ("<a>text</a>");
   Run ("<a><b></b></a>");
   Run ("<a><a></a></a>");
   Run ("<a></a><b></b>");
   Run ("x<a>y<b>z</b>w</a>v");
   Run ("<a></b>");
   Run ("<a><b></a></b>");
   Run ("<ab></a>");
   Run ("<a></ab>");
   Run ("<a>");
   Run ("</a>");
end Main;
