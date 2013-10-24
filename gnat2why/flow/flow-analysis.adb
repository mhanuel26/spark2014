------------------------------------------------------------------------------
--                                                                          --
--                           GNAT2WHY COMPONENTS                            --
--                                                                          --
--                        F L O W . A N A L Y S I S                         --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                  Copyright (C) 2013, Altran UK Limited                   --
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
------------------------------------------------------------------------------

with Ada.Text_IO;

with Namet;                 use Namet;
with Nlists;                use Nlists;
with Sem_Util;              use Sem_Util;
with Sinfo;                 use Sinfo;
with Sinput;                use Sinput;
with Snames;                use Snames;

with Why;

with Gnat2Why_Args;

with Flow.Slice;            use Flow.Slice;
with Flow.Utility;          use Flow.Utility;
with Flow_Error_Messages;   use Flow_Error_Messages;

--  with Treepr;                use Treepr;
--  with Flow.Debug;            use Flow.Debug;

package body Flow.Analysis is

   Debug_Depends_Required : constant Boolean := False;
   --  Enable this to always check the dependency relation, even if
   --  not specified. This may later be a configurable restriction
   --  (requires_depends or similar); but it is quite useful for
   --  debugging anyway.

   use type Ada.Containers.Count_Type;
   use type Flow_Graphs.Vertex_Id;
   use type Node_Sets.Set;
   use type Flow_Id_Sets.Set;

   function Error_Location (G : Flow_Graphs.T'Class;
                            V : Flow_Graphs.Vertex_Id)
                            return Node_Or_Entity_Id;
   --  Find a good place to raise an error for vertex V.

   function Get_Line (G   : Flow_Graphs.T'Class;
                      V   : Flow_Graphs.Vertex_Id;
                      Sep : Character := ':')
                      return String;
   --  Obtain the location for the given vertex as in "foo.adb:12".

   procedure Write_Vertex_Set
     (G        : Flow_Graphs.T;
      Set      : Vertex_Sets.Set;
      Filename : String);
   --  Write a trace file for GPS.

   procedure Global_Required
     (FA  : Flow_Analysis_Graphs;
      Var : Flow_Id)
   with Pre  => Var.Kind = Magic_String;
   --  Emit an error message that (the first call) introducing the
   --  global Var requires a global annotation.

   function Find_Global (S : Entity_Id;
                         F : Flow_Id)
                         return Node_Id;
   --  Find the given global F in the subprogram declaration of S (or
   --  in the initializes clause of S). If we can't find it (perhaps
   --  because of computed globals) we just return S which is a useful
   --  fallback place to raise an error.

   type Var_Use_Kind is (Use_Read, Use_Write, Use_Any);

   function First_Variable_Use (N       : Node_Id;
                                Scope   : Scope_Ptr;
                                Var     : Flow_Id;
                                Precise : Boolean)
                                return Node_Id;
   --  Given a node N, we traverse the tree to find the most deeply
   --  nested node which still uses Var. If Precise is True look only
   --  for Var (for example R.Y), otherwise we also look for the
   --  entire variable represented by Var (in our example we'd also
   --  look for R).
   --
   --  If we cannot find any suitable node we return N itself.

   function First_Variable_Use (FA      : Flow_Analysis_Graphs;
                                Var     : Flow_Id;
                                Kind    : Var_Use_Kind;
                                Precise : Boolean)
                                return Node_Id;
   --  Find a suitable node in the tree which uses the given
   --  variable. If Precise is True look only for Var (for example
   --  R.Y), otherwise we also look for the entire variable
   --  represented by Var (in our example we'd also look for R).
   --
   --  If no suitable node can be found we return FA.Analyzed_Entity
   --  as a fallback.

   --------------------
   -- Error_Location --
   --------------------

   function Error_Location (G : Flow_Graphs.T'Class;
                            V : Flow_Graphs.Vertex_Id)
                            return Node_Or_Entity_Id
   is
      K : constant Flow_Id      := G.Get_Key (V);
      A : constant V_Attributes := G.Get_Attributes (V);
   begin
      if Present (A.Error_Location) then
         return A.Error_Location;

      else
         case K.Kind is
            when Direct_Mapping | Record_Field =>
               return Get_Direct_Mapping_Id (K);

            when others =>
               raise Why.Unexpected_Node;
         end case;
      end if;
   end Error_Location;

   --------------
   -- Get_Line --
   --------------

   function Get_Line (G   : Flow_Graphs.T'Class;
                      V   : Flow_Graphs.Vertex_Id;
                      Sep : Character := ':')
                      return String
   is
      N       : constant Node_Or_Entity_Id := Error_Location (G, V);
      SI      : constant Source_File_Index := Get_Source_File_Index (Sloc (N));
      Line_No : constant String :=
        Logical_Line_Number'Image (Get_Logical_Line_Number (Sloc (N)));
   begin
      return Get_Name_String (File_Name (SI)) & Sep &
        Line_No (2 .. Line_No'Last);
   end Get_Line;

   ----------------------
   -- Write_Vertex_Set --
   ----------------------

   procedure Write_Vertex_Set
     (G        : Flow_Graphs.T;
      Set      : Vertex_Sets.Set;
      Filename : String)
   is
      FD       : Ada.Text_IO.File_Type;
   begin
      if not Set.Is_Empty then

         Ada.Text_IO.Create (FD, Ada.Text_IO.Out_File, Filename);

         for V of Set loop
            declare
               F : constant Flow_Id := G.Get_Key (V);
            begin
               if F.Kind = Direct_Mapping then
                  Ada.Text_IO.Put (FD, Get_Line (G, V));
                  Ada.Text_IO.New_Line (FD);
               end if;
            end;
         end loop;

         Ada.Text_IO.Close (FD);

      end if;
   end Write_Vertex_Set;

   ---------------------
   -- Global_Required --
   ---------------------

   procedure Global_Required
     (FA  : Flow_Analysis_Graphs;
      Var : Flow_Id)
   is
      First_Use : Node_Id;
      Tracefile : Unbounded_String;
   begin

      First_Use := First_Variable_Use (FA      => FA,
                                       Var     => Var,
                                       Kind    => Use_Any,
                                       Precise => True);

      if First_Use = FA.Analyzed_Entity then
         --  Ok, we did not actually find a node which make use of
         --  Var, which is a bit odd. This means that the computed
         --  globals for FA.Analyzed_Entity contain a symbol Var for
         --  no good reason.
         Error_Msg_Flow
           (FA        => FA,
            Tracefile => Tracefile,
            Msg       => "bug: & contains reference to &, " &
              "but no use can be found",
            N         => FA.Analyzed_Entity,
            F1        => Direct_Mapping_Id (FA.Analyzed_Entity),
            F2        => Var);

      else
         pragma Assert (Nkind (First_Use) in N_Subprogram_Call);

         Error_Msg_Flow
           (FA        => FA,
            Tracefile => Tracefile,
            Msg       => "called subprogram & requires GLOBAL " &
              "aspect to make state visible",
            N         => First_Use,
            F1        => Direct_Mapping_Id (Entity (Name (First_Use))));
      end if;

   end Global_Required;

   -----------------
   -- Find_Global --
   -----------------

   function Find_Global (S : Entity_Id;
                         F : Flow_Id)
                         return Node_Id
   is
      Needle     : Entity_Id;
      Haystack_A : Node_Id;
      Haystack_B : Node_Id;
      The_Global : Node_Id := Empty;

      function Find_It (N : Node_Id) return Traverse_Result;
      --  Checks if N refers to Needle and sets The_Global to N if
      --  that is the case.

      function Find_It (N : Node_Id) return Traverse_Result is
      begin
         case Nkind (N) is
            when N_Identifier | N_Expanded_Name =>
               if Present (Entity (N))
                 and then Nkind (Entity (N)) in N_Entity  -- ??? workaround
                 and then Unique_Entity (Entity (N)) = Needle
               then
                  The_Global := N;
                  return Abandon;
               else
                  return OK;
               end if;
            when others =>
               return OK;
         end case;
      end Find_It;

      procedure Look_For_Global is new Traverse_Proc (Find_It);
   begin
      case Ekind (S) is
         when E_Package_Body =>
            Haystack_A := Empty;
            Haystack_B := Get_Pragma (Spec_Entity (S), Pragma_Initializes);

         when E_Package =>
            Haystack_A := Empty;
            Haystack_B := Get_Pragma (S, Pragma_Initializes);

         when others =>
            if Present (Get_Body (S)) then
               Haystack_A := Get_Pragma (Get_Body (S), Pragma_Refined_Global);
            else
               Haystack_A := Empty;
            end if;
            Haystack_B := Get_Pragma (S, Pragma_Global);
      end case;

      case F.Kind is
         when Direct_Mapping | Record_Field =>
            Needle := Get_Direct_Mapping_Id (F);
            Look_For_Global (Haystack_A);
            if Present (The_Global) then
               return The_Global;
            end if;

            Look_For_Global (Haystack_B);
            if Present (The_Global) then
               return The_Global;
            else
               return S;
            end if;

         when Magic_String =>
            return S;

         when Null_Value =>
            raise Why.Unexpected_Node;
      end case;
   end Find_Global;

   ------------------------
   -- First_Variable_Use --
   ------------------------

   function First_Variable_Use (N       : Node_Id;
                                Scope   : Scope_Ptr;
                                Var     : Flow_Id;
                                Precise : Boolean)
                                return Node_Id
   is
      First_Use : Node_Id := N;
      Var_Tgt   : constant Flow_Id :=
        Change_Variant ((if Precise then Var else Entire_Variable (Var)),
                        Normal_Use);

      function Search_Expr (N : Node_Id) return Traverse_Result;
      --  This function sets First_Use to the given node if it
      --  contains the variable we're looking for. If not, we abort
      --  the search.

      -----------------
      -- Search_Expr --
      -----------------

      function Search_Expr (N : Node_Id) return Traverse_Result is
      begin
         if Get_Variable_Set (Scope            => Scope,
                              N                => N,
                              Reduced          => not Precise,
                              Allow_Statements => True).Contains (Var_Tgt)
         then
            First_Use := N;
            return OK;
         else
            return Skip;
         end if;
      end Search_Expr;

      procedure Search_Expression is new Traverse_Proc (Search_Expr);
      --  This will narrow down the location of the searched for
      --  variable in the given node as far as possible.

   begin
      Search_Expression (N);
      return First_Use;
   end First_Variable_Use;

   function First_Variable_Use (FA      : Flow_Analysis_Graphs;
                                Var     : Flow_Id;
                                Kind    : Var_Use_Kind;
                                Precise : Boolean)
                                return Node_Id
   is
      Var_Normal   : constant Flow_Id := Change_Variant (Var, Normal_Use);
      E_Var_Normal : constant Flow_Id := Entire_Variable (Var_Normal);

      First_Use : Node_Id := FA.Analyzed_Entity;

      procedure Proc (V      : Flow_Graphs.Vertex_Id;
                      Origin : Flow_Graphs.Vertex_Id;
                      Depth  : Natural;
                      T_Ins  : out Flow_Graphs.Simple_Traversal_Instruction);
      --  Checks if vertex V contains a reference to Var. If so, we
      --  set First_Use and abort the search.

      ----------
      -- Proc --
      ----------

      procedure Proc (V      : Flow_Graphs.Vertex_Id;
                      Origin : Flow_Graphs.Vertex_Id;
                      Depth  : Natural;
                      T_Ins  : out Flow_Graphs.Simple_Traversal_Instruction)
      is
         pragma Unreferenced (Origin, Depth);

         Atr         : constant V_Attributes := FA.CFG.Get_Attributes (V);
         Check_Read  : constant Boolean      := Kind in Use_Read | Use_Any;
         Check_Write : constant Boolean      := Kind in Use_Write | Use_Any;
         Of_Interest : Boolean               := False;

      begin

         --  First we check if the current vertex contains the
         --  variable of interest.

         if Check_Read then
            if Atr.Variables_Used.Contains (Var_Normal) or
              (not Precise and then
                 To_Entire_Variables (Atr.Variables_Used).Contains
                 (E_Var_Normal))
            then
               Of_Interest := True;
            end if;
         end if;
         if Check_Write then
            if Atr.Variables_Defined.Contains (Var_Normal) or
              (not Precise and then
                 To_Entire_Variables (Atr.Variables_Defined).Contains
                 (E_Var_Normal))
            then
               Of_Interest := True;
            end if;
         end if;

         --  If not we stop here.

         if not Of_Interest then
            T_Ins := Flow_Graphs.Continue;
            return;
         else
            T_Ins := Flow_Graphs.Abort_Traversal;
         end if;

         --  Not all vertices containing the variable are actually
         --  interesting. We want to deal only with program statements
         --  and procedure calls.

         if (Atr.Is_Program_Node or Atr.Is_Precondition) and
           not Atr.Is_Callsite
         then
            First_Use := Get_Direct_Mapping_Id (FA.CFG.Get_Key (V));
         elsif Atr.Is_Parameter then
            First_Use := Get_Direct_Mapping_Id (Atr.Parameter_Actual);
         elsif Atr.Is_Global_Parameter then
            --  If we have a global, the procedure call itself is the
            --  best location we can provide.
            First_Use := Get_Direct_Mapping_Id (Atr.Call_Vertex);
            return;
         else
            --  If we don't have any of the above, we should keep
            --  searching for other, more suitable, vertices.
            T_Ins := Flow_Graphs.Continue;
            return;
         end if;

         --  We have found a suitable vertex. We can now narrow down
         --  the location to the individual subexpression which
         --  contains the variable.

         case Nkind (First_Use) is
            when N_If_Statement | N_Elsif_Part =>
               First_Use := Condition (First_Use);

            when N_Case_Statement =>
               First_Use := Expression (First_Use);

            when N_Loop_Statement =>
               First_Use := Iteration_Scheme (First_Use);

            when others =>
               null;
         end case;

         First_Use := First_Variable_Use (N       => First_Use,
                                          Scope   => FA.Scope,
                                          Var     => Var,
                                          Precise => Precise);
      end Proc;
   begin
      FA.CFG.BFS (Start         => FA.Start_Vertex,
                  Include_Start => False,
                  Visitor       => Proc'Access);
      return First_Use;
   end First_Variable_Use;

   ------------------
   -- Analyse_Main --
   ------------------

   procedure Analyse_Main (FA : in out Flow_Analysis_Graphs) is
      Reads     : Flow_Id_Sets.Set;
      Unused    : Flow_Id_Sets.Set;
      Tracefile : Unbounded_String;
   begin
      if not FA.Is_Main then
         --  Nothing to see here, move along.
         return;
      end if;

      --  We need to make sure all global inputs are initialized. This
      --  means the following needs to hold:
      --     Input   ->   State must be initialized
      --     In_Out  ->   State must be initialized
      --     Output  ->   Always OK
      Get_Globals (Subprogram   => FA.Analyzed_Entity,
                   Reads        => Reads,
                   Writes       => Unused,
                   Refined_View => True);
      Reads := To_Entire_Variables (Reads);
      --  Note we never actually need writes in this analysis.

      for R of Reads loop
         --  ??? Fix this for magic strings once M711-031 is implemented
         if not (R.Kind in Direct_Mapping | Record_Field and then
                   Is_Initialized_At_Elaboration (Get_Direct_Mapping_Id (R)))
         then
            Error_Msg_Flow
              (FA        => FA,
               Tracefile => Tracefile,
               Msg       => "& might not be initialized after elaboration " &
                 "of main program &",
               N         => Find_Global (FA.Analyzed_Entity, R),
               F1        => R,
               F2        => Direct_Mapping_Id (FA.Analyzed_Entity),
               Tag       => "uninitialized",
               Warning   => True);
         end if;

      end loop;
   end Analyse_Main;

   ------------------
   -- Sanity_Check --
   ------------------

   procedure Sanity_Check (FA   : Flow_Analysis_Graphs;
                           Sane : out Boolean)
   is
      Tracefile : Unbounded_String;
      All_Vars : constant Flow_Id_Sets.Set :=
        To_Entire_Variables (FA.All_Vars);

      function Proc_Record_Decl (N : Node_Id) return Traverse_Result;
      --  Check each component declaration for use of non-manifest
      --  constants.

      function Quantified_Variables (N : Node_Id) return Flow_Id_Sets.Set;
      --  Return the set of variables which are introduced in a
      --  quantifier under node N

      function Proc_Record_Decl (N : Node_Id) return Traverse_Result
      is
      begin
         case Nkind (N) is
            when N_Subprogram_Body | N_Package_Body =>
               --  We do not want to process declarations any nested
               --  subprograms or packages.
               if N = FA.Scope then
                  return OK;
               else
                  return Skip;
               end if;
            when N_Component_Declaration =>
               if Present (Expression (N)) then
                  declare
                     Deps : constant Ordered_Flow_Id_Sets.Set :=
                       To_Ordered_Flow_Id_Set (Get_Variable_Set
                                                 (Get_Enclosing_Body_Scope (N),
                                                  Expression (N)));
                  begin
                     for F of Deps loop
                        --  ??? consider moving this to spark_definition
                        Error_Msg_Flow
                          (FA        => FA,
                           Tracefile => Tracefile,
                           Msg       => "default initialization cannot " &
                             "depend on &",
                           N         => Expression (N),
                           F1        => F);
                        Sane := False;
                     end loop;
                  end;
               end if;

               return Skip;
            when others =>
               return OK;
         end case;
      end Proc_Record_Decl;

      procedure Check_Record_Declarations is
        new Traverse_Proc (Proc_Record_Decl);

      function Quantified_Variables (N : Node_Id) return Flow_Id_Sets.Set
      is
         RV : Flow_Id_Sets.Set := Flow_Id_Sets.Empty_Set;

         function Proc (N : Node_Id) return Traverse_Result;

         function Proc (N : Node_Id) return Traverse_Result is
         begin
            case Nkind (N) is
               when N_Quantified_Expression =>
                  --  Sanity check: Iterator_Specification is not in
                  --  SPARK so it should always be empty.
                  pragma Assert (not Present (Iterator_Specification (N)));

                  RV.Include (Direct_Mapping_Id
                                (Defining_Identifier
                                   (Loop_Parameter_Specification (N))));

               when others =>
                  null;
            end case;
            return OK;
         end Proc;

         procedure Traverse is new Traverse_Proc (Proc);
      begin
         Traverse (N);
         return RV;
      end Quantified_Variables;

   begin
      --  Innocent until proven guilty.
      Sane := True;

      --  Sanity check for functions with global outputs.
      if Ekind (FA.Analyzed_Entity) = E_Function
        and then FA.Function_Side_Effects_Present
      then
         if Gnat2Why_Args.Flow_Debug_Mode then
            Error_Msg_Flow
              (FA        => FA,
               Tracefile => Tracefile,
               Msg       => "flow analysis of & abandoned due to " &
                 "function with side effects",
               N         => FA.Analyzed_Entity,
               F1        => Direct_Mapping_Id (FA.Analyzed_Entity));
         end if;
         Sane := False;
         return;
      end if;

      --  Sanity check for aliasing.

      pragma Assert_And_Cut (Sane);

      if FA.Aliasing_Present then
         if Gnat2Why_Args.Flow_Debug_Mode then
            Error_Msg_Flow
              (FA        => FA,
               Tracefile => Tracefile,
               Msg       => "flow analysis of & abandoned due to aliasing",
               N         => FA.Analyzed_Entity,
               F1        => Direct_Mapping_Id (FA.Analyzed_Entity));
         end if;
         Sane := False;
         return;
      end if;

      --  Sanity check for bad default initializations.

      pragma Assert_And_Cut (Sane);

      Check_Record_Declarations (FA.Scope);
      if not Sane then
         if Gnat2Why_Args.Flow_Debug_Mode then
            Error_Msg_Flow
              (FA        => FA,
               Tracefile => Tracefile,
               Msg       => "flow analysis of & abandoned due to records " &
                 "with non-manifest initializations",
               N         => FA.Analyzed_Entity,
               F1        => Direct_Mapping_Id (FA.Analyzed_Entity));
         end if;
         return;
      end if;

      --  Sanity check that postconditions do not reference
      --  non-visible state.

      pragma Assert_And_Cut (Sane);

      for Expr of Get_Postcondition_Expressions (FA.Spec_Node) loop
         declare
            --  The variables used are all variables appearing in the
            --  expression - any that have been introduced through a
            --  quantifier.
            V_Used : constant Ordered_Flow_Id_Sets.Set :=
              To_Ordered_Flow_Id_Set
              (To_Entire_Variables
                 (Get_Variable_Set (FA.Scope, Expr, True) -
                    Quantified_Variables (Expr)));

            Tmp : constant String :=
              (case FA.Kind is
                  when E_Subprogram_Body => "Global",
                  when others            => "Initializes");
         begin
            for Var of V_Used loop
               if not All_Vars.Contains (Var) then
                  --  ??? it would be nice to improve the error location
                  Error_Msg_Flow
                    (FA        => FA,
                     Tracefile => Tracefile,
                     Msg       => "& must be listed in the " & Tmp &
                       " aspect of &",
                     N         => First_Variable_Use (N       => Expr,
                                                      Scope   => FA.Scope,
                                                      Var     => Var,
                                                      Precise => False),
                     F1        => Entire_Variable (Var),
                     F2        => Direct_Mapping_Id (FA.Analyzed_Entity));
                  Sane := False;
               end if;
            end loop;
         end;
      end loop;
      if not Sane then
         return;
      end if;

      --  Sanity check all vertices if they mention a flow id that we
      --  do not know about.

      pragma Assert_And_Cut (Sane);

      for V of FA.CFG.Get_Collection (Flow_Graphs.All_Vertices) loop
         declare
            A : constant V_Attributes := FA.CFG.Get_Attributes (V);

            All_Vars : constant Ordered_Flow_Id_Sets.Set :=
              To_Ordered_Flow_Id_Set (A.Variables_Used or A.Variables_Defined);
         begin
            for Var of All_Vars loop
               declare
                  Neutral : constant Flow_Id :=
                    Change_Variant (Var, Normal_Use);
                  Tmp : constant String :=
                    (case FA.Kind is
                        when E_Subprogram_Body => "Global",
                        when others            => "Initializes");
               begin
                  if not FA.All_Vars.Contains (Neutral) then
                     case Neutral.Kind is
                        when Direct_Mapping | Record_Field =>
                           --  ??? hopefully we can move this to
                           --  spark_definition too

                           --  ??? maybe also point to the first
                           --  occurrence of the variable, possibly
                           --  via a continuation message
                           Error_Msg_Flow
                             (FA        => FA,
                              Tracefile => Tracefile,
                              Msg       => "& must be listed in the " & Tmp &
                                " aspect of &",
                              N   => First_Variable_Use (FA      => FA,
                                                         Var     => Var,
                                                         Kind    => Use_Read,
                                                         Precise => False),
                              F1  => Entire_Variable (Var),
                              F2  => Direct_Mapping_Id (FA.Analyzed_Entity));

                        when Magic_String =>
                           Global_Required (FA, Var);

                        when others =>
                           raise Why.Unexpected_Node;
                     end case;
                     Sane := False;
                  end if;
               end;
            end loop;
         end;
      end loop;

      if not Sane then
         if Gnat2Why_Args.Flow_Debug_Mode then
            Error_Msg_Flow
              (FA        => FA,
               Tracefile => Tracefile,
               Msg       => "flow analysis of & abandoned due to " &
                 "inconsistent graph",
               N   => FA.Analyzed_Entity,
               F1  => Direct_Mapping_Id (FA.Analyzed_Entity));
         end if;
         return;
      end if;

   end Sanity_Check;

   ----------------------------
   -- Find_Unwritten_Exports --
   ----------------------------

   procedure Find_Unwritten_Exports (FA : in out Flow_Analysis_Graphs) is
      F_Final   : Flow_Id;
      A_Final   : V_Attributes;
      F_Initial : Flow_Id;
      A_Initial : V_Attributes;
      Unwritten : Boolean;
      Tracefile : Unbounded_String;

      Written_Entire_Vars : Flow_Id_Sets.Set;
      Unwritten_Vars      : Vertex_Sets.Set := Vertex_Sets.Empty_Set;
   begin
      for V of FA.PDG.Get_Collection (Flow_Graphs.All_Vertices) loop
         F_Final := FA.PDG.Get_Key (V);
         A_Final := FA.PDG.Get_Attributes (V);
         if F_Final.Variant = Final_Value and then
           A_Final.Is_Export
         then

            --  We have a final use vertex which is an export that has
            --  a single in-link. If this in-link is its initial value
            --  then clearly we do not set defined this output on any
            --  path.

            Unwritten := False;
            if FA.PDG.In_Neighbour_Count (V) = 1 then
               F_Initial := FA.PDG.Get_Key (FA.PDG.Parent (V));
               A_Initial := FA.PDG.Get_Attributes (FA.PDG.Parent (V));
               if F_Initial.Variant = Initial_Value and then
                 A_Initial.Is_Import and then
                 Change_Variant (F_Initial, Final_Value) = F_Final
               then
                  Unwritten := True;
               end if;
            end if;

            if Unwritten then
               Unwritten_Vars.Include (V);
            else
               Written_Entire_Vars.Include (Entire_Variable (F_Final));
            end if;
         end if;
      end loop;

      for V of Unwritten_Vars loop
         F_Final := FA.PDG.Get_Key (V);
         A_Final := FA.PDG.Get_Attributes (V);

         if not Written_Entire_Vars.Contains (Entire_Variable (F_Final)) then

            if not (F_Final.Kind in Direct_Mapping | Record_Field)
              or else not FA.Unmodified_Vars.Contains
                            (Get_Direct_Mapping_Id (F_Final))
            then

               if A_Final.Is_Global then
                  Error_Msg_Flow
                    (FA        => FA,
                     Tracefile => Tracefile,
                     Msg       => "& is not modified, could be INPUT",
                     N         => Find_Global (FA.Analyzed_Entity, F_Final),
                     F1        => F_Final,
                     Tag       => "inout_only_read",
                     Warning   => True);
               else
                  Error_Msg_Flow
                    (FA        => FA,
                     Tracefile => Tracefile,
                     Msg       => "& is not modified, could be IN",
                     N         => Error_Location (FA.PDG, V),
                     F1        => F_Final,
                     Tag       => "inout_only_read",
                     Warning   => True);
               end if;
            end if;
         end if;
      end loop;
   end Find_Unwritten_Exports;

   ------------------------------
   -- Find_Ineffective_Imports --
   ------------------------------

   procedure Find_Ineffective_Imports (FA : in out Flow_Analysis_Graphs) is
      function Is_Final_Use (V : Flow_Graphs.Vertex_Id) return Boolean
      is (FA.PDG.Get_Key (V).Variant = Final_Value and then
            FA.PDG.Get_Attributes (V).Is_Export);
      --  Checks if the given vertex V is a final-use vertex.

      Effective_Ids   : Vertex_Sets.Set := Vertex_Sets.Empty_Set;
      Entire_Ids      : Vertex_Sets.Set := Vertex_Sets.Empty_Set;
      Tracefile       : Unbounded_String;
   begin
      for V of FA.PDG.Get_Collection (Flow_Graphs.All_Vertices) loop
         declare
            Key : constant Flow_Id      := FA.PDG.Get_Key (V);
            Atr : constant V_Attributes := FA.PDG.Get_Attributes (V);
         begin
            if Key.Variant = Initial_Value
              and then Atr.Is_Initialised
              and then (not Atr.Is_Loop_Parameter)
            then
               --  Note the entire variable.
               declare
                  P : Flow_Graphs.Vertex_Id := V;
               begin
                  while P /= Flow_Graphs.Null_Vertex loop
                     if FA.CFG.Parent (P) = Flow_Graphs.Null_Vertex then
                        Entire_Ids.Include (P);
                        exit;
                     end if;
                     P := FA.CFG.Parent (P);
                  end loop;
               end;

               --  Check if we're ineffective or not.
               if FA.PDG.Non_Trivial_Path_Exists (V,
                                                  Is_Final_Use'Access)
               then
                  --  We can reach a final use vertex, so we are doing
                  --  something useful. We flag up the entire chain as
                  --  being useful.
                  Effective_Ids.Include (V);
                  declare
                     P : Flow_Graphs.Vertex_Id := V;
                  begin
                     while P /= Flow_Graphs.Null_Vertex loop
                        Effective_Ids.Include (P);
                        P := FA.CFG.Parent (P);
                     end loop;
                  end;
               else
                  --  We cannot reach any final use vertex, hence the
                  --  import of V is ineffective.
                  null;
               end if;
            end if;
         end;
      end loop;

      --  Now that we can issue error messages. We can't do it inline
      --  because we need to pay special attention to records.
      for V of Entire_Ids loop
         declare
            F : constant Flow_Id      := FA.PDG.Get_Key (V);
            A : constant V_Attributes := FA.PDG.Get_Attributes (V);
         begin
            if not Effective_Ids.Contains (V) then

               if not (F.Kind in Direct_Mapping | Record_Field)
                 or else not FA.Unreferenced_Vars.Contains
                               (Get_Direct_Mapping_Id (F))
               then

                  if Is_Discriminant (F) then
                     --  Discriminants are never ineffective imports.
                     null;
                  elsif A.Is_Global then
                     if FA.Kind = E_Subprogram_Body and then
                       not FA.Is_Generative
                     then
                        Error_Msg_Flow
                          (FA        => FA,
                           Tracefile => Tracefile,
                           Msg       => "unused initial value of &",
                           N         => Find_Global (FA.Analyzed_Entity, F),
                           F1        => F,
                           Tag       => "unused_initial_value",
                        Warning => True);
                     end if;
                  else
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "unused initial value of &",
                        --  ??? find_import
                        N         => Error_Location (FA.PDG, V),
                        F1        => F,
                        Tag       => "unused_initial_value",
                        Warning   => True);
                  end if;
               end if;
            end if;
         end;
      end loop;
   end Find_Ineffective_Imports;

   --------------------------
   -- Find_Illegal_Updates --
   --------------------------

   procedure Find_Illegal_Updates (FA : in out Flow_Analysis_Graphs) is
      Tracefile : Unbounded_String;

      procedure Print_Error (Illegal_Use_Loc : Flow_Graphs.Vertex_Id;
                             The_Global_Id   : Flow_Id;
                             The_Global_Atr  : V_Attributes);
      --  Helper procedure to print the error message.

      procedure Print_Error (Illegal_Use_Loc : Flow_Graphs.Vertex_Id;
                             The_Global_Id   : Flow_Id;
                             The_Global_Atr  : V_Attributes)
      is
         Illegal_Use_Atr : constant V_Attributes :=
           FA.PDG.Get_Attributes (Illegal_Use_Loc);
         Tag : constant String := "illegal_update";
      begin
         if The_Global_Atr.Is_Global then
            if FA.Kind in E_Package | E_Package_Body then
               Error_Msg_Flow
                 (FA        => FA,
                  Tracefile => Tracefile,
                  Msg       => "illegal update of &," &
                    " which is not part of &",
                  N         => Error_Location (FA.PDG, Illegal_Use_Loc),
                  F1        => The_Global_Id,
                  F2        => Direct_Mapping_Id (FA.Analyzed_Entity),
                  Tag       => Tag);

            else
               Error_Msg_Flow
                 (FA        => FA,
                  Tracefile => Tracefile,
                  Msg       => "& must be a global output of &",
                  N         => Error_Location (FA.PDG, Illegal_Use_Loc),
                  F1        => (if Illegal_Use_Atr.Is_Parameter
                                then Illegal_Use_Atr.Parameter_Formal
                                else The_Global_Id),
                  F2        => Direct_Mapping_Id (FA.Analyzed_Entity),
                  Tag       => Tag);
            end if;
         else
            --  It *has* to be a global. The compiler would catch any
            --  updates to in parameters and loop parameters...
            raise Why.Unexpected_Node;
         end if;
      end Print_Error;
   begin
      --  We look at all vertices...
      for V of FA.PDG.Get_Collection (Flow_Graphs.All_Vertices) loop
         --  For any vertex which defines a variable (at most one, I
         --  suppose) we check we are allowed to define that variable.
         for Var of FA.PDG.Get_Attributes (V).Variables_Defined loop
            declare
               Corresp_Final_Vertex : constant Flow_Graphs.Vertex_Id :=
                 FA.PDG.Get_Vertex (Change_Variant (Var, Final_Value));
               pragma Assert (Corresp_Final_Vertex /=
                                Flow_Graphs.Null_Vertex);

               Final_Atr : constant V_Attributes :=
                 FA.PDG.Get_Attributes (Corresp_Final_Vertex);
            begin
               --  We only do this check if Var is something which we
               --  should not change.
               if Final_Atr.Is_Constant and not
                 Final_Atr.Is_Loop_Parameter then
                  if FA.PDG.Get_Key (V).Variant = Initial_Value then
                     --  The initial use vertex is, of course, allowed
                     --  to define the variable.
                     null;
                  else
                     Print_Error (Illegal_Use_Loc => V,
                                  The_Global_Id   => Var,
                                  The_Global_Atr  => Final_Atr);
                  end if;
               end if;
            end;
         end loop;
      end loop;
   end Find_Illegal_Updates;

   ---------------------------------
   -- Find_Ineffective_Statements --
   ---------------------------------

   procedure Find_Ineffective_Statements (FA : in out Flow_Analysis_Graphs) is
      Tracefile : Unbounded_String;

      function Is_Final_Use_Any_Export (V : Flow_Graphs.Vertex_Id)
                                        return Boolean;
      --  Checks if the given vertex V is a final-use vertex that is
      --  also an export.

      function Is_Any_Final_Use (V : Flow_Graphs.Vertex_Id)
                                 return Boolean;
      --  Checks if the given vertex V is a final-use vertex.

      function Find_Masking_Code
        (Ineffective_Statement : Flow_Graphs.Vertex_Id)
         return Vertex_Sets.Set;
      --  Find out why a given vertex is ineffective. A vertex is
      --  ineffective if the variable(s) defined by it are re-defined
      --  on all paths leading from it without being used. Thus all
      --  reachable vertices which also define at least one variable
      --  of that set (and do not use it), render the vertex
      --  ineffective.

      function Skip_Any_Conversions (N : Node_Or_Entity_Id)
                                     return Node_Or_Entity_Id;
      --  Skips any conversions (unchecked or otherwise) and jumps to
      --  the actual object.

      -----------------------------
      -- Is_Final_Use_Any_Export --
      -----------------------------

      function Is_Final_Use_Any_Export (V : Flow_Graphs.Vertex_Id)
                                        return Boolean is
      begin
         return FA.PDG.Get_Key (V).Variant = Final_Value and then
           FA.PDG.Get_Attributes (V).Is_Export;
      end Is_Final_Use_Any_Export;

      ----------------------
      -- Is_Any_Final_Use --
      ----------------------

      function Is_Any_Final_Use (V : Flow_Graphs.Vertex_Id)
                                 return Boolean is
      begin
         return FA.PDG.Get_Key (V).Variant = Final_Value;
      end Is_Any_Final_Use;

      -----------------------
      -- Find_Masking_Code --
      -----------------------

      function Find_Masking_Code
        (Ineffective_Statement : Flow_Graphs.Vertex_Id)
         return Vertex_Sets.Set
      is
         Mask         : Vertex_Sets.Set := Vertex_Sets.Empty_Set;
         Vars_Defined : constant Flow_Id_Sets.Set :=
           FA.CFG.Get_Attributes (Ineffective_Statement).Variables_Defined;

         procedure Visitor
           (V  : Flow_Graphs.Vertex_Id;
            TV : out Flow_Graphs.Simple_Traversal_Instruction);
         --  Check if V masks the ineffective statement.

         procedure Visitor
           (V  : Flow_Graphs.Vertex_Id;
            TV : out Flow_Graphs.Simple_Traversal_Instruction)
         is
            Intersection : constant Flow_Id_Sets.Set :=
              Vars_Defined and
              (FA.CFG.Get_Attributes (V).Variables_Defined -
                 FA.CFG.Get_Attributes (V).Variables_Used);
         begin
            if V /= Ineffective_Statement and then
              Intersection.Length >= 1
            then
               Mask.Include (V);
               TV := Flow_Graphs.Skip_Children;
            else
               TV := Flow_Graphs.Continue;
            end if;
         end Visitor;

      begin
         FA.CFG.DFS (Start         => Ineffective_Statement,
                     Include_Start => False,
                     Visitor       => Visitor'Access);
         return Mask;
      end Find_Masking_Code;

      --------------------------
      -- Skip_Any_Conversions --
      --------------------------

      function Skip_Any_Conversions (N : Node_Or_Entity_Id)
                                     return Node_Or_Entity_Id
      is
         P : Node_Or_Entity_Id := N;
      begin
         loop
            case Nkind (P) is
               when N_Type_Conversion =>
                  P := Expression (P);

               when others =>
                  return P;
            end case;
         end loop;
      end Skip_Any_Conversions;

   begin --  Find_Ineffective_Statements
      for V of FA.PDG.Get_Collection (Flow_Graphs.All_Vertices) loop
         declare
            N    : Node_Id;
            Key  : constant Flow_Id      := FA.PDG.Get_Key (V);
            Atr  : constant V_Attributes := FA.PDG.Get_Attributes (V);
            Mask : Vertex_Sets.Set;
            Tag  : constant String := "ineffective";
            Tmp  : Flow_Id;
         begin
            if Atr.Is_Program_Node or
              Atr.Is_Parameter or
              Atr.Is_Global_Parameter
            then
               --  A vertex is ineffective if there is no path in the
               --  PDG to *any* final use vertex that is also an
               --  export.
               --
               --  If we analyse a package, we supress this message if
               --  we don't have a initializes clause *and* the the
               --  given vertex has an effect on any final use (export
               --  or otherwise).
               if
                 --  Basic check here
                 not FA.PDG.Non_Trivial_Path_Exists
                 (V, Is_Final_Use_Any_Export'Access) and then

                 --  Supression for packages without initializes
                 (if FA.Kind in E_Package | E_Package_Body and then
                    not Present (FA.Initializes_N)
                  then
                     not FA.PDG.Non_Trivial_Path_Exists
                       (V, Is_Any_Final_Use'Access))
               then
                  Mask := Find_Masking_Code (V);
                  if FA.PDG.Get_Key (V) = Null_Flow_Id then
                     N := Empty;
                  else
                     N := Get_Direct_Mapping_Id (FA.PDG.Get_Key (V));
                  end if;

                  if Atr.Is_Parameter or Atr.Is_Global_Parameter then
                     if Atr.Is_Parameter then
                        Tmp := Direct_Mapping_Id
                          (Skip_Any_Conversions
                             (Get_Direct_Mapping_Id (Atr.Parameter_Actual)));
                     else
                        Tmp := Atr.Parameter_Formal;
                     end if;

                     if Key.Variant = In_View then
                        --  For in parameters we do not emit the
                        --  ineffective assignment error as its a bit
                        --  confusing.
                        null;

                     elsif Is_Easily_Printable (Tmp) then
                        Error_Msg_Flow
                          (FA        => FA,
                           Tracefile => Tracefile,
                           Msg       => "unused assignment to &",
                           N         => Error_Location (FA.PDG, V),
                           F1        => Tmp,
                           Tag       => Tag,
                           Warning   => True);

                     else
                        Error_Msg_Flow
                          (FA        => FA,
                           Tracefile => Tracefile,
                           Msg       => "unused assignment",
                           N         => Error_Location (FA.PDG, V),
                           Tag       => Tag,
                           Warning   => True);
                     end if;

                  elsif Nkind (N) = N_Assignment_Statement then
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "unused assignment",
                        N         => Error_Location (FA.PDG, V),
                        Tag       => Tag,
                        Warning   => True);

                  elsif Nkind (N) = N_Object_Declaration then
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "initialization has no effect",
                        N         => Error_Location (FA.PDG, V),
                        Tag       => Tag,
                        Warning   => True);

                  else
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "statement has no effect",
                        N         => Error_Location (FA.PDG, V),
                        Tag       => Tag,
                        Warning   => True);

                  end if;
                  if Mask.Length >= 1 then
                     Write_Vertex_Set
                       (G        => FA.PDG,
                        Set      => Mask,
                        Filename => To_String (Tracefile));
                  end if;
               end if;
            end if;
         end;
      end loop;
   end Find_Ineffective_Statements;

   -----------------------------------------
   -- Find_Use_Of_Uninitialised_Variables --
   -----------------------------------------

   procedure Find_Use_Of_Uninitialised_Variables
     (FA : in out Flow_Analysis_Graphs)
   is
      Tracefile : Unbounded_String;

      procedure Mark_Definition_Free_Path
        (From : Flow_Graphs.Vertex_Id;
         To   : Flow_Graphs.Vertex_Id;
         Var  : Flow_Id);
      --  Write a trace file for the error message at E_Loc with the
      --  given Tag. The trace will mark the path From -> To which
      --  does not define Var.

      function Might_Be_Defined_In_Other_Path
        (V_Initial : Flow_Graphs.Vertex_Id;
         V_Use     : Flow_Graphs.Vertex_Id) return Boolean;
      --  Checks if the variable corresponding to V_Initial is defined
      --  on any of the paths that lead to V_Use.
      --
      --  ??? Should V_Initial be a flow_id instead then?

      -------------------------------
      -- Mark_Definition_Free_Path --
      -------------------------------

      procedure Mark_Definition_Free_Path
        (From : Flow_Graphs.Vertex_Id;
         To   : Flow_Graphs.Vertex_Id;
         Var  : Flow_Id)
      is
         Path_Found : Boolean := False;
         Path       : Vertex_Sets.Set;

         procedure Are_We_There_Yet
           (V           : Flow_Graphs.Vertex_Id;
            Instruction : out Flow_Graphs.Traversal_Instruction);
         --  Visitor procedure for Shortest_Path.

         procedure Add_Loc
           (V : Flow_Graphs.Vertex_Id);
         --  Step procedure for Shortest_Path.

         ----------------------
         -- Are_We_There_Yet --
         ----------------------

         procedure Are_We_There_Yet
           (V           : Flow_Graphs.Vertex_Id;
            Instruction : out Flow_Graphs.Traversal_Instruction)
         is
            A : constant V_Attributes := FA.CFG.Get_Attributes (V);
         begin
            if V = To then
               Instruction := Flow_Graphs.Found_Destination;
               Path_Found  := True;
            elsif A.Variables_Defined.Contains (Var) then
               Instruction := Flow_Graphs.Skip_Children;
            else
               Instruction := Flow_Graphs.Continue;
            end if;
         end Are_We_There_Yet;

         -------------
         -- Add_Loc --
         -------------

         procedure Add_Loc
           (V : Flow_Graphs.Vertex_Id)
         is
            F : constant Flow_Id := FA.CFG.Get_Key (V);
         begin
            if V /= To and F.Kind = Direct_Mapping then
               Path.Include (V);
            end if;
         end Add_Loc;

      begin --  Mark_Definition_Free_Path
         FA.CFG.Shortest_Path (Start         => From,
                               Allow_Trivial => False,
                               Search        => Are_We_There_Yet'Access,
                               Step          => Add_Loc'Access);

         --  A little sanity check can't hurt.
         pragma Assert (Path_Found);

         Write_Vertex_Set (G        => FA.CFG,
                           Set      => Path,
                           Filename => To_String (Tracefile));
      end Mark_Definition_Free_Path;

      ------------------------------------
      -- Might_Be_Defined_In_Other_Path --
      ------------------------------------

      function Might_Be_Defined_In_Other_Path
        (V_Initial : Flow_Graphs.Vertex_Id;
         V_Use     : Flow_Graphs.Vertex_Id) return Boolean
      is
         The_Var : constant Flow_Id :=
           Change_Variant (FA.PDG.Get_Key (V_Initial),
                           Normal_Use);

         Key_U : constant Flow_Id := FA.PDG.Get_Key (V_Use);

         The_Var_Is_Array : constant Boolean :=
           (The_Var.Kind = Direct_Mapping
              and then Is_Array_Type (Etype (The_Var.Node)))
           or else
           (The_Var.Kind = Record_Field
              and then Is_Array_Type (Etype (The_Var.Component.Last_Element)));
         --  Notes if The_Var refers to an array.

         Use_Vertex_Points_To_Itself : constant Boolean :=
           (for some V of FA.PDG.Get_Collection (V_Use,
                                                 Flow_Graphs.Out_Neighbours)
              => V = V_Use);
         --  Notes if V_Use belongs to V_Use's Out_Neighbours

         Use_Execution_Is_Unconditional : constant Boolean :=
           (for some V of FA.PDG.Get_Collection (V_Use,
                                                 Flow_Graphs.In_Neighbours)
              => V = FA.Start_Vertex);
         --  Notes if FA.Start_Vertex is among the In_Neighbours of
         --  V_Use in the PDG (in other words, there is no control
         --  dependence on V).

         Is_Defined_In_Other_Path : Boolean := False;

         function The_Var_Is_In_Assignment_RHS return Boolean;
         --  If V_Use is an assignment statement, then this function
         --  checks if The_Var appears on its RHS.
         --
         --  If V_Use is not an assignment statement we return False.

         function Start_To_V_Def_Without_V_Use
           (V_Def : Flow_Graphs.Vertex_Id) return Boolean;
         --  Returns True if there exists a path in the CFG graph from
         --  Start to V_Def that does not cross V_Use.

         procedure Vertex_Defines_Variable
           (V  : Flow_Graphs.Vertex_Id;
            TV : out Flow_Graphs.Simple_Traversal_Instruction);
         --  Checks if V defines the The_Var
         --
         --  Sets Is_Defined_In_Other_Path

         ----------------------------------
         -- The_Var_Is_In_Assignment_RHS --
         ----------------------------------

         function The_Var_Is_In_Assignment_RHS return Boolean is
            Used : Flow_Id_Sets.Set;
         begin
            if Nkind (Key_U.Node) = N_Assignment_Statement then
               Used := Get_Variable_Set (FA.Scope, Expression (Key_U.Node));
               return Used.Contains (The_Var);
            end if;

            return False;
         end The_Var_Is_In_Assignment_RHS;

         ----------------------------------
         -- Start_To_V_Def_Without_V_Use --
         ----------------------------------

         function Start_To_V_Def_Without_V_Use
           (V_Def : Flow_Graphs.Vertex_Id) return Boolean
         is
            Path_Exists : Boolean := False;

            procedure Found_V_Def
              (V  : Flow_Graphs.Vertex_Id;
               TV : out Flow_Graphs.Simple_Traversal_Instruction);
            --  Stops the DFS search when we reach V_Def and skips the
            --  children of V_Use.

            procedure Found_V_Def
              (V  : Flow_Graphs.Vertex_Id;
               TV : out Flow_Graphs.Simple_Traversal_Instruction)
            is
            begin
               if V = V_Use then
                  TV := Flow_Graphs.Skip_Children;
               elsif V = V_Def then
                  Path_Exists := True;
                  TV := Flow_Graphs.Abort_Traversal;
               else
                  TV := Flow_Graphs.Continue;
               end if;
            end Found_V_Def;

         begin
            FA.CFG.DFS (Start         => FA.Start_Vertex,
                        Include_Start => False,
                        Visitor       => Found_V_Def'Access,
                        Reversed      => False);

            return Path_Exists;
         end Start_To_V_Def_Without_V_Use;

         -----------------------------
         -- Vertex_Defines_Variable --
         -----------------------------

         procedure Vertex_Defines_Variable
           (V  : Flow_Graphs.Vertex_Id;
            TV : out Flow_Graphs.Simple_Traversal_Instruction)
         is
         begin

            if V = FA.Start_Vertex or else V = V_Use then

               --  If we reach the start vertex (remember, this
               --  traversal is going backwards through the CFG) or
               --  ourselves, then we should look for another path.

               TV := Flow_Graphs.Skip_Children;

            else

               TV := Flow_Graphs.Continue;
               if FA.CFG.Get_Attributes (V).Variables_Defined.Contains
                 (The_Var)
               then

                  --  OK, so this vertex V does define The_Var. There
                  --  are a few cases where we can possibly issue a
                  --  warning instead of an error.

                  if Start_To_V_Def_Without_V_Use (V_Def => V) then
                     --  There is a path from start -> this definition
                     --  V, that does not use V (but subsequenty
                     --  reaches V).

                     Is_Defined_In_Other_Path := True;
                     TV := Flow_Graphs.Abort_Traversal;

                  elsif not Use_Execution_Is_Unconditional then
                     --  If the execution of v_use is predicated on
                     --  something else, then there might be a path
                     --  that defines the_var first.

                     Is_Defined_In_Other_Path := True;
                     TV := Flow_Graphs.Abort_Traversal;
                  end if;
               end if;

            end if;

         end Vertex_Defines_Variable;

      begin --  Might_Be_Defined_In_Other_Path

         --  Check if there might be some path that defines the
         --  variable before we use it.

         FA.CFG.DFS (Start         => V_Use,
                     Include_Start => False,
                     Visitor       => Vertex_Defines_Variable'Access,
                     Reversed      => True);

         --  Arrays that are partially defined have an implicit
         --  dependency on themselves. For this check, we cannot
         --  depend on the Variables_Used because they capture this
         --  implicit dependency. Instead, if we are dealing with an
         --  array, we recaltulate the variables that appear on the
         --  right hand side of the assignment statement and if the
         --  array is not amongst them, we concider the element
         --  defined without self-reference.

         if (not Is_Defined_In_Other_Path)
           and then Use_Vertex_Points_To_Itself
         then
            case The_Var.Kind is
               when Direct_Mapping | Record_Field =>
                  --  Check if node corresponds to an array.
                  if The_Var_Is_Array
                    and then not The_Var_Is_In_Assignment_RHS
                  then
                     Is_Defined_In_Other_Path := True;
                  end if;

               when Magic_String =>
                  null;

               when others =>
                  raise Why.Unexpected_Node;
            end case;
         end if;

         return Is_Defined_In_Other_Path;
      end Might_Be_Defined_In_Other_Path;

   begin --  Find_Use_Of_Uninitialised_Variables
      for V_Initial of FA.PDG.Get_Collection (Flow_Graphs.All_Vertices) loop

         --  We loop through all vertices, finding the ones that
         --  represent initial values that are not initialised.

         declare
            Key_I : constant Flow_Id      := FA.PDG.Get_Key (V_Initial);
            Atr_I : constant V_Attributes := FA.PDG.Get_Attributes (V_Initial);
         begin
            if Key_I.Variant = Initial_Value and then
              not Atr_I.Is_Initialised
            then

               --  V_Initial is a vertex of an uninitialised initial value
               --  Key_I     is its flow_id
               --  Atr_I     are its attributes

               --  We now look at all its out neighbours in the PDG
               --  (these are vertices using (or depending on) this
               --  uninitialised initial value).

               for V_Use of FA.PDG.Get_Collection
                 (V_Initial, Flow_Graphs.Out_Neighbours) loop
                  declare
                     Key_U : constant Flow_Id := FA.PDG.Get_Key (V_Use);
                     Atr_U : constant V_Attributes :=
                       FA.PDG.Get_Attributes (V_Use);
                  begin

                     --  V_Use is a vertex that depends on V_Initial
                     --  Key_U is its flow_id
                     --  Atr_U are its attributes

                     --  There are a number of places an uninitialised
                     --  value might be used, we issue slightly
                     --  different error messages depending on what
                     --  V_Use represents.

                     if Key_U.Variant = Final_Value then

                        --  This is a final value vertex; this
                        --  suggests there is a path in the CFG that
                        --  never sets the variable.

                        if Atr_U.Is_Global then
                           if Might_Be_Defined_In_Other_Path (V_Initial,
                                                              V_Use)
                           then
                              Error_Msg_Flow
                                (FA        => FA,
                                 Tracefile => Tracefile,
                                 Msg       => "& might not be initialized",
                                 N         => Find_Global
                                   (FA.Analyzed_Entity, Key_I),
                                 F1        => Key_I,
                                 Tag       => "uninitialized",
                                 Warning   => True);
                           else
                              Error_Msg_Flow
                                (FA        => FA,
                                 Tracefile => Tracefile,
                                 Msg       => "& is not initialized",
                                 N         => Find_Global
                                   (FA.Analyzed_Entity, Key_I),
                                 F1        => Key_I,
                                 Tag       => "uninitialized");
                           end if;
                           Mark_Definition_Free_Path
                             (From => FA.Start_Vertex,
                              To   => FA.End_Vertex,
                              Var  => Change_Variant (Key_I, Normal_Use));

                        elsif Atr_U.Is_Function_Return then

                           --  This is actually a totally different
                           --  error. It means we have a path where we
                           --  do not return from the function.

                           if not FA.Last_Statement_Is_Raise then

                              --  We only issue this error when the last
                              --  statement is not a raise statement.

                              Error_Msg_Flow
                                (FA        => FA,
                                 Tracefile => Tracefile,
                                 Msg       =>
                                   "possibly missing return statement in &",
                                 N         =>
                                   Error_Location (FA.PDG, FA.Start_Vertex),
                                 F1        => Direct_Mapping_Id
                                   (FA.Analyzed_Entity),
                                 Tag       => "noreturn");
                              Mark_Definition_Free_Path
                                (From => FA.Start_Vertex,
                                 To   => FA.End_Vertex,
                                 Var  => Change_Variant (Key_I, Normal_Use));
                           end if;

                        elsif Atr_U.Is_Export then

                           --  As we don't have a global, but an
                           --  export, it means we must be dealing
                           --  with a parameter.

                           if Might_Be_Defined_In_Other_Path (V_Initial,
                                                              V_Use)
                           then
                              Error_Msg_Flow
                                (FA        => FA,
                                 Tracefile => Tracefile,
                                 Msg       => "& might not be " &
                                   "initialized in &",
                                 N         => Error_Location
                                   (FA.PDG, V_Use),
                                 F1        => Key_I,
                                 F2        => Direct_Mapping_Id
                                   (FA.Analyzed_Entity),
                                 Tag       => "uninitialized",
                                 Warning   => True);
                           else
                              Error_Msg_Flow
                                (FA        => FA,
                                 Tracefile => Tracefile,
                                 Msg       => "& is not initialized in &",
                                 N         => Error_Location (FA.PDG, V_Use),
                                 F1        => Key_I,
                                 F2        => Direct_Mapping_Id
                                   (FA.Analyzed_Entity),
                                 Tag       => "uninitialized");
                           end if;
                           Mark_Definition_Free_Path
                             (From => FA.Start_Vertex,
                              To   => FA.End_Vertex,
                              Var  => Change_Variant (Key_I, Normal_Use));

                        else

                           --  We are dealing with a local variable,
                           --  so we don't care if there is a path
                           --  where it is not set.

                           null;
                        end if;
                     else

                        --  V_Use is not a final vertex.

                        if Might_Be_Defined_In_Other_Path (V_Initial,
                                                           V_Use)
                        then
                           Error_Msg_Flow
                             (FA        => FA,
                              Tracefile => Tracefile,
                              Msg       => "& might not be initialized",
                              N         => Error_Location (FA.PDG, V_Use),
                              F1        => Key_I,
                              Tag       => "uninitialized",
                              Warning   => True);
                           Mark_Definition_Free_Path
                             (From => FA.Start_Vertex,
                              To   => V_Use,
                              Var  => Change_Variant (Key_I, Normal_Use));
                        else
                           Error_Msg_Flow
                             (FA        => FA,
                              Tracefile => Tracefile,
                              Msg       => "& is not initialized",
                              N         => Error_Location (FA.PDG, V_Use),
                              F1        => Key_I,
                              Tag       => "uninitialized");
                           Mark_Definition_Free_Path
                             (From => FA.Start_Vertex,
                              To   => V_Use,
                              Var  => Change_Variant (Key_I, Normal_Use));
                        end if;

                     end if;
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Find_Use_Of_Uninitialised_Variables;

   --------------------------
   -- Find_Stable_Elements --
   --------------------------

   procedure Find_Stable_Elements (FA : in out Flow_Analysis_Graphs) is
      Done      : Boolean       := False;
      Tmp       : Flow_Graphs.T := FA.DDG.Create;
      Is_Stable : Boolean;
      Tracefile : Unbounded_String;
   begin
      for Loop_Id of FA.Loops loop
         Done := False;
         while not Done loop
            Done := True;
            for N_Loop of FA.PDG.Get_Collection (Flow_Graphs.All_Vertices) loop
               declare
                  Atr : V_Attributes := Tmp.Get_Attributes (N_Loop);
               begin
                  if Atr.Loops.Contains (Loop_Id) then
                     --  For all nodes in the loop, do:

                     --  We start by checking if the used variables
                     --  contain the loop parameter for our loop.
                     if Present (Loop_Parameter_From_Loop (Loop_Id)) then
                        Is_Stable := not Atr.Variables_Used.Contains
                          (Direct_Mapping_Id
                             (Loop_Parameter_From_Loop (Loop_Id)));
                     else
                        Is_Stable := True;
                     end if;

                     --  We then check if we have at least one
                     --  in-neighbour from "outside" the loop.
                     if Is_Stable then
                        for V of FA.PDG.Get_Collection
                          (N_Loop, Flow_Graphs.In_Neighbours) loop
                           if Tmp.Get_Attributes (V).Loops.Contains
                             (Loop_Id) then
                              Is_Stable := False;
                              exit;
                           end if;
                        end loop;
                     end if;

                     if Is_Stable then
                        --  Remove from the loop
                        Atr.Loops.Delete (Loop_Id);
                        Tmp.Set_Attributes (N_Loop, Atr);

                        --  Complain
                        Error_Msg_Flow
                          (FA        => FA,
                           Tracefile => Tracefile,
                           Msg       => "stable",
                           N         => Error_Location (FA.PDG, N_Loop),
                           Tag       => "stable",
                           Warning   => True);

                        --  There might be other stable elements now.
                        Done := False;
                     end if;
                  end if;
               end;
            end loop;
         end loop;
      end loop;
   end Find_Stable_Elements;

   -------------------------
   -- Find_Unused_Objects --
   -------------------------

   procedure Find_Unused_Objects (FA : in out Flow_Analysis_Graphs) is
      Used_Ids   : Vertex_Sets.Set := Vertex_Sets.Empty_Set;
      Entire_Ids : Vertex_Sets.Set := Vertex_Sets.Empty_Set;
      Tracefile  : Unbounded_String;
   begin
      --  First we collect a set of all unused inputs.
      for V_Initial of FA.PDG.Get_Collection (Flow_Graphs.All_Vertices) loop
         declare
            I_F       : constant Flow_Id := FA.PDG.Get_Key (V_Initial);
            V_Final   : Flow_Graphs.Vertex_Id;
            F_F       : Flow_Id;
            Is_Unused : Boolean := False;
         begin
            if I_F.Variant = Initial_Value then
               --  For all 'initial vertices which have precisely one
               --  link...
               if FA.PDG.Out_Neighbour_Count (V_Initial) = 1 then
                  for V of FA.PDG.Get_Collection
                    (V_Initial, Flow_Graphs.Out_Neighbours)
                  loop
                     V_Final := V;
                  end loop;
                  F_F := FA.PDG.Get_Key (V_Final);
                  --  If that one link goes directly to the final use
                  --  vertex and its the only link...
                  if F_F.Variant = Final_Value and then
                    FA.PDG.In_Neighbour_Count (V_Final) = 1
                  then
                     --  then we are dealing with an unused object.
                     Is_Unused := True;
                  end if;
               end if;

               --  Note the entire variable.
               declare
                  P : Flow_Graphs.Vertex_Id := V_Initial;
               begin
                  while P /= Flow_Graphs.Null_Vertex loop
                     if FA.CFG.Parent (P) = Flow_Graphs.Null_Vertex then
                        Entire_Ids.Include (P);
                        exit;
                     end if;
                     P := FA.CFG.Parent (P);
                  end loop;
               end;

               --  Flag up records used.
               if not Is_Unused then
                  declare
                     P : Flow_Graphs.Vertex_Id := V_Initial;
                  begin
                     while P /= Flow_Graphs.Null_Vertex loop
                        Used_Ids.Include (P);
                        P := FA.CFG.Parent (P);
                     end loop;
                  end;
               end if;
            end if;
         end;
      end loop;

      --  Now that we have this set we can issue error messages. We
      --  can't do it inline because we need to pay special attention
      --  to records.
      for V of Entire_Ids loop
         if not Used_Ids.Contains (V) then
            declare
               F : constant Flow_Id      := FA.PDG.Get_Key (V);
               A : constant V_Attributes := FA.PDG.Get_Attributes (V);
            begin
               if Is_Discriminant (F) then
                  --  Discriminants can never not be used.
                  null;
               elsif A.Is_Global then
                  --  We have an unused global, we need to give the
                  --  error on the subprogram, instead of the
                  --  global. In generative mode we don't produce this
                  --  warning.

                  if not FA.Is_Generative then
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "unused global &",
                        N         => Find_Global (FA.Analyzed_Entity, F),
                        F1        => F,
                        Tag       => "unused",
                        Warning   => True);
                  end if;
               else
                  --  ??? distinguish between variables and parameters
                  Error_Msg_Flow
                    (FA        => FA,
                     Tracefile => Tracefile,
                     Msg       => "unused variable &",
                     N         => Error_Location (FA.PDG, V),
                     F1        => F,
                     Tag       => "unused",
                     Warning   => True);
               end if;
            end;
         end if;
      end loop;
   end Find_Unused_Objects;

   ---------------------
   -- Check_Contracts --
   ---------------------

   procedure Check_Contracts (FA : in out Flow_Analysis_Graphs) is
      Tracefile : Unbounded_String;

      function Find_Export (E : Entity_Id) return Node_Id;
      --  Looks through the depends aspect on FA.Analyzed_Entity and
      --  returns the node which represents E in the dependency for E.
      --  If none can be found, returns FA.Analyzed_Entity as a
      --  fallback.

      -----------------
      -- Find_Export --
      -----------------

      function Find_Export (E : Entity_Id) return Node_Id
      is
         Depends_Contract : Node_Id;
         Needle           : Node_Id := Empty;

         function Proc (N : Node_Id) return Traverse_Result;
         --  Searches dependency aspect for export E and sets needle
         --  to the node, if found.

         function Proc (N : Node_Id) return Traverse_Result is
            Tmp : Node_Id;
         begin
            case Nkind (N) is
               when N_Component_Association =>
                  Tmp := First (Choices (N));
                  while Present (Tmp) loop
                     if Entity (Tmp) = E then
                        Needle := Tmp;
                        return Abandon;
                     end if;
                     Tmp := Next (Tmp);
                  end loop;
                  return Skip;
               when others =>
                  null;
            end case;
            return OK;
         end Proc;

         procedure Find_Export_Internal is new Traverse_Proc (Proc);

      begin
         if Present (FA.Refined_Depends_N) then
            Depends_Contract := FA.Refined_Depends_N;
         elsif Present (FA.Depends_N) then
            Depends_Contract := FA.Depends_N;
         else
            return FA.Analyzed_Entity;
         end if;

         Find_Export_Internal (Depends_Contract);
         if Present (Needle) then
            return Needle;
         else
            return FA.Analyzed_Entity;
         end if;
      end Find_Export;

      User_Deps   : Dependency_Maps.Map;
      Actual_Deps : Dependency_Maps.Map;

      Depends_Location : constant Node_Id :=
        (if Has_Depends (FA.Analyzed_Entity) then
            Get_Pragma (FA.Analyzed_Entity, Pragma_Depends)
         else
            FA.Analyzed_Entity);

   begin --  Check_Contracts

      if Present (FA.Refined_Depends_N) then
         User_Deps := Parse_Depends (FA.Refined_Depends_N);

      elsif Present (FA.Depends_N) then
         User_Deps := Parse_Depends (FA.Depends_N);

      elsif Debug_Depends_Required then
         User_Deps := Dependency_Maps.Empty_Map;

      else
         --  If the user has not specified a dependency relation we
         --  have no work to do.
         return;
      end if;

      Actual_Deps := Compute_Dependency_Relation (FA);

      --  Print_Dependency_Map (User_Deps);
      --  Print_Dependency_Map (Actual_Deps);

      --  If the user depds do not include something we have in the
      --  actual deps we will raise an appropriate error. We should
      --  however also sanity check there is nothing in the user
      --  dependencies which is *not* in the actual dependencies.

      for C in User_Deps.Iterate loop
         declare
            F_Out : constant Flow_Id := Dependency_Maps.Key (C);
         begin
            if not Actual_Deps.Contains (F_Out) then
               --  ??? check quotation in errout.ads
               Error_Msg_Flow
                 (FA        => FA,
                  Tracefile => Tracefile,
                  Msg       => "missing dependency ""null => #""",
                  N         => Depends_Location,
                  F1        => F_Out,
                  Tag       => "depends_null",
                  Warning   => True);
            end if;
         end;
      end loop;

      --  We go through the actual dependencies because they are
      --  always complete.

      for C in Actual_Deps.Iterate loop
         declare
            F_Out  : constant Flow_Id          := Dependency_Maps.Key (C);
            A_Deps : constant Flow_Id_Sets.Set := Dependency_Maps.Element (C);
            U_Deps : Flow_Id_Sets.Set;

            Missing_Deps : Ordered_Flow_Id_Sets.Set;
            Wrong_Deps   : Ordered_Flow_Id_Sets.Set;

            Proceed_With_Analysis : Boolean := True;
         begin
            if F_Out = Null_Flow_Id then
               --  The null dependency is special: it may not be
               --  present in the user dependency because null => null
               --  would be super tedious to write.
               if User_Deps.Contains (Null_Flow_Id) then
                  U_Deps := User_Deps (Null_Flow_Id);
               else
                  U_Deps := Flow_Id_Sets.Empty_Set;
               end if;
            elsif User_Deps.Contains (F_Out) then
               U_Deps := User_Deps (F_Out);
            elsif F_Out.Kind = Magic_String then
               Global_Required (FA, F_Out);
               Proceed_With_Analysis := False;
            else
               --  ??? legality error, should be moved to frontend;
               --  ??? possibly raise exception here
               Error_Msg_Flow
                 (FA        => FA,
                  Tracefile => Tracefile,
                  Msg       => "expected to see & on the left-hand-side of" &
                    " a dependency relation",
                  N         => Depends_Location,
                  F1        => F_Out,
                  Tag       => "depends_missing_clause",
                  Warning   => True);
               U_Deps := Flow_Id_Sets.Empty_Set;
            end if;

            --  If we mention magic strings anywhere, there is no
            --  point in proceeding as the dependency relation
            --  *cannot* be correct.

            if Proceed_With_Analysis then
               for Var of A_Deps loop
                  if Var.Kind = Magic_String then
                     Global_Required (FA, Var);
                     Proceed_With_Analysis := False;
                  end if;
               end loop;
            end if;

            --  If all is still well we now do a consistency check.

            if Proceed_With_Analysis then
               Missing_Deps := To_Ordered_Flow_Id_Set (A_Deps - U_Deps);
               Wrong_Deps   := To_Ordered_Flow_Id_Set (U_Deps - A_Deps);

               for Missing_Var of Missing_Deps loop
                  --  Something that the user dependency fails to
                  --  mention.
                  if F_Out = Null_Flow_Id then
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "missing dependency ""null => #""",
                        N         => Depends_Location,
                        F1        => Missing_Var,
                        Tag       => "depends_null",
                        Warning   => True);
                  else
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "missing dependency ""# => #""",
                        N         => Find_Export
                          (Get_Direct_Mapping_Id (F_Out)),
                        F1        => F_Out,
                        F2        => Missing_Var,
                        Tag       => "depends_missing",
                        Warning   => True);
                     --  ??? show path
                  end if;
               end loop;

               for Wrong_Var of Wrong_Deps loop
                  --  Something the user dependency claims, but does
                  --  not happen in reality.
                  if F_Out = Null_Flow_Id then
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "incorrect dependency ""null => #""",
                        N         => Depends_Location,
                        F1        => Wrong_Var,
                        Tag       => "depends_wrong",
                        Warning   => True);
                     --  ??? show a path?
                  else
                     Error_Msg_Flow
                       (FA        => FA,
                        Tracefile => Tracefile,
                        Msg       => "incorrect dependency ""# => #""",
                        N         => Find_Export
                          (Get_Direct_Mapping_Id (F_Out)),
                        F1        => F_Out,
                        F2        => Wrong_Var,
                        Tag       => "depends_wrong",
                        Warning   => True);
                  end if;
               end loop;

            end if;

         end;
      end loop;
   end Check_Contracts;

end Flow.Analysis;
