external ( + ) : int -> int -> int = "%addint"

let test x =
  let x = x, x in
  let[@inline always] sump (x, y) = x + y in
  let[@inline never] [@local never] f y z = sump x + sump y + sump z in
  let[@inline never] [@local never] g f = f x in
  g f x
