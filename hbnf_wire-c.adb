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

   --  The wire emitter, in one of two forms.  On its own (Hosted False) it makes
   --  a file: types, a reader and a writer over a buffer of bits.  Hosted, the
   --  bit rules live in a text parser: they read the text parser's input at its
   --  position (octet and bit offset), fail through its error record, and
   --  allocate from its arena, and only the types and the readers are made.
   --  Types is everything up to and including the declarations; Code the rest.
   procedure Generate
     (G : Grammar; Hosted : Boolean; Types, Code : out Unbounded_String)
   is
      Buf : Unbounded_String;
      Types_End : Natural := 0;
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
                     if not It.Bitsof then
                        Append (R, Pad (Ind) & Type_Of (To_String (It.Ref)) & " "
                                & N & ";" & ASCII.LF);
                     end if;
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
               if It.Kind = S_Ref and then Find (G, To_String (It.Ref)) /= 0 then
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
         if K = 1 then
            L (1, "/* what the read has to say, besides failing: `warn (...)`. */");
            L (1, "const char *warnings[8];");
            L (1, "unsigned nwarnings;");
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

      --  S with its `@` replaced by With_Text.
      function Replace_At (S, With_Text : String) return String is
         R : Unbounded_String;
      begin
         for C of S loop
            if C = '@' then
               Append (R, With_Text);
            else
               Append (R, C);
            end if;
         end loop;
         return To_String (R);
      end Replace_At;

      --  True while the code for the writer is being made.
      Emit_Side : Boolean := False;

      --  The width of a unit while the rest of a sequence reads the numbered
      --  words of a `name:bitsof(rule)` field; 0 otherwise (`align`).
      Unit_W : Natural := 0;

      --  A rule with a `bitsof` field in the sequence of one of its
      --  alternatives: its reader is wrapped to put the input back.
      function Has_Words (R : Rule) return Boolean is
        (for some A of R.Alts => (for some X of A.Items => X.Bitsof));

      Any_Words : constant Boolean := (for some R of G.Rules => Has_Words (R));

      --  `remaining`: the bits left in the input.  It means something only
      --  while reading; a writer works out the input's size from the tree.
      --  `align`: the bits to the next unit boundary, from where the reader
      --  or the writer is.
      function Expr_C (E : Expr_Access; Scope : Binding_Vectors.Vector)
        return String
      is
      begin
         case E.Kind is
            when E_Num =>
               return "((int64_t)" & Long_Long_Integer'Image (E.Value) & "LL)";
            when E_Var =>
               if To_String (E.Name) = "remaining" then
                  return "((int64_t)(WN(p) - WB(p)))";
               elsif To_String (E.Name) = "align" then
                  declare
                     W : constant String := Img (Unit_W);
                     B : constant String := (if Emit_Side then "w->bit"
                                             else "WB(p)");
                  begin
                     return "((int64_t)((" & W & " - " & B & " % " & W
                       & ") % " & W & "))";
                  end;
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
         Unit_Saved : constant Natural := Unit_W;
      begin
         L (Ind, "size_t " & St & " = WB(p); (void)" & St & ";");
         for It of S.Items loop
            declare
               N  : constant String := To_String (It.Name);
               W  : constant String := """" & Where & "." & N & """";
               Lw : constant String := Lv & N;
               U  : constant String := Img (Next_Id);
            begin
               case It.Kind is
                  when S_Const =>
                     L (Ind, "{ uint64_t v_; size_t s_ = WB(p);");
                     L (Ind + 1, "if (!bnf_rd (p, " & Img (It.Bits) & ", &v_, """
                       & Where & """)) { " & Fail & " }");
                     L (Ind + 1, "if (v_ != " & Hex (It.Value) & ") {");
                     L (Ind + 2, "bnf_fail (p, s_, """ & Where
                       & """, ""expected the constant " & Hex (It.Value)
                       & """); " & Fail);
                     L (Ind + 1, "}");
                     L (Ind, "}");
                  when S_Bits =>
                     L (Ind, "{ uint64_t v_; size_t s_ = WB(p); (void)s_;");
                     if It.At_Bit >= 0 and then not It.Static_Ok then
                        L (Ind + 1, "if (WB(p) - " & St & " != "
                          & Img (It.At_Bit) & ") {");
                        L (Ind + 2, "bnf_fail (p, WB(p), " & W
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
                     L (Ind + 1, "bnf_fail (p, WB(p), """ & Where
                       & """, """
                       & (if It.Ref /= Null_Unbounded_String
                          then Escape (To_String (It.Ref))
                          else "a condition does not hold: "
                               & Escape (Expr_Text (It.Count)))
                       & """); " & Fail);
                     L (Ind, "}");
                  when S_Octets =>
                     L (Ind, "{ int64_t n_ = " & Expr_C (It.Count, Scope) & ";");
                     L (Ind + 1, "if (n_ < 0) { bnf_fail (p, WB(p), " & W
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
                     L (Ind + 1, "if (n_ < 0 || n_ > 64) { bnf_fail (p, WB(p), "
                       & W & ", ""has a width outside 0..64 bits""); " & Fail
                       & " }");
                     L (Ind + 1, "if (!bnf_rd (p, (unsigned)n_, &v_, " & W
                       & ")) { " & Fail & " }");
                     L (Ind + 1, Lw & " = v_;");
                     L (Ind, "}");
                     Scope.Append (Binding'(It.Name, To_Unbounded_String (Lw)));
                  when S_Ref =>
                     if It.Bitsof then
                        --  The text rule is read; its numbered words become
                        --  the bits the rest of the sequence reads, and the
                        --  reader's wrapper (bnf_words_end) puts the input
                        --  back.
                        declare
                           K  : constant String := Img (It.Ord);
                           Fr : constant String :=
                             (if It.Tmp_Free = Null_Unbounded_String then ""
                              else Replace_At (To_String (It.Tmp_Free),
                                               "&t_") & " ");
                        begin
                           L (Ind, "{ bnf_save s2_ = bnf_enter (p);  bool ok_;");
                           L (Ind + 1, To_String (It.Tmp_Type) & " t_;");
                           L (Ind + 1, "uint8_t *wb_ = NULL;  size_t wn_ = 0;"
                              & "  size_t st_ = p->pos;");
                           L (Ind + 1, "if (p->sv.active) { bnf_leave (p, s2_, "
                              & "false); bnf_fail (p, WB(p), " & W
                              & ", ""a bitsof inside a bitsof""); " & Fail
                              & " }");
                           L (Ind + 1, "memset (&t_, 0, sizeof t_);");
                           L (Ind + 1, "ok_ = " & Fn_Of (To_String (It.Ref))
                              & " (p, &t_);");
                           L (Ind + 1, "if (ok_) { " & Fr
                              & "ok_ = bnf_words (p, st_, p->pos, "
                              & Img (It.Width) & ", bnf_word_" & K
                              & ", &wb_, &wn_); }");
                           L (Ind + 1, "bnf_leave (p, s2_, ok_);");
                           L (Ind + 1, "if (!ok_) { " & Fail & " }");
                           L (Ind + 1, "bnf_srcset (p, wb_, wn_, "
                              & Img (It.Width) & ", s2_.pos);");
                           L (Ind, "}");
                        end;
                        Unit_W := It.Width;
                     elsif Hosted and then Find (G, To_String (It.Ref)) = 0
                       and then (for some X of G.External_Tokens =>
                                   X = It.Ref)
                     then
                        --  A text token has a scanner, not a reader: its
                        --  value is the text it matched.  Its octets are
                        --  read from wherever the position is, bit by bit if
                        --  that is inside an octet (bnf_enter).
                        L (Ind, "{ bnf_save s_ = bnf_enter (p);");
                        L (Ind + 1, "size_t n_ = scan_" & To_String (It.Ref)
                          & "(p->text, p->pos, p->len);");
                        L (Ind + 1, "if (n_) { " & Lw
                          & " = hbnf_str_append (p->text + p->pos, n_);"
                          & "  p->pos += n_; }");
                        L (Ind + 1, "bnf_leave (p, s_, n_ != 0);");
                        L (Ind + 1, "if (!n_) { bnf_fail (p, WB(p), " & W
                          & ", ""a " & To_String (It.Ref) & """); "
                          & Fail & " }");
                        L (Ind, "}");
                     elsif Hosted and then Find (G, To_String (It.Ref)) = 0
                     then
                        L (Ind, "{ bnf_save s_ = bnf_enter (p);  bool ok_ = "
                          & Fn_Of (To_String (It.Ref)) & " (p, &" & Lw & ");");
                        L (Ind + 1, "bnf_leave (p, s_, ok_);");
                        L (Ind + 1, "if (!ok_) { " & Fail & " } }");
                     else
                        L (Ind, "if (!" & Fn_Of (To_String (It.Ref)) & " (p, &"
                          & Lw & ")) { " & Fail & " }");
                     end if;
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
                           L (Ind + 1, "if (cnt_ < 0) { bnf_fail (p, WB(p), "
                             & W & ", ""has a negative count""); " & Fail
                             & " }");
                        end if;
                        L (Ind + 1, "for (;;) {");
                        L (Ind + 2, "size_t s_ = WB(p); " & Type_Of (R)
                          & " t_;");
                        L (Ind + 2, "if (" & Mx & " >= 0 && (int64_t)n_ >= "
                          & Mx & ") break;");
                        L (Ind + 2, "if ((int64_t)n_ >= " & Mn
                          & " && WB(p) >= WN(p)) break;");
                        L (Ind + 2, "memset (&t_, 0, sizeof t_);");
                        L (Ind + 2, "if (!" & Fn_Of (R) & " (p, &t_)) {");
                        L (Ind + 3, "WSET(p, s_);");
                        L (Ind + 3, "if ((int64_t)n_ < " & Mn & ") { " & Fail
                          & " }");
                        L (Ind + 3, "break;");
                        L (Ind + 2, "}");
                        L (Ind + 2, "if (WB(p) == s_) break;");
                        L (Ind + 2, "if (n_ == cap_) {");
                        L (Ind + 3, "cap_ = cap_ ? cap_ * 2 : 8;");
                        L (Ind + 3, "a_ = (" & Type_Of (R)
                          & " *)bnf_grow (a_, n_, cap_, sizeof *a_);");
                        L (Ind + 2, "}");
                        L (Ind + 2, "a_[n_++] = t_;");
                        L (Ind + 1, "}");
                        L (Ind + 1, "if ((int64_t)n_ < " & Mn & ") { "
                          & "bnf_fail (p, WB(p), " & W
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
         Unit_W := Unit_Saved;
      end Gen_Seq;

      procedure Gen_Alts
        (Alts : Seq_Vectors.Vector; Lv : String; Scope : Binding_Vectors.Vector;
         Where : String; Fail : String; Ind : Natural)
      is
         D : constant String := Img (Next_Id);
         K : Natural := 0;
      begin
         L (Ind, "{ size_t c" & D & "_ = WB(p);");
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
               L (Ind + 1, F & ": WSET(p, c" & D & "_);");
            end;
         end loop;
         L (Ind + 1, "bnf_fail (p, WB(p), """ & Where
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
         Open  : Item_Vectors.Vector;     --  the bitsof fields to close
         Unit_Saved : constant Natural := Unit_W;
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
                          & """, """
                          & (if It.Ref /= Null_Unbounded_String
                             then Escape (To_String (It.Ref))
                             else "a condition does not hold: "
                                  & Escape (Expr_Text (It.Count)))
                          & """); " & Bad);
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
                     if It.Bitsof then
                        --  What follows is written as bits, and at the end
                        --  of the sequence they are spelled as the words.
                        declare
                           K : constant String := Img (It.Ord);
                        begin
                           L (Ind, "bnf_w *outer" & K & "_ = w;  bnf_w sub"
                              & K & "_;");
                           L (Ind, "memset (&sub" & K & "_, 0, sizeof sub"
                              & K & "_);  sub" & K & "_.own = 1;  sub" & K
                              & "_.up = w;  w = &sub" & K & "_;");
                           Open.Append (It);
                           Unit_W := It.Width;
                        end;
                     elsif Hosted and then Find (G, To_String (It.Ref)) = 0 then
                        if (for some X of G.External_Tokens => X = It.Ref) then
                           --  A text token is the text it matched.
                           L (Ind, "if (!bnf_wput (w, (const uint8_t *)" & Lw
                             & ", strlen (" & Lw & "), " & W & ")) " & Bad);
                        else
                           L (Ind, "bnf_wfail (w, " & W & ", ""is a text "
                             & "rule, which a bit rule cannot write yet""); "
                             & Bad);
                        end if;
                     else
                        L (Ind, "if (!emit_rule_" & To_String (It.Ref)
                          & " (w, &" & Lw & ")) " & Bad);
                     end if;
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
         for I in reverse 1 .. Natural (Open.Length) loop
            declare
               It : constant Item_Access := Open (I);
               K  : constant String := Img (It.Ord);
            begin
               L (Ind, "w = outer" & K & "_;");
               L (Ind, "if (!bnf_words_text (w, &sub" & K & "_, "
                  & Img (It.Width) & ", bnf_wu_" & K & ", sizeof bnf_wu_" & K
                  & " / sizeof bnf_wu_" & K & "[0], """
                  & Escape (To_String (It.Sep)) & """, "
                  & Img (Length (It.Sep)) & ")) return false;");
            end;
         end loop;
         Unit_W := Unit_Saved;
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
            if A.Guard /= null and then not Uses_Remaining (A.Guard) then
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

      ------------------------------------------------------------------------
      --  Actions: after a successful read, on each record, children first
      ------------------------------------------------------------------------

      function Is_Record (Name : String) return Boolean is
         K : constant Natural := Find (G, Name);
      begin
         return K /= 0 and then not Is_Value_Set (G.Rules (K));
      end Is_Record;

      Has_Actions : constant Boolean :=
        (for some R of G.Rules => R.Action /= Null_Unbounded_String);

      procedure Gen_Walk_Alts
        (Alts : Seq_Vectors.Vector; Lv : String; Ind : Natural);

      procedure Gen_Walk_Seq (S : Sequence; Lv : String; Ind : Natural) is
      begin
         for It of S.Items loop
            declare
               Lw : constant String := Lv & To_String (It.Name);
            begin
               case It.Kind is
                  when S_Ref =>
                     if Is_Record (To_String (It.Ref)) then
                        L (Ind, "walk_" & To_String (It.Ref) & " (&" & Lw & ");");
                     end if;
                  when S_Array =>
                     if Is_Record (To_String (It.Ref)) then
                        L (Ind, "for (size_t i_ = 0; i_ < " & Lw
                           & ".n; i_++) walk_" & To_String (It.Ref) & " (&"
                           & Lw & ".items[i_]);");
                     end if;
                  when S_Choice =>
                     Gen_Walk_Alts (It.Alts, Lw & ".", Ind);
                  when others =>
                     null;
               end case;
            end;
         end loop;
      end Gen_Walk_Seq;

      procedure Gen_Walk_Alts
        (Alts : Seq_Vectors.Vector; Lv : String; Ind : Natural)
      is
         K : Natural := 0;
      begin
         for A of Alts loop
            K := K + 1;
            L (Ind, "if (" & Lv & "kind == " & Img (K) & ") {");
            Gen_Walk_Seq (A.all, Lv & "u.a" & Img (K) & ".", Ind + 1);
            L (Ind, "}");
         end loop;
      end Gen_Walk_Alts;

      procedure Runtime_Writer is
      begin
         L (0, "");
         L (0, "/* The other direction: a tree to bytes.  With buf NULL it only"
            & " counts. */");
         L (0, "typedef struct bnf_w {");
         L (1, "uint8_t *buf;");
         L (1, "size_t cap;");
         L (1, "size_t bit;");
         L (1, "int failed;");
         L (1, "char msg[256];");
         L (1, "int own;                /* a buffer of its own that grows */");
         L (1, "struct bnf_w *up;       /* the writer this one writes bits for */");
         L (0, "} bnf_w;");
         L (0, "static void bnf_wfail (bnf_w *w, const char *where, const char"
            & " *what) {");
         L (1, "while (w->up) w = w->up;");
         L (1, "if (w->failed) return;");
         L (1, "w->failed = 1;");
         L (1, "snprintf (w->msg, sizeof w->msg, ""%s: %s"", where, what);");
         L (0, "}");
         L (0, "static void bnf_wgrow (bnf_w *w, size_t need) {");
         L (1, "size_t cap = w->cap * 2 > need ? w->cap * 2 : need;");
         L (1, "uint8_t *nb;");
         L (1, "if (cap < 64) cap = 64;");
         L (1, "nb = (uint8_t *)bnf_alloc (cap);");
         L (1, "if (w->bit) memcpy (nb, w->buf, (w->bit + 7) / 8);");
         L (1, "w->buf = nb;  w->cap = cap;");
         L (0, "}");
         L (0, "static void bnf_wr (bnf_w *w, unsigned n, uint64_t v) {");
         L (1, "unsigned put = 0;");
         L (1, "while (put < n) {");
         L (2, "size_t byte = w->bit >> 3;");
         L (2, "unsigned off = (unsigned)(w->bit & 7), take = 8 - off;");
         L (2, "unsigned chunk;");
         L (2, "if (take > n - put) take = n - put;");
         L (2, "chunk = (unsigned)((v >> (n - put - take)) & ((1u << take) - 1));");
         L (2, "if (w->own && byte >= w->cap) bnf_wgrow (w, byte + 1);");
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
         L (1, "if ((w->bit & 7) == 0 && !w->own) {");
         L (2, "if (w->buf && w->bit / 8 + n <= w->cap && n) "
            & "memcpy (w->buf + w->bit / 8, p, n);");
         L (2, "w->bit += n * 8;");
         L (1, "} else {");
         L (2, "for (size_t i = 0; i < n; i++) bnf_wr (w, 8, p[i]);");
         L (1, "}");
         L (1, "return true;");
         L (0, "}");
         if Any_Words then
            L (0, "/* The bits a sub-writer was given, spelled as words: width bits"
               & " each, the spelling of the word with that value, sep between. */");
            L (0, "struct bnf_wu { const char *s; size_t n; unsigned v; };");
            L (0, "static bool bnf_words_text (bnf_w *w, bnf_w *sub, unsigned width,"
               & " const struct bnf_wu *tab, size_t ntab, const char *sep, "
               & "size_t seplen) {");
            L (1, "size_t total = sub->bit, i, k;");
            L (1, "char t[96];");
            L (1, "if (total % width) {");
            L (2, "snprintf (t, sizeof t, ""%zu bits is not a whole number of "
               & "%u-bit units"", total, width);");
            L (2, "bnf_wfail (w, ""the words"", t);");
            L (2, "return false;");
            L (1, "}");
            L (1, "for (i = 0; i < total / width; i++) {");
            L (2, "unsigned v = 0;  size_t b;");
            L (2, "for (b = 0; b < width; b++) {");
            L (3, "size_t bit = i * width + b;");
            L (3, "v = (v << 1) | ((sub->buf[bit >> 3] >> (7 - (bit & 7))) & 1u);");
            L (2, "}");
            L (2, "for (k = 0; k < ntab; k++)");
            L (3, "if (tab[k].v == v) break;");
            L (2, "if (k == ntab) {");
            L (3, "snprintf (t, sizeof t, ""unit %zu has the value %u, which no "
               & "word spells"", i, v);");
            L (3, "bnf_wfail (w, ""the words"", t);");
            L (3, "return false;");
            L (2, "}");
            L (2, "if (i && seplen) bnf_wput (w, (const uint8_t *)sep, seplen, "
               & """the words"");");
            L (2, "bnf_wput (w, (const uint8_t *)tab[k].s, tab[k].n, ""the words"");");
            L (1, "}");
            L (1, "return true;");
            L (0, "}");
         end if;
      end Runtime_Writer;

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
         L (0, "/* The reader's place and input, behind names the text parser's own");
         L (0, "   place and input can stand in for. */");
         L (0, "#define WB(p) ((p)->bit)");
         L (0, "#define WSET(p, x) ((p)->bit = (x))");
         L (0, "#define WN(p) ((p)->nbits)");
         L (0, "#define WBUF(p) ((p)->buf)");
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
         L (1, "size_t left = WN(p) - WB(p);");
         L (1, "uint64_t x = 0;");
         L (1, "unsigned got = 0;");
         L (1, "if (n > left) {");
         L (2, "char t[64];");
         L (2, "snprintf (t, sizeof t, ""needs %u bits, %zu left"", n, left);");
         L (2, "bnf_fail (p, WB(p), where, t);");
         L (2, "return false;");
         L (1, "}");
         L (1, "while (got < n) {");
         L (2, "size_t byte = WB(p) >> 3;");
         L (2, "unsigned off = (unsigned)(WB(p) & 7), take = 8 - off;");
         L (2, "if (take > n - got) take = n - got;");
         L (2, "x = (x << take) | (((unsigned)WBUF(p)[byte] >> (8 - off - take))"
            & " & ((1u << take) - 1));");
         L (2, "WSET(p, WB(p) + take);  got += take;");
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
         L (1, "if (n > (WN(p) - WB(p)) / 8) {");
         L (2, "char t[64];");
         L (2, "snprintf (t, sizeof t, ""needs %zu octets, %zu bits left"", n, "
            & "WN(p) - WB(p));");
         L (2, "bnf_fail (p, WB(p), where, t);");
         L (2, "return false;");
         L (1, "}");
         L (1, "if ((WB(p) & 7) == 0) {");
         L (2, "o->ptr = WBUF(p) + WB(p) / 8;  o->len = n;");
         L (2, "WSET(p, WB(p) + n * 8);");
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
         L (1, "return bnf_take (p, (WN(p) - WB(p)) / 8, o, where);");
         L (0, "}");
         Runtime_Writer;
      end Runtime;

      --  The helpers a hosted reader needs, over the text parser's state.
      procedure Runtime_Hosted is
      begin
         L (0, "/* ---- bit rules, read from the text parser's input ---- */");
         L (0, "typedef parser_t bnf_p;");
         L (0, "#define WB(p) ((p)->pos * 8 + (p)->bit)");
         L (0, "#define WSET(p, x) do { size_t b_ = (x); (p)->pos = b_ >> 3; "
            & "(p)->bit = (unsigned)(b_ & 7); } while (0)");
         L (0, "#define WN(p) ((p)->lim ? (p)->lim : (p)->len * 8)");
         L (0, "#define WBUF(p) ((const uint8_t *)(p)->text)");
         L (0, "#define bnf_alloc hbnf_alloc");
         L (0, "static void *bnf_grow (void *old, size_t n, size_t cap, "
            & "size_t sz) {");
         L (1, "void *r = bnf_alloc (cap * sz);");
         L (1, "if (n) memcpy (r, old, n * sz);");
         L (1, "return r;");
         L (0, "}");
         L (0, "static char bnf_msg[256];");
         L (0, "static void bnf_fail (bnf_p *p, size_t bit, const char *where,"
            & " const char *what) {");
         L (1, "size_t save_pos = p->pos, save_len = p->len, flen = 0;");
         L (1, "unsigned save_bit = p->bit;  const char *save_text = p->text;");
         L (1, "if (p->sv.active) {");
         L (2, "/* reading the bits of a text: say where the text was */");
         L (2, "snprintf (bnf_msg, sizeof bnf_msg, ""%s: %s (at unit %zu)"", "
            & "where, what, bit / (p->unit ? p->unit : 1) + 1);");
         L (2, "p->text = p->sv.text;  p->len = p->sv.len;  p->pos = p->sv.start;"
            & "  p->bit = 0;");
         L (2, "flen = p->len - p->pos;  if (flen > 24) flen = 24;");
         L (1, "} else {");
         L (2, "p->pos = bit >> 3;  p->bit = (unsigned)(bit & 7);");
         L (2, "snprintf (bnf_msg, sizeof bnf_msg, ""%s: %s"", where, what);");
         L (1, "}");
         L (1, "fail (p, bnf_msg, 0, p->text + p->pos, flen);");
         L (1, "p->text = save_text;  p->len = save_len;  p->pos = save_pos;"
            & "  p->bit = save_bit;");
         L (0, "}");
         L (0, "/* n bits (at most 64), first bit in the most significant place. */");
         L (0, "static bool bnf_rd (bnf_p *p, unsigned n, uint64_t *v, "
            & "const char *where) {");
         L (1, "size_t left = WN(p) - WB(p);");
         L (1, "uint64_t x = 0;");
         L (1, "unsigned got = 0;");
         L (1, "if (n > left) {");
         L (2, "char t[64];");
         L (2, "snprintf (t, sizeof t, ""needs %u bits, %zu left"", n, left);");
         L (2, "bnf_fail (p, WB(p), where, t);");
         L (2, "return false;");
         L (1, "}");
         L (1, "while (got < n) {");
         L (2, "size_t byte = WB(p) >> 3;");
         L (2, "unsigned off = (unsigned)(WB(p) & 7), take = 8 - off;");
         L (2, "if (take > n - got) take = n - got;");
         L (2, "x = (x << take) | (((unsigned)WBUF(p)[byte] >> (8 - off - take))"
            & " & ((1u << take) - 1));");
         L (2, "WSET(p, WB(p) + take);  got += take;");
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
         L (1, "if (n > (WN(p) - WB(p)) / 8) {");
         L (2, "char t[64];");
         L (2, "snprintf (t, sizeof t, ""needs %zu octets, %zu bits left"", n, "
            & "WN(p) - WB(p));");
         L (2, "bnf_fail (p, WB(p), where, t);");
         L (2, "return false;");
         L (1, "}");
         L (1, "if ((WB(p) & 7) == 0) {");
         L (2, "o->ptr = WBUF(p) + WB(p) / 8;  o->len = n;");
         L (2, "WSET(p, WB(p) + n * 8);");
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
         L (1, "return bnf_take (p, (WN(p) - WB(p)) / 8, o, where);");
         L (0, "}");
         L (0, "/* Text is octets, and an octet is eight bits from any bit: a text");
         L (0, "   rule read where the position is inside an octet (after a 5-bit");
         L (0, "   field) reads a copy of the rest shifted to that bit.  bnf_enter");
         L (0, "   makes p read it, bnf_leave puts p back and, if the read worked,");
         L (0, "   moves the position on by the octets it used. */");
         L (0, "typedef struct { const char *text; size_t pos, len; unsigned bit; }"
            & " bnf_save;");
         L (0, "static bnf_save bnf_enter (bnf_p *p) {");
         L (1, "bnf_save s;");
         L (1, "s.text = p->text;  s.pos = p->pos;  s.len = p->len;  s.bit = p->bit;");
         L (1, "if (p->bit) {");
         L (2, "size_t m = ((p->len - p->pos) * 8 - p->bit) / 8, i;");
         L (2, "uint8_t *c = (uint8_t *)bnf_alloc (m + 1);");
         L (2, "const uint8_t *t = (const uint8_t *)p->text + p->pos;");
         L (2, "for (i = 0; i < m; i++)");
         L (3, "c[i] = (uint8_t)((t[i] << p->bit) | (t[i + 1] >> (8 - p->bit)));");
         L (2, "p->text = (const char *)c;  p->pos = 0;  p->len = m;  p->bit = 0;");
         L (1, "}");
         L (1, "return s;");
         L (0, "}");
         if Any_Words then
            L (0, "/* `name:bitsof(rule)`: the numbered words of the text the rule just"
               & " read, as the bits the rest of the reading uses.  word reads one"
               & " word from text; what is between two words is skipped. */");
            L (0, "static bool bnf_words (bnf_p *p, size_t s, size_t e, unsigned "
               & "width, bool (*word)(bnf_p *, unsigned *), uint8_t **out, "
               & "size_t *nbits) {");
            L (1, "bnf_p q = *p;");
            L (1, "uint8_t *buf = NULL;");
            L (1, "size_t k = 0, i;  unsigned v, pass;");
            L (1, "for (pass = 0; pass < 2; pass++) {");
            L (2, "k = 0;  q.pos = s;  q.len = e;  q.bit = 0;");
            L (2, "while (q.pos < e) {");
            L (3, "size_t before = q.pos;");
            L (3, "if (word (&q, &v) && q.pos > before) {");
            L (4, "if (pass)");
            L (5, "for (i = 0; i < width; i++) {");
            L (6, "size_t b = k * width + i;");
            L (6, "if ((v >> (width - 1 - i)) & 1)");
            L (7, "buf[b >> 3] |= (uint8_t)(0x80 >> (b & 7));");
            L (5, "}");
            L (4, "k++;");
            L (3, "} else {");
            L (4, "q.pos = before + 1;");
            L (3, "}");
            L (2, "}");
            L (2, "if (!pass) buf = (uint8_t *)bnf_alloc ((k * width + 7) / 8 + 1);");
            L (1, "}");
            L (1, "*out = buf;  *nbits = k * width;");
            L (1, "return true;");
            L (0, "}");
            L (0, "static void bnf_srcset (bnf_p *p, uint8_t *buf, size_t nbits, "
               & "unsigned width, size_t start) {");
            L (1, "p->sv.text = p->text;  p->sv.pos = p->pos;  p->sv.len = p->len;");
            L (1, "p->sv.lim = p->lim;  p->sv.bit = p->bit;  p->sv.unit = p->unit;");
            L (1, "p->sv.start = start;  p->sv.active = 1;");
            L (1, "p->text = (const char *)buf;  p->pos = 0;  p->bit = 0;");
            L (1, "p->len = (nbits + 7) / 8;  p->lim = nbits;  p->unit = width;");
            L (0, "}");
            L (0, "/* The end of a rule that read bits from words: all of them must "
               & "have been used, and the text is the input again. */");
            L (0, "static bool bnf_words_end (bnf_p *p, bool ok) {");
            L (1, "if (!p->sv.active) return ok;");
            L (1, "if (ok && WB(p) != WN(p)) {");
            L (2, "char t[64];");
            L (2, "snprintf (t, sizeof t, ""%zu bit(s) left over"", WN(p) - WB(p));");
            L (2, "bnf_fail (p, WB(p), ""the words"", t);");
            L (2, "ok = false;");
            L (1, "}");
            L (1, "p->text = p->sv.text;  p->len = p->sv.len;  p->lim = p->sv.lim;");
            L (1, "p->unit = p->sv.unit;  p->pos = p->sv.pos;  p->bit = p->sv.bit;");
            L (1, "p->sv.active = 0;");
            L (1, "return ok;");
            L (0, "}");
         end if;
         L (0, "static void bnf_leave (bnf_p *p, bnf_save s, bool ok) {");
         L (1, "if (s.bit) {");
         L (2, "size_t used = p->pos;");
         L (2, "p->text = s.text;  p->len = s.len;  p->pos = s.pos;  p->bit = s.bit;");
         L (2, "if (ok) WSET (p, s.pos * 8 + s.bit + used * 8);");
         L (1, "}");
         L (0, "}");
         Runtime_Writer;
      end Runtime_Hosted;

      Root : constant Natural := 1;
   begin
      Check_Code_Language (G, "C");
      if not Hosted then
         for R of G.Rules loop
            for A of R.Alts loop
               for It of A.Items loop
                  if It.Kind = S_Ref and then Find (G, To_String (It.Ref)) = 0
                  then
                     raise Wire_Error with
                       "rule `" & To_String (R.Name) & "` names the text rule `"
                       & To_String (It.Ref) & "`; a grammar whose first rule "
                       & "is a bit rule is read as bits alone.  Put a text "
                       & "rule first, and the one parser reads both";
                  end if;
               end loop;
            end loop;
         end loop;
      end if;
      if not Hosted and then Is_Value_Set (G.Rules (Root)) then
         raise Wire_Error with
           "the first rule, `" & To_String (G.Rules (Root).Name)
           & "`, is a list of constants; parse_bytes reads the first rule, "
           & "which should be the whole message";
      end if;

      if not Hosted then
         L (0, "/* generated by hbnf (binary) -- do not edit */");
         L (0, "#include <stdint.h>");
         L (0, "#include <stdbool.h>");
         L (0, "#include <stddef.h>");
         L (0, "#include <stdio.h>");
         L (0, "#include <stdlib.h>");
         L (0, "#include <string.h>");
         L (0, "");
         if G.Preamble /= Null_Unbounded_String then
            L (0, "/* the grammar's preamble */");
            Put (To_String (G.Preamble));
            L (0, "");
         end if;
      end if;
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
      if Hosted then
         --  Text that follows fields ending inside an octet.
         for R of G.Rules loop
            for A of R.Alts loop
               declare
                  Off : Integer := 0;       --  bits past an octet; -1 unknown
               begin
                  for It of A.Items loop
                     case It.Kind is
                        when S_Bits | S_Const =>
                           if Off >= 0 then
                              Off := (Off + It.Bits) mod 8;
                           end if;
                        when S_Octets | S_Rest | S_Assert =>
                           null;
                        when S_Ref =>
                           if Find (G, To_String (It.Ref)) = 0 then
                              if Off > 0 then
                                 Note_Shift (To_String (R.Name), Off);
                              end if;
                           else
                              declare
                                 F : constant Integer :=
                                   Fixed_Bits (G, G.Rules
                                     (Find (G, To_String (It.Ref))).Alts
                                       .First_Element.all);
                              begin
                                 Off := (if Off >= 0 and then F >= 0
                                         then (Off + F) mod 8 else -1);
                              end;
                           end if;
                        when others =>
                           Off := -1;
                     end case;
                  end loop;
               end;
            end loop;
         end loop;
      end if;
      if Hosted and then Has_Actions then
         --  The text parser's bind walk (declared before these readers) calls
         --  the walk of each bit rule it holds.
         for R of G.Rules loop
            if not Is_Value_Set (R) then
               L (0, "static void walk_" & To_String (R.Name) & " ("
                  & Type_Of (To_String (R.Name)) & " *n);");
            end if;
         end loop;
      end if;
      Types_End := Length (Buf);

      if Hosted then
         Runtime_Hosted;
      else
         Runtime;
      end if;
      if (for some R of G.Rules => R.Emit /= Null_Unbounded_String) then
         L (0, "/* In an %emit block: fail the write. */");
         L (0, "#define HBNF_EMIT_FAIL(msg) do { bnf_wfail (w, ""emit"", (msg)); \");
         L (0, "    return false; } while (0)");
         L (0, "");
      end if;

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

      --  The numbered words of each bitsof field: the function that reads one
      --  word from text, and the table that spells one.
      if Hosted then
         declare
            Count : Natural := 0;
            function C_Ident_Of (S : Unbounded_String) return String is
               R : String := To_String (S);
            begin
               for C of R loop
                  if C = '-' then
                     C := '_';
                  end if;
               end loop;
               return R;
            end C_Ident_Of;
            procedure Visit_Items (V : Item_Vectors.Vector) is
            begin
               for It of V loop
                  if It.Bitsof then
                     Count := Count + 1;
                     It.Ord := Count;
                     declare
                        K : constant String := Img (Count);
                        Wr : constant String := C_Ident_Of (It.Word_Rule);
                     begin
                        L (0, "static bool bnf_word_" & K
                           & " (bnf_p *q, unsigned *v) {");
                        L (1, Type_Of (Wr) & " e;");
                        L (1, "if (!" & Fn_Of (Wr) & " (q, &e)) return false;");
                        L (1, "*v = (unsigned)e;");
                        L (1, "return true;");
                        L (0, "}");
                        L (0, "static const struct bnf_wu bnf_wu_" & K & "[] = {");
                        for U of It.Words loop
                           L (1, "{ """ & Escape (To_String (U.Spelling)) & """, "
                              & Img (Length (U.Spelling)) & ", "
                              & Img (U.Value) & " },");
                        end loop;
                        L (0, "};");
                     end;
                  end if;
                  if It.Kind = S_Choice then
                     for A of It.Alts loop
                        Visit_Items (A.Items);
                     end loop;
                  end if;
               end loop;
            end Visit_Items;
         begin
            for R of G.Rules loop
               for A of R.Alts loop
                  Visit_Items (A.Items);
               end loop;
            end loop;
         end;
      end if;

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
               if Has_Words (R) then
                  L (0, "static bool " & Fn_Of (Nm) & "_body (bnf_p *p, "
                     & Type_Of (Nm) & " *out);");
                  L (0, "static bool " & Fn_Of (Nm) & " (bnf_p *p, "
                     & Type_Of (Nm) & " *out) {");
                  L (1, "return bnf_words_end (p, " & Fn_Of (Nm)
                     & "_body (p, out));");
                  L (0, "}");
                  L (0, "static bool " & Fn_Of (Nm) & "_body (bnf_p *p, "
                     & Type_Of (Nm) & " *out) {");
               else
                  L (0, "static bool " & Fn_Of (Nm) & " (bnf_p *p, "
                     & Type_Of (Nm) & " *out) {");
               end if;
               if Natural (R.Alts.Length) = 1 then
                  Gen_Seq (R.Alts.First_Element.all, "out->", Empty, Nm,
                           "return false;", 1);
               else
                  Gen_Alts (R.Alts, "out->", Empty, Nm, "return false;", 1);
               end if;
               L (1, "return true;");
               L (0, "}");
               if R.Emit /= Null_Unbounded_String then
                  --  The fields are written from a copy, which the block may
                  --  change: the caller's tree is not touched.
                  L (0, "static bool emit_rule_" & Nm & " (bnf_w *w, const "
                     & Type_Of (Nm) & " *in_) {");
                  L (1, Type_Of (Nm) & " copy_ = *in_;");
                  L (1, Type_Of (Nm) & " *n = &copy_;");
                  L (1, "const " & Type_Of (Nm) & " *in = n;");
                  L (1, "{");
                  Put (To_String (R.Emit));
                  L (0, "");
                  L (1, "}");
               else
                  L (0, "static bool emit_rule_" & Nm & " (bnf_w *w, const "
                     & Type_Of (Nm) & " *in) {");
               end if;
               Emit_Side := True;
               if Natural (R.Alts.Length) = 1 then
                  Gen_Emit_Seq (R.Alts.First_Element.all, "in->", Empty, Nm, 1);
               else
                  Gen_Emit_Alts (R.Alts, "in->", Empty, Nm, 1);
               end if;
               Emit_Side := False;
               L (1, "return true;");
               L (0, "}");
               if Hosted then
                  --  The writer of a bit rule, for the program to call.
                  L (0, "bool emit_bits_" & Nm & " (const " & Type_Of (Nm)
                     & " *in, uint8_t *buf, size_t cap, size_t *nbits,");
                  L (0, "                  char *err, size_t errsz) {");
                  L (1, "bnf_w w;");
                  L (1, "memset (&w, 0, sizeof w);");
                  L (1, "w.buf = buf;  w.cap = cap;");
                  L (1, "(void)bnf_wput;");
                  L (1, "if (!emit_rule_" & Nm & " (&w, in)) goto bad;");
                  L (1, "if (nbits) *nbits = w.bit;");
                  L (1, "if (buf && (w.bit + 7) / 8 > cap) {");
                  L (2, "bnf_wfail (&w, """ & Nm & """, ""the buffer is too "
                     & "small"");");
                  L (2, "goto bad;");
                  L (1, "}");
                  L (1, "return true;");
                  L (0, "bad:");
                  L (1, "if (nbits) *nbits = w.bit;");
                  L (1, "if (err && errsz) snprintf (err, errsz, ""%s"", w.msg);");
                  L (1, "return false;");
                  L (0, "}");
               end if;
            end if;
            L (0, "");
         end;
      end loop;

      if Has_Actions then
         L (0, "/* ---- actions: C that runs on a record, as n, once the whole read");
         L (0, "   has succeeded (children first).  HBNF_WARN (""..."") adds a");
         L (0, "   warning to the result, HBNF_FAIL (""..."") fails the read.  Not");
         L (0, "   reentrant: the warnings are collected in static storage. ---- */");
         L (0, "static const char *bnf_act_warn[8];");
         L (0, "static unsigned bnf_act_nwarn;");
         L (0, "#define HBNF_WARN(msg) do { if (bnf_act_nwarn < 8) \");
         L (0, "    bnf_act_warn[bnf_act_nwarn++] = (msg); } while (0)");
         if Hosted then
            --  A failure is the text parser's own: the walk carries on and the
            --  parse fails once it ends, with this as the message.
            L (0, "#define HBNF_FAIL(msg) bind_error (""%s"", (msg))");
            L (0, "/* The warnings the actions of the bit rules gave: n of them, i from 0. */");
            L (0, "__attribute__((unused)) static unsigned hbnf_warnings (void)"
               & " { return bnf_act_nwarn; }");
            L (0, "__attribute__((unused)) static const char *hbnf_warning "
               & "(unsigned i) { return i < bnf_act_nwarn ? bnf_act_warn[i] : 0; }");
         else
            L (0, "static const char *bnf_act_failed;");
            L (0, "#define HBNF_FAIL(msg) do { if (!bnf_act_failed) \");
            L (0, "    bnf_act_failed = (msg); } while (0)");
            for R of G.Rules loop
               if not Is_Value_Set (R) then
                  L (0, "static void walk_" & To_String (R.Name) & " ("
                     & Type_Of (To_String (R.Name)) & " *n);");
               end if;
            end loop;
         end if;
         L (0, "");
         for R of G.Rules loop
            if not Is_Value_Set (R) then
               declare
                  Nm : constant String := To_String (R.Name);
               begin
                  if R.Action /= Null_Unbounded_String then
                     L (0, "static void action_" & Nm & " ("
                        & Type_Of (Nm) & " *n) {");
                     L (1, "(void)n;");
                     Put (To_String (R.Action));
                     L (0, "");
                     L (0, "}");
                  end if;
                  L (0, "static void walk_" & Nm & " (" & Type_Of (Nm)
                     & " *n) {");
                  L (1, "(void)n;");
                  if Natural (R.Alts.Length) = 1 then
                     Gen_Walk_Seq (R.Alts.First_Element.all, "n->", 1);
                  else
                     Gen_Walk_Alts (R.Alts, "n->", 1);
                  end if;
                  if R.Action /= Null_Unbounded_String then
                     L (1, "action_" & Nm & " (n);");
                  end if;
                  L (0, "}");
               end;
            end if;
         end loop;
         L (0, "");
      end if;

      if not Hosted then
      declare
         Rt : constant String := To_String (G.Rules (Root).Name);
      begin
         L (0, "/* Read nbits bits of buf as one " & Rt & ".  On success all of"
            & " them were used and the strings of octets in *out point into buf"
            & " (or, when they start inside a byte, into the arena). */");
         L (0, "static bool bnf_read (const uint8_t *buf, size_t nbits, "
            & Type_Of (Rt) & " *out,");
         L (0, "                     char *err, size_t errsz, size_t *fail_bit) {");
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
         if Has_Actions then
            L (1, "bnf_act_nwarn = 0;  bnf_act_failed = NULL;");
            L (1, "walk_" & Rt & " (out);");
            L (1, "if (bnf_act_failed) {");
            L (2, "p.failed = 0;");
            L (2, "bnf_fail (&p, p.bit, """ & Rt & """, bnf_act_failed);");
            L (2, "goto bad;");
            L (1, "}");
            L (1, "memcpy (out->warnings, bnf_act_warn, sizeof out->warnings);");
            L (1, "out->nwarnings = bnf_act_nwarn;");
         end if;
         L (1, "return true;");
         L (0, "bad:");
         L (1, "if (fail_bit) *fail_bit = p.fail_bit;");
         L (1, "if (err && errsz) snprintf (err, errsz, ""%s"", p.msg);");
         L (1, "return false;");
         L (0, "}");
         L (0, "bool parse_bits (const uint8_t *buf, size_t nbits, "
            & Type_Of (Rt) & " *out,");
         L (0, "                 char *err, size_t errsz, size_t *at) {");
         L (1, "size_t fb = 0;");
         L (1, "char m[256];");
         L (1, "bool ok = bnf_read (buf, nbits, out, m, sizeof m, &fb);");
         L (1, "if (!ok) {");
         L (2, "if (at) *at = fb / 8;");
         L (2, "if (err && errsz) snprintf (err, errsz, ""octet %zu: %s"", fb / 8, m);");
         L (1, "}");
         L (1, "return ok;");
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
      end if;
      if G.Epilogue /= Null_Unbounded_String and then not Hosted then
         L (0, "");
         L (0, "/* the grammar's epilogue */");
         Put (To_String (G.Epilogue));
      end if;
      declare
         All_Text : constant String := To_String (Buf);
      begin
         Types := To_Unbounded_String (All_Text (All_Text'First .. All_Text'First + Types_End - 1));
         Code  := To_Unbounded_String (All_Text (All_Text'First + Types_End .. All_Text'Last));
      end;
   end Generate;

   function Emit (G : Grammar) return String is
      Types, Code : Unbounded_String;
   begin
      Generate (G, False, Types, Code);
      return To_String (Types) & To_String (Code);
   end Emit;

   procedure Emit_Hosted
     (G : Grammar; Types, Code : out Unbounded_String) is
   begin
      Generate (G, True, Types, Code);
   end Emit_Hosted;

end HBNF_Wire.C;
