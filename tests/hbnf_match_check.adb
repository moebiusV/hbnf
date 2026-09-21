pragma Ada_2022;

with Ada.Command_Line;
with Ada.Text_IO;
with Ada.Strings.Unbounded;
with HBNF;
with ASTBNF;
with ASTBNF_Match;

--  Match the hbnf schema against the token stream of one config file.
--  Usage: hbnf_match_check <schema.astbnf> <config.conf> <accept|reject>
--  accept: the file must lex and match; reject: it must not.
procedure HBNF_Match_Check is

   use Ada.Strings.Unbounded;
   use type HBNF.Token_Kind;

   function Read_File (Path : String) return String is
      F   : Ada.Text_IO.File_Type;
      Buf : Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Append (Buf, Ada.Text_IO.Get_Line (F));
         Append (Buf, ASCII.LF);
      end loop;
      Ada.Text_IO.Close (F);
      return To_String (Buf);
   end Read_File;

   --  Map an hbnf token onto the matcher's generic token.
   function Map (T : HBNF.Token) return ASTBNF_Match.Token is
   begin
      case T.Kind is
         when HBNF.Word => return (ASTBNF_Match.Atom, T.Text);
         when HBNF.Str  => return (ASTBNF_Match.Str, T.Text);
         when HBNF.Int  => return (ASTBNF_Match.Int, T.Text);
         when HBNF.Dec  => return (ASTBNF_Match.Dec, T.Text);
         when HBNF.LBrace =>
            return (ASTBNF_Match.Punct, To_Unbounded_String ("{"));
         when HBNF.RBrace =>
            return (ASTBNF_Match.Punct, To_Unbounded_String ("}"));
         when HBNF.Semicolon =>
            return (ASTBNF_Match.Punct, To_Unbounded_String (";"));
         when HBNF.Newline =>
            return (ASTBNF_Match.Newline, Null_Unbounded_String);
         when HBNF.Eof =>
            return (ASTBNF_Match.Eof, Null_Unbounded_String);
         when HBNF.Comment | HBNF.Eol_Comment =>
            return (ASTBNF_Match.Comment, T.Text);
      end case;
   end Map;

begin
   declare
      Schema  : constant ASTBNF.Rule_Vectors.Vector :=
        ASTBNF.Parse (Read_File (Ada.Command_Line.Argument (1)));
      Path    : constant String := Ada.Command_Line.Argument (2);
      Mode    : constant String := Ada.Command_Line.Argument (3);
      L       : constant HBNF.Lex_Result := HBNF.Lex (Read_File (Path));
      Toks    : ASTBNF_Match.Token_Vectors.Vector;
      Matched : Boolean := False;
      Pass    : Boolean;
   begin
      if L.Success then
         for T of L.Tokens loop
            Toks.Append (Map (T));
         end loop;
         Matched := ASTBNF_Match.Match (Schema, Toks, "config");
      end if;

      Pass := (Mode = "accept" and then L.Success and then Matched)
        or else (Mode = "reject" and then (not L.Success or else not Matched));

      if Pass then
         Ada.Text_IO.Put_Line ("ok: " & Path);
      else
         Ada.Text_IO.Put_Line
           ("FAIL: " & Path & " (mode " & Mode & ")");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end;
end HBNF_Match_Check;
