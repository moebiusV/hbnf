pragma Ada_2022;

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  The code-generator templates, loaded from disk at startup: every file
--  <dir>/*.tmpl is keyed by its base name (the file name without ".tmpl").
--  Nothing is baked in; asking for a template that was not loaded is an
--  error.  Two hole styles coexist: the lexer/conf templates still use
--  @PLACEHOLDER@ (Substitute), the rest use ${name} (Render).
package Templates is

   LF : constant Character := ASCII.LF;

   Template_Error : exception;
   --  A missing template, a ${name} hole with no value, a bare `$`, or a
   --  binding set twice.

   procedure Load (Dir : String);
   --  Read every Dir/*.tmpl into the store, keyed by base name.  A missing
   --  directory or unreadable file raises.

   function Get (Name : String) return String;
   --  The loaded text of the template named Name (base name, no ".tmpl").

   --  Replace every occurrence of From in Text with To.
   function Substitute (Text, From, To : String) return String;

   type Bindings is private;
   --  ${name} bindings for Render.  Set adds one; Render fills the holes and
   --  marks each used; Unused names the first binding no hole used.

   procedure Set (B : in out Bindings; Name, Value : String);

   function Render (Text : String; B : in out Bindings) return String;

   function Unused (B : Bindings) return String;

private

   type Slot is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
      Used  : Boolean := False;
   end record;

   package Slot_Vectors is new Ada.Containers.Vectors (Positive, Slot);

   type Bindings is record
      Slots : Slot_Vectors.Vector;
   end record;

end Templates;
