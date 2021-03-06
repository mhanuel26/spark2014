package body Depends_Legal_2
  with SPARK_Mode,
       Refined_State => (State => Rec1)
is
   type Dis_Rec (D : Boolean := True) is record
      case D is
         when True =>
            A, B : Integer;
         when False =>
            X, Y, Z : Float;
      end case;
   end record;

   Rec1 : Dis_Rec := Dis_Rec'(D => True, A => 1, B => 2);


   procedure P1 (Par1 : out Dis_Rec; Par2 : in Dis_Rec)
   --  TU: 5. The *input set* of a subprogram is the explicit input
   --  set of the subprogram augmented with those formal parameters of
   --  mode **out** and those ``global_items`` with a
   --  ``mode_selector`` of Output having discriminants, array bounds,
   --  or a tag which can be read and whose values are not implied by
   --  the subtype of the parameter. More specifically, it includes
   --  formal parameters of mode **out** and ``global_items`` with a
   --  ``mode_selector`` of Output which are of an unconstrained array
   --  subtype, an unconstrained discriminated subtype, a tagged type
   --  (with one exception), or a type having a subcomponent of an
   --  unconstrained discriminated subtype. The exception mentioned in
   --  the previous sentence is in the case where the formal parameter
   --  is of a specific tagged type and the applicable
   --  Extensions_Visible aspect is False. In that case, the tag of
   --  the parameter cannot be read and so the fact that the parameter
   --  is tagged does not cause it to included in the subprogram's
   --  *input_set*, although it may be included for some other reason
   --  (e.g., if the parameter is of an unconstrained discriminated
   --  subtype).
     with Global  => (Output => Rec1),
          Depends => (Par1 => Par1,
                      Rec1 => Par2)
   is
   begin
      if Par1.D then
         Par1 := Dis_Rec'(D => True, A | B => 0);
      else
         Par1 := Dis_Rec'(D => False, X | Y | Z => 0.0);
      end if;

      Rec1 := Par2;
   end P1;
end Depends_Legal_2;
