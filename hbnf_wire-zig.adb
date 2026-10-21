pragma Ada_2022;

with Ada.Characters.Handling;
with HBNF_Zig;

package body HBNF_Wire.Zig is

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
      return "0x" & R (K .. 16);
   end Hex;

   Zig_Words : constant array (Positive range <>) of access constant String :=
     [new String'("addrspace"), new String'("align"), new String'("allowzero"),
      new String'("and"), new String'("anyframe"), new String'("anytype"),
      new String'("asm"), new String'("async"), new String'("await"),
      new String'("break"), new String'("callconv"), new String'("catch"),
      new String'("comptime"), new String'("const"), new String'("continue"),
      new String'("defer"), new String'("else"), new String'("enum"),
      new String'("errdefer"), new String'("error"), new String'("export"),
      new String'("extern"), new String'("fn"), new String'("for"),
      new String'("if"), new String'("inline"), new String'("linksection"),
      new String'("noalias"), new String'("noinline"), new String'("nosuspend"),
      new String'("opaque"), new String'("or"), new String'("orelse"),
      new String'("packed"), new String'("pub"), new String'("resume"),
      new String'("return"), new String'("struct"), new String'("suspend"),
      new String'("switch"), new String'("test"), new String'("threadlocal"),
      new String'("try"), new String'("union"), new String'("unreachable"),
      new String'("usingnamespace"), new String'("var"), new String'("volatile"),
      new String'("while"), new String'("bool"), new String'("void"),
      new String'("type"), new String'("anyerror"), new String'("noreturn"),
      new String'("usize"), new String'("isize"), new String'("anyopaque"),
      new String'("null"), new String'("undefined"), new String'("true"),
      new String'("false"), new String'("f16"), new String'("f32"),
      new String'("f64"), new String'("f80"), new String'("f128"),
      new String'("comptime_int"), new String'("comptime_float")];

   --  A name that cannot be a plain identifier: a keyword, a primitive type
   --  (`u8`, `i32`, `u7`).
   function Is_Reserved (S : String) return Boolean is
   begin
      for K of Zig_Words loop
         if K.all = S then
            return True;
         end if;
      end loop;
      if S'Length >= 2 and then S (S'First) in 'u' | 'i' then
         return (for all C of S (S'First + 1 .. S'Last) => C in '0' .. '9');
      end if;
      return False;
   end Is_Reserved;

   function Quote (S : String) return String is
     (if Is_Reserved (S) then "@""" & S & """" else S);

   --  Rule_name or rule-name -> RuleName.
   function Camel (S : String) return String is
      R   : Unbounded_String;
      Up  : Boolean := True;
   begin
      for C of S loop
         if C in '_' | '-' then
            Up := True;
         elsif Up then
            Append (R, Ada.Characters.Handling.To_Upper (C));
            Up := False;
         else
            Append (R, C);
         end if;
      end loop;
      return To_String (R);
   end Camel;

   --  A string for inside a Zig string literal.
   function Escape (S : String) return String is
      R : Unbounded_String;
   begin
      for C of S loop
         if C in '"' | '\' then
            Append (R, '\');
         end if;
         Append (R, C);
      end loop;
      return To_String (R);
   end Escape;

   Hosted_Mode : Boolean := False;       --  Emit_Hosted is running
   Last_Types  : Unbounded_String;       --  the types of the last hosted Emit

   --  The wire reader's and writer's types are P and W; in a hosted file the
   --  text parser has a P, so they are WP and WW there.
   function Rename (S : String) return String is
      R : Unbounded_String;
      I : Natural := S'First;

      function Word_Char (C : Character) return Boolean is
        (C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_');
   begin
      while I <= S'Last loop
         if (S (I) = 'P' or else S (I) = 'W')
           and then (I = S'First or else not Word_Char (S (I - 1)))
           and then (I = S'Last or else not Word_Char (S (I + 1)))
         then
            Append (R, "W" & S (I));
         else
            Append (R, S (I));
         end if;
         I := I + 1;
      end loop;
      return To_String (R);
   end Rename;

   function Emit (G : Grammar) return String is
      Buf  : Unbounded_String;
      Defs : Unbounded_String;     --  the types of choices, as they are met
      Id   : Natural := 0;

      procedure Put (S : String) is
      begin
         Append (Buf, S);
      end Put;

      procedure L (Ind : Natural; S : String) is
      begin
         Append (Buf, [1 .. 4 * Ind => ' ']);
         Append (Buf, S);
         Append (Buf, ASCII.LF);
      end L;

      procedure D (Ind : Natural; S : String) is
      begin
         Append (Defs, [1 .. 4 * Ind => ' ']);
         Append (Defs, S);
         Append (Defs, ASCII.LF);
      end D;

      function Next_Id return Natural is
      begin
         Id := Id + 1;
         return Id;
      end Next_Id;

      Pfx : constant String :=
        (declare
            P : constant String := To_String (G.Prefix);
         begin
            (if P'Length > 0 and then P (P'Last) = '_'
             then Camel (P (P'First .. P'Last - 1)) else Camel (P)));

      function Type_Of (R : String) return String is (Pfx & Camel (R));
      function Parse_Fn_Of (R : String) return String is ("parse_rule_" & R);
      function Emit_Fn_Of (R : String) return String is ("emit_rule_" & R);
      function In_Of (R : String) return String is ("in_value_set_" & R);

      function Int_Type (Bits : Natural; Signed : Boolean) return String is
        ((if Signed then "i" else "u") & Img (Storage_Bits (Bits)));

      ------------------------------------------------------------------------
      --  Names.  A field is a local of the reader or the writer, and Zig does
      --  not let a local hide another, so a field that has the name of one in
      --  reach (a choice's alternative with the name of a field of its rule)
      --  is given another; every name the generated code makes for itself ends
      --  in an underscore, and a field that does too is renamed as well.
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
            if To_String (X) = Ident then
               return True;
            end if;
         end loop;
         return False;
      end In_Use;

      function Def_Field (Field : String) return String is
         Ident : Unbounded_String := To_Unbounded_String (Quote (Field));
      begin
         if In_Use (To_String (Ident)) or else Field (Field'Last) = '_' then
            Ident := To_Unbounded_String (Field & "_" & Img (Next_Id));
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
         return Quote (Field);
      end Lookup;

      ------------------------------------------------------------------------
      --  Types
      ------------------------------------------------------------------------

      procedure Define_Choice (Name : String; Alts : Seq_Vectors.Vector);

      function Named (It : Item) return Boolean is
        (It.Kind not in S_Const | S_Assert and then not It.Bitsof);

      function Field_Type (It : Item; Owner : String) return String is
      begin
         case It.Kind is
            when S_Bits     => return Int_Type (It.Bits, It.Signed);
            when S_Octets | S_Rest => return "[]u8";
            when S_Bit_Expr => return "u64";
            when S_Ref      => return Type_Of (To_String (It.Ref));
            when S_Array    => return "[]" & Type_Of (To_String (It.Ref));
            when S_Choice   =>
               declare
                  N : constant String := Owner & Camel (To_String (It.Name));
               begin
                  Define_Choice (N, It.Alts);
                  return N;
               end;
            when S_Const | S_Assert => return "";
         end case;
      end Field_Type;

      procedure Define_Choice (Name : String; Alts : Seq_Vectors.Vector) is
         K : Natural := 0;
         Variants : Unbounded_String;
      begin
         --  The types the fields need are defined as they are met, so the
         --  union's own text is built before it is written.
         for A of Alts loop
            K := K + 1;
            declare
               V : constant String := "a" & Img (K);
               Fields : Unbounded_String;
            begin
               for It of A.Items loop
                  if Named (It.all) then
                     Append (Fields, Quote (To_String (It.Name)) & ": "
                             & Field_Type (It.all, Name & "A" & Img (K)) & ", ");
                  end if;
               end loop;
               Append (Variants, "    " & V & ": struct { " & To_String (Fields)
                       & "}," & ASCII.LF);
            end;
         end loop;
         D (0, "pub const " & Name & " = union(enum) {");
         Append (Defs, Variants);
         D (0, "};");
         D (0, "");
      end Define_Choice;

      ------------------------------------------------------------------------
      --  Expressions: i64, wrapping, as C's are
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

      Emit_Side : Boolean := False;   --  writing, not reading: no parser, `align` is the writer's
      Words     : Item_Access;

      --  The table of the numbered words of a `bitsof` item, by where it is.
      function Table_Of (It : Item) return String is
        ("BNF_WORDS_" & Img (It.Line) & "_" & Img (It.Col));
      function Sep_Of (It : Item) return String is
        ("BNF_SEP_" & Img (It.Line) & "_" & Img (It.Col));

      function Seq_Has_Bitsof (S : Sequence) return Boolean is
        (for some It of S.Items =>
           It.Bitsof or else (It.Kind = S_Choice
                              and then (for some A of It.Alts =>
                                          Seq_Has_Bitsof (A.all))));
      function Rule_Has_Bitsof (R : Rule) return Boolean is
        (for some A of R.Alts => Seq_Has_Bitsof (A.all));
      Has_Actions : constant Boolean :=
        (for some R of G.Rules => R.Action /= Null_Unbounded_String);
      Walks : constant Name_Vectors.Vector := Walk_Set (G);

      function Expr_Z (E : Expr_Access) return String is
      begin
         case E.Kind is
            when E_Num =>
               return "@as(i64, " & Long_Long_Integer'Image (E.Value) & ")";
            when E_Var =>
               if To_String (E.Name) = "remaining" then
                  return "@as(i64, @intCast(p_.nbits - p_.bit))";
               elsif To_String (E.Name) = "align" then
                  if Hosted_Mode then
                     return (if Emit_Side then "bnf_align(w_.bit, w_.unit)"
                             else "bnf_align(p_.bit, p_.unit)");
                  end if;
                  return "bnf_align(" & (if Emit_Side then "w_.bit" else "p_.bit")
                    & ", BNF_UNIT)";
               end if;
               return "bnf_i(" & Lookup (To_String (E.Name)) & ")";
            when E_Call =>
               return "@as(i64, @intCast(" & Lookup (To_String (E.Arg))
                 & ".len))";
            when E_Unary =>
               declare
                  O  : constant String := To_String (E.Un_Op);
                  A  : constant String := Expr_Z (E.Operand);
               begin
                  if O = "-" then
                     return "(0 -% " & A & ")";
                  elsif O = "~" then
                     return "(~" & A & ")";
                  else
                     return "@as(i64, @intFromBool(" & A & " == 0))";
                  end if;
               end;
            when E_Binary =>
               declare
                  Op : constant String := To_String (E.Bin_Op);
                  A  : constant String := Expr_Z (E.Left);
                  B  : constant String := Expr_Z (E.Right);
               begin
                  if Op = "+" then
                     return "(" & A & " +% " & B & ")";
                  elsif Op = "-" then
                     return "(" & A & " -% " & B & ")";
                  elsif Op = "*" then
                     return "(" & A & " *% " & B & ")";
                  elsif Op = "/" then
                     return "bnf_div(" & A & ", " & B & ")";
                  elsif Op = "%" then
                     return "bnf_rem(" & A & ", " & B & ")";
                  elsif Op = "<<" then
                     return "bnf_shl(" & A & ", " & B & ")";
                  elsif Op = ">>" then
                     return "bnf_shr(" & A & ", " & B & ")";
                  elsif Op in "==" | "!=" | "<" | "<=" | ">" | ">=" then
                     return "@as(i64, @intFromBool(" & A & " " & Op & " "
                       & B & "))";
                  elsif Op = "&&" then
                     return "@as(i64, @intFromBool(" & A & " != 0 and " & B
                       & " != 0))";
                  elsif Op = "||" then
                     return "@as(i64, @intFromBool(" & A & " != 0 or " & B
                       & " != 0))";
                  else
                     return "(" & A & " " & Op & " " & B & ")";
                  end if;
               end;
         end case;
      end Expr_Z;

      function True_Z (E : Expr_Access) return String is
        (Expr_Z (E) & " != 0");

      function Needs_St (S : Sequence) return Boolean is
        (for some It of S.Items =>
           It.Kind = S_Bits and then It.At_Bit >= 0 and then not It.Static_Ok);

      ------------------------------------------------------------------------
      --  Parse code: a local for each field, then the record
      ------------------------------------------------------------------------

      --  `.a = a, .b = b, ` for the fields of a sequence read.
      function Field_Init (S : Sequence) return String is
         R : Unbounded_String;
      begin
         for It of S.Items loop
            if Named (It.all) then
               Append (R, "." & Quote (To_String (It.Name)) & " = "
                       & Lookup (To_String (It.Name)) & ", ");
            end if;
         end loop;
         return To_String (R);
      end Field_Init;

      procedure Gen_Choice
        (Alts : Seq_Vectors.Vector; Enum : String; Where : String;
         Fail : String; Ind : Natural; Blk : String);

      --  Fail is the statement that gives up: `return null`, or a break out of
      --  the alternative being tried.
      procedure Gen_Seq (S : Sequence; Where : String; Owner : String;
                         Fail : String; Ind : Natural)
      is
         Sid : constant String := "st" & Img (Next_Id) & "_";
      begin
         if Needs_St (S) then
            L (Ind, "const " & Sid & " = p_.bit;");
         end if;
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
               U  : constant String := Img (Next_Id) & "_";
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "{");
                     L (Ind + 1, "const s_ = p_.bit;");
                     L (Ind + 1, "const v_ = p_.rd(" & Img (It.Bits) & ", """
                       & Where & """) orelse " & Fail & ";");
                     L (Ind + 1, "if (v_ != " & Hex (It.Value) & ") {");
                     L (Ind + 2, "p_.fail(s_, """ & Where
                       & """, ""expected the constant " & Hex (It.Value)
                       & """);");
                     L (Ind + 2, Fail & ";");
                     L (Ind + 1, "}");
                     L (Ind, "}");
                  when S_Bits =>
                     declare
                        Var : constant Boolean := It.Little or else It.Signed;
                        Id  : constant String := Def_Field (N);
                     begin
                        L (Ind, "const " & Id & ": "
                          & Int_Type (It.Bits, It.Signed) & " = blk" & U
                          & ": {");
                        if It.Ref /= Null_Unbounded_String then
                           L (Ind + 1, "const s_ = p_.bit;");
                        end if;
                        if It.At_Bit >= 0 and then not It.Static_Ok then
                           L (Ind + 1, "if (p_.bit - " & Sid & " != "
                             & Img (It.At_Bit) & ") {");
                           L (Ind + 2, "p_.fail(p_.bit, " & W & ", ""is not "
                             & "at bit " & Img (It.At_Bit) & " of its "
                             & "record"");");
                           L (Ind + 2, Fail & ";");
                           L (Ind + 1, "}");
                        end if;
                        L (Ind + 1, (if Var then "var" else "const")
                          & " v_: u64 = p_.rd(" & Img (It.Bits) & ", " & W
                          & ") orelse " & Fail & ";");
                        if Var then
                           L (Ind + 1, "_ = &v_;");
                        end if;
                        if It.Little then
                           L (Ind + 1, "v_ = bnf_swap(v_, "
                             & Img (It.Bits / 8) & ");");
                        end if;
                        if It.Signed and then It.Bits < 64 then
                           L (Ind + 1, "v_ = @bitCast(@as(i64, @bitCast(v_ << "
                             & Img (64 - It.Bits) & ")) >> "
                             & Img (64 - It.Bits) & ");");
                        end if;
                        if It.Ref /= Null_Unbounded_String then
                           L (Ind + 1, "if (!" & In_Of (To_String (It.Ref))
                             & "(v_)) {");
                           L (Ind + 2, "p_.fail(s_, " & W & ", ""is not one "
                             & "of the values the rule `"
                             & To_String (It.Ref) & "` lists"");");
                           L (Ind + 2, Fail & ";");
                           L (Ind + 1, "}");
                        end if;
                        if It.Signed then
                           L (Ind + 1, "break :blk" & U & " @as("
                             & Int_Type (It.Bits, True)
                             & ", @truncate(@as(i64, @bitCast(v_))));");
                        elsif Storage_Bits (It.Bits) = 64 then
                           L (Ind + 1, "break :blk" & U & " v_;");
                        else
                           L (Ind + 1, "break :blk" & U & " @as("
                             & Int_Type (It.Bits, False) & ", @truncate(v_));");
                        end if;
                        L (Ind, "};");
                     end;
                  when S_Assert =>
                     L (Ind, "if (!(" & True_Z (It.Count) & ")) {");
                     L (Ind + 1, "p_.fail(p_.bit, """ & Where & """, """
                       & (if It.Ref /= Null_Unbounded_String
                          then Escape (To_String (It.Ref))
                          else "a condition does not hold: "
                               & Escape (Expr_Text (It.Count)))
                       & """);");
                     L (Ind + 1, Fail & ";");
                     L (Ind, "}");
                  when S_Octets =>
                     declare
                        Cnt : constant String := Expr_Z (It.Count);
                        Id  : constant String := Def_Field (N);
                     begin
                        L (Ind, "const " & Id & ": []u8 = blk" & U & ": {");
                        L (Ind + 1, "const n_ = " & Cnt & ";");
                        L (Ind + 1, "if (n_ < 0) {");
                        L (Ind + 2, "p_.fail(p_.bit, " & W
                          & ", ""has a negative length"");");
                        L (Ind + 2, Fail & ";");
                        L (Ind + 1, "}");
                        L (Ind + 1, "break :blk" & U & " p_.take(@intCast(n_), "
                          & W & ") orelse " & Fail & ";");
                        L (Ind, "};");
                     end;
                  when S_Rest =>
                     declare
                        Id : constant String := Def_Field (N);
                     begin
                        L (Ind, "const " & Id & ": []u8 = p_.take_rest(" & W
                          & ") orelse " & Fail & ";");
                     end;
                  when S_Bit_Expr =>
                     declare
                        Cnt : constant String := Expr_Z (It.Count);
                        Id  : constant String := Def_Field (N);
                     begin
                        L (Ind, "const " & Id & ": u64 = blk" & U & ": {");
                        L (Ind + 1, "const n_ = " & Cnt & ";");
                        L (Ind + 1, "if (n_ < 0 or n_ > 64) {");
                        L (Ind + 2, "p_.fail(p_.bit, " & W & ", ""has a "
                          & "width outside 0..64 bits"");");
                        L (Ind + 2, Fail & ";");
                        L (Ind + 1, "}");
                        L (Ind + 1, "break :blk" & U & " p_.rd(@intCast(n_), "
                          & W & ") orelse " & Fail & ";");
                        L (Ind, "};");
                     end;
                  when S_Ref =>
                     if It.Bitsof and then Hosted_Mode then
                        --  the text rule is read, its numbered words become the
                        --  bits the rest of the rule reads (bnf_words_end, in the
                        --  wrapper of the rule, puts the input back)
                        declare
                           R : constant String := To_String (It.Ref);
                        begin
                           L (Ind, "{");
                           L (Ind + 1, "if (p_.sv_active) {");
                           L (Ind + 2, "p_.fail(p_.bit, " & W & ", ""a bitsof inside a bitsof"");");
                           L (Ind + 2, Fail & ";");
                           L (Ind + 1, "}");
                           L (Ind + 1, "const start_ = p_.bit / 8;");
                           if (for some X of G.External_Tokens => To_String (X) = R) then
                              L (Ind + 1, "const tx_ = bnf_token(p_, " & HBNF_Zig.Scan_Fn (R)
                                 & ", " & W & ", ""a " & R & """) orelse " & Fail & ";");
                           else
                              --  a rule with structure: the text parser reads it,
                              --  and the text it used is what the words come from
                              L (Ind + 1, "const tx_ = (bnf_sub(p_, " & HBNF_Zig.Parse_Fn (R)
                                 & ", " & W & ", ""a " & R & """) orelse " & Fail & ").span;");
                           end if;
                           L (Ind + 1, "const wb_ = bnf_words(p_, tx_, " & Img (It.Width)
                              & ", &" & Table_Of (It.all) & ") orelse " & Fail & ";");
                           L (Ind + 1, "p_.sv_buf = p_.buf;");
                           L (Ind + 1, "p_.sv_bit = p_.bit;");
                           L (Ind + 1, "p_.sv_nbits = p_.nbits;");
                           L (Ind + 1, "p_.sv_unit = p_.unit;");
                           L (Ind + 1, "p_.sv_start = start_;");
                           L (Ind + 1, "p_.sv_active = true;");
                           L (Ind + 1, "p_.buf = wb_.buf;");
                           L (Ind + 1, "p_.nbits = wb_.nbits;");
                           L (Ind + 1, "p_.bit = 0;");
                           L (Ind + 1, "p_.unit = " & Img (It.Width) & ";");
                           L (Ind, "}");
                        end;
                     elsif not It.Bitsof then   --  the words are already the bits
                        declare
                           Id : constant String := Def_Field (N);
                           R  : constant String := To_String (It.Ref);
                        begin
                           if Hosted_Mode and then Find (G, R) = 0 then
                              --  a character rule of the text: its scanner reads
                              --  it here, from the octet the bits have reached
                              if (for some X of G.External_Tokens => To_String (X) = R) then
                                 L (Ind, "const " & Id & ": " & Type_Of (R)
                                    & " = bnf_token(p_, " & HBNF_Zig.Scan_Fn (R)
                                    & ", " & W & ", ""a " & R & """) orelse "
                                    & Fail & ";");
                              else
                                 --  a rule with structure: the text parser reads it
                                 L (Ind, "const " & Id & ": " & Type_Of (R)
                                    & " = (bnf_sub(p_, " & HBNF_Zig.Parse_Fn (R)
                                    & ", " & W & ", ""a " & R & """) orelse "
                                    & Fail & ").v;");
                              end if;
                           else
                              L (Ind, "const " & Id & ": " & Type_Of (R) & " = "
                                 & Parse_Fn_Of (R) & "(p_) orelse " & Fail & ";");
                           end if;
                        end;
                     end if;
                  when S_Array =>
                     declare
                        R   : constant String := To_String (It.Ref);
                        Cnt : constant String :=
                          (if It.Count /= null then Expr_Z (It.Count) else "");
                        Mn  : constant String :=
                          (if It.Count /= null then "cnt" & U
                           else "@as(i64, " & Img (It.Min) & ")");
                        Mx  : constant String :=
                          (if It.Count /= null then "cnt" & U
                           else "@as(i64, " & Img (It.Max) & ")");
                        Id  : constant String := Def_Field (N);
                     begin
                        L (Ind, "const " & Id & ": []" & Type_Of (R)
                          & " = blk" & U & ": {");
                        L (Ind + 1, "var a_: std.ArrayList(" & Type_Of (R)
                          & ") = .empty;");
                        if It.Count /= null then
                           L (Ind + 1, "const cnt" & U & " = " & Cnt & ";");
                           L (Ind + 1, "if (cnt" & U & " < 0) {");
                           L (Ind + 2, "p_.fail(p_.bit, " & W
                             & ", ""has a negative count"");");
                           L (Ind + 2, Fail & ";");
                           L (Ind + 1, "}");
                        end if;
                        L (Ind + 1, "while (true) {");
                        L (Ind + 2, "const s_ = p_.bit;");
                        L (Ind + 2, "if (" & Mx & " >= 0 and @as(i64, "
                          & "@intCast(a_.items.len)) >= " & Mx & ") break;");
                        L (Ind + 2, "if (@as(i64, @intCast(a_.items.len)) >= "
                          & Mn & " and p_.bit >= p_.nbits) break;");
                        L (Ind + 2, "if (" & Parse_Fn_Of (R) & "(p_)) |t_| {");
                        L (Ind + 3, "if (p_.bit == s_) break;");
                        L (Ind + 3, "a_.append(p_.alloc, t_) catch {");
                        L (Ind + 4, "p_.oom();");
                        L (Ind + 4, Fail & ";");
                        L (Ind + 3, "};");
                        L (Ind + 2, "} else {");
                        L (Ind + 3, "p_.bit = s_;");
                        L (Ind + 3, "if (@as(i64, @intCast(a_.items.len)) < "
                          & Mn & ") " & Fail & ";");
                        L (Ind + 3, "break;");
                        L (Ind + 2, "}");
                        L (Ind + 1, "}");
                        L (Ind + 1, "if (@as(i64, @intCast(a_.items.len)) < "
                          & Mn & ") {");
                        L (Ind + 2, "p_.fail(p_.bit, " & W
                          & ", ""has too few entries"");");
                        L (Ind + 2, Fail & ";");
                        L (Ind + 1, "}");
                        L (Ind + 1, "break :blk" & U & " a_.items;");
                        L (Ind, "};");
                     end;
                  when S_Choice =>
                     declare
                        E  : constant String := Owner & Camel (N);
                        Id : constant String := Def_Field (N);
                     begin
                        L (Ind, "const " & Id & ": " & E & " = blk" & U
                          & ": {");
                        Gen_Choice (It.Alts, E, Where & "." & N, Fail,
                                    Ind + 1, "blk" & U);
                        L (Ind, "};");
                     end;
               end case;
            end;
         end loop;
      end Gen_Seq;

      --  The statements of a block that yields the first alternative that
      --  reads, or gives up when none does (the bits are put back between
      --  tries).
      procedure Gen_Choice
        (Alts : Seq_Vectors.Vector; Enum : String; Where : String;
         Fail : String; Ind : Natural; Blk : String)
      is
         U : constant String := Img (Next_Id) & "_";
         K : Natural := 0;
      begin
         L (Ind, "const c" & U & " = p_.bit;");
         for A of Alts loop
            K := K + 1;
            declare
               Alt : constant String := "alt" & U & Img (K);
               Give : constant String := "break :" & Alt & " null";
               M    : constant Natural := Mark;
            begin
               L (Ind, "const r" & U & Img (K) & ": ?" & Enum & " = " & Alt
                  & ": {");
               if A.Guard /= null then
                  L (Ind + 1, "if (!(" & True_Z (A.Guard) & ")) " & Give
                     & ";");
               end if;
               Gen_Seq (A.all, Where, Enum & "A" & Img (K), Give, Ind + 1);
               L (Ind + 1, "break :" & Alt & " " & Enum & "{ .a" & Img (K)
                  & " = .{ " & Field_Init (A.all) & "} };");
               Pop (M);
               L (Ind, "};");
               L (Ind, "if (r" & U & Img (K) & ") |r_| break :" & Blk
                  & " r_;");
               L (Ind, "p_.bit = c" & U & ";");
            end;
         end loop;
         L (Ind, "p_.fail(p_.bit, """ & Where
           & """, ""none of the alternatives matches here"");");
         L (Ind, Fail & ";");
      end Gen_Choice;

      ------------------------------------------------------------------------
      --  Emit code: a tree back to bytes
      ------------------------------------------------------------------------

      procedure Gen_Emit_Match
        (Alts : Seq_Vectors.Vector; Subject : String; Enum : String;
         Where : String; Ind : Natural);

      --  The fields of a record or an alternative are bound already.
      procedure Gen_Emit_Seq (S : Sequence; Where : String; Owner : String;
                              Ind : Natural)
      is
         Sid : constant String := "st" & Img (Next_Id) & "_";
      begin
         if Needs_St (S) then
            L (Ind, "const " & Sid & " = w_.bit;");
         end if;
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
               Id : constant String :=
                 (if Named (It.all) then Lookup (N) else "");
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "w_.wr(" & Img (It.Bits) & ", " & Hex (It.Value)
                       & ");");
                  when S_Bits =>
                     L (Ind, "{");
                     if It.At_Bit >= 0 and then not It.Static_Ok then
                        L (Ind + 1, "if (w_.bit - " & Sid & " != "
                          & Img (It.At_Bit) & ") {");
                        L (Ind + 2, "w_.fail(" & W & ", ""is not at bit "
                          & Img (It.At_Bit) & " of its record"");");
                        L (Ind + 2, "return false;");
                        L (Ind + 1, "}");
                     end if;
                     if It.Signed then
                        L (Ind + 1, "const sv_: i64 = " & Id & ";");
                        if It.Bits < 64 then
                           L (Ind + 1, "if (sv_ < -(@as(i64, 1) << "
                             & Img (It.Bits - 1) & ") or sv_ >= (@as(i64, 1) << "
                             & Img (It.Bits - 1) & ")) {");
                           L (Ind + 2, "w_.fail(" & W & ", ""does not fit in "
                             & Img (It.Bits) & " bits (signed)"");");
                           L (Ind + 2, "return false;");
                           L (Ind + 1, "}");
                           L (Ind + 1, "var x_: u64 = @as(u64, @bitCast(sv_)) "
                             & "& ((@as(u64, 1) << " & Img (It.Bits)
                             & ") - 1);");
                        else
                           L (Ind + 1, "var x_: u64 = @bitCast(sv_);");
                        end if;
                     else
                        L (Ind + 1, "var x_: u64 = " & Id & ";");
                        if It.Bits < 64 then
                           L (Ind + 1, "if ((x_ >> " & Img (It.Bits)
                             & ") != 0) {");
                           L (Ind + 2, "w_.fail(" & W & ", ""does not fit "
                             & "in " & Img (It.Bits) & " bits"");");
                           L (Ind + 2, "return false;");
                           L (Ind + 1, "}");
                        end if;
                     end if;
                     L (Ind + 1, "_ = &x_;");
                     if It.Ref /= Null_Unbounded_String then
                        L (Ind + 1, "if (!" & In_Of (To_String (It.Ref))
                          & "(x_)) {");
                        L (Ind + 2, "w_.fail(" & W & ", ""is not one of the "
                          & "values the rule `" & To_String (It.Ref)
                          & "` lists"");");
                        L (Ind + 2, "return false;");
                        L (Ind + 1, "}");
                     end if;
                     if It.Little then
                        L (Ind + 1, "x_ = bnf_swap(x_, " & Img (It.Bits / 8)
                          & ");");
                     end if;
                     L (Ind + 1, "w_.wr(" & Img (It.Bits) & ", x_);");
                     L (Ind, "}");
                  when S_Assert =>
                     if not Uses_Remaining (It.Count) then
                        L (Ind, "if (!(" & True_Z (It.Count) & ")) {");
                        L (Ind + 1, "w_.fail(""" & Where & """, """
                          & (if It.Ref /= Null_Unbounded_String
                             then Escape (To_String (It.Ref))
                             else "a condition does not hold: "
                                  & Escape (Expr_Text (It.Count)))
                          & """);");
                        L (Ind + 1, "return false;");
                        L (Ind, "}");
                     end if;
                  when S_Octets =>
                     if not Uses_Remaining (It.Count) then
                        L (Ind, "if (@as(i64, @intCast(" & Id & ".len)) != "
                          & Expr_Z (It.Count) & ") {");
                        L (Ind + 1, "w_.fail(" & W & ", ""has a different "
                          & "number of octets than its length says"");");
                        L (Ind + 1, "return false;");
                        L (Ind, "}");
                     end if;
                     L (Ind, "w_.put(" & Id & ");");
                  when S_Rest =>
                     L (Ind, "w_.put(" & Id & ");");
                  when S_Bit_Expr =>
                     if Uses_Remaining (It.Count) then
                        L (Ind, "_ = " & Id & ";");
                        L (Ind, "w_.fail(" & W & ", ""has a width that "
                          & "depends on the size of the input, which a "
                          & "writer does not know yet"");");
                        L (Ind, "return false;");
                     else
                        L (Ind, "{");
                        L (Ind + 1, "const n_ = " & Expr_Z (It.Count) & ";");
                        L (Ind + 1, "if (n_ < 0 or n_ > 64 or (n_ < 64 and ("
                          & Id & " >> @as(u6, @intCast(n_))) != 0)) {");
                        L (Ind + 2, "w_.fail(" & W & ", ""does not fit in the "
                          & "number of bits its width field says"");");
                        L (Ind + 2, "return false;");
                        L (Ind + 1, "}");
                        L (Ind + 1, "w_.wr(@intCast(n_), " & Id & ");");
                        L (Ind, "}");
                     end if;
                  when S_Ref =>
                     if It.Bitsof and then Hosted_Mode then
                        --  what the rest of the sequence writes is bits that are
                        --  spelled as words once it ends
                        L (Ind, "w_.words_begin(" & Img (It.Width) & ");");
                     elsif not It.Bitsof then
                        if Hosted_Mode and then Find (G, To_String (It.Ref)) = 0
                        then
                           --  a text token held by the record: its octets
                           L (Ind, "w_.put(" & Id & ");");
                        else
                           L (Ind, "if (!" & Emit_Fn_Of (To_String (It.Ref))
                             & "(w_, " & Id & ")) return false;");
                        end if;
                     end if;
                  when S_Array =>
                     if It.Count /= null then
                        L (Ind, "if (@as(i64, @intCast(" & Id & ".len)) != "
                          & Expr_Z (It.Count) & ") {");
                        L (Ind + 1, "w_.fail(" & W & ", ""has a different "
                          & "number of entries than its count says"");");
                        L (Ind + 1, "return false;");
                        L (Ind, "}");
                     else
                        L (Ind, "if (" & Id & ".len < " & Img (It.Min)
                          & (if It.Max >= 0
                             then " or " & Id & ".len > " & Img (It.Max)
                             else "") & ") {");
                        L (Ind + 1, "w_.fail(" & W & ", ""has a number of "
                          & "entries outside " & Img (It.Min) & ".."
                          & (if It.Max >= 0 then Img (It.Max) else "")
                          & """);");
                        L (Ind + 1, "return false;");
                        L (Ind, "}");
                     end if;
                     L (Ind, "for (" & Id & ") |e_| {");
                     L (Ind + 1, "if (!" & Emit_Fn_Of (To_String (It.Ref))
                       & "(w_, e_)) return false;");
                     L (Ind, "}");
                  when S_Choice =>
                     Gen_Emit_Match (It.Alts, Id, Owner & Camel (N),
                                     Where & "." & N, Ind);
               end case;
            end;
         end loop;
         for It of S.Items loop
            if It.Bitsof and then Hosted_Mode then
               L (Ind, "if (!w_.words_end(&" & Table_Of (It.all) & ", "
                  & Sep_Of (It.all) & ")) return false;");
            end if;
         end loop;
      end Gen_Emit_Seq;

      --  Bind the named fields of a sequence from a record `v_`.
      procedure Bind_From_Record (S : Sequence; Src : String; Ind : Natural) is
      begin
         for It of S.Items loop
            if Named (It.all) then
               declare
                  Id : constant String := Def_Field (To_String (It.Name));
               begin
                  L (Ind, "const " & Id & " = " & Src & "."
                    & Quote (To_String (It.Name)) & ";");
               end;
            end if;
         end loop;
      end Bind_From_Record;

      --  A switch on a choice (or on a multi-alternative rule): each arm binds
      --  its fields.
      procedure Gen_Emit_Match
        (Alts : Seq_Vectors.Vector; Subject : String; Enum : String;
         Where : String; Ind : Natural)
      is
         K : Natural := 0;
      begin
         L (Ind, "switch (" & Subject & ") {");
         for A of Alts loop
            K := K + 1;
            declare
               M   : constant Natural := Mark;
               Cap : constant String := "a" & Img (Next_Id) & "_";
               Any : constant Boolean := (for some It of A.Items =>
                                            Named (It.all));
            begin
               L (Ind + 1, ".a" & Img (K) & " => "
                  & (if Any then "|" & Cap & "| " else "") & "{");
               Bind_From_Record (A.all, Cap, Ind + 2);
               if A.Guard /= null and then not Uses_Remaining (A.Guard) then
                  L (Ind + 2, "if (!(" & True_Z (A.Guard) & ")) {");
                  L (Ind + 3, "w_.fail(""" & Where & """, ""alternative "
                     & Img (K) & " is chosen, but its guard does not hold"");");
                  L (Ind + 3, "return false;");
                  L (Ind + 2, "}");
               end if;
               Gen_Emit_Seq (A.all, Where, Enum & "A" & Img (K), Ind + 2);
               Pop (M);
               L (Ind + 1, "},");
            end;
         end loop;
         L (Ind, "}");
      end Gen_Emit_Match;

      --  The walk that runs the actions once a record has been read, children
      --  first.  Base is how the record is reached: `n`, or a name a switch bound.
      procedure Gen_Walk_Seq
        (S : Sequence; Owner : String; Base : String; Ind : Natural)
      is
      begin
         for It of S.Items loop
            declare
               N : constant String := To_String (It.Name);
               U : constant String := Img (Next_Id);
               F : constant String := Base & "." & Quote (N);
            begin
               if Item_Walks (Walks, It.all) then
                  case It.Kind is
                     when S_Ref =>
                        L (Ind, "try walk_" & To_String (It.Ref) & "(&" & F
                           & ", h);");
                     when S_Array =>
                        L (Ind, "for (" & F & ") |*e" & U & "_| try walk_"
                           & To_String (It.Ref) & "(e" & U & "_, h);");
                     when S_Choice =>
                        declare
                           E : constant String := Owner & Camel (N);
                           K : Natural := 0;
                        begin
                           L (Ind, "switch (" & F & ") {");
                           for A of It.Alts loop
                              K := K + 1;
                              if Seq_Walks (Walks, A.all) then
                                 L (Ind + 1, ".a" & Img (K) & " => |x" & U
                                    & "_" & Img (K) & "| {");
                                 Gen_Walk_Seq (A.all, E & "A" & Img (K),
                                               "x" & U & "_" & Img (K), Ind + 2);
                                 L (Ind + 1, "},");
                              end if;
                           end loop;
                           L (Ind + 1, "else => {},");
                           L (Ind, "}");
                        end;
                     when others =>
                        null;
                  end case;
               end if;
            end;
         end loop;
      end Gen_Walk_Seq;

      Root : constant Natural := 1;
      Root_T : constant String := Type_Of (To_String (G.Rules (Root).Name));
      Rt     : constant String := To_String (G.Rules (Root).Name);
      Parse_Fn : constant String := Parse_Fn_Of (Rt);
      Emit_Fn  : constant String := Emit_Fn_Of (Rt);
   begin
      Check_Code_Language (G, "Zig");
      if not Hosted_Mode then
         Words := Words_Item (G, "Zig");
      end if;
      if not Hosted_Mode and then Is_Value_Set (G.Rules (Root)) then
         raise Wire_Error with
           "the first rule, `" & Rt & "`, is a list of constants; the "
           & "parser reads the first rule, which should be the whole message";
      end if;

      if not Hosted_Mode then
         L (0, "// generated by hbnf (binary) -- do not edit");
         L (0, "const std = @import(""std"");");
         L (0, "");
      end if;
      if G.Preamble /= Null_Unbounded_String then
         L (0, "// the grammar's preamble");
         Put (To_String (G.Preamble));
         L (0, "");
      end if;
      if Has_Actions then
         L (0, "var bnf_warning_list: []const []const u8 = &.{};");
         L (0, "");
         L (0, "/// The warnings the `%action`s gave on the last successful read (they live as long");
         L (0, "/// as the allocator that was given to it).");
         L (0, "pub fn hbnf_warnings() []const []const u8 {");
         L (0, "    return bnf_warning_list;");
         L (0, "}");
         L (0, "");
         L (0, "const Hooks = struct {");
         L (0, "    alloc: std.mem.Allocator,");
         L (0, "    warnings: std.ArrayList([]const u8) = .empty,");
         L (0, "    msg: []const u8 = """",");
         L (0, "");
         L (0, "    fn warn(self: *Hooks, m: []const u8) void {");
         L (0, "        self.warnings.append(self.alloc, m) catch {};");
         L (0, "    }");
         L (0, "");
         L (0, "    fn fail(self: *Hooks, m: []const u8) error{HbnfFail} {");
         L (0, "        if (self.msg.len == 0) self.msg = m;");
         L (0, "        return error.HbnfFail;");
         L (0, "    }");
         L (0, "};");
         L (0, "");
      end if;
      if not Hosted_Mode then
         L (0, "/// Where a read went wrong: the octet, and why.");
         L (0, "pub const ParseError = struct {");
         L (0, "    at: usize = 0,");
         L (0, "    message: []const u8 = """",");
         L (0, "};");
         L (0, "");
      end if;
      L (0, "const P = struct {");
      L (0, "    buf: []const u8,");
      L (0, "    nbits: usize,");
      L (0, "    alloc: std.mem.Allocator,");
      L (0, "    bit: usize = 0,");
      L (0, "    fail_bit: usize = 0,");
      L (0, "    failed: bool = false,");
      L (0, "    msg: []const u8 = """",");
      if Hosted_Mode then
         L (0, "    // the bits of a text read as words (name:bitsof(rule)): where the input is");
         L (0, "    // kept while the words are read, and how wide a word is");
         L (0, "    unit: usize = 0,");
         L (0, "    sv_active: bool = false,");
         L (0, "    sv_buf: []const u8 = """",");
         L (0, "    sv_bit: usize = 0,");
         L (0, "    sv_nbits: usize = 0,");
         L (0, "    sv_unit: usize = 0,");
         L (0, "    sv_start: usize = 0,");
         L (0, "    tp: ?*TextP = null,   // the text parser, for a text rule with structure");
      end if;
      L (0, "");
      L (0, "    // Keep the deepest failure, the first told.");
      L (0, "    fn fail(self: *P, bit_: usize, wh: []const u8, what: []const u8) void {");
      if Hosted_Mode then
         L (0, "        var bit = bit_;");
         L (0, "        var how: []const u8 = what;");
         L (0, "        if (self.sv_active) {");
         L (0, "            // reading the bits of a text: say which word, and where the text was");
         L (0, "            how = std.fmt.allocPrint(self.alloc, ""{s} (at unit {d})"", .{ what, bit_ / (if (self.unit != 0) self.unit else 1) + 1 }) catch what;");
         L (0, "            bit = self.sv_start * 8;");
         L (0, "        }");
      else
         L (0, "        const bit = bit_;");
         L (0, "        const how = what;");
      end if;
      L (0, "        if (self.failed and bit <= self.fail_bit) return;");
      L (0, "        self.failed = true;");
      L (0, "        self.fail_bit = bit;");
      L (0, "        self.msg = std.fmt.allocPrint(self.alloc, ""{s}: {s}"", .{ wh, how }) catch ""out of memory"";");
      L (0, "    }");
      L (0, "");
      L (0, "    fn oom(self: *P) void {");
      L (0, "        self.failed = true;");
      L (0, "        self.fail_bit = self.bit;");
      L (0, "        self.msg = ""out of memory"";");
      L (0, "    }");
      L (0, "");
      L (0, "    // n bits (at most 64), the first in the most significant place.");
      L (0, "    fn rd(self: *P, n: u32, wh: []const u8) ?u64 {");
      L (0, "        const left = self.nbits - self.bit;");
      L (0, "        if (n > left) {");
      L (0, "            const t = std.fmt.allocPrint(self.alloc, ""needs {d} bits, {d} left"", .{ n, left }) catch ""needs more bits"";");
      L (0, "            self.fail(self.bit, wh, t);");
      L (0, "            return null;");
      L (0, "        }");
      L (0, "        var x: u64 = 0;");
      L (0, "        var got: u32 = 0;");
      L (0, "        while (got < n) {");
      L (0, "            const byte = self.bit >> 3;");
      L (0, "            const off: u32 = @intCast(self.bit & 7);");
      L (0, "            var tk: u32 = 8 - off;");
      L (0, "            if (tk > n - got) tk = n - got;");
      L (0, "            const chunk: u64 = (@as(u64, self.buf[byte]) >> @intCast(8 - off - tk)) & ((@as(u64, 1) << @intCast(tk)) - 1);");
      L (0, "            x = (x << @intCast(tk)) | chunk;");
      L (0, "            self.bit += tk;");
      L (0, "            got += tk;");
      L (0, "        }");
      L (0, "        return x;");
      L (0, "    }");
      L (0, "");
      L (0, "    // n octets, copied, starting wherever the bits are.");
      L (0, "    fn take(self: *P, n: usize, wh: []const u8) ?[]u8 {");
      L (0, "        if (n > (self.nbits - self.bit) / 8) {");
      L (0, "            const t = std.fmt.allocPrint(self.alloc, ""needs {d} octets, {d} bits left"", .{ n, self.nbits - self.bit }) catch ""needs more octets"";");
      L (0, "            self.fail(self.bit, wh, t);");
      L (0, "            return null;");
      L (0, "        }");
      L (0, "        const v = self.alloc.alloc(u8, n) catch {");
      L (0, "            self.oom();");
      L (0, "            return null;");
      L (0, "        };");
      L (0, "        if (self.bit & 7 == 0) {");
      L (0, "            const s = self.bit / 8;");
      L (0, "            @memcpy(v, self.buf[s .. s + n]);");
      L (0, "            self.bit += n * 8;");
      L (0, "            return v;");
      L (0, "        }");
      L (0, "        for (v) |*b| b.* = @intCast(self.rd(8, wh) orelse return null);");
      L (0, "        return v;");
      L (0, "    }");
      L (0, "");
      L (0, "    fn take_rest(self: *P, wh: []const u8) ?[]u8 {");
      L (0, "        return self.take((self.nbits - self.bit) / 8, wh);");
      L (0, "    }");
      L (0, "};");
      L (0, "");
      L (0, "const W = struct {");
      L (0, "    alloc: std.mem.Allocator,");
      L (0, "    buf: std.ArrayList(u8) = .empty,");
      L (0, "    bit: usize = 0,");
      L (0, "    failed: bool = false,");
      L (0, "    msg: []const u8 = """",");
      if Hosted_Mode then
         L (0, "    // the bits of words (name:bitsof(rule)) being written: the output so far");
         L (0, "    unit: usize = 0,");
         L (0, "    sv_buf: std.ArrayList(u8) = .empty,");
         L (0, "    sv_bit: usize = 0,");
      end if;
      L (0, "");
      L (0, "    fn fail(self: *W, wh: []const u8, what: []const u8) void {");
      L (0, "        if (self.failed) return;");
      L (0, "        self.failed = true;");
      L (0, "        self.msg = std.fmt.allocPrint(self.alloc, ""{s}: {s}"", .{ wh, what }) catch ""out of memory"";");
      L (0, "    }");
      L (0, "");
      L (0, "    // In an %emit block: `return w_.emit_fail(""text"");` fails the write.");
      L (0, "    fn emit_fail(self: *W, what: []const u8) bool {");
      L (0, "        self.fail(""emit"", what);");
      L (0, "        return false;");
      L (0, "    }");
      L (0, "");
      L (0, "    fn wr(self: *W, n: u32, v: u64) void {");
      L (0, "        var done: u32 = 0;");
      L (0, "        while (done < n) {");
      L (0, "            const byte = self.bit >> 3;");
      L (0, "            const off: u32 = @intCast(self.bit & 7);");
      L (0, "            var tk: u32 = 8 - off;");
      L (0, "            if (tk > n - done) tk = n - done;");
      L (0, "            const chunk: u8 = @intCast((v >> @intCast(n - done - tk)) & ((@as(u64, 1) << @intCast(tk)) - 1));");
      L (0, "            if (byte >= self.buf.items.len) {");
      L (0, "                self.buf.append(self.alloc, 0) catch {");
      L (0, "                    self.fail("""", ""out of memory"");");
      L (0, "                    return;");
      L (0, "                };");
      L (0, "            }");
      L (0, "            self.buf.items[byte] |= chunk << @intCast(8 - off - tk);");
      L (0, "            self.bit += tk;");
      L (0, "            done += tk;");
      L (0, "        }");
      L (0, "    }");
      L (0, "");
      if Hosted_Mode then
         L (0, "    // From here the bits written are a word's each, spelled by words_end.");
         L (0, "    fn words_begin(self: *W, width: usize) void {");
         L (0, "        self.sv_buf = self.buf;");
         L (0, "        self.sv_bit = self.bit;");
         L (0, "        self.buf = .empty;");
         L (0, "        self.bit = 0;");
         L (0, "        self.unit = width;");
         L (0, "    }");
         L (0, "");
         L (0, "    // The bits written since words_begin, as the words that spell them, with sep");
         L (0, "    // between two, written to what was the output.");
         L (0, "    fn words_end(self: *W, tab: []const BnfWord, sep: []const u8) bool {");
         L (0, "        const total = self.bit;");
         L (0, "        const width = self.unit;");
         L (0, "        const bits = self.buf;");
         L (0, "        self.buf = self.sv_buf;");
         L (0, "        self.bit = self.sv_bit;");
         L (0, "        self.unit = 0;");
         L (0, "        if (width == 0 or total % width != 0) {");
         L (0, "            const t = std.fmt.allocPrint(self.alloc, ""{d} bits is not a whole number of {d}-bit units"", .{ total, width }) catch ""not a whole number of units"";");
         L (0, "            self.fail(""the words"", t);");
         L (0, "            return false;");
         L (0, "        }");
         L (0, "        var i: usize = 0;");
         L (0, "        while (i < total / width) : (i += 1) {");
         L (0, "            var v: u64 = 0;");
         L (0, "            for (0..width) |b| {");
         L (0, "                const bit = i * width + b;");
         L (0, "                v = (v << 1) | ((bits.items[bit >> 3] >> @intCast(7 - (bit & 7))) & 1);");
         L (0, "            }");
         L (0, "            var found: ?[]const u8 = null;");
         L (0, "            for (tab) |w| {");
         L (0, "                if (w.v == v) {");
         L (0, "                    found = w.s;");
         L (0, "                    break;");
         L (0, "                }");
         L (0, "            }");
         L (0, "            const s = found orelse {");
         L (0, "                const t = std.fmt.allocPrint(self.alloc, ""unit {d} has the value {d}, which no word spells"", .{ i, v }) catch ""a unit no word spells"";");
         L (0, "                self.fail(""the words"", t);");
         L (0, "                return false;");
         L (0, "            };");
         L (0, "            if (i > 0 and sep.len > 0) self.put(sep);");
         L (0, "            self.put(s);");
         L (0, "        }");
         L (0, "        return true;");
         L (0, "    }");
         L (0, "");
      end if;
      L (0, "    fn put(self: *W, p: []const u8) void {");
      L (0, "        if (self.bit & 7 == 0) {");
      L (0, "            self.buf.appendSlice(self.alloc, p) catch {");
      L (0, "                self.fail("""", ""out of memory"");");
      L (0, "                return;");
      L (0, "            };");
      L (0, "            self.bit += p.len * 8;");
      L (0, "        } else {");
      L (0, "            for (p) |b| self.wr(8, b);");
      L (0, "        }");
      L (0, "    }");
      L (0, "};");
      L (0, "");
      L (0, "fn bnf_i(x: anytype) i64 {");
      L (0, "    const T = @TypeOf(x);");
      L (0, "    if (@typeInfo(T).int.signedness == .signed) return @as(i64, x);");
      L (0, "    return @bitCast(@as(u64, x));");
      L (0, "}");
      L (0, "// the bits to the next boundary of a word; 0 when the grammar has no words");
      L (0, "fn bnf_align(bit: usize, unit: usize) i64 {");
      L (0, "    if (unit == 0) return 0;");
      L (0, "    return @intCast((unit - bit % unit) % unit);");
      L (0, "}");
      L (0, "const BNF_UNIT: usize = " & (if Words = null then "0" else Img (Words.Width)) & ";");
      if Hosted_Mode then
         L (0, "// A character rule of the text (a token) read where the bits are: its scanner");
         L (0, "// runs on the octets from here, on a shifted copy if they start inside a byte.");
         L (0, "fn bnf_token(p_: *P, comptime scan: anytype, wh: []const u8, what: []const u8) ?[]const u8 {");
         L (0, "    var text: []const u8 = p_.buf;");
         L (0, "    var pos: usize = p_.bit / 8;");
         L (0, "    if (p_.bit % 8 != 0) {");
         L (0, "        const off: u3 = @intCast(p_.bit % 8);");
         L (0, "        const m = (p_.nbits - p_.bit) / 8;");
         L (0, "        const c = p_.alloc.alloc(u8, m) catch {");
         L (0, "            p_.oom();");
         L (0, "            return null;");
         L (0, "        };");
         L (0, "        const t = p_.buf[p_.bit / 8 ..];");
         L (0, "        for (c, 0..) |*o, i| o.* = (t[i] << off) | (t[i + 1] >> @intCast(8 - @as(u4, off)));");
         L (0, "        text = c;");
         L (0, "        pos = 0;");
         L (0, "    }");
         L (0, "    const n = scan(text, pos, text.len);");
         L (0, "    if (n == 0) {");
         L (0, "        p_.fail(p_.bit, wh, what);");
         L (0, "        return null;");
         L (0, "    }");
         L (0, "    p_.bit += n * 8;");
         L (0, "    return text[pos .. pos + n];");
         L (0, "}");
         L (0, "");
         L (0, "fn BnfSub(comptime T: type) type {");
         L (0, "    return struct { v: T, span: []const u8 };");
         L (0, "}");
         L (0, "fn BnfPayload(comptime parse: anytype) type {");
         L (0, "    return @typeInfo(@typeInfo(@TypeOf(parse)).@""fn"".return_type.?).error_union.payload;");
         L (0, "}");
         L (0, "");
         L (0, "// A text rule with structure, read by the text parser where the bits are (on a shifted");
         L (0, "// copy of the octets if they start inside a byte): its value, and the text it used.");
         L (0, "fn bnf_sub(p_: *P, comptime parse: anytype, wh: []const u8, comptime what: []const u8) ?BnfSub(BnfPayload(parse)) {");
         L (0, "    const tp = p_.tp orelse {");
         L (0, "        p_.fail(p_.bit, wh, ""no text parser for "" ++ what);");
         L (0, "        return null;");
         L (0, "    };");
         L (0, "    const save_text = tp.text;");
         L (0, "    const save_pos = tp.pos;");
         L (0, "    var text: []const u8 = p_.buf;");
         L (0, "    var start: usize = p_.bit / 8;");
         L (0, "    if (p_.bit % 8 != 0) {");
         L (0, "        const off: u3 = @intCast(p_.bit % 8);");
         L (0, "        const m = (p_.nbits - p_.bit) / 8;");
         L (0, "        const c = p_.alloc.alloc(u8, m) catch {");
         L (0, "            p_.oom();");
         L (0, "            return null;");
         L (0, "        };");
         L (0, "        const t = p_.buf[p_.bit / 8 ..];");
         L (0, "        for (c, 0..) |*o, i| o.* = (t[i] << off) | (t[i + 1] >> @intCast(8 - @as(u4, off)));");
         L (0, "        text = c;");
         L (0, "        start = 0;");
         L (0, "    }");
         L (0, "    // what the text parser noted while it succeeded (a list looking for one more) is not");
         L (0, "    // an error of the whole read");
         L (0, "    const save_err = tp.err;");
         L (0, "    const save_len = tp.err_len;");
         L (0, "    const save_epos = tp.err_pos;");
         L (0, "    const save_line = tp.err_line;");
         L (0, "    const save_col = tp.err_col;");
         L (0, "    tp.text = text;");
         L (0, "    tp.pos = start;");
         L (0, "    const v = parse(tp) catch {");
         L (0, "        tp.text = save_text;");
         L (0, "        tp.pos = save_pos;");
         L (0, "        p_.fail(p_.bit, wh, what);");
         L (0, "        return null;");
         L (0, "    };");
         L (0, "    const end = tp.pos;");
         L (0, "    tp.text = save_text;");
         L (0, "    tp.pos = save_pos;");
         L (0, "    tp.err = save_err;");
         L (0, "    tp.err_len = save_len;");
         L (0, "    tp.err_pos = save_epos;");
         L (0, "    tp.err_line = save_line;");
         L (0, "    tp.err_col = save_col;");
         L (0, "    p_.bit += (end - start) * 8;");
         L (0, "    return .{ .v = v, .span = text[start..end] };");
         L (0, "}");
         L (0, "");
         L (0, "const BnfWord = struct { s: []const u8, v: u64 };");
         L (0, "const BnfBits = struct { buf: []u8, nbits: usize };");
         L (0, "");
         L (0, "// `name:bitsof(rule)`: the numbered words of the text the rule just read, as bits,");
         L (0, "// width to a word.  A word is looked for at each place (the longest of those that fit);");
         L (0, "// what is between two words is skipped.");
         L (0, "fn bnf_words(p_: *P, text: []const u8, width: usize, tab: []const BnfWord) ?BnfBits {");
         L (0, "    var vals: std.ArrayList(u64) = .empty;");
         L (0, "    var pos: usize = 0;");
         L (0, "    while (pos < text.len) {");
         L (0, "        var hit_n: usize = 0;");
         L (0, "        var hit_v: u64 = 0;");
         L (0, "        for (tab) |w| {");
         L (0, "            if (w.s.len > hit_n and std.mem.startsWith(u8, text[pos..], w.s)) {");
         L (0, "                hit_n = w.s.len;");
         L (0, "                hit_v = w.v;");
         L (0, "            }");
         L (0, "        }");
         L (0, "        if (hit_n > 0) {");
         L (0, "            vals.append(p_.alloc, hit_v) catch {");
         L (0, "                p_.oom();");
         L (0, "                return null;");
         L (0, "            };");
         L (0, "            pos += hit_n;");
         L (0, "        } else {");
         L (0, "            pos += 1;");
         L (0, "        }");
         L (0, "    }");
         L (0, "    const nbits = vals.items.len * width;");
         L (0, "    const buf = p_.alloc.alloc(u8, (nbits + 7) / 8 + 1) catch {");
         L (0, "        p_.oom();");
         L (0, "        return null;");
         L (0, "    };");
         L (0, "    @memset(buf, 0);");
         L (0, "    for (vals.items, 0..) |v, k| {");
         L (0, "        for (0..width) |i| {");
         L (0, "            const b = k * width + i;");
         L (0, "            if ((v >> @intCast(width - 1 - i)) & 1 == 1) buf[b >> 3] |= @as(u8, 0x80) >> @intCast(b & 7);");
         L (0, "        }");
         L (0, "    }");
         L (0, "    return BnfBits{ .buf = buf, .nbits = nbits };");
         L (0, "}");
         L (0, "");
         L (0, "// The end of a rule that read bits from words: all of them must have been used, and");
         L (0, "// the text is the input again.");
         L (0, "fn bnf_words_end(p_: *P, ok: bool) bool {");
         L (0, "    if (!p_.sv_active) return ok;");
         L (0, "    var good = ok;");
         L (0, "    if (ok and p_.bit != p_.nbits) {");
         L (0, "        const t = std.fmt.allocPrint(p_.alloc, ""{d} bit(s) left over"", .{p_.nbits - p_.bit}) catch ""bits left over"";");
         L (0, "        p_.fail(p_.bit, ""the words"", t);");
         L (0, "        good = false;");
         L (0, "    }");
         L (0, "    p_.buf = p_.sv_buf;");
         L (0, "    p_.nbits = p_.sv_nbits;");
         L (0, "    p_.bit = p_.sv_bit;");
         L (0, "    p_.unit = p_.sv_unit;");
         L (0, "    p_.sv_active = false;");
         L (0, "    return good;");
         L (0, "}");
      end if;
      L (0, "fn bnf_swap(v: u64, nbytes: u32) u64 {");
      L (0, "    var r: u64 = 0;");
      L (0, "    var x = v;");
      L (0, "    var k: u32 = 0;");
      L (0, "    while (k < nbytes) : (k += 1) {");
      L (0, "        r = (r << 8) | (x & 0xFF);");
      L (0, "        x >>= 8;");
      L (0, "    }");
      L (0, "    return r;");
      L (0, "}");
      L (0, "fn bnf_div(a: i64, b: i64) i64 {");
      L (0, "    if (b == 0) return 0;");
      L (0, "    if (b == -1) return 0 -% a;");
      L (0, "    return @divTrunc(a, b);");
      L (0, "}");
      L (0, "fn bnf_rem(a: i64, b: i64) i64 {");
      L (0, "    if (b == 0 or b == -1) return 0;");
      L (0, "    return @rem(a, b);");
      L (0, "}");
      L (0, "fn bnf_shl(a: i64, b: i64) i64 {");
      L (0, "    return @bitCast(@as(u64, @bitCast(a)) << @as(u6, @intCast(b & 63)));");
      L (0, "}");
      L (0, "fn bnf_shr(a: i64, b: i64) i64 {");
      L (0, "    return @bitCast(@as(u64, @bitCast(a)) >> @as(u6, @intCast(b & 63)));");
      L (0, "}");

      --  The types.
      for R of G.Rules loop
         if not Is_Value_Set (R) then
            declare
               Nm : constant String := Type_Of (To_String (R.Name));
            begin
               if Natural (R.Alts.Length) = 1 then
                  declare
                     Fields : Unbounded_String;
                  begin
                     for It of R.Alts.First_Element.Items loop
                        if Named (It.all) then
                           Append (Fields, "    " & Quote (To_String (It.Name))
                                   & ": " & Field_Type (It.all, Nm) & ","
                                   & ASCII.LF);
                        end if;
                     end loop;
                     D (0, "pub const " & Nm & " = struct {");
                     Append (Defs, Fields);
                     D (0, "};");
                     D (0, "");
                  end;
               else
                  Define_Choice (Nm, R.Alts);
               end if;
            end;
         end if;
      end loop;
      L (0, "");
      if Hosted_Mode then
         Last_Types := Defs;
      else
         Put (To_String (Defs));
      end if;

      --  Value sets.
      for R of G.Rules loop
         if Is_Value_Set (R) then
            declare
               First : Boolean := True;
               T     : Unbounded_String;
            begin
               for A of R.Alts loop
                  if not First then
                     Append (T, ", ");
                  end if;
                  First := False;
                  Append (T, Hex (A.Items.First_Element.Value));
               end loop;
               L (0, "fn " & In_Of (To_String (R.Name)) & "(v: u64) bool {");
               L (1, "return switch (v) {");
               L (2, To_String (T) & " => true,");
               L (2, "else => false,");
               L (1, "};");
               L (0, "}");
               L (0, "");
            end;
         end if;
      end loop;

      --  The numbered words of each `bitsof`, and what stands between two.
      if Hosted_Mode then
         declare
            procedure Tables (Alts : Seq_Vectors.Vector) is
            begin
               for A of Alts loop
                  for It of A.Items loop
                     if It.Bitsof then
                        L (0, "const " & Table_Of (It.all) & " = [_]BnfWord{");
                        for U of It.Words loop
                           L (1, ".{ .s = """ & Escape (To_String (U.Spelling))
                              & """, .v = " & Img (U.Value) & " },");
                        end loop;
                        L (0, "};");
                        L (0, "const " & Sep_Of (It.all) & " = """
                           & Escape (To_String (It.Sep)) & """;");
                        L (0, "");
                     elsif It.Kind = S_Choice then
                        Tables (It.Alts);
                     end if;
                  end loop;
               end loop;
            end Tables;
         begin
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
               T  : constant String := Type_Of (Nm);
               M  : constant Natural := Mark;
               Wrap : constant Boolean := Hosted_Mode and then Rule_Has_Bitsof (R);
            begin
               L (0, "fn " & Parse_Fn_Of (Nm) & (if Wrap then "_body" else "")
                  & "(p_: *P) ?" & T & " {");
               L (1, "_ = &p_;");
               if Natural (R.Alts.Length) = 1 then
                  Gen_Seq (R.Alts.First_Element.all, Nm, T, "return null", 1);
                  L (1, "return " & T & "{ "
                     & Field_Init (R.Alts.First_Element.all) & "};");
               else
                  declare
                     U : constant String := Img (Next_Id) & "_";
                  begin
                     L (1, "const r_: " & T & " = blk" & U & ": {");
                     Gen_Choice (R.Alts, T, Nm, "return null", 2, "blk" & U);
                     L (1, "};");
                     L (1, "return r_;");
                  end;
               end if;
               L (0, "}");
               L (0, "");
               if Wrap then
                  L (0, "fn " & Parse_Fn_Of (Nm) & "(p_: *P) ?" & T & " {");
                  L (1, "const r = " & Parse_Fn_Of (Nm) & "_body(p_);");
                  L (1, "if (!bnf_words_end(p_, r != null)) return null;");
                  L (1, "return r;");
                  L (0, "}");
                  L (0, "");
               end if;
               Pop (M);
               L (0, "fn " & Emit_Fn_Of (Nm) & "(w_: *W, v_: " & T & ") bool {");
               Emit_Side := True;
               L (1, "_ = &w_;");
               L (1, "_ = &v_;");
               if R.Emit /= Null_Unbounded_String then
                  --  %emit runs on a copy of the record, before its fields are
                  --  written
                  L (1, "var n = v_;");
                  L (1, "_ = &n;");
                  L (1, "{");
                  Put (To_String (R.Emit));
                  L (0, "");
                  L (1, "}");
               end if;
               if Natural (R.Alts.Length) = 1 then
                  Bind_From_Record (R.Alts.First_Element.all,
                                    (if R.Emit /= Null_Unbounded_String then "n" else "v_"), 1);
                  Gen_Emit_Seq (R.Alts.First_Element.all, Nm, T, 1);
               else
                  Gen_Emit_Match (R.Alts, (if R.Emit /= Null_Unbounded_String then "n" else "v_"), T, Nm, 1);
               end if;
               Pop (M);
               Emit_Side := False;
               L (1, "return true;");
               L (0, "}");
               L (0, "");
            end;
         end if;
      end loop;

      if Has_Actions then
         for R of G.Rules loop
            if not Is_Value_Set (R) and then In_Walk (Walks, To_String (R.Name))
            then
               declare
                  Nm : constant String := To_String (R.Name);
                  T  : constant String := Type_Of (Nm);
               begin
                  if R.Action /= Null_Unbounded_String then
                     L (0, "fn action_" & Nm & "(n: *const " & T
                        & ", h: *Hooks) error{HbnfFail}!void {");
                     L (1, "_ = &n;");
                     L (1, "_ = &h;");
                     L (1, "{");
                     Put (To_String (R.Action));
                     L (0, "");
                     L (1, "}");
                     L (0, "}");
                     L (0, "");
                  end if;
                  L (0, "fn walk_" & Nm & "(n: *const " & T
                     & ", h: *Hooks) error{HbnfFail}!void {");
                  L (1, "_ = &n;");
                  L (1, "_ = &h;");
                  if Natural (R.Alts.Length) = 1 then
                     Gen_Walk_Seq (R.Alts.First_Element.all, T, "n", 1);
                  else
                     declare
                        K : Natural := 0;
                     begin
                        L (1, "switch (n.*) {");
                        for A of R.Alts loop
                           K := K + 1;
                           if Seq_Walks (Walks, A.all) then
                              L (2, ".a" & Img (K) & " => |x" & Img (K) & "_| {");
                              Gen_Walk_Seq (A.all, T & "A" & Img (K),
                                            "x" & Img (K) & "_", 3);
                              L (2, "},");
                           end if;
                        end loop;
                        L (2, "else => {},");
                        L (1, "}");
                     end;
                  end if;
                  if R.Action /= Null_Unbounded_String then
                     L (1, "try action_" & Nm & "(n, h);");
                  end if;
                  L (0, "}");
                  L (0, "");
               end;
            end if;
         end loop;
         L (0, "// Run the actions on a record that has been read; the warnings are kept.");
         L (0, "fn bnf_check(alloc: std.mem.Allocator, v: *const " & Root_T & ", msg: *[]const u8) bool {");
         L (0, "    var h = Hooks{ .alloc = alloc };");
         L (0, "    walk_" & Rt & "(v, &h) catch {");
         L (0, "        msg.* = h.msg;");
         L (0, "        return false;");
         L (0, "    };");
         L (0, "    bnf_warning_list = h.warnings.items;");
         L (0, "    return true;");
         L (0, "}");
         L (0, "");
      end if;

      if Hosted_Mode then
         L (0, "");
         L (0, "pub const Emitted = struct { bytes: []u8, nbits: usize };");
         for R of G.Rules loop
            if not Is_Value_Set (R) then
               declare
                  Nm : constant String := To_String (R.Name);
                  T  : constant String := Type_Of (Nm);
               begin
                  L (0, "");
                  L (0, "/// The bits of one " & Nm & ", written (its %emit first).");
                  L (0, "pub fn emit_bits_" & Nm
                     & "(alloc: std.mem.Allocator, v: " & T
                     & ", msg: *[]const u8) error{Emit}!Emitted {");
                  L (0, "    var w_ = W{ .alloc = alloc };");
                  L (0, "    if (!" & Emit_Fn_Of (Nm) & "(&w_, v) or w_.failed) {");
                  L (0, "        msg.* = w_.msg;");
                  L (0, "        return error.Emit;");
                  L (0, "    }");
                  L (0, "    return Emitted{ .bytes = w_.buf.items, .nbits = w_.bit };");
                  L (0, "}");
               end;
            end if;
         end loop;
      elsif Words = null then
      L (0, "");
      L (0, "fn read(alloc: std.mem.Allocator, buf: []const u8, nbits: usize, err: *ParseError) error{Parse}!" & Root_T & " {");
      L (0, "    var p_ = P{ .buf = buf, .nbits = nbits, .alloc = alloc };");
      L (0, "    const v = " & Parse_Fn & "(&p_) orelse {");
      L (0, "        err.at = p_.fail_bit / 8;");
      L (0, "        err.message = std.fmt.allocPrint(alloc, ""octet {d}: {s}"", .{ p_.fail_bit / 8, p_.msg }) catch p_.msg;");
      L (0, "        return error.Parse;");
      L (0, "    };");
      L (0, "    if (p_.bit != nbits) {");
      L (0, "        p_.failed = false;");
      L (0, "        const t = std.fmt.allocPrint(alloc, ""{d} bit(s) left over after the message"", .{nbits - p_.bit}) catch ""bits left over after the message"";");
      L (0, "        p_.fail(p_.bit, """ & Rt & """, t);");
      L (0, "        err.at = p_.fail_bit / 8;");
      L (0, "        err.message = std.fmt.allocPrint(alloc, ""octet {d}: {s}"", .{ p_.fail_bit / 8, p_.msg }) catch p_.msg;");
      L (0, "        return error.Parse;");
      L (0, "    }");
      if Has_Actions then
         L (0, "    var m_: []const u8 = """";");
         L (0, "    if (!bnf_check(alloc, &v, &m_)) {");
         L (0, "        p_.failed = false;");
         L (0, "        p_.fail(p_.bit, """ & Rt & """, m_);");
         L (0, "        err.at = p_.fail_bit / 8;");
         L (0, "        err.message = std.fmt.allocPrint(alloc, ""octet {d}: {s}"", .{ p_.fail_bit / 8, p_.msg }) catch p_.msg;");
         L (0, "        return error.Parse;");
         L (0, "    }");
      end if;
      L (0, "    return v;");
      L (0, "}");
      L (0, "");
      L (0, "/// Read nbits bits of buf as one " & Rt & ".  On success all of them were used.");
      L (0, "pub fn parse_bits(alloc: std.mem.Allocator, buf: []const u8, nbits: usize, err: *ParseError) error{Parse}!" & Root_T & " {");
      L (0, "    return read(alloc, buf, nbits, err);");
      L (0, "}");
      L (0, "");
      L (0, "/// The same, for a message that is whole octets.");
      L (0, "pub fn parse_bytes(alloc: std.mem.Allocator, buf: []const u8, err: *ParseError) error{Parse}!" & Root_T & " {");
      L (0, "    return read(alloc, buf, buf.len * 8, err);");
      L (0, "}");
      L (0, "");
      L (0, "pub const Emitted = struct { bytes: []u8, nbits: usize };");
      L (0, "");
      L (0, "/// Write v as bits: the bytes (the last one may be partly filled) and the");
      L (0, "/// number of bits.  A value that does not fit its field, or does not agree with");
      L (0, "/// a length or tag field, is an error, not a guess; msg says which.");
      L (0, "pub fn emit_bits(alloc: std.mem.Allocator, v: " & Root_T & ", msg: *[]const u8) error{Emit}!Emitted {");
      L (0, "    var w_ = W{ .alloc = alloc };");
      L (0, "    if (!" & Emit_Fn & "(&w_, v) or w_.failed) {");
      L (0, "        msg.* = w_.msg;");
      L (0, "        return error.Emit;");
      L (0, "    }");
      L (0, "    return Emitted{ .bytes = w_.buf.items, .nbits = w_.bit };");
      L (0, "}");
      L (0, "");
      L (0, "/// The same, for a message that is whole octets.");
      L (0, "pub fn emit_bytes(alloc: std.mem.Allocator, v: " & Root_T & ", msg: *[]const u8) error{Emit}![]u8 {");
      L (0, "    const e = try emit_bits(alloc, v, msg);");
      L (0, "    if (e.nbits & 7 != 0) {");
      L (0, "        msg.* = """ & Rt & ": the message does not end on an octet boundary"";");
      L (0, "        return error.Emit;");
      L (0, "    }");
      L (0, "    return e.bytes;");
      L (0, "}");

      else
      declare
         Wd : constant String := Img (Words.Width);
         Tab : Unbounded_String;
         Order : Unit_Vectors.Vector := Words.Words;
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
         for U of Order loop
            Append (Tab, "    .{ .s = """ & Escape (To_String (U.Spelling))
                    & """, .v = " & Img (U.Value) & " },");
            Append (Tab, ASCII.LF);
         end loop;
         L (0, "");
         L (0, "const BNF_WIDTH: usize = " & Wd & ";");
         L (0, "const BNF_SEP = """ & Escape (To_String (Words.Sep)) & """;");
         L (0, "const BnfWord = struct { s: []const u8, v: u64 };");
         L (0, "// the spellings of the words and their numbers, a longer one before a shorter");
         L (0, "// one it starts with");
         L (0, "const BNF_WORDS = [_]BnfWord{");
         Put (To_String (Tab));
         L (0, "};");
         L (0, "");
         L (0, "// up to 24 characters of the text from `from`");
         L (0, "fn bnf_found(text: []const u8, from: usize) []const u8 {");
         L (0, "    if (from >= text.len) return ""end of input"";");
         L (0, "    var end = from;");
         L (0, "    var chars: usize = 0;");
         L (0, "    while (end < text.len) : (end += 1) {");
         L (0, "        if (text[end] & 0xC0 != 0x80) {");
         L (0, "            if (chars == 24) break;");
         L (0, "            chars += 1;");
         L (0, "        }");
         L (0, "    }");
         L (0, "    return text[from..end];");
         L (0, "}");
         L (0, "");
         L (0, "const BnfBits = struct { buf: []u8, nbits: usize };");
         L (0, "");
         L (0, "// The text as the bits of its words: BNF_WIDTH bits each, the first word first.");
         L (0, "fn bnf_words(alloc: std.mem.Allocator, text: []const u8, err: *ParseError) error{Parse}!BnfBits {");
         L (0, "    var vals: std.ArrayList(u64) = .empty;");
         L (0, "    var pos: usize = 0;");
         if Words.Words_Empty then
            L (0, "    if (text.len == 0) return BnfBits{ .buf = &.{}, .nbits = 0 };");
         end if;
         L (0, "    while (true) {");
         L (0, "        const rest = text[pos..];");
         L (0, "        var hit_n: usize = 0;");
         L (0, "        var hit_v: u64 = 0;");
         L (0, "        var hit = false;");
         L (0, "        for (BNF_WORDS) |w| {");
         L (0, "            if (std.mem.startsWith(u8, rest, w.s) and (!hit or w.s.len > hit_n)) {");
         L (0, "                hit = true;");
         L (0, "                hit_n = w.s.len;");
         L (0, "                hit_v = w.v;");
         L (0, "            }");
         L (0, "        }");
         L (0, "        if (!hit) {");
         L (0, "            err.at = pos;");
         L (0, "            err.message = std.fmt.allocPrint(alloc, ""expected a " & Escape (To_String (Words.Word_Rule)) & ", found {s}"", .{bnf_found(text, pos)}) catch ""out of memory"";");
         L (0, "            return error.Parse;");
         L (0, "        }");
         L (0, "        vals.append(alloc, hit_v) catch {");
         L (0, "            err.message = ""out of memory"";");
         L (0, "            return error.Parse;");
         L (0, "        };");
         L (0, "        pos += hit_n;");
         L (0, "        if (pos >= text.len) break;");
         L (0, "        if (BNF_SEP.len > 0) {");
         L (0, "            if (!std.mem.startsWith(u8, text[pos..], BNF_SEP)) {");
         L (0, "                err.at = pos;");
         L (0, "                err.message = std.fmt.allocPrint(alloc, ""expected `{s}`, found {s}"", .{ BNF_SEP, bnf_found(text, pos) }) catch ""out of memory"";");
         L (0, "                return error.Parse;");
         L (0, "            }");
         L (0, "            pos += BNF_SEP.len;");
         L (0, "        }");
         L (0, "    }");
         L (0, "    const nbits = vals.items.len * BNF_WIDTH;");
         L (0, "    const buf = alloc.alloc(u8, (nbits + 7) / 8) catch {");
         L (0, "        err.message = ""out of memory"";");
         L (0, "        return error.Parse;");
         L (0, "    };");
         L (0, "    @memset(buf, 0);");
         L (0, "    for (vals.items, 0..) |v, k| {");
         L (0, "        for (0..BNF_WIDTH) |i| {");
         L (0, "            const b = k * BNF_WIDTH + i;");
         L (0, "            if ((v >> @intCast(BNF_WIDTH - 1 - i)) & 1 == 1) buf[b >> 3] |= @as(u8, 0x80) >> @intCast(b & 7);");
         L (0, "        }");
         L (0, "    }");
         L (0, "    return BnfBits{ .buf = buf, .nbits = nbits };");
         L (0, "}");
         L (0, "");
         L (0, "fn bnf_at_unit(alloc: std.mem.Allocator, text: []const u8, m: []const u8, fail_bit: usize, err: *ParseError) void {");
         L (0, "    err.at = 0;");
         L (0, "    err.message = std.fmt.allocPrint(alloc, ""expected {s} (at unit {d}), found {s}"", .{ m, fail_bit / BNF_WIDTH + 1, bnf_found(text, 0) }) catch m;");
         L (0, "}");
         L (0, "");
         L (0, "/// Read the words of text as the bits of one " & Rt & ".  A mistake in the words");
         L (0, "/// says which; one in the bits says at which word (`(at unit N)`).");
         L (0, "pub fn parse_text(alloc: std.mem.Allocator, text: []const u8, err: *ParseError) error{Parse}!" & Root_T & " {");
         L (0, "    const w = try bnf_words(alloc, text, err);");
         L (0, "    var p_ = P{ .buf = w.buf, .nbits = w.nbits, .alloc = alloc };");
         L (0, "    const v = " & Parse_Fn & "(&p_) orelse {");
         L (0, "        bnf_at_unit(alloc, text, p_.msg, p_.fail_bit, err);");
         L (0, "        return error.Parse;");
         L (0, "    };");
         L (0, "    if (p_.bit != w.nbits) {");
         L (0, "        const m = std.fmt.allocPrint(alloc, ""the words: {d} bit(s) left over"", .{w.nbits - p_.bit}) catch ""the words: bits left over"";");
         L (0, "        bnf_at_unit(alloc, text, m, p_.bit, err);");
         L (0, "        return error.Parse;");
         L (0, "    }");
         if Has_Actions then
            L (0, "    var m_: []const u8 = """";");
            L (0, "    if (!bnf_check(alloc, &v, &m_)) {");
            L (0, "        err.at = 0;");
            L (0, "        err.message = m_;");
            L (0, "        return error.Parse;");
            L (0, "    }");
         end if;
         L (0, "    return v;");
         L (0, "}");
         L (0, "");
         L (0, "/// Write v as the text of its words: the bits, BNF_WIDTH to a word, each spelled,");
         L (0, "/// with the separator between.");
         L (0, "pub fn emit_text(alloc: std.mem.Allocator, v: " & Root_T & ", msg: *[]const u8) error{Emit}![]u8 {");
         L (0, "    var w_ = W{ .alloc = alloc };");
         L (0, "    if (!" & Emit_Fn & "(&w_, v) or w_.failed) {");
         L (0, "        msg.* = w_.msg;");
         L (0, "        return error.Emit;");
         L (0, "    }");
         L (0, "    if (w_.bit % BNF_WIDTH != 0) {");
         L (0, "        msg.* = std.fmt.allocPrint(alloc, ""the words: {d} bits is not a whole number of {d}-bit units"", .{ w_.bit, BNF_WIDTH }) catch ""the words: not a whole number of units"";");
         L (0, "        return error.Emit;");
         L (0, "    }");
         L (0, "    var out: std.ArrayList(u8) = .empty;");
         L (0, "    var k: usize = 0;");
         L (0, "    while (k < w_.bit / BNF_WIDTH) : (k += 1) {");
         L (0, "        var x: u64 = 0;");
         L (0, "        for (0..BNF_WIDTH) |i| {");
         L (0, "            const b = k * BNF_WIDTH + i;");
         L (0, "            x = (x << 1) | ((w_.buf.items[b >> 3] >> @intCast(7 - (b & 7))) & 1);");
         L (0, "        }");
         L (0, "        var spelled: ?[]const u8 = null;");
         L (0, "        for (BNF_WORDS) |w| {");
         L (0, "            if (w.v == x) {");
         L (0, "                spelled = w.s;");
         L (0, "                break;");
         L (0, "            }");
         L (0, "        }");
         L (0, "        const s = spelled orelse {");
         L (0, "            msg.* = std.fmt.allocPrint(alloc, ""the words: unit {d} has the value {d}, which no word spells"", .{ k, x }) catch ""the words: a unit no word spells"";");
         L (0, "            return error.Emit;");
         L (0, "        };");
         L (0, "        if (k > 0) out.appendSlice(alloc, BNF_SEP) catch {");
         L (0, "            msg.* = ""out of memory"";");
         L (0, "            return error.Emit;");
         L (0, "        };");
         L (0, "        out.appendSlice(alloc, s) catch {");
         L (0, "            msg.* = ""out of memory"";");
         L (0, "            return error.Emit;");
         L (0, "        };");
         L (0, "    }");
         L (0, "    return out.items;");
         L (0, "}");
      end;
      end if;

      if G.Epilogue /= Null_Unbounded_String then
         L (0, "");
         L (0, "// the grammar's epilogue");
         Put (To_String (G.Epilogue));
         L (0, "");
      end if;

      if Hosted_Mode then
         declare
            Text : Unbounded_String := To_Unbounded_String (Rename (To_String (Buf)));
         begin
            --  what the text parser calls: a bit rule read as a text rule is
            Append (Text, ASCII.LF & "const TextP = P;" & ASCII.LF);
            for R of G.Rules loop
               if not Is_Value_Set (R) then
                  declare
                     Nm : constant String := To_String (R.Name);
                  begin
                     Append (Text, ASCII.LF);
                     Append (Text, "fn " & HBNF_Zig.Parse_Fn (Nm)
                       & "(p: *P) ParseError!" & Type_Of (Nm) & " {" & ASCII.LF);
                     Append (Text, "    var w = WP{ .buf = p.text, .nbits = p.text.len * 8, "
                       & ".alloc = p.alloc, .bit = p.pos * 8 + p.bit, .tp = p };" & ASCII.LF);
                     Append (Text, "    const v = " & Parse_Fn_Of (Nm)
                       & "(&w) orelse {" & ASCII.LF);
                     Append (Text, "        p.pos = w.fail_bit / 8;" & ASCII.LF);
                     Append (Text, "        p.set_err(w.msg);" & ASCII.LF);
                     Append (Text, "        return error.Invalid;" & ASCII.LF);
                     Append (Text, "    };" & ASCII.LF);
                     Append (Text, "    p.pos = w.bit / 8;" & ASCII.LF);
                     Append (Text, "    p.bit = @intCast(w.bit % 8);" & ASCII.LF);
                     Append (Text, "    return v;" & ASCII.LF);
                     Append (Text, "}" & ASCII.LF);
                  end;
               end if;
            end loop;
            return To_String (Text);
         end;
      end if;
      return To_String (Buf);
   end Emit;

   procedure Emit_Hosted (G : Grammar; Types, Code : out Unbounded_String) is
   begin
      Hosted_Mode := True;
      begin
         Code := To_Unbounded_String (Emit (G));
      exception
         when others =>
            Hosted_Mode := False;
            raise;
      end;
      Hosted_Mode := False;
      Types := Last_Types;
   end Emit_Hosted;

end HBNF_Wire.Zig;
