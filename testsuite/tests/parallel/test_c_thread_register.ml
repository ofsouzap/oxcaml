(* TEST
 flags += "-alert -do_not_spawn_domains -alert -unsafe_multidomain";
 modules = "test_c_thread_register_cstubs.c";
 runtime5;
 multidomain;
 include systhreads;
 hassysthreads;
 {
   bytecode;
 }{
   native;
 }
*)

(* spins a external thread from C and register it to the OCaml runtime *)

external spawn_thread : (unit -> unit) -> unit = "spawn_thread"

let passed () = Printf.printf "passed\n"

let _ =
  let d =
    Domain.spawn begin fun () ->
      spawn_thread passed;
      Thread.delay 0.5
    end
  in
  let t = Thread.create (fun () -> Thread.delay 1.0) () in
  Thread.join t;
  Domain.join d
