module CodeTracking

using Base: PkgId
using Core: LineInfoNode
using Base.Meta: isexpr
using UUIDs
using InteractiveUtils

export whereis, definition, pkgfiles, signatures_at

include("pkgfiles.jl")
include("utils.jl")

### Global storage

# These values get populated by Revise

const method_info = IdDict{Type,Union{Missing,Tuple{LineNumberNode,Expr}}}()

const _pkgfiles = Dict{PkgId,PkgFiles}()

# Callback for method-lookup. `lookupfunc = method_lookup_callback[]` must have the form
#     ret = lookupfunc(method)
# where `ret` is either `nothing` or `(lnn, def)`. `lnn` is a LineNumberNode (or any valid
# input to `CodeTracking.fileline`) and `def` is the expression defining the method.
const method_lookup_callback = Ref{Any}(nothing)

# Callback for `signatures_at` (lookup by file/lineno). `lookupfunc = expressions_callback[]`
# must have the form
#    mod, exsigs = lookupfunc(id, relpath)
# where
#    id is the PkgId of the corresponding package
#    relpath is the path of the file from the basedir of `id`
#    mod is the "active" module at that point in the source
#    exsigs is a ex=>sigs dictionary, where `ex` is the source expression and `sigs`
#        a list of method-signatures defined by that expression.
const expressions_callback = Ref{Any}(nothing)

const juliabase = joinpath("julia", "base")
const juliastdlib = joinpath("julia", "stdlib", "v$(VERSION.major).$(VERSION.minor)")

### Public API

"""
    filepath, line = whereis(method::Method)

Return the file and line of the definition of `method`. `line`
is the first line of the method's body.
"""
function whereis(method::Method)
    file, line = String(method.file), method.line
    startswith(file, "REPL[") && return file, line
    lin = get(method_info, method.sig, nothing)
    if lin === nothing
        f = method_lookup_callback[]
        if f !== nothing
            try
                Base.invokelatest(f, method)
                lin = get(method_info, method.sig, nothing)
            catch
            end
        end
    end
    if lin === nothing || ismissing(lin)
    else
        file, line = fileline(lin[1])
    end
    file = maybe_fix_path(file)
    return file, line
end

"""
    loc = whereis(sf::StackFrame)

Return location information for a single frame of a stack trace.
If `sf` corresponds to a frame that was inlined, `loc` will be `nothing`.
Otherwise `loc` will be `(filepath, line)`.
"""
function whereis(sf::StackTraces.StackFrame)
    sf.linfo === nothing && return nothing
    return whereis(sf, sf.linfo.def)
end

"""
    filepath, line = whereis(lineinfo, method::Method)

Return the file and line number associated with a specific statement in `method`.
`lineinfo.line` should contain the line number of the statement at the time `method`
was compiled. The current location is returned.
"""
function whereis(lineinfo, method::Method)
    file, line1 = whereis(method)
    # We could be in an expanded macro. Apply the correction only if the filename checks out.
    # (We're not super-fastidious here because of symlinks and other path ambiguities)
    samefile = basename(file) == basename(String(lineinfo.file))
    if !samefile
        return maybe_fix_path(String(lineinfo.file)), lineinfo.line
    end
    return file, lineinfo.line - method.line + line1
end
function whereis(lineinfo::Core.LineInfoNode, method::Method)
    # With LineInfoNode we have certainty about whether we're in a macro expansion
    if lineinfo.method == Symbol("macro expansion")
        return maybe_fix_path(String(lineinfo.file)), lineinfo.line
    end
    file, line1 = whereis(method)
    return file, lineinfo.line - method.line + line1
end

"""
    sigs = signatures_at(filename, line)

Return the signatures of all methods whose definition spans the specified location.
`line` must correspond to a line in the method body (not the signature or final `end`).

Returns `nothing` if there are no methods at that location.
"""
function signatures_at(filename::AbstractString, line::Integer)
    if !startswith(filename, "REPL[")
        filename = abspath(filename)
    end
    if occursin(juliabase, filename)
        rpath = postpath(filename, juliabase)
        id = PkgId(Base)
        return signatures_at(id, rpath, line)
    elseif occursin(juliastdlib, filename)
        rpath = postpath(filename, juliastdlib)
        spath = splitpath(rpath)
        libname = spath[1]
        project = Base.active_project()
        id = PkgId(Base.project_deps_get(project, libname), libname)
        return signatures_at(id, joinpath(spath[2:end]...), line)
    end
    if startswith(filename, "REPL[")
        id = PkgId("@REPL")
        return signatures_at(id, filename, line)
    end
    for (id, pkgfls) in _pkgfiles
        if startswith(filename, basedir(pkgfls)) || id.name == "Main"
            bdir = basedir(pkgfls)
            rpath = isempty(bdir) ? filename : relpath(filename, bdir)
            if rpath ∈ pkgfls.files
                return signatures_at(id, rpath, line)
            end
        end
    end
    error("$filename not found in internal data, perhaps the package is not loaded (or not loaded with `includet`)")
