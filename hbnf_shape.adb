pragma Ada_2022;

package body HBNF_Shape is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

   --  Natural'Image with the leading blank stripped ("1", not " 1").
   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      if S'Length > 0 and then S (S'First) = ' ' then
         return S (S'First + 1 .. S'Last);
      end if;
      return S;
   end Img;

   --  True when every `|`-alternative is exactly one Literal — the shape an
   --  enum can hold.  A multi-token alternative (`"a" "b" | "c" "d"`), one that
   --  names another rule, or a single literal (no `|`) is not an enum.
   function Is_Pure_Literal_Alt (Els : Element_Vectors.Vector) return Boolean is
      N       : constant Natural := Natural (Els.Length);
      St      : Natural := 1;
      Has_Alt : Boolean := False;
   begin
      for K in 1 .. N + 1 loop
         if K > N then
            --  final alternative [St..N] must be exactly one literal
            if N /= St or else Els (St).Kind /= Literal then
               return False;
            end if;
         elsif Els (K).Kind = Alt then
            --  alternative [St..K-1] must be exactly one literal
            if K - 1 /= St or else Els (St).Kind /= Literal then
               return False;
            end if;
            St := K + 1;
            Has_Alt := True;
         end if;
      end loop;
      return Has_Alt;
   end Is_Pure_Literal_Alt;

   --  A valid C identifier from a rule name ('-' -> '_').
   function C_Name (S : String) return String is
      Buf : U;
   begin
      for C of HBNF_Grammar.Prefixed (S) loop
         Append (Buf, (if C = '-' then '_' else C));
      end loop;
      return To_String (Buf);
   end C_Name;

   --  A struct member name, kept clear of C keywords (the core types `int`,
   --  `float` and `bool` are C keywords/macros, so a field named after them
   --  would not compile).
   function C_Field (S : String) return String is
      N : constant String := C_Name (S);
   begin
      if N = "int" or else N = "float" or else N = "bool"
        or else N = "char" or else N = "double" or else N = "long"
        or else N = "short" or else N = "signed" or else N = "unsigned"
        or else N = "void" or else N = "const" or else N = "struct"
        or else N = "union" or else N = "enum" or else N = "auto"
        or else N = "break" or else N = "case" or else N = "continue"
        or else N = "default" or else N = "do" or else N = "else"
        or else N = "extern" or else N = "for" or else N = "goto"
        or else N = "if" or else N = "inline" or else N = "register"
        or else N = "restrict" or else N = "return" or else N = "sizeof"
        or else N = "static" or else N = "switch" or else N = "typedef"
        or else N = "volatile" or else N = "while"
      then
         return N & "_";
      end if;
      return N;
   end C_Field;

   function Contains (V : Member_Vectors.Vector; S : U) return Boolean is
   begin
      for X of V loop
         if X.Name = S then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   procedure Collect
     (Els     : Element_Vectors.Vector;
      Members : in out Member_Vectors.Vector;
      Lits    : in out String_Vectors.Vector;
      Has_Alt : in out Boolean) is
      Seen : String_Vectors.Vector;

      function Seen_Here (S : U) return Boolean is
      begin
         for X of Seen loop
            if X = S then
               return True;
            end if;
         end loop;
         return False;
      end Seen_Here;
   begin
      for E of Els loop
         case E.Kind is
            when Name =>
               declare
                  Is_List : constant Boolean :=
                    E.Min /= 1 or else E.Max /= 1;
               begin
                  if Is_Hidden (To_String (E.Name)) then
                     null;   --  matched, and kept nowhere
                  else
                     if Seen_Here (E.Name) then
                        raise Parse_Error with
                          "rule """ & To_String (E.Name)
                          & """ is referenced twice in one alternative;"
                          & " split it into alias rules (e.g. `a = "
                          & To_String (E.Name) & "; b = " & To_String (E.Name)
                          & ";`) so each gets its own field";
                     end if;
                     Seen.Append (E.Name);
                     if Contains (Members, E.Name) then
                        if Is_List then
                           for K in 1 .. Natural (Members.Length) loop
                              if Members (K).Name = E.Name then
                                 Members.Replace_Element
                                   (K,
                                    Member'(Name => E.Name, Is_List => True));
                              end if;
                           end loop;
                        end if;
                     else
                        Members.Append
                          (Member'(Name => E.Name, Is_List => Is_List));
                     end if;
                  end if;
               end;
            when Literal =>
               Lits.Append (E.Lit);
            when Alt =>
               Has_Alt := True;
               Seen.Clear;
            when Group =>
               Collect (E.Items, Members, Lits, Has_Alt);
            when Char_Range =>
               null;
            when Block =>
               null;  --  lifted to a rule of its own before emission
            when Bit_Field =>
               null;     --  a rule with bit fields never reaches here (Split_Wire)
            when Negation =>
               null;   --  resolved into a rule of ranges before this runs
         end case;
      end loop;
   end Collect;

   --  The names of the alternatives of a flat list of elements (Alt
   --  separators): a branch's first word-like literal, else its first rule
   --  name, else ALT<n>; a name already taken gets its branch number.  They
   --  are what node_alt_name returns and what the constants of <rule>_alt_t
   --  are spelled from (--ast).
   function Alt_Labels (Els : Element_Vectors.Vector)
      return String_Vectors.Vector
   is
      Res : String_Vectors.Vector;
      N   : constant Natural := Natural (Els.Length);
      St  : Natural := 1;
      Br  : Natural := 0;

      function Img (X : Natural) return String is
         S : constant String := Natural'Image (X);
      begin
         return S (S'First + 1 .. S'Last);
      end Img;

      function Taken (S : String) return Boolean is
        (for some X of Res => To_String (X) = S);
   begin
      for K in 1 .. N + 1 loop
         if K > N or else Els (K).Kind = Alt then
            Br := Br + 1;
            declare
               Lab : U := Null_Unbounded_String;
            begin
               if St <= K - 1 and then HBNF_Grammar.Label_Of (Els (St)) /= ""
               then
                  Lab := To_Unbounded_String (HBNF_Grammar.Label_Of (Els (St)));
               end if;
               for J in St .. K - 1 loop
                  exit when Lab /= Null_Unbounded_String;
                  if Els (J).Kind = Literal then
                     declare
                        L  : constant String := To_String (Els (J).Lit);
                        Ok : Boolean := L'Length > 0;
                     begin
                        for C of L loop
                           if not (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
                                     | '_' | '-')
                           then
                              Ok := False;
                           end if;
                        end loop;
                        if Ok then
                           Lab := To_Unbounded_String (L);
                           exit;
                        end if;
                     end;
                  elsif Els (J).Kind = Name then
                     Lab := Els (J).Name;
                     exit;
                  end if;
               end loop;
               if Lab = Null_Unbounded_String then
                  Lab := To_Unbounded_String ("alt" & Img (Br));
               end if;
               if Taken (To_String (Lab)) then
                  Lab := To_Unbounded_String (To_String (Lab) & "_" & Img (Br));
               end if;
               Res.Append (Lab);
            end;
            St := K + 1;
         end if;
      end loop;
      return Res;
   end Alt_Labels;

   function Member_Label (Name : String) return String is (C_Field (Name));

   function Alt_Label
     (Els : HBNF_Grammar.Element_Vectors.Vector; Branch : Positive)
      return String is
     (To_String (Alt_Labels (Els) (Branch)));

end HBNF_Shape;
