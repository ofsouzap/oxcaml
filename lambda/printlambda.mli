(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

open Lambda

open Format

val integer_comparison: formatter -> integer_comparison -> unit
val float_comparison: float_comparison -> string
val structured_constant: formatter -> structured_constant -> unit
val lambda: formatter -> lambda -> unit
val lfunction : formatter -> lfunction -> unit
val program: formatter -> program -> unit
val primitive: formatter -> primitive -> unit
val name_of_primitive : primitive -> string
val variant_kind : (formatter -> value_kind -> unit) ->
  formatter -> consts:int list -> non_consts:(int * constructor_shape) list ->
  unit
val value_kind : formatter -> value_kind -> unit
val layout : formatter -> layout -> unit
val block_shape : formatter -> value_kind list option -> unit
val record_rep : formatter -> Types.record_representation -> unit
val print_bigarray :
  string -> bool -> Lambda.bigarray_kind -> formatter ->
  Lambda.bigarray_layout -> unit
val zero_alloc_attribute : formatter -> zero_alloc_attribute -> unit
val locality_mode : formatter -> locality_mode -> unit
val array_kind : array_kind -> string
val array_set_kind : formatter -> array_set_kind -> unit

val tag_and_constructor_shape :
  (formatter -> value_kind -> unit) ->
  formatter -> int * constructor_shape -> unit
