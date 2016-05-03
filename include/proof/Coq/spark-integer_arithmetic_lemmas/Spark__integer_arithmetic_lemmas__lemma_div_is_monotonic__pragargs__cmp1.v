(* This file is generated by Why3's Coq driver *)
(* Beware! Only edit allowed sections below    *)
Require Import BuiltIn.
Require BuiltIn.
Require bool.Bool.
Require int.Int.
Require int.Abs.
Require int.EuclideanDivision.
Require int.ComputerDivision.

(* Why3 assumption *)
Definition unit := unit.

Axiom us_private : Type.
Parameter us_private_WhyType : WhyType us_private.
Existing Instance us_private_WhyType.

Parameter us_null_ext__: us_private.

(* Why3 assumption *)
Definition us_fixed := Z.

Axiom us_type_of_heap : Type.
Parameter us_type_of_heap_WhyType : WhyType us_type_of_heap.
Existing Instance us_type_of_heap_WhyType.

(* Why3 assumption *)
Inductive us_type_of_heap__ref :=
  | mk___type_of_heap__ref : us_type_of_heap -> us_type_of_heap__ref.
Axiom us_type_of_heap__ref_WhyType : WhyType us_type_of_heap__ref.
Existing Instance us_type_of_heap__ref_WhyType.

(* Why3 assumption *)
Definition us_type_of_heap__content
  (v:us_type_of_heap__ref): us_type_of_heap :=
  match v with
  | (mk___type_of_heap__ref x) => x
  end.

Axiom us_image : Type.
Parameter us_image_WhyType : WhyType us_image.
Existing Instance us_image_WhyType.

(* Why3 assumption *)
Inductive int__ref :=
  | mk_int__ref : Z -> int__ref.
Axiom int__ref_WhyType : WhyType int__ref.
Existing Instance int__ref_WhyType.

(* Why3 assumption *)
Definition int__content (v:int__ref): Z :=
  match v with
  | (mk_int__ref x) => x
  end.

(* Why3 assumption *)
Inductive bool__ref :=
  | mk_bool__ref : bool -> bool__ref.
Axiom bool__ref_WhyType : WhyType bool__ref.
Existing Instance bool__ref_WhyType.

(* Why3 assumption *)
Definition bool__content (v:bool__ref): bool :=
  match v with
  | (mk_bool__ref x) => x
  end.

(* Why3 assumption *)
Inductive real__ref :=
  | mk_real__ref : R -> real__ref.
Axiom real__ref_WhyType : WhyType real__ref.
Existing Instance real__ref_WhyType.

(* Why3 assumption *)
Definition real__content (v:real__ref): R :=
  match v with
  | (mk_real__ref x) => x
  end.

(* Why3 assumption *)
Inductive us_private__ref :=
  | mk___private__ref : us_private -> us_private__ref.
Axiom us_private__ref_WhyType : WhyType us_private__ref.
Existing Instance us_private__ref_WhyType.

(* Why3 assumption *)
Definition us_private__content (v:us_private__ref): us_private :=
  match v with
  | (mk___private__ref x) => x
  end.

(* Why3 assumption *)
Definition int__ref___projection (a:int__ref): Z := (int__content a).

(* Why3 assumption *)
Definition bool__ref___projection (a:bool__ref): bool := (bool__content a).

(* Why3 assumption *)
Definition real__ref___projection (a:real__ref): R := (real__content a).

(* Why3 assumption *)
Definition us_private__ref___projection (a:us_private__ref): us_private :=
  (us_private__content a).

Parameter us_compatible_tags: Z -> Z -> Prop.

Axiom us_compatible_tags_refl : forall (tag:Z), (us_compatible_tags tag tag).

Axiom int__ : Type.
Parameter int___WhyType : WhyType int__.
Existing Instance int___WhyType.

(* Why3 assumption *)
Definition in_range (x:Z): Prop :=
  ((-2147483648%Z)%Z <= x)%Z /\ (x <= 2147483647%Z)%Z.

Parameter bool_eq: Z -> Z -> bool.

Parameter bool_ne: Z -> Z -> bool.

Parameter bool_lt: Z -> Z -> bool.

Parameter bool_le: Z -> Z -> bool.

Parameter bool_gt: Z -> Z -> bool.

Parameter bool_ge: Z -> Z -> bool.

Axiom bool_eq_axiom : forall (x:Z),
                       forall (y:Z), ((bool_eq x y) = true) <-> (x = y).

Axiom bool_ne_axiom : forall (x:Z),
                       forall (y:Z), ((bool_ne x y) = true) <-> ~ (x = y).

Axiom bool_lt_axiom : forall (x:Z),
                       forall (y:Z), ((bool_lt x y) = true) <-> (x < y)%Z.

Axiom bool_int__le_axiom : forall (x:Z),
                            forall (y:Z),
                             ((bool_le x y) = true) <-> (x <= y)%Z.

Axiom bool_gt_axiom : forall (x:Z),
                       forall (y:Z), ((bool_gt x y) = true) <-> (y < x)%Z.

Axiom bool_ge_axiom : forall (x:Z),
                       forall (y:Z), ((bool_ge x y) = true) <-> (y <= x)%Z.

Parameter bool_eq1: Z -> Z -> bool.

Axiom bool_eq_def : forall (x:Z) (y:Z),
                     ((x = y) -> ((bool_eq1 x y) = true))
                     /\ ((~ (x = y)) -> ((bool_eq1 x y) = false)).

Parameter attr__ATTRIBUTE_IMAGE: Z -> us_image.

Parameter attr__ATTRIBUTE_VALUE__pre_check: us_image -> Prop.

Parameter attr__ATTRIBUTE_VALUE: us_image -> Z.

Parameter to_rep: int__ -> Z.

Parameter of_rep: Z -> int__.

Parameter user_eq: int__ -> int__ -> bool.

Parameter dummy: int__.

Axiom inversion_axiom : forall (x:int__), ((of_rep (to_rep x)) = x).

Axiom range_axiom : forall (x:int__), (in_range (to_rep x)).

Axiom coerce_axiom : forall (x:Z), (in_range x) -> ((to_rep (of_rep x)) = x).

(* Why3 assumption *)
Inductive int____ref :=
  | mk_int____ref : int__ -> int____ref.
Axiom int____ref_WhyType : WhyType int____ref.
Existing Instance int____ref_WhyType.

(* Why3 assumption *)
Definition int____content (v:int____ref): int__ :=
  match v with
  | (mk_int____ref x) => x
  end.

(* Why3 assumption *)
Definition int____ref___projection (a:int____ref): int__ :=
  (int____content a).

(* Why3 assumption *)
Definition dynamic_invariant (temp___expr_144:Z) (temp___is_init_141:bool)
  (temp___do_constant_142:bool) (temp___do_toplevel_143:bool): Prop :=
  ((temp___is_init_141 = true) \/ ((-2147483648%Z)%Z <= 2147483647%Z)%Z) ->
  (in_range temp___expr_144).

Axiom pos : Type.
Parameter pos_WhyType : WhyType pos.
Existing Instance pos_WhyType.

(* Why3 assumption *)
Definition in_range1 (x:Z): Prop := (1%Z <= x)%Z /\ (x <= 2147483647%Z)%Z.

Parameter bool_eq2: Z -> Z -> bool.

Axiom bool_eq_def1 : forall (x:Z) (y:Z),
                      ((x = y) -> ((bool_eq2 x y) = true))
                      /\ ((~ (x = y)) -> ((bool_eq2 x y) = false)).

Parameter attr__ATTRIBUTE_IMAGE1: Z -> us_image.

Parameter attr__ATTRIBUTE_VALUE__pre_check1: us_image -> Prop.

Parameter attr__ATTRIBUTE_VALUE1: us_image -> Z.

Parameter to_rep1: pos -> Z.

Parameter of_rep1: Z -> pos.

Parameter user_eq1: pos -> pos -> bool.

Parameter dummy1: pos.

Axiom inversion_axiom1 : forall (x:pos), ((of_rep1 (to_rep1 x)) = x).

Axiom range_axiom1 : forall (x:pos), (in_range1 (to_rep1 x)).

Axiom coerce_axiom1 : forall (x:Z),
                       (in_range1 x) -> ((to_rep1 (of_rep1 x)) = x).

(* Why3 assumption *)
Inductive pos__ref :=
  | mk_pos__ref : pos -> pos__ref.
Axiom pos__ref_WhyType : WhyType pos__ref.
Existing Instance pos__ref_WhyType.

(* Why3 assumption *)
Definition pos__content (v:pos__ref): pos :=
  match v with
  | (mk_pos__ref x) => x
  end.

(* Why3 assumption *)
Definition pos__ref___projection (a:pos__ref): pos := (pos__content a).

(* Why3 assumption *)
Definition dynamic_invariant1 (temp___expr_156:Z) (temp___is_init_153:bool)
  (temp___do_constant_154:bool) (temp___do_toplevel_155:bool): Prop :=
  ((temp___is_init_153 = true) \/ (1%Z <= 2147483647%Z)%Z) -> (in_range1
  temp___expr_156).

Parameter val1: Z.

Parameter attr__ATTRIBUTE_ADDRESS: Z.

Parameter val2: Z.

Parameter attr__ATTRIBUTE_ADDRESS1: Z.

Parameter denom: Z.

Parameter attr__ATTRIBUTE_ADDRESS2: Z.

Parameter res1: Z.

Parameter attr__ATTRIBUTE_ADDRESS3: Z.

Parameter res2: Z.

Parameter attr__ATTRIBUTE_ADDRESS4: Z.

(* Why3 goal *)
Theorem WP_parameter_def : ((in_range val1)
                            /\ ((in_range val2)
                                /\ ((in_range1 denom)
                                    /\ ((in_range res1)
                                        /\ ((in_range res2)
                                            /\ ((val1 <= val2)%Z
                                                /\ ((res1 = (ZArith.BinInt.Z.quot val1 denom))
                                                    /\ (res2 = (ZArith.BinInt.Z.quot val2 denom))))))))) ->
                           (*      Post => Res1 <= Res2;                                                                                             *)
                           (*              ^ spark-arithmetic_lemmas.ads:35:14:instantiated:spark-integer_arithmetic_lemmas.ads:3:1:VC_POSTCONDITION *)
                           (res1 <= res2)%Z.
(* Why3 intros (h1,(h2,(h3,(h4,(h5,(h6,(h7,h8))))))). *)
intros (h1,(h2,(h3,(h4,(h5,(h6,(h7,h8))))))).
rewrite h7,h8.
apply Z.quot_le_mono.
unfold in_range1 in h3.
auto with zarith.
auto with zarith.
Qed.
