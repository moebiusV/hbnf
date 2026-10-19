pragma Ada_2022;

with Ada.Characters.Latin_1;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with HBNF_Lookahead;

package body HBNF_Tree_Sitter is

   use Ada.Strings.Unbounded;
   use HBNF_Grammar;

   subtype U is Unbounded_String;

   LF : constant Character := Ada.Characters.Latin_1.LF;
   Max_Cp : constant := 16#10FFFF#;

   package Name_Vectors is new Ada.Containers.Vectors (Positive, U);

   type Span is record
      Lo, Hi : Natural;
   end record;
   package Span_Vectors is new Ada.Containers.Vectors (Positive, Span);

   function Img (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Img;

   function Hex (N : Natural) return String is
      Digits_16 : constant String := "0123456789ABCDEF";
      R : U;
      V : Natural := N;
   begin
      if V = 0 then
         return "0";
      end if;
      while V > 0 loop
         R := Digits_16 (V mod 16 + 1) & R;
         V := V / 16;
      end loop;
      return To_String (R);
   end Hex;

   --  ---- a small tree, so a long call can be laid out over several lines ----

   type Node;
   type Node_Access is access Node;
   package Node_Vectors is new Ada.Containers.Vectors (Positive, Node_Access);
   type Node is record
      Fn   : U;                      --  "" for an atom
      Text : U;                      --  the atom
      Args : Node_Vectors.Vector;
   end record;

   function Atom (S : String) return Node_Access is
     (new Node'(Fn => Null_Unbounded_String,
                Text => To_Unbounded_String (S), Args => <>));

   function Call (Fn : String; Args : Node_Vectors.Vector) return Node_Access is
     (new Node'(Fn => To_Unbounded_String (Fn),
                Text => Null_Unbounded_String, Args => Args));

   function Call1 (Fn : String; A : Node_Access) return Node_Access is
      V : Node_Vectors.Vector;
   begin
      V.Append (A);
      return Call (Fn, V);
   end Call1;

   function Flat (N : Node_Access) return String is
      R : U;
   begin
      if N.Fn = Null_Unbounded_String then
         return To_String (N.Text);
      end if;
      Append (R, To_String (N.Fn) & "(");
      for K in 1 .. Natural (N.Args.Length) loop
         if K > 1 then
            Append (R, ", ");
         end if;
         Append (R, Flat (N.Args (K)));
      end loop;
      Append (R, ")");
      return To_String (R);
   end Flat;

   function Pad (N : Natural) return String is ([1 .. N => ' ']);

   function Layout (N : Node_Access; Indent : Natural) return String is
      F : constant String := Flat (N);
      R : U;
   begin
      if N.Fn = Null_Unbounded_String or else N.Args.Is_Empty
        or else Indent + F'Length <= 78
      then
         return F;
      end if;
      Append (R, To_String (N.Fn) & "(" & LF);
      for A of N.Args loop
         Append (R, Pad (Indent + 2) & Layout (A, Indent + 2) & "," & LF);
      end loop;
      Append (R, Pad (Indent) & ")");
      return To_String (R);
   end Layout;

   --  ---- spelling ----------------------------------------------------------

   --  A rule's name as a JavaScript identifier (tree-sitter's: letters, digits
   --  and underscores; hyphens, the one other character a rule name has, are
   --  underscores).
   function Js_Name (N : String) return String is
      R : String := N;
   begin
      for K in R'Range loop
         if R (K) not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' then
            R (K) := '_';
         end if;
      end loop;
      if R'Length = 0 or else R (R'First) in '0' .. '9' then
         return "r_" & R;
      end if;
      return R;
   end Js_Name;

   function Js_Str (S : String) return String is
      Dq : constant Boolean :=
        (for some C of S => C = ''') and then (for all C of S => C /= '"');
      Q  : constant String := (if Dq then """" else "'");
      R  : U := To_Unbounded_String (Q);
   begin
      for C of S loop
         case C is
            when '\' => Append (R, "\\");
            when ''' => Append (R, (if Dq then "'" else "\'"));
            when '"' => Append (R, (if Dq then "\""" else """"));
            when LF => Append (R, "\n");
            when Ada.Characters.Latin_1.CR => Append (R, "\r");
            when Ada.Characters.Latin_1.HT => Append (R, "\t");
            when others =>
               if Character'Pos (C) < 32 then
                  Append (R, "\x" & (if Character'Pos (C) < 16 then "0" else "")
                    & Hex (Character'Pos (C)));
               else
                  Append (R, C);
               end if;
         end case;
      end loop;
      Append (R, Q);
      return To_String (R);
   end Js_Str;

   --  One code point in a regular expression (and in a class).  JavaScript
   --  reads the pattern first, so \xHH and \uHHHH, not \u{...}.
   function Re_Cp (Cp : Natural) return String is
      function Fixed (N, Width : Natural) return String is
         H : constant String := Hex (N);
      begin
         return [1 .. Width - H'Length => '0'] & H;
      end Fixed;
   begin
      if Cp in 32 .. 126 then
         declare
            C : constant Character := Character'Val (Cp);
         begin
            if C in '\' | '^' | '$' | '.' | '|' | '?' | '*' | '+' | '(' | ')'
                  | '[' | ']' | '{' | '}' | '/' | '-'
            then
               return "\" & C;
            end if;
            return [1 => C];
         end;
      elsif Cp = 9 then
         return "\t";
      elsif Cp = 10 then
         return "\n";
      elsif Cp = 13 then
         return "\r";
      elsif Cp < 256 then
         return "\x" & Fixed (Cp, 2);
      elsif Cp < 65536 then
         return "\u" & Fixed (Cp, 4);
      end if;
      return "\u{" & Hex (Cp) & "}";
   end Re_Cp;

   --  The ranges, sorted and merged.
   procedure Normalize (V : in out Span_Vectors.Vector) is
      A : Span_Vectors.Vector := V;
      R : Span_Vectors.Vector;
   begin
      --  insertion sort by Lo
      for I in 2 .. Natural (A.Length) loop
         declare
            X : constant Span := A (I);
            J : Natural := I - 1;
         begin
            while J >= 1 and then A (J).Lo > X.Lo loop
               A (J + 1) := A (J);
               J := J - 1;
            end loop;
            A (J + 1) := X;
         end;
      end loop;
      for S of A loop
         if not R.Is_Empty and then S.Lo <= R.Last_Element.Hi + 1 then
            if S.Hi > R.Last_Element.Hi then
               R (Natural (R.Length)).Hi := S.Hi;
            end if;
         else
            R.Append (S);
         end if;
      end loop;
      V := R;
   end Normalize;

   --  A set of code points as a class, a negated one when it runs to the end
   --  of Unicode (JavaScript has no \u{...} without a flag).
   function Class_Text (Ranges : Span_Vectors.Vector) return String is
      V : Span_Vectors.Vector := Ranges;
      R : U;
      Negate : Boolean;
      Set : Span_Vectors.Vector;
   begin
      Normalize (V);
      if V.Is_Empty then
         return "(?:)";
      end if;
      Negate := V.Last_Element.Hi >= Max_Cp;
      if Negate then
         --  the gaps
         declare
            Next : Natural := 0;
         begin
            for S of V loop
               if S.Lo > Next then
                  Set.Append (Span'((Next, S.Lo - 1)));
               end if;
               Next := S.Hi + 1;
            end loop;
         end;
         if Set.Is_Empty then
            return "[\s\S]";
         end if;
      else
         Set := V;
      end if;
      if not Negate and then Natural (Set.Length) = 1
        and then Set (1).Lo = Set (1).Hi
      then
         return Re_Cp (Set (1).Lo);
      end if;
      Append (R, (if Negate then "[^" else "["));
      for S of Set loop
         Append (R, Re_Cp (S.Lo));
         if S.Hi > S.Lo then
            Append (R, (if S.Hi > S.Lo + 1 then "-" else "") & Re_Cp (S.Hi));
         end if;
      end loop;
      Append (R, "]");
      return To_String (R);
   end Class_Text;

   --  ---- the emitter ---------------------------------------------------------

   Scanner_Text : Unbounded_String;

   --  A lookahead the scanner does: `!x` or `&x`, with x alternatives that are
   --  each one literal or one token.
   type Look_Info is record
      Neg    : Boolean;
      Elem   : Element_Access;
      Follow : Element_Access;     --  a literal that must follow, or null
   end record;
   package Look_Vectors is new Ada.Containers.Vectors (Positive, Look_Info);

   function Scanner_Source return String is (To_String (Scanner_Text));

   function Num (N : Natural) return String is
      T : constant String := Natural'Image (N);
   begin
      return T (T'First + 1 .. T'Last);
   end Num;

   function Hex2 (N : Natural) return String is
      Digs : constant String := "0123456789abcdef";
   begin
      return [Digs (N / 16 + 1), Digs (N mod 16 + 1)];
   end Hex2;

   --  The external scanner for the `%as` / `%same` pairs: for each tag, an
   --  automaton (the token's own, as the C backend scans it) that captures the
   --  text, and a comparison that must find the same text again.
   function Scanner_C
     (Rules : HBNF_Grammar.Rule_Vectors.Vector;
      Tags, Tokens : Name_Vectors.Vector; Looks : Look_Vectors.Vector;
      Ws : String; Language : String) return String
   is
      Out_Text : U;
      Fn : constant String := "tree_sitter_" & Language & "_external_scanner_";

      procedure Ln (S : String) is
      begin
         Append (Out_Text, S & LF);
      end Ln;

      function Img (N : Natural) return String is
         T : constant String := Natural'Image (N);
      begin
         return T (T'First + 1 .. T'Last);
      end Img;
   begin
      Ln ("// Generated by hbnf (--backend=tree-sitter --ts-scanner): the external scanner of");
      Ln ("// " & Language & ".  `x %as tag` ... `%same tag` in the grammar: the first captures the");
      Ln ("// text of x, the second matches only that text again.  The captured tags are the");
      Ln ("// scanner's state (at most 1,024 octets, as tree-sitter saves it for every fork).");
      Ln ("#include ""tree_sitter/parser.h""");
      Ln ("#include <stdbool.h>");
      Ln ("#include <stdint.h>");
      Ln ("#include <stdlib.h>");
      Ln ("#include <string.h>");
      Ln ("");
      Append (Out_Text, "enum { ");
      for K in 0 .. Natural (Tags.Length) - 1 loop
         Append (Out_Text, "AS_" & Img (K) & ", SAME_" & Img (K) & ", ");
      end loop;
      for K in 0 .. Natural (Looks.Length) - 1 loop
         Append (Out_Text, "LOOK_" & Img (K) & ", ");
      end loop;
      Ln ("ERROR_SENTINEL };   // the order of `externals` in grammar.js");
      Ln ("");
      Ln ("#define STATE_MAX 1024");
      Ln ("// buf: a record for each tag held: its number, n, then n octets of UTF-8");
      Ln ("typedef struct { unsigned len; unsigned char buf[STATE_MAX]; } Scanner;");
      Ln ("");
      Ln ("void *" & Fn & "create(void) { return calloc(1, sizeof(Scanner)); }");
      Ln ("void " & Fn & "destroy(void *p) { free(p); }");
      Ln ("unsigned " & Fn & "serialize(void *p, char *out) {");
      Ln ("    Scanner *s = p;");
      Ln ("    memcpy(out, s->buf, s->len);");
      Ln ("    return s->len;");
      Ln ("}");
      Ln ("void " & Fn & "deserialize(void *p, const char *in, unsigned n) {");
      Ln ("    Scanner *s = p;");
      Ln ("    if (n > STATE_MAX) n = 0;");
      Ln ("    if (n) memcpy(s->buf, in, n);");
      Ln ("    s->len = n;");
      Ln ("}");
      Ln ("");
      Ln ("static unsigned utf8(uint32_t c, unsigned char *o) {");
      Ln ("    if (c < 0x80) { o[0] = (unsigned char)c; return 1; }");
      Ln ("    if (c < 0x800) { o[0] = 0xC0 | (c >> 6); o[1] = 0x80 | (c & 63); return 2; }");
      Ln ("    if (c < 0x10000) { o[0] = 0xE0 | (c >> 12); o[1] = 0x80 | ((c >> 6) & 63);");
      Ln ("                       o[2] = 0x80 | (c & 63); return 3; }");
      Ln ("    o[0] = 0xF0 | (c >> 18); o[1] = 0x80 | ((c >> 12) & 63);");
      Ln ("    o[2] = 0x80 | ((c >> 6) & 63); o[3] = 0x80 | (c & 63); return 4;");
      Ln ("}");
      Ln ("");
      Ln ("// The text again: the last tag held with this number, matched octet for octet.");
      Ln ("static bool same(Scanner *s, TSLexer *lx, unsigned tag) {");
      Ln ("    unsigned pos = 0, i = 0, n;");
      Ln ("    int found = -1;");
      Ln ("    const unsigned char *t;");
      Ln ("    while (pos < s->len) {");
      Ln ("        if (s->buf[pos] == tag) found = (int)pos;");
      Ln ("        pos += 2 + s->buf[pos + 1];");
      Ln ("    }");
      Ln ("    if (found < 0) return false;");
      Ln ("    n = s->buf[found + 1];");
      Ln ("    t = s->buf + found + 2;");
      Ln ("    while (i < n) {");
      Ln ("        unsigned char o[4];");
      Ln ("        unsigned m;");
      Ln ("        if (lx->eof(lx)) return false;");
      Ln ("        m = utf8((uint32_t)lx->lookahead, o);");
      Ln ("        if (i + m > n || memcmp(t + i, o, m) != 0) return false;");
      Ln ("        lx->advance(lx, false);");
      Ln ("        i += m;");
      Ln ("    }");
      Ln ("    lx->mark_end(lx);");
      Ln ("    memmove(s->buf + found, s->buf + found + 2 + n, s->len - (found + 2 + n));");
      Ln ("    s->len -= 2 + n;");
      Ln ("    return true;");
      Ln ("}");
      Ln ("");
      for K in 1 .. Natural (Tags.Length) loop
         declare
            D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
            Ok  : Boolean;
            Why : U;
            Lo, Hi, To, First, Acc : U;
            T   : constant String := Img (K - 1);
         begin
            HBNF_Lookahead.Token_Dfa (Rules, To_String (Tokens (K)), D, Ok, Why);
            if not Ok then
               raise Parse_Error with "the scanner for `" & To_String (Tokens (K))
                 & "` cannot be made: " & To_String (Why);
            end if;
            HBNF_Lookahead.Dfa_Tables (D, Lo, Hi, To, First, Acc);
            Ln ("// " & To_String (Tags (K)) & ": the text of `" & To_String (Tokens (K)) & "`");
            Ln ("static bool as_" & T & "(Scanner *s, TSLexer *lx) {");
            Ln ("    static const uint32_t lo[] = {" & To_String (Lo) & "};");
            Ln ("    static const uint32_t hi[] = {" & To_String (Hi) & "};");
            Ln ("    static const uint16_t to[] = {" & To_String (To) & "};");
            Ln ("    static const uint16_t first[] = {" & To_String (First) & "};");
            Ln ("    static const unsigned char acc[] = {" & To_String (Acc) & "};");
            Ln ("    unsigned char tmp[255];");
            Ln ("    unsigned tn = 0, best = 0, st = 0;");
            Ln ("    for (;;) {");
            Ln ("        unsigned char o[4];");
            Ln ("        unsigned k, m;");
            Ln ("        uint32_t c;");
            Ln ("        if (lx->eof(lx)) break;");
            Ln ("        c = (uint32_t)lx->lookahead;");
            Ln ("        for (k = first[st]; k < first[st + 1]; k++)");
            Ln ("            if (c >= lo[k] && c <= hi[k]) break;");
            Ln ("        if (k == first[st + 1]) break;");
            Ln ("        m = utf8(c, o);");
            Ln ("        if (tn + m > sizeof tmp) return false;");
            Ln ("        memcpy(tmp + tn, o, m);");
            Ln ("        tn += m;");
            Ln ("        lx->advance(lx, false);");
            Ln ("        st = to[k];");
            Ln ("        if (acc[st]) { lx->mark_end(lx); best = tn; }");
            Ln ("    }");
            Ln ("    if (!best || s->len + 2 + best > STATE_MAX) return false;");
            Ln ("    s->buf[s->len] = " & T & ";");
            Ln ("    s->buf[s->len + 1] = (unsigned char)best;");
            Ln ("    memcpy(s->buf + s->len + 2, tmp, best);");
            Ln ("    s->len += 2 + best;");
            Ln ("    return true;");
            Ln ("}");
            Ln ("");
         end;
      end loop;
      --  The lookaheads.  Each is a zero-width token: the white space the grammar
      --  skips is skipped, the token is marked as ending there, and the branches
      --  are run side by side over the text that follows.
      if not Looks.Is_Empty then
         Ln ("// A branch of a lookahead: a literal (compared as UTF-8, a fold to lower case for %i)");
         Ln ("// or a token's automaton.");
         Ln ("typedef struct { const unsigned char *lit; unsigned n; bool fold;");
         Ln ("                 const uint32_t *lo, *hi; const uint16_t *to, *first;");
         Ln ("                 const unsigned char *acc;");
         Ln ("                 unsigned at, st; bool dead, hit; } Branch;");
         Ln ("");
         Ln ("// The text at the lookahead, run through the branches; true if one matches.");
         Ln ("// A literal that has to come next (the last branch, when follow is set) is part of the");
         Ln ("// test, because tree-sitter cannot take the token back if what follows does not fit.");
         Ln ("static bool look(TSLexer *lx, Branch *b, unsigned nb, bool follow, bool neg) {");
         Ln ("    bool hit = false;");
         Ln ("    unsigned i;");
         Ln ("    for (i = 0; i < nb; i++) { b[i].at = 0; b[i].st = 0; b[i].dead = false; b[i].hit = false; }");
         Ln ("    for (;;) {");
         Ln ("        unsigned char o[4];");
         Ln ("        unsigned m = 0, live = 0;");
         Ln ("        uint32_t c = 0;");
         Ln ("        bool more = !lx->eof(lx);");
         Ln ("        if (more) { c = (uint32_t)lx->lookahead; m = utf8(c, o); }");
         Ln ("        for (i = 0; i < nb; i++) {");
         Ln ("            Branch *x = &b[i];");
         Ln ("            if (x->dead) continue;");
         Ln ("            if (x->lit) {");
         Ln ("                unsigned j;");
         Ln ("                if (x->at == x->n) { x->hit = true; x->dead = true; continue; }");
         Ln ("                if (!more || x->at + m > x->n) { x->dead = true; continue; }");
         Ln ("                for (j = 0; j < m; j++) {");
         Ln ("                    unsigned char a = o[j], z = x->lit[x->at + j];");
         Ln ("                    if (x->fold) { if (a >= 'A' && a <= 'Z') a += 32; if (z >= 'A' && z <= 'Z') z += 32; }");
         Ln ("                    if (a != z) break;");
         Ln ("                }");
         Ln ("                if (j < m) { x->dead = true; continue; }");
         Ln ("                x->at += m;");
         Ln ("                if (x->at == x->n) { x->hit = true; x->dead = true; continue; }");
         Ln ("            } else {");
         Ln ("                unsigned k;");
         Ln ("                if (x->at && x->acc[x->st]) { x->hit = true; x->dead = true; continue; }");
         Ln ("                if (!more) { x->dead = true; continue; }");
         Ln ("                for (k = x->first[x->st]; k < x->first[x->st + 1]; k++)");
         Ln ("                    if (c >= x->lo[k] && c <= x->hi[k]) break;");
         Ln ("                if (k == x->first[x->st + 1]) { x->dead = true; continue; }");
         Ln ("                x->st = x->to[k];");
         Ln ("                x->at++;");
         Ln ("            }");
         Ln ("            live++;");
         Ln ("        }");
         Ln ("        if (!live || !more) break;");
         Ln ("        lx->advance(lx, false);");
         Ln ("    }");
         Ln ("    for (i = 0; i < (follow ? nb - 1 : nb); i++) {");
         Ln ("        Branch *x = &b[i];");
         Ln ("        if (x->hit || (!x->lit && x->at && x->acc[x->st])) hit = true;");
         Ln ("    }");
         Ln ("    return (neg ? !hit : hit) && (!follow || b[nb - 1].hit);");
         Ln ("}");
         Ln ("");
         if Ws /= "" then
            declare
               D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
               Ok  : Boolean;
               Why : U;
               Lo, Hi, To, First, Acc : U;
            begin
               HBNF_Lookahead.Token_Dfa (Rules, Ws, D, Ok, Why);
               HBNF_Lookahead.Dfa_Tables (D, Lo, Hi, To, First, Acc);
               Ln ("// The white space the grammar skips between elements (`" & Ws & "`).");
               Ln ("static void skip_ws(TSLexer *lx) {");
               Ln ("    static const uint32_t lo[] = {" & To_String (Lo) & "};");
               Ln ("    static const uint32_t hi[] = {" & To_String (Hi) & "};");
               Ln ("    static const uint16_t to[] = {" & To_String (To) & "};");
               Ln ("    static const uint16_t first[] = {" & To_String (First) & "};");
               Ln ("    unsigned st = 0;");
               Ln ("    while (!lx->eof(lx)) {");
               Ln ("        uint32_t c = (uint32_t)lx->lookahead;");
               Ln ("        unsigned k;");
               Ln ("        for (k = first[st]; k < first[st + 1]; k++)");
               Ln ("            if (c >= lo[k] && c <= hi[k]) break;");
               Ln ("        if (k == first[st + 1]) break;");
               Ln ("        st = to[k];");
               Ln ("        lx->advance(lx, true);");
               Ln ("    }");
               Ln ("}");
               Ln ("");
            end;
         else
            Ln ("static void skip_ws(TSLexer *lx) { (void)lx; }");
            Ln ("");
         end if;
         for K in 1 .. Natural (Looks.Length) loop
            declare
               L : constant Look_Info := Looks (K);
               N : Natural := 0;
               Defs : U;
               Init : U;
               B : Natural := 0;

               procedure Add (X : Element_Access) is
               begin
                  B := B + 1;
                  if X.Kind = Literal then
                     declare
                        Lit : constant String := To_String (X.Lit);
                        Esc : U;
                     begin
                        for C of Lit loop
                           Append (Esc, "\x" & Hex2 (Character'Pos (C)));
                        end loop;
                        Append (Defs, "    static const unsigned char l" & Img (B - 1)
                          & "[] = """ & To_String (Esc) & """;" & LF);
                        Append (Init, "    b[" & Img (B - 1) & "] = (Branch){ .lit = l"
                          & Img (B - 1) & ", .n = " & Img (Lit'Length) & ", .fold = "
                          & (if X.No_Case then "true" else "false") & " };" & LF);
                     end;
                  else
                     declare
                        D   : HBNF_Lookahead.Dfa_State_Vectors.Vector;
                        Ok  : Boolean;
                        Why : U;
                        Lo, Hi, To, First, Acc : U;
                        T : constant String := Img (B - 1);
                     begin
                        HBNF_Lookahead.Token_Dfa (Rules, To_String (X.Name), D, Ok, Why);
                        HBNF_Lookahead.Dfa_Tables (D, Lo, Hi, To, First, Acc);
                        Append (Defs, "    static const uint32_t lo" & T & "[] = {" & To_String (Lo) & "};" & LF);
                        Append (Defs, "    static const uint32_t hi" & T & "[] = {" & To_String (Hi) & "};" & LF);
                        Append (Defs, "    static const uint16_t to" & T & "[] = {" & To_String (To) & "};" & LF);
                        Append (Defs, "    static const uint16_t first" & T & "[] = {" & To_String (First) & "};" & LF);
                        Append (Defs, "    static const unsigned char acc" & T & "[] = {" & To_String (Acc) & "};" & LF);
                        Append (Init, "    b[" & T & "] = (Branch){ .lo = lo" & T & ", .hi = hi" & T
                          & ", .to = to" & T & ", .first = first" & T & ", .acc = acc" & T & " };" & LF);
                     end;
                  end if;
               end Add;
            begin
               for X of L.Elem.Look loop
                  if X.Kind /= Alt then
                     Add (X);
                  end if;
               end loop;
               if L.Follow /= null then
                  Add (L.Follow);
               end if;
               N := B;
               Ln ("// " & (if L.Neg then "!" else "&") & " lookahead " & Img (K - 1));
               Ln ("static bool look_" & Img (K - 1) & "(TSLexer *lx) {");
               Append (Out_Text, To_String (Defs));
               Ln ("    Branch b[" & Img (N) & "];");
               Append (Out_Text, To_String (Init));
               Ln ("    skip_ws(lx);");
               Ln ("    lx->mark_end(lx);");
               Ln ("    return look(lx, b, " & Img (N) & ", "
                  & (if L.Follow /= null then "true" else "false") & ", "
                  & (if L.Neg then "true" else "false") & ");");
               Ln ("}");
               Ln ("");
            end;
         end loop;
      end if;
      Ln ("bool " & Fn & "scan(void *p, TSLexer *lx, const bool *valid) {");
      Ln ("    Scanner *s = p;");
      Ln ("    // not while tree-sitter is recovering from an error: it asks for every token");
      Ln ("    if (valid[ERROR_SENTINEL]) return false;");
      for K in 0 .. Natural (Tags.Length) - 1 loop
         Ln ("    if (valid[AS_" & Img (K) & "]) {");
         Ln ("        if (!as_" & Img (K) & "(s, lx)) return false;");
         Ln ("        lx->result_symbol = AS_" & Img (K) & ";");
         Ln ("        return true;");
         Ln ("    }");
         Ln ("    if (valid[SAME_" & Img (K) & "]) {");
         Ln ("        if (!same(s, lx, " & Img (K) & ")) return false;");
         Ln ("        lx->result_symbol = SAME_" & Img (K) & ";");
         Ln ("        return true;");
         Ln ("    }");
      end loop;
      for K in 0 .. Natural (Looks.Length) - 1 loop
         Ln ("    if (valid[LOOK_" & Img (K) & "]) {");
         Ln ("        if (!look_" & Img (K) & "(lx)) return false;");
         Ln ("        lx->result_symbol = LOOK_" & Img (K) & ";");
         Ln ("        return true;");
         Ln ("    }");
      end loop;
      Ln ("    return false;");
      Ln ("}");
      return To_String (Out_Text);
   end Scanner_C;

   function Emit
     (Rules     : HBNF_Grammar.Rule_Vectors.Vector;
      Language  : String;
      Conflicts : String  := "";
      Ordered   : Boolean := False;
      Scanner   : Boolean := False) return String
   is
      Output : U;
      Notes  : Name_Vectors.Vector;     --  what could not be said, once each
      Core   : Name_Vectors.Vector;     --  built-in token types used
      Ws_Rule : U;                      --  the rule the file skips between elements

      procedure Note (S : String) is
      begin
         for N of Notes loop
            if To_String (N) = S then
               return;
            end if;
         end loop;
         Notes.Append (To_Unbounded_String (S));
         HBNF_Grammar.Warn_Once ("ts:" & S, "", S);
      end Note;

      function Find (Name : String) return Natural is
      begin
         for K in 1 .. Natural (Rules.Length) loop
            if To_String (Rules (K).Name) = Name then
               return K;
            end if;
         end loop;
         return 0;
      end Find;

      function Is_Builtin (N : String) return Boolean is
        (Find (N) = 0 and then Is_Core_Name (N));

      function Is_Char (N : String) return Boolean is
        (Find (N) /= 0 and then Is_Char_Rule (Rules, N));

      function Core_Regex (N : String) return String is
      begin
         if N = "word" or else N = "atom" then
            return "[A-Za-z_\-][A-Za-z0-9_.\-]*";
         elsif N = "str" then
            return "\""(?:[^""\\]|\\.)*\""";
         elsif N = "bool" then
            return "(?:true|false)";
         elsif N = "float" then
            return "-?[0-9]+(?:\.[0-9]+)?";
         else
            return "-?[0-9]+";               --  int, dec, uN, iN
         end if;
      end Core_Regex;

      procedure Use_Core (N : String) is
      begin
         for C of Core loop
            if To_String (C) = N then
               return;
            end if;
         end loop;
         Core.Append (To_Unbounded_String (N));
      end Use_Core;

      --  Can the character rule match nothing?  (A tree-sitter token cannot.)
      function Nullable_Alts
        (V : Element_Vectors.Vector; Depth : Natural) return Boolean;

      function Nullable_Elem (E : Element_Access; Depth : Natural) return Boolean is
      begin
         if E.Min = 0 then
            return True;
         end if;
         case E.Kind is
            when Literal => return Length (E.Lit) = 0;
            when Group => return Nullable_Alts (E.Items, Depth + 1);
            when Name =>
               declare
                  N : constant String := To_String (E.Name);
               begin
                  return Depth < 12 and then Is_Char (N)
                    and then Nullable_Alts (Rules (Find (N)).Pattern, Depth + 1);
               end;
            when others => return False;
         end case;
      end Nullable_Elem;

      function Nullable_Alts
        (V : Element_Vectors.Vector; Depth : Natural) return Boolean
      is
         All_Null : Boolean := True;
      begin
         for K in 1 .. Natural (V.Length) + 1 loop
            if K > Natural (V.Length) or else V (K).Kind = Alt then
               if All_Null then
                  return True;
               end if;
               All_Null := True;
            elsif not Nullable_Elem (V (K), Depth) then
               All_Null := False;
            end if;
         end loop;
         return False;
      end Nullable_Alts;

      --  A character rule that is only a choice among other character rules
      --  (`label = identifier / digits`) is not a token of its own: two tokens
      --  with the same text, in a state that wants either, are one the lexer
      --  picks between by itself.  It is a phrase rule, `choice($.identifier,
      --  $.digits)`, and the parser decides.
      function Alias_Union (J : Natural) return Boolean is
         V  : Element_Vectors.Vector renames Rules (J).Pattern;
         St : Natural := 1;
      begin
         if not Is_Char_Rule (Rules, To_String (Rules (J).Name))
           or else Rules (J).Jet_Code /= Null_Unbounded_String
           or else V.Is_Empty
         then
            return False;
         end if;
         for K in 1 .. Natural (V.Length) + 1 loop
            if K > Natural (V.Length) or else V (K).Kind = Alt then
               if K - St /= 1 then
                  return False;
               end if;
               declare
                  E : constant Element_Access := V (St);
               begin
                  if E.Kind /= Name or else E.Min /= 1 or else E.Max /= 1
                    or else not (Is_Char (To_String (E.Name))
                                 or else Is_Builtin (To_String (E.Name)))
                  then
                     return False;
                  end if;
               end;
               St := K + 1;
            end if;
         end loop;
         return True;
      end Alias_Union;

      function Rule_Nullable (N : String) return Boolean is
        (Is_Char (N) and then Nullable_Alts (Rules (Find (N)).Pattern, 0));

      --  ---- a character rule as a regular expression ------------------------

      type Piece is record
         Text   : U;
         Atomic : Boolean;
      end record;

      function Mk (S : String; Atomic : Boolean) return Piece is
        ((To_Unbounded_String (S), Atomic));

      function Re_Alts (V : Element_Vectors.Vector; Depth : Natural) return Piece;

      --  When the choice is a set of single code points (ranges, one-character
      --  literals, rules and groups of those) it is one class.
      function Class_Of
        (V : Element_Vectors.Vector; Depth : Natural; Ranges : in out Span_Vectors.Vector)
        return Boolean
      is
         Count : Natural := 0;
         St    : Natural := 1;
      begin
         if Depth > 12 then
            return False;
         end if;
         for K in 1 .. Natural (V.Length) + 1 loop
            if K > Natural (V.Length) or else V (K).Kind = Alt then
               if K - St /= 1 then
                  return False;                -- not exactly one element
               end if;
               declare
                  E : constant Element_Access := V (St);
               begin
                  if E.Min /= 1 or else E.Max /= 1 then
                     return False;
                  end if;
                  case E.Kind is
                     when Char_Range =>
                        Ranges.Append (Span'((E.Lo, E.Hi)));
                     when Literal =>
                        declare
                           S : constant String := To_String (E.Lit);
                           C : Character;
                        begin
                           if S'Length /= 1 or else Character'Pos (S (S'First)) >= 128 then
                              return False;
                           end if;
                           C := S (S'First);
                           Ranges.Append (Span'((Character'Pos (C), Character'Pos (C))));
                           if E.No_Case and then C in 'a' .. 'z' then
                              Ranges.Append (Span'((Character'Pos (C) - 32, Character'Pos (C) - 32)));
                           elsif E.No_Case and then C in 'A' .. 'Z' then
                              Ranges.Append (Span'((Character'Pos (C) + 32, Character'Pos (C) + 32)));
                           end if;
                        end;
                     when Name =>
                        declare
                           N : constant String := To_String (E.Name);
                        begin
                           if not Is_Char (N)
                             or else Rules (Find (N)).Jet_Code /= Null_Unbounded_String
                             or else not Class_Of (Rules (Find (N)).Pattern,
                                                   Depth + 1, Ranges)
                           then
                              return False;
                           end if;
                        end;
                     when Group =>
                        if not Class_Of (E.Items, Depth + 1, Ranges) then
                           return False;
                        end if;
                     when others =>
                        return False;
                  end case;
               end;
               Count := Count + 1;
               St := K + 1;
            end if;
         end loop;
         return Count > 0;
      end Class_Of;

      function Quantified (P : Piece; Min : Natural; Max : Integer) return Piece is
         Base : constant String :=
           (if P.Atomic or else (Min = 1 and then Max = 1) then To_String (P.Text)
            else "(?:" & To_String (P.Text) & ")");
      begin
         if Max = 0 then
            return Mk ("(?:)", True);                --  `0x`: nothing at all
         elsif Min = 1 and then Max = 1 then
            return P;
         elsif Min = 0 and then Max = 1 then
            return Mk (Base & "?", False);
         elsif Min = 0 and then Max < 0 then
            return Mk (Base & "*", False);
         elsif Min = 1 and then Max < 0 then
            return Mk (Base & "+", False);
         elsif Max < 0 then
            return Mk (Base & "{" & Img (Min) & ",}", False);
         elsif Min = Max then
            return Mk (Base & "{" & Img (Min) & "}", False);
         else
            return Mk (Base & "{" & Img (Min) & "," & Img (Max) & "}", False);
         end if;
      end Quantified;

      function Re_Elem (E : Element_Access; Depth : Natural) return Piece is
         P : Piece;
      begin
         if Depth > 24 then
            Note ("a character rule is too deep (or recursive) to be one regular expression");
            return Mk ("(?:)", True);
         end if;
         case E.Kind is
            when Literal =>
               declare
                  S : constant String := To_String (E.Lit);
                  R : U;
               begin
                  for C of S loop
                     if E.No_Case and then C in 'a' .. 'z' | 'A' .. 'Z' then
                        declare
                           Lo : constant Character :=
                             (if C in 'A' .. 'Z'
                              then Character'Val (Character'Pos (C) + 32) else C);
                           Up : constant Character :=
                             (if C in 'a' .. 'z'
                              then Character'Val (Character'Pos (C) - 32) else C);
                        begin
                           Append (R, "[" & Lo & Up & "]");
                        end;
                     elsif Character'Pos (C) >= 128 then
                        Append (R, C);          --  UTF-8, as it is
                     else
                        Append (R, Re_Cp (Character'Pos (C)));
                     end if;
                  end loop;
                  P := (R, S'Length = 1 or else (E.No_Case and then S'Length = 1));
                  if S'Length = 0 then
                     P := Mk ("(?:)", True);
                  end if;
               end;
            when Char_Range =>
               declare
                  V : Span_Vectors.Vector;
               begin
                  V.Append (Span'((E.Lo, E.Hi)));
                  P := Mk (Class_Text (V), True);
               end;
            when Name =>
               declare
                  N : constant String := To_String (E.Name);
                  J : constant Natural := Find (N);
               begin
                  if J = 0 then
                     if Is_Core_Name (N) then
                        P := Mk (Core_Regex (N), False);
                     else
                        P := Mk ("(?:)", True);
                     end if;
                  elsif Rules (J).Jet_Code /= Null_Unbounded_String then
                     Note ("a scanner action (" & N & ") is C code; it needs"
                       & " an external scanner in tree-sitter");
                     P := Mk ("(?:)", True);
                  else
                     P := Re_Alts (Rules (J).Pattern, Depth + 1);
                  end if;
               end;
            when Group =>
               P := Re_Alts (E.Items, Depth + 1);
            when others =>
               P := Mk ("(?:)", True);
         end case;
         return Quantified (P, E.Min, E.Max);
      end Re_Elem;

      function Re_Alts (V : Element_Vectors.Vector; Depth : Natural) return Piece is
         Ranges : Span_Vectors.Vector;
         R      : U;
         Br     : U;
         Elems  : Natural := 0;
         Last_P : Piece;
         First  : Boolean := True;
         Branches : Natural := 0;
         Single_Atomic : Boolean := False;
      begin
         if Class_Of (V, Depth, Ranges) then
            return Mk (Class_Text (Ranges), True);
         end if;
         for K in 1 .. Natural (V.Length) + 1 loop
            if K > Natural (V.Length) or else V (K).Kind = Alt then
               if not First then
                  Append (R, "|");
               end if;
               Append (R, (if Elems = 0 then "(?:)" else To_String (Br)));
               Branches := Branches + 1;
               Single_Atomic := Branches = 1 and then Elems = 1 and then Last_P.Atomic;
               Br := Null_Unbounded_String;
               Elems := 0;
               First := False;
            elsif V (K).Kind = Block then
               Note ("a lookahead or a test inside a character rule is left out");
            else
               Last_P := Re_Elem (V (K), Depth);
               Append (Br, To_String (Last_P.Text));
               Elems := Elems + 1;
            end if;
         end loop;
         if Branches = 1 then
            return (R, Single_Atomic);
         end if;
         return Mk ("(?:" & To_String (R) & ")", True);     --  a choice, in a sequence
      end Re_Alts;

      --  The rule's regex, not empty: `*x` alone is `x+` (the references to it
      --  are optional).
      function Token_Regex (R : Rule) return String is
      begin
         if Rule_Nullable (To_String (R.Name))
           and then Natural (R.Pattern.Length) = 1
           and then R.Pattern (1).Min = 0
         then
            declare
               E : constant Element_Access := new HBNF_Grammar.Element'(R.Pattern (1).all);
               V : Element_Vectors.Vector;
            begin
               E.Min := 1;
               V.Append (E);
               return To_String (Re_Alts (V, 0).Text);
            end;
         end if;
         return To_String (Re_Alts (R.Pattern, 0).Text);
      end Token_Regex;

      --  ---- which phrase rules can match nothing -------------------------------
      --  tree-sitter refuses a rule that matches the empty string (the start
      --  rule excepted), so such a rule is defined by what it matches that is
      --  not empty, and each place that names it says `optional($.it)`.

      Pnull : array (1 .. Natural (Rules.Length)) of Boolean := (others => False);

      function Alts_Null (V : Element_Vectors.Vector) return Boolean;

      function El_Base_Null (E : Element_Access) return Boolean is
      begin
         case E.Kind is
            when Literal => return Length (E.Lit) = 0;
            when Name =>
               declare
                  N : constant String := To_String (E.Name);
                  J : constant Natural := Find (N);
               begin
                  if J = 0 then
                     return False;
                  elsif Is_Char_Rule (Rules, N) then
                     return Rule_Nullable (N);
                  end if;
                  return Pnull (J);
               end;
            when Group => return Alts_Null (E.Items);
            when Block => return True;
            when others => return False;
         end case;
      end El_Base_Null;

      function El_Null (E : Element_Access) return Boolean is
        (E.Min = 0 or else E.Max = 0 or else El_Base_Null (E));

      function Alts_Null (V : Element_Vectors.Vector) return Boolean is
         All_Null : Boolean := True;
      begin
         for K in 1 .. Natural (V.Length) + 1 loop
            if K > Natural (V.Length) or else V (K).Kind = Alt then
               if All_Null then
                  return True;
               end if;
               All_Null := True;
            elsif not El_Null (V (K)) then
               All_Null := False;
            end if;
         end loop;
         return False;
      end Alts_Null;

      --  ---- a phrase rule as seq / choice / repeat / optional -----------------

      function Ph_Alts (V : Element_Vectors.Vector) return Node_Access;
      function Ne_Alts (V : Element_Vectors.Vector) return Node_Access;

      --  One branch is itself; several are `choice`, and with Ordered the first
      --  is given the highest dynamic precedence (hbnf's first match wins).
      function Choice (Branches : Node_Vectors.Vector) return Node_Access is
         Ranked : Node_Vectors.Vector;
         N : constant Natural := Natural (Branches.Length);
      begin
         if N = 1 then
            return Branches (1);
         elsif not Ordered then
            return Call ("choice", Branches);
         end if;
         for K in 1 .. N loop
            declare
               V : Node_Vectors.Vector;
            begin
               V.Append (Atom (Img (N - K + 1)));
               V.Append (Branches (K));
               Ranked.Append (Call ("prec.dynamic", V));
            end;
         end loop;
         return Call ("choice", Ranked);
      end Choice;

      function Repeated (X : Node_Access; Min : Natural; Max : Integer)
        return Node_Access
      is
         Parts : Node_Vectors.Vector;
      begin
         if Min = 1 and then Max = 1 then
            return X;
         elsif Min = 0 and then Max = 1 then
            return Call1 ("optional", X);
         elsif Min = 0 and then Max < 0 then
            return Call1 ("repeat", X);
         elsif Min = 1 and then Max < 0 then
            return Call1 ("repeat1", X);
         elsif Max < 0 then                 --  n or more
            for K in 1 .. Min - 1 loop
               Parts.Append (X);
            end loop;
            Parts.Append (Call1 ("repeat1", X));
            return Call ("seq", Parts);
         else                               --  n to m: n copies, then nested optionals
            declare
               Tail : Node_Access := null;
            begin
               for K in 1 .. Max - Min loop
                  if Tail = null then
                     Tail := Call1 ("optional", X);
                  else
                     declare
                        V : Node_Vectors.Vector;
                     begin
                        V.Append (X);
                        V.Append (Tail);
                        Tail := Call1 ("optional", Call ("seq", V));
                     end;
                  end if;
               end loop;
               for K in 1 .. Min loop
                  Parts.Append (X);
               end loop;
               if Tail /= null then
                  Parts.Append (Tail);
               end if;
               if Natural (Parts.Length) = 1 then
                  return Parts (1);
               end if;
               return Call ("seq", Parts);
            end;
         end if;
      end Repeated;

      --  `x %as tag` ... `%same tag`: tree-sitter cannot make a text repeat, so the
      --  `%same` is written as another x, and any text will do.
      Tag_Elems : Element_Vectors.Vector;
      Tag_Names : Name_Vectors.Vector;

      --  The tags done by the external scanner: the tag, and the token rule it
      --  captures.
      Sc_Tags   : Name_Vectors.Vector;
      Sc_Tokens : Name_Vectors.Vector;

      Sc_Looks : Look_Vectors.Vector;

      --  Can the scanner do the lookahead E?  Each branch is one literal, or one
      --  token the automaton scans; and the white space, if there is any, scans.
      function Look_Ok (E : Element_Access) return Boolean is
         Prev_Atom : Boolean := False;
      begin
         if not Scanner then
            return False;
         end if;
         if Ws_Rule /= Null_Unbounded_String
           and then not Is_Dfa_Token (Rules, To_String (Ws_Rule))
         then
            return False;
         end if;
         for X of E.Look loop
            if X.Kind = Alt then
               Prev_Atom := False;
            elsif Prev_Atom then
               return False;                 --  a sequence, not alternatives
            else
               Prev_Atom := True;
               if X.Kind = Name
                 and then (Find (To_String (X.Name)) = 0
                           or else not Is_Dfa_Token (Rules, To_String (X.Name)))
               then
                  return False;
               end if;
            end if;
         end loop;
         return True;
      end Look_Ok;

      --  The literal the sequence goes on with after the lookahead being made, if
      --  it is a single one (Ph_Seq sets it).
      Cur_Follow : Element_Access := null;

      --  What a lookahead tests, as text: two with the same text are one token,
      --  so every place that wants it gets the same one.
      function Look_Key (E, Follow : Element_Access) return String is
         R : U;
      begin
         Append (R, (if E.Op = B_Not then "!" else "&"));
         for X of E.Look loop
            case X.Kind is
               when Alt     => Append (R, "|");
               when Literal => Append (R, "L" & (if X.No_Case then "i" else "c")
                                         & To_String (X.Lit));
               when Name    => Append (R, "N" & To_String (X.Name));
               when others  => Append (R, "?");
            end case;
            Append (R, ASCII.NUL);
         end loop;
         if Follow /= null then
            Append (R, "F" & To_String (Follow.Lit));
         end if;
         return To_String (R);
      end Look_Key;

      function Look_Id (E : Element_Access) return Natural is
      begin
         for K in 1 .. Natural (Sc_Looks.Length) loop
            if Look_Key (Sc_Looks (K).Elem, Sc_Looks (K).Follow)
               = Look_Key (E, Cur_Follow)
            then
               return K;
            end if;
         end loop;
         Sc_Looks.Append
           (Look_Info'(Neg => E.Op = B_Not, Elem => E, Follow => Cur_Follow));
         return Natural (Sc_Looks.Length);
      end Look_Id;

      function Sc_Find (Tag : String) return Natural is
      begin
         for K in 1 .. Natural (Sc_Tags.Length) loop
            if To_String (Sc_Tags (K)) = Tag then
               return K;
            end if;
         end loop;
         return 0;
      end Sc_Find;

      --  Can the scanner capture E (the element before a `%as`)?
      function Scannable (E : Element_Access; Tag : String) return Boolean is
      begin
         if not Scanner or else E.Kind /= Name or else E.Min /= 1
           or else E.Max /= 1 or else Find (To_String (E.Name)) = 0
           or else not Is_Dfa_Token (Rules, To_String (E.Name))
         then
            return False;
         end if;
         declare
            K : constant Natural := Sc_Find (Tag);
         begin
            return K = 0 or else To_String (Sc_Tokens (K)) = To_String (E.Name);
         end;
      end Scannable;

      procedure Note_Dropped (E : Element_Access) is
      begin
         if E.Op in B_Not | B_And then
            Note ("a lookahead (!x, &x) is left out: tree-sitter has none");
         elsif E.Op in B_As | B_Same and then Sc_Find (To_String (E.Ctx)) /= 0 then
            null;                              --  the scanner does it
         elsif E.Op in B_As | B_Same then
            Note ("a back-reference (%as, %same: a closing tag that repeats"
              & " the opening one) is approximated: the second is any text of"
              & " the same kind, tree-sitter cannot make it repeat the first");
         elsif E.Op /= B_Action then
            Note ("a context test or binding (?, %bind, %scope, %where)"
              & " is left out: tree-sitter has none");
         end if;
      end Note_Dropped;

      --  The element without its repetition, as it reads where it may be empty
      --  (a rule that can be empty is `optional`).
      function Base_Full (E : Element_Access) return Node_Access is
      begin
         case E.Kind is
            when Literal =>
               declare
                  S : constant String := To_String (E.Lit);
               begin
                  if S'Length = 0 then
                     return Call ("blank", Node_Vectors.Empty_Vector);
                  elsif E.No_Case then
                     return Atom
                       ("/" & To_String
                          (Re_Elem (new HBNF_Grammar.Element'
                                      (E.all with delta Min => 1, Max => 1), 0).Text)
                        & "/");
                  end if;
                  return Atom (Js_Str (S));
               end;
            when Name =>
               declare
                  N : constant String := To_String (E.Name);
                  X : Node_Access;
               begin
                  if Is_Builtin (N) then
                     Use_Core (N);
                  end if;
                  X := Atom ("$." & Js_Name (N));
                  if El_Base_Null (E) then
                     X := Call1 ("optional", X);
                  end if;
                  return X;
               end;
            when Group =>
               return Ph_Alts (E.Items);
            when Char_Range =>
               return Atom
                 ("/" & To_String
                    (Re_Elem (new HBNF_Grammar.Element'
                                (E.all with delta Min => 1, Max => 1), 0).Text) & "/");
            when Block =>
               if E.Op in B_Not | B_And and then Look_Ok (E) then
                  return Atom ("$._look_" & Num (Look_Id (E) - 1));
               end if;
               Note_Dropped (E);
               if E.Op = B_Same and then Sc_Find (To_String (E.Ctx)) /= 0 then
                  return Atom ("$._same_" & Js_Name (To_String (E.Ctx)));
               end if;
               if E.Op = B_Same then
                  for K in reverse 1 .. Natural (Tag_Names.Length) loop
                     if Tag_Names (K) = E.Ctx then
                        return Base_Full (Tag_Elems (K));
                     end if;
                  end loop;
               end if;
               return null;
            when Bit_Field =>
               raise Parse_Error with
                 "a rule of bit fields cannot be emitted as a tree-sitter grammar";
            when others =>
               return null;
         end case;
      end Base_Full;

      --  What the element matches that is not empty (null: it matches nothing
      --  else).  Only asked of an element whose base can be empty.
      function Base_Ne (E : Element_Access) return Node_Access is
      begin
         case E.Kind is
            when Name =>
               return Atom ("$." & Js_Name (To_String (E.Name)));   --  defined non-empty
            when Group =>
               return Ne_Alts (E.Items);
            when Block =>
               Note_Dropped (E);
               return null;
            when others =>
               return null;
         end case;
      end Base_Ne;

      function Ph_Elem (E : Element_Access) return Node_Access is
         Base : Node_Access;
      begin
         if E.Max = 0 then
            return null;                       --  `0x`: nothing at all
         end if;
         if El_Base_Null (E) then
            if E.Max = 1 then
               return Base_Full (E);           --  once, or not at all
            end if;
            Base := Base_Ne (E);               --  a run of what is not empty
            return (if Base = null then null else Repeated (Base, 0, E.Max));
         end if;
         Base := Base_Full (E);
         return (if Base = null then null else Repeated (Base, E.Min, E.Max));
      end Ph_Elem;

      function Ne_Elem (E : Element_Access) return Node_Access is
         Base : Node_Access;
      begin
         if E.Max = 0 then
            return null;
         end if;
         if El_Base_Null (E) then
            Base := Base_Ne (E);
            return (if Base = null then null
                    else Repeated (Base, 1, E.Max));
         end if;
         Base := Base_Full (E);
         return (if Base = null then null
                 else Repeated (Base, (if E.Min = 0 then 1 else E.Min), E.Max));
      end Ne_Elem;

      function Ph_Seq (V : Element_Vectors.Vector; St, En : Natural)
        return Node_Access
      is
         Parts : Node_Vectors.Vector;
      begin
         for K in St .. En loop
            if V (K).Kind = Block and then V (K).Op = B_As and then K > St then
               Tag_Elems.Append (V (K - 1));
               Tag_Names.Append (V (K).Ctx);
               if Scannable (V (K - 1), To_String (V (K).Ctx))
                 and then not Parts.Is_Empty
               then
                  if Sc_Find (To_String (V (K).Ctx)) = 0 then
                     Sc_Tags.Append (V (K).Ctx);
                     Sc_Tokens.Append (V (K - 1).Name);
                  end if;
                  Parts.Replace_Element
                    (Parts.Last_Index,
                     Atom ("alias($._as_" & Js_Name (To_String (V (K).Ctx))
                           & ", $." & Js_Name (To_String (V (K - 1).Name)) & ")"));
               end if;
            end if;
            Cur_Follow :=
              (if V (K).Kind = Block and then V (K).Op in B_Not | B_And
                 and then K < En and then V (K + 1).Kind = Literal
                 and then V (K + 1).Min = 1 and then V (K + 1).Max = 1
                 and then Length (V (K + 1).Lit) > 0
               then V (K + 1) else null);
            declare
               N : constant Node_Access := Ph_Elem (V (K));
            begin
               Cur_Follow := null;
               if N /= null then
                  Parts.Append (N);
               end if;
            end;
         end loop;
         if Parts.Is_Empty then
            return Call ("blank", Node_Vectors.Empty_Vector);
         elsif Natural (Parts.Length) = 1 then
            return Parts (1);
         end if;
         return Call ("seq", Parts);
      end Ph_Seq;

      --  What the sequence matches that is not empty: the first thing that is
      --  not empty, after only empties, then the rest as it reads.
      function Ne_Seq (V : Element_Vectors.Vector; St, En : Natural)
        return Node_Access
      is
         Choices : Node_Vectors.Vector;
      begin
         for I in St .. En loop
            declare
               Head : constant Node_Access := Ne_Elem (V (I));
            begin
               if Head /= null then
                  declare
                     Parts : Node_Vectors.Vector;
                  begin
                     Parts.Append (Head);
                     for J in I + 1 .. En loop
                        declare
                           N : constant Node_Access := Ph_Elem (V (J));
                        begin
                           if N /= null then
                              Parts.Append (N);
                           end if;
                        end;
                     end loop;
                     Choices.Append
                       (if Natural (Parts.Length) = 1 then Parts (1)
                        else Call ("seq", Parts));
                  end;
               end if;
            end;
            exit when not El_Null (V (I));
         end loop;
         if Choices.Is_Empty then
            return null;
         elsif Natural (Choices.Length) = 1 then
            return Choices (1);
         end if;
         return Call ("choice", Choices);
      end Ne_Seq;

      function Ph_Alts (V : Element_Vectors.Vector) return Node_Access is
         Branches : Node_Vectors.Vector;
         St : Natural := 1;
      begin
         for K in 1 .. Natural (V.Length) + 1 loop
            if K > Natural (V.Length) or else V (K).Kind = Alt then
               Branches.Append (Ph_Seq (V, St, K - 1));
               St := K + 1;
            end if;
         end loop;
         return Choice (Branches);
      end Ph_Alts;

      function Ne_Alts (V : Element_Vectors.Vector) return Node_Access is
         Branches : Node_Vectors.Vector;
         St : Natural := 1;
      begin
         for K in 1 .. Natural (V.Length) + 1 loop
            if K > Natural (V.Length) or else V (K).Kind = Alt then
               declare
                  N : constant Node_Access := Ne_Seq (V, St, K - 1);
               begin
                  if N /= null then
                     Branches.Append (N);
                  end if;
               end;
               St := K + 1;
            end if;
         end loop;
         if Branches.Is_Empty then
            return null;
         end if;
         return Choice (Branches);
      end Ne_Alts;

      procedure Comment (S : String; Ind : String) is
         Start : Natural := S'First;
      begin
         for K in S'Range loop
            if S (K) = LF or else K = S'Last then
               declare
                  Stop : constant Natural := (if S (K) = LF then K - 1 else K);
               begin
                  if Stop >= Start then
                     Append (Output, Ind & "// "
                       & S (Start .. Stop) & LF);
                  end if;
                  Start := K + 1;
               end;
            end if;
         end loop;
      end Comment;

      --  ---- which rules the grammar uses -------------------------------------
      --  Those a phrase rule reaches from the root.  A character rule is a token:
      --  what it names is inlined into its regular expression, not emitted.

      Wanted : array (1 .. Natural (Rules.Length)) of Boolean := (others => False);

      procedure Want (N : String);

      procedure Want_Els (V : Element_Vectors.Vector) is
      begin
         for E of V loop
            case E.Kind is
               when Name => Want (To_String (E.Name));
               when Group => Want_Els (E.Items);
               when others => null;
            end case;
         end loop;
      end Want_Els;

      procedure Want (N : String) is
         J : constant Natural := Find (N);
      begin
         if J = 0 or else Wanted (J) then
            return;
         end if;
         Wanted (J) := True;
         if (not Is_Char_Rule (Rules, N) or else Alias_Union (J))
           and then Rules (J).Jet_Code = Null_Unbounded_String
         then
            Want_Els (Rules (J).Pattern);
         end if;
      end Want;

      Body_Text : U;                 --  the rules, built before the header
      Root_Loops : Boolean := False; --  the start rule can be empty and is also used inside

      function Names_Root (V : Element_Vectors.Vector) return Boolean is
      begin
         for E of V loop
            if (E.Kind = Name and then not Rules.Is_Empty
                and then E.Name = Rules (1).Name)
              or else (E.Kind = Group and then Names_Root (E.Items))
            then
               return True;
            end if;
         end loop;
         return False;
      end Names_Root;
   begin
      for R of Rules loop
         if R.Whitespace /= Null_Unbounded_String then
            Ws_Rule := R.Whitespace;
            exit;
         end if;
      end loop;
      if not Rules.Is_Empty then
         Want (To_String (Rules (1).Name));
      end if;
      declare
         Changed : Boolean := True;
      begin
         while Changed loop
            Changed := False;
            for J in 1 .. Natural (Rules.Length) loop
               if not Pnull (J)
                 and then Rules (J).Jet_Code = Null_Unbounded_String
                 and then (not Is_Char_Rule (Rules, To_String (Rules (J).Name))
                           or else Alias_Union (J))
                 and then Alts_Null (Rules (J).Pattern)
               then
                  Pnull (J) := True;
                  Changed := True;
               end if;
            end loop;
         end loop;
      end;

      if not Rules.Is_Empty and then Pnull (1) then
         for J in 1 .. Natural (Rules.Length) loop
            if Wanted (J) and then not Is_Char_Rule (Rules, To_String (Rules (J).Name))
              and then Names_Root (Rules (J).Pattern)
            then
               Root_Loops := True;
            end if;
         end loop;
      end if;
      if Root_Loops then
         --  tree-sitter lets only the start rule be empty, and not if it is used
         --  inside: a start rule of its own, and the root defined by what it
         --  matches that is not empty
         Append (Body_Text, "    source_file: $ => optional($."
           & Js_Name (To_String (Rules (1).Name)) & ")," & LF);
      end if;

      for J in 1 .. Natural (Rules.Length) loop
         declare
            R : constant Rule := Rules (J);
            N : constant String := To_String (R.Name);
            Node : Node_Access := null;
         begin
            if Wanted (J) and then N /= To_String (Ws_Rule) then
               Output := Null_Unbounded_String;
               Comment (To_String (R.Leading_Comment), "    ");
               if R.Jet_Code /= Null_Unbounded_String then
                  Note ("a scanner action (" & N & ") is C code; it needs an"
                    & " external scanner in tree-sitter");
                  Append (Output, "    " & Js_Name (N) & ": $ => /ÿÿ/,"
                    & "  // scanner action: not expressible" & LF);
               elsif Is_Char_Rule (Rules, N) and then not Alias_Union (J) then
                  Append (Output, "    " & Js_Name (N) & ": $ => /"
                    & Token_Regex (R) & "/," & LF);
               else
                  if R.Left_Bases > 0 then
                     declare
                        Parts : Node_Vectors.Vector;
                     begin
                        Parts.Append (Ph_Alts (Base_Branches (R)));
                        Parts.Append
                          (Call1 ("repeat", Ph_Alts (Tail_Branches (R))));
                        Node := Call ("seq", Parts);
                     end;
                  elsif Pnull (J) and then (J /= 1 or else Root_Loops) then
                     Node := Ne_Alts (R.Pattern);
                     if Node = null then
                        Node := Call ("blank", Node_Vectors.Empty_Vector);
                     end if;
                  else
                     Node := Ph_Alts (R.Pattern);
                  end if;
                  Append (Output, "    " & Js_Name (N) & ": $ => "
                    & Layout (Node, 4) & "," & LF);
               end if;
               Append (Body_Text, To_String (Output));
            end if;
         end;
      end loop;
      for C of Core loop
         Append (Body_Text, "    " & Js_Name (To_String (C)) & ": $ => /"
           & Core_Regex (To_String (C)) & "/," & LF);
      end loop;

      --  the whole file
      Output := Null_Unbounded_String;
      Append (Output, "// Generated by hbnf (--backend=tree-sitter).  The grammar of" & LF
        & "// " & Language & " as hbnf reads it; edit the .hbnf, not this." & LF);
      if not Notes.Is_Empty then
         Append (Output, "//" & LF & "// Not expressed in tree-sitter, and left out:" & LF);
         for N of Notes loop
            Append (Output, "//   - " & To_String (N) & LF);
         end loop;
      end if;
      Append (Output, "//" & LF
        & "// hbnf's choice is ordered (the first alternative that matches is kept)." & LF
        & "// tree-sitter's is not: where two alternatives can match alike," & LF
        & "// `tree-sitter generate` reports a conflict, and the author says which" & LF
        & "// wins (`conflicts`, `prec`, `prec.dynamic`)." & LF & LF);
      Append (Output, "module.exports = grammar({" & LF
        & "  name: '" & Language & "'," & LF & LF);
      if Ws_Rule = Null_Unbounded_String then
         Append (Output, "  extras: $ => []," & LF & LF);
      else
         declare
            J : constant Natural := Find (To_String (Ws_Rule));
         begin
            Append (Output, "  extras: $ => [/"
              & (if J = 0 then "\s+" else Token_Regex (Rules (J)))
              & "/]," & LF & LF);
         end;
      end if;
      if Conflicts'Length > 0 then
         Append (Output, "  conflicts: $ => [" & LF);
         declare
            Start : Natural := Conflicts'First;
         begin
            for K in Conflicts'Range loop
               if Conflicts (K) = ';' or else K = Conflicts'Last then
                  declare
                     Stop : constant Natural :=
                       (if Conflicts (K) = ';' then K - 1 else K);
                     G : constant String := Conflicts (Start .. Stop);
                     Names : U;
                     B : Natural := G'First;
                  begin
                     for J in G'Range loop
                        if G (J) = ',' or else J = G'Last then
                           declare
                              E : constant Natural := (if G (J) = ',' then J - 1 else J);
                           begin
                              if E >= B then
                                 if Length (Names) > 0 then
                                    Append (Names, ", ");
                                 end if;
                                 Append (Names, "$." & Js_Name (G (B .. E)));
                              end if;
                              B := J + 1;
                           end;
                        end if;
                     end loop;
                     if Length (Names) > 0 then
                        Append (Output, "    [" & To_String (Names) & "]," & LF);
                     end if;
                     Start := K + 1;
                  end;
               end if;
            end loop;
         end;
         Append (Output, "  ]," & LF & LF);
      end if;
      Scanner_Text := Null_Unbounded_String;
      if not Sc_Tags.Is_Empty or else not Sc_Looks.Is_Empty then
         Append (Output, "  externals: $ => [" & LF);
         for T of Sc_Tags loop
            Append (Output, "    $._as_" & Js_Name (To_String (T)) & ", $._same_"
              & Js_Name (To_String (T)) & "," & LF);
         end loop;
         for K in 0 .. Natural (Sc_Looks.Length) - 1 loop
            Append (Output, "    $._look_" & Num (K) & "," & LF);
         end loop;
         Append (Output, "    $._error_sentinel," & LF & "  ]," & LF & LF);
         Scanner_Text := To_Unbounded_String
           (Scanner_C (Rules, Sc_Tags, Sc_Tokens, Sc_Looks,
                       To_String (Ws_Rule), Language));
      end if;
      Append (Output, "  rules: {" & LF & To_String (Body_Text)
        & "  }" & LF & "});" & LF);
      return To_String (Output);
   end Emit;

end HBNF_Tree_Sitter;
