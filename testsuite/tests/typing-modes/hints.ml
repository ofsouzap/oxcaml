(* TEST
 expect;
*)

(* CR pdsouza: at the time of writing these tests, many hints are not yet
               provided in the codebase, meanine that there are some tests
               here that have empty hints when in the future they will have
               hint text. These expected outputs will need to be changed at
               that point *)

(* Unnamed item *)

let x @ global = local_ "hello"
[%%expect{|
Line 1, characters 17-31:
1 | let x @ global = local_ "hello"
                     ^^^^^^^^^^^^^^
Error: This value is "local" but expected to be "global".
|}]

(* Named variable with no hints *)

let () =
  let x @ local = local_ "hi" in
  let _y @ global = x in
  ()
[%%expect{|
Line 3, characters 20-21:
3 |   let _y @ global = x in
                        ^
Error: This value is "local" but expected to be "global".
|}]

let foo () =
  let f : b:local_ string -> (c:int -> unit) =
    fun ~b -> fun[@curry] ~c -> print_string b
  in
  f ~b:"hello"
[%%expect{|
Line 3, characters 45-46:
3 |     fun ~b -> fun[@curry] ~c -> print_string b
                                                 ^
Error: The value "b" is local to the parent region
       because it crosses from something
       which is local to the parent region.
       However, it is expected to be "global"
       because it is used inside a function which is "global"
       because it crosses from something which is "global".
|}]
