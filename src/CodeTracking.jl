module CodeTracking

using Base: PkgId
using Core: LineInfoNode
using UUIDs

export whereis, definition, pkgfiles, signatures_at

include("pkgfiles.jl")
include("utils.jl")

### Global storage

# These values get populated by Revise

const method_info = IdDict{Type,Tuple{LineNumberNode,Expr}}()

const _pkgfiles = Dict{PkgId,PkgFiles}()

const method_lookup_callback = Ref{Any}(nothing)
const expressions_callback   = Ref{Any}(nothing)

### Public API

"""
    filepath, line = whereis(method::Method)

Return the file and line of the definition of `method`. `line`
is the first line of the method's body.
"""
function whereis(method::Method)
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
    if lin === nothing
        file, line = String(method.file), method.line
    else
        file, line = fileline(lin[1])
    end
    if !isabspath(file)
        # This may be a Base or Core method
        newfile = Base.find_source_file(file)
        if isa(newfile, AbstractString)
            file = normpath(newfile)
        end
    end
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
    return file, lineinfo.line-method.line+line1
end

"""
    sigs = signatures_at(filename, line)

Return the signatures of all methods whose definition spans the specified location.
`line` must correspond to a line in the method body (not the signature or final `end`).

Returns `nothing` if there are no methods at that location.
"""
function signatures_at(filename::AbstractString, line::Integer)
    for (id, pkgfls) in _pkgfiles
        if startswith(filename, basedir(pkgfls)) || id.name == "Main"
            bdir = basedir(pkgfls)
            rpath = isempty(bdir) ? filename : relpath(filename, bdir)
            if rpath ∈ pkgfls.files
                return signatures_at(id, rpath, line)
            end
        end
    end
    error("$filename not found, perhaps the package is not loaded")
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
    src = definition(method::Method, String)

Return a string with the code that defines `method`.

Note this may not be terribly useful for methods that are defined inside `@eval` statements;
see [`definition(method::Method, Expr)`](@ref) instead.
"""
function definition(method::Method, ::Type{String})
    file, line = whereis(method)
    src = read(file, String)
    eol = isequal('\n')
    linestarts = Int[]
    istart = 0
    for i = 1:line-1
        push!(linestarts, istart+1)
        istart = findnext(eol, src, istart+1)
    end
    ex, iend = Meta.parse(src, istart)
    if isfuncexpr(ex)
        return src[istart+1:iend-1]
    end
    # The function declaration was presumably on a previous line
    lineindex = lastindex(linestarts)
    while !isfuncexpr(ex)
        istart = linestarts[lineindex]
        ex, iend = Meta.parse(src, istart)
    end
    return src[istart:iend-1]
end

"""
    ex = definition(method::Method, Expr)
    ex = definition(method::Method)

Return an expression that defines `method`.
"""
function definition(method::Method, ::Type{Expr})
    def = get(method_info, method.sig, nothing)
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
    return def === nothing ? nothing : copy(def[2])
end

definition(method::Method) = definition(method, Expr)

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
    uuid = Base.project_deps_get(project, name)
    uuid == false && error("no package ", name, " recognized")
    return pkgfiles(name, uuid)
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
