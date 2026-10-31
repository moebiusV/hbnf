pragma Ada_2022;

--  HBNF_Template: the Mustache the code generators are written in, rendered here.
--
--  A template is read by the parser hbnf makes of grammars/template.hbnf (HBNF_Template_Syntax, generated and
--  kept in the source tree: `sh scripts/gen-template-syntax.sh` writes it again), and rendered against a
--  context, a stack of scopes each a tree of scalar, list and map values.
--
--  What it does of Mustache: interpolation ({{name}} escaped, {{&name}} and {{{name}}} as it is), sections
--  and inverted sections, comments, dotted names and the implicit iterator ({{.}}), and the rule that a line
--  holding a section tag or a comment and nothing else is dropped whole.  What it does not: partials and a
--  change of delimiters, which are read and refused (no template here uses either).

with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

package HBNF_Template is

   Template_Error : exception;
   --  A template that cannot be read (an unterminated tag, a section whose closing tag names another, a
   --  partial, a change of delimiters) or that was never loaded.  A name the view lacks is not an error: it
   --  renders as nothing, as in Mustache.

   --  =====================================================================
   --  Values.
   --  =====================================================================

   type Value;
   type Value_Access is access Value;

   package Value_Lists is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Value_Access);

   package Value_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Value_Access,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Value_Kind is (Scalar, List, Map);

   type Value (Kind : Value_Kind) is record
      case Kind is
         when Scalar =>
            Text : Ada.Strings.Unbounded.Unbounded_String;
         when List =>
            Items : Value_Lists.Vector;
         when Map =>
            Fields : Value_Maps.Map;
      end case;
   end record;

   function New_Scalar (Text : String) return Value_Access;
   function New_List return Value_Access;
   function New_Map return Value_Access;

   procedure Append (V : Value_Access; Item : Value_Access);
   --  Add Item to the end of a list value.

   procedure Insert (V : Value_Access; Key : String; Item : Value_Access);
   --  Bind Key to Item in a map value; a key already there is replaced.

   --  =====================================================================
   --  The context (the view).
   --  =====================================================================

   type Context is record
      Scopes : Value_Lists.Vector;
   end record;
   --  A stack of scopes, the top last.  A name is looked up from the top down, so the scope a section pushes
   --  shadows the ones around it and inherits them.

   function View return Context;
   --  A context with one empty map scope.

   procedure Put (Ctx : in out Context; Key : String; Value : String);
   procedure Put (Ctx : in out Context; Key : String; Value : Value_Access);
   --  Add Key to the top scope: a string becomes a scalar; a Value_Access is a list or a map.

   --  =====================================================================
   --  Templates.
   --  =====================================================================

   procedure Load (Dir : String);
   --  Read every Dir/*.tmpl, keyed by its base name.

   procedure Define (Name : String; Source : String);
   --  Register a template by name, from a string.

   function Get (Name : String) return String;
   --  The text of the template loaded under Name, as it was read.

   function Render (Source : String; View : Context) return String;
   function Render_File (Name : String; View : Context) return String;
   --  A template given as a string, or one loaded by name.

end HBNF_Template;
