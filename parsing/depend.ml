(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1999 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open Asttypes
open Location
open Longident
open Parsetree
module String = Misc.Stdlib.String

let pp_deps = ref []

(* Module resolution map *)
(* Node (set of imports for this path, map for submodules) *)
type map_tree = Node of String.Set.t * bound_map
and  bound_map = map_tree String.Map.t
let bound = Node (String.Set.empty, String.Map.empty)

(*let get_free (Node (s, _m)) = s*)
let get_map (Node (_s, m)) = m
let make_leaf s = Node (String.Set.singleton s, String.Map.empty)
let make_node m =  Node (String.Set.empty, m)
let rec weaken_map s (Node(s0,m0)) =
  Node (String.Set.union s s0, String.Map.map (weaken_map s) m0)
let rec collect_free (Node (s, m)) =
  String.Map.fold (fun _ n -> String.Set.union (collect_free n)) m s

(* Returns the imports required to access the structure at path p *)
(* Only raises Not_found if the head of p is not in the toplevel map *)
let rec lookup_free p m =
  match p with
    [] -> raise Not_found
  | s::p ->
      let Node (f, m') = String.Map.find s m  in
      try lookup_free p m' with Not_found -> f

(* Returns the node corresponding to the structure at path p *)
let rec lookup_map lid m =
  match lid with
    Lident s    -> String.Map.find s m
  | Ldot (l, s) -> String.Map.find s (get_map (lookup_map l m))
  | Lapply _    -> raise Not_found

let free_structure_names = ref String.Set.empty

let add_names s =
  free_structure_names := String.Set.union s !free_structure_names

let rec add_path bv ?(p=[]) = function
  | Lident s ->
      let free =
        try lookup_free (s::p) bv with Not_found -> String.Set.singleton s
      in
      (*String.Set.iter (fun s -> Printf.eprintf "%s " s) free;
        prerr_endline "";*)
      add_names free
  | Ldot(l, s) -> add_path bv ~p:(s::p) l
  | Lapply(l1, l2) -> add_path bv l1; add_path bv l2

let open_module bv lid =
  match lookup_map lid bv with
  | Node (s, m) ->
      add_names s;
      String.Map.fold String.Map.add m bv
  | exception Not_found ->
      add_path bv lid; bv

let add_parent bv lid =
  match lid.txt with
    Ldot(l, _s) -> add_path bv l
  | _ -> ()

let add = add_parent

let add_module_path bv lid = add_path bv lid.txt

let handle_extension ext =
  match (fst ext).txt with
  | "error" | "ocaml.error" ->
    raise (Location.Error
             (Builtin_attributes.error_of_extension ext))
  | _ ->
    ()

let rec add_type bv ty =
  match ty.ptyp_desc with
    Ptyp_any jkind
  | Ptyp_var (_, jkind) -> Option.iter (add_jkind bv) jkind
  | Ptyp_arrow(_, t1, t2, _, _) -> add_type bv t1; add_type bv t2
  | Ptyp_tuple tl -> add_type_labeled_tuple bv tl
  | Ptyp_unboxed_tuple tl -> add_type_labeled_tuple bv tl
  | Ptyp_constr(c, tl) -> add bv c; List.iter (add_type bv) tl
  | Ptyp_object (fl, _) ->
      List.iter
       (fun {pof_desc; _} -> match pof_desc with
         | Otag (_, t) -> add_type bv t
         | Oinherit t -> add_type bv t) fl
  | Ptyp_class(c, tl) -> add bv c; List.iter (add_type bv) tl
  | Ptyp_alias(t, _, jkind) ->
      add_type bv t;
      Option.iter (add_jkind bv) jkind
  | Ptyp_variant(fl, _, _) ->
      List.iter
        (fun {prf_desc; _} -> match prf_desc with
          | Rtag(_, _, stl) -> List.iter (add_type bv) stl
          | Rinherit sty -> add_type bv sty)
        fl
  | Ptyp_poly(bound_vars, t) ->
      add_vars_jkinds bv bound_vars;
      add_type bv t
  | Ptyp_package pt -> add_package_type bv pt
  | Ptyp_open (mod_ident, t) ->
    let bv = open_module bv mod_ident.txt in
    add_type bv t
  | Ptyp_of_kind jkind -> add_jkind bv jkind
  | Ptyp_extension e -> handle_extension e

and add_type_labeled_tuple bv tl =
  List.iter (fun (_, ty) -> add_type bv ty) tl

and add_package_type bv (lid, l) =
  add bv lid;
  List.iter (add_type bv) (List.map (fun (_, e) -> e) l)

(* CR layouts: Remember to add this when jkinds can have module
   prefixes. *)
and add_jkind bv (jkind : jkind_annotation) =
  match jkind.pjkind_desc with
  | Default -> ()
  | Abbreviation _ -> ()
  | Mod (jkind, (_ : modes)) -> add_jkind bv jkind
  | With (jkind, typ, (_ : modalities)) ->
      add_jkind bv jkind;
      add_type bv typ;
  | Kind_of typ ->
      add_type bv typ
  | Product jkinds ->
      List.iter (fun jkind -> add_jkind bv jkind) jkinds

and add_vars_jkinds bv vars_jkinds =
  let add_one (_, jkind) = Option.iter (add_jkind bv) jkind in
  List.iter add_one vars_jkinds

let add_opt add_fn bv = function
    None -> ()
  | Some x -> add_fn bv x

let add_constructor_arguments bv = function
  | Pcstr_tuple l -> List.iter (fun a -> add_type bv a.pca_type) l
  | Pcstr_record l -> List.iter (fun l -> add_type bv l.pld_type) l

let add_constructor_decl bv pcd =
  add_constructor_arguments bv pcd.pcd_args;
  Option.iter (add_type bv) pcd.pcd_res

let add_type_declaration bv td =
  List.iter
    (fun (ty1, ty2, _) -> add_type bv ty1; add_type bv ty2)
    td.ptype_cstrs;
  add_opt add_type bv td.ptype_manifest;
  let add_tkind = function
    Ptype_abstract -> ()
  | Ptype_variant cstrs ->
      List.iter (add_constructor_decl bv) cstrs
  | Ptype_record lbls ->
      List.iter (fun pld -> add_type bv pld.pld_type) lbls
  | Ptype_record_unboxed_product lbls ->
      List.iter (fun pld -> add_type bv pld.pld_type) lbls
  | Ptype_open -> () in
  add_tkind td.ptype_kind

let add_extension_constructor bv ext =
  match ext.pext_kind with
    Pext_decl(vars_jkinds, args, rty) ->
      add_vars_jkinds bv vars_jkinds;
      add_constructor_arguments bv args;
      Option.iter (add_type bv) rty
  | Pext_rebind lid -> add bv lid

let add_type_extension bv te =
  add bv te.ptyext_path;
  List.iter (add_extension_constructor bv) te.ptyext_constructors

let add_type_exception bv te =
  add_extension_constructor bv te.ptyexn_constructor

let pattern_bv = ref String.Map.empty

let rec add_pattern bv pat =
  match pat.ppat_desc with
    Ppat_any -> ()
  | Ppat_var _ -> ()
  | Ppat_alias(p, _) -> add_pattern bv p
  | Ppat_interval _
  | Ppat_constant _ -> ()
  | Ppat_tuple (pl, _) -> add_pattern_labeled_tuple bv pl
  | Ppat_unboxed_tuple (pl, _)-> add_pattern_labeled_tuple bv pl
  | Ppat_construct(c, opt) ->
      add bv c;
      add_opt
        (fun bv (_,p) -> add_pattern bv p)
        bv opt
  | Ppat_record(pl, _) | Ppat_record_unboxed_product(pl, _) ->
      List.iter (fun (lbl, p) -> add bv lbl; add_pattern bv p) pl
  | Ppat_array (_, pl) -> List.iter (add_pattern bv) pl
  | Ppat_or(p1, p2) -> add_pattern bv p1; add_pattern bv p2
  | Ppat_constraint(p, ty, _) ->
      add_pattern bv p;
      Option.iter (fun ty -> add_type bv ty) ty;
  | Ppat_variant(_, op) -> add_opt add_pattern bv op
  | Ppat_type li -> add bv li
  | Ppat_lazy p -> add_pattern bv p
  | Ppat_unpack id ->
      Option.iter
        (fun name -> pattern_bv := String.Map.add name bound !pattern_bv) id.txt
  | Ppat_open ( m, p) -> let bv = open_module bv m.txt in add_pattern bv p
  | Ppat_exception p -> add_pattern bv p
  | Ppat_extension e -> handle_extension e

and add_pattern_labeled_tuple bv labeled_pl =
  List.iter (fun (_, p) -> add_pattern bv p) labeled_pl

let add_pattern bv pat =
  pattern_bv := bv;
  add_pattern bv pat;
  !pattern_bv

let rec add_expr bv exp =
  match exp.pexp_desc with
    Pexp_ident l -> add bv l
  | Pexp_constant _ -> ()
  | Pexp_let(_mf, rf, pel, e) ->
      let bv = add_bindings rf bv pel in add_expr bv e
  | Pexp_function (params, constraint_, body) ->
      let bv = List.fold_left add_function_param bv params in
      add_function_constraint bv constraint_;
      add_function_body bv body
  | Pexp_apply(e, el) ->
      add_expr bv e; List.iter (fun (_,e) -> add_expr bv e) el
  | Pexp_match(e, pel) -> add_expr bv e; add_cases bv pel
  | Pexp_try(e, pel) -> add_expr bv e; add_cases bv pel
  | Pexp_tuple el -> add_labeled_tuple_expr bv el
  | Pexp_unboxed_tuple el -> add_labeled_tuple_expr bv el
  | Pexp_construct(c, opte) -> add bv c; add_opt add_expr bv opte
  | Pexp_variant(_, opte) -> add_opt add_expr bv opte
  | Pexp_record(lblel, opte)
  | Pexp_record_unboxed_product(lblel, opte) ->
      List.iter (fun (lbl, e) -> add bv lbl; add_expr bv e) lblel;
      add_opt add_expr bv opte
  | Pexp_field(e, fld) | Pexp_unboxed_field(e, fld) -> add_expr bv e; add bv fld
  | Pexp_setfield(e1, fld, e2) -> add_expr bv e1; add bv fld; add_expr bv e2
  | Pexp_array (_, el) -> List.iter (add_expr bv) el
  | Pexp_ifthenelse(e1, e2, opte3) ->
      add_expr bv e1; add_expr bv e2; add_opt add_expr bv opte3
  | Pexp_sequence(e1, e2) -> add_expr bv e1; add_expr bv e2
  | Pexp_while(e1, e2) -> add_expr bv e1; add_expr bv e2
  | Pexp_for( _, e1, e2, _, e3) ->
      add_expr bv e1; add_expr bv e2; add_expr bv e3
  | Pexp_coerce(e1, oty2, ty3) ->
      add_expr bv e1;
      add_opt add_type bv oty2;
      add_type bv ty3
  | Pexp_constraint(e1, ty2, _) ->
      add_expr bv e1;
      Option.iter (add_type bv) ty2
  | Pexp_send(e, _m) -> add_expr bv e
  | Pexp_new li -> add bv li
  | Pexp_setvar(_v, e) -> add_expr bv e
  | Pexp_override sel -> List.iter (fun (_s, e) -> add_expr bv e) sel
  | Pexp_letmodule(id, m, e) ->
      let b = add_module_binding bv m in
      let bv =
        match id.txt with
        | None -> bv
        | Some id -> String.Map.add id b bv
      in
      add_expr bv e
  | Pexp_letexception(_, e) -> add_expr bv e
  | Pexp_assert (e) -> add_expr bv e
  | Pexp_lazy (e) -> add_expr bv e
  | Pexp_poly (e, t) -> add_expr bv e; add_opt add_type bv t
  | Pexp_object { pcstr_self = pat; pcstr_fields = fieldl } ->
      let bv = add_pattern bv pat in List.iter (add_class_field bv) fieldl
  | Pexp_newtype (_, jkind, e) ->
      Option.iter (add_jkind bv) jkind;
      add_expr bv e
  | Pexp_pack m -> add_module_expr bv m
  | Pexp_open (o, e) ->
      let bv = open_declaration bv o in
      add_expr bv e
  | Pexp_letop {let_; ands; body} ->
      let bv' = add_binding_op bv bv let_ in
      let bv' = List.fold_left (add_binding_op bv) bv' ands in
      add_expr bv' body
  | Pexp_extension (({ txt = ("ocaml.extension_constructor"|
                              "extension_constructor"); _ },
                     PStr [item]) as e) ->
      begin match item.pstr_desc with
      | Pstr_eval ({ pexp_desc = Pexp_construct (c, None) }, _) -> add bv c
      | _ -> handle_extension e
      end
  | Pexp_extension (({ txt = ("probe"|"ocaml.probe"); _ }, payload) as e) ->
      begin match Builtin_attributes.get_tracing_probe_payload payload with
      | Error () -> handle_extension e
      | Ok { arg; _ } -> add_expr bv arg
      end
  | Pexp_extension e -> handle_extension e
  | Pexp_stack e -> add_expr bv e
  | Pexp_overwrite (e1, e2) -> add_expr bv e1; add_expr bv e2
  | Pexp_hole -> ()
  | Pexp_unreachable -> ()
  | Pexp_comprehension x -> add_comprehension_expr bv x

and add_comprehension_expr bv = function
  | Pcomp_list_comprehension comp -> add_comprehension bv comp
  | Pcomp_array_comprehension (_, comp) -> add_comprehension bv comp

and add_comprehension bv { pcomp_body; pcomp_clauses } =
  let bv = List.fold_left add_comprehension_clause bv pcomp_clauses in
  add_expr bv pcomp_body

and add_comprehension_clause bv = function
    (* fold_left here is a little suspicious, because the different
       clauses should be interpreted in parallel. But this treatment
       echoes the treatment in [Pexp_let] (in [add_bindings]). *)
  | Pcomp_for cbs -> List.fold_left add_comprehension_clause_binding bv cbs
  | Pcomp_when expr -> add_expr bv expr; bv

and add_comprehension_clause_binding bv
      { pcomp_cb_pattern; pcomp_cb_iterator; pcomp_cb_attributes = _ } =
  let bv = add_pattern bv pcomp_cb_pattern in
  add_comprehension_iterator bv pcomp_cb_iterator;
  bv

and add_comprehension_iterator bv = function
  | Pcomp_range { start; stop; direction = _ } ->
    add_expr bv start;
    add_expr bv stop
  | Pcomp_in expr ->
    add_expr bv expr

and add_labeled_tuple_expr bv el = List.iter (add_expr bv) (List.map snd el)

and add_function_param bv param =
  match param.pparam_desc with
  | Pparam_val (_, opte, pat) ->
      add_opt add_expr bv opte;
      add_pattern bv pat
  | Pparam_newtype _ -> bv

and add_function_body bv body =
  match body with
  | Pfunction_body e ->
      add_expr bv e
  | Pfunction_cases (cases, _, _) ->
      add_cases bv cases

and add_function_constraint bv { mode_annotations = _; ret_type_constraint; ret_mode_annotations = _ } =
  match ret_type_constraint with
  | Some (Pconstraint ty) ->
      add_type bv ty
  | Some (Pcoerce (ty1, ty2)) ->
      add_opt add_type bv ty1;
      add_type bv ty2
  | None -> ()

and add_cases bv cases =
  List.iter (add_case bv) cases

and add_case bv {pc_lhs; pc_guard; pc_rhs} =
  let bv = add_pattern bv pc_lhs in
  add_opt add_expr bv pc_guard;
  add_expr bv pc_rhs

and add_bindings recf bv pel =
  let bv' = List.fold_left (fun bv x -> add_pattern bv x.pvb_pat) bv pel in
  let bv = if recf = Recursive then bv' else bv in
  let add_constraint = function
    | Pvc_constraint {locally_abstract_univars=_; typ} ->
        add_type bv typ
    | Pvc_coercion { ground; coercion } ->
        Option.iter (add_type bv) ground;
        add_type bv coercion
  in
  let add_one_binding { pvb_pat= _ ; pvb_loc= _ ; pvb_constraint; pvb_expr } =
    add_expr bv pvb_expr;
    Option.iter add_constraint pvb_constraint
  in
  List.iter add_one_binding pel;
  bv'

and add_binding_op bv bv' pbop =
  add_expr bv pbop.pbop_exp;
  add_pattern bv' pbop.pbop_pat

and add_modtype bv mty =
  match mty.pmty_desc with
    Pmty_ident l -> add bv l
  | Pmty_alias l -> add_module_path bv l
  | Pmty_signature s -> add_signature bv s
  | Pmty_functor(param, mty2, _) ->
      let bv =
        match param with
        | Unit -> bv
        | Named (id, mty1, _) ->
          add_modtype bv mty1;
          match id.txt with
          | None -> bv
          | Some name -> String.Map.add name bound bv
      in
      add_modtype bv mty2
  | Pmty_with(mty, cstrl) ->
      add_modtype bv mty;
      List.iter
        (function
          | Pwith_type (_, td) -> add_type_declaration bv td
          | Pwith_module (_, lid) -> add_module_path bv lid
          | Pwith_modtype (_, mty) -> add_modtype bv mty
          | Pwith_typesubst (_, td) -> add_type_declaration bv td
          | Pwith_modsubst (_, lid) -> add_module_path bv lid
          | Pwith_modtypesubst (_, mty) -> add_modtype bv mty
        )
        cstrl
  | Pmty_typeof m -> add_module_expr bv m
  | Pmty_extension e -> handle_extension e
  | Pmty_strengthen (mty, mod_id) ->
      add_modtype bv mty;
      add_module_path bv mod_id

and add_module_alias bv l =
  (* If we are in delayed dependencies mode, we delay the dependencies
       induced by "Lident s" *)
  (if !Clflags.transparent_modules then add_parent else add_module_path) bv l;
  try
    lookup_map l.txt bv
  with Not_found ->
    match l.txt with
      Lident s -> make_leaf s
    | _ -> add_module_path bv l; bound (* cannot delay *)

and add_modtype_binding bv mty =
  match mty.pmty_desc with
    Pmty_alias l ->
      add_module_alias bv l
  | Pmty_signature s ->
      make_node (add_signature_binding bv s)
  | Pmty_typeof modl ->
      add_module_binding bv modl
  | Pmty_strengthen (mty, mod_id) ->
      (* treat like a [with] constraint *)
      add_modtype bv mty;
      add_module_path bv mod_id;
      bound
  | _ ->
      add_modtype bv mty; bound

and add_signature bv sg =
  ignore (add_signature_binding bv sg)

and add_signature_binding bv sg =
  snd (List.fold_left add_sig_item (bv, String.Map.empty) sg.psg_items)

(* When we merge [include functor] upstream this can get re-inlined *)
and add_include_description (bv, m) incl =
  let Node (s, m') = add_modtype_binding bv incl.pincl_mod in
  add_names s;
  let add = String.Map.fold String.Map.add m' in
  (add bv, add m)

and add_sig_item (bv, m) item =
  match item.psig_desc with
    Psig_value vd ->
      add_type bv vd.pval_type; (bv, m)
  | Psig_type (_, dcls)
  | Psig_typesubst dcls->
      List.iter (add_type_declaration bv) dcls; (bv, m)
  | Psig_typext te ->
      add_type_extension bv te; (bv, m)
  | Psig_exception te ->
      add_type_exception bv te; (bv, m)
  | Psig_module pmd ->
      let m' = add_modtype_binding bv pmd.pmd_type in
      let add map =
        match pmd.pmd_name.txt with
        | None -> map
        | Some name -> String.Map.add name m' map
      in
      (add bv, add m)
  | Psig_modsubst pms ->
      let m' = add_module_alias bv pms.pms_manifest in
      let add = String.Map.add pms.pms_name.txt m' in
      (add bv, add m)
  | Psig_recmodule decls ->
      let add =
        List.fold_right (fun pmd map ->
          match pmd.pmd_name.txt with
          | None -> map
          | Some name -> String.Map.add name bound map
        ) decls
      in
      let bv' = add bv and m' = add m in
      List.iter (fun pmd -> add_modtype bv' pmd.pmd_type) decls;
      (bv', m')
  | Psig_modtype x | Psig_modtypesubst x->
      begin match x.pmtd_type with
        None -> ()
      | Some mty -> add_modtype bv mty
      end;
      (bv, m)
  | Psig_open od ->
      (open_description bv od, m)
  | Psig_include (incl, _) ->
      add_include_description (bv, m) incl
  | Psig_class cdl ->
      List.iter (add_class_description bv) cdl; (bv, m)
  | Psig_class_type cdtl ->
      List.iter (add_class_type_declaration bv) cdtl; (bv, m)
  | Psig_attribute _ -> (bv, m)
  | Psig_extension (e, _) ->
      handle_extension e;
      (bv, m)
  | Psig_kind_abbrev (_, jkind) ->
      add_jkind bv jkind; (bv, m)

and open_description bv od =
  let Node(s, m) = add_module_alias bv od.popen_expr in
  add_names s;
  String.Map.fold String.Map.add m bv

and open_declaration bv od =
  let Node (s, m) = add_module_binding bv od.popen_expr in
  add_names s;
  String.Map.fold String.Map.add m bv

and add_module_binding bv modl =
  match modl.pmod_desc with
    Pmod_ident l -> add_module_alias bv l
  | Pmod_structure s ->
     make_node (snd @@ add_structure_binding bv s)
  | _ -> add_module_expr bv modl; bound

and add_module_expr bv modl =
  match modl.pmod_desc with
    Pmod_ident l -> add_module_path bv l
  | Pmod_structure s -> ignore (add_structure bv s)
  | Pmod_functor(param, modl) ->
      let bv =
        match param with
        | Unit -> bv
        | Named (id, mty, _) ->
          add_modtype bv mty;
          match id.txt with
          | None -> bv
          | Some name -> String.Map.add name bound bv
      in
      add_module_expr bv modl
  | Pmod_apply (mod1, mod2) ->
      add_module_expr bv mod1;
      add_module_expr bv mod2
  | Pmod_apply_unit mod1 ->
      add_module_expr bv mod1
  | Pmod_constraint(modl, mty, _) ->
      add_module_expr bv modl; Option.iter (add_modtype bv) mty
  | Pmod_unpack(e) ->
      add_expr bv e
  | Pmod_extension e ->
      handle_extension e
  | Pmod_instance instance ->
      add_instance bv instance

and add_instance bv { pmod_instance_head; pmod_instance_args } =
  add_path bv (Lident pmod_instance_head);
  List.iter (fun (name, arg) ->
      add_path bv (Lident name);
      add_instance bv arg)
    pmod_instance_args

and add_class_type bv cty =
  match cty.pcty_desc with
    Pcty_constr(l, tyl) ->
      add bv l; List.iter (add_type bv) tyl
  | Pcty_signature { pcsig_self = ty; pcsig_fields = fieldl } ->
      add_type bv ty;
      List.iter (add_class_type_field bv) fieldl
  | Pcty_arrow(_, ty1, cty2) ->
      add_type bv ty1; add_class_type bv cty2
  | Pcty_extension e -> handle_extension e
  | Pcty_open (o, e) ->
      let bv = open_description bv o in
      add_class_type bv e

and add_class_type_field bv pctf =
  match pctf.pctf_desc with
    Pctf_inherit cty -> add_class_type bv cty
  | Pctf_val(_, _, _, ty) -> add_type bv ty
  | Pctf_method(_, _, _, ty) -> add_type bv ty
  | Pctf_constraint(ty1, ty2) -> add_type bv ty1; add_type bv ty2
  | Pctf_attribute _ -> ()
  | Pctf_extension e -> handle_extension e

and add_class_description bv infos =
  add_class_type bv infos.pci_expr

and add_class_type_declaration bv infos = add_class_description bv infos

and add_structure bv item_list =
  let (bv, m) = add_structure_binding bv item_list in
  add_names (collect_free (make_node m));
  bv

and add_structure_binding bv item_list =
  List.fold_left add_struct_item (bv, String.Map.empty) item_list

(* When we merge [include functor] upstream this can get re-inlined *)
and add_include_declaration (bv, m) incl =
  let Node (s, m') as n = add_module_binding bv incl.pincl_mod in
  if !Clflags.transparent_modules then
    add_names s
  else
    (* If we are not in the delayed dependency mode, we need to
       collect all delayed dependencies imported by the include statement *)
    add_names (collect_free n);
  let add = String.Map.fold String.Map.add m' in
  (add bv, add m)

and add_struct_item (bv, m) item : _ String.Map.t * _ String.Map.t =
  match item.pstr_desc with
    Pstr_eval (e, _attrs) ->
      add_expr bv e; (bv, m)
  | Pstr_value(rf, pel) ->
      let bv = add_bindings rf bv pel in (bv, m)
  | Pstr_primitive vd ->
      add_type bv vd.pval_type; (bv, m)
  | Pstr_type (_, dcls) ->
      List.iter (add_type_declaration bv) dcls; (bv, m)
  | Pstr_typext te ->
      add_type_extension bv te;
      (bv, m)
  | Pstr_exception te ->
      add_type_exception bv te;
      (bv, m)
  | Pstr_module x ->
      let b = add_module_binding bv x.pmb_expr in
      let add map =
        match x.pmb_name.txt with
        | None -> map
        | Some name -> String.Map.add name b map
      in
      (add bv, add m)
  | Pstr_recmodule bindings ->
      let add =
        List.fold_right (fun x map ->
          match x.pmb_name.txt with
          | None -> map
          | Some name -> String.Map.add name bound map
        ) bindings
      in
      let bv' = add bv and m = add m in
      List.iter
        (fun x -> add_module_expr bv' x.pmb_expr)
        bindings;
      (bv', m)
  | Pstr_modtype x ->
      begin match x.pmtd_type with
        None -> ()
      | Some mty -> add_modtype bv mty
      end;
      (bv, m)
  | Pstr_open od ->
      (open_declaration bv od, m)
  | Pstr_class cdl ->
      List.iter (add_class_declaration bv) cdl; (bv, m)
  | Pstr_class_type cdtl ->
      List.iter (add_class_type_declaration bv) cdtl; (bv, m)
  | Pstr_include incl ->
      add_include_declaration (bv, m) incl
  | Pstr_attribute _ -> (bv, m)
  | Pstr_extension (e, _) ->
      handle_extension e;
      (bv, m)
  | Pstr_kind_abbrev (_name, jkind) ->
      add_jkind bv jkind; (bv, m)

and add_use_file bv top_phrs =
  ignore (List.fold_left add_top_phrase bv top_phrs)

and add_implementation bv l =
    ignore (add_structure_binding bv l)

and add_implementation_binding bv l =
  snd (add_structure_binding bv l)

and add_top_phrase bv = function
  | Ptop_def str -> add_structure bv str
  | Ptop_dir _ -> bv

and add_class_expr bv ce =
  match ce.pcl_desc with
    Pcl_constr(l, tyl) ->
      add bv l; List.iter (add_type bv) tyl
  | Pcl_structure { pcstr_self = pat; pcstr_fields = fieldl } ->
      let bv = add_pattern bv pat in List.iter (add_class_field bv) fieldl
  | Pcl_fun(_, opte, pat, ce) ->
      add_opt add_expr bv opte;
      let bv = add_pattern bv pat in add_class_expr bv ce
  | Pcl_apply(ce, exprl) ->
      add_class_expr bv ce; List.iter (fun (_,e) -> add_expr bv e) exprl
  | Pcl_let(rf, pel, ce) ->
      let bv = add_bindings rf bv pel in add_class_expr bv ce
  | Pcl_constraint(ce, ct) ->
      add_class_expr bv ce; add_class_type bv ct
  | Pcl_extension e -> handle_extension e
  | Pcl_open (o, e) ->
      let bv = open_description bv o in
      add_class_expr bv e

and add_class_field bv pcf =
  match pcf.pcf_desc with
    Pcf_inherit(_, ce, _) -> add_class_expr bv ce
  | Pcf_val(_, _, Cfk_concrete (_, e))
  | Pcf_method(_, _, Cfk_concrete (_, e)) -> add_expr bv e
  | Pcf_val(_, _, Cfk_virtual ty)
  | Pcf_method(_, _, Cfk_virtual ty) -> add_type bv ty
  | Pcf_constraint(ty1, ty2) -> add_type bv ty1; add_type bv ty2
  | Pcf_initializer e -> add_expr bv e
  | Pcf_attribute _ -> ()
  | Pcf_extension e -> handle_extension e

and add_class_declaration bv decl =
  add_class_expr bv decl.pci_expr
