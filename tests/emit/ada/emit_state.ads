--  the state the %emit blocks of tests/emit/*-ada.hbnf change, outside the generated parser so that a driver can read it
package Emit_State is
   Stack : array (1 .. 64) of Integer := (others => 0);
   Depth : Natural := 0;
   procedure Push (V : Integer);
   --  the calls of tests/emit/safe-ada.hbnf, noted in the order they are made
   Trace : String (1 .. 200);
   Trace_Len : Natural := 0;
   function Open return Natural;
   procedure Close (V : Natural);
   procedure Put (Key : String);
   procedure Yes;
   procedure No;
   procedure Done;
   procedure One;
   procedure Two;
   procedure Array_Table;
   procedure Table;
end Emit_State;
