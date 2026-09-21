with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Server_Schema;
with Server_Schema.Parser;

procedure Ada_Main is
   use Ada.Strings.Unbounded;
   use Server_Schema.Parser;

   Valid : constant String :=
     """example.com""" & ASCII.LF &
     "on wg0 port 443" & ASCII.LF &
     """/var/www""" & ASCII.LF &
     """www""" & ASCII.LF &
     "yes" & ASCII.LF;

   Bad : constant String :=
     """example.com""" & ASCII.LF &
     "on wg0 port oops" & ASCII.LF &
     """/var/www""" & ASCII.LF &
     """www""" & ASCII.LF &
     "yes" & ASCII.LF;

   procedure Run (Name : String; Text : String) is
   begin
      begin
         declare
            R : Server_Schema.Server_Type := Parse_Text (Text);
         begin
            Ada.Text_IO.Put_Line
              (Name & ": OK name=" & To_String (R.Name)
               & " port=" & Natural'Image (Natural (R.Listen.Port)));
         end;
      exception
         when E : Parse_Error =>
            Ada.Text_IO.Put_Line
              (Name & ": " & Ada.Exceptions.Exception_Message (E));
      end;
   end Run;
begin
   Run ("valid", Valid);
   Run ("malformed", Bad);
end Ada_Main;
