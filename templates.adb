pragma Ada_2022;

with Ada.Strings.Unbounded;

package body Templates is

   use Ada.Strings.Unbounded;

   --  Replace every occurrence of From in Text with To.
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
   --  ${name} hole rendering.  A template is plain text with ${name} holes;
   --  $$ writes a literal $.  Set adds a binding; Render fills the holes and
   --  marks each used; Unused names the first binding no hole used.
   --  =====================================================================

   procedure Set (B : in out Bindings; Name, Value : String) is
   begin
      for I in 1 .. Natural (B.Slots.Length) loop
         if To_String (B.Slots (I).Name) = Name then
            raise Template_Error with
              "template binding `" & Name & "` set twice";
         end if;
      end loop;
      B.Slots.Append (Slot'(Name  => To_Unbounded_String (Name),
                            Value => To_Unbounded_String (Value),
                            Used  => False));
   end Set;

   function Find_Slot (B : Bindings; Name : String) return Natural is
   begin
      for I in 1 .. Natural (B.Slots.Length) loop
         if To_String (B.Slots (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Slot;

   function Render (Text : String; B : in out Bindings) return String is
      Result : Unbounded_String;
      I      : Natural := Text'First;
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
                  declare
                     Name : constant String := Text (I + 2 .. J - 1);
                     K    : constant Natural := Find_Slot (B, Name);
                  begin
                     if K = 0 then
                        raise Template_Error with
                          "template hole `${" & Name & "}` has no value";
                     end if;
                     Append (Result, To_String (B.Slots (K).Value));
                     B.Slots (K).Used := True;
                  end;
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

   function Unused (B : Bindings) return String is
   begin
      for S of B.Slots loop
         if not S.Used then
            return To_String (S.Name);
         end if;
      end loop;
      return "";
   end Unused;

end Templates;
