package body Initializes_Illegal
  with SPARK_Mode
is
   package body Incorrect_Placement
     with Refined_State => (S => null),
          Initializes => S
   is
      procedure Does_Nothing is begin null; end Does_Nothing;
   end Incorrect_Placement;
end Initializes_Illegal;
