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
