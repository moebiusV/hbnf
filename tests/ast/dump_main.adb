--  The walk and the dump of tests/ast/ast.hbnf's tree in Ada: the same lines C's node_walk and
--  node_dump print (the first three sections of tests/ast/expected.txt).
with Ada.Text_IO; use Ada.Text_IO;
with Ast;
with Ast.Parser; use Ast.Parser;

procedure Dump_Main is
   use Ast;

   type Show is new Walker with record
      Depth       : Natural := 0;
      Skip_Blocks : Boolean := False;
   end record;

   overriding function Enter (W : in out Show; N : Node) return Walk_Action;
   overriding function Leave (W : in out Show; N : Node) return Walk_Action;

   overriding function Enter (W : in out Show; N : Node) return Walk_Action is
      Alt : constant Natural := Node_Alt (N);
   begin
      Put ((1 .. 2 * W.Depth => ' ') & Node_Kind_Name (N));
      if Alt /= 0 then
         Put ("[" & Node_Alt_Name (N, Alt) & "]");
      end if;
      New_Line;
      if W.Skip_Blocks and then Node_Kind_Name (N) = "block" then
         return Skip;
      end if;
      W.Depth := W.Depth + 1;
      return Continue;
   end Enter;

   overriding function Leave (W : in out Show; N : Node) return Walk_Action is
      pragma Unreferenced (N);
   begin
      W.Depth := W.Depth - 1;
      return Continue;
   end Leave;

   Text : constant String := "set a 1; run b; { set c ""x""; set d e; }";
   Tree : Config_Type := Parse_Text (Text);
   S1   : Show;
   S2   : Show := (Walker with Depth => 0, Skip_Blocks => True);
   Ok   : Boolean;
   pragma Unreferenced (Ok);
begin
   Put_Line ("== all");
   Ok := Walk_Config (Tree, S1);
   Put_Line ("== blocks skipped");
   Ok := Walk_Config (Tree, S2);
   Put_Line ("== dump");
   Put_Line (Dump_Config (Tree));
   declare
      Other : Config_Type := Parse_Text ("set a 2; run b; { set c ""x""; set d e; }");
      Same  : Config_Type := Parse_Text (Text);
      function First (T : Config_Type) return Node is
        (Kind => Config_Kind, Ref_Config => Config_Ref (T.First_Element));
   begin
      Put_Line ("== equal");
      Put_Line ("same text: " & Boolean'Image (Node_Equal (First (Tree), First (Same))));
      Put_Line ("other text: " & Boolean'Image (Node_Equal (First (Tree), First (Other))));
      Free_Config (Other);
      Free_Config (Same);
   end;
   Free_Config (Tree);
end Dump_Main;
