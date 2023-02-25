# NOTE: tests are sensitive to the line number at which statements appear
function f1(x, y)
    # A comment
    return x + y
end

@noinline function throws()
    x = nothing
    error("oops")
end
@inline inlined() = throws()
call_throws() = inlined()

f2(x, y) = x + y

@inline function multilinesig(x::Int,
                              y::String)
    z = x + 1
    return z
end

function f50()   # issue #50
    todB(x) = 10*log10(x)
    println("100x is $(todB(100)) dB.")
end

func_1st_nokwarg() = true
func_2nd_kwarg(; kw=2) = true

module Foo
module Bar
function fit end
end
end

function Foo.Bar.fit(m)
    return m
end

Foo.Bar.fit(a, b) = a + b

# Issue #81
function hasrettype(x::Real)::Float32
    return x*x + x
end

function fkw(; x=1)
    x
end

# Issue #80
f80 = x -> 2 * x^3 + 1

# Issue #103
if isdefined(Base, Symbol("@assume_effects"))
    @eval begin
        Base.@assume_effects :terminates_locally  function pow103(x)
            # this :terminates_locally allows `pow` to be constant-folded
            res = 1
            1 < x < 20 || error("bad pow")
            while x > 1
                res *= x
                x -= 1
            end
            return res
        end
    end
end

has_semicolon1(x, y) = x + y;
