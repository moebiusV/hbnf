pragma Ada_2022;

with Ada.Characters.Handling;
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
      new String'("sv_"), new String'("cnt_")];

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
        (It.Kind not in S_Const | S_Assert);

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
                  declare
                     W : constant String := Img (G.Unit_Width);
                     B : constant String := (if Emit_Side then "w_.bit"
                                             else "p_.bit");
                  begin
                     return "((" & W & " - " & B & " % " & W & ") % " & W
                       & ") as i64";
                  end;
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
                     L (Ind, "let " & N & ": " & Type_Of (To_String (It.Ref))
                       & " = " & Parse_Fn_Of (To_String (It.Ref)) & "(p_)?;");
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
                     L (Ind, "if !" & Emit_Fn_Of (To_String (It.Ref))
                       & "(w_, " & N & ") { return false; }");
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

      Root : constant Natural := 1;
      Root_T : constant String := Type_Of (To_String (G.Rules (Root).Name));
      Rt     : constant String := To_String (G.Rules (Root).Name);
      Parse_Fn : constant String := Parse_Fn_Of (Rt);
      Emit_Fn  : constant String := Emit_Fn_Of (Rt);
   begin
      Check_Code_Language (G, "Rust");
      if Is_Value_Set (G.Rules (Root)) then
         raise Wire_Error with
           "the first rule, `" & Rt & "`, is a list of constants; the "
           & "parser reads the first rule, which should be the whole message";
      end if;

         L (0, "// generated by hbnf (binary) -- do not edit");
         L (0, "#![allow(dead_code, unused_variables, unused_mut, unused_parens, unused_assignments,");
         L (0, "         unreachable_code, non_snake_case, non_camel_case_types, non_upper_case_globals)]");
         L (0, "");
         L (0, "/// Where a read went wrong: the octet, and why.");
         L (0, "#[derive(Debug, Clone, PartialEq)]");
         L (0, "pub struct ParseError {");
         L (0, "    pub at: usize,");
         L (0, "    pub message: String,");
         L (0, "}");
         L (0, "");
         L (0, "struct P<'a> {");
         L (0, "    buf: &'a [u8],");
         L (0, "    nbits: usize,");
         L (0, "    bit: usize,");
         L (0, "    fail_bit: usize,");
         L (0, "    failed: bool,");
         L (0, "    msg: String,");
         L (0, "}");
         L (0, "");
         L (0, "impl<'a> P<'a> {");
         L (0, "    // Keep the deepest failure, the first told.");
         L (0, "    fn fail(&mut self, bit: usize, wh: &str, what: &str) {");
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
         L (0, "}");
         L (0, "");
         L (0, "struct W {");
         L (0, "    buf: Vec<u8>,");
         L (0, "    bit: usize,");
         L (0, "    failed: bool,");
         L (0, "    msg: String,");
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
                     D (0, "#[derive(Debug, Clone, PartialEq)]");
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
      Put (To_String (Defs));

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

      --  The readers and the writers.
      for R of G.Rules loop
         if not Is_Value_Set (R) then
            declare
               Nm : constant String := To_String (R.Name);
               T  : constant String := Type_Of (Nm);
            begin
               L (0, "fn " & Parse_Fn_Of (Nm) & "(p_: &mut P) -> Option<"
                  & T & "> {");
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
               L (0, "fn " & Emit_Fn_Of (Nm) & "(w_: &mut W, v_: &" & T
                  & ") -> bool {");
               Emit_Side := True;
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

      if G.Unit_Width > 0 then
         L (0, "");
         L (0, "const UNIT_BITS: u32 = " & Img (G.Unit_Width) & ";");
         L (0, "const SEP: &str = """ & Escape (To_String (G.Unit_Sep)) & """;");
         L (0, "// The spellings, longest first.");
         L (0, "static UNITS: &[(&str, u32)] = &[");
         declare
            Longest : Natural := 0;
         begin
            for U of G.Units loop
               Longest := Natural'Max (Longest, Length (U.Spelling));
            end loop;
            for Len in reverse 0 .. Longest loop
               for U of G.Units loop
                  if Length (U.Spelling) = Len then
                     L (1, "(""" & Escape (To_String (U.Spelling)) & """, "
                        & Img (U.Value) & "),");
                  end if;
               end loop;
            end loop;
         end;
         L (0, "];");
         L (0, "");
         L (0, "// ---- the text form: the message as units of UNIT_BITS bits, each spelled by");
         L (0, "// one of the strings above (a bech32 symbol, a BIP-39 word).  A spelling is");
         L (0, "// matched longest first, and where there is a separator it counts only if it is");
         L (0, "// followed by one or by the end, so a word is never taken for the start of a");
         L (0, "// longer one.");
         L (0, "pub fn parse_text(text: &str) -> Result<" & Root_T & ", ParseError> {");
         L (0, "    let t = text.as_bytes();");
         L (0, "    let mut w_ = W { buf: Vec::new(), bit: 0, failed: false, msg: String::new() };");
         L (0, "    let mut start: Vec<usize> = Vec::new();");
         L (0, "    let mut pos = 0usize;");
         L (0, "    while pos < t.len() {");
         L (0, "        let mut found: Option<(usize, u32)> = None;");
         L (0, "        for &(s, v) in UNITS {");
         L (0, "            let sb = s.as_bytes();");
         L (0, "            if !t[pos..].starts_with(sb) {");
         L (0, "                continue;");
         L (0, "            }");
         L (0, "            if !SEP.is_empty()");
         L (0, "                && pos + sb.len() < t.len()");
         L (0, "                && !t[pos + sb.len()..].starts_with(SEP.as_bytes())");
         L (0, "            {");
         L (0, "                continue;");
         L (0, "            }");
         L (0, "            found = Some((sb.len(), v));");
         L (0, "            break;");
         L (0, "        }");
         L (0, "        let (l, v) = match found {");
         L (0, "            Some(x) => x,");
         L (0, "            None => {");
         L (0, "                return Err(ParseError {");
         L (0, "                    at: pos,");
         L (0, "                    message: format!(""character {}: not one of the units"", pos),");
         L (0, "                })");
         L (0, "            }");
         L (0, "        };");
         L (0, "        start.push(pos);");
         L (0, "        w_.wr(UNIT_BITS, v as u64);");
         L (0, "        pos += l;");
         L (0, "        if !SEP.is_empty() && pos < t.len() {");
         L (0, "            pos += SEP.len();");
         L (0, "            if pos == t.len() {");
         L (0, "                return Err(ParseError {");
         L (0, "                    at: pos,");
         L (0, "                    message: format!(""character {}: the text ends with a separator"", pos),");
         L (0, "                });");
         L (0, "            }");
         L (0, "        }");
         L (0, "    }");
         L (0, "    match read(&w_.buf, start.len() * UNIT_BITS as usize) {");
         L (0, "        Ok(v) => Ok(v),");
         L (0, "        Err((fb, m)) => {");
         L (0, "            let u = fb / UNIT_BITS as usize;");
         L (0, "            let c = if u < start.len() { start[u] } else { t.len() };");
         L (0, "            Err(ParseError { at: c, message: format!(""unit {} (character {}): {}"", u, c, m) })");
         L (0, "        }");
         L (0, "    }");
         L (0, "}");
         L (0, "");
         L (0, "/// The message as text.");
         L (0, "pub fn emit_text(v: &" & Root_T & ") -> Result<String, String> {");
         L (0, "    let (b, nbits) = emit_bits(v)?;");
         L (0, "    let ub = UNIT_BITS as usize;");
         L (0, "    if nbits % ub != 0 {");
         L (0, "        return Err(format!(""{} bits is not a whole number of {}-bit units"", nbits, UNIT_BITS));");
         L (0, "    }");
         L (0, "    let mut out = String::new();");
         L (0, "    for i in 0..nbits / ub {");
         L (0, "        let mut x: u32 = 0;");
         L (0, "        for k in 0..ub {");
         L (0, "            let bit = i * ub + k;");
         L (0, "            x = (x << 1) | ((b[bit >> 3] >> (7 - (bit & 7))) & 1) as u32;");
         L (0, "        }");
         L (0, "        let s = match UNITS.iter().find(|(_, val)| *val == x) {");
         L (0, "            Some((s, _)) => *s,");
         L (0, "            None => return Err(format!(""unit {} has the value {}, which no unit spells"", i, x)),");
         L (0, "        };");
         L (0, "        if i > 0 {");
         L (0, "            out.push_str(SEP);");
         L (0, "        }");
         L (0, "        out.push_str(s);");
         L (0, "    }");
         L (0, "    Ok(out)");
         L (0, "}");
      end if;
      return To_String (Buf);
   end Emit;

end HBNF_Wire.Rust;
