--  Spans and parents (--spans --parents) in Ada: where each node of tests/ast/ast.hbnf's tree is
--  in the text, and which node holds it; the lines C prints (tests/spans/expected.txt).
with Ada.Text_IO; use Ada.Text_IO;
with Ast;
with Ast.Parser; use Ast.Parser;

procedure Main is
   use Ast;
   LF   : constant Character := Character'Val (10);
   Text : constant String :=
     "set a 1;" & LF & "run b;" & LF & "{ set c ""x""; }" & LF;

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Pad_Left (S : String; W : Natural) return String is
     ((1 .. Natural'Max (0, W - S'Length) => ' ') & S);
   function Pad_Right (S : String; W : Natural) return String is
     (S & (1 .. Natural'Max (0, W - S'Length) => ' '));

   Tree    : Config_Type := Parse_Text (Text);
   Ps      : constant Ast.Parser.Parents := Link_Config (Tree);

   type Show is new Walker with null record;
   overriding function Enter (W : in out Show; N : Node) return Walk_Action;

   overriding function Enter (W : in out Show; N : Node) return Walk_Action is
      pragma Unreferenced (W);
      S : constant Span := Node_Span (N);
   begin
      if S.Known then
         declare
            Pl : constant Place := Node_Where (Text, S.First);
            Up : constant Maybe_Node := Parent (Ps, N);
         begin
            Put_Line (Pad_Right (Node_Kind_Name (N), 6) & " "
                      & Pad_Left (Img (S.First), 2) & ".." & Pad_Right (Img (S.Last), 2) & " "
                      & Img (Pl.Line) & ":" & Img (Pl.Col) & " in "
                      & Pad_Right ((if Up.Found then Node_Kind_Name (Up.N) else "-"), 6)
                      & " """ & Text (Text'First + S.First .. Text'First + S.Last - 1) & """");
         end;
      end if;
      return Continue;
   end Enter;

   Sh : Show;
   Ok : Boolean;
   pragma Unreferenced (Ok);
begin
   Ok := Walk_Config (Tree, Sh);
   Free_Config (Tree);
end Main;
