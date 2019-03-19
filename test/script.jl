# NOTE: tests are sensitive to the line number at which statements appear
function f1(x, y)
    # A comment
    return x + y
end

f2(x, y) = x + y

@noinline function throws()
    x = nothing
    error("oops")
end
@inline inlined() = throws()
call_throws() = inlined()
