pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  HBNF_Grammar: a schema for mapping a preparsed *generic* AST (a tree of named
--  nodes carrying symbol/string values, children and comments) to typed C/Ada.
--
--  The schema notation is RFC 5234 ABNF, with `|` for `/` and the other
--  additions ABNF.md lists.  Types are *not* part of the grammar: they
--  are a reserved set of built-in rule names the code emitter
--  interprets.  `str` is a quoted c-string; `atom` (synonym `word`) is a bare
--  token, a symbol or a number, that the matcher narrows against the typed
--  core types (`int`, `dec`, `float`, `u8`..`u64`, `i8`..`i64`, `bool`,
--  `flag`) with full type checking.  This package is only the ABNF parser: it
--  turns the schema text into a flat list of rules and has no notion of type,
--  struct, enum or flag.  The emitter walks these rules and reads the shapes:
--
--     name      = str                      ; a field (single core type)
--     tls       = flag                     ; a flag (the `flag` core type)
--     direction = "in" | "out"             ; an enum (literal alternation)
--     listen    = "on" iface "port" port   ; a directive (literals + refs)
--     server    = name 1*( listen | root ) ; a struct (ref + children)
package HBNF_Grammar is

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
            No_Case : Boolean := False;  --  %i"...": any case matches
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
      Jet_Code        : Unbounded_String := Null_Unbounded_String;
      --  Non-empty for a jet: `name = %{ <code> %}`.  The code is a
      --  hand-written scanner body emitted verbatim; Pattern stays empty.
      C_Type          : Unbounded_String := Null_Unbounded_String;
      --  Non-empty for a typed rule: `{ <C-type> } name = pattern` declares
      --  the C storage class of the rule's value (e.g. `struct pf_rule_addr`,
      --  `char[IFNAMSIZ]`); the C emitter uses it in place of a type inferred
      --  from the pattern.
      Action_Code     : Unbounded_String := Null_Unbounded_String;
      --  Non-empty for an action jet: `name = pattern { <C-code> }`, or a
      --  separate `action name { <C-code> }` (e.g. in a binding file).  The
      --  code is a fragment that builds the daemon's conf struct, run once
      --  after a successful parse in the bottom-up bind walk (children before
      --  parents), with the rule's node as `n` and the daemon's conf global
      --  in scope.  It never runs during parsing, so a backtracking re-parse
      --  cannot re-run its side effects.
      Left_Bases      : Natural := 0;
      --  Non-zero for a rule written with direct left recursion,
      --  `a = a t1 | a t2 | b1 | b2`, which the reader turns into the
      --  list `1*( b1 | b2 | t1 | t2 )`: the number of branches, at the
      --  front of the list's group, that are bases.  The first entry is
      --  read from the bases and every later one from the tails, so the
      --  list is exactly b (t)*, in a loop rather than by recursion.
   end record;

   package Rule_Vectors is new Ada.Containers.Vectors (Positive, Rule);

   --  The base branches and the tail branches of a list rewritten from
   --  left recursion (R.Left_Bases > 0), each a flat vector with Alt
   --  separators, as a group's items are.
   function Base_Branches (R : Rule) return Element_Vectors.Vector;
   function Tail_Branches (R : Rule) return Element_Vectors.Vector;

   --  True when some rule has a %i literal, so an emitter writes its
   --  case-insensitive match only for a schema that uses one.
   function Has_No_Case (Rules : Rule_Vectors.Vector) return Boolean;

   package Word_Vectors is new
     Ada.Containers.Vectors (Positive, Unbounded_String);

   --  Parse HBNF_Grammar (ABNF) source text into a flat list of rules, in order.
   function Parse (Text : String) return Rule_Vectors.Vector;

   --  Parse a schema file, resolving top-level `include "path"` directives
   --  (each path relative to the including file's directory).  Included files
   --  are loaded first, depth-first; a same-named local rule overrides an
   --  included one, so a daemon schema can pull in a common core and replace
   --  just the rules that differ.  Preambles and epilogues are concatenated,
   --  included files' first (like C's #include); for the other header
   --  directives the including file, parsed last, wins.  `action name
   --  { code }` attaches an action jet to a rule from any of the files, so a
   --  binding file can include a grammar and add the daemon's actions and
   --  headers without touching it.  Header state is reset at the start of
   --  each top-level call, so nothing carries over between schemas.
   function Parse_File (Path : String) return Rule_Vectors.Vector;

   --  Rules, minus those nothing uses: the root (Rules (1)), every rule
   --  reachable from it through references (groups included), and every jet
   --  rule (the lexer runs jets whether or not a rule names them), in their
   --  original order.  An include like commonconf.hbnf brings rules a
   --  grammar never references; emitting them costs code and unused-function
   --  warnings, and their literals would still become keywords.
   function Reachable (Rules : Rule_Vectors.Vector) return Rule_Vectors.Vector;

   --  The schema language declared by the first non-blank line
   --  (`language C|Rust|Zig|Ada`), or "C" when absent.  Jet code blocks are
   --  written in this language.
   function Language return String;

   --  A raw `%{ ... %}` block at the top of the file (emitted before the
   --  declarations), or "" when absent.
   function Preamble return String;

   --  A raw `%{ ... %}` block after the rules (emitted after the parser), or
   --  "" when absent.
   function Epilogue return String;

   --  Extra bareword characters declared by a top-level `wordchars "..."`,
   --  beyond the base set (letters, digits, `.`, `_`, `-`); the lexer folds
   --  them into its word token.  "" when absent.
   function Word_Chars return String;

   --  The raw code overriding one C list operation, from a top-level
   --  `list-head { … }` … `list-relink { … }` directive; "" when absent, in
   --  which case the C emitter writes hbnf's own head/tail singly-linked
   --  list directly.  Op is one of "head", "entry", "init", "append",
   --  "foreach", "first", "next", "relink".
   function List_Override (Op : String) return String;

   --  The prefix declared by a top-level `prefix "pf_"` (or set with
   --  Set_Type_Prefix, for hbnf_cli's --prefix=, which wins), "" when absent.
   --  It is put in front of every generated C type and struct tag, so a rule
   --  named daddr becomes pf_daddr_t and cannot collide with <sys/types.h>.
   function Type_Prefix return String;
   procedure Set_Type_Prefix (Prefix : String);

   --  The daemon's own conf struct, from a top-level `conf struct ntpd_conf`
   --  directive; "" when absent.  When set, the C `--conf` wrapper emits
   --  parse_config(filename, <conf>) — it fills the caller's conf instead of
   --  allocating an AST-shaped one — so the action jets' `conf` global is the
   --  daemon's real tree, not hbnf's parse tree.
   function Conf_Type return String;

   --  `statements`: the root rule is a list whose entries are statements,
   --  and the C parser reads the config one statement at a time, as
   --  parse.y's yyparse does.  A statement ends at a newline outside `{ }`
   --  (backslash-newline, and a next line starting with `{`, continue it).
   --  Each is lexed, parsed, bound and handed on before the next is read,
   --  a syntax error is reported and the parse goes on with the next
   --  statement, and only one statement's tokens are held at a time.
   function Statements return Boolean;

   --  `macros varset`: a statement the named rule matches whole defines a
   --  macro, as parse.y's varset: its first token is the name, the tokens
   --  after `=` joined by spaces the value.  `$name` then expands, outside
   --  quotes and comments, to the value.  "" when absent.
   function Macros_Rule return String;

   --  `includes include`: a statement the named rule matches whole
   --  includes the file its last token names; the file's statements are
   --  read in its place.  "" when absent.
   function Includes_Rule return String;

   --  `keywords { all any anchor ... }`: the words the C lexer reserves, as
   --  parse.y's lookup() table does.  A letter-led literal in the table is a
   --  keyword: interned, refused as a `word`, dispatched on by id.  Any other
   --  literal matches a word by its text and reserves nothing, as parse.y's
   --  STRING compared with strcmp in an action.  A word in the table that no
   --  rule uses is still reserved.  Empty when the directive is absent, and
   --  then every letter-led literal is a keyword.
   function Keyword_Table return Word_Vectors.Vector;

end HBNF_Grammar;
