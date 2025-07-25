(* TEST
 readonly_files = "contexts_1.ml contexts_2.ml contexts_3.ml";
 flags = "-dsource -dlambda";
 stack-allocation;
 expect;
*)

#use "contexts_1.ml";;
(* Notice that (field_mut 1 input) occurs twice, it
   is evaluated once in the 'false' branch and once in the 'true'
   branch. The compiler assumes that its static knowledge about the
   first read (it cannot be a [Right] as we already matched against it
   and failed) also applies to the second read, which is unsound.
*)
[%%expect {|

#use  "contexts_1.ml";;

type u = {
  a: bool ;
  mutable b: (bool, int) Either.t };;
0
type u = { a : bool; mutable b : (bool, int) Either.t; }

let example_1 () =
  let input = { a = true; b = (Either.Left true) } in
  match input with
  | { a = false; b = _ } -> Result.Error 1
  | { a = _; b = Either.Right _ } -> Result.Error 2
  | { a = _; b = _ } when input.b <- (Either.Right 3); false ->
      Result.Error 3
  | { a = true; b = Either.Left y } -> Result.Ok y;;
(let
  (example_1/304 =
     (function {nlocal = 0} param/328[value<int>]
       : (consts ()) (non_consts ([1: ?] [0: ?]))
       (region
         (let
           (input/306 =
              (makelocalmutable 0 (value<int>,value<
                                               (consts ())
                                                (non_consts ([1: ?] [0: ?]))>)
                1 [0: 1]))
           (if (field_int 0 input/306)
             (let (*match*/331 =o? (field_mut 1 input/306))
               (switch* *match*/331
                case tag 0:
                 (if (seq (setfield_ptr(maybe-stack) 1 input/306 [1: 3]) 0)
                   [1: 3]
                   (let (*match*/333 =o? (field_mut 1 input/306))
                     (makeblock 0 (value<int>) (field_imm 0 *match*/333))))
                case tag 1: [1: 2]))
             [1: 1])))))
  (apply (field_imm 1 (global Toploop!)) "example_1" example_1/304))
val example_1 : unit -> (bool, int) Result.t = <fun>
|}]

#use "contexts_2.ml";;
[%%expect {|

#use  "contexts_2.ml";;

type 'a myref = {
  mutable mut: 'a };;
0
type 'a myref = { mutable mut : 'a; }

type u = {
  a: bool ;
  b: (bool, int) Either.t myref };;
0
type u = { a : bool; b : (bool, int) Either.t myref; }

let example_2 () =
  let input = { a = true; b = { mut = (Either.Left true) } } in
  match input with
  | { a = false; b = _ } -> Result.Error 1
  | { a = _; b = { mut = Either.Right _ } } -> Result.Error 2
  | { a = _; b = _ } when (input.b).mut <- (Either.Right 3); false ->
      Result.Error 3
  | { a = true; b = { mut = Either.Left y } } -> Result.Ok y;;
(let
  (example_2/343 =
     (function {nlocal = 0} param/347[value<int>]
       : (consts ()) (non_consts ([1: ?] [0: ?]))
       (region
         (let
           (input/345 =[value<(consts ()) (non_consts ([0: value<int>, *]))>]
              (makelocalblock 0 (value<int>,*) 1
                (makelocalmutable 0 (value<
                                      (consts ()) (non_consts ([1: ?]
                                       [0: ?]))>)
                  [0: 1])))
           (if (field_int 0 input/345)
             (let (*match*/351 =o? (field_mut 0 (field_imm 1 input/345)))
               (switch* *match*/351
                case tag 0:
                 (if
                   (seq
                     (setfield_ptr(maybe-stack) 0 (field_imm 1 input/345)
                       [1: 3])
                     0)
                   [1: 3]
                   (let
                     (*match*/354 =o? (field_mut 0 (field_imm 1 input/345)))
                     (makeblock 0 (value<int>) (field_imm 0 *match*/354))))
                case tag 1: [1: 2]))
             [1: 1])))))
  (apply (field_imm 1 (global Toploop!)) "example_2" example_2/343))
val example_2 : unit -> (bool, int) Result.t = <fun>
|}]

#use "contexts_3.ml";;
[%%expect {|

#use  "contexts_3.ml";;

type 'a myref = {
  mutable mut: 'a };;
0
type 'a myref = { mutable mut : 'a; }

type u = (bool * (bool, int) Either.t) myref;;
0
type u = (bool * (bool, int) Either.t) myref

let example_3 () =
  let input = { mut = (true, (Either.Left true)) } in
  match input with
  | { mut = (false, _) } -> Result.Error 1
  | { mut = (_, Either.Right _) } -> Result.Error 2
  | { mut = (_, _) } when input.mut <- (true, (Either.Right 3)); false ->
      Result.Error 3
  | { mut = (true, Either.Left y) } -> Result.Ok y;;
(let
  (example_3/361 =
     (function {nlocal = 0} param/365[value<int>]
       : (consts ()) (non_consts ([1: ?] [0: ?]))
       (region
         (let
           (input/363 =mut[value<
                            (consts ())
                             (non_consts ([0: value<int>,
                                           value<
                                            (consts ()) (non_consts (
                                             [1: ?] [0: ?]))>]))>]
              [0: 1 [0: 1]]
            *match*/366 =o? *input/363)
           (if (field_imm 0 *match*/366)
             (switch* (field_imm 1 *match*/366)
              case tag 0:
               (if (seq (assign input/363 [0: 1 [1: 3]]) 0) [1: 3]
                 (makeblock 0 (value<int>)
                   (field_imm 0 (field_imm 1 *match*/366))))
              case tag 1: [1: 2])
             [1: 1])))))
  (apply (field_imm 1 (global Toploop!)) "example_3" example_3/361))
val example_3 : unit -> (bool, int) Result.t = <fun>
|}]
