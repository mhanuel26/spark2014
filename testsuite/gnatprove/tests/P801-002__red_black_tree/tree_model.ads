with Conts.Functional.Sequences;
use Conts;
package Tree_Model with SPARK_Mode is

   Max : constant := 100;

   subtype Index_Type is Count_Type range 1 .. Max;
   subtype Extended_Index_Type is Index_Type'Base range 0 .. Max;
   type Position_Type is (Left, Right, Top);
   subtype Direction is Position_Type range Left .. Right;

   package D_Seq is new Conts.Functional.Sequences
     (Positive_Count_Type, Direction);
   use D_Seq;

   type Path_Type is record
      A : Sequence;
      K : Boolean := False;
   end record
   with Predicate => Length (A) <= Max;

   function Is_Concat (Q, V, P : Sequence) return Boolean
   is
     (Length (P) - Length (V) = Length (Q)
      and then (for all I in 1 .. Length (Q) => Get (P, I) = Get (Q, I))
      and then
        (for all I in 1 .. Length (V) =>
              Get (P, I + Length (Q)) = Get (V, I))
      and then
        (for all I in Length (Q) + 1 .. Length (P) =>
              Get (V, I - Length (Q)) = Get (P, I)));

   function "<" (S1, S2 : Sequence) return Boolean
   is
     (Length (S1) < Length (S2) and then
          (for all I in 1 .. Length (S1) => Get (S1, I) = Get (S2, I)));

   function "<=" (S1, S2 : Sequence) return Boolean
   is
     (Length (S1) <= Length (S2) and then
          (for all I in 1 .. Length (S1) => Get (S1, I) = Get (S2, I)));

   type Model_Type is array (Index_Type) of Path_Type;

   function "=" (M1, M2 : Model_Type) return Boolean is
      (for all I in Index_Type => M1 (I).A = M2 (I).A and M1 (I).K = M2 (I).K);

end Tree_Model;