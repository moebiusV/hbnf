pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  ASTBNF: a schema for mapping a preparsed *generic* AST (a tree of named
--  nodes carrying symbol/string values, children and comments) to typed C/Ada.
--
--  The schema notation is plain RFC 5234 ABNF.  Types are *not* part of the
--  grammar: they are a reserved set of built-in rule names the code emitter
--  interprets.  `str` is a quoted c-string; `atom` (synonym `word`) is a bare
--  token, a symbol or a number, that the matcher narrows against the typed
--  core types (`int`, `dec`, `float`, `u8`..`u64`, `i8`..`i64`, `bool`,
--  `flag`) with full type checking.  This package is only the ABNF parser: it
--  turns the schema text into a flat list of rules and has no notion of type,
--  struct, enum or flag.  The emitter walks these rules and reads the shapes:
--
--     name      = str                      ; a field (single core type)
--     tls       = flag                     ; a flag (the `flag` core type)
--     direction = "in" / "out"             ; an enum (literal alternation)
--     listen    = "on" iface "port" port   ; a directive (literals + refs)
--     server    = name 1*( listen / root ) ; a struct (ref + children)
package ASTBNF is

   use Ada.Strings.Unbounded;

   Parse_Error : exception;
   --  Raised by Parse on malformed schema text; message carries "line: col:".

   type Element_Kind is (Literal, Name, Group, Alt);
   --  Literal = "quoted" keyword to match-and-skip; Name = a bare rule/core
   --  reference; Group = a parenthesized/bracketed group; Alt = a separator
   --  between a group's alternatives (a group's children are a flat list, Alt
   --  marking each split).

   type Element;
   type Element_Access is access Element;

   package Element_Vectors is new
     Ada.Containers.Vectors (Positive, Element_Access);

   type Element (Kind : Element_Kind := Literal) is record
      Min : Natural := 1;   --  minimum occurrences (repetition)
      Max : Integer := 1;   --  -1 = unbounded
      case Kind is
         when Literal =>
            Lit : Unbounded_String;      --  keyword to match-and-skip
         when Name =>
            Name : Unbounded_String;     --  rule/core reference
         when Group =>
            Items : Element_Vectors.Vector;   --  flat; Alt splits alternatives
         when Alt =>
            null;
      end case;
   end record;

   --  A single ABNF rule:  name = pattern.  Comments in the schema are
   --  carried through: a `;` comment block on its own line(s) immediately
   --  before the rule is Leading_Comment; a `;` comment on the same line
   --  after the pattern is Trailing_Comment.  The emitter reproduces both.
   type Rule is record
      Name            : Unbounded_String;
      Pattern         : Element_Vectors.Vector := Element_Vectors.Empty_Vector;
      Leading_Comment : Unbounded_String := Null_Unbounded_String;
      Trailing_Comment : Unbounded_String := Null_Unbounded_String;
   end record;

   package Rule_Vectors is new Ada.Containers.Vectors (Positive, Rule);

   --  Parse ASTBNF (ABNF) source text into a flat list of rules, in order.
   function Parse (Text : String) return Rule_Vectors.Vector;

end ASTBNF;
