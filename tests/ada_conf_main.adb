with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Server_Schema;
with Server_Schema.Parser;

procedure Ada_Conf_Main is
   use Ada.Strings.Unbounded;
   use Server_Schema.Parser;
begin
   declare
      R : Server_Schema.Server_Type := Parse_Config ("valid.conf");
   begin
      Ada.Text_IO.Put_Line
        ("valid: OK name=" & To_String (R.Name)
         & " port=" & Natural'Image (Natural (R.Listen.Port)));
   end;

   begin
      declare
         R : Server_Schema.Server_Type := Parse_Config ("bad.conf");
      begin
         Ada.Text_IO.Put_Line ("bad: unexpectedly OK name=" & To_String (R.Name));
      end;
   exception
      when E : Parse_Error =>
         Ada.Text_IO.Put_Line ("bad: handled by exception:");
         Ada.Text_IO.Put_Line (Ada.Exceptions.Exception_Message (E));
   end;
end Ada_Conf_Main;
