# An optimization to reduce the amount of time spent re-parsing Manifest.toml
# Revise may invalidate this if the active manifest file changes
if isdefined(Base, :TOMLCache)
    const tomlcache = Ref{Union{Nothing,Base.TOMLCache}}(nothing)
    function locate_package(id::PkgId)
        cache = tomlcache[]
        if cache === nothing
            cache = tomlcache[] = Base.TOMLCache()
        end
        return Base.locate_package(id, cache)
    end
    function project_deps_get(env::String, name::String)
        cache = tomlcache[]
        if cache === nothing
            cache = tomlcache[] = Base.TOMLCache()
        end
        return Base.project_deps_get(env, name, cache)
    end
else
    const tomlcache = Ref(nothing)
    locate_package(id::PkgId) = Base.locate_package(id)
    project_deps_get(env::String, name::String) = Base.project_deps_get(env, name)
end

function checkname(fdef::Expr, name)
    fproto = fdef.args[1]
    fdef.head === :where && return checkname(fproto, name)
    if fproto isa Expr
        # Is the check below redundant?
        fproto.head === :. || return false
        # E.g. `function Mod.bar.foo(a, b)`
        return checkname(fproto.args[end], name)
    end
    return checkname(fproto, name)
end
checkname(fname::Symbol, name::Symbol) = begin
    fname === name && return true
    startswith(string(name), string('#', fname, '#')) && return true
    return false
end
checkname(fname::Symbol, ::Nothing) = true
checkname(fname::QuoteNode, name) = checkname(fname.value, name)

function isfuncexpr(ex, name=nothing)
    # Strip any macros that wrap the method definition
    while ex isa Expr && ex.head === :macrocall && length(ex.args) == 3
        ex = ex.args[3]
    end
    isa(ex, Expr) || return false
    if ex.head === :function || ex.head === :(=)
        return checkname(ex.args[1], name)
    end
    return false
end

function linerange(def::Expr)
    start, haslinestart = findline(def, identity)
    stop, haslinestop  = findline(def, Iterators.reverse)
    (haslinestart & haslinestop) && return start:stop
    return nothing
end
linerange(arg) = linerange(convert(Expr, arg))  # Handle Revise's RelocatableExpr

function findline(ex, order)
    ex.head === :line && return ex.args[1], true
    for a in order(ex.args)
        a isa LineNumberNode && return a.line, true
        if a isa Expr
            ln, hasline = findline(a, order)
            hasline && return ln, true
        end
    end
    return 0, false
end

fileline(lin::LineInfoNode)   = String(lin.file), lin.line
fileline(lnn::LineNumberNode) = String(lnn.file), lnn.line

# This is piracy, but it's not ambiguous in terms of what it should do
Base.convert(::Type{LineNumberNode}, lin::LineInfoNode) = LineNumberNode(lin.line, lin.file)

# This regex matches the pseudo-file name of a REPL history entry.
const rREPL = r"^REPL\[(\d+)\]$"

"""
    src = src_from_file_or_REPL(origin::AbstractString, repl = Base.active_repl)

Read the source for a function from `origin`, which is either the name of a file
or "REPL[\$i]", where `i` is an integer specifying the particular history entry.
Methods defined at the REPL use strings of this form in their `file` field.

If you happen to have a file where the name matches `REPL[\$i]`, first pass it through
`abspath`.
"""
function src_from_file_or_REPL(origin::AbstractString, args...)
    # This Varargs design prevents an unnecessary error when Base.active_repl is undefined
    # and `origin` does not match "REPL[$i]"
    m = match(rREPL, origin)
    if m !== nothing
        return src_from_REPL(m.captures[1], args...)
    end
    return read(origin, String)
end

function src_from_REPL(origin::AbstractString, repl = Base.active_repl)
    hist_idx = parse(Int, origin)
    hp = repl.interface.modes[1].hist
    return hp.history[hp.start_idx+hist_idx]
end

function basepath(id::PkgId)
    id.name ∈ ("Main", "Base", "Core") && return ""
    loc = locate_package(id)
    loc === nothing && return ""
    return dirname(dirname(loc))
end

"""
    path = maybe_fix_path(path)

Return a normalized, absolute path for a source file `path`.
"""
function maybe_fix_path(file)
    if !isabspath(file)
        # This may be a Base or Core method
        newfile = Base.find_source_file(file)
        if isa(newfile, AbstractString)
            file = normpath(newfile)
        end
    end
    return maybe_fixup_stdlib_path(file)
end

safe_isfile(x) = try isfile(x); catch; false end
const BUILDBOT_STDLIB_PATH = dirname(abspath(joinpath(String((@which uuid1()).file), "..", "..", "..")))
replace_buildbot_stdlibpath(str::String) = replace(str, BUILDBOT_STDLIB_PATH => Sys.STDLIB)
"""
    path = maybe_fixup_stdlib_path(path::String)

Return `path` corrected for julia issue [#26314](https://github.com/JuliaLang/julia/issues/26314) if applicable.
Otherwise, return the input `path` unchanged.

Due to the issue mentioned above, location info for methods defined one of Julia's standard libraries
are, for non source Julia builds, given as absolute paths on the worker that built the `julia` executable.
This function corrects such a path to instead refer to the local path on the users drive.
"""
function maybe_fixup_stdlib_path(path)
    if !safe_isfile(path)
        maybe_stdlib_path = replace_buildbot_stdlibpath(path)
        safe_isfile(maybe_stdlib_path) && return maybe_stdlib_path
    end
    return path
end

function postpath(filename, pre)
    idx = findfirst(pre, filename)
    idx === nothing && error(pre, " not found in ", filename)
    post = filename[first(idx) + length(pre) : end]
    post[1:1] == Base.Filesystem.path_separator && return post[2:end]
    return post
end