end

"""
    sigs = signatures_at(mod::Module, relativepath, line)

For a package that defines module `mod`, return the signatures of all methods whose definition
spans the specified location. `relativepath` indicates the path of the file relative to
the packages top-level directory, e.g., `"src/utils.jl"`.
`line` must correspond to a line in the method body (not the signature or final `end`).

Returns `nothing` if there are no methods at that location.
"""
function signatures_at(mod::Module, relpath::AbstractString, line::Integer)
    id = PkgId(mod)
    return signatures_at(id, relpath, line)
end

function signatures_at(id::PkgId, relpath::AbstractString, line::Integer)
    expressions = expressions_callback[]
    expressions === nothing && error("cannot look up methods by line number, try `using Revise` before loading other packages")
    try
        for (mod, exsigs) in Base.invokelatest(expressions, id, relpath)
            for (ex, sigs) in exsigs
                lr = linerange(ex)
                lr === nothing && continue
                line ∈ lr && return sigs
            end
        end
    catch
    end
    return nothing
end

"""
    src, line1 = definition(String, method::Method)

Return a string with the code that defines `method`. Also return the first line of the
definition, including the signature (which may not be the same line number returned
by `whereis`).

Note this may not be terribly useful for methods that are defined inside `@eval` statements;
see [`definition(Expr, method::Method)`](@ref) instead.
"""
function definition(::Type{String}, method::Method)
    file, line = whereis(method)
    src = src_from_file_or_REPL(file)
    eol = isequal('\n')
    linestarts = Int[]
    istart = 1
    for i = 1:line-1
        push!(linestarts, istart)
        istart = findnext(eol, src, istart) + 1
    end
    ex, iend = Meta.parse(src, istart)
    iend = prevind(src, iend)
    if isfuncexpr(ex)
        iend = min(iend, lastindex(src))
        return strip(src[istart:iend], '\n'), line
    end
    # The function declaration was presumably on a previous line
    lineindex = lastindex(linestarts)
    while !isfuncexpr(ex) && lineindex > 0
        istart = linestarts[lineindex]
        try
            ex, iend = Meta.parse(src, istart)
        catch
        end
        lineindex -= 1
        line -= 1
    end
    return chomp(src[istart:iend-1]), line
end

"""
    ex = definition(Expr, method::Method)
    ex = definition(method::Method)

Return an expression that defines `method`.
"""
function definition(::Type{Expr}, method::Method)
    file = String(method.file)
    def = startswith(file, "REPL[") ? nothing : get(method_info, method.sig, nothing)
    if def === nothing
        f = method_lookup_callback[]
        if f !== nothing
            try
                Base.invokelatest(f, method)
                def = get(method_info, method.sig, nothing)
            catch
            end
        end
    end
    return def === nothing || ismissing(def) ? nothing : copy(def[2])
end

definition(method::Method) = definition(Expr, method)

"""
    info = pkgfiles(name::AbstractString)
    info = pkgfiles(name::AbstractString, uuid::UUID)

Return a [`CodeTracking.PkgFiles`](@ref) structure with information about the files that
define the package specified by `name` and `uuid`.
Returns `nothing` if this package has not been loaded.
"""
pkgfiles(name::AbstractString, uuid::UUID) = pkgfiles(PkgId(uuid, name))
function pkgfiles(name::AbstractString)
    project = Base.active_project()
    # The value returned by Base.project_deps_get depends on the Julia version
    id = Base.project_deps_get(project, name)
    (id == false || id === nothing) && error("no package ", name, " recognized")
    return isa(id, PkgId) ? pkgfiles(id) : pkgfiles(name, id)
end
pkgfiles(id::PkgId) = get(_pkgfiles, id, nothing)

"""
    info = pkgfiles(mod::Module)

Return a [`CodeTracking.PkgFiles`](@ref) structure with information about the files that
were loaded to define the package that defined `mod`.
"""
pkgfiles(mod::Module) = pkgfiles(PkgId(mod))

if ccall(:jl_generating_output, Cint, ()) == 1
    precompile(Tuple{typeof(setindex!), Dict{PkgId,PkgFiles}, PkgFiles, PkgId})
end

end # module
