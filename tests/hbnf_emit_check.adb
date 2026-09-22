pragma Ada_2022;

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with HBNF_Grammar;
use type HBNF_Grammar.Element_Kind;
with HBNF_Ada;
with HBNF_C;
with HBNF_Match;
with HBNF_Rust;
with HBNF_Zig;

--  Check the parser and the four emitters against two schema files passed on
--  the command line.  Usage: hbnf_emit_check <server.hbnf> <hbnf_schema.hbnf>
--  The first is the small server example, which drives the C/Ada/Rust/Zig
--  emitters; the second is the hbnf config grammar, checked at the parse
--  level (its entry/block rules are mutually recursive, which the
--  declaration-only emitters reject as a cyclic reference).
procedure Hbnf_Emit_Check is

   use Ada.Strings.Unbounded;

   Failures : Natural := 0;
   Checks   : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      Checks := Checks + 1;
      if Cond then
         Ada.Text_IO.Put_Line ("ok: " & Name);
      else
         Failures := Failures + 1;
         Ada.Text_IO.Put_Line ("FAIL: " & Name);
      end if;
   end Check;

   function Has (Hay, Needle : String) return Boolean is
   begin
      if Needle'Length = 0 then
         return True;
      end if;
      for I in Hay'First .. Hay'Last - Needle'Length + 1 loop
         if Hay (I .. I + Needle'Length - 1) = Needle then
            return True;
         end if;
      end loop;
      return False;
   end Has;

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

   function Find_Rule
     (Rules : HBNF_Grammar.Rule_Vectors.Vector; Name : String) return Natural is
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if To_String (Rules (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Rule;

   procedure Check_Server (Path : String) is
      Rules       : constant HBNF_Grammar.Rule_Vectors.Vector :=
        HBNF_Grammar.Parse (Read_File (Path));
      C_Text      : constant String := HBNF_C.Emit (Rules);
      Ada_Text    : constant String := HBNF_Ada.Emit (Rules, "Server_Schema");
      Rust_Text   : constant String := HBNF_Rust.Emit (Rules);
      Zig_Text    : constant String := HBNF_Zig.Emit (Rules);
      Parser_Text : constant String := HBNF_C.Emit_Parser (Rules);
      Ada_Parser  : constant String := HBNF_Ada.Emit_Parser (Rules, "Server_Schema");
      Rust_Parser : constant String := HBNF_Rust.Emit_Parser (Rules);
      Zig_Parser  : constant String := HBNF_Zig.Emit_Parser (Rules);
   begin
      Check ("13 rules", Natural (Rules.Length) = 13);
      Check ("first rule server", To_String (Rules (1).Name) = "server");

      Check ("C enum", Has (C_Text, "DIRECTION_IN"));
      Check ("C struct", Has (C_Text, "typedef struct"));
      Check ("C scalar", Has (C_Text, "typedef const char * name_t;"));
      Check ("C comment", Has (C_Text, "/* host name"));

      Check ("C parser fn", Has (Parser_Text, "parse_server"));
      Check ("C parser link", Has (Parser_Text, "calloc"));
      Check ("C parser expect", Has (Parser_Text, "expect_lit"));
      Check ("C parser err", Has (Parser_Text, "err_line"));
      Check ("C parser caret", Has (Parser_Text, "memset(pad"));

      Check ("Ada enum", Has (Ada_Text, "Direction_In"));
      Check ("Ada record", Has (Ada_Text, "type Server_Type is record"));
      Check ("Ada subtype",
             Has (Ada_Text, "subtype Port_Type is Unsigned_16"));
      Check ("Ada comment", Has (Ada_Text, "-- host name"));

      Check ("Ada parser fn", Has (Ada_Parser, "Parse_Server"));
      Check ("Ada parser except", Has (Ada_Parser, "Parse_Error"));
      Check ("Ada parser expect", Has (Ada_Parser, "Expect_Lit"));
      Check ("Ada parser caret", Has (Ada_Parser, "& ""^"""));

      Check ("Rust enum", Has (Rust_Text, "pub enum Direction"));
      Check ("Rust struct", Has (Rust_Text, "pub struct Server"));
      Check ("Rust scalar", Has (Rust_Text, "pub type Port = u16;"));
      Check ("Rust comment", Has (Rust_Text, "// host name"));

      Check ("Rust parser fn", Has (Rust_Parser, "parse_server"));
      Check ("Rust parser err", Has (Rust_Parser, "ParseError"));
      Check ("Rust parser expect", Has (Rust_Parser, "expect_lit"));
      Check ("Rust parser caret", Has (Rust_Parser, "{}^"));

      Check ("Zig enum", Has (Zig_Text, "const Direction = enum"));
      Check ("Zig struct", Has (Zig_Text, "const Server = struct"));
      Check ("Zig scalar", Has (Zig_Text, "const Port = u16;"));
      Check ("Zig comment", Has (Zig_Text, "// host name"));

      Check ("Zig parser fn", Has (Zig_Parser, "parse_server"));
      Check ("Zig parser err", Has (Zig_Parser, "ParseError"));
      Check ("Zig parser expect", Has (Zig_Parser, "expect_lit"));
      Check ("Zig parser caret", Has (Zig_Parser, "{s}^"));
   end Check_Server;

   procedure Check_Hbnf (Path : String) is
      use HBNF_Match;
      Rules : constant HBNF_Grammar.Rule_Vectors.Vector :=
        HBNF_Grammar.Parse (Read_File (Path));
      I     : Natural;
   begin
      Check ("hbnf 9 rules", Natural (Rules.Length) = 9);

      --  entry = block / statement : block first, so a block's "{" wins.
      I := Find_Rule (Rules, "entry");
      Check ("entry is block/statement",
             I /= 0 and then Natural (Rules (I).Pattern.Length) = 3
               and then Rules (I).Pattern (2).Kind = HBNF_Grammar.Alt
               and then To_String (Rules (I).Pattern (1).Name) = "block"
               and then To_String (Rules (I).Pattern (3).Name) = "statement");

      --  statement = name *arg (the terminator is handled by `sep`).
      I := Find_Rule (Rules, "statement");
      Check ("statement is name *arg",
             I /= 0 and then Natural (Rules (I).Pattern.Length) = 2
               and then To_String (Rules (I).Pattern (1).Name) = "name"
               and then Rules (I).Pattern (2).Min = 0
               and then Rules (I).Pattern (2).Max = -1);

      --  ws = 1*( "\n" / comment ) — newlines and comments are whitespace.
      I := Find_Rule (Rules, "ws");
      Check ("ws is newline/comment",
             I /= 0 and then Natural (Rules (I).Pattern.Length) = 1
               and then Rules (I).Pattern (1).Kind = HBNF_Grammar.Group
               and then Rules (I).Pattern (1).Min = 1
               and then Rules (I).Pattern (1).Max = -1);

      I := Find_Rule (Rules, "name");
      Check ("name is an atom",
             I /= 0 and then Natural (Rules (I).Pattern.Length) = 1
               and then To_String (Rules (I).Pattern (1).Name) = "atom");

      I := Find_Rule (Rules, "qualifier");
      Check ("qualifier alternates str/atom",
             I /= 0 and then Natural (Rules (I).Pattern.Length) = 3
               and then Rules (I).Pattern (2).Kind = HBNF_Grammar.Alt);

      I := Find_Rule (Rules, "arg");
      Check ("arg alternates atom/str/int/dec",
             I /= 0 and then Natural (Rules (I).Pattern.Length) = 7);

      --  semicolon = ";" — the entry terminator, captured so the binder can
      --  set Semicolon_After.
      I := Find_Rule (Rules, "semicolon");
      Check ("semicolon is a literal ';'",
             I /= 0 and then Natural (Rules (I).Pattern.Length) = 1
               and then Rules (I).Pattern (1).Kind = HBNF_Grammar.Literal
               and then To_String (Rules (I).Pattern (1).Lit) = ";");

      --  The matcher recognizes the schema against a token stream.
      declare
         T : Token_Vectors.Vector;
      begin
         T.Append (Token'(Atom, To_Unbounded_String ("listen")));
         T.Append (Token'(Atom, To_Unbounded_String ("on")));
         T.Append (Token'(Int, To_Unbounded_String ("443")));
         T.Append (Token'(Newline, Null_Unbounded_String));
         T.Append (Token'(Eof, Null_Unbounded_String));
         Check ("matcher accepts a directive",
                HBNF_Match.Match (Rules, T, "config"));

         T.Clear;
         T.Append (Token'(Punct, To_Unbounded_String ("}")));
         T.Append (Token'(Eof, Null_Unbounded_String));
         Check ("matcher rejects a stray brace",
                not HBNF_Match.Match (Rules, T, "config"));
      end;
   end Check_Hbnf;

begin
   Check_Server (Ada.Command_Line.Argument (1));
   Check_Hbnf (Ada.Command_Line.Argument (2));

   Ada.Text_IO.Put_Line
     ("checks: " & Natural'Image (Checks) &
      ", failures: " & Natural'Image (Failures));
   if Failures = 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Hbnf_Emit_Check;
