--  A pretty-printer's say in how the tree is written (Layout): a newline before every "buy" but the
--  first, "from" in capitals, and a log of the rules entered.
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Shopping; use Shopping;
with Shopping.Parser; use Shopping.Parser;

procedure Layout_Main is
   LF   : constant Character := Character'Val (10);
   Text : constant String := "buy 2 apples;" & LF & "buy 1 milk from corner-shop;" & LF;

   type Pretty is new Layout with record
      Buys : Natural := 0;
      Log  : Unbounded_String;
   end record;
   overriding function Before (L : in out Pretty; S : String) return Opt_Text;
   overriding function Replace (L : in out Pretty; S : String) return Opt_Text;
   overriding procedure On_Enter (L : in out Pretty; Rule : String);

   overriding function Before (L : in out Pretty; S : String) return Opt_Text is
   begin
      if S = "buy" then
         L.Buys := L.Buys + 1;
         if L.Buys > 1 then
            return (Found => True, Text => To_Unbounded_String ((1 => LF)));
         end if;
      end if;
      return (Found => False);
   end Before;

   overriding function Replace (L : in out Pretty; S : String) return Opt_Text is
      pragma Unreferenced (L);
   begin
      if S = "from" then
         return (Found => True, Text => To_Unbounded_String ("FROM"));
      end if;
      return (Found => False);
   end Replace;

   overriding procedure On_Enter (L : in out Pretty; Rule : String) is
   begin
      Append (L.Log, " " & Rule);
   end On_Enter;

   List : List_Type := Parse_Text (Text);
   P    : Pretty;
   Out_T : Unbounded_String;
   Ok   : Boolean;
   Msg  : Unbounded_String;
begin
   Write_List_With (List, P, Out_T, Ok, Msg);
   Put_Line (To_String (Out_T));
   Put_Line ("rules:" & To_String (P.Log));
   Free_List (List);
end Layout_Main;
