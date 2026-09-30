pragma Ada_2022;

with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Templates is

   use Ada.Strings.Unbounded;

   package Text_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (String, Unbounded_String);

   use type Text_Maps.Cursor;

   Store : Text_Maps.Map;

   --  =====================================================================
   --  Loading: read every Dir/*.tmpl, keyed by its base name.
   --  =====================================================================

   function Read_File (Path : String) return String is
      F   : Ada.Text_IO.File_Type;
      Buf : Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Append (Buf, Ada.Text_IO.Get_Line (F));
         if not Ada.Text_IO.End_Of_File (F) then
            Append (Buf, ASCII.LF);
         end if;
      end loop;
      Ada.Text_IO.Close (F);
      return To_String (Buf);
   end Read_File;

   procedure Load (Dir : String) is
      Filter : constant Ada.Directories.Filter_Type :=
        (Ada.Directories.Ordinary_File => True, others => False);

      procedure Visit (Dir_Entry : Ada.Directories.Directory_Entry_Type) is
         Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
      begin
         if Name'Length > 5
           and then Name (Name'Last - 4 .. Name'Last) = ".tmpl"
         then
            Store.Insert
              (Name (Name'First .. Name'Last - 5),
               To_Unbounded_String
                 (Read_File (Ada.Directories.Full_Name (Dir_Entry))));
         end if;
      end Visit;
   begin
      Store.Clear;
      Ada.Directories.Search (Dir, "*.tmpl", Filter, Visit'Access);
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         raise Template_Error with "no template directory `" & Dir & "`";
   end Load;

   function Get (Name : String) return String is
      C : constant Text_Maps.Cursor := Store.Find (Name);
   begin
      if C = Text_Maps.No_Element then
         raise Template_Error with "no template `" & Name & "` loaded";
      end if;
      return To_String (Text_Maps.Element (C));
   end Get;

   --  =====================================================================
   --  @PLACEHOLDER@ substitution (the lexer/conf templates).
   --  =====================================================================

   function Substitute (Text, From, To : String) return String is
      Result : Unbounded_String;
      I      : Natural := Text'First;
   begin
      if From'Length = 0 then
         return Text;
      end if;
      while I <= Text'Last loop
         if I + From'Length - 1 <= Text'Last
           and then Text (I .. I + From'Length - 1) = From
         then
            Append (Result, To);
            I := I + From'Length;
         else
            Append (Result, Text (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Result);
   end Substitute;

   --  =====================================================================
   --  ${name} hole rendering from a table of name/value rows.
   --  =====================================================================

   function Bind (Name, Value : String) return Binding is
   begin
      return Binding'(Name  => To_Unbounded_String (Name),
                      Value => To_Unbounded_String (Value));
   end Bind;

   function Render (Text : String; Pairs : Binding_Array) return String is
      Result : Unbounded_String;
      I      : Natural := Text'First;

      function Lookup (Name : String) return String is
      begin
         for P of Pairs loop
            if To_String (P.Name) = Name then
               return To_String (P.Value);
            end if;
         end loop;
         raise Template_Error with
           "template hole `${" & Name & "}` has no value";
      end Lookup;
   begin
      while I <= Text'Last loop
         if Text (I) = '$' then
            if I < Text'Last and then Text (I + 1) = '$' then
               Append (Result, '$');
               I := I + 2;
            elsif I < Text'Last and then Text (I + 1) = '{' then
               declare
                  J : Natural := I + 2;
               begin
                  while J <= Text'Last and then Text (J) /= '}' loop
                     J := J + 1;
                  end loop;
                  if J > Text'Last then
                     raise Template_Error with
                       "a template hole has no closing `}`";
                  end if;
                  Append (Result, Lookup (Text (I + 2 .. J - 1)));
                  I := J + 1;
               end;
            else
               raise Template_Error with
                 "a `$` in a template must be `$$` or `${name}`";
            end if;
         else
            Append (Result, Text (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Result);
   end Render;

end Templates;
