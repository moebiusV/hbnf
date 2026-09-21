pragma Ada_2022;

package body ASTBNF_Match is

   use ASTBNF;

   type Matcher is record
      Rules  : ASTBNF.Rule_Vectors.Vector;
      Tokens : Token_Vectors.Vector;
   end record;

   type Match_Result is record
      Pos   : Natural := 0;
      Nodes : Node_Vectors.Vector;
   end record;

   function Last (M : Matcher) return Natural is
     (Natural (M.Tokens.Length));

   function Find_Rule (M : Matcher; Name : String) return Natural is
   begin
      for I in 1 .. Natural (M.Rules.Length) loop
         if To_String (M.Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Rule;

   --  Is Name a built-in core type (not a rule reference)?
   function Is_Core (Name : String) return Boolean is
   begin
      if Name = "atom" or else Name = "word" or else Name = "str"
        or else Name = "int" or else Name = "dec" or else Name = "float"
        or else Name = "bool" or else Name = "flag" or else Name = "comment"
      then
         return True;
      end if;
      if Name'Length >= 2 then
         declare
            P : constant Character := Name (Name'First);
            R : constant String := Name (Name'First + 1 .. Name'Last);
         begin
            return (P = 'u' or else P = 'i')
              and then (for all C of R => C in '0' .. '9');
         end;
      end if;
      return False;
   end Is_Core;

   procedure Append_All (Dst : in out Node_Vectors.Vector;
                         Src : Node_Vectors.Vector) is
   begin
      for N of Src loop
         Dst.Append (N);
      end loop;
   end Append_All;

   --  Match a literal terminal against the token at Pos.
   function Match_Literal (M : Matcher; Lit : String; Pos : Natural)
     return Natural
   is
      T : Token;
   begin
      if Pos > Last (M) then
         return 0;
      end if;
      T := M.Tokens (Pos);
      if Lit'Length = 1 and then Lit (Lit'First) = ASCII.LF then
         return (if T.Kind = Newline then Pos + 1 else 0);
      elsif Lit'Length = 1 and then
        (Lit (Lit'First) not in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_')
      then
         return (if T.Kind = Punct and then To_String (T.Text) = Lit
                 then Pos + 1 else 0);
      else
         return (if T.Kind = Atom and then To_String (T.Text) = Lit
                 then Pos + 1 else 0);
      end if;
   end Match_Literal;

   --  Match a built-in core type against the token at Pos.
   function Match_Core (M : Matcher; Name : String; Pos : Natural)
     return Natural
   is
      T : Token;
   begin
      if Pos > Last (M) then
         return 0;
      end if;
      T := M.Tokens (Pos);
      if Name = "str" then
         return (if T.Kind = Str then Pos + 1 else 0);
      elsif Name = "atom" or else Name = "word" then
         return (if T.Kind = Atom then Pos + 1 else 0);
      elsif Name = "int" then
         return (if T.Kind = Int then Pos + 1 else 0);
      elsif Name = "dec" or else Name = "float" then
         return (if T.Kind = Dec then Pos + 1 else 0);
      elsif Name = "bool" or else Name = "flag" then
         return (if T.Kind = Atom then Pos + 1 else 0);
      elsif Name = "comment" then
         return (if T.Kind = Comment or else T.Kind = Eol_Comment
                 then Pos + 1 else 0);
      else
         return (if T.Kind = Int then Pos + 1 else 0);  --  u8..u64 / i8..i64
      end if;
   end Match_Core;

   --  Mutually recursive match functions (PEG-style: ordered choice, greedy
   --  repetition), each building the matched subtree.
   function Match_Alts (M : Matcher; Els : Element_Vectors.Vector;
                        Pos : Natural) return Match_Result;
   function Match_Concat (M : Matcher; Els : Element_Vectors.Vector;
                          From, To : Natural; Pos : Natural)
                          return Match_Result;
   function Match_Element (M : Matcher; E : Element_Access; Pos : Natural)
                           return Match_Result;
   function Match_Atom (M : Matcher; E : Element_Access; Pos : Natural)
                        return Match_Result;
   function Match_Rule (M : Matcher; Name : String; Pos : Natural)
                        return Match_Result;

   function Match_Rule (M : Matcher; Name : String; Pos : Natural)
     return Match_Result
   is
      RI : constant Natural := Find_Rule (M, Name);
      R  : Match_Result;
   begin
      if RI = 0 then
         raise ASTBNF.Parse_Error with "undefined rule: " & Name;
      end if;
      R := Match_Alts (M, M.Rules (RI).Pattern, Pos);
      if R.Pos /= 0 then
         declare
            N : constant Node_Access := new Node'
              (Kind      => Rule_Node,
               Rule_Name => To_Unbounded_String (Name),
               Kids      => R.Nodes);
         begin
            R.Nodes.Clear;
            R.Nodes.Append (N);
         end;
      end if;
      return R;
   end Match_Rule;

   function Match_Atom (M : Matcher; E : Element_Access; Pos : Natural)
     return Match_Result
   is
      R : Match_Result;
   begin
      case E.Kind is
         when Literal =>
            R.Pos := Match_Literal (M, To_String (E.Lit), Pos);
         when Name =>
            if Is_Core (To_String (E.Name)) then
               R.Pos := Match_Core (M, To_String (E.Name), Pos);
               if R.Pos /= 0 then
                  R.Nodes.Append
                    (new Node'(Kind => Token_Node, Tok => M.Tokens (Pos)));
               end if;
            else
               return Match_Rule (M, To_String (E.Name), Pos);
            end if;
         when Group =>
            return Match_Alts (M, E.Items, Pos);
         when Alt =>
            return R;
      end case;
      return R;
   end Match_Atom;

   function Match_Element (M : Matcher; E : Element_Access; Pos : Natural)
     return Match_Result
   is
      Count : Natural := 0;
      P     : Natural := Pos;
      R     : Match_Result;
   begin
      loop
         exit when E.Max >= 0 and then Count >= E.Max;
         declare
            Next : constant Match_Result := Match_Atom (M, E, P);
         begin
            exit when Next.Pos = 0;
            P := Next.Pos;
            Append_All (R.Nodes, Next.Nodes);
            Count := Count + 1;
         end;
      end loop;
      if Count >= E.Min then
         R.Pos := P;
         return R;
      end if;
      return (Pos => 0, Nodes => Node_Vectors.Empty_Vector);
   end Match_Element;

   function Match_Concat (M : Matcher; Els : Element_Vectors.Vector;
                          From, To : Natural; Pos : Natural)
     return Match_Result
   is
      R : Match_Result;
      P : Natural := Pos;
   begin
      for K in From .. To loop
         declare
            Next : constant Match_Result := Match_Element (M, Els (K), P);
         begin
            if Next.Pos = 0 then
               return (Pos => 0, Nodes => Node_Vectors.Empty_Vector);
            end if;
            P := Next.Pos;
            Append_All (R.Nodes, Next.Nodes);
         end;
      end loop;
      R.Pos := P;
      return R;
   end Match_Concat;

   function Match_Alts (M : Matcher; Els : Element_Vectors.Vector;
                        Pos : Natural) return Match_Result
   is
      Alt_First : Natural := 1;
   begin
      for K in 1 .. Natural (Els.Length) + 1 loop
         if K > Natural (Els.Length) or else Els (K).Kind = Alt then
            declare
               R : constant Match_Result :=
                 Match_Concat (M, Els, Alt_First, K - 1, Pos);
            begin
               if R.Pos /= 0 then
                  return R;
               end if;
            end;
            Alt_First := K + 1;
         end if;
      end loop;
      return (Pos => 0, Nodes => Node_Vectors.Empty_Vector);
   end Match_Alts;

   function Bind (Rules  : ASTBNF.Rule_Vectors.Vector;
                  Tokens : Token_Vectors.Vector;
                  Root   : String) return Node_Access
   is
      M : constant Matcher := (Rules => Rules, Tokens => Tokens);
      R : Match_Result;
   begin
      if Find_Rule (M, Root) = 0 then
         raise ASTBNF.Parse_Error with "no root rule: " & Root;
      end if;
      R := Match_Rule (M, Root, 1);
      if R.Pos /= 0 and then R.Pos <= Last (M)
        and then M.Tokens (R.Pos).Kind = Eof
      then
         return R.Nodes (1);
      end if;
      return null;
   end Bind;

   function Match (Rules  : ASTBNF.Rule_Vectors.Vector;
                   Tokens : Token_Vectors.Vector;
                   Root   : String) return Boolean is
     (Bind (Rules, Tokens, Root) /= null);

end ASTBNF_Match;
