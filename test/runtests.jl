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

    info = PkgFiles(Base.PkgId(CodeTracking))
    @test Base.PkgId(info) === info.id
    @test CodeTracking.basedir(info) == dirname(@__DIR__)

    io = IOBuffer()
    show(io, info)
    str = String(take!(io))
    @test startswith(str, "PkgFiles(CodeTracking [da1fd8a2-8d9e-5ec2-8556-3022fb5608a2]):\n  basedir:")
end
