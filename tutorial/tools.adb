--  The walker and the dump the generator makes (--ast), the same in every language.
with Ada.Text_IO; use Ada.Text_IO;
with Shopping; use Shopping;
with Shopping.Parser; use Shopping.Parser;

procedure Tools is
   LF   : constant Character := Character'Val (10);
   Text : constant String := "buy 2 apples;" & LF & "buy 1 milk from corner-shop;" & LF;

   type Show is new Walker with record
      Depth : Natural := 0;
   end record;
   overriding function Enter (W : in out Show; N : Node) return Walk_Action;
   overriding function Leave (W : in out Show; N : Node) return Walk_Action;

   overriding function Enter (W : in out Show; N : Node) return Walk_Action is
   begin
      Put_Line ((1 .. 2 * W.Depth => ' ') & Node_Kind_Name (N));
      W.Depth := W.Depth + 1;
      return Continue;
   end Enter;

   overriding function Leave (W : in out Show; N : Node) return Walk_Action is
      pragma Unreferenced (N);
   begin
      W.Depth := W.Depth - 1;
      return Continue;
   end Leave;

   List : List_Type := Parse_Text (Text);
   S    : Show;
   Ok   : Boolean;
   pragma Unreferenced (Ok);
begin
   Ok := Walk_List (List, S);
   Put_Line (Dump_List (List));
   Free_List (List);
end Tools;
