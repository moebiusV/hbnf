pragma Ada_2022;

with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

--  The code-generator templates, loaded from disk at startup: every file
--  <dir>/*.tmpl is keyed by its base name (the file name without ".tmpl").
--  Nothing is baked in; asking for a template that was not loaded is an
--  error.  Two hole styles coexist: the lexer/conf templates still use
--  @PLACEHOLDER@ (Substitute), the rest use ${name} (Render, with the
--  bindings given as a table).
package Templates is

   LF : constant Character := ASCII.LF;

   Template_Error : exception;
   --  A missing template, a ${name} hole with no table row, a bare `$`, or
   --  a binding set twice.

   procedure Load (Dir : String);
   --  Read every Dir/*.tmpl into the store, keyed by base name.  A missing
   --  directory or unreadable file raises.

   function Get (Name : String) return String;
   --  The loaded text of the template named Name (base name, no ".tmpl").

   --  Replace every occurrence of From in Text with To.
   function Substitute (Text, From, To : String) return String;

   type Binding is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Binding_Array is array (Positive range <>) of Binding;

   function Bind (Name, Value : String) return Binding;
   --  One table row.

   function Render (Text : String; Pairs : Binding_Array) return String;
   --  Fill each ${name} hole from the first Pair whose Name matches; a hole
   --  no pair names is an error.

   --  ===================================================================
   --  Recursive context model.
   --
   --  A value is a scalar, a list, or a map, recursively.  This is the
   --  "context tree" the Mustache-style renderer resolves names against,
   --  and it is what lets {{#each}} and {{> partial}} move the per-element
   --  loops and nested blocks out of the emitters and into the templates:
   --  a Scalar is what {{var}} prints, a List is what {{#each}} iterates
   --  (each element becomes the scope inside the section), and a Map is a
   --  scope of named values whose fields may themselves be Maps or Lists.
   --  ===================================================================

   type Template_Value;
   type Value_Access is access Template_Value;

   package Value_Lists is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Value_Access);

   package Value_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Value_Access,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Value_Kind is (Scalar, List, Map);

   type Template_Value (Kind : Value_Kind) is record
      case Kind is
         when Scalar =>
            Text : Ada.Strings.Unbounded.Unbounded_String;
         when List =>
            Items : Value_Lists.Vector;
         when Map =>
            Fields : Value_Maps.Map;
      end case;
   end record;

   --  Builders.  Each returns a fresh heap value; a process builds a
   --  context, renders it, and drops it, so no deallocation is needed.
   function New_Scalar (Text : String) return Value_Access;
   function New_List return Value_Access;
   function New_Map return Value_Access;

   procedure Append (V : Value_Access; Item : Value_Access);
   --  Add Item to the end of a list value; V must have Kind = List.

   procedure Insert (V : Value_Access; Key : String; Item : Value_Access);
   --  Bind Key to Item in a map value; V must have Kind = Map.  Binding a
   --  key already present is an error.

   --  A rendering context: a stack of scopes, top-of-stack last.  A name
   --  lookup walks from the top down, so a scope pushed by {{#each}} or a
   --  partial both shadows and inherits its enclosing scopes.
   type Template_Context is record
      Scopes : Value_Lists.Vector;
   end record;

   function Context (Root : Value_Access) return Template_Context;
   --  A context whose single scope is Root.

   procedure Push (Ctx : in out Template_Context; Scope : Value_Access);
   --  Push a scope onto the top of the stack.

   procedure Pop (Ctx : in out Template_Context);
   --  Drop the top scope.

end Templates;
