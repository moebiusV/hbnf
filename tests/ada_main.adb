with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Server_Schema;
with Server_Schema.Parser;

procedure Ada_Main is
   use Ada.Strings.Unbounded;
   use Server_Schema.Parser;

   procedure Run (Name : String; Toks : Token_Vectors.Vector) is
      Lines : Line_Vectors.Vector;
   begin
      Lines.Append (To_Unbounded_String ("example.com"));
      Lines.Append (To_Unbounded_String ("on wg0 port oops"));
      Lines.Append (To_Unbounded_String ("/var/www"));
      Lines.Append (To_Unbounded_String ("www"));
      Lines.Append (To_Unbounded_String ("yes"));
      begin
         declare
            R : Server_Schema.Server_Type := Parse_Config (Toks, Lines);
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

   Valid : Token_Vectors.Vector;
   Bad   : Token_Vectors.Vector;
begin
   Valid.Append (Token'(Str, To_Unbounded_String ("example.com"), 1, 1));
   Valid.Append (Token'(Atom, To_Unbounded_String ("on"), 2, 1));
   Valid.Append (Token'(Atom, To_Unbounded_String ("wg0"), 2, 4));
   Valid.Append (Token'(Atom, To_Unbounded_String ("port"), 2, 8));
   Valid.Append (Token'(Int, To_Unbounded_String ("443"), 2, 13));
   Valid.Append (Token'(Str, To_Unbounded_String ("/var/www"), 3, 1));
   Valid.Append (Token'(Str, To_Unbounded_String ("www"), 4, 1));
   Valid.Append (Token'(Atom, To_Unbounded_String ("yes"), 5, 1));
   Valid.Append (Token'(Eof, Null_Unbounded_String, 5, 1));

   Bad.Append (Token'(Str, To_Unbounded_String ("example.com"), 1, 1));
   Bad.Append (Token'(Atom, To_Unbounded_String ("on"), 2, 1));
   Bad.Append (Token'(Atom, To_Unbounded_String ("wg0"), 2, 4));
   Bad.Append (Token'(Atom, To_Unbounded_String ("port"), 2, 8));
   Bad.Append (Token'(Atom, To_Unbounded_String ("oops"), 2, 13));
   Bad.Append (Token'(Eof, Null_Unbounded_String, 5, 1));

   Run ("valid", Valid);
   Run ("malformed", Bad);
end Ada_Main;
