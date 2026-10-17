pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Fixed;

package body HBNF_Wire.C is

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
      return "0x" & R (K .. 16) & "ULL";
   end Hex;

   C_Keywords : constant array (Positive range <>) of access constant String :=
     [new String'("auto"), new String'("break"), new String'("case"),
      new String'("char"), new String'("const"), new String'("continue"),
      new String'("default"), new String'("do"), new String'("double"),
      new String'("else"), new String'("enum"), new String'("extern"),
      new String'("float"), new String'("for"), new String'("goto"),
      new String'("if"), new String'("inline"), new String'("int"),
      new String'("long"), new String'("register"), new String'("restrict"),
      new String'("return"), new String'("short"), new String'("signed"),
      new String'("sizeof"), new String'("static"), new String'("struct"),
      new String'("switch"), new String'("typedef"), new String'("union"),
      new String'("unsigned"), new String'("void"), new String'("volatile"),
      new String'("while"), new String'("bool"), new String'("true"),
      new String'("false")];

   function Is_Keyword (S : String) return Boolean is
   begin
      for K of C_Keywords loop
         if K.all = S then
            return True;
         end if;
      end loop;
      return False;
   end Is_Keyword;

   type Binding is record
      Name   : Unbounded_String;
      Lvalue : Unbounded_String;
   end record;
   package Binding_Vectors is new Ada.Containers.Vectors (Positive, Binding);

   function Emit (G : Grammar) return String is
      Buf : Unbounded_String;
      Id  : Natural := 0;

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

      function Next_Id return Natural is
      begin
         Id := Id + 1;
         return Id;
      end Next_Id;

      Pfx : constant String := To_String (G.Prefix);

      function Type_Of (R : String) return String is (Pfx & R & "_t");
      function Tag_Of (R : String) return String is (Pfx & R & "_s");
      function Fn_Of (R : String) return String is ("parse_rule_" & R);
      function In_Of (R : String) return String is ("in_value_set_" & R);

      function Int_Type (Bits : Natural; Signed : Boolean) return String is
        ((if Signed then "int" else "uint") & Img (Storage_Bits (Bits)) & "_t");

      procedure Check_Name (It : Item) is
      begin
         if Is_Keyword (To_String (It.Name)) then
            raise Wire_Error with
              Img (It.Line) & ":" & Img (It.Col) & ": the field `"
              & To_String (It.Name) & "` is a C keyword, so it cannot be a "
              & "member of the struct; rename it (`"
              & To_String (It.Name) & "_` or a name from the RFC's own text)";
         end if;
      end Check_Name;

      ------------------------------------------------------------------------
      --  Types
      ------------------------------------------------------------------------

      function Members (S : Sequence; Ind : Natural) return String;
      function Choice_Body (Alts : Seq_Vectors.Vector; Ind : Natural)
        return String;

      function Pad (Ind : Natural) return String is ([1 .. 4 * Ind => ' ']);

      function Members (S : Sequence; Ind : Natural) return String is
         R : Unbounded_String;
      begin
         for It of S.Items loop
            if It.Kind not in S_Const | S_Assert then
               Check_Name (It.all);
            end if;
            declare
               N : constant String := To_String (It.Name);
            begin
               case It.Kind is
                  when S_Const | S_Assert => null;
                  when S_Bits =>
                     Append (R, Pad (Ind) & Int_Type (It.Bits, It.Signed)
                             & " " & N & ";" & ASCII.LF);
                  when S_Octets | S_Rest =>
                     Append (R, Pad (Ind) & Pfx & "octets_t " & N & ";"
                             & ASCII.LF);
                  when S_Bit_Expr =>
                     Append (R, Pad (Ind) & "uint64_t " & N & ";" & ASCII.LF);
                  when S_Ref =>
                     Append (R, Pad (Ind) & Type_Of (To_String (It.Ref)) & " "
                             & N & ";" & ASCII.LF);
                  when S_Array =>
                     Append (R, Pad (Ind) & "struct { "
                             & Type_Of (To_String (It.Ref)) & " *items; "
                             & "size_t n; } " & N & ";" & ASCII.LF);
                  when S_Choice =>
                     Append (R, Pad (Ind) & "struct {" & ASCII.LF
                             & Choice_Body (It.Alts, Ind + 1)
                             & Pad (Ind) & "} " & N & ";" & ASCII.LF);
               end case;
            end;
         end loop;
         if R = Null_Unbounded_String then
            Append (R, Pad (Ind) & "char unused_;" & ASCII.LF);
         end if;
         return To_String (R);
      end Members;

      function Choice_Body (Alts : Seq_Vectors.Vector; Ind : Natural)
        return String
      is
         R : Unbounded_String;
         K : Natural := 0;
      begin
         Append (R, Pad (Ind) & "int kind;   /* 1.." & Img (Natural (Alts.Length))
                 & ": the alternative that matched */" & ASCII.LF);
         Append (R, Pad (Ind) & "union {" & ASCII.LF);
         for A of Alts loop
            K := K + 1;
            Append (R, Pad (Ind + 1) & "struct {" & ASCII.LF
                    & Members (A.all, Ind + 2)
                    & Pad (Ind + 1) & "} a" & Img (K) & ";" & ASCII.LF);
         end loop;
         Append (R, Pad (Ind) & "} u;" & ASCII.LF);
         return To_String (R);
      end Choice_Body;

      --  Rules in an order where a record comes after the records it holds.
      Done : array (1 .. Natural (G.Rules.Length)) of Boolean :=
        [others => False];

      procedure Define (K : Positive);

      procedure Needs (Alts : Seq_Vectors.Vector) is
      begin
         for A of Alts loop
            for It of A.Items loop
               if It.Kind = S_Ref then
                  Define (Find (G, To_String (It.Ref)));
               elsif It.Kind = S_Choice then
                  Needs (It.Alts);
               end if;
            end loop;
         end loop;
      end Needs;

      procedure Define (K : Positive) is
         R : Rule renames G.Rules (K);
      begin
         if Done (K) then
            return;
         end if;
         Done (K) := True;
         if Is_Value_Set (R) then
            return;
         end if;
         Needs (R.Alts);
         if Natural (R.Alts.Length) = 1 then
            L (0, "struct " & Tag_Of (To_String (R.Name)) & " {");
            Put (Members (R.Alts.First_Element.all, 1));
         else
            L (0, "struct " & Tag_Of (To_String (R.Name)) & " {");
            Put (Choice_Body (R.Alts, 1));
         end if;
         L (0, "};");
         L (0, "");
      end Define;

      ------------------------------------------------------------------------
      --  Expressions
      ------------------------------------------------------------------------

      function Lookup (Scope : Binding_Vectors.Vector; N : String) return String
      is
      begin
         for K in reverse 1 .. Natural (Scope.Length) loop
            if To_String (Scope (K).Name) = N then
               return To_String (Scope (K).Lvalue);
            end if;
         end loop;
         return N;     --  Check_Expr has seen to it that this is not reached
      end Lookup;

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

      --  `remaining`: the bits left in the input.  It means something only
      --  while reading; a writer works out the input's size from the tree.
      function Expr_C (E : Expr_Access; Scope : Binding_Vectors.Vector)
        return String
      is
      begin
         case E.Kind is
            when E_Num =>
               return "((int64_t)" & Long_Long_Integer'Image (E.Value) & "LL)";
            when E_Var =>
               if To_String (E.Name) = "remaining" then
                  return "((int64_t)(p->nbits - p->bit))";
               end if;
               return "((int64_t)" & Lookup (Scope, To_String (E.Name)) & ")";
            when E_Call =>
               return "((int64_t)(" & Lookup (Scope, "*" & To_String (E.Arg))
                 & ".len))";
            when E_Unary =>
               return "(" & To_String (E.Un_Op) & Expr_C (E.Operand, Scope) & ")";
            when E_Binary =>
               declare
                  Op : constant String := To_String (E.Bin_Op);
                  A  : constant String := Expr_C (E.Left, Scope);
                  B  : constant String := Expr_C (E.Right, Scope);
               begin
                  if Op in "/" | "%" then
                     return "(" & B & " != 0 ? (" & A & " " & Op & " " & B
                       & ") : 0)";
                  elsif Op in "<<" | ">>" then
                     return "((int64_t)((uint64_t)" & A & " " & Op
                       & " (" & B & " & 63)))";
                  else
                     return "(" & A & " " & Op & " " & B & ")";
                  end if;
               end;
         end case;
      end Expr_C;

      --  A string for inside a C string literal.
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

      ------------------------------------------------------------------------
      --  Parse code
      ------------------------------------------------------------------------

      procedure Gen_Alts
        (Alts : Seq_Vectors.Vector; Lv : String; Scope : Binding_Vectors.Vector;
         Where : String; Fail : String; Ind : Natural);

      procedure Gen_Seq
        (S : Sequence; Lv : String; Scope_In : Binding_Vectors.Vector;
         Where : String; Fail : String; Ind : Natural)
      is
         Scope : Binding_Vectors.Vector := Scope_In;
         St    : constant String := "st" & Img (Next_Id) & "_";
      begin
         L (Ind, "size_t " & St & " = p->bit; (void)" & St & ";");
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
               Lw : constant String := Lv & N;
               U  : constant String := Img (Next_Id);
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "{ uint64_t v_; size_t s_ = p->bit;");
                     L (Ind + 1, "if (!bnf_rd (p, " & Img (It.Bits) & ", &v_, """
                       & Where & """)) { " & Fail & " }");
                     L (Ind + 1, "if (v_ != " & Hex (It.Value) & ") {");
                     L (Ind + 2, "bnf_fail (p, s_, """ & Where
                       & """, ""expected the constant " & Hex (It.Value)
                       & """); " & Fail);
                     L (Ind + 1, "}");
                     L (Ind, "}");
                  when S_Bits =>
                     L (Ind, "{ uint64_t v_; size_t s_ = p->bit; (void)s_;");
                     if It.At_Bit >= 0 and then not It.Static_Ok then
                        L (Ind + 1, "if (p->bit - " & St & " != "
                          & Img (It.At_Bit) & ") {");
                        L (Ind + 2, "bnf_fail (p, p->bit, " & W
                          & ", ""is not at bit " & Img (It.At_Bit)
                          & " of its record""); " & Fail);
                        L (Ind + 1, "}");
                     end if;
                     L (Ind + 1, "if (!bnf_rd (p, " & Img (It.Bits)
                       & ", &v_, " & W & ")) { " & Fail & " }");
                     if It.Little then
                        L (Ind + 1, "v_ = bnf_swap (v_, " & Img (It.Bits / 8)
                          & ");");
                     end if;
                     if It.Signed and then It.Bits < 64 then
                        L (Ind + 1, "v_ = (uint64_t)((int64_t)(v_ << "
                          & Img (64 - It.Bits) & ") >> " & Img (64 - It.Bits)
                          & ");");
                     end if;
                     if It.Ref /= Null_Unbounded_String then
                        L (Ind + 1, "if (!" & In_Of (To_String (It.Ref))
                          & " (v_)) {");
                        L (Ind + 2, "bnf_fail (p, s_, " & W
                          & ", ""is not one of the values the rule `"
                          & To_String (It.Ref) & "` lists""); " & Fail);
                        L (Ind + 1, "}");
                     end if;
                     L (Ind + 1, Lw & " = (" & Int_Type (It.Bits, It.Signed)
                       & ")v_;");
                     L (Ind, "}");
                     Scope.Append (Binding'(It.Name, To_Unbounded_String (Lw)));
                  when S_Assert =>
                     L (Ind, "if (!(" & Expr_C (It.Count, Scope) & ")) {");
                     L (Ind + 1, "bnf_fail (p, p->bit, """ & Where
                       & """, ""a condition does not hold: "
                       & Escape (Expr_Text (It.Count)) & """); " & Fail);
                     L (Ind, "}");
                  when S_Octets =>
                     L (Ind, "{ int64_t n_ = " & Expr_C (It.Count, Scope) & ";");
                     L (Ind + 1, "if (n_ < 0) { bnf_fail (p, p->bit, " & W
                       & ", ""has a negative length""); " & Fail & " }");
                     L (Ind + 1, "if (!bnf_take (p, (size_t)n_, &" & Lw & ", "
                       & W & ")) { " & Fail & " }");
                     L (Ind, "}");
                     Scope.Append
                       (Binding'("*" & It.Name, To_Unbounded_String (Lw)));
                  when S_Rest =>
                     L (Ind, "if (!bnf_take_rest (p, &" & Lw & ", " & W
                       & ")) { " & Fail & " }");
                     Scope.Append
                       (Binding'("*" & It.Name, To_Unbounded_String (Lw)));
                  when S_Bit_Expr =>
                     L (Ind, "{ int64_t n_ = " & Expr_C (It.Count, Scope)
                       & "; uint64_t v_;");
                     L (Ind + 1, "if (n_ < 0 || n_ > 64) { bnf_fail (p, p->bit, "
                       & W & ", ""has a width outside 0..64 bits""); " & Fail
                       & " }");
                     L (Ind + 1, "if (!bnf_rd (p, (unsigned)n_, &v_, " & W
                       & ")) { " & Fail & " }");
                     L (Ind + 1, Lw & " = v_;");
                     L (Ind, "}");
                     Scope.Append (Binding'(It.Name, To_Unbounded_String (Lw)));
                  when S_Ref =>
                     L (Ind, "if (!" & Fn_Of (To_String (It.Ref)) & " (p, &"
                       & Lw & ")) { " & Fail & " }");
                  when S_Array =>
                     declare
                        R   : constant String := To_String (It.Ref);
                        Mn  : constant String :=
                          (if It.Count /= null then "cnt_" else Img (It.Min));
                        Mx  : constant String :=
                          (if It.Count /= null then "cnt_" else Img (It.Max));
                     begin
                        L (Ind, "{ size_t n_ = 0, cap_ = 0; " & Type_Of (R)
                          & " *a_ = NULL;");
                        if It.Count /= null then
                           L (Ind + 1, "int64_t cnt_ = "
                             & Expr_C (It.Count, Scope) & ";");
                           L (Ind + 1, "if (cnt_ < 0) { bnf_fail (p, p->bit, "
                             & W & ", ""has a negative count""); " & Fail
                             & " }");
                        end if;
                        L (Ind + 1, "for (;;) {");
                        L (Ind + 2, "size_t s_ = p->bit; " & Type_Of (R)
                          & " t_;");
                        L (Ind + 2, "if (" & Mx & " >= 0 && (int64_t)n_ >= "
                          & Mx & ") break;");
                        L (Ind + 2, "if ((int64_t)n_ >= " & Mn
                          & " && p->bit >= p->len * 8) break;");
                        L (Ind + 2, "memset (&t_, 0, sizeof t_);");
                        L (Ind + 2, "if (!" & Fn_Of (R) & " (p, &t_)) {");
                        L (Ind + 3, "p->bit = s_;");
                        L (Ind + 3, "if ((int64_t)n_ < " & Mn & ") { " & Fail
                          & " }");
                        L (Ind + 3, "break;");
                        L (Ind + 2, "}");
                        L (Ind + 2, "if (p->bit == s_) break;");
                        L (Ind + 2, "if (n_ == cap_) {");
                        L (Ind + 3, "cap_ = cap_ ? cap_ * 2 : 8;");
                        L (Ind + 3, "a_ = (" & Type_Of (R)
                          & " *)bnf_grow (a_, n_, cap_, sizeof *a_);");
                        L (Ind + 2, "}");
                        L (Ind + 2, "a_[n_++] = t_;");
                        L (Ind + 1, "}");
                        L (Ind + 1, "if ((int64_t)n_ < " & Mn & ") { "
                          & "bnf_fail (p, p->bit, " & W
                          & ", ""has too few entries""); " & Fail & " }");
                        L (Ind + 1, Lw & ".items = a_; " & Lw & ".n = n_;");
                        L (Ind, "}");
                     end;
                  when S_Choice =>
                     Gen_Alts (It.Alts, Lw & ".", Scope, Where & "." & N, Fail,
                               Ind);
               end case;
               pragma Unreferenced (U);
            end;
         end loop;
      end Gen_Seq;

      procedure Gen_Alts
        (Alts : Seq_Vectors.Vector; Lv : String; Scope : Binding_Vectors.Vector;
         Where : String; Fail : String; Ind : Natural)
      is
         D : constant String := Img (Next_Id);
         K : Natural := 0;
      begin
         L (Ind, "{ size_t c" & D & "_ = p->bit;");
         for A of Alts loop
            K := K + 1;
            declare
               F : constant String := "alt" & D & "_" & Img (K);
               Goto_Fail : constant String := "goto " & F & ";";
               Sub : constant String := Lv & "u.a" & Img (K) & ".";
            begin
               L (Ind + 1, "{");
               if A.Guard /= null then
                  L (Ind + 2, "if (!(" & Expr_C (A.Guard, Scope) & ")) "
                    & Goto_Fail);
               end if;
               Gen_Seq (A.all, Sub, Scope, Where, Goto_Fail, Ind + 2);
               L (Ind + 2, Lv & "kind = " & Img (K) & ";");
               L (Ind + 2, "goto done" & D & "_;");
               L (Ind + 1, "}");
               L (Ind + 1, F & ": p->bit = c" & D & "_;");
            end;
         end loop;
         L (Ind + 1, "bnf_fail (p, p->bit, """ & Where
           & """, ""none of the alternatives matches here""); " & Fail);
         L (Ind, "}");
         L (Ind, "done" & D & "_: ;");
      end Gen_Alts;

      ------------------------------------------------------------------------
      --  Emit code: a tree back to bytes
      ------------------------------------------------------------------------

      procedure Gen_Emit_Alts
        (Alts : Seq_Vectors.Vector; Lv : String; Scope : Binding_Vectors.Vector;
         Where : String; Ind : Natural);

      procedure Gen_Emit_Seq
        (S : Sequence; Lv : String; Scope_In : Binding_Vectors.Vector;
         Where : String; Ind : Natural)
      is
         Scope : Binding_Vectors.Vector := Scope_In;
         St    : constant String := "st" & Img (Next_Id) & "_";
         Bad   : constant String := "return false;";
      begin
         L (Ind, "size_t " & St & " = w->bit; (void)" & St & ";");
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
               Lw : constant String := Lv & N;
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "bnf_wr (w, " & Img (It.Bits) & ", "
                       & Hex (It.Value) & ");");
                  when S_Bits =>
                     L (Ind, "{ uint64_t v_;");
                     if It.At_Bit >= 0 and then not It.Static_Ok then
                        L (Ind + 1, "if (w->bit - " & St & " != "
                          & Img (It.At_Bit) & ") { bnf_wfail (w, " & W
                          & ", ""is not at bit " & Img (It.At_Bit)
                          & " of its record""); " & Bad & " }");
                     end if;
                     if It.Signed then
                        L (Ind + 1, "int64_t sv_ = " & Lw & ";");
                        if It.Bits < 64 then
                           L (Ind + 1, "if (sv_ < -((int64_t)1 << "
                             & Img (It.Bits - 1) & ") || sv_ >= ((int64_t)1 << "
                             & Img (It.Bits - 1) & ")) {");
                           L (Ind + 2, "bnf_wfail (w, " & W & ", ""does not "
                             & "fit in " & Img (It.Bits) & " bits (signed)""); "
                             & Bad);
                           L (Ind + 1, "}");
                           L (Ind + 1, "v_ = (uint64_t)sv_ & ((((uint64_t)1 << "
                             & Img (It.Bits) & ") - 1));");
                        else
                           L (Ind + 1, "v_ = (uint64_t)sv_;");
                        end if;
                     else
                        L (Ind + 1, "v_ = (uint64_t)" & Lw & ";");
                        if It.Bits < 64 then
                           L (Ind + 1, "if (v_ >> " & Img (It.Bits) & ") {");
                           L (Ind + 2, "bnf_wfail (w, " & W & ", ""does not "
                             & "fit in " & Img (It.Bits) & " bits""); " & Bad);
                           L (Ind + 1, "}");
                        end if;
                     end if;
                     if It.Ref /= Null_Unbounded_String then
                        L (Ind + 1, "if (!" & In_Of (To_String (It.Ref))
                          & " (v_)) {");
                        L (Ind + 2, "bnf_wfail (w, " & W & ", ""is not one of "
                          & "the values the rule `" & To_String (It.Ref)
                          & "` lists""); " & Bad);
                        L (Ind + 1, "}");
                     end if;
                     if It.Little then
                        L (Ind + 1, "v_ = bnf_swap (v_, " & Img (It.Bits / 8)
                          & ");");
                     end if;
                     L (Ind + 1, "bnf_wr (w, " & Img (It.Bits) & ", v_);");
                     L (Ind, "}");
                     Scope.Append (Binding'(It.Name, To_Unbounded_String (Lw)));
                  when S_Assert =>
                     if not Uses_Remaining (It.Count) then
                        L (Ind, "if (!(" & Expr_C (It.Count, Scope) & ")) {");
                        L (Ind + 1, "bnf_wfail (w, """ & Where
                          & """, ""a condition does not hold: "
                          & Escape (Expr_Text (It.Count)) & """); " & Bad);
                        L (Ind, "}");
                     end if;
                  when S_Octets =>
                     if not Uses_Remaining (It.Count) then
                        L (Ind, "if ((int64_t)" & Lw & ".len != "
                          & Expr_C (It.Count, Scope) & ") {");
                        L (Ind + 1, "bnf_wfail (w, " & W & ", ""has a "
                          & "different number of octets than its length "
                          & "says""); " & Bad);
                        L (Ind, "}");
                     end if;
                     L (Ind, "if (!bnf_wput (w, " & Lw & ".ptr, " & Lw
                       & ".len, " & W & ")) " & Bad);
                     Scope.Append
                       (Binding'("*" & It.Name, To_Unbounded_String (Lw)));
                  when S_Rest =>
                     L (Ind, "if (!bnf_wput (w, " & Lw & ".ptr, " & Lw
                       & ".len, " & W & ")) " & Bad);
                     Scope.Append
                       (Binding'("*" & It.Name, To_Unbounded_String (Lw)));
                  when S_Bit_Expr =>
                     if Uses_Remaining (It.Count) then
                        --  The width is the bits that are left, which a
                        --  writer does not know until it has written them.
                        L (Ind, "bnf_wfail (w, " & W & ", ""has a width "
                          & "that depends on the size of the input, which "
                          & "a writer does not know yet""); " & Bad);
                     else
                        L (Ind, "{ int64_t n_ = " & Expr_C (It.Count, Scope)
                          & ";");
                        L (Ind + 1, "if (n_ < 0 || n_ > 64 || (n_ < 64 && ("
                          & "(uint64_t)" & Lw & " >> n_))) {");
                        L (Ind + 2, "bnf_wfail (w, " & W & ", ""does not fit "
                          & "in the number of bits its width field says""); "
                          & Bad);
                        L (Ind + 1, "}");
                        L (Ind + 1, "bnf_wr (w, (unsigned)n_, " & Lw & ");");
                        L (Ind, "}");
                     end if;
                     Scope.Append (Binding'(It.Name, To_Unbounded_String (Lw)));
                  when S_Ref =>
                     L (Ind, "if (!emit_rule_" & To_String (It.Ref) & " (w, &"
                       & Lw & ")) " & Bad);
                  when S_Array =>
                     L (Ind, "{ size_t i_;");
                     if It.Count /= null then
                        L (Ind + 1, "if ((int64_t)" & Lw & ".n != "
                          & Expr_C (It.Count, Scope) & ") {");
                        L (Ind + 2, "bnf_wfail (w, " & W & ", ""has a "
                          & "different number of entries than its count "
                          & "says""); " & Bad);
                        L (Ind + 1, "}");
                     else
                        L (Ind + 1, "if (" & Lw & ".n < " & Img (It.Min)
                          & (if It.Max >= 0
                             then " || " & Lw & ".n > " & Img (It.Max) else "")
                          & ") {");
                        L (Ind + 2, "bnf_wfail (w, " & W & ", ""has a number "
                          & "of entries outside " & Img (It.Min) & ".."
                          & (if It.Max >= 0 then Img (It.Max) else "")
                          & """); " & Bad);
                        L (Ind + 1, "}");
                     end if;
                     L (Ind + 1, "for (i_ = 0; i_ < " & Lw & ".n; i_++)");
                     L (Ind + 2, "if (!emit_rule_" & To_String (It.Ref)
                       & " (w, &" & Lw & ".items[i_])) " & Bad);
                     L (Ind, "}");
                  when S_Choice =>
                     Gen_Emit_Alts (It.Alts, Lw & ".", Scope,
                                    Where & "." & N, Ind);
               end case;
            end;
         end loop;
      end Gen_Emit_Seq;

      procedure Gen_Emit_Alts
        (Alts : Seq_Vectors.Vector; Lv : String; Scope : Binding_Vectors.Vector;
         Where : String; Ind : Natural)
      is
         K : Natural := 0;
      begin
         L (Ind, "{");
         for A of Alts loop
            K := K + 1;
            L (Ind + 1, (if K > 1 then "else " else "") & "if (" & Lv
              & "kind == " & Img (K) & ") {");
            if A.Guard /= null then
               L (Ind + 2, "if (!(" & Expr_C (A.Guard, Scope) & ")) {");
               L (Ind + 3, "bnf_wfail (w, """ & Where & """, ""alternative "
                 & Img (K) & " is chosen, but its guard does not hold""); "
                 & "return false;");
               L (Ind + 2, "}");
            end if;
            Gen_Emit_Seq (A.all, Lv & "u.a" & Img (K) & ".", Scope, Where,
                          Ind + 2);
            L (Ind + 1, "}");
         end loop;
         L (Ind + 1, "else {");
         L (Ind + 2, "bnf_wfail (w, """ & Where & """, ""kind is not the "
           & "number of an alternative (1.." & Img (Natural (Alts.Length))
           & ")""); return false;");
         L (Ind + 1, "}");
         L (Ind, "}");
      end Gen_Emit_Alts;

      procedure Runtime is
      begin
         L (0, "typedef struct {");
         L (1, "const uint8_t *buf;");
         L (1, "size_t len;        /* octets */");
         L (1, "size_t nbits;      /* bits: the input need not be whole octets */");
         L (1, "size_t bit;        /* 0 is the most significant bit of buf[0] */");
         L (1, "size_t fail_bit;   /* the deepest place a read failed */");
         L (1, "int failed;");
         L (1, "char msg[256];");
         L (0, "} bnf_p;");
         L (0, "");
         L (0, "static void *bnf_blocks;");
         L (0, "static void *bnf_alloc (size_t n) {");
         L (1, "char *b = (char *)calloc (1, n + 16);");
         L (1, "if (!b) { fputs (""hbnf: out of memory\n"", stderr); exit (1); }");
         L (1, "*(void **)b = bnf_blocks;  bnf_blocks = b;");
         L (1, "return b + 16;");
         L (0, "}");
         L (0, "void free_arena (void) {");
         L (1, "while (bnf_blocks) {");
         L (2, "void *n = *(void **)bnf_blocks;");
         L (2, "free (bnf_blocks);  bnf_blocks = n;");
         L (1, "}");
         L (0, "}");
         L (0, "static void *bnf_grow (void *old, size_t n, size_t cap, "
            & "size_t sz) {");
         L (1, "void *r = bnf_alloc (cap * sz);");
         L (1, "if (n) memcpy (r, old, n * sz);");
         L (1, "return r;");
         L (0, "}");
         L (0, "");
         L (0, "static void bnf_fail (bnf_p *p, size_t bit, const char *where,"
            & " const char *what) {");
         L (1, "if (p->failed && bit <= p->fail_bit) return;");
         L (1, "p->failed = 1;  p->fail_bit = bit;");
         L (1, "snprintf (p->msg, sizeof p->msg, ""%s: %s"", where, what);");
         L (0, "}");
         L (0, "");
         L (0, "/* n bits (at most 64), first bit in the most significant place. */");
         L (0, "static bool bnf_rd (bnf_p *p, unsigned n, uint64_t *v, "
            & "const char *where) {");
         L (1, "size_t left = p->nbits - p->bit;");
         L (1, "uint64_t x = 0;");
         L (1, "unsigned got = 0;");
         L (1, "if (n > left) {");
         L (2, "char t[64];");
         L (2, "snprintf (t, sizeof t, ""needs %u bits, %zu left"", n, left);");
         L (2, "bnf_fail (p, p->bit, where, t);");
         L (2, "return false;");
         L (1, "}");
         L (1, "while (got < n) {");
         L (2, "size_t byte = p->bit >> 3;");
         L (2, "unsigned off = (unsigned)(p->bit & 7), take = 8 - off;");
         L (2, "if (take > n - got) take = n - got;");
         L (2, "x = (x << take) | (((unsigned)p->buf[byte] >> (8 - off - take))"
            & " & ((1u << take) - 1));");
         L (2, "p->bit += take;  got += take;");
         L (1, "}");
         L (1, "*v = x;");
         L (1, "return true;");
         L (0, "}");
         L (0, "static uint64_t bnf_swap (uint64_t v, unsigned nbytes) {");
         L (1, "uint64_t r = 0;");
         L (1, "for (unsigned i = 0; i < nbytes; i++) {");
         L (2, "r = (r << 8) | (v & 0xFF);  v >>= 8;");
         L (1, "}");
         L (1, "return r;");
         L (0, "}");
         L (0, "static bool bnf_take (bnf_p *p, size_t n, " & Pfx
            & "octets_t *o, const char *where) {");
         L (1, "if (n > (p->nbits - p->bit) / 8) {");
         L (2, "char t[64];");
         L (2, "snprintf (t, sizeof t, ""needs %zu octets, %zu bits left"", n, "
            & "p->nbits - p->bit);");
         L (2, "bnf_fail (p, p->bit, where, t);");
         L (2, "return false;");
         L (1, "}");
         L (1, "if ((p->bit & 7) == 0) {");
         L (2, "o->ptr = p->buf + p->bit / 8;  o->len = n;");
         L (2, "p->bit += n * 8;");
         L (2, "return true;");
         L (1, "}");
         L (1, "/* The octets start inside a byte (after a 5-bit field, say): they"
            & " are not a slice of the input, so they are copied. */");
         L (1, "{");
         L (2, "uint8_t *c = (uint8_t *)bnf_alloc (n ? n : 1);");
         L (2, "for (size_t i = 0; i < n; i++) {");
         L (3, "uint64_t v;");
         L (3, "bnf_rd (p, 8, &v, where);");
         L (3, "c[i] = (uint8_t)v;");
         L (2, "}");
         L (2, "o->ptr = c;  o->len = n;");
         L (1, "}");
         L (1, "return true;");
         L (0, "}");
         L (0, "static bool bnf_take_rest (bnf_p *p, " & Pfx
            & "octets_t *o, const char *where) {");
         L (1, "return bnf_take (p, (p->nbits - p->bit) / 8, o, where);");
         L (0, "}");
         L (0, "");
         L (0, "/* The other direction: a tree to bytes.  With buf NULL it only"
            & " counts. */");
         L (0, "typedef struct {");
         L (1, "uint8_t *buf;");
         L (1, "size_t cap;");
         L (1, "size_t bit;");
         L (1, "int failed;");
         L (1, "char msg[256];");
         L (0, "} bnf_w;");
         L (0, "static void bnf_wfail (bnf_w *w, const char *where, const char"
            & " *what) {");
         L (1, "if (w->failed) return;");
         L (1, "w->failed = 1;");
         L (1, "snprintf (w->msg, sizeof w->msg, ""%s: %s"", where, what);");
         L (0, "}");
         L (0, "static void bnf_wr (bnf_w *w, unsigned n, uint64_t v) {");
         L (1, "unsigned put = 0;");
         L (1, "while (put < n) {");
         L (2, "size_t byte = w->bit >> 3;");
         L (2, "unsigned off = (unsigned)(w->bit & 7), take = 8 - off;");
         L (2, "unsigned chunk;");
         L (2, "if (take > n - put) take = n - put;");
         L (2, "chunk = (unsigned)((v >> (n - put - take)) & ((1u << take) - 1));");
         L (2, "if (w->buf && byte < w->cap) {");
         L (3, "if (off == 0) w->buf[byte] = 0;");
         L (3, "w->buf[byte] |= (uint8_t)(chunk << (8 - off - take));");
         L (2, "}");
         L (2, "w->bit += take;  put += take;");
         L (1, "}");
         L (0, "}");
         L (0, "static bool bnf_wput (bnf_w *w, const uint8_t *p, size_t n, "
            & "const char *where) {");
         L (1, "(void)where;");
         L (1, "if ((w->bit & 7) == 0) {");
         L (2, "if (w->buf && w->bit / 8 + n <= w->cap && n) "
            & "memcpy (w->buf + w->bit / 8, p, n);");
         L (2, "w->bit += n * 8;");
         L (1, "} else {");
         L (2, "for (size_t i = 0; i < n; i++) bnf_wr (w, 8, p[i]);");
         L (1, "}");
         L (1, "return true;");
         L (0, "}");
      end Runtime;

      Root : constant Natural := 1;
   begin
      if Is_Value_Set (G.Rules (Root)) then
         raise Wire_Error with
           "the first rule, `" & To_String (G.Rules (Root).Name)
           & "`, is a list of constants; parse_bytes reads the first rule, "
           & "which should be the whole message";
      end if;

      L (0, "/* generated by hbnf (binary) -- do not edit */");
      L (0, "#include <stdint.h>");
      L (0, "#include <stdbool.h>");
      L (0, "#include <stddef.h>");
      L (0, "#include <stdio.h>");
      L (0, "#include <stdlib.h>");
      L (0, "#include <string.h>");
      L (0, "");
      L (0, "/* A run of octets: a slice of the input, not a copy. */");
      L (0, "typedef struct { const uint8_t *ptr; size_t len; } " & Pfx
         & "octets_t;");
      L (0, "");

      --  Typedefs first, so a record may point at one defined later.
      for R of G.Rules loop
         if Is_Value_Set (R) then
            L (0, "typedef " & Int_Type (Value_Width (R), False) & " "
               & Type_Of (To_String (R.Name)) & ";");
         else
            L (0, "typedef struct " & Tag_Of (To_String (R.Name)) & " "
               & Type_Of (To_String (R.Name)) & ";");
         end if;
      end loop;
      L (0, "");
      for K in 1 .. Natural (G.Rules.Length) loop
         Define (K);
      end loop;

      Runtime;

      for R of G.Rules loop
         if Is_Value_Set (R) then
            L (0, "static bool " & In_Of (To_String (R.Name))
               & " (uint64_t v);");
         else
            L (0, "static bool " & Fn_Of (To_String (R.Name)) & " (bnf_p *p, "
               & Type_Of (To_String (R.Name)) & " *out);");
            L (0, "static bool emit_rule_" & To_String (R.Name)
               & " (bnf_w *w, const " & Type_Of (To_String (R.Name))
               & " *in);");
         end if;
      end loop;
      L (0, "");

      for R of G.Rules loop
         declare
            Nm : constant String := To_String (R.Name);
            Empty : Binding_Vectors.Vector;
         begin
            if Is_Value_Set (R) then
               declare
                  First : Boolean := True;
                  T : Unbounded_String;
               begin
                  for A of R.Alts loop
                     if not First then
                        Append (T, " || ");
                     end if;
                     First := False;
                     Append (T, "v == " & Hex (A.Items.First_Element.Value));
                  end loop;
                  L (0, "static bool " & In_Of (Nm) & " (uint64_t v) {");
                  L (1, "return " & To_String (T) & ";");
                  L (0, "}");
               end;
            else
               L (0, "static bool " & Fn_Of (Nm) & " (bnf_p *p, "
                  & Type_Of (Nm) & " *out) {");
               if Natural (R.Alts.Length) = 1 then
                  Gen_Seq (R.Alts.First_Element.all, "out->", Empty, Nm,
                           "return false;", 1);
               else
                  Gen_Alts (R.Alts, "out->", Empty, Nm, "return false;", 1);
               end if;
               L (1, "return true;");
               L (0, "}");
               L (0, "static bool emit_rule_" & Nm & " (bnf_w *w, const "
                  & Type_Of (Nm) & " *in) {");
               if Natural (R.Alts.Length) = 1 then
                  Gen_Emit_Seq (R.Alts.First_Element.all, "in->", Empty, Nm, 1);
               else
                  Gen_Emit_Alts (R.Alts, "in->", Empty, Nm, 1);
               end if;
               L (1, "return true;");
               L (0, "}");
            end if;
            L (0, "");
         end;
      end loop;

      declare
         Rt : constant String := To_String (G.Rules (Root).Name);
      begin
         L (0, "/* Read nbits bits of buf as one " & Rt & ".  On success all of"
            & " them were used and the strings of octets in *out point into buf"
            & " (or, when they start inside a byte, into the arena). */");
         L (0, "bool parse_bits (const uint8_t *buf, size_t nbits, "
            & Type_Of (Rt) & " *out,");
         L (0, "                 char *err, size_t errsz, size_t *at) {");
         L (1, "bnf_p p;");
         L (1, "memset (&p, 0, sizeof p);");
         L (1, "p.buf = buf;  p.nbits = nbits;  p.len = (nbits + 7) / 8;");
         L (1, "memset (out, 0, sizeof *out);");
         L (1, "if (!" & Fn_Of (Rt) & " (&p, out)) goto bad;");
         L (1, "if (p.bit != nbits) {");
         L (2, "char t[64];");
         L (2, "p.failed = 0;");
         L (2, "snprintf (t, sizeof t, ""%zu bit(s) left over after the "
            & "message"", nbits - p.bit);");
         L (2, "bnf_fail (&p, p.bit, """ & Rt & """, t);");
         L (2, "goto bad;");
         L (1, "}");
         L (1, "return true;");
         L (0, "bad:");
         L (1, "if (at) *at = p.fail_bit / 8;");
         L (1, "if (err && errsz) snprintf (err, errsz, ""octet %zu: %s"", "
            & "p.fail_bit / 8, p.msg);");
         L (1, "return false;");
         L (0, "}");
         L (0, "bool parse_bytes (const uint8_t *buf, size_t len, "
            & Type_Of (Rt) & " *out,");
         L (0, "                  char *err, size_t errsz, size_t *at) {");
         L (1, "return parse_bits (buf, len * 8, out, err, errsz, at);");
         L (0, "}");
         L (0, "");
         L (0, "/* Write *in as bits.  *nbits is the number of bits it takes, "
            & "even when buf is NULL or too small (then false, as snprintf's"
            & " count).  A value that does not fit its field, or does not "
            & "agree with a length or tag field, is an error, not a guess. */");
         L (0, "bool emit_bits (const " & Type_Of (Rt) & " *in, uint8_t *buf,"
            & " size_t cap, size_t *nbits,");
         L (0, "                char *err, size_t errsz) {");
         L (1, "bnf_w w;");
         L (1, "memset (&w, 0, sizeof w);");
         L (1, "w.buf = buf;  w.cap = cap;");
         L (1, "(void)bnf_swap;  (void)bnf_grow;  (void)bnf_take_rest;");
         L (1, "if (!emit_rule_" & Rt & " (&w, in)) goto bad;");
         L (1, "if (nbits) *nbits = w.bit;");
         L (1, "if (buf && (w.bit + 7) / 8 > cap) {");
         L (2, "bnf_wfail (&w, """ & Rt & """, ""the buffer is too small"");");
         L (2, "goto bad;");
         L (1, "}");
         L (1, "return true;");
         L (0, "bad:");
         L (1, "if (nbits) *nbits = w.bit;");
         L (1, "if (err && errsz) snprintf (err, errsz, ""%s"", w.msg);");
         L (1, "return false;");
         L (0, "}");
         L (0, "/* The same, for a message that is whole octets. */");
         L (0, "bool emit_bytes (const " & Type_Of (Rt) & " *in, uint8_t *buf,"
            & " size_t cap, size_t *n,");
         L (0, "                 char *err, size_t errsz) {");
         L (1, "size_t nb = 0;");
         L (1, "bool ok = emit_bits (in, buf, cap, &nb, err, errsz);");
         L (1, "if (ok && (nb & 7)) {");
         L (2, "if (err && errsz) snprintf (err, errsz, """ & Rt
            & ": the message does not end on an octet boundary"");");
         L (2, "ok = false;");
         L (1, "}");
         L (1, "if (n) *n = (nb + 7) / 8;");
         L (1, "return ok;");
         L (0, "}");
      end;
      return To_String (Buf);
   end Emit;

end HBNF_Wire.C;
