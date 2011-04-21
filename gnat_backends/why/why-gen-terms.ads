------------------------------------------------------------------------------
--                                                                          --
--                            GNAT2WHY COMPONENTS                           --
--                                                                          --
--                   G N A T 2 W H Y - G E N - T E R M S                    --
--                                                                          --
--                                 S p e c                                  --
--                                                                          --
--                       Copyright (C) 2010-2011, AdaCore                   --
--                                                                          --
-- gnat2why is  free  software;  you can redistribute it and/or modify it   --
-- under terms of the  GNU General Public License as published  by the Free --
-- Software Foundation;  either version  2,  or  (at your option) any later --
-- version. gnat2why is distributed in the hope that it will  be  useful,   --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHAN-  --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License  for more details. You  should  have  received a copy of the GNU --
-- General Public License  distributed with GNAT; see file COPYING. If not, --
-- write to the Free Software Foundation,  51 Franklin Street, Fifth Floor, --
-- Boston,                                                                  --
--                                                                          --
-- gnat2why is maintained by AdaCore (http://www.adacore.com)               --
--                                                                          --
------------------------------------------------------------------------------

with Types;         use Types;
with Why.Gen.Types; use Why.Gen.Types;
with Why.Ids;       use Why.Ids;
with Why.Sinfo;     use Why.Sinfo;

package Why.Gen.Terms is
   --  Functions that deal with generation of terms

   function Insert_Conversion_Term
      (Ada_Node : Node_Id := Empty;
       To       : Why_Type;
       From     : Why_Type;
       Why_Term : W_Term_Id) return W_Term_Id;
   --  We expect Why_Expr to be of the type that corresponds to the type
   --  "From". We insert a conversion so that its type corresponds to "To".

   function New_Andb (Left, Right : W_Term_Id) return W_Term_Id;
   --  Build a boolean conjunction.

   function New_Call_To_Logic
     (Name    : W_Identifier_Id;
      Binders : W_Binder_Array)
     return W_Term_Id;
   --  Create a call to an operation in the logical space with parameters
   --  taken from Binders. Typically, from:
   --
   --     (x1 : type1) (x2 : type2)
   --
   --  ...it produces:
   --
   --     operation_name (x1, x2)

   function New_Old_Ident (Ident : W_Identifier_Id) return W_Term_Id;
   --  Build an identifier with "old" label

   function New_Orb (Left, Right : W_Term_Id) return W_Term_Id;
   --  Build a boolean disjunction.

   function New_Ifb (Condition, Left, Right : W_Term_Id) return W_Term_Id;
   --  Build a if-then-else construct with a boolean test and terms in the
   --  branches.

   function New_Boolean_Cmp (Cmp : W_Relation; Left, Right : W_Term_Id)
      return W_Term_Id;
   --  build a boolean comparison for terms of "int" type.

   function New_Result_Term return W_Term_Id;
   --  return the term containing the ident "result"
end Why.Gen.Terms;
