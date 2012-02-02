------------------------------------------------------------------------------
--                                                                          --
--                            GNAT2WHY COMPONENTS                           --
--                                                                          --
--                             W H Y - I N T E R                            --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                       Copyright (C) 2010-2012, AdaCore                   --
--                                                                          --
-- gnat2why is  free  software;  you can redistribute  it and/or  modify it --
-- under terms of the  GNU General Public License as published  by the Free --
-- Software  Foundation;  either version 3,  or (at your option)  any later --
-- version.  gnat2why is distributed  in the hope that  it will be  useful, --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of  MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public License  distributed with  gnat2why;  see file COPYING3. --
-- If not,  go to  http://www.gnu.org/licenses  for a complete  copy of the --
-- license.                                                                 --
--                                                                          --
-- gnat2why is maintained by AdaCore (http://www.adacore.com)               --
--                                                                          --
------------------------------------------------------------------------------
with AA_Util;             use AA_Util;
with Ada.Characters.Handling;
with Alfa.Common;         use Alfa.Common;
with Alfa.Filter;         use Alfa.Filter;
with Alfa.Definition;     use Alfa.Definition;
with Einfo;               use Einfo;
with Sem_Util;            use Sem_Util;
with Stand;               use Stand;
with Constant_Tree;
with Why.Conversions;     use Why.Conversions;
with Why.Atree.Tables;    use Why.Atree.Tables;
with Why.Atree.Accessors; use Why.Atree.Accessors;
with Why.Atree.Mutators;  use Why.Atree.Mutators;
with Why.Gen.Names;       use Why.Gen.Names;
with Why.Gen.Expr;        use Why.Gen.Expr;

with Gnat2Why.Decls;      use Gnat2Why.Decls;

package body Why.Inter is

   package Type_Hierarchy is
     new Constant_Tree (EW_Base_Type, EW_Unit);

   function Get_EW_Term_Type (N : Node_Id) return EW_Type;

   ------------------------
   -- Add_Effect_Imports --
   ------------------------

   procedure Add_Effect_Imports (P : in out Why_File;
                                 S : Name_Set.Set)
   is
   begin
      for Var of S loop
         if not (Is_Heap_Variable (Var)) then
            declare
               F : constant Entity_Name := File_Of_Entity (Var);
               S : String := Var.all;
            begin
               S (S'First) := Ada.Characters.Handling.To_Upper (S (S'First));

               Add_With_Clause (P,
                                File_Name_Without_Suffix (F.all) &
                                  Variables_Suffix,
                                S,
                                EW_Import);
            end;
         end if;
      end loop;
   end Add_Effect_Imports;

   ---------------------
   -- Add_With_Clause --
   ---------------------

   procedure Add_With_Clause (P        : in out Why_File;
                              File     : String;
                              T_Name   : String;
                              Use_Kind : EW_Clone_Type := EW_Export) is
      File_Ident : constant W_Identifier_Id :=
        (if File = "" then Why_Empty else New_Identifier (Name => File));
   begin
      Theory_Declaration_Append_To_Includes
        (P.Cur_Theory,
         New_Include_Declaration (File     => File_Ident,
                                  T_Name   => New_Identifier (Name => T_Name),
                                  Use_Kind => Use_Kind,
                                  Kind     => EW_Module));
   end Add_With_Clause;

   procedure Add_With_Clause (P        : in out Why_File;
                              Other    : Why_File;
                              Use_Kind : EW_Clone_Type := EW_Export) is
   begin
      Add_With_Clause (P, Other.Name.all, "Main", Use_Kind);
   end Add_With_Clause;

   -------------------
   -- Base_Why_Type --
   -------------------

   function Base_Why_Type (W : W_Base_Type_Id) return W_Base_Type_Id is
      Kind : constant EW_Type := Get_Base_Type (W);
   begin
      case Kind is
         when EW_Abstract =>
            return Base_Why_Type (Get_Ada_Node (+W));
         when others =>
            return W;
      end case;
   end Base_Why_Type;

   function Base_Why_Type (N : Node_Id) return W_Base_Type_Id is

      --  Get to the unique type, in order to reach the actual base type,
      --  because the private view has another base type (possibly itself).

      E   : constant EW_Type := Get_EW_Term_Type (N);
      Typ : constant Entity_Id := Unique_Entity (Etype (N));
   begin
      case E is
         when EW_Abstract =>
            if Is_Array_Type (Typ) then
               return Why_Types (EW_Array);
            else
               return EW_Abstract (Typ);
            end if;
         when others =>
            return Why_Types (E);
      end case;
   end Base_Why_Type;

   function Base_Why_Type (Left, Right : W_Base_Type_Id) return W_Base_Type_Id
   is
   begin
      return LCA (Base_Why_Type (Left), Base_Why_Type (Right));
   end Base_Why_Type;

   function Base_Why_Type (Left, Right : Node_Id) return W_Base_Type_Id is
   begin
      return Base_Why_Type (Base_Why_Type (Left), Base_Why_Type (Right));
   end Base_Why_Type;

   ------------------
   -- Close_Theory --
   ------------------

   procedure Close_Theory (P : in out Why_File;
                           No_Imports : Boolean := False)
   is

      function File_Base_Name_Of_Entity (E : Entity_Id) return String;
      --  return the base name of the unit in which the entity is
      --  defined

      function File_Suffix (E : Entity_Id) return String;
      --  compute the file suffix of the unit in which the entity is defined

      function Theory_Name (E : Entity_Id) return String;
      --  compute the name of the theory in which the Why equivalent of the
      --  entity is defined

      ------------------------------
      -- File_Base_Name_Of_Entity --
      ------------------------------

      function File_Base_Name_Of_Entity (E : Entity_Id) return String is
         U : Node_Id;
      begin
         if Is_In_Standard_Package (E) then
            return "_standard";
         end if;
         U := Enclosing_Lib_Unit_Node (E);
         if not Present (U) and then Is_Itype (E) then
            U := Enclosing_Lib_Unit_Node (Associated_Node_For_Itype (E));
         end if;
         return File_Name_Without_Suffix (Sloc (U));
      end File_Base_Name_Of_Entity;

      -----------------
      -- File_Suffix --
      -----------------

      function File_Suffix (E : Entity_Id) return String is
      begin
         if Is_In_Standard_Package (E) then
            return "";
         end if;
         case Ekind (E) is
            when Subprogram_Kind | E_Subprogram_Body | Named_Kind =>
               if Is_In_Current_Unit (E) and then
                 Body_Entities.Contains (E) then
                  return Context_In_Body_Suffix;
               else
                  return Context_In_Spec_Suffix;
               end if;

            when Object_Kind =>
               if not Is_Mutable (E) then
                  if Is_In_Current_Unit (E) and then
                    Body_Entities.Contains (E) then
                     return Context_In_Body_Suffix;
                  else
                     return Context_In_Spec_Suffix;
                  end if;
               else
                  return Variables_Suffix;
               end if;

            when Type_Kind =>
               return Types_In_Body_Suffix;

            when others =>
               return Variables_Suffix;

         end case;
      end File_Suffix;

      -----------------
      -- Theory_Name --
      -----------------

      function Theory_Name (E : Entity_Id) return String is
      begin
         if Is_In_Standard_Package (E) then
            return "Main";
         end if;
         case Ekind (E) is
            when Subprogram_Kind
               | E_Subprogram_Body
               | Named_Kind
               | Object_Kind =>
               return Full_Name (E);

            when others =>
               return "Main";

         end case;
      end Theory_Name;

      use Node_Sets;

      S        : constant Node_Sets.Set := Compute_Ada_Nodeset (+P.Cur_Theory);
   begin
      if not No_Imports then
         Add_With_Clause (P, Standard_Why_Package_Name, "Main", EW_Import);

         --  S contains all mentioned Ada entities; for each, we get the
         --  unit where it was defined and add it to the unit set

         for N of S loop

            --  Loop parameters may appear, but they do not have a Why
            --  declaration; we skip them here.

            if Ekind (N) /= E_Loop_Parameter then
               declare
                  File_Name : constant String :=
                    File_Base_Name_Of_Entity (N) & File_Suffix (N);
                  T         : String := Theory_Name (N);
               begin
                  T (T'First) :=
                    Ada.Characters.Handling.To_Upper (T (T'First));
                  if File_Name /= P.Name.all then
                     Add_With_Clause (P, File_Name, T, EW_Import);
                  else
                     Add_With_Clause (P, "", T, EW_Import);
                  end if;
               end;
            end if;
         end loop;
      end if;

      File_Append_To_Theories (P.File, P.Cur_Theory);
      P.Cur_Theory := Why_Empty;
   end Close_Theory;

   --------
   -- Eq --
   --------

   function Eq (Left, Right : Entity_Id) return Boolean is
   begin
      if No (Left) or else No (Right) then
         return Left = Right;
      else
         return
           Full_Name (Left) = Full_Name (Right);
      end if;
   end Eq;

   function Eq (Left, Right : W_Base_Type_Id) return Boolean is
      Left_Kind  : constant EW_Type := Get_Base_Type (Left);
      Right_Kind : constant EW_Type := Get_Base_Type (Right);
   begin
      if Left_Kind /= Right_Kind then
         return False;
      end if;

      return Left_Kind /= EW_Abstract
        or else Eq (Get_Ada_Node (+Left), Get_Ada_Node (+Right));
   end Eq;

   ---------------
   -- Full_Name --
   ---------------

   function Full_Name (N : Entity_Id) return String is
   begin
      if N = Standard_Boolean then
         return "bool";
      elsif N = Universal_Fixed then
         return "real";
      else
         declare
            S : String := Unique_Name (N);
         begin

            --  In Why3, enumeration literals need to be upper case. Why2
            --  doesn't care, so we enforce upper case here

            if Ekind (N) = E_Enumeration_Literal then
               S (S'First) := Ada.Characters.Handling.To_Upper (S (S'First));
            end if;
            return S;
         end;
      end if;
   end Full_Name;

   -----------------
   -- Get_EW_Type --
   -----------------

   function Get_EW_Type (T : W_Primitive_Type_Id) return EW_Type is
   begin
      if Get_Kind (+T) = W_Base_Type then
         return Get_Base_Type (+T);
      else
         return EW_Abstract;
      end if;
   end Get_EW_Type;

   function Get_EW_Type (T : Node_Id) return EW_Type is
      E : constant EW_Type := Get_EW_Term_Type (T);
   begin
      case E is
         when EW_Scalar =>
            return E;
         when others =>
            return EW_Abstract;
      end case;
   end Get_EW_Type;

   ----------------------
   -- Get_EW_Term_Type --
   ----------------------

   function Get_EW_Term_Type (N : Node_Id) return EW_Type is
      Ty : Node_Id := N;
   begin
      if Nkind (N) /= N_Defining_Identifier
        or else not (Ekind (N) in Type_Kind) then
         Ty := Etype (N);
      end if;

      --  Get to the unique type, to skip private type

      Ty := Unique_Entity (Ty);

      case Ekind (Ty) is
         when Real_Kind =>
            return EW_Real;

         when Discrete_Kind =>
            --  In the case of Standard.Boolean, the base type 'bool' is
            --  used directly. For its subtypes, however, an abstract type
            --  representing a signed int is generated, just like for any
            --  other enumeration subtype.
            --  ??? It would make sense to use a bool-based abstract
            --  subtype in this case, and it should be rather easy to
            --  make this change as soon as theory cloning would work
            --  in Why 3. No point in implementing this improvement
            --  before that, as we have seen no cases where this was a
            --  problem for the prover.

            if Ty = Standard_Boolean then
               return EW_Bool;
            elsif Ty = Universal_Fixed then
               return EW_Real;
            else
               return EW_Int;
            end if;

         when Private_Kind =>
            --  We can only be in this case if Ty is *derived* from a private
            --  type. We go up one step to go the the base type.

            return Get_EW_Term_Type (Etype (Ty));

         when others =>
            return EW_Abstract;
      end case;
   end Get_EW_Term_Type;

   ---------
   -- LCA --
   ---------

   function  LCA (Left, Right : W_Base_Type_Id) return W_Base_Type_Id is
   begin
      if Eq (Left, Right) then
         return Left;
      else
         return Why_Types
           (Type_Hierarchy.LCA
             (Get_Base_Type (Base_Why_Type (Left)),
              Get_Base_Type (Base_Why_Type (Right))));
      end if;
   end LCA;

   -------------------------
   -- Make_Empty_Why_File --
   -------------------------

   function Make_Empty_Why_File (S : String) return Why_File is
   begin
      return
        (Name       => new String'(S),
         File       => New_File,
         Cur_Theory => Why_Empty);
   end Make_Empty_Why_File;

   -----------------
   -- Open_Theory --
   -----------------

   procedure Open_Theory (P    : in out Why_File;
                          Name : String;
                          Kind : EW_Theory_Type := EW_Module) is
      S : String := Name;
   begin
      S (S'First) := Ada.Characters.Handling.To_Upper (S (S'First));
      P.Cur_Theory :=
        New_Theory_Declaration (Name => New_Identifier (Name => S),
                                Kind => Kind);
   end Open_Theory;

   --------
   -- Up --
   --------

   function Up (WT : W_Base_Type_Id) return W_Base_Type_Id is
      Kind : constant EW_Type := Get_Base_Type (WT);
   begin
      case Kind is
         when EW_Abstract =>
            return Base_Why_Type (WT);
         when others =>
            return Why_Types (Type_Hierarchy.Up (Kind));
      end case;
   end Up;

   --------
   -- Up --
   --------

   function Up (From, To : W_Base_Type_Id) return W_Base_Type_Id is
   begin
      if Eq (From, To) then
         return From;
      else
         return Up (From);
      end if;
   end Up;

   -----------------
   -- EW_Abstract --
   -----------------

   function EW_Abstract (N : Node_Id) return W_Base_Type_Id is
   begin
      if N = Standard_Boolean then
         return EW_Bool_Type;
      elsif N = Universal_Fixed then
         return EW_Real_Type;
      else
         return New_Base_Type (Base_Type => EW_Abstract, Ada_Node => N);
      end if;
   end EW_Abstract;

begin
   Type_Hierarchy.Move_Child (EW_Array, EW_Array);  --  Special self loop
   Type_Hierarchy.Move_Child (EW_Unit, EW_Real);
   Type_Hierarchy.Move_Child (EW_Int, EW_Bool);
   Type_Hierarchy.Move_Child (EW_Real, EW_Int);
   Type_Hierarchy.Freeze;
end Why.Inter;
