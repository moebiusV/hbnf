pragma Ada_2022;

with Ada.Characters.Handling;
with HBNF_Rust;
with Ada.Containers.Vectors;

package body HBNF_Wire.Rust is

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
      return "0x" & R (K .. 16) & "u64";
   end Hex;

   Rust_Keywords : constant array (Positive range <>) of access constant String :=
     [new String'("as"), new String'("break"), new String'("const"),
      new String'("continue"), new String'("crate"), new String'("else"),
      new String'("enum"), new String'("extern"), new String'("false"),
      new String'("fn"), new String'("for"), new String'("if"),
      new String'("impl"), new String'("in"), new String'("let"),
      new String'("loop"), new String'("match"), new String'("mod"),
      new String'("move"), new String'("mut"), new String'("pub"),
      new String'("ref"), new String'("return"), new String'("self"),
      new String'("Self"), new String'("static"), new String'("struct"),
      new String'("super"), new String'("trait"), new String'("true"),
      new String'("type"), new String'("unsafe"), new String'("use"),
      new String'("where"), new String'("while"), new String'("async"),
      new String'("await"), new String'("dyn"), new String'("abstract"),
      new String'("become"), new String'("box"), new String'("do"),
      new String'("final"), new String'("macro"), new String'("override"),
      new String'("priv"), new String'("typeof"), new String'("unsized"),
      new String'("virtual"), new String'("yield"), new String'("try"),
      new String'("p_"), new String'("w_"), new String'("v_"),
      new String'("s_"), new String'("n_"), new String'("c_"),
      new String'("x_"), new String'("a_"), new String'("t_"),
      new String'("e_"), new String'("r_"), new String'("st_"),
      new String'("sv_"), new String'("cnt_"), new String'("h_")];

   function Is_Keyword (S : String) return Boolean is
   begin
      for K of Rust_Keywords loop
         if K.all = S then
            return True;
         end if;
      end loop;
      return False;
   end Is_Keyword;

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

   --  A string for inside a Rust string literal.
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

   --  The reader's and the writer's types are P and W; in a hosted file the
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

      function Type_Of (R : String) return String is
        (if Hosted_Mode and then Find (G, R) = 0 then HBNF_Rust.Type_Name (R)
         else Pfx & Camel (R));
      function Parse_Fn_Of (R : String) return String is ("parse_rule_" & R);
      function Emit_Fn_Of (R : String) return String is ("emit_rule_" & R);
      function In_Of (R : String) return String is ("in_value_set_" & R);

      function Int_Type (Bits : Natural; Signed : Boolean) return String is
        ((if Signed then "i" else "u") & Img (Storage_Bits (Bits)));

      procedure Check_Name (It : Item) is
      begin
         if Is_Keyword (To_String (It.Name)) then
            raise Wire_Error with
              Img (It.Line) & ":" & Img (It.Col) & ": the field `"
              & To_String (It.Name) & "` is a Rust keyword, or a name the "
              & "generated code keeps for itself, so it cannot be a field; "
              & "rename it (`" & To_String (It.Name) & "_x` or a name from "
              & "the RFC's own text)";
         end if;
      end Check_Name;

      ------------------------------------------------------------------------
      --  Types
      ------------------------------------------------------------------------

      --  The enum for a choice, named Name, one variant for each alternative.
      procedure Define_Choice (Name : String; Alts : Seq_Vectors.Vector);

      function Field_Type (It : Item; Owner : String) return String is
      begin
         case It.Kind is
            when S_Bits     => return Int_Type (It.Bits, It.Signed);
            when S_Octets | S_Rest => return "Vec<u8>";
            when S_Bit_Expr => return "u64";
            when S_Ref      => return Type_Of (To_String (It.Ref));
            when S_Array    => return "Vec<" & Type_Of (To_String (It.Ref)) & ">";
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

      function Named (It : Item) return Boolean is
        (It.Kind not in S_Const | S_Assert and then not It.Bitsof);

      procedure Define_Choice (Name : String; Alts : Seq_Vectors.Vector) is
         K : Natural := 0;
         Variants : Unbounded_String;
      begin
         --  The types the fields need come first (Field_Type defines them
         --  as it meets them), so the enum's own text is built before it is
         --  written.
         for A of Alts loop
            K := K + 1;
            declare
               V : constant String := "A" & Img (K);
               Fields : Unbounded_String;
            begin
               for It of A.Items loop
                  if Named (It.all) then
                     Check_Name (It.all);
                     Append (Fields, To_String (It.Name) & ": "
                             & Field_Type (It.all, Name & V) & ", ");
                  end if;
               end loop;
               Append (Variants, "    " & V & " { " & To_String (Fields)
                       & "}," & ASCII.LF);
            end;
         end loop;
         D (0, "#[derive(Debug, Clone, PartialEq)]");
         D (0, "pub enum " & Name & " {");
         Append (Defs, Variants);
         D (0, "}");
         if Hosted_Mode then
            --  a text rule that holds it starts from `Default`
            declare
               First_Fields : Unbounded_String;
            begin
               for It of Alts.First_Element.Items loop
                  if Named (It.all) then
                     Append (First_Fields, To_String (It.Name)
                             & ": Default::default(), ");
                  end if;
               end loop;
               D (0, "impl Default for " & Name & " {");
               D (1, "fn default() -> Self {");
               D (2, Name & "::A1 { " & To_String (First_Fields) & "}");
               D (1, "}");
               D (0, "}");
            end;
         end if;
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

      Emit_Side : Boolean := False;

      function Expr_R (E : Expr_Access) return String is
      begin
         case E.Kind is
            when E_Num =>
               return "(" & Long_Long_Integer'Image (E.Value) & "i64)";
            when E_Var =>
               if To_String (E.Name) = "remaining" then
                  return "((p_.nbits - p_.bit) as i64)";
               elsif To_String (E.Name) = "align" then
                  return "bnf_align(" & (if Emit_Side then "w_.bit" else "p_.bit")
                    & ", " & (if Hosted_Mode
                               then (if Emit_Side then "w_.unit" else "p_.unit")
                               else "BNF_UNIT") & ")";
               end if;
               return "(" & To_String (E.Name) & " as i64)";
            when E_Call =>
               return "(" & To_String (E.Arg) & ".len() as i64)";
            when E_Unary =>
               declare
                  O  : constant String := To_String (E.Un_Op);
                  A  : constant String := Expr_R (E.Operand);
               begin
                  if O = "-" then
                     return "(" & A & ").wrapping_neg()";
                  elsif O = "~" then
                     return "(!" & A & ")";
                  else
                     return "((" & A & " == 0) as i64)";
                  end if;
               end;
            when E_Binary =>
               declare
                  Op : constant String := To_String (E.Bin_Op);
                  A  : constant String := Expr_R (E.Left);
                  B  : constant String := Expr_R (E.Right);
               begin
                  if Op = "+" then
                     return "(" & A & ").wrapping_add(" & B & ")";
                  elsif Op = "-" then
                     return "(" & A & ").wrapping_sub(" & B & ")";
                  elsif Op = "*" then
                     return "(" & A & ").wrapping_mul(" & B & ")";
                  elsif Op = "/" then
                     return "bnf_div(" & A & ", " & B & ")";
                  elsif Op = "%" then
                     return "bnf_rem(" & A & ", " & B & ")";
                  elsif Op = "<<" then
                     return "bnf_shl(" & A & ", " & B & ")";
                  elsif Op = ">>" then
                     return "bnf_shr(" & A & ", " & B & ")";
                  elsif Op in "==" | "!=" | "<" | "<=" | ">" | ">=" then
                     return "((" & A & " " & Op & " " & B & ") as i64)";
                  elsif Op = "&&" then
                     return "((" & A & " != 0 && " & B & " != 0) as i64)";
                  elsif Op = "||" then
                     return "((" & A & " != 0 || " & B & " != 0) as i64)";
                  else
                     return "(" & A & " " & Op & " " & B & ")";
                  end if;
               end;
         end case;
      end Expr_R;

      function True_R (E : Expr_Access) return String is
        (Expr_R (E) & " != 0");

      ------------------------------------------------------------------------
      --  Parse code: a local for each field, then the record
      ------------------------------------------------------------------------

      function Field_List (S : Sequence) return String is
         R : Unbounded_String;
      begin
         for It of S.Items loop
            if Named (It.all) then
               Append (R, To_String (It.Name) & ", ");
            end if;
         end loop;
         return To_String (R);
      end Field_List;

      procedure Gen_Choice
        (Alts : Seq_Vectors.Vector; Enum : String; Where : String;
         Ind : Natural);

      --  A text rule read where the bits are, into `let N`; with Span, the
      --  value is (value, the octets it used).
      procedure Gen_Text_Ref (Ind : Natural; N, R, W : String; Span : Boolean) is
         Ty : constant String :=
           (if Span then "(" & Type_Of (R) & ", Vec<u8>)" else Type_Of (R));
      begin
                  if (for some X of G.External_Tokens =>
                                    To_String (X) = R)
                              then
                                 --  a character rule of the text: its scanner
                                 --  reads it here, from the octet the bits have
                                 --  reached
                                 L (Ind, "let " & N & ": " & Ty & " = {");
                                 L (Ind + 1, "let shifted_;");
                                 L (Ind + 1, "let (b_, start_): (&[u8], usize) = if p_.bit % 8 == 0 {");
                                 L (Ind + 2, "(&p_.buf[..], p_.bit / 8)");
                                 L (Ind + 1, "} else {");
                                 L (Ind + 2, "shifted_ = bnf_shifted(p_);");
                                 L (Ind + 2, "(&shifted_[..], 0)");
                                 L (Ind + 1, "};");
                                 L (Ind + 1, "let n_ = " & HBNF_Rust.Scan_Fn (R) & "(b_, start_, b_.len());");
                                 L (Ind + 1, "if n_ == 0 { p_.fail(p_.bit, " & W & ", ""a " & R & """); return None; }");
                                 L (Ind + 1, "p_.bit += n_ * 8;");
                                 L (Ind + 1, (if Span then "(bnf_lossy(&b_[start_..start_ + n_]), b_[start_..start_ + n_].to_vec())" else "bnf_lossy(&b_[start_..start_ + n_])"));
                                 L (Ind, "};");
                              else
                                 --  a rule with structure: the text parser reads
                                 --  it, on a shifted copy if the octets start
                                 --  inside a byte
                                 L (Ind, "let " & N & ": " & Ty & " = {");
                                 L (Ind + 1, "let shifted_;");
                                 L (Ind + 1, "let (b_, start_): (&[u8], usize) = if p_.bit % 8 == 0 {");
                                 L (Ind + 2, "(&p_.buf[..], p_.bit / 8)");
                                 L (Ind + 1, "} else {");
                                 L (Ind + 2, "shifted_ = bnf_shifted(p_);");
                                 L (Ind + 2, "(&shifted_[..], 0)");
                                 L (Ind + 1, "};");
                                 L (Ind + 1, "let mut tp_ = TextP { text: Txt(b_), pos: start_, bit: 0, err_pos: 0, err: None };");
                                 L (Ind + 1, "match " & HBNF_Rust.Parse_Fn (R) & "(&mut tp_) {");
                                 L (Ind + 2, "Ok(v_) => { p_.bit += (tp_.pos - start_) * 8; " & (if Span then "(v_, b_[start_..tp_.pos].to_vec())" else "v_") & " }");
                                 L (Ind + 2, "Err(_) => { p_.fail(p_.bit, " & W & ", ""a " & R & """); return None; }");
                                 L (Ind + 1, "}");
                                 L (Ind, "};");
                              end if;
      end Gen_Text_Ref;

      procedure Gen_Seq (S : Sequence; Where : String; Owner : String;
                         Ind : Natural)
      is
      begin
         L (Ind, "let st_ = p_.bit;");
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "{ let s_ = p_.bit; let v_ = p_.rd("
                       & Img (It.Bits) & ", """ & Where & """)?;");
                     L (Ind + 1, "if v_ != " & Hex (It.Value) & " {");
                     L (Ind + 2, "p_.fail(s_, """ & Where
                       & """, ""expected the constant " & Hex (It.Value)
                       & """); return None;");
                     L (Ind + 1, "}");
                     L (Ind, "}");
                  when S_Bits =>
                     L (Ind, "let " & N & ": " & Int_Type (It.Bits, It.Signed)
                       & " = {");
                     L (Ind + 1, "let s_ = p_.bit;");
                     if It.At_Bit >= 0 and then not It.Static_Ok then
                        L (Ind + 1, "if p_.bit - st_ != " & Img (It.At_Bit)
                          & " { p_.fail(p_.bit, " & W & ", ""is not at bit "
                          & Img (It.At_Bit) & " of its record""); "
                          & "return None; }");
                     end if;
                     L (Ind + 1, "let mut v_ = p_.rd(" & Img (It.Bits) & ", "
                       & W & ")?;");
                     if It.Little then
                        L (Ind + 1, "v_ = bnf_swap(v_, " & Img (It.Bits / 8)
                          & ");");
                     end if;
                     if It.Signed and then It.Bits < 64 then
                        L (Ind + 1, "v_ = ((((v_ << " & Img (64 - It.Bits)
                          & ") as i64) >> " & Img (64 - It.Bits) & ") as u64);");
                     end if;
                     if It.Ref /= Null_Unbounded_String then
                        L (Ind + 1, "if !" & In_Of (To_String (It.Ref))
                          & "(v_) { p_.fail(s_, " & W & ", ""is not one of "
                          & "the values the rule `" & To_String (It.Ref)
                          & "` lists""); return None; }");
                     end if;
                     L (Ind + 1, "v_ as " & Int_Type (It.Bits, It.Signed));
                     L (Ind, "};");
                  when S_Assert =>
                     L (Ind, "if !(" & True_R (It.Count) & ") {");
                     L (Ind + 1, "p_.fail(p_.bit, """ & Where & """, """
                       & (if It.Ref /= Null_Unbounded_String
                          then Escape (To_String (It.Ref))
                          else "a condition does not hold: "
                               & Escape (Expr_Text (It.Count)))
                       & """); return None;");
                     L (Ind, "}");
                  when S_Octets =>
                     L (Ind, "let " & N & ": Vec<u8> = {");
                     L (Ind + 1, "let n_ = " & Expr_R (It.Count) & ";");
                     L (Ind + 1, "if n_ < 0 { p_.fail(p_.bit, " & W
                       & ", ""has a negative length""); return None; }");
                     L (Ind + 1, "p_.take(n_ as usize, " & W & ")?");
                     L (Ind, "};");
                  when S_Rest =>
                     L (Ind, "let " & N & ": Vec<u8> = p_.take_rest(" & W
                       & ")?;");
                  when S_Bit_Expr =>
                     L (Ind, "let " & N & ": u64 = {");
                     L (Ind + 1, "let n_ = " & Expr_R (It.Count) & ";");
                     L (Ind + 1, "if n_ < 0 || n_ > 64 { p_.fail(p_.bit, " & W
                       & ", ""has a width outside 0..64 bits""); "
                       & "return None; }");
                     L (Ind + 1, "p_.rd(n_ as u32, " & W & ")?");
                     L (Ind, "};");
                  when S_Ref =>
                     if not It.Bitsof then   --  the words are already the bits
                        declare
                           R : constant String := To_String (It.Ref);
                        begin
                           if Hosted_Mode and then Find (G, R) = 0 then
                              Gen_Text_Ref (Ind, N, R, W, False);
                           else
                              L (Ind, "let " & N & ": " & Type_Of (R)
                                & " = " & Parse_Fn_Of (R) & "(p_)?;");
                           end if;
                        end;
                     elsif Hosted_Mode then
                        --  the text rule is read, its numbered words become the
                        --  bits the rest of the rule reads (the rule's wrapper
                        --  puts the input back)
                        L (Ind, "if p_.sv_active { p_.fail(p_.bit, " & W
                           & ", ""a bitsof inside a bitsof""); return None; }");
                        L (Ind, "let bstart_ = p_.bit / 8;");
                        Gen_Text_Ref (Ind, "tx_" & Img (It.Line) & "_" & Img (It.Col), To_String (It.Ref), W, True);
                        L (Ind, "p_.words_begin(&tx_" & Img (It.Line) & "_" & Img (It.Col) & ".1, " & Img (It.Width)
                           & ", &" & Table_Of (It.all) & ", bstart_);");
                     end if;
                  when S_Array =>
                     declare
                        R   : constant String := To_String (It.Ref);
                        Mn  : constant String :=
                          (if It.Count /= null then "cnt_"
                           else Img (It.Min) & "i64");
                        Mx  : constant String :=
                          (if It.Count /= null then "cnt_"
                           else Img (It.Max) & "i64");
                     begin
                        L (Ind, "let " & N & ": Vec<" & Type_Of (R) & "> = {");
                        L (Ind + 1, "let mut a_: Vec<" & Type_Of (R)
                          & "> = Vec::new();");
                        if It.Count /= null then
                           L (Ind + 1, "let cnt_ = " & Expr_R (It.Count) & ";");
                           L (Ind + 1, "if cnt_ < 0 { p_.fail(p_.bit, " & W
                             & ", ""has a negative count""); return None; }");
                        end if;
                        L (Ind + 1, "loop {");
                        L (Ind + 2, "let s_ = p_.bit;");
                        L (Ind + 2, "if " & Mx & " >= 0 && a_.len() as i64 >= "
                          & Mx & " { break; }");
                        L (Ind + 2, "if a_.len() as i64 >= " & Mn
                          & " && p_.bit >= p_.nbits { break; }");
                        L (Ind + 2, "match " & Parse_Fn_Of (R) & "(p_) {");
                        L (Ind + 3, "None => {");
                        L (Ind + 4, "p_.bit = s_;");
                        L (Ind + 4, "if (a_.len() as i64) < " & Mn
                          & " { return None; }");
                        L (Ind + 4, "break;");
                        L (Ind + 3, "}");
                        L (Ind + 3, "Some(t_) => {");
                        L (Ind + 4, "if p_.bit == s_ { break; }");
                        L (Ind + 4, "a_.push(t_);");
                        L (Ind + 3, "}");
                        L (Ind + 2, "}");
                        L (Ind + 1, "}");
                        L (Ind + 1, "if (a_.len() as i64) < " & Mn
                          & " { p_.fail(p_.bit, " & W
                          & ", ""has too few entries""); return None; }");
                        L (Ind + 1, "a_");
                        L (Ind, "};");
                     end;
                  when S_Choice =>
                     declare
                        E : constant String := Owner & Camel (N);
                     begin
                        L (Ind, "let " & N & ": " & E & " = {");
                        Gen_Choice (It.Alts, E, Where & "." & N, Ind + 1);
                        L (Ind, "};");
                     end;
               end case;
            end;
         end loop;
      end Gen_Seq;

      --  The value of a block: the first alternative that reads, or a return
      --  of None when none does (the bits are put back between tries).
      procedure Gen_Choice
        (Alts : Seq_Vectors.Vector; Enum : String; Where : String;
         Ind : Natural)
      is
         D_Id : constant String := Img (Next_Id);
         K    : Natural := 0;
      begin
         L (Ind, "'c" & D_Id & ": {");
         L (Ind + 1, "let c_ = p_.bit;");
         for A of Alts loop
            K := K + 1;
            L (Ind + 1, "if let Some(r_) = (|| -> Option<" & Enum & "> {");
            if A.Guard /= null then
               L (Ind + 2, "if !(" & True_R (A.Guard) & ") { return None; }");
            end if;
            Gen_Seq (A.all, Where, Enum & "A" & Img (K), Ind + 2);
            L (Ind + 2, "Some(" & Enum & "::A" & Img (K) & " { "
               & Field_List (A.all) & "})");
            L (Ind + 1, "})() { break 'c" & D_Id & " r_; }");
            L (Ind + 1, "p_.bit = c_;");
         end loop;
         L (Ind + 1, "p_.fail(p_.bit, """ & Where
           & """, ""none of the alternatives matches here""); return None;");
         L (Ind, "}");
      end Gen_Choice;

      ------------------------------------------------------------------------
      --  Emit code: a tree back to bytes
      ------------------------------------------------------------------------

      procedure Gen_Emit_Match
        (Alts : Seq_Vectors.Vector; Subject : String; Enum : String;
         Where : String; Ind : Natural);

      --  The fields of a record or an alternative are bound already: numbers
      --  by value, the rest by reference.
      procedure Gen_Emit_Seq (S : Sequence; Where : String; Owner : String;
                              Ind : Natural)
      is
      begin
         L (Ind, "let st_ = w_.bit;");
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "w_.wr(" & Img (It.Bits) & ", " & Hex (It.Value)
                       & ");");
                  when S_Bits =>
                     L (Ind, "{");
                     if It.At_Bit >= 0 and then not It.Static_Ok then
                        L (Ind + 1, "if w_.bit - st_ != " & Img (It.At_Bit)
                          & " { w_.fail(" & W & ", ""is not at bit "
                          & Img (It.At_Bit) & " of its record""); "
                          & "return false; }");
                     end if;
                     if It.Signed then
                        L (Ind + 1, "let sv_ = " & N & " as i64;");
                        if It.Bits < 64 then
                           L (Ind + 1, "if sv_ < -(1i64 << "
                             & Img (It.Bits - 1) & ") || sv_ >= (1i64 << "
                             & Img (It.Bits - 1) & ") {");
                           L (Ind + 2, "w_.fail(" & W & ", ""does not fit in "
                             & Img (It.Bits) & " bits (signed)""); "
                             & "return false;");
                           L (Ind + 1, "}");
                           L (Ind + 1, "let mut x_: u64 = (sv_ as u64) & ((1u64 << "
                             & Img (It.Bits) & ") - 1);");
                        else
                           L (Ind + 1, "let mut x_: u64 = sv_ as u64;");
                        end if;
                     else
                        L (Ind + 1, "let mut x_: u64 = " & N & " as u64;");
                        if It.Bits < 64 then
                           L (Ind + 1, "if (x_ >> " & Img (It.Bits)
                             & ") != 0 { w_.fail(" & W & ", ""does not fit "
                             & "in " & Img (It.Bits) & " bits""); "
                             & "return false; }");
                        end if;
                     end if;
                     if It.Ref /= Null_Unbounded_String then
                        L (Ind + 1, "if !" & In_Of (To_String (It.Ref))
                          & "(x_) { w_.fail(" & W & ", ""is not one of the "
                          & "values the rule `" & To_String (It.Ref)
                          & "` lists""); return false; }");
                     end if;
                     if It.Little then
                        L (Ind + 1, "x_ = bnf_swap(x_, " & Img (It.Bits / 8)
                          & ");");
                     end if;
                     L (Ind + 1, "w_.wr(" & Img (It.Bits) & ", x_);");
                     L (Ind, "}");
                  when S_Assert =>
                     if not Uses_Remaining (It.Count) then
                        L (Ind, "if !(" & True_R (It.Count) & ") {");
                        L (Ind + 1, "w_.fail(""" & Where & """, """
                          & (if It.Ref /= Null_Unbounded_String
                             then Escape (To_String (It.Ref))
                             else "a condition does not hold: "
                                  & Escape (Expr_Text (It.Count)))
                          & """); return false;");
                        L (Ind, "}");
                     end if;
                  when S_Octets =>
                     if not Uses_Remaining (It.Count) then
                        L (Ind, "if (" & N & ".len() as i64) != "
                          & Expr_R (It.Count) & " {");
                        L (Ind + 1, "w_.fail(" & W & ", ""has a different "
                          & "number of octets than its length says""); "
                          & "return false;");
                        L (Ind, "}");
                     end if;
                     L (Ind, "w_.put(" & N & ");");
                  when S_Rest =>
                     L (Ind, "w_.put(" & N & ");");
                  when S_Bit_Expr =>
                     if Uses_Remaining (It.Count) then
                        L (Ind, "w_.fail(" & W & ", ""has a width that "
                          & "depends on the size of the input, which a "
                          & "writer does not know yet""); return false;");
                     else
                        L (Ind, "{");
                        L (Ind + 1, "let n_ = " & Expr_R (It.Count) & ";");
                        L (Ind + 1, "if n_ < 0 || n_ > 64 || (n_ < 64 && ("
                          & N & " >> (n_ as u32)) != 0) {");
                        L (Ind + 2, "w_.fail(" & W & ", ""does not fit in the "
                          & "number of bits its width field says""); "
                          & "return false;");
                        L (Ind + 1, "}");
                        L (Ind + 1, "w_.wr(n_ as u32, " & N & ");");
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
                           if (for some X of G.External_Tokens =>
                                 To_String (X) = To_String (It.Ref))
                           then
                              --  a text token held by the record: its octets
                              L (Ind, "w_.put(" & N & ".as_bytes());");
                           else
                              L (Ind, "w_.fail(" & W & ", ""is a text rule with "
                                 & "structure, which Rust writes only as a "
                                 & "token; the C backend writes any""); "
                                 & "return false;");
                           end if;
                        else
                           L (Ind, "if !" & Emit_Fn_Of (To_String (It.Ref))
                             & "(w_, " & N & ") { return false; }");
                        end if;
                     end if;
                  when S_Array =>
                     if It.Count /= null then
                        L (Ind, "if (" & N & ".len() as i64) != "
                          & Expr_R (It.Count) & " {");
                        L (Ind + 1, "w_.fail(" & W & ", ""has a different "
                          & "number of entries than its count says""); "
                          & "return false;");
                        L (Ind, "}");
                     else
                        L (Ind, "if " & N & ".len() < " & Img (It.Min)
                          & (if It.Max >= 0
                             then " || " & N & ".len() > " & Img (It.Max)
                             else "") & " {");
                        L (Ind + 1, "w_.fail(" & W & ", ""has a number of "
                          & "entries outside " & Img (It.Min) & ".."
                          & (if It.Max >= 0 then Img (It.Max) else "")
                          & """); return false;");
                        L (Ind, "}");
                     end if;
                     L (Ind, "for e_ in " & N & ".iter() { if !"
                       & Emit_Fn_Of (To_String (It.Ref)) & "(w_, e_) "
                       & "{ return false; } }");
                  when S_Choice =>
                     Gen_Emit_Match (It.Alts, N, Owner & Camel (N),
                                     Where & "." & N, Ind);
               end case;
            end;
         end loop;
         for It of S.Items loop
            if It.Bitsof and then Hosted_Mode then
               L (Ind, "if !w_.words_end(&" & Table_Of (It.all) & ", "
                  & Sep_Of (It.all) & ") { return false; }");
            end if;
         end loop;
      end Gen_Emit_Seq;

      --  Bind the named fields of a sequence from a record `v_`.
      procedure Bind_From_Record (S : Sequence; Ind : Natural) is
      begin
         for It of S.Items loop
            if Named (It.all) then
               if It.Kind in S_Bits | S_Bit_Expr then
                  L (Ind, "let " & To_String (It.Name) & " = v_."
                    & To_String (It.Name) & ";");
               else
                  L (Ind, "let " & To_String (It.Name) & " = &v_."
                    & To_String (It.Name) & ";");
               end if;
            end if;
         end loop;
      end Bind_From_Record;

      --  A match on a choice (or on a multi-alternative rule): each arm binds
      --  its fields by reference, and the numbers are copied out.
      procedure Gen_Emit_Match
        (Alts : Seq_Vectors.Vector; Subject : String; Enum : String;
         Where : String; Ind : Natural)
      is
         K : Natural := 0;
      begin
         L (Ind, "match " & Subject & " {");
         for A of Alts loop
            K := K + 1;
            L (Ind + 1, Enum & "::A" & Img (K) & " { " & Field_List (A.all)
               & "} => {");
            for It of A.Items loop
               if It.Kind in S_Bits | S_Bit_Expr then
                  L (Ind + 2, "let " & To_String (It.Name) & " = *"
                    & To_String (It.Name) & ";");
               end if;
            end loop;
            if A.Guard /= null and then not Uses_Remaining (A.Guard) then
               L (Ind + 2, "if !(" & True_R (A.Guard) & ") {");
               L (Ind + 3, "w_.fail(""" & Where & """, ""alternative "
                 & Img (K) & " is chosen, but its guard does not hold""); "
                 & "return false;");
               L (Ind + 2, "}");
            end if;
            Gen_Emit_Seq (A.all, Where, Enum & "A" & Img (K), Ind + 2);
            L (Ind + 1, "}");
         end loop;
         L (Ind, "}");
      end Gen_Emit_Match;

      Has_Actions : constant Boolean :=
        (for some R of G.Rules => R.Action /= Null_Unbounded_String);
      Walks : constant Name_Vectors.Vector := Walk_Set (G);

      --  The walk that runs the actions once a record has been read, children
      --  first.  Acc is how the fields are reached: `n.f` of the record, or a
      --  name bound by a match.
      procedure Gen_Walk_Seq
        (S : Sequence; Owner : String; Rec : Boolean; Ind : Natural)
      is
      begin
         for It of S.Items loop
            declare
               N : constant String := To_String (It.Name);
               U : constant String := Img (Next_Id);
            begin
               if Item_Walks (Walks, It.all) then
                  case It.Kind is
                     when S_Ref =>
                        L (Ind, "walk_" & To_String (It.Ref) & "("
                           & (if Rec then "&n." & N else N) & ", h_)?;");
                     when S_Array =>
                        L (Ind, "for e" & U & "_ in "
                           & (if Rec then "n." & N else N) & ".iter() {");
                        L (Ind + 1, "walk_" & To_String (It.Ref) & "(e" & U
                           & "_, h_)?;");
                        L (Ind, "}");
                     when S_Choice =>
                        declare
                           E : constant String := Owner & Camel (N);
                           K : Natural := 0;
                        begin
                           L (Ind, "match " & (if Rec then "&n." & N else N)
                              & " {");
                           for A of It.Alts loop
                              K := K + 1;
                              if Seq_Walks (Walks, A.all) then
                                 declare
                                    Names : Unbounded_String;
                                 begin
                                    for X of A.Items loop
                                       if Item_Walks (Walks, X.all) then
                                          Append (Names, To_String (X.Name) & ", ");
                                       end if;
                                    end loop;
                                    L (Ind + 1, E & "::A" & Img (K) & " { "
                                       & To_String (Names) & ".. } => {");
                                    Gen_Walk_Seq (A.all, E & "A" & Img (K),
                                                  False, Ind + 2);
                                    L (Ind + 1, "}");
                                 end;
                              end if;
                           end loop;
                           L (Ind + 1, "_ => {}");
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
      Words : Item_Access;
      Root_T : constant String := Type_Of (To_String (G.Rules (Root).Name));
      Rt     : constant String := To_String (G.Rules (Root).Name);
      Parse_Fn : constant String := Parse_Fn_Of (Rt);
      Emit_Fn  : constant String := Emit_Fn_Of (Rt);
   begin
      Check_Code_Language (G, "Rust");
      if not Hosted_Mode and then Is_Value_Set (G.Rules (Root)) then
         raise Wire_Error with
           "the first rule, `" & Rt & "`, is a list of constants; the "
           & "parser reads the first rule, which should be the whole message";
      end if;
      if Hosted_Mode then
         if Has_Actions then
            raise Wire_Error with
              "an %action in a grammar of text rules and bit rules is read by "
              & "C so far (Rust reads %emit there, but not %action)";
         end if;
      else
         Words := Words_Item (G, "Rust");
      end if;

         if not Hosted_Mode then
            L (0, "// generated by hbnf (binary) -- do not edit");
            L (0, "#![allow(dead_code, unused_variables, unused_mut, unused_parens, unused_assignments,");
            L (0, "         unreachable_code, non_snake_case, non_camel_case_types, non_upper_case_globals,");
            L (0, "         unused_macros)]");
         end if;
         if G.Preamble /= Null_Unbounded_String then
            L (0, "");
            L (0, "// the grammar's preamble");
            Put (To_String (G.Preamble));
            L (0, "");
         end if;
         if Has_Actions then
            L (0, "");
            L (0, "thread_local! {");
            L (0, "    static BNF_WARNINGS: std::cell::RefCell<Vec<String>> = std::cell::RefCell::new(Vec::new());");
            L (0, "}");
            L (0, "");
            L (0, "/// The warnings the `%action`s gave on the last successful read.");
            L (0, "pub fn hbnf_warnings() -> Vec<String> {");
            L (0, "    BNF_WARNINGS.with(|w| w.borrow().clone())");
            L (0, "}");
            L (0, "");
            L (0, "struct Hooks {");
            L (0, "    warnings: Vec<String>,");
            L (0, "}");
         end if;
         L (0, "");
         if not Hosted_Mode then
            L (0, "/// Where a read went wrong: the octet, and why.");
            L (0, "#[derive(Debug, Clone, PartialEq)]");
            L (0, "pub struct ParseError {");
            L (0, "    pub at: usize,");
            L (0, "    pub message: String,");
            L (0, "}");
            L (0, "");
         end if;
         L (0, "struct P<'a> {");
         if Hosted_Mode then
            L (0, "    buf: std::borrow::Cow<'a, [u8]>,");
         else
            L (0, "    buf: &'a [u8],");
         end if;
         L (0, "    nbits: usize,");
         L (0, "    bit: usize,");
         L (0, "    fail_bit: usize,");
         L (0, "    failed: bool,");
         L (0, "    msg: String,");
         if Hosted_Mode then
            L (0, "    // the bits of a text read as words (name:bitsof(rule)): where the input is");
            L (0, "    // kept while the words are read, and how wide a word is");
            L (0, "    unit: usize,");
            L (0, "    sv_active: bool,");
            L (0, "    sv_buf: std::borrow::Cow<'a, [u8]>,");
            L (0, "    sv_bit: usize,");
            L (0, "    sv_nbits: usize,");
            L (0, "    sv_unit: usize,");
            L (0, "    sv_start: usize,");
         end if;
         L (0, "}");
         L (0, "");
         L (0, "impl<'a> P<'a> {");
         L (0, "    // Keep the deepest failure, the first told.");
         L (0, "    fn fail(&mut self, bit: usize, wh: &str, what: &str) {");
         if Hosted_Mode then
            L (0, "        let mut bit = bit;");
            L (0, "        let mut how = what.to_string();");
            L (0, "        if self.sv_active {");
            L (0, "            // reading the bits of a text: say which word, and where the text was");
            L (0, "            how = format!(""{} (at unit {})"", what, bit / (if self.unit != 0 { self.unit } else { 1 }) + 1);");
            L (0, "            bit = self.sv_start * 8;");
            L (0, "        }");
            L (0, "        let what = &how[..];");
         end if;
         L (0, "        if self.failed && bit <= self.fail_bit {");
         L (0, "            return;");
         L (0, "        }");
         L (0, "        self.failed = true;");
         L (0, "        self.fail_bit = bit;");
         L (0, "        self.msg = format!(""{}: {}"", wh, what);");
         L (0, "    }");
         L (0, "");
         L (0, "    // n bits (at most 64), the first in the most significant place.");
         L (0, "    fn rd(&mut self, n: u32, wh: &str) -> Option<u64> {");
         L (0, "        let left = self.nbits - self.bit;");
         L (0, "        if n as usize > left {");
         L (0, "            let t = format!(""needs {} bits, {} left"", n, left);");
         L (0, "            self.fail(self.bit, wh, &t);");
         L (0, "            return None;");
         L (0, "        }");
         L (0, "        let mut x: u64 = 0;");
         L (0, "        let mut got: u32 = 0;");
         L (0, "        while got < n {");
         L (0, "            let byte = self.bit >> 3;");
         L (0, "            let off = (self.bit & 7) as u32;");
         L (0, "            let mut take = 8 - off;");
         L (0, "            if take > n - got {");
         L (0, "                take = n - got;");
         L (0, "            }");
         L (0, "            x = (x << take)");
         L (0, "                | (((self.buf[byte] as u32) >> (8 - off - take)) & ((1u32 << take) - 1)) as u64;");
         L (0, "            self.bit += take as usize;");
         L (0, "            got += take;");
         L (0, "        }");
         L (0, "        Some(x)");
         L (0, "    }");
         L (0, "");
         L (0, "    // n octets; copied (the Vec owns them), starting wherever the bits are.");
         L (0, "    fn take(&mut self, n: usize, wh: &str) -> Option<Vec<u8>> {");
         L (0, "        if n > (self.nbits - self.bit) / 8 {");
         L (0, "            let t = format!(""needs {} octets, {} bits left"", n, self.nbits - self.bit);");
         L (0, "            self.fail(self.bit, wh, &t);");
         L (0, "            return None;");
         L (0, "        }");
         L (0, "        if self.bit & 7 == 0 {");
         L (0, "            let s = self.bit / 8;");
         L (0, "            let v = self.buf[s..s + n].to_vec();");
         L (0, "            self.bit += n * 8;");
         L (0, "            return Some(v);");
         L (0, "        }");
         L (0, "        let mut v = Vec::with_capacity(n);");
         L (0, "        for _ in 0..n {");
         L (0, "            v.push(self.rd(8, wh)? as u8);");
         L (0, "        }");
         L (0, "        Some(v)");
         L (0, "    }");
         L (0, "");
         L (0, "    fn take_rest(&mut self, wh: &str) -> Option<Vec<u8>> {");
         L (0, "        let n = (self.nbits - self.bit) / 8;");
         L (0, "        self.take(n, wh)");
         L (0, "    }");
         if Hosted_Mode then
            L (0, "");
            L (0, "    // `name:bitsof(rule)`: the numbered words of the text the rule just read, as");
            L (0, "    // bits, width to a word; the rest of the rule reads them.  A word is looked for");
            L (0, "    // at each place (the longest that fits); what is between two is skipped.");
            L (0, "    fn words_begin(&mut self, text: &[u8], width: usize, tab: &[BnfWord], start: usize) {");
            L (0, "        let mut vals: Vec<u64> = Vec::new();");
            L (0, "        let mut pos = 0;");
            L (0, "        while pos < text.len() {");
            L (0, "            let mut hit_n = 0;");
            L (0, "            let mut hit_v = 0;");
            L (0, "            for w in tab {");
            L (0, "                if w.s.len() > hit_n && text[pos..].starts_with(w.s.as_bytes()) {");
            L (0, "                    hit_n = w.s.len();");
            L (0, "                    hit_v = w.v;");
            L (0, "                }");
            L (0, "            }");
            L (0, "            if hit_n > 0 {");
            L (0, "                vals.push(hit_v);");
            L (0, "                pos += hit_n;");
            L (0, "            } else {");
            L (0, "                pos += 1;");
            L (0, "            }");
            L (0, "        }");
            L (0, "        let nbits = vals.len() * width;");
            L (0, "        let mut buf = vec![0u8; (nbits + 7) / 8 + 1];");
            L (0, "        for (k, v) in vals.iter().enumerate() {");
            L (0, "            for i in 0..width {");
            L (0, "                let b = k * width + i;");
            L (0, "                if (v >> (width - 1 - i)) & 1 == 1 {");
            L (0, "                    buf[b >> 3] |= 0x80u8 >> (b & 7);");
            L (0, "                }");
            L (0, "            }");
            L (0, "        }");
            L (0, "        self.sv_buf = std::mem::replace(&mut self.buf, std::borrow::Cow::Owned(buf));");
            L (0, "        self.sv_bit = self.bit;");
            L (0, "        self.sv_nbits = self.nbits;");
            L (0, "        self.sv_unit = self.unit;");
            L (0, "        self.sv_start = start;");
            L (0, "        self.sv_active = true;");
            L (0, "        self.nbits = nbits;");
            L (0, "        self.bit = 0;");
            L (0, "        self.unit = width;");
            L (0, "    }");
            L (0, "");
            L (0, "    // The end of a rule that read bits from words: all of them must have been used,");
            L (0, "    // and the text is the input again.");
            L (0, "    fn words_end(&mut self, ok: bool) -> bool {");
            L (0, "        if !self.sv_active {");
            L (0, "            return ok;");
            L (0, "        }");
            L (0, "        let mut good = ok;");
            L (0, "        if ok && self.bit != self.nbits {");
            L (0, "            let t = format!(""{} bit(s) left over"", self.nbits - self.bit);");
            L (0, "            self.fail(self.bit, ""the words"", &t);");
            L (0, "            good = false;");
            L (0, "        }");
            L (0, "        self.buf = std::mem::replace(&mut self.sv_buf, std::borrow::Cow::Borrowed(&[]));");
            L (0, "        self.nbits = self.sv_nbits;");
            L (0, "        self.bit = self.sv_bit;");
            L (0, "        self.unit = self.sv_unit;");
            L (0, "        self.sv_active = false;");
            L (0, "        good");
            L (0, "    }");
         end if;
         L (0, "}");
         L (0, "");
         L (0, "struct W {");
         L (0, "    buf: Vec<u8>,");
         L (0, "    bit: usize,");
         L (0, "    failed: bool,");
         L (0, "    msg: String,");
         if Hosted_Mode then
            L (0, "    // the bits of words (name:bitsof(rule)) being written: the output so far");
            L (0, "    unit: usize,");
            L (0, "    sv_buf: Vec<u8>,");
            L (0, "    sv_bit: usize,");
         end if;
         L (0, "}");
         L (0, "");
         L (0, "impl W {");
         L (0, "    fn fail(&mut self, wh: &str, what: &str) {");
         L (0, "        if self.failed {");
         L (0, "            return;");
         L (0, "        }");
         L (0, "        self.failed = true;");
         L (0, "        self.msg = format!(""{}: {}"", wh, what);");
         L (0, "    }");
         L (0, "");
         L (0, "    fn wr(&mut self, n: u32, v: u64) {");
         L (0, "        let mut put: u32 = 0;");
         L (0, "        while put < n {");
         L (0, "            let byte = self.bit >> 3;");
         L (0, "            let off = (self.bit & 7) as u32;");
         L (0, "            let mut take = 8 - off;");
         L (0, "            if take > n - put {");
         L (0, "                take = n - put;");
         L (0, "            }");
         L (0, "            let chunk = ((v >> (n - put - take)) & ((1u64 << take) - 1)) as u8;");
         L (0, "            if byte >= self.buf.len() {");
         L (0, "                self.buf.push(0);");
         L (0, "            }");
         L (0, "            self.buf[byte] |= chunk << (8 - off - take);");
         L (0, "            self.bit += take as usize;");
         L (0, "            put += take;");
         L (0, "        }");
         L (0, "    }");
         L (0, "");
         if Hosted_Mode then
            L (0, "    // From here the bits written are a word's each, spelled by words_end.");
            L (0, "    fn words_begin(&mut self, width: usize) {");
            L (0, "        self.sv_buf = std::mem::take(&mut self.buf);");
            L (0, "        self.sv_bit = self.bit;");
            L (0, "        self.bit = 0;");
            L (0, "        self.unit = width;");
            L (0, "    }");
            L (0, "");
            L (0, "    // The bits written since words_begin, as the words that spell them, with sep");
            L (0, "    // between two, written to what was the output.");
            L (0, "    fn words_end(&mut self, tab: &[BnfWord], sep: &str) -> bool {");
            L (0, "        let total = self.bit;");
            L (0, "        let width = self.unit;");
            L (0, "        let bits = std::mem::take(&mut self.buf);");
            L (0, "        self.buf = std::mem::take(&mut self.sv_buf);");
            L (0, "        self.bit = self.sv_bit;");
            L (0, "        self.unit = 0;");
            L (0, "        if width == 0 || total % width != 0 {");
            L (0, "            let t = format!(""{} bits is not a whole number of {}-bit units"", total, width);");
            L (0, "            self.fail(""the words"", &t);");
            L (0, "            return false;");
            L (0, "        }");
            L (0, "        for i in 0..total / width {");
            L (0, "            let mut v: u64 = 0;");
            L (0, "            for b in 0..width {");
            L (0, "                let bit = i * width + b;");
            L (0, "                v = (v << 1) | ((bits[bit >> 3] >> (7 - (bit & 7))) & 1) as u64;");
            L (0, "            }");
            L (0, "            match tab.iter().find(|w| w.v == v) {");
            L (0, "                Some(w) => {");
            L (0, "                    if i > 0 && !sep.is_empty() {");
            L (0, "                        self.put(sep.as_bytes());");
            L (0, "                    }");
            L (0, "                    self.put(w.s.as_bytes());");
            L (0, "                }");
            L (0, "                None => {");
            L (0, "                    let t = format!(""unit {} has the value {}, which no word spells"", i, v);");
            L (0, "                    self.fail(""the words"", &t);");
            L (0, "                    return false;");
            L (0, "                }");
            L (0, "            }");
            L (0, "        }");
            L (0, "        true");
            L (0, "    }");
            L (0, "");
         end if;
         L (0, "    fn put(&mut self, p: &[u8]) {");
         L (0, "        if self.bit & 7 == 0 {");
         L (0, "            self.buf.extend_from_slice(p);");
         L (0, "            self.bit += p.len() * 8;");
         L (0, "        } else {");
         L (0, "            for b in p {");
         L (0, "                self.wr(8, *b as u64);");
         L (0, "            }");
         L (0, "        }");
         L (0, "    }");
         L (0, "}");
         L (0, "");
         L (0, "// the bits to the next boundary of a word; 0 when the grammar has no words");
         L (0, "fn bnf_align(bit: usize, unit: usize) -> i64 {");
         L (0, "    if unit == 0 { 0 } else { ((unit - bit % unit) % unit) as i64 }");
         L (0, "}");
         if Hosted_Mode then
            L (0, "struct BnfWord { s: &'static str, v: u64 }");
         else
            L (0, "const BNF_UNIT: usize = " & (if Words = null then "0" else Img (Words.Width)) & ";");
         end if;
         if Hosted_Mode then
            L (0, "fn bnf_lossy(b: &[u8]) -> String {");
            L (0, "    String::from_utf8_lossy(b).into_owned()");
            L (0, "}");
            L (0, "// The octets from the current bit on, as octets: a copy shifted to start on one.");
            L (0, "fn bnf_shifted(p_: &P) -> Vec<u8> {");
            L (0, "    let off = (p_.bit % 8) as u32;");
            L (0, "    let base = p_.bit / 8;");
            L (0, "    let m = (p_.nbits - p_.bit) / 8;");
            L (0, "    (0..m).map(|k| (p_.buf[base + k] << off) | (p_.buf[base + k + 1] >> (8 - off))).collect()");
            L (0, "}");
         end if;
         L (0, "fn bnf_swap(v: u64, nbytes: u32) -> u64 {");
         L (0, "    let mut r: u64 = 0;");
         L (0, "    let mut v = v;");
         L (0, "    for _ in 0..nbytes {");
         L (0, "        r = (r << 8) | (v & 0xFF);");
         L (0, "        v >>= 8;");
         L (0, "    }");
         L (0, "    r");
         L (0, "}");
         L (0, "fn bnf_div(a: i64, b: i64) -> i64 {");
         L (0, "    if b != 0 { a.wrapping_div(b) } else { 0 }");
         L (0, "}");
         L (0, "fn bnf_rem(a: i64, b: i64) -> i64 {");
         L (0, "    if b != 0 { a.wrapping_rem(b) } else { 0 }");
         L (0, "}");
         L (0, "fn bnf_shl(a: i64, b: i64) -> i64 {");
         L (0, "    ((a as u64) << ((b & 63) as u32)) as i64");
         L (0, "}");
         L (0, "fn bnf_shr(a: i64, b: i64) -> i64 {");
         L (0, "    ((a as u64) >> ((b & 63) as u32)) as i64");
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
                           Check_Name (It.all);
                           Append (Fields, "    pub " & To_String (It.Name)
                                   & ": " & Field_Type (It.all, Nm) & ","
                                   & ASCII.LF);
                        end if;
                     end loop;
                     D (0, (if Hosted_Mode
                            then "#[derive(Debug, Clone, PartialEq, Default)]"
                            else "#[derive(Debug, Clone, PartialEq)]"));
                     D (0, "pub struct " & Nm & " {");
                     Append (Defs, Fields);
                     D (0, "}");
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
                     Append (T, " | ");
                  end if;
                  First := False;
                  Append (T, Hex (A.Items.First_Element.Value));
               end loop;
               L (0, "fn " & In_Of (To_String (R.Name)) & "(v: u64) -> bool {");
               L (1, "matches!(v, " & To_String (T) & ")");
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
                        L (0, "const " & Table_Of (It.all) & ": [BnfWord; "
                           & Img (Natural (It.Words.Length)) & "] = [");
                        for U of It.Words loop
                           L (1, "BnfWord { s: """ & Escape (To_String (U.Spelling))
                              & """, v: " & Img (U.Value) & " },");
                        end loop;
                        L (0, "];");
                        L (0, "const " & Sep_Of (It.all) & ": &str = """
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
               Wrap : constant Boolean := Hosted_Mode and then Rule_Has_Bitsof (R);
            begin
               L (0, "fn " & Parse_Fn_Of (Nm) & (if Wrap then "_body" else "")
                  & "(p_: &mut P) -> Option<" & T & "> {");
               Emit_Side := False;
               if Natural (R.Alts.Length) = 1 then
                  Gen_Seq (R.Alts.First_Element.all, Nm, T, 1);
                  L (1, "Some(" & T & " { "
                     & Field_List (R.Alts.First_Element.all) & "})");
               else
                  L (1, "let r_: " & T & " = {");
                  Gen_Choice (R.Alts, T, Nm, 2);
                  L (1, "};");
                  L (1, "Some(r_)");
               end if;
               L (0, "}");
               L (0, "");
               if Wrap then
                  L (0, "fn " & Parse_Fn_Of (Nm) & "(p_: &mut P) -> Option<" & T & "> {");
                  L (1, "let r = " & Parse_Fn_Of (Nm) & "_body(p_);");
                  L (1, "if !p_.words_end(r.is_some()) { return None; }");
                  L (1, "r");
                  L (0, "}");
                  L (0, "");
               end if;
               L (0, "fn " & Emit_Fn_Of (Nm) & "(w_: &mut W, v_: &" & T
                  & ") -> bool {");
               Emit_Side := True;
               if R.Emit /= Null_Unbounded_String then
                  --  %emit runs on a copy of the record, before its fields are
                  --  written
                  L (1, "let mut n = v_.clone();");
                  L (1, "{");
                  L (2, "macro_rules! hbnf_emit_fail {");
                  L (3, "($m:expr) => {{ w_.fail(""emit"", $m); return false; }};");
                  L (2, "}");
                  Put (To_String (R.Emit));
                  L (0, "");
                  L (1, "}");
                  L (1, "let v_ = &n;");
               end if;
               if Natural (R.Alts.Length) = 1 then
                  Bind_From_Record (R.Alts.First_Element.all, 1);
                  Gen_Emit_Seq (R.Alts.First_Element.all, Nm, T, 1);
               else
                  Gen_Emit_Match (R.Alts, "v_", T, Nm, 1);
               end if;
               Emit_Side := False;
               L (1, "true");
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
                     L (0, "fn action_" & Nm & "(n: &" & T
                        & ", h_: &mut Hooks) -> Result<(), String> {");
                     L (1, "macro_rules! hbnf_warn {");
                     L (2, "($m:expr) => { h_.warnings.push(($m).to_string()) };");
                     L (1, "}");
                     L (1, "macro_rules! hbnf_fail {");
                     L (2, "($m:expr) => { return Err(($m).to_string()) };");
                     L (1, "}");
                     L (1, "{");
                     Put (To_String (R.Action));
                     L (0, "");
                     L (1, "}");
                     L (1, "Ok(())");
                     L (0, "}");
                     L (0, "");
                  end if;
                  L (0, "fn walk_" & Nm & "(n: &" & T
                     & ", h_: &mut Hooks) -> Result<(), String> {");
                  if Natural (R.Alts.Length) = 1 then
                     Gen_Walk_Seq (R.Alts.First_Element.all, T, True, 1);
                  else
                     declare
                        K : Natural := 0;
                     begin
                        L (1, "match n {");
                        for A of R.Alts loop
                           K := K + 1;
                           if Seq_Walks (Walks, A.all) then
                              declare
                                 Names : Unbounded_String;
                              begin
                                 for X of A.Items loop
                                    if Item_Walks (Walks, X.all) then
                                       Append (Names, To_String (X.Name) & ", ");
                                    end if;
                                 end loop;
                                 L (2, T & "::A" & Img (K) & " { "
                                    & To_String (Names) & ".. } => {");
                                 Gen_Walk_Seq (A.all, T & "A" & Img (K), False, 3);
                                 L (2, "}");
                              end;
                           end if;
                        end loop;
                        L (2, "_ => {}");
                        L (1, "}");
                     end;
                  end if;
                  if R.Action /= Null_Unbounded_String then
                     L (1, "action_" & Nm & "(n, h_)?;");
                  end if;
                  L (1, "Ok(())");
                  L (0, "}");
                  L (0, "");
               end;
            end if;
         end loop;
         L (0, "// Run the actions on a record that has been read; the warnings are kept.");
         L (0, "fn bnf_check(v: &" & Root_T & ") -> Result<(), String> {");
         L (0, "    let mut h_ = Hooks { warnings: Vec::new() };");
         L (0, "    let r = walk_" & Rt & "(v, &mut h_);");
         L (0, "    BNF_WARNINGS.with(|w| *w.borrow_mut() = h_.warnings);");
         L (0, "    r");
         L (0, "}");
         L (0, "");
      end if;

      if Hosted_Mode then
         for R of G.Rules loop
            if not Is_Value_Set (R) then
               declare
                  Nm : constant String := To_String (R.Name);
               begin
                  L (0, "");
                  L (0, "/// The bits of one " & Nm & ", written (its %emit first).");
                  L (0, "pub fn emit_bits_" & Nm & "(v: &" & Type_Of (Nm)
                     & ") -> Result<(Vec<u8>, usize), String> {");
                  L (0, "    let mut w_ = W { buf: Vec::new(), bit: 0, failed: false, msg: String::new(), unit: 0, sv_buf: Vec::new(), sv_bit: 0 };");
                  L (0, "    if !" & Emit_Fn_Of (Nm) & "(&mut w_, v) {");
                  L (0, "        return Err(w_.msg);");
                  L (0, "    }");
                  L (0, "    Ok((w_.buf, w_.bit))");
                  L (0, "}");
               end;
            end if;
         end loop;
      elsif Words = null then
         L (0, "");
         L (0, "fn read(buf: &[u8], nbits: usize) -> Result<" & Root_T & ", (usize, String)> {");
         L (0, "    let mut p_ = P { buf, nbits, bit: 0, fail_bit: 0, failed: false, msg: String::new() };");
         L (0, "    match " & Parse_Fn & "(&mut p_) {");
         L (0, "        None => Err((p_.fail_bit, p_.msg)),");
         L (0, "        Some(v) => {");
         L (0, "            if p_.bit != nbits {");
         L (0, "                p_.failed = false;");
         L (0, "                let t = format!(""{} bit(s) left over after the message"", nbits - p_.bit);");
         L (0, "                p_.fail(p_.bit, """ & Rt & """, &t);");
         L (0, "                Err((p_.fail_bit, p_.msg))");
         L (0, "            } else {");
         if Has_Actions then
            L (0, "                if let Err(m) = bnf_check(&v) {");
            L (0, "                    p_.failed = false;");
            L (0, "                    p_.fail(p_.bit, """ & Rt & """, &m);");
            L (0, "                    return Err((p_.fail_bit, p_.msg));");
            L (0, "                }");
         end if;
         L (0, "                Ok(v)");
         L (0, "            }");
         L (0, "        }");
         L (0, "    }");
         L (0, "}");
         L (0, "");
         L (0, "/// Read nbits bits of buf as one " & Rt & ".  On success all of them were used.");
         L (0, "pub fn parse_bits(buf: &[u8], nbits: usize) -> Result<" & Root_T & ", ParseError> {");
         L (0, "    read(buf, nbits).map_err(|(fb, m)| ParseError {");
         L (0, "        at: fb / 8,");
         L (0, "        message: format!(""octet {}: {}"", fb / 8, m),");
         L (0, "    })");
         L (0, "}");
         L (0, "");
         L (0, "/// The same, for a message that is whole octets.");
         L (0, "pub fn parse_bytes(buf: &[u8]) -> Result<" & Root_T & ", ParseError> {");
         L (0, "    parse_bits(buf, buf.len() * 8)");
         L (0, "}");
         L (0, "");
         L (0, "/// Write v as bits: the bytes (the last one may be partly filled) and the");
         L (0, "/// number of bits.  A value that does not fit its field, or does not agree with");
         L (0, "/// a length or tag field, is an error, not a guess.");
         L (0, "pub fn emit_bits(v: &" & Root_T & ") -> Result<(Vec<u8>, usize), String> {");
         L (0, "    let mut w_ = W { buf: Vec::new(), bit: 0, failed: false, msg: String::new() };");
         L (0, "    if !" & Emit_Fn & "(&mut w_, v) {");
         L (0, "        return Err(w_.msg);");
         L (0, "    }");
         L (0, "    Ok((w_.buf, w_.bit))");
         L (0, "}");
         L (0, "");
         L (0, "/// The same, for a message that is whole octets.");
         L (0, "pub fn emit_bytes(v: &" & Root_T & ") -> Result<Vec<u8>, String> {");
         L (0, "    let (b, n) = emit_bits(v)?;");
         L (0, "    if n & 7 != 0 {");
         L (0, "        return Err(""" & Rt & ": the message does not end on an octet boundary"".to_string());");
         L (0, "    }");
         L (0, "    Ok(b)");
         L (0, "}");

      else
      declare
         Wd : constant String := Img (Words.Width);
         Tab : Unbounded_String;
         Order : Unit_Vectors.Vector := Words.Words;
      begin
         --  a longer spelling is tried before a shorter one it starts with
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
            Append (Tab, "    (""" & Escape (To_String (U.Spelling)) & """, "
                    & Img (U.Value) & "),");
            Append (Tab, ASCII.LF);
         end loop;
         L (0, "");
         L (0, "const BNF_WIDTH: usize = " & Wd & ";");
         L (0, "const BNF_SEP: &str = """ & Escape (To_String (Words.Sep)) & """;");
         L (0, "// the spellings of the words and their numbers, a longer one before a shorter");
         L (0, "// one it starts with");
         L (0, "const BNF_WORDS: &[(&str, u64)] = &[");
         Put (To_String (Tab));
         L (0, "];");
         L (0, "");
         L (0, "fn bnf_found(text: &str, from: usize) -> String {");
         L (0, "    if from >= text.len() {");
         L (0, "        return ""end of input"".to_string();");
         L (0, "    }");
         L (0, "    text[from..].chars().take(24).collect()");
         L (0, "}");
         L (0, "");
         L (0, "// The text as the bits of its words: BNF_WIDTH bits each, the first word first.");
         L (0, "fn bnf_words(text: &str) -> Result<(Vec<u8>, usize), ParseError> {");
         L (0, "    let mut vals: Vec<u64> = Vec::new();");
         L (0, "    let mut pos = 0usize;");
         if Words.Words_Empty then
            L (0, "    if text.is_empty() {");
            L (0, "        return Ok((Vec::new(), 0));");
            L (0, "    }");
         end if;
         L (0, "    loop {");
         L (0, "        let rest = &text[pos..];");
         L (0, "        let mut hit: Option<(usize, u64)> = None;");
         L (0, "        for (s, v) in BNF_WORDS {");
         L (0, "            if rest.starts_with(s) && hit.map_or(true, |(n, _)| s.len() > n) {");
         L (0, "                hit = Some((s.len(), *v));");
         L (0, "            }");
         L (0, "        }");
         L (0, "        match hit {");
         L (0, "            None => {");
         L (0, "                return Err(ParseError {");
         L (0, "                    at: pos,");
         L (0, "                    message: format!(""expected a " & Escape (To_String (Words.Word_Rule)) & ", found {}"", bnf_found(text, pos)),");
         L (0, "                });");
         L (0, "            }");
         L (0, "            Some((n, v)) => {");
         L (0, "                vals.push(v);");
         L (0, "                pos += n;");
         L (0, "            }");
         L (0, "        }");
         L (0, "        if pos >= text.len() {");
         L (0, "            break;");
         L (0, "        }");
         L (0, "        if !BNF_SEP.is_empty() {");
         L (0, "            if !text[pos..].starts_with(BNF_SEP) {");
         L (0, "                return Err(ParseError {");
         L (0, "                    at: pos,");
         L (0, "                    message: format!(""expected `{}`, found {}"", BNF_SEP, bnf_found(text, pos)),");
         L (0, "                });");
         L (0, "            }");
         L (0, "            pos += BNF_SEP.len();");
         L (0, "        }");
         L (0, "    }");
         L (0, "    let nbits = vals.len() * BNF_WIDTH;");
         L (0, "    let mut buf = vec![0u8; (nbits + 7) / 8];");
         L (0, "    for (k, v) in vals.iter().enumerate() {");
         L (0, "        for i in 0..BNF_WIDTH {");
         L (0, "            let b = k * BNF_WIDTH + i;");
         L (0, "            if (v >> (BNF_WIDTH - 1 - i)) & 1 == 1 {");
         L (0, "                buf[b >> 3] |= 0x80 >> (b & 7);");
         L (0, "            }");
         L (0, "        }");
         L (0, "    }");
         L (0, "    Ok((buf, nbits))");
         L (0, "}");
         L (0, "");
         L (0, "/// Read the words of text as the bits of one " & Rt & ".  A mistake in the words");
         L (0, "/// says which; one in the bits says at which word (`(at unit N)`).");
         L (0, "pub fn parse_text(text: &str) -> Result<" & Root_T & ", ParseError> {");
         L (0, "    let (buf, nbits) = bnf_words(text)?;");
         L (0, "    let mut p_ = P { buf: &buf, nbits, bit: 0, fail_bit: 0, failed: false, msg: String::new() };");
         L (0, "    let at_unit = |p_: &P, m: &str| ParseError {");
         L (0, "        at: 0,");
         L (0, "        message: format!(""expected {} (at unit {}), found {}"", m, p_.fail_bit / BNF_WIDTH + 1, bnf_found(text, 0)),");
         L (0, "    };");
         L (0, "    match " & Parse_Fn & "(&mut p_) {");
         L (0, "        None => Err(at_unit(&p_, &p_.msg)),");
         L (0, "        Some(v) => {");
         L (0, "            if p_.bit != nbits {");
         L (0, "                p_.fail_bit = p_.bit;");
         L (0, "                let m = format!(""the words: {} bit(s) left over"", nbits - p_.bit);");
         L (0, "                Err(at_unit(&p_, &m))");
         L (0, "            } else {");
         if Has_Actions then
            L (0, "                match bnf_check(&v) {");
            L (0, "                    Ok(()) => Ok(v),");
            L (0, "                    Err(m) => Err(ParseError { at: 0, message: m }),");
            L (0, "                }");
         else
            L (0, "                Ok(v)");
         end if;
         L (0, "            }");
         L (0, "        }");
         L (0, "    }");
         L (0, "}");
         L (0, "");
         L (0, "/// Write v as the text of its words: the bits, BNF_WIDTH to a word, each spelled,");
         L (0, "/// with the separator between.");
         L (0, "pub fn emit_text(v: &" & Root_T & ") -> Result<String, String> {");
         L (0, "    let mut w_ = W { buf: Vec::new(), bit: 0, failed: false, msg: String::new() };");
         L (0, "    if !" & Emit_Fn & "(&mut w_, v) {");
         L (0, "        return Err(w_.msg);");
         L (0, "    }");
         L (0, "    if w_.bit % BNF_WIDTH != 0 {");
         L (0, "        return Err(format!(""the words: {} bits is not a whole number of {}-bit units"", w_.bit, BNF_WIDTH));");
         L (0, "    }");
         L (0, "    let mut out = String::new();");
         L (0, "    for k in 0..w_.bit / BNF_WIDTH {");
         L (0, "        let mut x: u64 = 0;");
         L (0, "        for i in 0..BNF_WIDTH {");
         L (0, "            let b = k * BNF_WIDTH + i;");
         L (0, "            x = (x << 1) | ((w_.buf[b >> 3] >> (7 - (b & 7))) & 1) as u64;");
         L (0, "        }");
         L (0, "        match BNF_WORDS.iter().find(|(_, n)| *n == x) {");
         L (0, "            Some((s, _)) => {");
         L (0, "                if k > 0 {");
         L (0, "                    out.push_str(BNF_SEP);");
         L (0, "                }");
         L (0, "                out.push_str(s);");
         L (0, "            }");
         L (0, "            None => {");
         L (0, "                return Err(format!(""the words: unit {} has the value {}, which no word spells"", k, x));");
         L (0, "            }");
         L (0, "        }");
         L (0, "    }");
         L (0, "    Ok(out)");
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
            --  the text as bytes, the types the text parser needs of it, and
            --  what it calls: a bit rule read as a text rule is
            Append (Text, ASCII.LF
              & "// The text, as bytes: a bit rule reads any octet, and a text rule sees" & ASCII.LF
              & "// the octets it reads as text." & ASCII.LF
              & "#[derive(Clone, Copy)]" & ASCII.LF
              & "struct Txt<'a>(&'a [u8]);" & ASCII.LF
              & "impl<'a> Txt<'a> {" & ASCII.LF
              & "    fn as_bytes(&self) -> &'a [u8] { self.0 }" & ASCII.LF
              & "    fn len(&self) -> usize { self.0.len() }" & ASCII.LF
              & "    fn cut(self, end: usize) -> Txt<'a> { Txt(&self.0[..end]) }" & ASCII.LF
              & "}" & ASCII.LF
              & "impl<'a> std::ops::Index<std::ops::Range<usize>> for Txt<'a> {" & ASCII.LF
              & "    type Output = str;" & ASCII.LF
              & "    fn index(&self, r: std::ops::Range<usize>) -> &str { unsafe { std::str::from_utf8_unchecked(&self.0[r]) } }" & ASCII.LF
              & "}" & ASCII.LF
              & "impl<'a> std::ops::Index<std::ops::RangeFrom<usize>> for Txt<'a> {" & ASCII.LF
              & "    type Output = str;" & ASCII.LF
              & "    fn index(&self, r: std::ops::RangeFrom<usize>) -> &str { unsafe { std::str::from_utf8_unchecked(&self.0[r]) } }" & ASCII.LF
              & "}" & ASCII.LF
              & "impl<'a> std::ops::Index<std::ops::RangeTo<usize>> for Txt<'a> {" & ASCII.LF
              & "    type Output = str;" & ASCII.LF
              & "    fn index(&self, r: std::ops::RangeTo<usize>) -> &str { unsafe { std::str::from_utf8_unchecked(&self.0[r]) } }" & ASCII.LF
              & "}" & ASCII.LF
              & "type TextP<'a> = P<'a>;" & ASCII.LF
              & "fn bnf_first_char(b: &[u8]) -> String {" & ASCII.LF
              & "    let n = match b[0] { 0..=0x7f => 1, 0xc0..=0xdf => 2, 0xe0..=0xef => 3, 0xf0..=0xf7 => 4, _ => 1 };" & ASCII.LF
              & "    String::from_utf8_lossy(&b[..n.min(b.len())]).chars().next().unwrap_or('\u{FFFD}').to_string()" & ASCII.LF
              & "}" & ASCII.LF);
            for R of G.Rules loop
               if not Is_Value_Set (R) then
                  declare
                     Nm : constant String := To_String (R.Name);
                     T  : constant String := Type_Of (Nm);
                  begin
                     Append (Text, ASCII.LF & "fn " & HBNF_Rust.Parse_Fn (Nm)
                       & "(p: &mut P) -> Result<" & T & ", ParseError> {" & ASCII.LF);
                     Append (Text, "    let mut w = WP { buf: std::borrow::Cow::Borrowed(p.text.as_bytes()), nbits: p.text.len() * 8, "
                       & "bit: p.pos * 8 + p.bit, fail_bit: 0, failed: false, msg: String::new(), "
                       & "unit: 0, sv_active: false, sv_buf: std::borrow::Cow::Borrowed(&[]), "
                       & "sv_bit: 0, sv_nbits: 0, sv_unit: 0, sv_start: 0 };"
                       & ASCII.LF);
                     Append (Text, "    match " & Parse_Fn_Of (Nm) & "(&mut w) {" & ASCII.LF
                       & "        Some(v) => {" & ASCII.LF
                       & "            p.pos = w.bit / 8;" & ASCII.LF
                       & "            p.bit = w.bit % 8;" & ASCII.LF
                       & "            Ok(v)" & ASCII.LF & "        }" & ASCII.LF
                       & "        None => {" & ASCII.LF
                       & "            p.pos = w.fail_bit / 8;" & ASCII.LF
                       & "            let m = w.msg.clone();" & ASCII.LF
                       & "            Err(p.fail(&m))" & ASCII.LF & "        }" & ASCII.LF
                       & "    }" & ASCII.LF & "}" & ASCII.LF);
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

end HBNF_Wire.Rust;
