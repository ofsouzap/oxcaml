(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*          Fabrice Le Fessant, projet Gallium, INRIA Rocquencourt        *)
(*                                                                        *)
(*   Copyright 2014 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(** Definitions shared between the 32 and 64 bit Intel backends. *)

[@@@ocaml.warning "+a-40-41-42"]

open X86_ast

(** Helpers for textual emitters *)

val string_of_reg8l : reg64 -> string

val string_of_reg8h : reg8h -> string

val string_of_reg16 : reg64 -> string

val string_of_reg32 : reg64 -> string

val string_of_reg64 : reg64 -> string

val string_of_regf : regf -> string

val string_of_substring_literal : int -> int -> string -> string

val string_of_string_literal : string -> string

val string_of_condition : condition -> string

val string_of_float_condition : float_condition -> string

val string_of_float_condition_imm : arg -> string

val string_of_symbol : (*prefix*) string -> string -> string

val string_of_rounding : rounding -> string

val imm_of_float_condition : float_condition -> arg

val imm_of_rounding : rounding -> arg

val string_of_prefetch_temporal_locality_hint :
  prefetch_temporal_locality_hint -> string

val buf_bytes_directive :
  Buffer.t -> (*directive*) string -> (*data*) string -> unit

(** Buffer of assembly code *)

val create_asm_file : bool ref

val emit : instruction -> unit

val directive : asm_line -> unit

val reset_asm_code : unit -> unit

(** Code emission *)

(** Post-process the stream of instructions.  Dump it (using
      the provided syntax emitter) in a file (if provided) and
      compile it with an internal assembler (if registered
      through [register_internal_assembler]). *)
val generate_code : (X86_ast.asm_line list -> unit) option -> unit

(** Generate an object file corresponding to the last call to
    [generate_code].  An internal assembler is used if available (and
    the input file is ignored). Otherwise, the source asm file with an
    external assembler. *)
val assemble_file : (*infile*) string -> (*outfile*) string -> (*retcode*) int

(** System detection *)

(* CR-soon xclerc: remove the systems we do not (and will not) support. *)
type system =
  (* 32 bits and 64 bits *)
  | S_macosx
  | S_gnu
  | S_cygwin
  (* 32 bits only *)
  | S_solaris
  | S_win32
  | S_linux_elf
  | S_bsd_elf
  | S_beos
  | S_mingw
  (* 64 bits only *)
  | S_win64
  | S_linux
  | S_mingw64
  | S_freebsd
  | S_netbsd
  | S_openbsd
  | S_unknown

val system : system

val masm : bool

val windows : bool

val is_linux : system -> bool

val is_macosx : system -> bool

val is_win32 : system -> bool

val is_win64 : system -> bool

val is_solaris : system -> bool

(** Whether calls need to go via the PLT. *)
val use_plt : bool

module Section_name : sig
  type t

  val equal : t -> t -> bool

  val hash : t -> int

  val compare : t -> t -> int

  val make : string list -> string option -> string list -> t

  val of_string : string -> t

  val to_string : t -> string

  val flags : t -> string option

  val alignment : t -> int64

  val is_text_like : t -> bool

  val is_data_like : t -> bool

  val is_note_like : t -> bool

  module Map : Map.S with type key = t

  module Tbl : Hashtbl.S with type key = t
end

(** Support for plumbing a binary code emitter *)

val internal_assembler :
  (delayed:(unit -> (Section_name.t * X86_ast.asm_program) list) ->
  (Section_name.t * X86_ast.asm_program) list ->
  string ->
  unit)
  option
  ref

val register_internal_assembler :
  (delayed:(unit -> (Section_name.t * X86_ast.asm_program) list) ->
  (Section_name.t * X86_ast.asm_program) list ->
  string ->
  unit) ->
  unit
