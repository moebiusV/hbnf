pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with ASTBNF;

--  ASTBNF_Match: the matcher and binder.  Given a parsed schema and a token
--  stream, recognize whether the tokens spell out the schema's root rule and
--  bind them to a parse tree.
--
--  The tokens are generic: a kind plus optional text.  hbnf's Lex produces
--  the stream; a small adapter maps its token kinds onto these.  A comment
--  is Comment (own line) or Eol_Comment (end of line), which is what lets a
--  later pass place it as leading vs trailing.

package ASTBNF_Match is

   use Ada.Strings.Unbounded;

   type Token_Kind is (Atom, Str, Int, Dec, Comment, Eol_Comment,
                       Punct, Newline, Eof);
   --  Atom = a bare word; Str = a quoted string; Int/Dec = numbers;
   --  Comment/Eol_Comment = own-line / end-of-line comment; Punct = a
   --  punctuation character (Text holds it); Newline = a line break.

   type Token is record
      Kind : Token_Kind := Eof;
      Text : Unbounded_String := Null_Unbounded_String;
   end record;

   package Token_Vectors is new Ada.Containers.Vectors (Positive, Token);

   --  The parse tree: a rule application (its name and matched children) or
   --  a matched token (a core type).  Literals are match-and-skip and never
   --  become a node.
   type Node_Kind is (Rule_Node, Token_Node);

   type Node;
   type Node_Access is access Node;

   package Node_Vectors is new Ada.Containers.Vectors (Positive, Node_Access);

   type Node (Kind : Node_Kind := Rule_Node) is record
      case Kind is
         when Rule_Node =>
            Rule_Name : Unbounded_String;
            Kids      : Node_Vectors.Vector;
         when Token_Node =>
            Tok       : Token;
      end case;
   end record;

   --  True if Tokens (ending in Eof) match the rule named Root.
   function Match
     (Rules  : ASTBNF.Rule_Vectors.Vector;
      Tokens : Token_Vectors.Vector;
      Root   : String) return Boolean;

   --  Match Root against Tokens and return the parse tree (a Rule_Node for
   --  Root), or null on failure.
   function Bind
     (Rules  : ASTBNF.Rule_Vectors.Vector;
      Tokens : Token_Vectors.Vector;
      Root   : String) return Node_Access;

end ASTBNF_Match;
