pragma Ada_2022;

with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body HBNF_Compilable is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

   function Has_Alt (V : Element_Vectors.Vector) return Boolean is
     (for some E of V => E.Kind = Alt);

   procedure Reject (Rule_Name, What : String) is
   begin
      raise Parse_Error with
        Rule_Name & ": " & What & " inside a sequence is not supported by "
        & "the compiled backends yet; move it into a rule of its own";
   end Reject;

   --  Walk a sequence (or an alternation's branches).  Sole is True when V
   --  is a rule's whole pattern and has exactly one element: that element's
   --  repetition or grouping is the rule itself (a list, an optional rule,
   --  a grouped alternation) and the emitters handle it.
   procedure Walk
     (Rule_Name : String; V : Element_Vectors.Vector; Sole : Boolean) is
   begin
      for E of V loop
         case E.Kind is
            when Group =>
               if not Sole then
                  if E.Min /= 1 or else E.Max /= 1 then
                     Reject (Rule_Name,
                             (if E.Min = 0 and then E.Max = 1
                              then "an optional [ ]"
                              else "a repeated group"));
                  elsif Has_Alt (E.Items) then
                     Reject (Rule_Name, "an alternation group ( a / b )");
                  end if;
               end if;
               Walk (Rule_Name, E.Items, False);
            when Name =>
               if not Sole and then (E.Min /= 1 or else E.Max /= 1) then
                  Reject (Rule_Name,
                          "a repeated reference to " & To_String (E.Name));
               end if;
            when Literal | Alt =>
               null;
         end case;
      end loop;
   end Walk;

   function Find (Rules : Rule_Vectors.Vector; Name : String) return Natural is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if To_String (Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   function Is_List_Rule (R : Rule) return Boolean is
     (Natural (R.Pattern.Length) = 1
      and then R.Jet_Code = Null_Unbounded_String
      and then not (R.Pattern (1).Min = 1 and then R.Pattern (1).Max = 1));

   procedure Append_Comma (S : in out Unbounded_String; Item : String) is
   begin
      if S /= Null_Unbounded_String then
         Append (S, ", ");
      end if;
      Append (S, Item);
   end Append_Comma;

   procedure Check
     (Rules   : HBNF_Grammar.Rule_Vectors.Vector;
      Backend : String) is
   begin
      if Natural (Rules.Length) = 0 then
         raise Parse_Error with "the schema defines no rules";
      end if;

      --  A listops block overrides hbnf's built-in list operation by
      --  operation.  The seven structural operations form one list, so a
      --  partial block (mixing overridden and built-in operations) would
      --  generate a list whose parts do not fit together.  Require all seven
      --  when any is given; relink stays optional.
      if Backend = "c" then
         declare
            Ops     : constant array (Positive range <>) of Unbounded_String :=
              (To_Unbounded_String ("head"), To_Unbounded_String ("entry"),
               To_Unbounded_String ("init"), To_Unbounded_String ("append"),
               To_Unbounded_String ("foreach"), To_Unbounded_String ("first"),
               To_Unbounded_String ("next"));
            Given   : Unbounded_String;
            Missing : Unbounded_String;
         begin
            for Op of Ops loop
               if List_Override (To_String (Op)) /= "" then
                  Append_Comma (Given, To_String (Op));
               else
                  Append_Comma (Missing, To_String (Op));
               end if;
            end loop;
            if Given /= Null_Unbounded_String
              and then Missing /= Null_Unbounded_String
            then
               raise Parse_Error with
                 "listops: gives " & To_String (Given) & " but not "
                 & To_String (Missing)
                 & "; give all of head, entry, init, append, foreach, first, "
                 & "next (relink is optional)";
            end if;
         end;
      end if;

      for R of Rules loop
         declare
            P : constant Element_Vectors.Vector := R.Pattern;
            N : constant String := To_String (R.Name);
         begin
            Walk (N, P, Natural (P.Length) = 1);
            --  An alias of a list rule would take the list's node type,
            --  not its head type, in every backend.
            if Natural (P.Length) = 1 and then P (1).Kind = Name
              and then P (1).Min = 1 and then P (1).Max = 1
            then
               declare
                  T : constant Natural := Find (Rules, To_String (P (1).Name));
               begin
                  if T /= 0 and then Is_List_Rule (Rules (T)) then
                     raise Parse_Error with
                       N & ": an alias of the list rule `"
                       & To_String (P (1).Name) & "` is not supported yet; "
                       & "define " & N & " as a list of the same element";
                  end if;
               end;
            end if;
            if Backend /= "c"
              and then Natural (P.Length) = 1
              and then not (P (1).Min = 1 and then P (1).Max = 1)
              and then not (P (1).Min = 0 and then P (1).Max = -1)
            then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "hbnf: warning: " & N & ": repetition bounds are enforced "
                  & "by the C backend only; the " & Backend
                  & " backend treats this rule as *");
            end if;
         end;
      end loop;
   end Check;

end HBNF_Compilable;
