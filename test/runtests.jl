using CodeTracking
using Test

include("script.jl")

@testset "CodeTracking.jl" begin
    m = first(methods(f1))
    file, line = whereis(m)
    @test file == normpath(joinpath(@__DIR__, "script.jl"))
    src = definition(m, String)
    @test src == """
    function f1(x, y)
        return x + y
    end
    """

    m = first(methods(f2))
    src = definition(m, String)
    @test src == """
    f2(x, y) = x + y
    """
end
