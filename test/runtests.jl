# Note: some of CodeTracking's functionality can only be tested by Revise

using CodeTracking
using Test, InteractiveUtils
# Note: ColorTypes needs to be installed, but note the intentional absence of `using ColorTypes`

using CodeTracking: line_is_decl

isdefined(Main, :Revise) ? includet("script.jl") : include("script.jl")

@testset "CodeTracking.jl" begin
    m = first(methods(f1))
    file, line = whereis(m)
    scriptpath = normpath(joinpath(@__DIR__, "script.jl"))
    @test file == scriptpath
    @test line == (line_is_decl ? 2 : 4)
    trace = try
        call_throws()
    catch
        stacktrace(catch_backtrace())
    end
    @test whereis(trace[2]) == (scriptpath, 9)
    @test whereis(trace[3]) === nothing

    src, line = definition(String, m)
    @test src == chomp("""
    function f1(x, y)
        # A comment
        return x + y
    end
    """)
    @test line == 2
    @test code_string(f1, Tuple{Any,Any}) == src
    @test @code_string(f1(1, 2)) == src

    m = first(methods(f2))
    src, line = definition(String, m)
    @test src == "f2(x, y) = x + y"
    @test line == 14

    m = first(methods(throws))
    src, line = definition(String, m)
    @test startswith(src, "@noinline")
    @test line == 7

    m = first(methods(multilinesig))
    src, line = definition(String, m)
    @test startswith(src, "@inline")
    @test line == 16
    @test @code_string(multilinesig(1, "hi")) == src
    @test_throws ErrorException("no unique matching method found for the specified argument types") @code_string(multilinesig(1, 2))

    m = first(methods(f50))
    src, line = definition(String, m)
    @test occursin("100x", src)
    @test line == 22

    info = CodeTracking.PkgFiles(Base.PkgId(CodeTracking))
    @test Base.PkgId(info) === info.id
    @test CodeTracking.basedir(info) == dirname(@__DIR__)

    io = IOBuffer()
    show(io, info)
    str = String(take!(io))
    @test startswith(str, "PkgFiles(CodeTracking [da1fd8a2-8d9e-5ec2-8556-3022fb5608a2]):\n  basedir:")

    @test pkgfiles("ColorTypes") === nothing
    @test_throws ErrorException pkgfiles("NotAPkg")

    # Test a method marked as missing
    m = @which sum(1:5)
    CodeTracking.method_info[m.sig] = missing
    @test whereis(m) == (CodeTracking.maybe_fix_path(String(m.file)), m.line)
    @test definition(m) === nothing

    # Test that definitions at the REPL work with `whereis`
    ex = Base.parse_input_line("replfunc(x) = 1"; filename="REPL[1]")
    eval(ex)
    m = first(methods(replfunc))
    @test whereis(m) == ("REPL[1]", 1)
    # Test with broken lookup
    oldlookup = CodeTracking.method_lookup_callback[]
    CodeTracking.method_lookup_callback[] = m -> error("oops")
    @test whereis(m) == ("REPL[1]", 1)
    # Test with definition(String, m)
    if isdefined(Base, :active_repl)
        hp = Base.active_repl.interface.modes[1].hist
        fstr = "__fREPL__(x::Int16) = 0"
        histidx = length(hp.history) + 1 - hp.start_idx
        ex = Base.parse_input_line(fstr; filename="REPL[$histidx]")
        f = Core.eval(Main, ex)
        push!(hp.history, fstr)
        @test definition(String, first(methods(f))) == (fstr, 1)
        pop!(hp.history)
    end
    CodeTracking.method_lookup_callback[] = oldlookup

    m = first(methods(Test.eval))
    @test occursin(Sys.STDLIB, whereis(m)[1])

    # https://github.com/JuliaDebug/JuliaInterpreter.jl/issues/150
    function f150()
        x = 1 + 1
        @info "hello"
    end
    m = first(methods(f150))
    src = Base.uncompressed_ast(m)
    idx = findfirst(lin -> String(lin.file) != @__FILE__, src.linetable)
    lin = src.linetable[idx]
    file, line = whereis(lin, m)
    @test endswith(file, String(lin.file))

    # Issues raised in #48
    m = @which(sum([1]; dims=1))
    if !isdefined(Main, :Revise)
        def = definition(String, m)
        @test def === nothing || isa(def[1], AbstractString)
        def = definition(Expr, m)
        @test def === nothing || isa(def, Expr)
    else
        def = definition(String, m)
        @test isa(def[1], AbstractString)
        def = definition(Expr, m)
        @test isa(def, Expr)
    end
end

@testset "With Revise" begin
    if isdefined(Main, :Revise)
        m = @which gcd(10, 20)
        sigs = signatures_at(Base.find_source_file(String(m.file)), m.line)
        @test !isempty(sigs)
        ex = @code_expr(gcd(10, 20))
        @test ex isa Expr
        @test occursin(String(m.file), String(ex.args[2].args[2].args[1].file))
        @test ex == code_expr(gcd, Tuple{Int,Int})

        m = first(methods(edit))
        sigs = signatures_at(String(m.file), m.line)
        @test !isempty(sigs)
        sigs = signatures_at(Base.find_source_file(String(m.file)), m.line)
        @test !isempty(sigs)

        # issue #23
        @test !isempty(signatures_at("script.jl", 9))
    end
end

(a_34)(x::T, y::T) where {T<:Integer} = no_op_err("&", T)
(b_34)(x::T, y::T) where {T<:Integer} = no_op_err("|", T)
c_34(x::T, y::T) where {T<:Integer} = no_op_err("xor", T)

(d_34)(x::T, y::T) where {T<:Number} = x === y
(e_34)(x::T, y::T) where {T<:Real} = no_op_err("<" , T)
(f_34)(x::T, y::T) where {T<:Real} = no_op_err("<=", T)
l = @__LINE__
@testset "#34 last character" begin
    def, line = definition(String, @which d_34(1, 2))
    @test line == l - 3
    @test def == "(d_34)(x::T, y::T) where {T<:Number} = x === y"
end

function g()
    Base.@_inline_meta
    print("hello")
end
@testset "inline macros" begin
    def, line = CodeTracking.definition(String, @which g())
    @test def == """
    function g()
        Base.@_inline_meta
        print("hello")
    end"""
end
