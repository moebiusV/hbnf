--  Read a shopping list with the parser hbnf made, and use the tree.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Shopping; use Shopping;
with Shopping.Parser; use Shopping.Parser;

procedure Main is
   LF    : constant Character := Character'Val (10);
   Text  : constant String := "buy 2 apples;" & LF & "buy 1 milk from corner-shop;" & LF;
   Total : Long_Long_Integer := 0;

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;
begin
   declare
      List : List_Type := Parse_Text (Text);
   begin
      for Item of List loop
         Put (Img (Item.Qty) & " x " & To_String (Item.Name));
         for From of Item.Item_1 loop           --  [ ... ] is 0 or 1
            Put (" (from " & To_String (From.Shop) & ")");
         end loop;
         New_Line;
         Total := Total + Item.Qty;
      end loop;
      Free_List (List);
   end;
   Put_Line ("total:" & Long_Long_Integer'Image (Total) & " items");
exception
   when E : Parse_Error =>
      Put_Line (Ada.Exceptions.Exception_Message (E));   --  the message points at the text
end Main;
