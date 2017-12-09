data = String.duplicate(<<0>>, div(35651528,8))
<<x::integer-size(35651528), rest::bits>> = data
IO.inspect {x, rest}
