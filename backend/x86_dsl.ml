(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*         Fabrice Le Fessant, projet Gallium, INRIA Rocquencourt         *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(** Helpers for Intel code generators *)

(* The DSL* modules expose functions to emit x86_64 instructions using a syntax
   close to AT&T (in particular, arguments are reversed compared to the official
   Intel syntax). *)

[@@@ocaml.warning "+a-40-41-42"]

open! Int_replace_polymorphic_compare
open X86_ast
open X86_proc

let sym s = Sym s

let nat n = Imm (Int64.of_nativeint n)

let int n = Imm (Int64.of_int n)

let const_32 n = Const (Int64.of_int32 n)

let const_nat n = Const (Int64.of_nativeint n)

let const n = Const (Int64.of_int n)

let al = Reg8L RAX

let ah = Reg8H AH

let cl = Reg8L RCX

let ax = Reg16 RAX

let rax = Reg64 RAX

let rbx = Reg64 RBX

let rdi = Reg64 RDI

let rdx = Reg64 RDX

let r10 = Reg64 R10

let r11 = Reg64 R11

let r12 = Reg64 R12

let r13 = Reg64 R13

let r14 = Reg64 R14

let r15 = Reg64 R15

let rsp = Reg64 RSP

let rbp = Reg64 RBP

let xmm15 = Regf (XMM 15)

let eax = Reg32 RAX

let ebx = Reg32 RBX

let ecx = Reg32 RCX

let edx = Reg32 RDX

let ebp = Reg32 RBP

let esp = Reg32 RSP

let mem32 typ ?(scale = 1) ?base ?sym displ idx =
  assert (scale >= 0);
  Mem { arch = X86; typ; idx; scale; base; sym; displ }

let mem64 typ ?(scale = 1) ?base ?sym displ idx =
  assert (scale > 0);
  Mem { arch = X64; typ; idx; scale; base; sym; displ }

let mem64_rip typ ?(ofs = 0) s = Mem64_RIP (typ, s, ofs)

module I = struct
  let add x y = emit (ADD (x, y))

  let and_ x y = emit (AND (x, y))

  let bsf x y = emit (BSF (x, y))

  let bsr x y = emit (BSR (x, y))

  let bswap x = emit (BSWAP x)

  let call x = emit (CALL x)

  let cdq () = emit CDQ

  let cldemote x = emit (CLDEMOTE x)

  let cmov cond x y = emit (CMOV (cond, x, y))

  let cmp x y = emit (CMP (x, y))

  let cqo () = emit CQO

  let dec x = emit (DEC x)

  let hlt () = emit HLT

  let idiv x = emit (IDIV x)

  let imul x y = emit (IMUL (x, y))

  let mul x = emit (MUL x)

  let inc x = emit (INC x)

  let j cond x = emit (J (cond, x))

  let ja = j A

  let jae = j AE

  let jb = j B

  let jbe = j BE

  let je = j E

  let jg = j G

  let jl = j L

  let jmp x = emit (JMP x)

  let jne = j NE

  let jp = j P

  let lea x y = emit (LEA (x, y))

  let lock_cmpxchg x y = emit (LOCK_CMPXCHG (x, y))

  let lock_xadd x y = emit (LOCK_XADD (x, y))

  let lock_add x y = emit (LOCK_ADD (x, y))

  let lock_sub x y = emit (LOCK_SUB (x, y))

  let lock_and x y = emit (LOCK_AND (x, y))

  let lock_or x y = emit (LOCK_OR (x, y))

  let lock_xor x y = emit (LOCK_XOR (x, y))

  let mov x y = emit (MOV (x, y))

  let movsx x y = emit (MOVSX (x, y))

  let movsxd x y = emit (MOVSXD (x, y))

  let movzx x y = emit (MOVZX (x, y))

  let neg x = emit (NEG x)

  let nop () = emit NOP

  let or_ x y = emit (OR (x, y))

  let pause () = emit PAUSE

  let pop x = emit (POP x)

  let popcnt x y = emit (POPCNT (x, y))

  let prefetch is_write locality x = emit (PREFETCH (is_write, locality, x))

  let push x = emit (PUSH x)

  let rdtsc () = emit RDTSC

  let rdpmc () = emit RDPMC

  let lfence () = emit LFENCE

  let sfence () = emit SFENCE

  let mfence () = emit MFENCE

  let ret () = emit RET

  let sal x y = emit (SAL (x, y))

  let sar x y = emit (SAR (x, y))

  let set cond x = emit (SET (cond, x))

  let shr x y = emit (SHR (x, y))

  let sub x y = emit (SUB (x, y))

  let test x y = emit (TEST (x, y))

  let xchg x y = emit (XCHG (x, y))

  let xor x y = emit (XOR (x, y))

  let lzcnt x y = emit (LZCNT (x, y))

  let tzcnt x y = emit (TZCNT (x, y))

  let simd instr args = emit (SIMD (instr, args))
end
