pragma Assertion_Policy (Check);

package Basic_Contracts is
 pragma SPARK_Mode(On);

 function Increment (Item : Integer) return Integer
 with Pre => (Item < Integer'Last),
 Post => (Increment'Result = Item + 1),
 Inline
 ;

 function Average (Numerator : Integer;
 Denominator : Integer) return Float
 with Pre => (Numerator >= 0 and Denominator > 0),
 Post => (Average'Result >= 0.0),
 Inline
 ;

end Basic_Contracts;

