--  How a walker, a dump and a pretty-printer are made: plain procedures over the typed tree.
--  Nothing here is generated; it is what you would write.  (The parse is messy on purpose.)
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Shopping; use Shopping;
with Shopping.Parser; use Shopping.Parser;

procedure Tour is
   LF   : constant Character := Character'Val (10);
   Text : constant String :=
     "buy  2   apples ;" & LF & "  buy 1" & LF & " milk from   corner-shop ;";

   function Img (N : Long_Long_Integer) return String is
      S : constant String := Long_Long_Integer'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Pad (Depth : Natural) return String is ((1 .. 2 * Depth => ' '));

   --  Walk: one procedure per rule, children in the order the grammar has them.
   procedure Walk_Item (Item : Item_Type; Depth : Natural) is
   begin
      Put_Line (Pad (Depth) & "item");
      Put_Line (Pad (Depth + 1) & "qty " & Img (Item.Qty));
      Put_Line (Pad (Depth + 1) & "name " & To_String (Item.Name));
      for From of Item.Item_1 loop
         Put_Line (Pad (Depth + 1) & "from");
         Put_Line (Pad (Depth + 2) & "shop " & To_String (From.Shop));
      end loop;
   end Walk_Item;

   --  Dump: the same recursion, but it writes an S-expression.
   procedure Dump_List (List : List_Type) is
   begin
      Put ("(list");
      for Item of List loop
         Put (" (item (qty " & Img (Item.Qty) & ") (name """ & To_String (Item.Name) & """)");
         for From of Item.Item_1 loop
            Put (" (from (shop """ & To_String (From.Shop) & """))");
         end loop;
         Put (")");
      end loop;
      Put_Line (")");
   end Dump_List;

   --  Pretty-print: the text the grammar reads, in one canonical layout.
   procedure Print_List (List : List_Type) is
   begin
      for Item of List loop
         Put ("buy " & Img (Item.Qty) & " " & To_String (Item.Name));
         for From of Item.Item_1 loop
            Put (" from " & To_String (From.Shop));
         end loop;
         Put_Line (";");
      end loop;
   end Print_List;

   List : List_Type := Parse_Text (Text);
begin
   Put_Line ("== walk");
   Put_Line ("list");
   for Item of List loop
      Walk_Item (Item.all, 1);
   end loop;
   Put_Line ("== dump");
   Dump_List (List);
   Put_Line ("== print");
   Print_List (List);
   Free_List (List);
exception
   when Parse_Error =>
      Put_Line ("parse error");
end Tour;
