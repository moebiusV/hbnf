pragma Ada_2022;
--  check.adb: HBNF_Template against the Mustache it is meant to do (tests/template.sh builds and runs it).
with Ada.Exceptions;
with Ada.Text_IO;
with HBNF_Template; use HBNF_Template;

procedure Check is
   Failed : Natural := 0;
   Count  : Natural := 0;

   LF : constant String := [ASCII.LF];

   procedure Show (Name, Got, Want : String) is
   begin
      Failed := Failed + 1;
      Ada.Text_IO.Put_Line ("FAIL " & Name & ": got [" & Got & "], wanted [" & Want & "]");
   end Show;

   procedure Ok (Name, Source : String; V : Context; Want : String) is
   begin
      Count := Count + 1;
      begin
         declare
            Got : constant String := Render (Source, V);
         begin
            if Got /= Want then
               Show (Name, Got, Want);
            end if;
         end;
      exception
         when E : others =>
            Show (Name, "error " & Ada.Exceptions.Exception_Message (E), Want);
      end;
   end Ok;

   procedure Refused (Name, Source : String; V : Context) is
   begin
      Count := Count + 1;
      begin
         declare
            Got : constant String := Render (Source, V);
         begin
            Show (Name, Got, "an error");
         end;
      exception
         when Template_Error => null;
      end;
   end Refused;

   function Row (K1, V1 : String; K2 : String := ""; V2 : String := "") return Value_Access is
      M : constant Value_Access := New_Map;
   begin
      Insert (M, K1, New_Scalar (V1));
      if K2 /= "" then
         Insert (M, K2, New_Scalar (V2));
      end if;
      return M;
   end Row;

   E : Context := View;
   S : Context := View;
   L : Context := View;
   Items : constant Value_Access := New_List;
   Words : constant Value_Access := New_List;
   Deep  : Context := View;
   Inner : constant Value_Access := New_Map;
   Outer : constant Value_Access := New_Map;
   Nest  : Context := View;
   NestA : constant Value_Access := New_Map;
   NestB : constant Value_Access := New_List;
   Empty : Context := View;
   Shadow : Context := View;
   Single  : constant Value_Access := New_List;
begin
   Put (E, "x", "1<2");
   Put (S, "x", "<&>""'");
   Put (S, "yes", "y");
   Put (S, "no", "");
   Append (Items, Row ("n", "1"));
   Append (Items, Row ("n", "2"));
   Put (L, "l", Items);
   Append (Words, New_Scalar ("p"));
   Append (Words, New_Scalar ("q"));
   Insert (Inner, "c", New_Scalar ("z"));
   Insert (Outer, "b", Inner);
   Put (Deep, "a", Outer);
   Append (NestB, Row ("v", "1"));
   Append (NestB, Row ("v", "2"));
   Insert (NestA, "b", NestB);
   Put (Nest, "a", NestA);
   Put (Empty, "l", New_List);
   Put (Shadow, "o", "O");
   Append (Single, Row ("n", "1"));
   Put (Shadow, "l", Single);

   --  interpolation
   Ok ("raw", "a {{&x}} b", E, "a 1<2 b");
   Ok ("escaped", "{{x}}", S, "&lt;&amp;&gt;&quot;&#39;");
   Ok ("triple", "{{{x}}}", E, "1<2");
   Ok ("blanks in a tag", "{{ & x }}|{{ x }}", E, "1<2|1&lt;2");
   Ok ("missing", "[{{&nope}}][{{nope}}]", E, "[][]");
   Ok ("dotted", "{{&a.b.c}}", Deep, "z");
   Ok ("dotted, missing", "[{{&a.b.d}}][{{&q.b.c}}]", Deep, "[][]");

   --  sections
   Ok ("list", "[{{#l}}{{&n}},{{/l}}]", L, "[1,2,]");
   Ok ("empty list", "[{{#l}}{{&n}},{{/l}}]", Empty, "[]");
   Ok ("scalar there", "{{#yes}}Y{{/yes}}{{^yes}}N{{/yes}}", S, "Y");
   Ok ("scalar empty", "{{#no}}Y{{/no}}{{^no}}N{{/no}}", S, "N");
   Ok ("scalar missing", "{{#nope}}Y{{/nope}}{{^nope}}N{{/nope}}", S, "N");
   Ok ("inverted, empty list", "{{^l}}none{{/l}}", Empty, "none");
   Ok ("inverted, list", "{{^l}}none{{/l}}", L, "");
   Ok ("nested", "{{#a}}{{#b}}{{&v}}{{/b}}{{/a}}", Nest, "12");
   Ok ("outer names", "{{#l}}{{&n}}{{&o}}{{/l}}", Shadow, "1O");
   Ok ("blank before the sigil", "{{ # yes }}y{{ / yes }}", S, "y");
   declare
      V : Context := View;
   begin
      Put (V, "l", Words);
      Ok ("implicit iterator", "{{#l}}{{&.}};{{/l}}", V, "p;q;");
   end;

   --  lines that hold a section tag or a comment and nothing else are dropped whole
   Ok ("standalone section", "a" & LF & "{{#l}}" & LF & "- {{&n}}" & LF & "{{/l}}" & LF & "z" & LF, L,
       "a" & LF & "- 1" & LF & "- 2" & LF & "z" & LF);
   Ok ("standalone, indented", "a" & LF & "  {{#yes}}" & LF & "b" & LF & "  {{/yes}}" & LF & "z", S,
       "a" & LF & "b" & LF & "z");
   Ok ("standalone inverted", "{{^l}}" & LF & "none" & LF & "{{/l}}" & LF, Empty, "none" & LF);
   Ok ("standalone comment", "a" & LF & "  {{! note }}" & LF & "b", E, "a" & LF & "b");
   Ok ("inline comment", "a{{! x }}b", E, "ab");
   Ok ("section after text is not alone", "a {{#yes}}" & LF & "b{{/yes}}", S, "a " & LF & "b");
   Ok ("interpolation line is kept", "  {{&x}}" & LF, E, "  1<2" & LF);

   --  text with braces
   Ok ("single brace", "a{b}c{", E, "a{b}c{");
   Ok ("code", "if (x) { y(); }" & LF, E, "if (x) { y(); }" & LF);
   Ok ("nothing", "", E, "");

   --  what is refused
   Refused ("unterminated", "a {{x", E);
   Refused ("unterminated triple", "{{{x}}", E);
   Refused ("closed by another name", "{{#a}}x{{/b}}", E);
   Refused ("never closed", "{{#a}}x", E);
   Refused ("closed but not opened", "x{{/a}}", E);
   Refused ("partial", "{{> p}}", E);
   Refused ("delimiters", "{{=<% %>=}}", E);

   Ada.Text_IO.Put_Line ((if Failed = 0 then "ok " else "FAIL ") & Count'Image & " cases," & Failed'Image & " failed");
   if Failed > 0 then
      raise Program_Error;
   end if;
end Check;
