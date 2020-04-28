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
