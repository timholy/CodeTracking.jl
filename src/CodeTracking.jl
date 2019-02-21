module CodeTracking

using Base: PkgId
using Core: LineInfoNode

export whereis, definition, pkgfiles

include("data.jl")
include("utils.jl")

"""
    filepath, line = whereis(method::Method)

Return the file and line of the definition of `method`. `line`
is the first line of the method's body.
"""
function whereis(method::Method)
    lin = get(method_locations, method.sig, nothing)
    if lin === nothing
        file, line = String(method.file), method.line
    else
        file, line = fileline(lin)
    end
    if !isabspath(file)
        # This is a Base or Core method
        file = Base.find_source_file(file)
    end
    return normpath(file), line
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
definition(method::Method, ::Type{Expr}) = get(method_definitions, method.sig, nothing)

definition(method::Method) = definition(method, Expr)

"""
    info = pkgfiles(id::PkgId)

Return a [`PkgFiles`](@ref) structure with information about the files that define package `id`.
Returns `nothing` if `id` has not been loaded.
"""
pkgfiles(id::PkgId) = get(_pkgfiles, id, nothing)

"""
    info = pkgfiles(mod::Module)

Return a [`PkgFiles`](@ref) structure with information about the files that were loaded to
define the package that defined `mod`.
"""
pkgfiles(mod::Module) = pkgfiles(PkgId(mod))

end # module
