package body Stack_05
--# own Stack is S, Pointer; -- state refinement
is
   Stack_Size : constant := 100;
   type    Pointer_Range is range 0 .. Stack_Size;
   subtype Index_Range   is Pointer_Range range 1..Stack_Size;
   type    Vector        is array(Index_Range) of Integer;
   S : Vector;

   Pointer : Pointer_Range := 0;
   -- initialization by elaboration of declaration

   procedure Push(X : in Integer)
   --# global in out S, Pointer;
   is
   begin
      Pointer := Pointer + 1;
      S(Pointer) := X;
   end Push;

   procedure Pop(X : out Integer)
   --# global in     S;
   --#        in out Pointer;
   is
   begin
      X := S(Pointer);
      Pointer := Pointer - 1;
   end Pop;
begin  -- initialization by body statements
   S := Vector'(Index_Range => 0);
end Stack_05;
