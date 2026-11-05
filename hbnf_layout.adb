pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with HBNF_Grammar;
with HBNF_Template;
with Interfaces;

package body HBNF_Layout is

   use Ada.Strings.Unbounded;
   use HBNF_Wire;
   use type Interfaces.Unsigned_64;
   package T renames HBNF_Template;

   Max_Charts : constant := 20_000;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   function US (S : String) return Unbounded_String renames To_Unbounded_String;

   function Ident (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C = '-' then
            C := '_';
         end if;
      end loop;
      return R;
   end Ident;

   function Spell (S : Unbounded_String) return String is
      R : String := To_String (S);
   begin
      for C of R loop
         if C = '_' then
            C := '-';
         end if;
      end loop;
      return R;
   end Spell;
   --  A name in the model is written as the author wrote it: the lowering turns a hyphen into an underscore for
   --  the code generators, and a chart wants the hyphen back.

   ---------------------------------------------------------------------------
   --  Charts
   ---------------------------------------------------------------------------

   type Field_Rec is record
      Name, Label, Role, Note, Expr : Unbounded_String;
      Kind   : Item_Kind := S_Bits;
      Bits   : Natural := 0;
      Value  : Interfaces.Unsigned_64 := 0;
      Signed : Boolean := False;
   end record;
   package Field_Vectors is new Ada.Containers.Vectors (Positive, Field_Rec);
   package Text_Vectors is new Ada.Containers.Vectors (Positive, Unbounded_String);

   type Chart_Rec is record
      Rule, Last_Ref, Title, Note : Unbounded_String;
      Name   : Unbounded_String;
      Guards : Text_Vectors.Vector;
      Fields : Field_Vectors.Vector;
   end record;
   package Chart_Vectors is new Ada.Containers.Vectors (Positive, Chart_Rec);

   procedure Expand_Rule
     (G : Grammar; R : Rule; Base : Chart_Rec; Result : in out Chart_Vectors.Vector;
      Depth : Natural);

   procedure Expand_Seq
     (G : Grammar; S : Sequence; Base : Chart_Rec; Result : in out Chart_Vectors.Vector;
      Depth : Natural)
   is
      Partials : Chart_Vectors.Vector;
      First    : Chart_Rec := Base;
   begin
      if Depth > 32 then
         raise Layout_Error with "rules nest more than 32 deep (a record that holds itself?)";
      end if;
      if S.Title /= Null_Unbounded_String then
         First.Title := S.Title;
         First.Note := S.Title_Note;
      end if;
      if S.Guard_Text /= Null_Unbounded_String then
         First.Guards.Append (S.Guard_Text);
      end if;
      Partials.Append (First);
      for It of S.Items loop
         declare
            Next : Chart_Vectors.Vector;
         begin
            case It.Kind is
               when S_Assert =>
                  Next := Partials;       --  a check says nothing about the layout
               when S_Bits | S_Const | S_Octets | S_Rest | S_Bit_Expr | S_Array =>
                  for P of Partials loop
                     declare
                        C : Chart_Rec := P;
                     begin
                        C.Fields.Append
                          (Field_Rec'(Name   => US (Spell (It.Name)),
                                      Label  => It.Label, Role => It.Role, Note => It.Note,
                                      Expr   => It.Expr_Text,
                                      Kind   => It.Kind, Bits => It.Bits,
                                      Value  => It.Value, Signed => It.Signed));
                        Next.Append (C);
                     end;
                  end loop;
               when S_Choice =>
                  for P of Partials loop
                     for A of It.Alts loop
                        Expand_Seq (G, A.all, P, Next, Depth + 1);
                     end loop;
                  end loop;
               when S_Ref =>
                  declare
                     Idx2 : constant Natural := Find (G, To_String (It.Ref));
                  begin
                     if Idx2 = 0 or else Is_Value_Set (G.Rules (Idx2)) then
                        --  a text rule, an enum, a value set: a field the chart cannot size
                        for P of Partials loop
                           declare
                              C : Chart_Rec := P;
                           begin
                              C.Fields.Append
                                (Field_Rec'(Name  => US (Spell (It.Name)),
                                            Label => It.Label, Role => It.Role, Note => It.Note,
                                            Expr  => It.Ref, Kind => S_Ref,
                                            Bits  => (if Idx2 /= 0 then Value_Width (G.Rules (Idx2)) else 0),
                                            others => <>));
                              Next.Append (C);
                           end;
                        end loop;
                     else
                        for P of Partials loop
                           declare
                              B : Chart_Rec := P;
                           begin
                              B.Last_Ref := US (Spell (It.Ref));
                              Expand_Rule (G, G.Rules (Idx2), B, Next, Depth + 1);
                           end;
                        end loop;
                     end if;
                  end;
            end case;
            Partials := Next;
            if Natural (Partials.Length) > Max_Charts then
               raise Layout_Error with "more than" & Integer'Image (Max_Charts) & " charts: give --rule=NAME";
            end if;
         end;
      end loop;
      for P of Partials loop
         Result.Append (P);
      end loop;
   end Expand_Seq;

   procedure Expand_Rule
     (G : Grammar; R : Rule; Base : Chart_Rec; Result : in out Chart_Vectors.Vector;
      Depth : Natural) is
   begin
      for A of R.Alts loop
         Expand_Seq (G, A.all, Base, Result, Depth);
      end loop;
   end Expand_Rule;

   --  A rule is a root when no other bit rule names it.
   function Referenced (G : Grammar; Name : String) return Boolean is
      function In_Seq (S : Sequence) return Boolean;
      function In_Item (It : Item) return Boolean is
      begin
         if It.Kind in S_Ref | S_Array and then To_String (It.Ref) = Name then
            return True;
         end if;
         if It.Kind = S_Choice then
            return (for some A of It.Alts => In_Seq (A.all));
         end if;
         return False;
      end In_Item;
      function In_Seq (S : Sequence) return Boolean is
        (for some It of S.Items => In_Item (It.all));
   begin
      return (for some R of G.Rules =>
                To_String (R.Name) /= Name
                and then (for some A of R.Alts => In_Seq (A.all)));
   end Referenced;

   ---------------------------------------------------------------------------
   --  Slugs and files
   ---------------------------------------------------------------------------

   function Slug (S : String) return String is
      R : String := S;
   begin
      for C of R loop
         if C not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '-' | '_' then
            C := '_';
         end if;
      end loop;
      return R;
   end Slug;

   function Binary (V : Interfaces.Unsigned_64; W : Natural) return String is
      R : String (1 .. W);
      X : Interfaces.Unsigned_64 := V;
   begin
      for I in reverse 1 .. W loop
         R (I) := (if X mod 2 = 1 then '1' else '0');
         X := X / 2;
      end loop;
      return R;
   end Binary;

   ---------------------------------------------------------------------------
   --  The model
   ---------------------------------------------------------------------------

   procedure Put (M : T.Value_Access; K, V : String) is
   begin
      T.Insert (M, K, T.New_Scalar (V));
   end Put;

   function Flag (B : Boolean) return String is (if B then "1" else "");

   --  The label drawn in a piece N bits wide: the label cut to what fits at about five characters to a bit.
   function Fit (S : String; W : Natural) return String is
      Room : constant Natural := Natural'Max (1, W * 5);
   begin
      return (if S'Length <= Room then S else S (S'First .. S'First + Room - 1));
   end Fit;

   --  The running totals of the table target: runs and places over all the charts so far, so that a leaf table can
   --  say where its places start in the place pool (`run0`, `place0`), as the C tables of a codec do.
   Glob_Runs   : Natural := 0;
   Glob_Places : Natural := 0;

   type Run_Rec is record
      Parcel, Hi, Len : Natural;
   end record;
   package Run_Vectors is new Ada.Containers.Vectors (Positive, Run_Rec);
   type Place_Rec is record
      Name, Label, Role : Unbounded_String;
      Bits   : Natural := 0;
      Signed : Boolean := False;
      Runs   : Run_Vectors.Vector;
   end record;
   package Place_Vectors is new Ada.Containers.Vectors (Positive, Place_Rec);

   function Chart_Model
     (C : Chart_Rec; Index : Positive; O : Options; File : String; Uid : in out Natural) return T.Value_Access
   is
      M      : constant T.Value_Access := T.New_Map;
      Rows   : constant T.Value_Access := T.New_List;
      Guards : constant T.Value_Access := T.New_List;
      Roles  : constant T.Value_Access := T.New_List;
      Seen   : Text_Vectors.Vector;
      Unit   : constant Natural := O.Unit;
      Places : constant T.Value_Access := T.New_List;
      Plist  : Place_Vectors.Vector;
      Cur    : Run_Vectors.Vector;                 --  the runs of the field being laid out
      Place0 : constant Natural := Glob_Places;
      Prefix_Bits : Natural := 0;
      Prefix_Value : Interfaces.Unsigned_64 := 0;
      Pos    : Natural := 0;                 --  absolute bit, from the left
      Fixed  : Boolean := True;
      Row    : T.Value_Access := null;
      Pieces : T.Value_Access := null;
      Row_N  : Integer := -1;
      Nrows  : Natural := 0;
      Total  : Natural := 0;

      procedure Open_Row (Label : String; Var : Boolean) is
      begin
         Row := T.New_Map;
         Pieces := T.New_list;
         Row_N := Row_N + 1;
         Put (Row, "n", Img (Row_N));
         Put (Row, "label", Label);
         Put (Row, "var", Flag (Var));
         T.Insert (Row, "pieces", Pieces);
         T.Append (Rows, Row);
      end Open_Row;

      procedure Note_Role (R : String) is
      begin
         for S of Seen loop
            if To_String (S) = R then
               return;
            end if;
         end loop;
         Seen.Append (US (R));
         declare
            E : constant T.Value_Access := T.New_Map;
         begin
            Put (E, "role", R);
            Put (E, "ri", Img (Natural (Roles.Items.Length)));
            T.Append (Roles, E);
         end;
      end Note_Role;

      procedure Add_Piece
        (F : Field_Rec; W, Field_Hi, Field_Lo : Natural; Total_W : Natural; Col : Natural;
         Cont_Before, Cont_After : Boolean; Var : Boolean)
      is
         P       : constant T.Value_Access := T.New_Map;
         Digits_L : constant T.Value_Access := T.New_List;
         Name    : constant String := To_String (F.Name);
         Is_K    : constant Boolean := F.Kind = S_Const;
         Role    : constant String :=
           (if F.Role /= Null_Unbounded_String then To_String (F.Role)
            elsif Is_K then "const"
            elsif Var then "var"
            else "field");
         Label   : constant String :=
           (if F.Label /= Null_Unbounded_String then To_String (F.Label)
            elsif Is_K then ""
            else Name);
         Hi      : constant Integer := Unit - 1 - Col;
         Lo      : constant Integer := Hi - W + 1;
      begin
         Uid := Uid + 1;
         Put (P, "uid", Img (Uid));
         Put (P, "parcel", Img (Row_N));
         Cur.Append (Run_Rec'(Parcel => Row_N, Hi => Unit - 1 - Col, Len => W));
         Put (P, "name", Name);
         Put (P, "label", Label);
         Put (P, "short", Fit (Label, W));
         Put (P, "note", To_String (F.Note));
         Put (P, "role", Role);
         Put (P, "w", Img (W));
         Put (P, "pos", Img (Col));
         Put (P, "hi", Img (Hi));
         Put (P, "lo", Img (Lo));
         Put (P, "const", Flag (Is_K));
         Put (P, "var", Flag (Var));
         Put (P, "signed", Flag (F.Signed));
         Put (P, "expr", To_String (F.Expr));
         Put (P, "bits_total", Img (Total_W));
         Put (P, "split", Flag (Cont_Before or else Cont_After));
         Put (P, "cont_before", Flag (Cont_Before));
         Put (P, "cont_after", Flag (Cont_After));
         Put (P, "range", (if Cont_Before or else Cont_After then Img (Field_Hi) & ":" & Img (Field_Lo) else ""));
         Put (P, "field_hi", Img (Field_Hi));
         Put (P, "field_lo", Img (Field_Lo));
         if Is_K then
            declare
               Full : constant String := Binary (F.Value, F.Bits);
               Mine : constant String := Full (Full'First + (F.Bits - 1 - Field_Hi) .. Full'First + (F.Bits - 1 - Field_Lo));
            begin
               Put (P, "value", Mine);
               for I in Mine'Range loop
                  declare
                     D : constant T.Value_Access := T.New_Map;
                  begin
                     Put (D, "d", [Mine (I)]);
                     Put (D, "i", Img (I - Mine'First));
                     Put (D, "pos", Img (Col + I - Mine'First));
                     T.Append (Digits_L, D);
                  end;
               end loop;
            end;
         else
            Put (P, "value", "");
         end if;
         T.Insert (P, "digits", Digits_L);
         Note_Role (Role);
         T.Append (Pieces, P);
      end Add_Piece;

      Guard_Seen : Boolean := False;
      After_Var  : Boolean := False;
   begin
      Put (M, "index", Img (Index));
      Put (M, "name", To_String (C.Name));
      Put (M, "file", File);
      Put (M, "rule", To_String (C.Rule));
      Put (M, "title", (if C.Title /= Null_Unbounded_String then To_String (C.Title) else To_String (C.Name)));
      Put (M, "has_title", Flag (C.Title /= Null_Unbounded_String));
      Put (M, "note", To_String (C.Note));
      Put (M, "unit", Img (Unit));
      Put (M, "unit_name", To_String (O.Unit_Name));
      --  A guard is drawn as lines of at most 78 characters, broken at a blank.
      for Gd of C.Guards loop
         declare
            Txt  : constant String := To_String (Gd);
            From : Positive := Txt'First;
         begin
            while From <= Txt'Last loop
               declare
                  Last : Natural := Natural'Min (Txt'Last, From + 77);
                  E    : constant T.Value_Access := T.New_Map;
               begin
                  if Last < Txt'Last then
                     while Last > From and then Txt (Last) /= ' ' loop
                        Last := Last - 1;
                     end loop;
                     if Last = From then
                        Last := Natural'Min (Txt'Last, From + 77);
                     end if;
                  end if;
                  Put (E, "g", Txt (From .. Last));
                  Put (E, "gi", Img (Natural (Guards.Items.Length)));
                  T.Append (Guards, E);
                  Guard_Seen := True;
                  From := Last + 1;
               end;
            end loop;
         end;
      end loop;
      T.Insert (M, "guards", Guards);
      Put (M, "has_guards", Flag (Guard_Seen));
      Put (M, "nguards", Img (Natural (Guards.Items.Length)));
      --  The geometry a drawing wants, fixed here so that every target agrees: the left margin that holds the row
      --  labels, the width of a bit (36 for a 16-bit row, narrower for a wider one so the chart stays 576 wide),
      --  the height of the head (title and guards).
      Put (M, "left", "80");
      Put (M, "cell", Img (if Unit <= 16 then 36 else Natural'Max (10, 576 / Unit)));
      Put (M, "hdr", Img (34 + 14 * Natural (Guards.Items.Length)));
      --  Lay the fields out: a row is Unit bits; a field that crosses a row is split; a field of unknown size
      --  (octets, a count of bits, a list, a text rule) is a row of its own, and what follows it starts a row.
      Open_Row (To_String (O.Unit_Name) & " 0", False);
      for F of C.Fields loop
         declare
            W : constant Natural :=
              (case F.Kind is
                  when S_Bits | S_Const => F.Bits,
                  when S_Ref => F.Bits,
                  when others => 0);
            Sized : constant Boolean := F.Kind in S_Bits | S_Const or else (F.Kind = S_Ref and then F.Bits > 0);
         begin
            if F.Kind = S_Bit_Expr and then F.Expr = US ("0") then
               null;                   --  bits(0): no bits, nothing to draw
            elsif not Sized then
               Fixed := False;
               if Natural (Pieces.Items.Length) > 0 then
                  Open_Row ("then", True);
               else
                  Put (Row, "var", "1");
               end if;
               Add_Piece (F, Unit, 0, 0, 0, 0, False, False, True);
               After_Var := True;
               Open_Row ("then", False);
               Pos := 0;
            else
               Cur.Clear;
               if F.Kind = S_Const and then Total = 0 and then Prefix_Bits = 0 then
                  Prefix_Bits := F.Bits;
                  Prefix_Value := F.Value;
               end if;
               declare
                  Left : Natural := W;                 --  bits of the field still to place
                  Hi   : Natural := W - 1;
               begin
                  while Left > 0 loop
                     declare
                        Col  : constant Natural := Pos mod Unit;
                        Take : constant Natural := Natural'Min (Left, Unit - Col);
                     begin
                        if Col = 0 and then Pos > 0 and then Natural (Pieces.Items.Length) > 0 then
                           Open_Row ((if After_Var then "then" else To_String (O.Unit_Name) & " " & Img (Pos / Unit)),
                                     False);
                        end if;
                        Add_Piece (F, Take, Hi, Hi + 1 - Take, W, Col, Hi /= W - 1, Left > Take, False);
                        Pos := Pos + Take;
                        Total := Total + Take;
                        Left := Left - Take;
                        Hi := (if Hi >= Take then Hi - Take else 0);
                     end;
                  end loop;
               end;
               if F.Kind /= S_Const then
                  --  A field is a place; fields that carry one label are the pieces of one field (the label names
                  --  the logical field), their runs kept together, in the order of the bits.
                  declare
                     Merged : Boolean := False;
                  begin
                     if F.Label /= Null_Unbounded_String then
                        for Pl of Plist loop
                           if Pl.Label = F.Label then
                              Pl.Bits := Pl.Bits + W;
                              for R of Cur loop
                                 Pl.Runs.Append (R);
                              end loop;
                              Merged := True;
                              exit;
                           end if;
                        end loop;
                     end if;
                     if not Merged then
                        Plist.Append
                          (Place_Rec'(Name => F.Name, Label => F.Label, Role => F.Role, Bits => W,
                                      Signed => F.Signed, Runs => Cur));
                     end if;
                  end;
               end if;
            end if;
         end;
      end loop;
      --  A trailing empty row (after a variable one, or none) is dropped.
      Nrows := Natural (Rows.Items.Length);
      if Nrows > 0 and then Natural (Rows.Items.Last_Element.Fields.Element ("pieces").Items.Length) = 0 then
         Rows.Items.Delete_Last;
         Nrows := Nrows - 1;
      end if;
      T.Insert (M, "rows", Rows);
      for Pl of Plist loop
         declare
            E    : constant T.Value_Access := T.New_Map;
            Runs : constant T.Value_Access := T.New_List;
         begin
            Put (E, "name", To_String (Pl.Name));
            Put (E, "label", To_String (Pl.Label));
            Put (E, "role", To_String (Pl.Role));
            Put (E, "bits", Img (Pl.Bits));
            Put (E, "signed", Flag (Pl.Signed));
            Put (E, "nruns", Img (Natural (Pl.Runs.Length)));
            Put (E, "run0", Img (Glob_Runs));
            for R of Pl.Runs loop
               declare
                  X : constant T.Value_Access := T.New_Map;
               begin
                  Put (X, "parcel", Img (R.Parcel));
                  Put (X, "hi", Img (R.Hi));
                  Put (X, "len", Img (R.Len));
                  T.Append (Runs, X);
               end;
            end loop;
            T.Insert (E, "runs", Runs);
            Glob_Runs := Glob_Runs + Natural (Pl.Runs.Length);
            T.Append (Places, E);
         end;
      end loop;
      T.Insert (M, "places", Places);
      Put (M, "nplaces", Img (Natural (Plist.Length)));
      Put (M, "place0", Img (Place0));
      Glob_Places := Glob_Places + Natural (Plist.Length);
      Put (M, "prefix_bits", Img (Prefix_Bits));
      Put (M, "prefix_value", Ada.Strings.Fixed.Trim (Interfaces.Unsigned_64'Image (Prefix_Value), Ada.Strings.Left));
      Put (M, "nparcels", Img ((Total + Unit - 1) / Unit));
      T.Insert (M, "roles", Roles);
      Put (M, "nrows", Img (Nrows));
      Put (M, "nroles", Img (Natural (Roles.Items.Length)));
      Put (M, "bits", (if Fixed then Img (Total) else ""));
      Put (M, "fixed", Flag (Fixed));
      return M;
   end Chart_Model;

   ---------------------------------------------------------------------------
   --  Targets: a directory of transforms.  NAME.EXT.tmpl is rendered once to NAME.EXT with the whole model;
   --  chart.EXT.tmpl is rendered once for every chart to <chart>.EXT.
   ---------------------------------------------------------------------------

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

   procedure Write_File (Dir, Name, Text : String) is
      F : Ada.Text_IO.File_Type;
   begin
      if Dir = "" then
         return;
      end if;
      Ada.Directories.Create_Path (Dir);
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Dir & "/" & Name);
      Ada.Text_IO.Put (F, Text);
      Ada.Text_IO.Close (F);
   end Write_File;

   procedure Run (G : Grammar; O : Options) is
      Charts : Chart_Vectors.Vector;
      Uid    : Natural := 0;

      Roots : Text_Vectors.Vector;
   begin
      --  The roots: the first rule (hbnf's own convention for the grammar's root), or the rules --chart-root names
      --  (a comma list), or, for `all`, every bit rule that no other bit rule names.
      if O.Root = US ("all") then
         for R of G.Rules loop
            if not Is_Value_Set (R) and then not Referenced (G, To_String (R.Name))
              and then not Roots.Contains (R.Name)
            then
               Roots.Append (R.Name);
            end if;
         end loop;
      elsif O.Root /= Null_Unbounded_String then
         declare
            L : constant String := To_String (O.Root);
            B : Positive := L'First;
         begin
            for I in L'First .. L'Last + 1 loop
               if I = L'Last + 1 or else L (I) = ',' then
                  declare
                     N : constant String := Ident (L (B .. I - 1));
                  begin
                     if Find (G, N) = 0 then
                        raise Layout_Error with "no bit rule `" & L (B .. I - 1) & "`";
                     end if;
                     Roots.Append (US (N));
                  end;
                  B := I + 1;
               end if;
            end loop;
         end;
      elsif not G.Rules.Is_Empty then
         Roots.Append (G.Rules.First_Element.Name);
      end if;
      if Roots.Is_Empty then
         raise Layout_Error with "no bit rule to draw";
      end if;
      for N of Roots loop
         declare
            R    : constant Rule := G.Rules (Find (G, To_String (N)));
            Seed : Chart_Rec;
            Mine : Chart_Vectors.Vector;
         begin
            Seed.Rule := US (Spell (R.Name));
            Expand_Rule (G, R, Seed, Mine, 0);
            --  Names: the innermost rule named on the way, else the root rule; a name that more than one chart
            --  has is numbered.
            for C of Mine loop
               C.Name := (if C.Last_Ref /= Null_Unbounded_String then C.Last_Ref else C.Rule);
            end loop;
            declare
               Base : constant Chart_Vectors.Vector := Mine;   --  the names before they are numbered
            begin
               for I in Mine.First_Index .. Mine.Last_Index loop
                  declare
                     Dup : Natural := 0;
                     Nth : Natural := 0;
                  begin
                     for J in Base.First_Index .. Base.Last_Index loop
                        if Base (J).Name = Base (I).Name then
                           Dup := Dup + 1;
                           if J <= I then
                              Nth := Nth + 1;
                           end if;
                        end if;
                     end loop;
                     if Dup > 1 then
                        Mine (I).Name := Base (I).Name & US ("-" & Img (Nth));
                     end if;
                  end;
               end loop;
            end;
            for C of Mine loop
               Charts.Append (C);
            end loop;
         end;
      end loop;

      --  The model
      declare
         Dir     : constant String := To_String (O.Target_Dir);
         Slash   : constant Natural := Ada.Strings.Fixed.Index (Dir, "/", Ada.Strings.Backward);
         Target_Name : constant String := (if Slash = 0 then Dir else Dir (Slash + 1 .. Dir'Last));
         Top     : T.Context := T.View;
         List    : constant T.Value_Access := T.New_List;
         Models  : constant T.Value_Access := T.New_List;
         Names   : Text_Vectors.Vector;
         Outputs : Text_Vectors.Vector;
         Stdout  : Unbounded_String;
         Count   : Natural := 0;
         Search  : Ada.Directories.Search_Type;
         Ent     : Ada.Directories.Directory_Entry_Type;
      begin
         if not Ada.Directories.Exists (Dir) then
            raise Layout_Error with "no target directory `" & Dir & "`";
         end if;
         for I in Charts.First_Index .. Charts.Last_Index loop
            declare
               C : constant Chart_Rec := Charts (I);
               File : constant String := Slug (To_String (C.Name));
               M : constant T.Value_Access := Chart_Model (C, I, O, File, Uid);
            begin
               T.Append (Models, M);
            end;
         end loop;
         T.Put (Top, "charts", Models);
         T.Put (Top, "nchart", Img (Natural (Charts.Length)));
         T.Put (Top, "source", To_String (O.Source));
         T.Put (Top, "unit", Img (O.Unit));
         T.Put (Top, "unit_name", To_String (O.Unit_Name));
         --  Load the transforms.
         Ada.Directories.Start_Search
           (Search, Dir, "*.tmpl", [Ada.Directories.Ordinary_File => True, others => False]);
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Ent);
            declare
               Simple : constant String := Ada.Directories.Simple_Name (Ent);
            begin
               if not Names.Contains (US (Simple)) then
                  T.Define ("target:" & Simple, Read_File (Ada.Directories.Full_Name (Ent)) & ASCII.LF);
                  Names.Append (US (Simple));
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         if Names.Is_Empty then
            raise Layout_Error with "target `" & Dir & "` holds no *.tmpl";
         end if;
         --  Sort the file names, so the output is the same on every machine.
         declare
            package Sorting is new Text_Vectors.Generic_Sorting;
         begin
            Sorting.Sort (Names);
         end;

         for N of Names loop
            declare
               Simple : constant String := To_String (N);
               Base   : constant String := Simple (Simple'First .. Simple'Last - 5);   --  without .tmpl
               Dot    : constant Natural := Ada.Strings.Fixed.Index (Base, ".", Ada.Strings.Backward);
               Stem   : constant String := (if Dot = 0 then Base else Base (Base'First .. Dot - 1));
               Ext    : constant String := (if Dot = 0 then "" else Base (Dot .. Base'Last));
            begin
               if Stem = "chart" then
                  for I in Charts.First_Index .. Charts.Last_Index loop
                     declare
                        Ctx  : T.Context := Top;
                        Name : constant String := Slug (To_String (Charts (I).Name)) & Ext;
                     begin
                        Ctx.Scopes.Append (Models.Items (I));
                        declare
                           --  A rule's own transform for this target (`%svg{ ... }` at the end of the rule)
                           --  stands in for the target's chart template.
                           Own  : constant String :=
                             HBNF_Grammar.Rule_Transform
                               (To_String (if Charts (I).Last_Ref /= Null_Unbounded_String
                                           then Charts (I).Last_Ref else Charts (I).Rule),
                                Target_Name);
                           Text : constant String :=
                             (if Own /= "" then T.Render (Own, Ctx)
                              else T.Render_File ("target:" & Simple, Ctx));
                        begin
                           Write_File (To_String (O.Out_Dir), Name, Text);
                           Outputs.Append (US (Name));
                           Append (Stdout, "%%% " & Name & ASCII.LF & Text);
                        end;
                     end;
                  end loop;
               else
                  declare
                     Name : constant String := Base;
                     Text : constant String := T.Render_File ("target:" & Simple, Top);
                  begin
                     Write_File (To_String (O.Out_Dir), Name, Text);
                     Outputs.Append (US (Name));
                     Append (Stdout, "%%% " & Name & ASCII.LF & Text);
                  end;
               end if;
               Count := Count + 1;
            end;
         end loop;
         if O.Out_Dir = Null_Unbounded_String then
            Ada.Text_IO.Put (To_String (Stdout));
         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "hbnf: wrote" & Integer'Image (Natural (Outputs.Length)) & " files to " & To_String (O.Out_Dir));
         end if;
      end;
   exception
      when E : T.Template_Error =>
         raise Layout_Error with "target `" & To_String (O.Target_Dir) & "`: " & Ada.Exceptions.Exception_Message (E);
   end Run;

end HBNF_Layout;
