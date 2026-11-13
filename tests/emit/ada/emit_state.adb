package body Emit_State is
   procedure Push (V : Integer) is
   begin
      Depth := Depth + 1;
      Stack (Depth) := V;
   end Push;
   procedure Note (S : String) is
   begin
      Trace (Trace_Len + 1 .. Trace_Len + S'Length) := S;
      Trace_Len := Trace_Len + S'Length;
   end Note;
   function Open return Natural is
   begin
      Note ("{");
      return Trace_Len;
   end Open;
   procedure Close (V : Natural) is
   begin
      Note ("}");
   end Close;
   procedure Put (Key : String) is
   begin
      Note ("p:" & Key);
   end Put;
   procedure Yes is
   begin
      Note ("y");
   end Yes;
   procedure No is
   begin
      Note ("n");
   end No;
   procedure Done is
   begin
      Note ("done");
   end Done;
   procedure One is
   begin
      Note ("one");
   end One;
   procedure Two is
   begin
      Note ("two");
   end Two;
   procedure Array_Table is
   begin
      Note ("array_table");
   end Array_Table;
   procedure Table is
   begin
      Note ("table");
   end Table;
end Emit_State;
