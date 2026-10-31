pragma Ada_2022;

with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with HBNF_Template_Syntax;
with HBNF_Template_Syntax.Parser;

package body HBNF_Template is

   use Ada.Strings.Unbounded;
   use HBNF_Template_Syntax;

   package Text_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (String, Unbounded_String);

   type Template_Access is access Template_Type;

   --  A template is read once: the tree is kept under the name it was loaded by.
   package Tree_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (String, Template_Access);

   use type Text_Maps.Cursor;
   use type Tree_Maps.Cursor;
   use type Value_Maps.Cursor;

   Store : Text_Maps.Map;
   Trees : Tree_Maps.Map;

   --  =====================================================================
   --  Loading and defining templates.
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
        [Ada.Directories.Ordinary_File => True, others => False];

      procedure Visit (Dir_Entry : Ada.Directories.Directory_Entry_Type) is
         Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
      begin
         if Name'Length > 5
           and then Name (Name'Last - 4 .. Name'Last) = ".tmpl"
         then
            Define
              (Name (Name'First .. Name'Last - 5),
               Read_File (Ada.Directories.Full_Name (Dir_Entry)));
         end if;
      end Visit;
   begin
      Ada.Directories.Search (Dir, "*.tmpl", Filter, Visit'Access);
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         raise Template_Error with "no template directory `" & Dir & "`";
   end Load;

   procedure Define (Name : String; Source : String) is
   begin
      Store.Include (Name, To_Unbounded_String (Source));
      Trees.Exclude (Name);
   end Define;

   function Get (Name : String) return String is
      C : constant Text_Maps.Cursor := Store.Find (Name);
   begin
      if C = Text_Maps.No_Element then
         raise Template_Error with "no template `" & Name & "` loaded";
      end if;
      return To_String (Text_Maps.Element (C));
   end Get;

   --  =====================================================================
   --  Values.
   --  =====================================================================

   function New_Scalar (Text : String) return Value_Access is
     (new Value'(Kind => Scalar, Text => To_Unbounded_String (Text)));

   function New_List return Value_Access is
     (new Value'(Kind => List, Items => Value_Lists.Empty_Vector));

   function New_Map return Value_Access is
     (new Value'(Kind => Map, Fields => Value_Maps.Empty_Map));

   procedure Append (V : Value_Access; Item : Value_Access) is
   begin
      if V.Kind /= List then
         raise Template_Error with "append to a value that is not a list";
      end if;
      V.Items.Append (Item);
   end Append;

   procedure Insert (V : Value_Access; Key : String; Item : Value_Access) is
   begin
      if V.Kind /= Map then
         raise Template_Error with "insert into a value that is not a map";
      end if;
      V.Fields.Include (Key, Item);
   end Insert;

   function View return Context is
      Ctx : Context;
   begin
      Ctx.Scopes.Append (New_Map);
      return Ctx;
   end View;

   procedure Put (Ctx : in out Context; Key : String; Value : String) is
   begin
      Insert (Ctx.Scopes (Ctx.Scopes.Last_Index), Key, New_Scalar (Value));
   end Put;

   procedure Put (Ctx : in out Context; Key : String; Value : Value_Access) is
   begin
      Insert (Ctx.Scopes (Ctx.Scopes.Last_Index), Key, Value);
   end Put;

   --  =====================================================================
   --  Reading a template.
   --
   --  Mustache drops a line that holds a section tag or a comment and nothing but blanks besides, the
   --  newline with it.  The grammar knows nothing of lines, so that is done to the text before it is
   --  read: the blanks before such a tag, the tag's neighbours and the line end are taken out whole.
   --  =====================================================================

   function Is_Blank (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT);

   function Is_Break (C : Character) return Boolean is
     (C = ASCII.LF or else C = ASCII.CR);

   function Strip_Standalone (Source : String) return String is
      Result : Unbounded_String;
      I      : Natural := Source'First;

      function Starts (P : Natural; S : String) return Boolean is
        (P + S'Length - 1 <= Source'Last and then Source (P .. P + S'Length - 1) = S);

      --  The first character from P on that is not a blank (the sigil of a tag, if it has one).
      function First_Past_Blanks (P : Natural) return Character is
         Q : Natural := P;
      begin
         while Q <= Source'Last and then (Is_Blank (Source (Q)) or else Is_Break (Source (Q))) loop
            Q := Q + 1;
         end loop;
         return (if Q <= Source'Last then Source (Q) else ' ');
      end First_Past_Blanks;

      --  Is the tag at Tag_Start .. Tag_End alone on its line?
      function Is_Standalone (Tag_Start, Tag_End : Natural) return Boolean is
         P : Integer := Tag_Start - 1;
         Q : Natural := Tag_End + 1;
      begin
         while P >= Source'First and then Is_Blank (Source (P)) loop
            P := P - 1;
         end loop;
         if P >= Source'First and then not Is_Break (Source (P)) then
            return False;
         end if;
         while Q <= Source'Last and then Is_Blank (Source (Q)) loop
            Q := Q + 1;
         end loop;
         return Q > Source'Last or else Is_Break (Source (Q));
      end Is_Standalone;

      --  Take back the blanks the text ended in: they were the line's indent.
      procedure Drop_Indent is
         L : Natural := Length (Result);
      begin
         while L > 0 and then Is_Blank (Element (Result, L)) loop
            L := L - 1;
         end loop;
         Head (Result, L);
      end Drop_Indent;

      --  The position after the blanks and the line end that follow a tag ending at From - 1.
      function After_Line (From : Natural) return Natural is
         Q : Natural := From;
      begin
         while Q <= Source'Last and then Is_Blank (Source (Q)) loop
            Q := Q + 1;
         end loop;
         if Q <= Source'Last and then Source (Q) = ASCII.CR then
            if Q < Source'Last and then Source (Q + 1) = ASCII.LF then
               Q := Q + 1;
            end if;
            return Q + 1;
         elsif Q <= Source'Last and then Source (Q) = ASCII.LF then
            return Q + 1;
         end if;
         return Q;
      end After_Line;
   begin
      while I <= Source'Last loop
         if Starts (I, "{{") then
            declare
               Triple  : constant Boolean := Starts (I, "{{{");
               Close   : constant String := (if Triple then "}}}" else "}}");
               J       : constant Natural :=
                 Ada.Strings.Fixed.Index (Source, Close, I + (if Triple then 3 else 2));
            begin
               if J = 0 then
                  raise Template_Error with "an unterminated tag";
               end if;
               declare
                  Tag_End : constant Natural := J + Close'Length - 1;
                  Sigil   : constant Character := First_Past_Blanks (I + 2);
               begin
                  if not Triple and then Sigil in '#' | '^' | '/' | '!'
                    and then Is_Standalone (I, Tag_End)
                  then
                     Drop_Indent;
                     Append (Result, Source (I .. Tag_End));
                     I := After_Line (Tag_End + 1);
                  else
                     Append (Result, Source (I .. Tag_End));
                     I := Tag_End + 1;
                  end if;
               end;
            end;
         else
            Append (Result, Source (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Result);
   end Strip_Standalone;

   --  =====================================================================
   --  Names and truth.
   --  =====================================================================

   function Is_Truthy (V : Value_Access) return Boolean is
   begin
      if V = null then
         return False;
      end if;
      case V.Kind is
         when Scalar => return Length (V.Text) > 0;
         when List   => return not V.Items.Is_Empty;
         when Map    => return True;
      end case;
   end Is_Truthy;

   function Find_Dot (Name : String) return Natural is
     (Ada.Strings.Fixed.Index (Name, "."));

   function Resolve_Tail (M : Value_Access; Name : String) return Value_Access is
      Dot : constant Natural := Find_Dot (Name);
   begin
      if M = null or else M.Kind /= Map then
         return null;
      end if;
      declare
         Head : constant String := (if Dot = 0 then Name else Name (Name'First .. Dot - 1));
         Tail : constant String := (if Dot = 0 then "" else Name (Dot + 1 .. Name'Last));
         C    : constant Value_Maps.Cursor := M.Fields.Find (Head);
      begin
         if C = Value_Maps.No_Element then
            return null;
         elsif Tail = "" then
            return Value_Maps.Element (C);
         end if;
         return Resolve_Tail (Value_Maps.Element (C), Tail);
      end;
   end Resolve_Tail;

   function Resolve (Ctx : Context; Name : String) return Value_Access is
      Dot  : constant Natural := Find_Dot (Name);
      Head : constant String := (if Dot = 0 then Name else Name (Name'First .. Dot - 1));
      Tail : constant String := (if Dot = 0 then "" else Name (Dot + 1 .. Name'Last));
      Found : Value_Access := null;
   begin
      if Name = "." then
         return Ctx.Scopes (Ctx.Scopes.Last_Index);
      end if;
      for I in reverse 1 .. Ctx.Scopes.Last_Index loop
         declare
            Scope : constant Value_Access := Ctx.Scopes (I);
         begin
            if Scope.Kind = Map then
               declare
                  C : constant Value_Maps.Cursor := Scope.Fields.Find (Head);
               begin
                  if C /= Value_Maps.No_Element then
                     Found := Value_Maps.Element (C);
                     exit;
                  end if;
               end;
            end if;
         end;
      end loop;
      if Found = null or else Tail = "" then
         return Found;
      end if;
      return Resolve_Tail (Found, Tail);
   end Resolve;

   function String_Of (V : Value_Access) return String is
     (if V = null or else V.Kind /= Scalar then "" else To_String (V.Text));

   function Escape (S : String) return String is
      Result : Unbounded_String;
   begin
      for C of S loop
         case C is
            when '&'    => Append (Result, "&amp;");
            when '<'    => Append (Result, "&lt;");
            when '>'    => Append (Result, "&gt;");
            when '"'    => Append (Result, "&quot;");
            when '''    => Append (Result, "&#39;");
            when others => Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end Escape;

   --  A tag as the grammar gave it, whole (`{{ & name }}`): its sigil (a space for none, { for {{{ }}}) and
   --  the name in it.
   procedure Split_Tag (Tag : Unbounded_String; Sigil : out Character; Name : out Unbounded_String) is
      S : constant String := To_String (Tag);
      F : Natural := S'First + 2;
      L : Natural := S'Last - 2;
   begin
      if S'Length > 4 and then S (F) = '{' then
         Sigil := '{';
         F := F + 1;
         L := L - 1;
      else
         while F <= L and then (Is_Blank (S (F)) or else Is_Break (S (F))) loop
            F := F + 1;
         end loop;
         if F <= L and then S (F) in '#' | '^' | '/' | '!' | '&' | '>' | '=' then
            Sigil := S (F);
            F := F + 1;
         else
            Sigil := ' ';
         end if;
      end if;
      while F <= L and then (Is_Blank (S (F)) or else Is_Break (S (F))) loop
         F := F + 1;
      end loop;
      while L >= F and then (Is_Blank (S (L)) or else Is_Break (S (L))) loop
         L := L - 1;
      end loop;
      Name := To_Unbounded_String (S (F .. L));
   end Split_Tag;

   function Name_Of (Tag : Unbounded_String) return String is
      Sigil : Character;
      Name  : Unbounded_String;
   begin
      Split_Tag (Tag, Sigil, Name);
      return To_String (Name);
   end Name_Of;

   --  A block is closed by the tag that names what opened it.
   procedure Check_Blocks (Parts : Template_Type) is
   begin
      for P of Parts loop
         if P.Block /= null then
            if Name_Of (P.Block.Open) /= Name_Of (P.Block.Close) then
               raise Template_Error with
                 "`" & To_String (P.Block.Open) & "` is closed by `" & To_String (P.Block.Close) & "`";
            end if;
            Check_Blocks (P.Block.Template);
         end if;
      end loop;
   end Check_Blocks;

   function Tree_Of (Name : String; Source : String) return Template_Access is
   begin
      declare
         T : constant Template_Access := new Template_Type'
           (HBNF_Template_Syntax.Parser.Parse_Text (Strip_Standalone (Source)));
      begin
         Check_Blocks (T.all);
         return T;
      end;
   exception
      when E : HBNF_Template_Syntax.Parser.Parse_Error | Template_Error =>
         raise Template_Error with
           "template `" & Name & "`: " & Ada.Exceptions.Exception_Message (E);
   end Tree_Of;

   --  =====================================================================
   --  Rendering.
   --  =====================================================================

   procedure Render_Parts
     (Parts : Template_Type; Ctx : in out Context; Result : in out Unbounded_String)
   is
   begin
      for P of Parts loop
         if P.Block /= null then
            declare
               Sigil : Character;
               Name  : Unbounded_String;
            begin
               Split_Tag (P.Block.Open, Sigil, Name);
               declare
                  V : constant Value_Access := Resolve (Ctx, To_String (Name));
               begin
                  if Sigil = '^' then
                     if not Is_Truthy (V) then
                        Render_Parts (P.Block.Template, Ctx, Result);
                     end if;
                  elsif V = null then
                     null;
                  elsif V.Kind = List then
                     for E of V.Items loop
                        Ctx.Scopes.Append (E);
                        Render_Parts (P.Block.Template, Ctx, Result);
                        Ctx.Scopes.Delete_Last;
                     end loop;
                  elsif Is_Truthy (V) then
                     Ctx.Scopes.Append (V);
                     Render_Parts (P.Block.Template, Ctx, Result);
                     Ctx.Scopes.Delete_Last;
                  end if;
               end;
            end;
         elsif Length (P.Tag) > 0 then
            declare
               Sigil : Character;
               Name  : Unbounded_String;
            begin
               Split_Tag (P.Tag, Sigil, Name);
               case Sigil is
                  when '&' | '{' =>
                     Append (Result, String_Of (Resolve (Ctx, To_String (Name))));
                  when ' ' =>
                     Append (Result, Escape (String_Of (Resolve (Ctx, To_String (Name)))));
                  when '!' =>
                     null;                 --  a comment renders as nothing
                  when others =>
                     raise Template_Error with
                       "a partial or a change of delimiters (`" & To_String (P.Tag)
                       & "`): this template reader does neither";
               end case;
            end;
         elsif Length (P.Text) > 0 then
            Append (Result, P.Text);
         elsif P.Lone /= null then
            Append (Result, '{');
         end if;
      end loop;
   end Render_Parts;

   function Render_Tree (Tree : Template_Type; View : Context) return String is
      Ctx    : Context := View;
      Result : Unbounded_String;
   begin
      Render_Parts (Tree, Ctx, Result);
      return To_String (Result);
   end Render_Tree;

   procedure Free_Tree is new Ada.Unchecked_Deallocation (Template_Type, Template_Access);

   function Render (Source : String; View : Context) return String is
      T : Template_Access := Tree_Of ("(text)", Source);
   begin
      return Result : constant String := Render_Tree (T.all, View) do
         HBNF_Template_Syntax.Parser.Free_Template (T.all);
         Free_Tree (T);
      end return;
   end Render;

   function Render_File (Name : String; View : Context) return String is
      T : Tree_Maps.Cursor := Trees.Find (Name);
   begin
      if T = Tree_Maps.No_Element then
         declare
            S : constant Text_Maps.Cursor := Store.Find (Name);
         begin
            if S = Text_Maps.No_Element then
               raise Template_Error with "no template `" & Name & "` loaded";
            end if;
            Trees.Insert (Name, Tree_Of (Name, To_String (Text_Maps.Element (S))));
         end;
         T := Trees.Find (Name);
      end if;
      return Render_Tree (Tree_Maps.Element (T).all, View);
   end Render_File;

end HBNF_Template;
