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

end Templates;
