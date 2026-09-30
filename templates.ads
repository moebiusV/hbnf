pragma Ada_2022;

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

end Templates;
