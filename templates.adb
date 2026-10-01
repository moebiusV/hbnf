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
   use type Value_Maps.Cursor;

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

   --  =====================================================================
   --  Recursive context model: builders and the scope stack.
   --  =====================================================================

   function New_Scalar (Text : String) return Value_Access is
     (new Template_Value'(Kind => Scalar, Text => To_Unbounded_String (Text)));

   function New_List return Value_Access is
     (new Template_Value'(Kind => List, Items => Value_Lists.Empty_Vector));

   function New_Map return Value_Access is
     (new Template_Value'(Kind => Map, Fields => Value_Maps.Empty_Map));

   procedure Append (V : Value_Access; Item : Value_Access) is
   begin
      case V.Kind is
         when List =>
            V.Items.Append (Item);
         when others =>
            raise Template_Error with "append to a non-list template value";
      end case;
   end Append;

   procedure Insert (V : Value_Access; Key : String; Item : Value_Access) is
   begin
      case V.Kind is
         when Map =>
            if V.Fields.Contains (Key) then
               raise Template_Error with
                 "template key `" & Key & "` bound twice";
            end if;
            V.Fields.Insert (Key, Item);
         when others =>
            raise Template_Error with "insert into a non-map template value";
      end case;
   end Insert;

   function Context (Root : Value_Access) return Template_Context is
      Ctx : Template_Context;
   begin
      Ctx.Scopes.Append (Root);
      return Ctx;
   end Context;

   procedure Push (Ctx : in out Template_Context; Scope : Value_Access) is
   begin
      Ctx.Scopes.Append (Scope);
   end Push;

   procedure Pop (Ctx : in out Template_Context) is
   begin
      Ctx.Scopes.Delete_Last;
   end Pop;

   --  =====================================================================
   --  Mustache-subset renderer over the recursive context model.
   --  =====================================================================

   type Token_Kind is
     (Text, Interp, Section_Open, Inverted_Open, Section_Close, Partial);

   type Token is record
      Kind : Token_Kind;
      Name : Unbounded_String;   --  Text: the literal; else the tag body
   end record;

   package Token_Lists is new Ada.Containers.Vectors (Positive, Token);

   function Trim (S : String) return String is
      F : Natural := S'First;
      L : Natural := S'Last;
   begin
      while F <= L and then (S (F) = ' ' or else S (F) = ASCII.HT) loop
         F := F + 1;
      end loop;
      while L >= F and then (S (L) = ' ' or else S (L) = ASCII.HT) loop
         L := L - 1;
      end loop;
      if F > L then
         return "";
      end if;
      return S (F .. L);
   end Trim;

   function Tokenize (Source : String) return Token_Lists.Vector is
      Result : Token_Lists.Vector;
      I      : Natural := Source'First;
      Lit    : Unbounded_String;

      procedure Flush is
      begin
         if Lit /= Null_Unbounded_String then
            Result.Append (Token'(Text, Lit));
            Lit := Null_Unbounded_String;
         end if;
      end Flush;
   begin
      while I <= Source'Last loop
         if I < Source'Last
           and then Source (I) = '{' and then Source (I + 1) = '{'
         then
            Flush;
            declare
               J : Natural := I + 2;
            begin
               while J < Source'Last
                 and then not (Source (J) = '}' and then Source (J + 1) = '}')
               loop
                  J := J + 1;
               end loop;
               if J >= Source'Last then
                  raise Template_Error with "a `{{` has no closing `}}`";
               end if;
               declare
                  Tag : constant String := Trim (Source (I + 2 .. J - 1));
               begin
                  if Tag'Length = 0 then
                     Result.Append (Token'(Interp, To_Unbounded_String ("")));
                  else
                     case Tag (Tag'First) is
                        when '#' =>
                           Result.Append (Token'(Section_Open,
                             To_Unbounded_String
                               (Trim (Tag (Tag'First + 1 .. Tag'Last)))));
                        when '^' =>
                           Result.Append (Token'(Inverted_Open,
                             To_Unbounded_String
                               (Trim (Tag (Tag'First + 1 .. Tag'Last)))));
                        when '>' =>
                           Result.Append (Token'(Partial,
                             To_Unbounded_String
                               (Trim (Tag (Tag'First + 1 .. Tag'Last)))));
                        when '/' =>
                           Result.Append (Token'(Section_Close,
                             To_Unbounded_String
                               (Trim (Tag (Tag'First + 1 .. Tag'Last)))));
                        when others =>
                           Result.Append (Token'(Interp, To_Unbounded_String (Tag)));
                     end case;
                  end if;
               end;
               I := J + 2;
            end;
         else
            Append (Lit, Source (I));
            I := I + 1;
         end if;
      end loop;
      Flush;
      return Result;
   end Tokenize;

   function Lookup (Ctx : Template_Context; Name : String) return Value_Access is
   begin
      for I in reverse 1 .. Ctx.Scopes.Last_Index loop
         declare
            Scope : constant Value_Access := Ctx.Scopes (I);
         begin
            if Scope.Kind = Map then
               declare
                  C : constant Value_Maps.Cursor := Scope.Fields.Find (Name);
               begin
                  if C /= Value_Maps.No_Element then
                     return Value_Maps.Element (C);
                  end if;
               end;
            end if;
         end;
      end loop;
      return null;
   end Lookup;

   function Interpolate (Ctx : Template_Context; Name : String) return String is
      V : constant Value_Access := Lookup (Ctx, Name);
   begin
      if V = null then
         raise Template_Error with "no value for `{{" & Name & "}}`";
      elsif V.Kind /= Scalar then
         raise Template_Error with "`{{" & Name & "}}` is not a scalar";
      end if;
      return To_String (V.Text);
   end Interpolate;

   function Current_Scalar (Ctx : Template_Context) return String is
   begin
      if Ctx.Scopes.Is_Empty then
         raise Template_Error with "`{{.}}` outside any section";
      end if;
      declare
         Top : constant Value_Access := Ctx.Scopes (Ctx.Scopes.Last_Index);
      begin
         if Top.Kind /= Scalar then
            raise Template_Error with "`{{.}}` has no scalar value here";
         end if;
         return To_String (Top.Text);
      end;
   end Current_Scalar;

   function Find_Close
     (Tokens : Token_Lists.Vector; Open : Positive) return Positive
   is
      Depth : Natural := 0;
   begin
      for I in Open .. Tokens.Last_Index loop
         case Tokens (I).Kind is
            when Section_Open | Inverted_Open =>
               Depth := Depth + 1;
            when Section_Close =>
               Depth := Depth - 1;
               if Depth = 0 then
                  return I;
               end if;
            when others =>
               null;
         end case;
      end loop;
      raise Template_Error with "a section has no closing tag";
   end Find_Close;

   function Render_Template
     (Name : String; Ctx : Template_Context) return String
   is
      Tokens : constant Token_Lists.Vector := Tokenize (Get (Name));

      function Render_Range
        (First : Positive; Last : Natural;
         Ctx   : Template_Context) return String
      is
         Result : Unbounded_String;
         I      : Natural := First;
      begin
         while I <= Last loop
            declare
               T : constant Token := Tokens (I);
            begin
               case T.Kind is
                  when Text =>
                     Append (Result, To_String (T.Name));
                  when Interp =>
                     if To_String (T.Name) = "." then
                        Append (Result, Current_Scalar (Ctx));
                     else
                        Append (Result, Interpolate (Ctx, To_String (T.Name)));
                     end if;
                  when Partial =>
                     Append (Result, Render_Template (To_String (T.Name), Ctx));
                  when Section_Open =>
                     declare
                        J    : constant Positive := Find_Close (Tokens, I);
                        Tag  : constant String := To_String (T.Name);
                        Each : constant Boolean :=
                          Tag'Length > 5
                          and then Tag (Tag'First .. Tag'First + 4) = "each ";
                        Name : constant String :=
                          (if Each then Tag (Tag'First + 5 .. Tag'Last)
                           else Tag);
                        V    : constant Value_Access := Lookup (Ctx, Name);
                        C    : Template_Context := Ctx;
                     begin
                        if Each then
                           if V = null then
                              raise Template_Error with
                                "no value for `{{#each " & Name & "}}`";
                           elsif V.Kind /= List then
                              raise Template_Error with
                                "`{{#each " & Name & "}}` is not a list";
                           end if;
                           for E of V.Items loop
                              Push (C, E);
                              Append (Result,
                                Render_Range (I + 1, J - 1, C));
                              Pop (C);
                           end loop;
                        elsif V = null then
                           null;
                        elsif V.Kind = List then
                           for E of V.Items loop
                              Push (C, E);
                              Append (Result,
                                Render_Range (I + 1, J - 1, C));
                              Pop (C);
                           end loop;
                        elsif V.Kind = Map then
                           Push (C, V);
                           Append (Result, Render_Range (I + 1, J - 1, C));
                           Pop (C);
                        elsif To_String (V.Text) /= "" then
                           Push (C, V);
                           Append (Result, Render_Range (I + 1, J - 1, C));
                           Pop (C);
                        end if;
                        I := J;
                     end;
                  when Inverted_Open =>
                     declare
                        J     : constant Positive := Find_Close (Tokens, I);
                        Name  : constant String := To_String (T.Name);
                        V     : constant Value_Access := Lookup (Ctx, Name);
                        Empty : Boolean;
                     begin
                        if V = null then
                           Empty := True;
                        else
                           case V.Kind is
                              when Scalar => Empty := (To_String (V.Text) = "");
                              when List   => Empty := V.Items.Is_Empty;
                              when Map    => Empty := False;
                           end case;
                        end if;
                        if Empty then
                           Append (Result, Render_Range (I + 1, J - 1, Ctx));
                        end if;
                        I := J;
                     end;
                  when Section_Close =>
                     raise Template_Error with "unmatched closing tag";
               end case;
            end;
            I := I + 1;
         end loop;
         return To_String (Result);
      end Render_Range;
   begin
      if Tokens.Is_Empty then
         return "";
      end if;
      return Render_Range (1, Tokens.Last_Index, Ctx);
   end Render_Template;

end Templates;
