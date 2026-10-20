pragma Ada_2022;

with Ada.Characters.Handling;
with HBNF_Ada;
with Ada.Containers.Vectors;

package body HBNF_Wire.Ada_Lang is

   use Interfaces;

   function Img (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if S (S'First) = ' ' then S (S'First + 1 .. S'Last) else S);
   end Img;

   function Hex (V : Unsigned_64) return String is
      Digits_Of : constant String := "0123456789ABCDEF";
      R : String (1 .. 16);
      X : Unsigned_64 := V;
      K : Natural := 17;
   begin
      loop
         K := K - 1;
         R (K) := Digits_Of (Integer (X and 15) + 1);
         X := Shift_Right (X, 4);
         exit when X = 0;
      end loop;
      return "16#" & R (K .. 16) & "#";
   end Hex;

   Ada_Words : constant array (Positive range <>) of access constant String :=
     [new String'("abort"), new String'("abs"), new String'("abstract"),
      new String'("accept"), new String'("access"), new String'("aliased"),
      new String'("all"), new String'("and"), new String'("array"),
      new String'("at"), new String'("begin"), new String'("body"),
      new String'("case"), new String'("constant"), new String'("declare"),
      new String'("delay"), new String'("delta"), new String'("digits"),
      new String'("do"), new String'("else"), new String'("elsif"),
      new String'("end"), new String'("entry"), new String'("exception"),
      new String'("exit"), new String'("for"), new String'("function"),
      new String'("generic"), new String'("goto"), new String'("if"),
      new String'("in"), new String'("interface"), new String'("is"),
      new String'("limited"), new String'("loop"), new String'("mod"),
      new String'("new"), new String'("not"), new String'("null"),
      new String'("of"), new String'("or"), new String'("others"),
      new String'("out"), new String'("overriding"), new String'("package"),
      new String'("parallel"), new String'("pragma"), new String'("private"),
      new String'("procedure"), new String'("protected"), new String'("raise"),
      new String'("range"), new String'("record"), new String'("rem"),
      new String'("renames"), new String'("requires"), new String'("return"),
      new String'("reverse"), new String'("select"), new String'("separate"),
      new String'("some"), new String'("subtype"), new String'("synchronized"),
      new String'("tagged"), new String'("task"), new String'("terminate"),
      new String'("then"), new String'("type"), new String'("until"),
      new String'("use"), new String'("when"), new String'("while"),
      new String'("with"), new String'("xor"),
      --  names the generated code uses unqualified
      new String'("alt"), new String'("octets"), new String'("byte_array"),
      new String'("parse_error"), new String'("writer"), new String'("parser"),
      new String'("natural"), new String'("positive"), new String'("integer"),
      new String'("boolean"), new String'("true"), new String'("false"),
      new String'("string"), new String'("character"),
      new String'("unsigned_8"), new String'("unsigned_16"),
      new String'("unsigned_32"), new String'("unsigned_64"),
      new String'("integer_8"), new String'("integer_16"),
      new String'("integer_32"), new String'("integer_64"),
      new String'("shift_left"), new String'("shift_right"),
      new String'("interfaces"), new String'("ada")];

   function Lower (S : String) return String renames
     Ada.Characters.Handling.To_Lower;

   function Is_Reserved (S : String) return Boolean is
   begin
      if S'Length >= 3 and then Lower (S (S'First .. S'First + 2)) = "bnf" then
         return True;
      end if;
      for K of Ada_Words loop
         if K.all = Lower (S) then
            return True;
         end if;
      end loop;
      return False;
   end Is_Reserved;

   --  Rule_name or rule-name -> Rule_Name; an identifier Ada accepts.
   function Ada_Case (S : String) return String is
      R  : Unbounded_String;
      Up : Boolean := True;
   begin
      for C of S loop
         if C in '_' | '-' then
            if Length (R) > 0 and then Element (R, Length (R)) /= '_' then
               Append (R, '_');
            end if;
            Up := True;
         elsif Up then
            Append (R, Ada.Characters.Handling.To_Upper (C));
            Up := False;
         else
            Append (R, C);
         end if;
      end loop;
      if Length (R) = 0 then
         return "X";
      end if;
      if Element (R, Length (R)) = '_' then
         Append (R, 'X');
      end if;
      return To_String (R);
   end Ada_Case;

   --  A string for inside an Ada string literal.
   function Escape (S : String) return String is
      R : Unbounded_String;
   begin
      for C of S loop
         if C = '"' then
            Append (R, '"');
         end if;
         Append (R, C);
      end loop;
      return To_String (R);
   end Escape;

   --  An Ada expression for the string S: characters outside printable ASCII
   --  are written by position, so no source encoding matters.
   function Ada_Str (S : String) return String is
      R   : Unbounded_String;
      Open : Boolean := False;
   begin
      if S'Length = 0 then
         return """""";
      end if;
      for C of S loop
         if C in ' ' .. '~' then
            if not Open then
               if Length (R) > 0 then
                  Append (R, " & ");
               end if;
               Append (R, '"');
               Open := True;
            end if;
            if C = '"' then
               Append (R, '"');
            end if;
            Append (R, C);
         else
            if Open then
               Append (R, '"');
               Open := False;
            end if;
            if Length (R) > 0 then
               Append (R, " & ");
            end if;
            Append (R, "Character'Val (" & Img (Character'Pos (C)) & ")");
         end if;
      end loop;
      if Open then
         Append (R, '"');
      end if;
      return "(" & To_String (R) & ")";
   end Ada_Str;

   Hosted_Mode  : Boolean := False;      --  Emit_Hosted is running
   Last_Types   : Unbounded_String;      --  the types of the last hosted Emit
   Last_Spec    : Unbounded_String;      --  what the Parser spec gets
   Last_Withs   : Unbounded_String;

   --  The reader's type is Parser; the text parser's is too, in a hosted file.
   function Rename (S : String) return String is
      R : Unbounded_String;
      I : Natural := S'First;

      function Word_Char (C : Character) return Boolean is
        (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');
   begin
      while I <= S'Last loop
         if I + 14 <= S'Last and then S (I .. I + 14) = "Bnf_Text_Parser" then
            Append (R, "Parser");   --  the text parser's
            I := I + 15;
         elsif I + 5 <= S'Last and then S (I .. I + 5) = "Parser"
           and then (I = S'First or else not Word_Char (S (I - 1)))
           and then (I + 6 > S'Last or else not Word_Char (S (I + 6)))
         then
            Append (R, "Wire_Parser");
            I := I + 6;
         else
            Append (R, S (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (R);
   end Rename;

   function Emit (G : Grammar; Package_Name : String) return String is
      Spec : Unbounded_String;     --  the package specification
      Bod  : Unbounded_String;     --  the body
      Cur  : access Unbounded_String := Bod'Unrestricted_Access;
      Id   : Natural := 0;

      procedure L (Ind : Natural; S : String) is
      begin
         Append (Cur.all, [1 .. 3 * Ind => ' ']);
         Append (Cur.all, S);
         Append (Cur.all, ASCII.LF);
      end L;

      procedure SL (Ind : Natural; S : String) is
      begin
         Append (Spec, [1 .. 3 * Ind => ' ']);
         Append (Spec, S);
         Append (Spec, ASCII.LF);
      end SL;

      function Next_Id return Natural is
      begin
         Id := Id + 1;
         return Id;
      end Next_Id;

      Pfx : constant String :=
        (declare
            P : constant String := To_String (G.Prefix);
         begin
            (if P'Length = 0 then ""
             elsif P (P'Last) = '_' then Ada_Case (P (P'First .. P'Last - 1)) & "_"
             else Ada_Case (P) & "_"));

      function Type_Of (R : String) return String is
        (if Hosted_Mode and then Find (G, R) = 0 then HBNF_Ada.Type_Name (R)
         else Pfx & Ada_Case (R) & "_T");
      function Parse_Fn_Of (R : String) return String is
        ((if Hosted_Mode then "Read_" else "Parse_") & Ada_Case (R));
      function Emit_Fn_Of (R : String) return String is
        ("Emit_" & Ada_Case (R));
      function In_Of (R : String) return String is
        ("In_Set_" & Ada_Case (R));
      function Vec_Of (R : String) return String is
        (Ada_Case (R) & "_Vectors");

      function Int_Type (Bits : Natural; Signed : Boolean) return String is
        ((if Signed then "Integer_" else "Unsigned_") & Img (Storage_Bits (Bits)));

      ------------------------------------------------------------------------
      --  Names.  A field is a local of the reader or the writer, and Ada lets
      --  an inner declaration hide an outer one, which would send an
      --  expression to the wrong field; so a field that has the name of one in
      --  reach is given another.  Names are not case sensitive.
      ------------------------------------------------------------------------

      Scope_Names  : Name_Vectors.Vector;
      Scope_Idents : Name_Vectors.Vector;

      function Mark return Natural is (Natural (Scope_Names.Length));

      procedure Pop (To : Natural) is
      begin
         while Natural (Scope_Names.Length) > To loop
            Scope_Names.Delete_Last;
            Scope_Idents.Delete_Last;
         end loop;
      end Pop;

      function In_Use (Ident : String) return Boolean is
      begin
         for X of Scope_Idents loop
            if Lower (To_String (X)) = Lower (Ident) then
               return True;
            end if;
         end loop;
         return False;
      end In_Use;

      --  The name of a field as a record component.
      function Comp (Field : String) return String is
         C : constant String := Ada_Case (Field);
      begin
         return (if Is_Reserved (C) then C & "_F" else C);
      end Comp;

      function Def_Field (Field : String) return String is
         Ident : Unbounded_String := To_Unbounded_String (Comp (Field));
      begin
         if In_Use (To_String (Ident)) then
            Ident := To_Unbounded_String (Comp (Field) & "_" & Img (Next_Id));
         end if;
         Scope_Names.Append (To_Unbounded_String (Field));
         Scope_Idents.Append (Ident);
         return To_String (Ident);
      end Def_Field;

      function Lookup (Field : String) return String is
      begin
         for K in reverse 1 .. Natural (Scope_Names.Length) loop
            if To_String (Scope_Names (K)) = Field then
               return To_String (Scope_Idents (K));
            end if;
         end loop;
         return Comp (Field);
      end Lookup;

      ------------------------------------------------------------------------
      --  Types
      ------------------------------------------------------------------------

      function Named (It : Item) return Boolean is
        (It.Kind not in S_Const | S_Assert and then not It.Bitsof);

      function Type_Name (It : Item; Owner : String) return String is
      begin
         case It.Kind is
            when S_Bits     => return Int_Type (It.Bits, It.Signed);
            when S_Octets | S_Rest => return "Octets";
            when S_Bit_Expr => return "Unsigned_64";
            when S_Ref      => return Type_Of (To_String (It.Ref));
            when S_Array    => return Vec_Of (To_String (It.Ref)) & ".Vector";
            when S_Choice   => return Owner & "_" & Ada_Case (To_String (It.Name)) & "_T";
            when S_Const | S_Assert => return "";
         end case;
      end Type_Name;

      --  The rules a rule reads (so a type comes after the types it holds).
      procedure Deps (Alts : Seq_Vectors.Vector; Into : in out Name_Vectors.Vector)
      is
      begin
         for A of Alts loop
            for It of A.Items loop
               case It.Kind is
                  when S_Ref | S_Array => Into.Append (It.Ref);
                  when S_Choice        => Deps (It.Alts, Into);
                  when others          => null;
               end case;
            end loop;
         end loop;
      end Deps;

      function Is_Array_Elem (Name : String; Alts : Seq_Vectors.Vector)
        return Boolean
      is
      begin
         for A of Alts loop
            for It of A.Items loop
               if It.Kind = S_Array and then To_String (It.Ref) = Name then
                  return True;
               elsif It.Kind = S_Choice and then Is_Array_Elem (Name, It.Alts) then
                  return True;
               end if;
            end loop;
         end loop;
         return False;
      end Is_Array_Elem;

      function Used_As_Array (Name : String) return Boolean is
      begin
         for R of G.Rules loop
            if Is_Array_Elem (Name, R.Alts) then
               return True;
            end if;
         end loop;
         return False;
      end Used_As_Array;

      --  A choice: the type named Name, a record with a variant part, and the
      --  types of choices inside it first.
      procedure Define_Choice (Name : String; Alts : Seq_Vectors.Vector);

      procedure Define_Nested (S : Sequence; Owner : String) is
      begin
         for It of S.Items loop
            if It.Kind = S_Choice then
               Define_Choice (Owner & "_" & Ada_Case (To_String (It.Name)),
                              It.Alts);
            end if;
         end loop;
      end Define_Nested;

      --  Components of the variants must all have different names.
      function Variant_Comp
        (Seen : in out Name_Vectors.Vector; Field : String; K : Natural)
         return String
      is
         C : constant String := Comp (Field);
      begin
         for X of Seen loop
            if Lower (To_String (X)) = Lower (C) then
               declare
                  N : constant String := C & "_A" & Img (K);
               begin
                  Seen.Append (To_Unbounded_String (N));
                  return N;
               end;
            end if;
         end loop;
         Seen.Append (To_Unbounded_String (C));
         return C;
      end Variant_Comp;

      procedure Define_Choice (Name : String; Alts : Seq_Vectors.Vector) is
         K    : Natural := 0;
         Seen : Name_Vectors.Vector;
         Body_Text : Unbounded_String;
      begin
         Seen.Append (To_Unbounded_String ("Alt"));
         for A of Alts loop
            K := K + 1;
            Define_Nested (A.all, Name & "_A" & Img (K));
         end loop;
         K := 0;
         for A of Alts loop
            K := K + 1;
            Append (Body_Text, "         when " & Img (K) & " =>" & ASCII.LF);
            declare
               Any : Boolean := False;
            begin
               for It of A.Items loop
                  if Named (It.all) then
                     Any := True;
                     Append (Body_Text, "            "
                       & Variant_Comp (Seen, To_String (It.Name), K) & " : "
                       & Type_Name (It.all, Name & "_A" & Img (K)) & ";"
                       & ASCII.LF);
                  end if;
               end loop;
               if not Any then
                  Append (Body_Text, "            null;" & ASCII.LF);
               end if;
            end;
         end loop;
         SL (1, "subtype " & Name & "_Alt is Positive range 1 .. "
             & Img (Natural (Alts.Length)) & ";");
         SL (1, "type " & Name & "_T (Alt : " & Name & "_Alt := 1) is record");
         SL (2, "case Alt is");
         Append (Spec, To_String (Body_Text));
         SL (2, "end case;");
         SL (1, "end record;");
         SL (1, "");
      end Define_Choice;

      --  The names of the components of a choice's alternatives, as Define_Choice
      --  gave them.
      function Alt_Comps (Alts : Seq_Vectors.Vector) return Name_Vectors.Vector is
         Seen : Name_Vectors.Vector;
         Out_V : Name_Vectors.Vector;
         K : Natural := 0;
      begin
         Seen.Append (To_Unbounded_String ("Alt"));
         for A of Alts loop
            K := K + 1;
            for It of A.Items loop
               if Named (It.all) then
                  Out_V.Append (To_Unbounded_String
                    (Variant_Comp (Seen, To_String (It.Name), K)));
               end if;
            end loop;
         end loop;
         return Out_V;
      end Alt_Comps;

      Done_Types : Name_Vectors.Vector;

      procedure Declare_Rule (Name : String) is
         J : constant Natural := Find (G, Name);
      begin
         for X of Done_Types loop
            if To_String (X) = Name then
               return;
            end if;
         end loop;
         Done_Types.Append (To_Unbounded_String (Name));
         if J = 0 or else Is_Value_Set (G.Rules (J)) then
            return;
         end if;
         declare
            R    : constant Rule := G.Rules (J);
            Ds   : Name_Vectors.Vector;
            Nm   : constant String := Type_Of (Name);
            Base : constant String := Pfx & Ada_Case (Name);
         begin
            Deps (R.Alts, Ds);
            for X of Ds loop
               Declare_Rule (To_String (X));
            end loop;
            if Natural (R.Alts.Length) = 1 then
               Define_Nested (R.Alts.First_Element.all, Base);
               SL (1, "type " & Nm & " is record");
               declare
                  Any : Boolean := False;
               begin
                  for It of R.Alts.First_Element.Items loop
                     if Named (It.all) then
                        Any := True;
                        SL (2, Comp (To_String (It.Name)) & " : "
                            & Type_Name (It.all, Base) & ";");
                     end if;
                  end loop;
                  if not Any then
                     SL (2, "null;");
                  end if;
               end;
               SL (1, "end record;");
               SL (1, "");
            else
               Define_Choice (Base, R.Alts);
            end if;
            if Hosted_Mode then
               --  what a text rule calls the rule's type
               SL (1, "subtype " & HBNF_Ada.Type_Name (Name) & " is "
                   & (if Natural (R.Alts.Length) = 1 then Nm else Base & "_T")
                   & ";");
               SL (1, "");
            end if;
            if Used_As_Array (Name) then
               SL (1, "package " & Vec_Of (Name)
                   & " is new Ada.Containers.Vectors (Natural, "
                   & (if Natural (R.Alts.Length) = 1 then Nm
                      else Base & "_T") & ");");
               SL (1, "");
            end if;
         end;
      end Declare_Rule;

      --  The type a rule is read into (a choice rule's is named for the rule).
      function Rule_Type (R : Rule) return String is
        (if Natural (R.Alts.Length) = 1 then Type_Of (To_String (R.Name))
         else Pfx & Ada_Case (To_String (R.Name)) & "_T");

      ------------------------------------------------------------------------
      --  Expressions: Integer_64, wrapping, as C's are
      ------------------------------------------------------------------------

      function Uses_Remaining (E : Expr_Access) return Boolean is
        (E /= null and then
           (case E.Kind is
               when E_Num    => False,
               when E_Var    => To_String (E.Name) = "remaining",
               when E_Call   => False,
               when E_Unary  => Uses_Remaining (E.Operand),
               when E_Binary => Uses_Remaining (E.Left)
                                or else Uses_Remaining (E.Right)));

      function Expr_Text (E : Expr_Access) return String is
        (case E.Kind is
            when E_Num    => Img (Integer (E.Value)),
            when E_Var    => To_String (E.Name),
            when E_Call   => To_String (E.Fn) & " (" & To_String (E.Arg) & ")",
            when E_Unary  => To_String (E.Un_Op) & Expr_Text (E.Operand),
            when E_Binary => "(" & Expr_Text (E.Left) & " "
                             & To_String (E.Bin_Op) & " "
                             & Expr_Text (E.Right) & ")");

      Emit_Side : Boolean := False;   --  writing, not reading: `align` is the writer's
      Words     : Item_Access;

      function Expr_A (E : Expr_Access) return String is
      begin
         case E.Kind is
            when E_Num =>
               return "Integer_64'(" & Long_Long_Integer'Image (E.Value) & ")";
            when E_Var =>
               if To_String (E.Name) = "remaining" then
                  return "Integer_64 (Bnf_P.Nbits - Bnf_P.Bit)";
               elsif To_String (E.Name) = "align" then
                  if Hosted_Mode then
                     return (if Emit_Side then "Bnf_Align (Bnf_W.Bit, Bnf_W.Unit)"
                             else "Bnf_Align (Bnf_P.Bit, Bnf_P.Unit)");
                  end if;
                  return "Bnf_Align (" & (if Emit_Side then "Bnf_W.Bit" else "Bnf_P.Bit")
                    & ")";
               end if;
               return "Bnf_I (" & Lookup (To_String (E.Name)) & ")";
            when E_Call =>
               return "Integer_64 (" & Lookup (To_String (E.Arg)) & ".Length)";
            when E_Unary =>
               declare
                  O  : constant String := To_String (E.Un_Op);
                  A  : constant String := Expr_A (E.Operand);
               begin
                  if O = "-" then
                     return "Bnf_Neg (" & A & ")";
                  elsif O = "~" then
                     return "Bnf_Not (" & A & ")";
                  else
                     return "Bnf_B (" & A & " = 0)";
                  end if;
               end;
            when E_Binary =>
               declare
                  Op : constant String := To_String (E.Bin_Op);
                  A  : constant String := Expr_A (E.Left);
                  B  : constant String := Expr_A (E.Right);
               begin
                  if Op = "+" then
                     return "Bnf_Add (" & A & ", " & B & ")";
                  elsif Op = "-" then
                     return "Bnf_Sub (" & A & ", " & B & ")";
                  elsif Op = "*" then
                     return "Bnf_Mul (" & A & ", " & B & ")";
                  elsif Op = "/" then
                     return "Bnf_Div (" & A & ", " & B & ")";
                  elsif Op = "%" then
                     return "Bnf_Rem (" & A & ", " & B & ")";
                  elsif Op = "<<" then
                     return "Bnf_Shl (" & A & ", " & B & ")";
                  elsif Op = ">>" then
                     return "Bnf_Shr (" & A & ", " & B & ")";
                  elsif Op = "&" then
                     return "Bnf_And (" & A & ", " & B & ")";
                  elsif Op = "|" then
                     return "Bnf_Or (" & A & ", " & B & ")";
                  elsif Op = "^" then
                     return "Bnf_Xor (" & A & ", " & B & ")";
                  elsif Op = "==" then
                     return "Bnf_B (" & A & " = " & B & ")";
                  elsif Op = "!=" then
                     return "Bnf_B (" & A & " /= " & B & ")";
                  elsif Op in "<" | "<=" | ">" | ">=" then
                     return "Bnf_B (" & A & " " & Op & " " & B & ")";
                  elsif Op = "&&" then
                     return "Bnf_B (" & A & " /= 0 and then " & B & " /= 0)";
                  elsif Op = "||" then
                     return "Bnf_B (" & A & " /= 0 or else " & B & " /= 0)";
                  else
                     raise Wire_Error with
                       "the operator `" & Op & "` is not in the Ada backend";
                  end if;
               end;
         end case;
      end Expr_A;

      function True_A (E : Expr_Access) return String is
        (Expr_A (E) & " /= 0");

      function Needs_St (S : Sequence) return Boolean is
        (for some It of S.Items =>
           It.Kind = S_Bits and then It.At_Bit >= 0 and then not It.Static_Ok);

      --  `Dst => D, Src => S` for the fields of a sequence read, with Alt
      --  first when it is an alternative.
      function Aggregate (S : Sequence; Comps : Name_Vectors.Vector;
                          First : in out Natural; Alt : Natural) return String
      is
         R : Unbounded_String;
         Any : Boolean := False;
      begin
         if Alt > 0 then
            Append (R, "Alt => " & Img (Alt));
            Any := True;
         end if;
         for It of S.Items loop
            if Named (It.all) then
               if Any then
                  Append (R, ", ");
               end if;
               Any := True;
               declare
                  C : constant String :=
                    (if Alt > 0 then To_String (Comps (First)) else
                       Comp (To_String (It.Name)));
               begin
                  Append (R, C & " => " & Lookup (To_String (It.Name)));
               end;
               First := First + 1;
            end if;
         end loop;
         if not Any then
            return "null record";
         end if;
         return To_String (R);
      end Aggregate;

      ------------------------------------------------------------------------
      --  Parse code: a local for each field, then the record
      ------------------------------------------------------------------------

      procedure Gen_Choice
        (Alts : Seq_Vectors.Vector; Enum : String; Target : String;
         Where : String; Ind : Natural);

      function Table_Of (It : Item) return String is
        ("Bnf_Tab_" & Img (It.Line) & "_" & Img (It.Col));
      function Sep_Of (It : Item) return String is
        ("Bnf_Sep_" & Img (It.Line) & "_" & Img (It.Col));

      function Seq_Has_Bitsof (S : Sequence) return Boolean;
      function Seq_Has_Bitsof (S : Sequence) return Boolean is
        (for some It of S.Items =>
           It.Bitsof or else (It.Kind = S_Choice
                              and then (for some A of It.Alts =>
                                          Seq_Has_Bitsof (A.all))));
      function Rule_Has_Bitsof (R : Rule) return Boolean is
        (for some A of R.Alts => Seq_Has_Bitsof (A.all));

      --  A text rule read where the bits are, into Fid (an Unbounded_String for a
      --  token, the rule's type otherwise); Span, if given, is an
      --  Unbounded_String that gets the text it used.
      procedure Gen_Text_Ref
        (Ind : Natural; R, W, U, Fid, Span : String)
      is
      begin
                              if (for some X of G.External_Tokens =>
                                    To_String (X) = R)
                              then
                                 --  a character rule of the text: its scanner
                                 --  reads it here, from the octet the bits have
                                 --  reached
                                 L (Ind, "declare");
                                 L (Ind + 1, "Bnf_N" & U & " : Natural;");
                                 L (Ind, "begin");
                                 L (Ind + 1, "if Bnf_P.Bit mod 8 = 0 then");
                                 L (Ind + 2, "Bnf_N" & U & " := " & HBNF_Ada.Scan_Fn (R)
                                    & " (Bnf_P.Buf.all, Bnf_P.Bit / 8 + 1, Bnf_P.Buf'Last);");
                                 L (Ind + 2, "if Bnf_N" & U & " = 0 then");
                                 L (Ind + 3, "Fail (Bnf_P, Bnf_P.Bit, " & W & ", ""a " & R & """);");
                                 L (Ind + 2, "end if;");
                                 L (Ind + 2, Fid & " := To_Unbounded_String (Bnf_P.Buf (Bnf_P.Bit / 8 + 1 .. Bnf_P.Bit / 8 + Bnf_N" & U & "));");
                                 if Span /= "" and then Span /= Fid then
                                    L (Ind + 2, Span & " := " & Fid & ";");
                                 end if;
                                 L (Ind + 1, "else");
                                 L (Ind + 2, "declare");
                                 L (Ind + 3, "C : constant String := Bnf_Shifted (Bnf_P);");
                                 L (Ind + 2, "begin");
                                 L (Ind + 3, "Bnf_N" & U & " := " & HBNF_Ada.Scan_Fn (R) & " (C, 1, C'Last);");
                                 L (Ind + 3, "if Bnf_N" & U & " = 0 then");
                                 L (Ind + 4, "Fail (Bnf_P, Bnf_P.Bit, " & W & ", ""a " & R & """);");
                                 L (Ind + 3, "end if;");
                                 L (Ind + 3, Fid & " := To_Unbounded_String (C (1 .. Bnf_N" & U & "));");
                                 if Span /= "" and then Span /= Fid then
                                    L (Ind + 3, Span & " := " & Fid & ";");
                                 end if;
                                 L (Ind + 2, "end;");
                                 L (Ind + 1, "end if;");
                                 L (Ind + 1, "Bnf_P.Bit := Bnf_P.Bit + Bnf_N" & U & " * 8;");
                                 L (Ind, "end;");
                              else
                                 --  a text rule with structure: the text parser
                                 --  reads it, on a shifted copy if the octets
                                 --  start inside a byte
                                 L (Ind, "declare");
                                 L (Ind + 1, "Bnf_Start" & U & " : constant Natural := Bnf_P.Bit / 8 + 1;");
                                 L (Ind, "begin");
                                 L (Ind + 1, "if Bnf_P.Bit mod 8 = 0 then");
                                 L (Ind + 2, "declare");
                                 L (Ind + 3, "Tp : Bnf_Text_Parser := (Text => Bnf_P.Buf, Pos => Bnf_Start" & U & ", Last => Natural'Last, Bit => 0);");
                                 L (Ind + 2, "begin");
                                 L (Ind + 3, Fid & " := " & HBNF_Ada.Parse_Fn (R) & " (Tp);");
                                 L (Ind + 3, "Bnf_P.Bit := Bnf_P.Bit + (Tp.Pos - Bnf_Start" & U & ") * 8;");
                                 if Span /= "" then
                                    L (Ind + 3, Span & " := To_Unbounded_String (Bnf_P.Buf (Bnf_Start" & U & " .. Tp.Pos - 1));");
                                 end if;
                                 L (Ind + 2, "exception");
                                 L (Ind + 3, "when Parse_Error =>");
                                 L (Ind + 4, "Fail (Bnf_P, Bnf_P.Bit, " & W & ", ""a " & R & """);");
                                 L (Ind + 2, "end;");
                                 L (Ind + 1, "else");
                                 L (Ind + 2, "declare");
                                 L (Ind + 3, "C  : aliased constant String := Bnf_Shifted (Bnf_P);");
                                 L (Ind + 3, "Tp : Bnf_Text_Parser := (Text => C'Unchecked_Access, Pos => 1, Last => Natural'Last, Bit => 0);");
                                 L (Ind + 2, "begin");
                                 L (Ind + 3, Fid & " := " & HBNF_Ada.Parse_Fn (R) & " (Tp);");
                                 L (Ind + 3, "Bnf_P.Bit := Bnf_P.Bit + (Tp.Pos - 1) * 8;");
                                 if Span /= "" then
                                    L (Ind + 3, Span & " := To_Unbounded_String (C (1 .. Tp.Pos - 1));");
                                 end if;
                                 L (Ind + 2, "exception");
                                 L (Ind + 3, "when Parse_Error =>");
                                 L (Ind + 4, "Fail (Bnf_P, Bnf_P.Bit, " & W & ", ""a " & R & """);");
                                 L (Ind + 2, "end;");
                                 L (Ind + 1, "end if;");
                                 L (Ind, "end;");
                              end if;
      end Gen_Text_Ref;

      --  The locals a sequence reads into (Decls) and the statements (Stmts);
      --  Ind is the indentation of the statements.
      procedure Gen_Seq (S : Sequence; Where : String; Owner : String;
                         Ind : Natural; Decls : in out Unbounded_String;
                         Stmts : in out Unbounded_String)
      is
         Saved : constant access Unbounded_String := Cur;
         Sid   : constant String := "Bnf_St" & Img (Next_Id);

         procedure D (S : String) is
         begin
            Append (Decls, S & ASCII.LF);
         end D;
      begin
         Cur := Stmts'Unrestricted_Access;
         if Needs_St (S) then
            D ("      " & Sid & " : constant Natural := Bnf_P.Bit;");
         end if;
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
               U  : constant String := Img (Next_Id);
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "declare");
                     L (Ind + 1, "Bnf_S" & U & " : constant Natural := Bnf_P.Bit;");
                     L (Ind + 1, "Bnf_V" & U & " : constant Unsigned_64 := Rd (Bnf_P, "
                       & Img (It.Bits) & ", """ & Where & """);");
                     L (Ind, "begin");
                     L (Ind + 1, "if Bnf_V" & U & " /= " & Hex (It.Value) & " then");
                     L (Ind + 2, "Fail (Bnf_P, Bnf_S" & U & ", """ & Where
                       & """, ""expected the constant " & Hex (It.Value) & """);");
                     L (Ind + 1, "end if;");
                     L (Ind, "end;");
                  when S_Bits =>
                     declare
                        Fid : constant String := Def_Field (N);
                     begin
                        D ("      " & Fid & " : " & Int_Type (It.Bits, It.Signed)
                           & ";");
                        L (Ind, "declare");
                        L (Ind + 1, "Bnf_S" & U & " : constant Natural := Bnf_P.Bit;");
                        L (Ind + 1, "Bnf_V" & U & " : Unsigned_64 := 0;");
                        L (Ind, "begin");
                        if It.At_Bit >= 0 and then not It.Static_Ok then
                           L (Ind + 1, "if Bnf_P.Bit - " & Sid & " /= "
                             & Img (It.At_Bit) & " then");
                           L (Ind + 2, "Fail (Bnf_P, Bnf_P.Bit, " & W
                             & ", ""is not at bit " & Img (It.At_Bit)
                             & " of its record"");");
                           L (Ind + 1, "end if;");
                        end if;
                        L (Ind + 1, "Bnf_V" & U & " := Rd (Bnf_P, " & Img (It.Bits)
                          & ", " & W & ");");
                        if It.Little then
                           L (Ind + 1, "Bnf_V" & U & " := Bnf_Swap (Bnf_V" & U
                             & ", " & Img (It.Bits / 8) & ");");
                        end if;
                        if It.Signed and then It.Bits < 64 then
                           L (Ind + 1, "Bnf_V" & U & " := Shift_Right_Arithmetic "
                             & "(Shift_Left (Bnf_V" & U & ", "
                             & Img (64 - It.Bits) & "), " & Img (64 - It.Bits)
                             & ");");
                        end if;
                        if It.Ref /= Null_Unbounded_String then
                           L (Ind + 1, "if not " & In_Of (To_String (It.Ref))
                             & " (Bnf_V" & U & ") then");
                           L (Ind + 2, "Fail (Bnf_P, Bnf_S" & U & ", " & W
                             & ", ""is not one of the values the rule `"
                             & To_String (It.Ref) & "` lists"");");
                           L (Ind + 1, "end if;");
                        end if;
                        if It.Signed then
                           L (Ind + 1, Fid & " := " & Int_Type (It.Bits, True)
                             & " (To_I64 (Bnf_V" & U & "));");
                        else
                           L (Ind + 1, Fid & " := " & Int_Type (It.Bits, False)
                             & " (Bnf_V" & U & ");");
                        end if;
                        L (Ind, "end;");
                     end;
                  when S_Assert =>
                     L (Ind, "if not (" & True_A (It.Count) & ") then");
                     L (Ind + 1, "Fail (Bnf_P, Bnf_P.Bit, """ & Where & """, """
                       & (if It.Ref /= Null_Unbounded_String
                          then Escape (To_String (It.Ref))
                          else "a condition does not hold: "
                               & Escape (Expr_Text (It.Count)))
                       & """);");
                     L (Ind, "end if;");
                  when S_Octets =>
                     declare
                        Cnt : constant String := Expr_A (It.Count);
                        Fid : constant String := Def_Field (N);
                     begin
                        D ("      " & Fid & " : Octets;");
                        L (Ind, "declare");
                        L (Ind + 1, "Bnf_N" & U & " : constant Integer_64 := " & Cnt & ";");
                        L (Ind, "begin");
                        L (Ind + 1, "if Bnf_N" & U & " < 0 then");
                        L (Ind + 2, "Fail (Bnf_P, Bnf_P.Bit, " & W
                          & ", ""has a negative length"");");
                        L (Ind + 1, "end if;");
                        L (Ind + 1, Fid & " := Take (Bnf_P, Bnf_N" & U & ", " & W & ");");
                        L (Ind, "end;");
                     end;
                  when S_Rest =>
                     declare
                        Fid : constant String := Def_Field (N);
                     begin
                        D ("      " & Fid & " : Octets;");
                        L (Ind, Fid & " := Take_Rest (Bnf_P, " & W & ");");
                     end;
                  when S_Bit_Expr =>
                     declare
                        Cnt : constant String := Expr_A (It.Count);
                        Fid : constant String := Def_Field (N);
                     begin
                        D ("      " & Fid & " : Unsigned_64 := 0;");
                        L (Ind, "declare");
                        L (Ind + 1, "Bnf_N" & U & " : constant Integer_64 := " & Cnt & ";");
                        L (Ind, "begin");
                        L (Ind + 1, "if Bnf_N" & U & " < 0 or else Bnf_N" & U
                          & " > 64 then");
                        L (Ind + 2, "Fail (Bnf_P, Bnf_P.Bit, " & W
                          & ", ""has a width outside 0..64 bits"");");
                        L (Ind + 1, "end if;");
                        L (Ind + 1, Fid & " := Rd (Bnf_P, Natural (Bnf_N" & U
                          & "), " & W & ");");
                        L (Ind, "end;");
                     end;
                  when S_Ref =>
                     if It.Bitsof and then Hosted_Mode then
                        --  the text rule is read, its numbered words become the
                        --  bits the rest of the rule reads (the rule's wrapper
                        --  puts the input back)
                        declare
                           R : constant String := To_String (It.Ref);
                           Tokn : constant Boolean :=
                             (for some X of G.External_Tokens => To_String (X) = R);
                        begin
                           L (Ind, "declare");
                           L (Ind + 1, "Bnf_Start" & U & " : constant Natural := Bnf_P.Bit / 8;");
                           L (Ind + 1, "Bnf_T" & U & " : Unbounded_String;");
                           if not Tokn then
                              L (Ind + 1, "Bnf_V" & U & " : " & HBNF_Ada.Type_Name (R) & ";");
                           end if;
                           L (Ind, "begin");
                           L (Ind + 1, "if Bnf_P.Sv_Active then");
                           L (Ind + 2, "Fail (Bnf_P, Bnf_P.Bit, " & W & ", ""a bitsof inside a bitsof"");");
                           L (Ind + 1, "end if;");
                           Gen_Text_Ref (Ind + 1, R, W, U,
                                         (if Tokn then "Bnf_T" & U else "Bnf_V" & U),
                                         "Bnf_T" & U);
                           L (Ind + 1, "Bnf_Words_Begin (Bnf_P, To_String (Bnf_T" & U & "), "
                              & Img (It.Width) & ", " & Table_Of (It.all) & ", Bnf_Start" & U & ");");
                           L (Ind, "end;");
                        end;
                     elsif not It.Bitsof then   --  the words are already the bits
                        declare
                           Fid : constant String := Def_Field (N);
                           R   : constant String := To_String (It.Ref);
                        begin
                           D ("      " & Fid & " : " & Type_Of (R) & ";");
                           if Hosted_Mode and then Find (G, R) = 0 then
                              Gen_Text_Ref (Ind, R, W, U, Fid, "");
                           else
                              L (Ind, Fid & " := " & Parse_Fn_Of (R)
                                 & " (Bnf_P);");
                           end if;
                        end;
                     end if;
                  when S_Array =>
                     declare
                        R   : constant String := To_String (It.Ref);
                        Cnt : constant String :=
                          (if It.Count /= null then Expr_A (It.Count) else "");
                        Mn  : constant String :=
                          (if It.Count /= null then "Bnf_Cnt" & U
                           else "Integer_64'(" & Img (It.Min) & ")");
                        Mx  : constant String :=
                          (if It.Count /= null then "Bnf_Cnt" & U
                           else "Integer_64'(" & Img (It.Max) & ")");
                        Fid : constant String := Def_Field (N);
                     begin
                        D ("      " & Fid & " : " & Vec_Of (R) & ".Vector;");
                        L (Ind, "declare");
                        if It.Count /= null then
                           L (Ind + 1, "Bnf_Cnt" & U & " : constant Integer_64 := "
                             & Cnt & ";");
                        end if;
                        L (Ind, "begin");
                        if It.Count /= null then
                           L (Ind + 1, "if Bnf_Cnt" & U & " < 0 then");
                           L (Ind + 2, "Fail (Bnf_P, Bnf_P.Bit, " & W
                             & ", ""has a negative count"");");
                           L (Ind + 1, "end if;");
                        end if;
                        L (Ind + 1, "loop");
                        L (Ind + 2, "declare");
                        L (Ind + 3, "Bnf_S" & U & " : constant Natural := Bnf_P.Bit;");
                        L (Ind + 2, "begin");
                        L (Ind + 3, "exit when " & Mx & " >= 0 and then Integer_64 ("
                          & Fid & ".Length) >= " & Mx & ";");
                        L (Ind + 3, "exit when Integer_64 (" & Fid & ".Length) >= "
                          & Mn & " and then Bnf_P.Bit >= Bnf_P.Nbits;");
                        L (Ind + 3, "begin");
                        L (Ind + 4, "declare");
                        L (Ind + 5, "Bnf_T" & U & " : constant "
                          & Type_Of (R) & " := " & Parse_Fn_Of (R) & " (Bnf_P);");
                        L (Ind + 4, "begin");
                        L (Ind + 5, "exit when Bnf_P.Bit = Bnf_S" & U & ";");
                        L (Ind + 5, Fid & ".Append (Bnf_T" & U & ");");
                        L (Ind + 4, "end;");
                        L (Ind + 3, "exception");
                        L (Ind + 4, "when Bnf_Fail =>");
                        L (Ind + 5, "Bnf_P.Bit := Bnf_S" & U & ";");
                        L (Ind + 5, "if Integer_64 (" & Fid & ".Length) < " & Mn
                          & " then");
                        L (Ind + 6, "raise;");
                        L (Ind + 5, "end if;");
                        L (Ind + 5, "exit;");
                        L (Ind + 3, "end;");
                        L (Ind + 2, "end;");
                        L (Ind + 1, "end loop;");
                        L (Ind + 1, "if Integer_64 (" & Fid & ".Length) < " & Mn
                          & " then");
                        L (Ind + 2, "Fail (Bnf_P, Bnf_P.Bit, " & W
                          & ", ""has too few entries"");");
                        L (Ind + 1, "end if;");
                        L (Ind, "end;");
                     end;
                  when S_Choice =>
                     declare
                        E   : constant String :=
                          Owner & "_" & Ada_Case (N) & "_T";
                        Fid : constant String := Def_Field (N);
                     begin
                        D ("      " & Fid & " : " & E & ";");
                        Gen_Choice (It.Alts, Owner & "_" & Ada_Case (N), Fid,
                                    Where & "." & N, Ind);
                     end;
               end case;
            end;
         end loop;
         Cur := Saved;
      end Gen_Seq;

      --  Try the alternatives in turn, the bits put back between tries; Target
      --  is the variable that gets the first one that reads.
      procedure Gen_Choice
        (Alts : Seq_Vectors.Vector; Enum : String; Target : String;
         Where : String; Ind : Natural)
      is
         U : constant String := Img (Next_Id);
         K : Natural := 0;
      begin
         L (Ind, "declare");
         L (Ind + 1, "Bnf_C" & U & " : constant Natural := Bnf_P.Bit;");
         L (Ind + 1, "Bnf_Done" & U & " : Boolean := False;");
         L (Ind, "begin");
         for A of Alts loop
            K := K + 1;
            declare
               M      : constant Natural := Mark;
               Decls  : Unbounded_String;
               Stmts  : Unbounded_String;
               Comps  : constant Name_Vectors.Vector := Alt_Comps (Alts);
               First  : Natural := 1;
               Skip   : Natural := 0;
            begin
               --  The components before this alternative's own.
               for B in 1 .. K - 1 loop
                  for It of Alts (B).Items loop
                     if Named (It.all) then
                        Skip := Skip + 1;
                     end if;
                  end loop;
               end loop;
               First := Skip + 1;
               Gen_Seq (A.all, Where, Enum & "_A" & Img (K), Ind + 4, Decls,
                        Stmts);
               L (Ind + 1, "if not Bnf_Done" & U & " then");
               L (Ind + 2, "begin");
               L (Ind + 3, "declare");
               Append (Cur.all, To_String (Decls));
               L (Ind + 3, "begin");
               if A.Guard /= null then
                  L (Ind + 4, "if not (" & True_A (A.Guard) & ") then");
                  L (Ind + 5, "raise Bnf_Fail;");
                  L (Ind + 4, "end if;");
               end if;
               Append (Cur.all, To_String (Stmts));
               L (Ind + 4, Target & " := (" & Aggregate (A.all, Comps, First, K)
                  & ");");
               L (Ind + 4, "Bnf_Done" & U & " := True;");
               L (Ind + 3, "end;");
               L (Ind + 2, "exception");
               L (Ind + 3, "when Bnf_Fail =>");
               L (Ind + 4, "Bnf_P.Bit := Bnf_C" & U & ";");
               L (Ind + 2, "end;");
               L (Ind + 1, "end if;");
               Pop (M);
            end;
         end loop;
         L (Ind + 1, "if not Bnf_Done" & U & " then");
         L (Ind + 2, "Fail (Bnf_P, Bnf_P.Bit, """ & Where
           & """, ""none of the alternatives matches here"");");
         L (Ind + 1, "end if;");
         L (Ind, "end;");
      end Gen_Choice;

      ------------------------------------------------------------------------
      --  Emit code: a tree back to bytes
      ------------------------------------------------------------------------

      procedure Gen_Emit_Match
        (Alts : Seq_Vectors.Vector; Subject : String; Enum : String;
         Where : String; Ind : Natural);

      procedure Gen_Emit_Seq (S : Sequence; Where : String; Owner : String;
                              Ind : Natural)
      is
         Sid : constant String := "Bnf_St" & Img (Next_Id);
      begin
         if Needs_St (S) then
            L (Ind, "declare");
            L (Ind + 1, Sid & " : constant Natural := Bnf_W.Bit;");
            L (Ind, "begin");
         end if;
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
               Fid : constant String :=
                 (if Named (It.all) then Lookup (N) else "");
               U  : constant String := Img (Next_Id);
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "Wr (Bnf_W, " & Img (It.Bits) & ", " & Hex (It.Value)
                       & ");");
                  when S_Bits =>
                     L (Ind, "declare");
                     L (Ind + 1, "Bnf_X" & U & " : Unsigned_64;");
                     L (Ind, "begin");
                     if It.At_Bit >= 0 and then not It.Static_Ok then
                        L (Ind + 1, "if Bnf_W.Bit - " & Sid & " /= "
                          & Img (It.At_Bit) & " then");
                        L (Ind + 2, "Efail (Bnf_W, " & W & ", ""is not at bit "
                          & Img (It.At_Bit) & " of its record"");");
                        L (Ind + 1, "end if;");
                     end if;
                     if It.Signed then
                        if It.Bits < 64 then
                           L (Ind + 1, "if Integer_64 (" & Fid & ") < -(2 ** "
                             & Img (It.Bits - 1) & ") or else Integer_64 (" & Fid
                             & ") >= 2 ** " & Img (It.Bits - 1) & " then");
                           L (Ind + 2, "Efail (Bnf_W, " & W & ", ""does not fit "
                             & "in " & Img (It.Bits) & " bits (signed)"");");
                           L (Ind + 1, "end if;");
                           L (Ind + 1, "Bnf_X" & U & " := To_U64 (Integer_64 ("
                             & Fid & ")) and (2 ** " & Img (It.Bits)
                             & " - 1);");
                        else
                           L (Ind + 1, "Bnf_X" & U & " := To_U64 (Integer_64 ("
                             & Fid & "));");
                        end if;
                     else
                        L (Ind + 1, "Bnf_X" & U & " := Unsigned_64 (" & Fid & ");");
                        if It.Bits < 64 then
                           L (Ind + 1, "if Shift_Right (Bnf_X" & U & ", "
                             & Img (It.Bits) & ") /= 0 then");
                           L (Ind + 2, "Efail (Bnf_W, " & W & ", ""does not fit "
                             & "in " & Img (It.Bits) & " bits"");");
                           L (Ind + 1, "end if;");
                        end if;
                     end if;
                     if It.Ref /= Null_Unbounded_String then
                        L (Ind + 1, "if not " & In_Of (To_String (It.Ref))
                          & " (Bnf_X" & U & ") then");
                        L (Ind + 2, "Efail (Bnf_W, " & W & ", ""is not one of "
                          & "the values the rule `" & To_String (It.Ref)
                          & "` lists"");");
                        L (Ind + 1, "end if;");
                     end if;
                     if It.Little then
                        L (Ind + 1, "Bnf_X" & U & " := Bnf_Swap (Bnf_X" & U & ", "
                          & Img (It.Bits / 8) & ");");
                     end if;
                     L (Ind + 1, "Wr (Bnf_W, " & Img (It.Bits) & ", Bnf_X" & U
                       & ");");
                     L (Ind, "end;");
                  when S_Assert =>
                     if not Uses_Remaining (It.Count) then
                        L (Ind, "if not (" & True_A (It.Count) & ") then");
                        L (Ind + 1, "Efail (Bnf_W, """ & Where & """, """
                          & (if It.Ref /= Null_Unbounded_String
                             then Escape (To_String (It.Ref))
                             else "a condition does not hold: "
                                  & Escape (Expr_Text (It.Count)))
                          & """);");
                        L (Ind, "end if;");
                     end if;
                  when S_Octets =>
                     if not Uses_Remaining (It.Count) then
                        L (Ind, "if Integer_64 (" & Fid & ".Length) /= "
                          & Expr_A (It.Count) & " then");
                        L (Ind + 1, "Efail (Bnf_W, " & W & ", ""has a different "
                          & "number of octets than its length says"");");
                        L (Ind, "end if;");
                     end if;
                     L (Ind, "Put (Bnf_W, " & Fid & ");");
                  when S_Rest =>
                     L (Ind, "Put (Bnf_W, " & Fid & ");");
                  when S_Bit_Expr =>
                     if Uses_Remaining (It.Count) then
                        L (Ind, "Efail (Bnf_W, " & W & ", ""has a width that "
                          & "depends on the size of the input, which a "
                          & "writer does not know yet"");");
                     else
                        L (Ind, "declare");
                        L (Ind + 1, "Bnf_N" & U & " : constant Integer_64 := "
                          & Expr_A (It.Count) & ";");
                        L (Ind, "begin");
                        L (Ind + 1, "if Bnf_N" & U & " < 0 or else Bnf_N" & U
                          & " > 64 or else (Bnf_N" & U & " < 64 and then "
                          & "Shift_Right (" & Fid & ", Natural (Bnf_N" & U
                          & ")) /= 0) then");
                        L (Ind + 2, "Efail (Bnf_W, " & W & ", ""does not fit in "
                          & "the number of bits its width field says"");");
                        L (Ind + 1, "end if;");
                        L (Ind + 1, "Wr (Bnf_W, Natural (Bnf_N" & U & "), "
                          & Fid & ");");
                        L (Ind, "end;");
                     end if;
                  when S_Ref =>
                     if It.Bitsof and then Hosted_Mode then
                        --  what the rest of the sequence writes is bits that are
                        --  spelled as words once it ends
                        L (Ind, "Bnf_Words_Begin (Bnf_W, " & Img (It.Width) & ");");
                     elsif not It.Bitsof then
                        if Hosted_Mode and then Find (G, To_String (It.Ref)) = 0
                        then
                           if (for some X of G.External_Tokens =>
                                 To_String (X) = To_String (It.Ref))
                           then
                              --  a text token held by the record: its octets
                              L (Ind, "Put (Bnf_W, To_String (" & Fid & "));");
                           else
                              L (Ind, "Efail (Bnf_W, " & W & ", ""is a text rule "
                                 & "with structure, which Ada writes only as a "
                                 & "token; the C backend writes any"");");
                           end if;
                        else
                           L (Ind, Emit_Fn_Of (To_String (It.Ref)) & " (Bnf_W, "
                             & Fid & ");");
                        end if;
                     end if;
                  when S_Array =>
                     if It.Count /= null then
                        L (Ind, "if Integer_64 (" & Fid & ".Length) /= "
                          & Expr_A (It.Count) & " then");
                        L (Ind + 1, "Efail (Bnf_W, " & W & ", ""has a different "
                          & "number of entries than its count says"");");
                        L (Ind, "end if;");
                     else
                        L (Ind, "if Integer_64 (" & Fid & ".Length) < "
                          & Img (It.Min)
                          & (if It.Max >= 0
                             then " or else Integer_64 (" & Fid & ".Length) > "
                                  & Img (It.Max)
                             else "") & " then");
                        L (Ind + 1, "Efail (Bnf_W, " & W & ", ""has a number of "
                          & "entries outside " & Img (It.Min) & ".."
                          & (if It.Max >= 0 then Img (It.Max) else "")
                          & """);");
                        L (Ind, "end if;");
                     end if;
                     L (Ind, "for Bnf_E" & U & " of " & Fid & " loop");
                     L (Ind + 1, Emit_Fn_Of (To_String (It.Ref)) & " (Bnf_W, Bnf_E"
                       & U & ");");
                     L (Ind, "end loop;");
                  when S_Choice =>
                     Gen_Emit_Match (It.Alts, Fid, Owner & "_" & Ada_Case (N),
                                     Where & "." & N, Ind);
               end case;
            end;
         end loop;
         if Needs_St (S) then
            L (Ind, "end;");
         end if;
         for It of S.Items loop
            if It.Bitsof and then Hosted_Mode then
               L (Ind, "Bnf_Words_End (Bnf_W, " & Table_Of (It.all) & ", "
                  & Sep_Of (It.all) & ");");
            end if;
         end loop;
         --  an empty sequence is no statement
         L (Ind, "null;");
      end Gen_Emit_Seq;

      --  Bind the named fields of a sequence as renamings of the components of
      --  Src (a record).  Comps, from First, are the components' names.
      procedure Bind
        (S : Sequence; Src : String; Comps : Name_Vectors.Vector;
         First : in out Natural; Owner : String; Alt : Boolean; Ind : Natural)
      is
      begin
         for It of S.Items loop
            if Named (It.all) then
               declare
                  C   : constant String :=
                    (if Alt then To_String (Comps (First))
                     else Comp (To_String (It.Name)));
                  Fid : constant String := Def_Field (To_String (It.Name));
               begin
                  L (Ind, Fid & " : " & Type_Name (It.all, Owner) & " renames "
                     & Src & "." & C & ";");
                  First := First + 1;
               end;
            end if;
         end loop;
      end Bind;

      --  A case on a choice (or on a multi-alternative rule): each arm binds
      --  its fields.
      procedure Gen_Emit_Match
        (Alts : Seq_Vectors.Vector; Subject : String; Enum : String;
         Where : String; Ind : Natural)
      is
         K     : Natural := 0;
         Comps : constant Name_Vectors.Vector := Alt_Comps (Alts);
         Skip  : Natural := 0;
      begin
         L (Ind, "case " & Subject & ".Alt is");
         for A of Alts loop
            K := K + 1;
            declare
               M     : constant Natural := Mark;
               First : Natural := Skip + 1;
            begin
               L (Ind + 1, "when " & Img (K) & " =>");
               L (Ind + 2, "declare");
               Bind (A.all, Subject, Comps, First, Enum & "_A" & Img (K), True,
                     Ind + 3);
               L (Ind + 2, "begin");
               if A.Guard /= null and then not Uses_Remaining (A.Guard) then
                  L (Ind + 3, "if not (" & True_A (A.Guard) & ") then");
                  L (Ind + 4, "Efail (Bnf_W, """ & Where & """, ""alternative "
                     & Img (K) & " is chosen, but its guard does not hold"");");
                  L (Ind + 3, "end if;");
               end if;
               Gen_Emit_Seq (A.all, Where, Enum & "_A" & Img (K), Ind + 3);
               L (Ind + 2, "end;");
               Pop (M);
               Skip := First - 1;
            end;
         end loop;
         L (Ind, "end case;");
      end Gen_Emit_Match;

      Has_Actions : constant Boolean :=
        (for some R of G.Rules => R.Action /= Null_Unbounded_String);
      Walks : constant Name_Vectors.Vector := Walk_Set (G);

      --  The walk that runs the actions once a record has been read, children
      --  first.  Base is the record (or the variant record) whose components
      --  Alts names; Comps and First say what the components of the
      --  alternative are called.
      procedure Gen_Walk_Seq
        (S : Sequence; Owner : String; Base : String;
         Comps : Name_Vectors.Vector; First : Natural; Alt : Boolean;
         Ind : Natural)
      is
         Next : Natural := First;
      begin
         for It of S.Items loop
            declare
               N : constant String := To_String (It.Name);
               U : constant String := Img (Next_Id);
               C : constant String :=
                 (if not Named (It.all) then ""
                  elsif Alt then To_String (Comps (Next)) else Comp (N));
            begin
               if Named (It.all) then
                  Next := Next + 1;
               end if;
               if Item_Walks (Walks, It.all) then
                  case It.Kind is
                     when S_Ref =>
                        L (Ind, "Walk_" & Ada_Case (To_String (It.Ref)) & " ("
                           & Base & "." & C & ", H);");
                     when S_Array =>
                        L (Ind, "for E" & U & " of " & Base & "." & C & " loop");
                        L (Ind + 1, "Walk_" & Ada_Case (To_String (It.Ref))
                           & " (E" & U & ", H);");
                        L (Ind, "end loop;");
                     when S_Choice =>
                        declare
                           E  : constant String := Owner & "_" & Ada_Case (N);
                           Cs : constant Name_Vectors.Vector :=
                             Alt_Comps (It.Alts);
                           K  : Natural := 0;
                           Off : Natural := 1;
                        begin
                           L (Ind, "case " & Base & "." & C & ".Alt is");
                           for A of It.Alts loop
                              K := K + 1;
                              if Seq_Walks (Walks, A.all) then
                                 L (Ind + 1, "when " & Img (K) & " =>");
                                 Gen_Walk_Seq (A.all, E & "_A" & Img (K),
                                               Base & "." & C, Cs, Off, True,
                                               Ind + 2);
                              end if;
                              for X of A.Items loop
                                 if Named (X.all) then
                                    Off := Off + 1;
                                 end if;
                              end loop;
                           end loop;
                           L (Ind + 1, "when others =>");
                           L (Ind + 2, "null;");
                           L (Ind, "end case;");
                        end;
                     when others =>
                        null;
                  end case;
               end if;
            end;
         end loop;
      end Gen_Walk_Seq;

      Root   : constant Natural := 1;
      Rt     : constant String := To_String (G.Rules (Root).Name);
      Root_T : constant String := Rule_Type (G.Rules (Root));
      Pkg    : constant String := Package_Name;
   begin
      Check_Code_Language (G, "Ada");
      if Hosted_Mode then
         if Has_Actions then
            raise Wire_Error with
              "an %action in a grammar of text rules and bit rules is read by "
              & "C so far (Ada reads %emit there, but not %action)";
         end if;
      else
         Words := Words_Item (G, "Ada");
      end if;
      if not Hosted_Mode and then Is_Value_Set (G.Rules (Root)) then
         raise Wire_Error with
           "the first rule, `" & Rt & "`, is a list of constants; the "
           & "parser reads the first rule, which should be the whole message";
      end if;

      --  The types (in the specification).
      for R of G.Rules loop
         Declare_Rule (To_String (R.Name));
      end loop;
      if Hosted_Mode then
         Last_Types := To_Unbounded_String
           ("   package Octet_Vectors is new Ada.Containers.Vectors (Natural, Unsigned_8);"
            & ASCII.LF & "   subtype Octets is Octet_Vectors.Vector;" & ASCII.LF
            & ASCII.LF) & Spec;
         Spec := Null_Unbounded_String;
      end if;

      --  Subprogram declarations for the body, the readers and the writers.
      declare
         Decls : Unbounded_String;
      begin
         for R of G.Rules loop
            if not Is_Value_Set (R) then
               declare
                  Nm : constant String := To_String (R.Name);
               begin
                  Append (Decls, "   function " & Parse_Fn_Of (Nm)
                    & " (Bnf_P : in out Parser) return " & Rule_Type (R)
                    & ";" & ASCII.LF);
                  Append (Decls, "   procedure " & Emit_Fn_Of (Nm)
                    & " (Bnf_W : in out Writer; Bnf_V : " & Rule_Type (R)
                    & ");" & ASCII.LF);
                  if R.Emit /= Null_Unbounded_String then
                     Append (Decls, "   procedure " & Emit_Fn_Of (Nm)
                       & "_Body (Bnf_W : in out Writer; Bnf_V : "
                       & Rule_Type (R) & ");" & ASCII.LF);
                  end if;
                  if Has_Actions and then In_Walk (Walks, To_String (R.Name))
                  then
                     if R.Action /= Null_Unbounded_String then
                        Append (Decls, "   procedure Action_" & Ada_Case (Nm)
                          & " (N : " & Rule_Type (R)
                          & "; H : in out Hooks);" & ASCII.LF);
                     end if;
                     Append (Decls, "   procedure Walk_" & Ada_Case (Nm)
                       & " (N : " & Rule_Type (R)
                       & "; H : in out Hooks);" & ASCII.LF);
                  end if;
               end;
            end if;
         end loop;
         Cur := Bod'Unrestricted_Access;
         if not Hosted_Mode then
            Append (Bod, "with Ada.Unchecked_Conversion;" & ASCII.LF);
            if G.Preamble /= Null_Unbounded_String then
               Append (Bod, To_String (G.Preamble) & ASCII.LF);
            end if;
            Append (Bod, ASCII.LF);
            Append (Bod, "package body " & Pkg & " is" & ASCII.LF & ASCII.LF);
         end if;
         L (1, "use Interfaces;");
         L (1, "use type Ada.Containers.Count_Type;");
         L (1, "");
         L (1, "Bnf_Fail      : exception;   --  a read failed; the message is in the parser");
         L (1, "Bnf_Emit_Fail : exception;   --  a write failed; the message is in the writer");
         L (1, "");
         if Hosted_Mode then
            L (1, "type String_Access is access String;");
            L (1, "procedure Bnf_Free is new Ada.Unchecked_Deallocation (String, String_Access);");
            L (1, "");
         end if;
         L (1, "type Parser is record");
         if Hosted_Mode then
            L (2, "Buf      : Text_Access;");
         else
            L (2, "Buf      : access constant Byte_Array;");
         end if;
         L (2, "Nbits    : Natural := 0;");
         L (2, "Bit      : Natural := 0;");
         L (2, "Fail_Bit : Natural := 0;");
         L (2, "Failed   : Boolean := False;");
         L (2, "Msg      : Unbounded_String;");
         if Hosted_Mode then
            L (2, "--  the bits of a text read as words (name:bitsof(rule)): where the input");
            L (2, "--  is kept while the words are read, and how wide a word is");
            L (2, "Unit      : Natural := 0;");
            L (2, "Sv_Active : Boolean := False;");
            L (2, "Sv_Buf    : Text_Access;");
            L (2, "Sv_Bit    : Natural := 0;");
            L (2, "Sv_Nbits  : Natural := 0;");
            L (2, "Sv_Unit   : Natural := 0;");
            L (2, "Sv_Start  : Natural := 0;");
            L (2, "Own       : String_Access;");
         end if;
         L (1, "end record;");
         L (1, "");
         L (1, "type Writer is record");
         L (2, "Buf    : Octets;");
         L (2, "Bit    : Natural := 0;");
         L (2, "Failed : Boolean := False;");
         L (2, "Msg    : Unbounded_String;");
         if Hosted_Mode then
            L (2, "Unit      : Natural := 0;");
            L (2, "Sv_Active : Boolean := False;");
            L (2, "Sv_Buf    : Octets;");
            L (2, "Sv_Bit    : Natural := 0;");
         end if;
         L (1, "end record;");
         L (1, "");
         L (1, "function To_U64 is new Ada.Unchecked_Conversion (Integer_64, Unsigned_64);");
         L (1, "function To_I64 is new Ada.Unchecked_Conversion (Unsigned_64, Integer_64);");
         L (1, "");
         L (1, "function Img (N : Natural) return String is");
         L (2, "S : constant String := Natural'Image (N);");
         L (1, "begin");
         L (2, "return S (S'First + 1 .. S'Last);");
         L (1, "end Img;");
         L (1, "");
         L (1, "--  Keep the deepest failure, the first told.");
         if Hosted_Mode then
            L (1, "procedure Fail (Bnf_P : in out Parser; Bit_In : Natural; Wh, What : String) is");
            L (2, "Bit : Natural := Bit_In;");
            L (2, "How : Unbounded_String := To_Unbounded_String (What);");
            L (1, "begin");
            L (2, "if Bnf_P.Sv_Active then");
            L (3, "--  reading the bits of a text: say which word, and where the text was");
            L (3, "How := To_Unbounded_String (What & "" (at unit "" & Img (Bit_In /");
            L (5, "(if Bnf_P.Unit /= 0 then Bnf_P.Unit else 1) + 1) & "")"");");
            L (3, "Bit := Bnf_P.Sv_Start * 8;");
            L (2, "end if;");
            L (2, "if not (Bnf_P.Failed and then Bit <= Bnf_P.Fail_Bit) then");
            L (3, "Bnf_P.Failed := True;");
            L (3, "Bnf_P.Fail_Bit := Bit;");
            L (3, "Bnf_P.Msg := To_Unbounded_String (Wh & "": "") & How;");
            L (2, "end if;");
            L (2, "raise Bnf_Fail;");
            L (1, "end Fail;");
         else
            L (1, "procedure Fail (Bnf_P : in out Parser; Bit : Natural; Wh, What : String) is");
            L (1, "begin");
            L (2, "if not (Bnf_P.Failed and then Bit <= Bnf_P.Fail_Bit) then");
            L (3, "Bnf_P.Failed := True;");
            L (3, "Bnf_P.Fail_Bit := Bit;");
            L (3, "Bnf_P.Msg := To_Unbounded_String (Wh & "": "" & What);");
            L (2, "end if;");
            L (2, "raise Bnf_Fail;");
            L (1, "end Fail;");
         end if;
         L (1, "");
         L (1, "procedure Efail (Bnf_W : in out Writer; Wh, What : String) is");
         L (1, "begin");
         L (2, "if not Bnf_W.Failed then");
         L (3, "Bnf_W.Failed := True;");
         L (3, "Bnf_W.Msg := To_Unbounded_String (Wh & "": "" & What);");
         L (2, "end if;");
         L (2, "raise Bnf_Emit_Fail;");
         L (1, "end Efail;");
         L (1, "");
         L (1, "--  n bits (at most 64), the first in the most significant place.");
         L (1, "function Rd (Bnf_P : in out Parser; N : Natural; Wh : String) return Unsigned_64 is");
         L (2, "Left : constant Natural := Bnf_P.Nbits - Bnf_P.Bit;");
         L (2, "X    : Unsigned_64 := 0;");
         L (2, "Got  : Natural := 0;");
         L (1, "begin");
         L (2, "if N > Left then");
         L (3, "Fail (Bnf_P, Bnf_P.Bit, Wh, ""needs "" & Img (N) & "" bits, "" & Img (Left) & "" left"");");
         L (2, "end if;");
         L (2, "while Got < N loop");
         L (3, "declare");
         L (4, "Byte : constant Natural := Bnf_P.Bit / 8;");
         L (4, "Off  : constant Natural := Bnf_P.Bit mod 8;");
         L (4, "Tk   : Natural := 8 - Off;");
         L (3, "begin");
         L (4, "if Tk > N - Got then");
         L (5, "Tk := N - Got;");
         L (4, "end if;");
         L (4, "X := Shift_Left (X, Tk)");
         L (5, "or (Shift_Right (Unsigned_64 ("
            & (if Hosted_Mode
               then "Character'Pos (Bnf_P.Buf (Bnf_P.Buf'First + Byte))"
               else "Bnf_P.Buf (Bnf_P.Buf'First + Byte)")
            & "), 8 - Off - Tk)");
         L (6, "and (Shift_Left (Unsigned_64'(1), Tk) - 1));");
         L (4, "Bnf_P.Bit := Bnf_P.Bit + Tk;");
         L (4, "Got := Got + Tk;");
         L (3, "end;");
         L (2, "end loop;");
         L (2, "return X;");
         L (1, "end Rd;");
         L (1, "");
         L (1, "--  n octets, copied, starting wherever the bits are.");
         L (1, "function Take (Bnf_P : in out Parser; N : Integer_64; Wh : String) return Octets is");
         L (2, "V : Octets;");
         L (1, "begin");
         L (2, "if N > Integer_64 ((Bnf_P.Nbits - Bnf_P.Bit) / 8) then");
         L (3, "Fail (Bnf_P, Bnf_P.Bit, Wh, ""needs "" & Img (Natural'Min (Natural (Integer_64'Min (N, Integer_64 (Natural'Last))), Natural'Last)) & "" octets, "" & Img (Bnf_P.Nbits - Bnf_P.Bit) & "" bits left"");");
         L (2, "end if;");
         L (2, "for K in 1 .. Natural (N) loop");
         L (3, "V.Append (Unsigned_8 (Rd (Bnf_P, 8, Wh)));");
         L (2, "end loop;");
         L (2, "return V;");
         L (1, "end Take;");
         L (1, "");
         L (1, "function Take_Rest (Bnf_P : in out Parser; Wh : String) return Octets is");
         L (1, "begin");
         L (2, "return Take (Bnf_P, Integer_64 ((Bnf_P.Nbits - Bnf_P.Bit) / 8), Wh);");
         L (1, "end Take_Rest;");
         L (1, "");
         L (1, "procedure Wr (Bnf_W : in out Writer; N : Natural; V : Unsigned_64) is");
         L (2, "Done : Natural := 0;");
         L (1, "begin");
         L (2, "while Done < N loop");
         L (3, "declare");
         L (4, "Byte  : constant Natural := Bnf_W.Bit / 8;");
         L (4, "Off   : constant Natural := Bnf_W.Bit mod 8;");
         L (4, "Tk    : Natural := 8 - Off;");
         L (4, "Chunk : Unsigned_8;");
         L (3, "begin");
         L (4, "if Tk > N - Done then");
         L (5, "Tk := N - Done;");
         L (4, "end if;");
         L (4, "Chunk := Unsigned_8 (Shift_Right (V, N - Done - Tk)");
         L (5, "and (Shift_Left (Unsigned_64'(1), Tk) - 1));");
         L (4, "if Byte >= Natural (Bnf_W.Buf.Length) then");
         L (5, "Bnf_W.Buf.Append (0);");
         L (4, "end if;");
         L (4, "Bnf_W.Buf.Replace_Element");
         L (5, "(Byte, Bnf_W.Buf.Element (Byte) or Shift_Left (Chunk, 8 - Off - Tk));");
         L (4, "Bnf_W.Bit := Bnf_W.Bit + Tk;");
         L (4, "Done := Done + Tk;");
         L (3, "end;");
         L (2, "end loop;");
         L (1, "end Wr;");
         L (1, "");
         if Hosted_Mode then
            L (1, "procedure Put (Bnf_W : in out Writer; S : String) is");
            L (1, "begin");
            L (2, "for C of S loop");
            L (3, "Wr (Bnf_W, 8, Unsigned_64 (Character'Pos (C)));");
            L (2, "end loop;");
            L (1, "end Put;");
            L (1, "");
            L (1, "--  The octets from the current bit on, as octets: a copy shifted to start on one.");
            L (1, "function Bnf_Shifted (Bnf_P : Parser) return String is");
            L (2, "Off  : constant Natural := Bnf_P.Bit mod 8;");
            L (2, "Base : constant Natural := Bnf_P.Bit / 8 + 1;");
            L (2, "M    : constant Natural := (Bnf_P.Nbits - Bnf_P.Bit) / 8;");
            L (2, "R    : String (1 .. M);");
            L (1, "begin");
            L (2, "for K in 1 .. M loop");
            L (3, "R (K) := Character'Val (Natural (");
            L (4, "Shift_Left (Unsigned_8 (Character'Pos (Bnf_P.Buf (Base + K - 1))), Off)");
            L (4, "or Shift_Right (Unsigned_8 (Character'Pos (Bnf_P.Buf (Base + K))), 8 - Off)));");
            L (2, "end loop;");
            L (2, "return R;");
            L (1, "end Bnf_Shifted;");
            L (1, "");
         end if;
         L (1, "procedure Put (Bnf_W : in out Writer; P : Octets) is");
         L (1, "begin");
         L (2, "for B of P loop");
         L (3, "Wr (Bnf_W, 8, Unsigned_64 (B));");
         L (2, "end loop;");
         L (1, "end Put;");
         L (1, "");
         L (1, "--  the bits to the next boundary of a word; 0 when the grammar has no words");
         if Hosted_Mode then
            L (1, "function Bnf_Align (Bit, Unit : Natural) return Integer_64 is");
            L (2, "(if Unit = 0 then 0 else Integer_64 ((Unit - Bit mod Unit) mod Unit));");
            L (1, "");
            L (1, "type Bnf_Entry is record");
            L (2, "S : access constant String;");
            L (2, "V : Unsigned_64;");
            L (1, "end record;");
            L (1, "type Bnf_Table is array (Positive range <>) of Bnf_Entry;");
            L (1, "package Val_Vectors is new Ada.Containers.Vectors (Natural, Unsigned_64);");
            L (1, "");
            L (1, "--  `name:bitsof(rule)`: the numbered words of the text the rule just read, as");
            L (1, "--  bits, Width to a word; the rest of the rule reads them.  A word is looked for");
            L (1, "--  at each place (the longest that fits); what is between two is skipped.");
            L (1, "procedure Bnf_Words_Begin");
            L (2, "(Bnf_P : in out Parser; Text : String; Width : Positive; Tab : Bnf_Table;");
            L (2, " Start : Natural)");
            L (1, "is");
            L (2, "Vals : Val_Vectors.Vector;");
            L (2, "Pos  : Natural := Text'First;");
            L (1, "begin");
            L (2, "while Pos <= Text'Last loop");
            L (3, "declare");
            L (4, "Best   : Natural := 0;");
            L (4, "Best_V : Unsigned_64 := 0;");
            L (3, "begin");
            L (4, "for E of Tab loop");
            L (5, "if E.S'Length > Best and then E.S'Length <= Text'Last - Pos + 1");
            L (6, "and then Text (Pos .. Pos + E.S'Length - 1) = E.S.all");
            L (5, "then");
            L (6, "Best := E.S'Length;");
            L (6, "Best_V := E.V;");
            L (5, "end if;");
            L (4, "end loop;");
            L (4, "if Best > 0 then");
            L (5, "Vals.Append (Best_V);");
            L (5, "Pos := Pos + Best;");
            L (4, "else");
            L (5, "Pos := Pos + 1;");
            L (4, "end if;");
            L (3, "end;");
            L (2, "end loop;");
            L (2, "declare");
            L (3, "Nbits  : constant Natural := Natural (Vals.Length) * Width;");
            L (3, "Packed : constant String_Access :=");
            L (4, "new String'(1 .. (Nbits + 7) / 8 + 1 => Character'Val (0));");
            L (2, "begin");
            L (3, "for K in 0 .. Natural (Vals.Length) - 1 loop");
            L (4, "for I in 0 .. Width - 1 loop");
            L (5, "declare");
            L (6, "Bit : constant Natural := K * Width + I;");
            L (5, "begin");
            L (6, "if (Shift_Right (Vals.Element (K), Width - 1 - I) and 1) = 1 then");
            L (7, "Packed (Bit / 8 + 1) := Character'Val");
            L (8, "(Natural (Unsigned_8 (Character'Pos (Packed (Bit / 8 + 1))) or Shift_Right (Unsigned_8'(16#80#), Bit mod 8)));");
            L (6, "end if;");
            L (5, "end;");
            L (4, "end loop;");
            L (3, "end loop;");
            L (3, "Bnf_P.Sv_Buf := Bnf_P.Buf;");
            L (3, "Bnf_P.Sv_Bit := Bnf_P.Bit;");
            L (3, "Bnf_P.Sv_Nbits := Bnf_P.Nbits;");
            L (3, "Bnf_P.Sv_Unit := Bnf_P.Unit;");
            L (3, "Bnf_P.Sv_Start := Start;");
            L (3, "Bnf_P.Sv_Active := True;");
            L (3, "Bnf_P.Own := Packed;");
            L (3, "Bnf_P.Buf := Text_Access (Packed);");
            L (3, "Bnf_P.Nbits := Nbits;");
            L (3, "Bnf_P.Bit := 0;");
            L (3, "Bnf_P.Unit := Width;");
            L (2, "end;");
            L (1, "end Bnf_Words_Begin;");
            L (1, "");
            L (1, "--  The end of a rule that read bits from words: all of them must have been used,");
            L (1, "--  and the text is the input again.");
            L (1, "procedure Bnf_Words_End (Bnf_P : in out Parser; Check : Boolean) is");
            L (2, "Bad : Boolean := False;");
            L (1, "begin");
            L (2, "if not Bnf_P.Sv_Active then");
            L (3, "return;");
            L (2, "end if;");
            L (2, "if Check and then Bnf_P.Bit /= Bnf_P.Nbits then");
            L (3, "begin");
            L (4, "Fail (Bnf_P, Bnf_P.Bit, ""the words"",");
            L (6, "Img (Bnf_P.Nbits - Bnf_P.Bit) & "" bit(s) left over"");");
            L (3, "exception");
            L (4, "when Bnf_Fail => Bad := True;");
            L (3, "end;");
            L (2, "end if;");
            L (2, "Bnf_Free (Bnf_P.Own);");
            L (2, "Bnf_P.Buf := Bnf_P.Sv_Buf;");
            L (2, "Bnf_P.Nbits := Bnf_P.Sv_Nbits;");
            L (2, "Bnf_P.Bit := Bnf_P.Sv_Bit;");
            L (2, "Bnf_P.Unit := Bnf_P.Sv_Unit;");
            L (2, "Bnf_P.Sv_Active := False;");
            L (2, "if Bad then");
            L (3, "raise Bnf_Fail;");
            L (2, "end if;");
            L (1, "end Bnf_Words_End;");
            L (1, "");
            L (1, "--  From here the bits written are a word's each, spelled by Bnf_Words_End.");
            L (1, "procedure Bnf_Words_Begin (Bnf_W : in out Writer; Width : Positive) is");
            L (1, "begin");
            L (2, "Bnf_W.Sv_Buf := Bnf_W.Buf;");
            L (2, "Bnf_W.Sv_Bit := Bnf_W.Bit;");
            L (2, "Bnf_W.Buf := Octet_Vectors.Empty_Vector;");
            L (2, "Bnf_W.Bit := 0;");
            L (2, "Bnf_W.Unit := Width;");
            L (2, "Bnf_W.Sv_Active := True;");
            L (1, "end Bnf_Words_Begin;");
            L (1, "");
            L (1, "--  The bits written since, as the words that spell them, with Sep between two,");
            L (1, "--  written to what was the output.");
            L (1, "procedure Bnf_Words_End (Bnf_W : in out Writer; Tab : Bnf_Table; Sep : String) is");
            L (2, "Total : constant Natural := Bnf_W.Bit;");
            L (2, "Width : constant Natural := Bnf_W.Unit;");
            L (2, "Bits  : constant Octets := Bnf_W.Buf;");
            L (1, "begin");
            L (2, "Bnf_W.Buf := Bnf_W.Sv_Buf;");
            L (2, "Bnf_W.Bit := Bnf_W.Sv_Bit;");
            L (2, "Bnf_W.Unit := 0;");
            L (2, "Bnf_W.Sv_Active := False;");
            L (2, "if Width = 0 or else Total mod Width /= 0 then");
            L (3, "Efail (Bnf_W, ""the words"", Img (Total) & "" bits is not a whole number of """);
            L (5, "& Img (Width) & ""-bit units"");");
            L (2, "end if;");
            L (2, "for K in 0 .. Total / Width - 1 loop");
            L (3, "declare");
            L (4, "V     : Unsigned_64 := 0;");
            L (4, "Spelt : Boolean := False;");
            L (3, "begin");
            L (4, "for I in 0 .. Width - 1 loop");
            L (5, "declare");
            L (6, "Bit : constant Natural := K * Width + I;");
            L (5, "begin");
            L (6, "V := Shift_Left (V, 1)");
            L (7, "or Unsigned_64 (Shift_Right (Bits.Element (Bit / 8), 7 - Bit mod 8) and 1);");
            L (5, "end;");
            L (4, "end loop;");
            L (4, "for E of Tab loop");
            L (5, "if E.V = V then");
            L (6, "if K > 0 and then Sep'Length > 0 then");
            L (7, "Put (Bnf_W, Sep);");
            L (6, "end if;");
            L (6, "Put (Bnf_W, E.S.all);");
            L (6, "Spelt := True;");
            L (6, "exit;");
            L (5, "end if;");
            L (4, "end loop;");
            L (4, "if not Spelt then");
            L (5, "Efail (Bnf_W, ""the words"", ""unit "" & Img (K) & "" has the value """);
            L (7, "& Img (Natural (V)) & "", which no word spells"");");
            L (4, "end if;");
            L (3, "end;");
            L (2, "end loop;");
            L (1, "end Bnf_Words_End;");
            L (1, "");
         else
            L (1, "Bnf_Unit : constant Natural := "
               & (if Words = null then "0" else Img (Words.Width)) & ";");
            L (1, "function Bnf_Align (Bit : Natural) return Integer_64 is");
            L (2, "(if Bnf_Unit = 0 then 0 else Integer_64 ((Bnf_Unit - Bit mod Bnf_Unit) mod Bnf_Unit));");
         end if;
         L (1, "function Bnf_I (X : Unsigned_8) return Integer_64 is (To_I64 (Unsigned_64 (X)));");
         L (1, "function Bnf_I (X : Unsigned_16) return Integer_64 is (To_I64 (Unsigned_64 (X)));");
         L (1, "function Bnf_I (X : Unsigned_32) return Integer_64 is (To_I64 (Unsigned_64 (X)));");
         L (1, "function Bnf_I (X : Unsigned_64) return Integer_64 is (To_I64 (X));");
         L (1, "function Bnf_I (X : Integer_8) return Integer_64 is (Integer_64 (X));");
         L (1, "function Bnf_I (X : Integer_16) return Integer_64 is (Integer_64 (X));");
         L (1, "function Bnf_I (X : Integer_32) return Integer_64 is (Integer_64 (X));");
         L (1, "function Bnf_I (X : Integer_64) return Integer_64 is (X);");
         L (1, "function Bnf_B (X : Boolean) return Integer_64 is (if X then 1 else 0);");
         L (1, "function Bnf_Add (A, B : Integer_64) return Integer_64 is (To_I64 (To_U64 (A) + To_U64 (B)));");
         L (1, "function Bnf_Sub (A, B : Integer_64) return Integer_64 is (To_I64 (To_U64 (A) - To_U64 (B)));");
         L (1, "function Bnf_Mul (A, B : Integer_64) return Integer_64 is (To_I64 (To_U64 (A) * To_U64 (B)));");
         L (1, "function Bnf_Neg (A : Integer_64) return Integer_64 is (To_I64 (0 - To_U64 (A)));");
         L (1, "function Bnf_Not (A : Integer_64) return Integer_64 is (To_I64 (not To_U64 (A)));");
         L (1, "function Bnf_And (A, B : Integer_64) return Integer_64 is (To_I64 (To_U64 (A) and To_U64 (B)));");
         L (1, "function Bnf_Or (A, B : Integer_64) return Integer_64 is (To_I64 (To_U64 (A) or To_U64 (B)));");
         L (1, "function Bnf_Xor (A, B : Integer_64) return Integer_64 is (To_I64 (To_U64 (A) xor To_U64 (B)));");
         L (1, "function Bnf_Div (A, B : Integer_64) return Integer_64 is");
         L (2, "(if B = 0 then 0 elsif B = -1 then Bnf_Neg (A) else A / B);");
         L (1, "function Bnf_Rem (A, B : Integer_64) return Integer_64 is");
         L (2, "(if B = 0 or else B = -1 then 0 else A rem B);");
         L (1, "function Bnf_Shl (A, B : Integer_64) return Integer_64 is");
         L (2, "(To_I64 (Shift_Left (To_U64 (A), Natural (To_U64 (B) and 63))));");
         L (1, "function Bnf_Shr (A, B : Integer_64) return Integer_64 is");
         L (2, "(To_I64 (Shift_Right (To_U64 (A), Natural (To_U64 (B) and 63))));");
         L (1, "function Bnf_Swap (V : Unsigned_64; Nbytes : Natural) return Unsigned_64 is");
         L (2, "R : Unsigned_64 := 0;");
         L (2, "X : Unsigned_64 := V;");
         L (1, "begin");
         L (2, "for K in 1 .. Nbytes loop");
         L (3, "R := Shift_Left (R, 8) or (X and 16#FF#);");
         L (3, "X := Shift_Right (X, 8);");
         L (2, "end loop;");
         L (2, "return R;");
         L (1, "end Bnf_Swap;");
         L (1, "");
         --  value sets
         for R of G.Rules loop
            if Is_Value_Set (R) then
               declare
                  First : Boolean := True;
                  T     : Unbounded_String;
               begin
                  for A of R.Alts loop
                     if not First then
                        Append (T, " | ");
                     end if;
                     First := False;
                     Append (T, Hex (A.Items.First_Element.Value));
                  end loop;
                  L (1, "function " & In_Of (To_String (R.Name))
                     & " (V : Unsigned_64) return Boolean is");
                  L (2, "(V in " & To_String (T) & ");");
                  L (1, "");
               end;
            end if;
         end loop;
         if Has_Actions then
            L (1, "package Warn_Vectors is new Ada.Containers.Vectors (Natural, Unbounded_String);");
            L (1, "");
            L (1, "--  What an %action sees: Hbnf_Warn adds a warning, Hbnf_Fail fails the read.");
            L (1, "type Hooks is record");
            L (2, "Warnings : Warn_Vectors.Vector;");
            L (2, "Msg      : Unbounded_String;");
            L (1, "end record;");
            L (1, "Bnf_Action_Fail : exception;");
            L (1, "Bnf_Warns : Warn_Vectors.Vector;   --  the last successful read's warnings");
            L (1, "");
            L (1, "procedure Hbnf_Warn (H : in out Hooks; M : String) is");
            L (1, "begin");
            L (2, "H.Warnings.Append (To_Unbounded_String (M));");
            L (1, "end Hbnf_Warn;");
            L (1, "");
            L (1, "procedure Hbnf_Fail (H : in out Hooks; M : String) is");
            L (1, "begin");
            L (2, "if Length (H.Msg) = 0 then");
            L (3, "H.Msg := To_Unbounded_String (M);");
            L (2, "end if;");
            L (2, "raise Bnf_Action_Fail;");
            L (1, "end Hbnf_Fail;");
            L (1, "");
            L (1, "function Warning_Count return Natural is (Natural (Bnf_Warns.Length));");
            L (1, "function Warning (I : Positive) return String is");
            L (2, "(To_String (Bnf_Warns.Element (I - 1)));");
            L (1, "");
         end if;
         Append (Bod, To_String (Decls));
         L (1, "");
         if G.Epilogue /= Null_Unbounded_String then
            L (1, "--  the grammar's epilogue");
            Append (Bod, To_String (G.Epilogue) & ASCII.LF);
            L (1, "");
         end if;
      end;

      --  The numbered words of each `bitsof`, and what stands between two.
      if Hosted_Mode then
         declare
            procedure Tables (Alts : Seq_Vectors.Vector) is
            begin
               for A of Alts loop
                  for It of A.Items loop
                     if It.Bitsof then
                        declare
                           Tab : constant String := Table_Of (It.all);
                           N   : Natural := 0;
                        begin
                           for U of It.Words loop
                              N := N + 1;
                              L (1, Tab & "_S" & Img (N) & " : aliased constant String := "
                                 & Ada_Str (To_String (U.Spelling)) & ";");
                           end loop;
                           L (1, Tab & " : constant Bnf_Table :=");
                           N := 0;
                           for U of It.Words loop
                              N := N + 1;
                              L (2, (if N = 1 then "(" else " ") & Img (N) & " => ("
                                 & Tab & "_S" & Img (N) & "'Access, " & Img (U.Value) & ")"
                                 & (if N = Natural (It.Words.Length) then ");" else ","));
                           end loop;
                           L (1, Sep_Of (It.all) & " : constant String := "
                              & Ada_Str (To_String (It.Sep)) & ";");
                           L (1, "");
                        end;
                     elsif It.Kind = S_Choice then
                        Tables (It.Alts);
                     end if;
                  end loop;
               end loop;
            end Tables;
         begin
            Cur := Bod'Unrestricted_Access;
            for R of G.Rules loop
               Tables (R.Alts);
            end loop;
         end;
      end if;

      --  The readers and the writers.
      for R of G.Rules loop
         if not Is_Value_Set (R) then
            declare
               Nm : constant String := To_String (R.Name);
               T  : constant String := Rule_Type (R);
               M  : constant Natural := Mark;
               Base : constant String := Pfx & Ada_Case (Nm);
               Wrap : constant Boolean := Hosted_Mode and then Rule_Has_Bitsof (R);
               Fn   : constant String := Parse_Fn_Of (Nm) & (if Wrap then "_Body" else "");
            begin
               --  reader
               declare
                  Decls : Unbounded_String;
                  Stmts : Unbounded_String;
                  Dummy : Unbounded_String;
               begin
                  Cur := Dummy'Unrestricted_Access;
                  if Natural (R.Alts.Length) = 1 then
                     Gen_Seq (R.Alts.First_Element.all, Nm, Base, 2, Decls, Stmts);
                     declare
                        First : Natural := 1;
                        Agg : constant String :=
                          Aggregate (R.Alts.First_Element.all,
                                     Name_Vectors.Empty_Vector, First, 0);
                     begin
                        Cur := Bod'Unrestricted_Access;
                        L (1, "function " & Fn
                           & " (Bnf_P : in out Parser) return " & T & " is");
                        Append (Bod, To_String (Decls));
                        L (1, "begin");
                        Append (Bod, To_String (Stmts));
                        L (2, "return (" & Agg & ");");
                        L (1, "end " & Fn & ";");
                     end;
                  else
                     Cur := Stmts'Unrestricted_Access;
                     Gen_Choice (R.Alts, Base, "Bnf_R", Nm, 2);
                     Cur := Bod'Unrestricted_Access;
                     L (1, "function " & Fn
                        & " (Bnf_P : in out Parser) return " & T & " is");
                     L (2, "Bnf_R : " & T & ";");
                     L (1, "begin");
                     Append (Bod, To_String (Stmts));
                     L (2, "return Bnf_R;");
                     L (1, "end " & Fn & ";");
                  end if;
                  L (1, "");
               end;
               if Wrap then
                  L (1, "function " & Parse_Fn_Of (Nm)
                     & " (Bnf_P : in out Parser) return " & T & " is");
                  L (1, "begin");
                  L (2, "declare");
                  L (3, "R : constant " & T & " := " & Fn & " (Bnf_P);");
                  L (2, "begin");
                  L (3, "Bnf_Words_End (Bnf_P, True);");
                  L (3, "return R;");
                  L (2, "end;");
                  L (1, "exception");
                  L (2, "when Bnf_Fail =>");
                  L (3, "Bnf_Words_End (Bnf_P, False);");
                  L (3, "raise;");
                  L (1, "end " & Parse_Fn_Of (Nm) & ";");
                  L (1, "");
               end if;
               Pop (M);
               --  writer
               L (1, "procedure " & Emit_Fn_Of (Nm)
                  & (if R.Emit /= Null_Unbounded_String then "_Body" else "")
                  & " (Bnf_W : in out Writer; Bnf_V : " & T & ") is");
               Emit_Side := True;
               if Natural (R.Alts.Length) = 1 then
                  declare
                     First : Natural := 1;
                  begin
                     Bind (R.Alts.First_Element.all, "Bnf_V",
                           Name_Vectors.Empty_Vector, First, Base, False, 2);
                  end;
                  L (1, "begin");
                  Gen_Emit_Seq (R.Alts.First_Element.all, Nm, Base, 2);
               else
                  L (1, "begin");
                  Gen_Emit_Match (R.Alts, "Bnf_V", Base, Nm, 2);
               end if;
               L (1, "end " & Emit_Fn_Of (Nm)
                  & (if R.Emit /= Null_Unbounded_String then "_Body" else "")
                  & ";");
               L (1, "");
               if R.Emit /= Null_Unbounded_String then
                  --  %emit runs on a copy of the record, before its fields are
                  --  written
                  L (1, "procedure " & Emit_Fn_Of (Nm)
                     & " (Bnf_W : in out Writer; Bnf_V : " & T & ") is");
                  L (2, "N : " & T & " := Bnf_V;");
                  L (2, "procedure Hbnf_Emit_Fail (M : String) is");
                  L (2, "begin");
                  L (3, "Efail (Bnf_W, ""emit"", M);");
                  L (2, "end Hbnf_Emit_Fail;");
                  L (1, "begin");
                  Append (Bod, To_String (R.Emit) & ASCII.LF);
                  L (2, Emit_Fn_Of (Nm) & "_Body (Bnf_W, N);");
                  L (1, "end " & Emit_Fn_Of (Nm) & ";");
                  L (1, "");
               end if;
               Emit_Side := False;
               Pop (M);
            end;
         end if;
      end loop;

      if Has_Actions then
         for R of G.Rules loop
            if not Is_Value_Set (R) and then In_Walk (Walks, To_String (R.Name))
            then
               declare
                  Nm   : constant String := To_String (R.Name);
                  T    : constant String := Rule_Type (R);
                  Base : constant String := Pfx & Ada_Case (Nm);
               begin
                  if R.Action /= Null_Unbounded_String then
                     L (1, "procedure Action_" & Ada_Case (Nm) & " (N : " & T
                        & "; H : in out Hooks) is");
                     L (1, "begin");
                     Append (Bod, To_String (R.Action) & ASCII.LF);
                     L (1, "end Action_" & Ada_Case (Nm) & ";");
                     L (1, "");
                  end if;
                  L (1, "procedure Walk_" & Ada_Case (Nm) & " (N : " & T
                     & "; H : in out Hooks) is");
                  L (1, "begin");
                  if Natural (R.Alts.Length) = 1 then
                     Gen_Walk_Seq (R.Alts.First_Element.all, Base, "N",
                                   Name_Vectors.Empty_Vector, 1, False, 2);
                  else
                     declare
                        Cs  : constant Name_Vectors.Vector := Alt_Comps (R.Alts);
                        K   : Natural := 0;
                        Off : Natural := 1;
                     begin
                        L (2, "case N.Alt is");
                        for A of R.Alts loop
                           K := K + 1;
                           if Seq_Walks (Walks, A.all) then
                              L (3, "when " & Img (K) & " =>");
                              Gen_Walk_Seq (A.all, Base & "_A" & Img (K), "N",
                                            Cs, Off, True, 4);
                           end if;
                           for X of A.Items loop
                              if Named (X.all) then
                                 Off := Off + 1;
                              end if;
                           end loop;
                        end loop;
                        L (3, "when others =>");
                        L (4, "null;");
                        L (2, "end case;");
                     end;
                  end if;
                  if R.Action /= Null_Unbounded_String then
                     L (2, "Action_" & Ada_Case (Nm) & " (N, H);");
                  end if;
                  L (2, "null;");
                  L (1, "end Walk_" & Ada_Case (Nm) & ";");
                  L (1, "");
               end;
            end if;
         end loop;
         L (1, "--  Run the actions on a record that has been read; the warnings are kept.");
         L (1, "procedure Bnf_Check (V : " & Root_T & "; Msg : out Unbounded_String;");
         L (3, "Ok : out Boolean) is");
         L (2, "H : Hooks;");
         L (1, "begin");
         L (2, "Msg := Null_Unbounded_String;");
         L (2, "Walk_" & Ada_Case (Rt) & " (V, H);");
         L (2, "Bnf_Warns := H.Warnings;");
         L (2, "Ok := True;");
         L (1, "exception");
         L (2, "when Bnf_Action_Fail =>");
         L (3, "Msg := H.Msg;");
         L (3, "Ok := False;");
         L (1, "end Bnf_Check;");
         L (1, "");
      end if;

      if Hosted_Mode then
         for R of G.Rules loop
            if not Is_Value_Set (R) then
               declare
                  Nm : constant String := To_String (R.Name);
                  Id : constant String := HBNF_Ada.Ident (Nm);
                  Sp : constant String :=
                    "   procedure Emit_Bits_" & Id & " (V : "
                    & HBNF_Ada.Type_Name (Nm) & "; Bytes : out Octets;"
                    & ASCII.LF & "      Nbits : out Natural; Ok : out Boolean;"
                    & ASCII.LF & "      Message : out Unbounded_String)";
               begin
                  Append (Last_Spec, "   --  The bits of one " & Nm
                          & ", written (its %emit first)." & ASCII.LF
                          & Sp & ";" & ASCII.LF & ASCII.LF);
                  L (1, Sp & " is");
                  L (2, "Bnf_W : Writer;");
                  L (1, "begin");
                  L (2, "Ok := False;");
                  L (2, "Nbits := 0;");
                  L (2, "Bytes := Octet_Vectors.Empty_Vector;");
                  L (2, "Message := Null_Unbounded_String;");
                  L (2, Emit_Fn_Of (Nm) & " (Bnf_W, V);");
                  L (2, "Bytes := Bnf_W.Buf;");
                  L (2, "Nbits := Bnf_W.Bit;");
                  L (2, "Ok := True;");
                  L (1, "exception");
                  L (2, "when Bnf_Emit_Fail =>");
                  L (3, "Message := Bnf_W.Msg;");
                  L (1, "end Emit_Bits_" & Id & ";");
                  L (1, "");
               end;
            end if;
         end loop;
      elsif Words = null then
      --  The entry points.
      L (1, "procedure Parse_Bits (Buf : Byte_Array; Nbits : Natural;");
      L (3, "Result : out " & Root_T & "; Ok : out Boolean;");
      L (3, "Err : out Parse_Error) is");
      L (2, "Bnf_P : Parser;");
      L (2, "Bnf_A : aliased constant Byte_Array := Buf;");
      L (1, "begin");
      L (2, "Ok := False;");
      L (2, "Err := (At_Octet => 0, Message => Null_Unbounded_String);");
      L (2, "Bnf_P.Buf := Bnf_A'Unchecked_Access;");
      L (2, "Bnf_P.Nbits := Nbits;");
      L (2, "Result := " & Parse_Fn_Of (Rt) & " (Bnf_P);");
      L (2, "if Bnf_P.Bit /= Nbits then");
      L (3, "Bnf_P.Failed := False;");
      L (3, "begin");
      L (4, "Fail (Bnf_P, Bnf_P.Bit, """ & Rt & """, Img (Nbits - Bnf_P.Bit)");
      L (5, "& "" bit(s) left over after the message"");");
      L (3, "exception");
      L (4, "when Bnf_Fail => null;");
      L (3, "end;");
      L (3, "Err := (At_Octet => Bnf_P.Fail_Bit / 8,");
      L (5, "Message => To_Unbounded_String (""octet "" & Img (Bnf_P.Fail_Bit / 8)");
      L (6, "& "": "" & To_String (Bnf_P.Msg)));");
      L (3, "return;");
      L (2, "end if;");
      if Has_Actions then
         L (2, "declare");
         L (3, "Msg  : Unbounded_String;");
         L (3, "Good : Boolean;");
         L (2, "begin");
         L (3, "Bnf_Check (Result, Msg, Good);");
         L (3, "if not Good then");
         L (4, "Err := (At_Octet => Bnf_P.Bit / 8,");
         L (6, "Message => To_Unbounded_String (""octet "" & Img (Bnf_P.Bit / 8)");
         L (7, "& "": " & Escape (Rt) & ": "" & To_String (Msg)));");
         L (4, "return;");
         L (3, "end if;");
         L (2, "end;");
      end if;
      L (2, "Ok := True;");
      L (1, "exception");
      L (2, "when Bnf_Fail =>");
      L (3, "Err := (At_Octet => Bnf_P.Fail_Bit / 8,");
      L (5, "Message => To_Unbounded_String (""octet "" & Img (Bnf_P.Fail_Bit / 8)");
      L (6, "& "": "" & To_String (Bnf_P.Msg)));");
      L (1, "end Parse_Bits;");
      L (1, "");
      L (1, "procedure Parse_Bytes (Buf : Byte_Array; Result : out " & Root_T & ";");
      L (3, "Ok : out Boolean; Err : out Parse_Error) is");
      L (1, "begin");
      L (2, "Parse_Bits (Buf, Buf'Length * 8, Result, Ok, Err);");
      L (1, "end Parse_Bytes;");
      L (1, "");
      L (1, "procedure Emit_Bits (V : " & Root_T & "; Bytes : out Octets;");
      L (3, "Nbits : out Natural; Ok : out Boolean;");
      L (3, "Message : out Unbounded_String) is");
      L (2, "Bnf_W : Writer;");
      L (1, "begin");
      L (2, "Ok := False;");
      L (2, "Nbits := 0;");
      L (2, "Bytes := Octet_Vectors.Empty_Vector;");
      L (2, "Message := Null_Unbounded_String;");
      L (2, Emit_Fn_Of (Rt) & " (Bnf_W, V);");
      L (2, "Bytes := Bnf_W.Buf;");
      L (2, "Nbits := Bnf_W.Bit;");
      L (2, "Ok := True;");
      L (1, "exception");
      L (2, "when Bnf_Emit_Fail =>");
      L (3, "Message := Bnf_W.Msg;");
      L (1, "end Emit_Bits;");
      L (1, "");
      L (1, "procedure Emit_Bytes (V : " & Root_T & "; Bytes : out Octets;");
      L (3, "Ok : out Boolean; Message : out Unbounded_String) is");
      L (2, "N : Natural;");
      L (1, "begin");
      L (2, "Emit_Bits (V, Bytes, N, Ok, Message);");
      L (2, "if Ok and then N mod 8 /= 0 then");
      L (3, "Ok := False;");
      L (3, "Message := To_Unbounded_String (""" & Rt
         & ": the message does not end on an octet boundary"");");
      L (2, "end if;");
      L (1, "end Emit_Bytes;");
      L (1, "");
      else
      --  The entry points for the words of a text.
      declare
         Order : Unit_Vectors.Vector := Words.Words;
         N     : Natural := 0;
      begin
         for I in 1 .. Natural (Order.Length) loop
            for J in I + 1 .. Natural (Order.Length) loop
               if Length (Order (J).Spelling) > Length (Order (I).Spelling) then
                  declare
                     T : constant Unit := Order (I);
                  begin
                     Order (I) := Order (J);
                     Order (J) := T;
                  end;
               end if;
            end loop;
         end loop;
         L (1, "Bnf_Width : constant Natural := " & Img (Words.Width) & ";");
         L (1, "Bnf_Sep   : constant String := " & Ada_Str (To_String (Words.Sep)) & ";");
         L (1, "");
         L (1, "--  the spellings of the words and their numbers, a longer one before a");
         L (1, "--  shorter one it starts with");
         for U of Order loop
            N := N + 1;
            L (1, "Bnf_S" & Img (N) & " : aliased constant String := "
               & Ada_Str (To_String (U.Spelling)) & ";");
         end loop;
         L (1, "type Bnf_Entry is record");
         L (2, "S : access constant String;");
         L (2, "V : Unsigned_64;");
         L (1, "end record;");
         L (1, "Bnf_Words : constant array (1 .. " & Img (N) & ") of Bnf_Entry :=");
         N := 0;
         for U of Order loop
            N := N + 1;
            L (2, (if N = 1 then "(" else " ") & "(Bnf_S" & Img (N) & "'Access, "
               & Img (U.Value) & ")"
               & (if N = Natural (Order.Length) then ");" else ","));
         end loop;
         L (1, "");
         L (1, "package Val_Vectors is new Ada.Containers.Vectors (Natural, Unsigned_64);");
         L (1, "");
         L (1, "--  up to 24 characters of the text from From");
         L (1, "function Found (Text : String; From : Integer) return String is");
         L (2, "Last  : Integer := From - 1;");
         L (2, "Chars : Natural := 0;");
         L (1, "begin");
         L (2, "if From > Text'Last then");
         L (3, "return ""end of input"";");
         L (2, "end if;");
         L (2, "for K in From .. Text'Last loop");
         L (3, "if Character'Pos (Text (K)) / 64 /= 2 then");
         L (4, "exit when Chars = 24;");
         L (4, "Chars := Chars + 1;");
         L (3, "end if;");
         L (3, "Last := K;");
         L (2, "end loop;");
         L (2, "return Text (From .. Last);");
         L (1, "end Found;");
         L (1, "");
         L (1, "--  The words as bits: Bnf_Width each, the first word first.");
         L (1, "function Pack (Vals : Val_Vectors.Vector) return Byte_Array is");
         L (2, "Nbits : constant Natural := Natural (Vals.Length) * Bnf_Width;");
         L (2, "R     : Byte_Array (0 .. (Nbits + 7) / 8 - 1) := (others => 0);");
         L (1, "begin");
         L (2, "for K in 0 .. Natural (Vals.Length) - 1 loop");
         L (3, "for I in 0 .. Bnf_Width - 1 loop");
         L (4, "declare");
         L (5, "Bit : constant Natural := K * Bnf_Width + I;");
         L (4, "begin");
         L (5, "if (Shift_Right (Vals.Element (K), Bnf_Width - 1 - I) and 1) = 1 then");
         L (6, "R (Bit / 8) := R (Bit / 8) or Shift_Right (Unsigned_8'(16#80#), Bit mod 8);");
         L (5, "end if;");
         L (4, "end;");
         L (3, "end loop;");
         L (2, "end loop;");
         L (2, "return R;");
         L (1, "end Pack;");
         L (1, "");
         L (1, "procedure Parse_Text (Text : String; Result : out " & Root_T & ";");
         L (3, "Ok : out Boolean; Err : out Parse_Error) is");
         L (2, "Vals : Val_Vectors.Vector;");
         L (2, "Pos  : Integer := Text'First;");
         L (1, "begin");
         L (2, "Ok := False;");
         L (2, "Err := (At_Octet => 0, Message => Null_Unbounded_String);");
         if Words.Words_Empty then
            L (2, "if Text'Length > 0 then");
         else
            L (2, "if True then");
         end if;
         L (3, "loop");
         L (4, "declare");
         L (5, "Best  : Natural := 0;");
         L (5, "Best_V : Unsigned_64 := 0;");
         L (5, "Hit   : Boolean := False;");
         L (4, "begin");
         L (5, "for E of Bnf_Words loop");
         L (6, "if E.S'Length <= Text'Last - Pos + 1");
         L (7, "and then Text (Pos .. Pos + E.S'Length - 1) = E.S.all");
         L (7, "and then (not Hit or else E.S'Length > Best)");
         L (6, "then");
         L (7, "Hit := True;");
         L (7, "Best := E.S'Length;");
         L (7, "Best_V := E.V;");
         L (6, "end if;");
         L (5, "end loop;");
         L (5, "if not Hit then");
         L (6, "Err := (At_Octet => Pos - Text'First,");
         L (8, "Message => To_Unbounded_String (""expected a "
            & Escape (To_String (Words.Word_Rule)) & ", found "" & Found (Text, Pos)));");
         L (6, "return;");
         L (5, "end if;");
         L (5, "Vals.Append (Best_V);");
         L (5, "Pos := Pos + Best;");
         L (4, "end;");
         L (4, "exit when Pos > Text'Last;");
         L (4, "if Bnf_Sep'Length > 0 then");
         L (5, "if Pos + Bnf_Sep'Length - 1 > Text'Last");
         L (6, "or else Text (Pos .. Pos + Bnf_Sep'Length - 1) /= Bnf_Sep");
         L (5, "then");
         L (6, "Err := (At_Octet => Pos - Text'First,");
         L (8, "Message => To_Unbounded_String (""expected `"" & Bnf_Sep & ""`, found "" & Found (Text, Pos)));");
         L (6, "return;");
         L (5, "end if;");
         L (5, "Pos := Pos + Bnf_Sep'Length;");
         L (4, "end if;");
         L (3, "end loop;");
         L (2, "end if;");
         L (2, "declare");
         L (3, "Nbits : constant Natural := Natural (Vals.Length) * Bnf_Width;");
         L (3, "Bnf_A : aliased constant Byte_Array := Pack (Vals);");
         L (3, "Bnf_P : Parser;");
         L (2, "begin");
         L (3, "Bnf_P.Buf := Bnf_A'Unchecked_Access;");
         L (3, "Bnf_P.Nbits := Nbits;");
         L (3, "begin");
         L (4, "Result := " & Parse_Fn_Of (Rt) & " (Bnf_P);");
         L (4, "if Bnf_P.Bit /= Nbits then");
         L (5, "Bnf_P.Failed := False;");
         L (5, "begin");
         L (6, "Fail (Bnf_P, Bnf_P.Bit, ""the words"", Img (Nbits - Bnf_P.Bit) & "" bit(s) left over"");");
         L (5, "exception");
         L (6, "when Bnf_Fail => null;");
         L (5, "end;");
         L (5, "raise Bnf_Fail;");
         L (4, "end if;");
         if Has_Actions then
            L (4, "declare");
            L (5, "Msg  : Unbounded_String;");
            L (5, "Good : Boolean;");
            L (4, "begin");
            L (5, "Bnf_Check (Result, Msg, Good);");
            L (5, "if not Good then");
            L (6, "Err := (At_Octet => 0, Message => Msg);");
            L (6, "return;");
            L (5, "end if;");
            L (4, "end;");
         end if;
         L (4, "Ok := True;");
         L (3, "exception");
         L (4, "when Bnf_Fail =>");
         L (5, "Err := (At_Octet => 0,");
         L (7, "Message => To_Unbounded_String (""expected "" & To_String (Bnf_P.Msg)");
         L (9, "& "" (at unit "" & Img (Bnf_P.Fail_Bit / Bnf_Width + 1)");
         L (9, "& ""), found "" & Found (Text, Text'First)));");
         L (3, "end;");
         L (2, "end;");
         L (1, "end Parse_Text;");
         L (1, "");
         L (1, "procedure Emit_Text (V : " & Root_T & "; Text : out Unbounded_String;");
         L (3, "Ok : out Boolean; Message : out Unbounded_String) is");
         L (2, "Bnf_W : Writer;");
         L (1, "begin");
         L (2, "Ok := False;");
         L (2, "Text := Null_Unbounded_String;");
         L (2, "Message := Null_Unbounded_String;");
         L (2, Emit_Fn_Of (Rt) & " (Bnf_W, V);");
         L (2, "if Bnf_W.Bit mod Bnf_Width /= 0 then");
         L (3, "Message := To_Unbounded_String (""the words: "" & Img (Bnf_W.Bit)");
         L (5, "& "" bits is not a whole number of "" & Img (Bnf_Width) & ""-bit units"");");
         L (3, "return;");
         L (2, "end if;");
         L (2, "for K in 0 .. Bnf_W.Bit / Bnf_Width - 1 loop");
         L (3, "declare");
         L (4, "X     : Unsigned_64 := 0;");
         L (4, "Spelt : Boolean := False;");
         L (3, "begin");
         L (4, "for I in 0 .. Bnf_Width - 1 loop");
         L (5, "declare");
         L (6, "Bit : constant Natural := K * Bnf_Width + I;");
         L (5, "begin");
         L (6, "X := Shift_Left (X, 1)");
         L (7, "or Unsigned_64 (Shift_Right (Bnf_W.Buf.Element (Bit / 8), 7 - Bit mod 8) and 1);");
         L (5, "end;");
         L (4, "end loop;");
         L (4, "for E of Bnf_Words loop");
         L (5, "if E.V = X then");
         L (6, "if K > 0 then");
         L (7, "Append (Text, Bnf_Sep);");
         L (6, "end if;");
         L (6, "Append (Text, E.S.all);");
         L (6, "Spelt := True;");
         L (6, "exit;");
         L (5, "end if;");
         L (4, "end loop;");
         L (4, "if not Spelt then");
         L (5, "Message := To_Unbounded_String (""the words: unit "" & Img (K)");
         L (7, "& "" has the value "" & Img (Natural (X)) & "", which no word spells"");");
         L (5, "return;");
         L (4, "end if;");
         L (3, "end;");
         L (2, "end loop;");
         L (2, "Ok := True;");
         L (1, "exception");
         L (2, "when Bnf_Emit_Fail =>");
         L (3, "Message := Bnf_W.Msg;");
         L (1, "end Emit_Text;");
         L (1, "");
      end;
      end if;
      if Hosted_Mode then
         declare
            Text : Unbounded_String := To_Unbounded_String (Rename (To_String (Bod)));
         begin
            Last_Withs := To_Unbounded_String
              ("with Ada.Containers.Vectors;" & ASCII.LF
               & "with Ada.Unchecked_Conversion;" & ASCII.LF);
            if G.Preamble /= Null_Unbounded_String then
               Append (Last_Withs, To_String (G.Preamble) & ASCII.LF);
            end if;
            --  what the text parser calls: a bit rule read as a text rule is
            for R of G.Rules loop
               if not Is_Value_Set (R) then
                  declare
                     Nm : constant String := To_String (R.Name);
                     T  : constant String := HBNF_Ada.Type_Name (Nm);
                  begin
                     Append (Text, ASCII.LF & "   function " & HBNF_Ada.Parse_Fn (Nm)
                       & " (P : in out Parser) return " & T & " is" & ASCII.LF);
                     Append (Text, "      W : Wire_Parser :=" & ASCII.LF
                       & "        (Buf => P.Text, Nbits => P.Text'Length * 8,"
                       & ASCII.LF & "         Bit => (P.Pos - 1) * 8 + P.Bit, others => <>);"
                       & ASCII.LF & "      R : " & T & ";" & ASCII.LF);
                     Append (Text, "   begin" & ASCII.LF & "      begin" & ASCII.LF
                       & "         R := " & Parse_Fn_Of (Nm) & " (W);" & ASCII.LF
                       & "      exception" & ASCII.LF & "         when Bnf_Fail =>"
                       & ASCII.LF & "            P.Pos := W.Fail_Bit / 8 + 1;"
                       & ASCII.LF & "            Fail (P, To_String (W.Msg));"
                       & ASCII.LF & "      end;" & ASCII.LF
                       & "      P.Pos := W.Bit / 8 + 1;" & ASCII.LF
                       & "      P.Bit := W.Bit mod 8;" & ASCII.LF
                       & "      return R;" & ASCII.LF & "   end "
                       & HBNF_Ada.Parse_Fn (Nm) & ";" & ASCII.LF);
                  end;
               end if;
            end loop;
            return To_String (Text);
         end;
      end if;
      Append (Bod, "end " & Pkg & ";" & ASCII.LF);

      --  The specification.
      declare
         Head : Unbounded_String;
      begin
         Append (Head, "--  generated by hbnf (binary) -- do not edit" & ASCII.LF);
         Append (Head, "with Ada.Containers.Vectors;" & ASCII.LF);
         Append (Head, "with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;" & ASCII.LF);
         Append (Head, "with Interfaces;" & ASCII.LF & ASCII.LF);
         Append (Head, "package " & Pkg & " is" & ASCII.LF & ASCII.LF);
         Append (Head, "   use Interfaces;" & ASCII.LF & ASCII.LF);
         Append (Head, "   type Byte_Array is array (Natural range <>) of Unsigned_8;" & ASCII.LF);
         Append (Head, "   package Octet_Vectors is new Ada.Containers.Vectors (Natural, Unsigned_8);" & ASCII.LF);
         Append (Head, "   subtype Octets is Octet_Vectors.Vector;" & ASCII.LF & ASCII.LF);
         Append (Head, "   --  Where a read went wrong: the octet, and why." & ASCII.LF);
         Append (Head, "   type Parse_Error is record" & ASCII.LF);
         Append (Head, "      At_Octet : Natural := 0;" & ASCII.LF);
         Append (Head, "      Message  : Unbounded_String;" & ASCII.LF);
         Append (Head, "   end record;" & ASCII.LF & ASCII.LF);
         Spec := Head & Spec;
      end;
      if Words = null then
      SL (1, "--  Read Nbits bits of Buf as one " & Rt & ".  On success all of them were used.");
      SL (1, "procedure Parse_Bits (Buf : Byte_Array; Nbits : Natural;");
      SL (3, "Result : out " & Root_T & "; Ok : out Boolean;");
      SL (3, "Err : out Parse_Error);");
      SL (1, "--  The same, for a message that is whole octets.");
      SL (1, "procedure Parse_Bytes (Buf : Byte_Array; Result : out " & Root_T & ";");
      SL (3, "Ok : out Boolean; Err : out Parse_Error);");
      SL (1, "--  Write V as bits: the bytes (the last one may be partly filled) and the");
      SL (1, "--  number of bits.  A value that does not fit its field, or does not agree");
      SL (1, "--  with a length or tag field, is an error, not a guess; Message says which.");
      SL (1, "procedure Emit_Bits (V : " & Root_T & "; Bytes : out Octets;");
      SL (3, "Nbits : out Natural; Ok : out Boolean;");
      SL (3, "Message : out Unbounded_String);");
      SL (1, "--  The same, for a message that is whole octets.");
      SL (1, "procedure Emit_Bytes (V : " & Root_T & "; Bytes : out Octets;");
      SL (3, "Ok : out Boolean; Message : out Unbounded_String);");
      else
      SL (1, "--  Read the words of Text as the bits of one " & Rt & ".  A mistake in the words");
      SL (1, "--  says which; one in the bits says at which word (""(at unit N)"").");
      SL (1, "procedure Parse_Text (Text : String; Result : out " & Root_T & ";");
      SL (3, "Ok : out Boolean; Err : out Parse_Error);");
      SL (1, "--  Write V as the text of its words: the bits, a word to every");
      SL (1, "--  " & Img (Words.Width) & ", each spelled, with the separator between.");
      SL (1, "procedure Emit_Text (V : " & Root_T & "; Text : out Unbounded_String;");
      SL (3, "Ok : out Boolean; Message : out Unbounded_String);");
      end if;
      if Has_Actions then
         SL (1, "--  The warnings the %actions gave on the last successful read.");
         SL (1, "function Warning_Count return Natural;");
         SL (1, "function Warning (I : Positive) return String;");
      end if;
      SL (0, "");
      SL (0, "end " & Pkg & ";");

      return To_String (Spec) & ASCII.LF & To_String (Bod);
   end Emit;

   procedure Emit_Hosted
     (G : Grammar; Package_Name : String;
      Types, Spec, Withs, Code : out Unbounded_String) is
   begin
      Hosted_Mode := True;
      Last_Spec := Null_Unbounded_String;
      begin
         Code := To_Unbounded_String (Emit (G, Package_Name));
      exception
         when others =>
            Hosted_Mode := False;
            raise;
      end;
      Hosted_Mode := False;
      Types := Last_Types;
      Spec := Last_Spec;
      Withs := Last_Withs;
   end Emit_Hosted;

end HBNF_Wire.Ada_Lang;
