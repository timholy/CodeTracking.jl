# Note: some of CodeTracking's functionality can only be tested by Revise

using CodeTracking
using Test
# Note: ColorTypes needs to be installed, but note the intentional absence of `using ColorTypes`

include("script.jl")

@testset "CodeTracking.jl" begin
    m = first(methods(f1))
    file, line = whereis(m)
    scriptpath = normpath(joinpath(@__DIR__, "script.jl"))
    @test file == scriptpath
    @test line == 3
    trace = try
        call_throws()
    catch
        stacktrace(catch_backtrace())
    end
    @test whereis(trace[2]) == (scriptpath, 10)
    @test whereis(trace[3]) === nothing

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

    info = CodeTracking.PkgFiles(Base.PkgId(CodeTracking))
    @test Base.PkgId(info) === info.id
    @test CodeTracking.basedir(info) == dirname(@__DIR__)

    io = IOBuffer()
    show(io, info)
    str = String(take!(io))
    @test startswith(str, "PkgFiles(CodeTracking [da1fd8a2-8d9e-5ec2-8556-3022fb5608a2]):\n  basedir:")

    @test pkgfiles("ColorTypes") === nothing
    @test_throws ErrorException pkgfiles("NotAPkg")

    # Test that definitions at the REPL work with `whereis`
    ex = Base.parse_input_line("replfunc(x) = 1"; filename="REPL[1]")
    eval(ex)
    m = first(methods(replfunc))
    @test whereis(m) == ("REPL[1]", 1)

    # Test with broken lookup
    CodeTracking.method_lookup_callback[] = m -> error("oops")
    @test whereis(m) == ("REPL[1]", 1)
end
