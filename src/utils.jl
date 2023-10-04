# This should stay as the first method because it's used in a test
# (or change the test)
function checkname(fdef::Expr, name)   # this is now unused
    fdef.head === :call || return false
    fproto = fdef.args[1]
    if fproto isa Expr
        fproto.head == :(::) && return last(fproto.args) === name  # (obj::MyCallable)(x) = ...
        fproto.head == :curly && return fproto.args[1] === name   # MyType{T}(x) = ...
        # A metaprogramming-generated function
        fproto.head === :$ && return true   # uncheckable, let's assume all is well
        # Is the check below redundant?
        fproto.head === :. || return false
        # E.g. `function Mod.bar.foo(a, b)`
        return checkname(fproto.args[end], name)
    end
    isa(fproto, Symbol) || isa(fproto, QuoteNode) || isa(fproto, Expr) || return false
    return checkname(fproto, name)
end

function get_call_expr(@nospecialize(ex))
    while isa(ex, Expr) && ex.head ∈ (:where, :(::))
        ex = ex.args[1]
    end
    isexpr(ex, :call) && return ex
    return nothing
end

function get_func_expr(@nospecialize(ex))
    isa(ex, Expr) || return ex
    # Strip any macros that wrap the method definition
    while isa(ex, Expr) && ex.head ∈ (:toplevel, :macrocall, :global, :local)
        ex.head == :macrocall && length(ex.args) < 3 && return ex
        ex = ex.args[end]
    end
    isa(ex, Expr) || return ex
    if ex.head == :(=) && length(ex.args) == 2
        child1, child2 = ex.args
        isexpr(get_call_expr(child1), :call) && return ex
        isexpr(child2, :(->)) && return child2
    end
    return ex
end

function is_func_expr(@nospecialize(ex))
    isa(ex, Expr) || return false
    ex.head ∈ (:function, :(->)) && return true
    if ex.head == :(=) && length(ex.args) == 2
        child1 = ex.args[1]
        isexpr(get_call_expr(child1), :call) && return true
    end
    return false
end

function is_func_expr(@nospecialize(ex), name::Symbol)
    ex = get_func_expr(ex)
    is_func_expr(ex) || return false
    return checkname(get_call_expr(ex.args[1]), name)
end

function is_func_expr(@nospecialize(ex), meth::Method)
    ex = get_func_expr(ex)
    is_func_expr(ex) || return false
    fname = nothing
    if ex.head == :(->)
        exargs = ex.args[1]
        if isexpr(exargs, :tuple)
            exargs = exargs.args
        elseif (isa(exargs, Expr) && exargs.head ∈ (:(::), :.)) || isa(exargs, Symbol)
            exargs = [exargs]
        elseif isa(exargs, Expr)
            return false
        end
    else
        callex = get_call_expr(ex.args[1])
        isexpr(callex, :call) || return false
        fname = callex.args[1]
        modified = true
        while modified
            modified = false
            if isexpr(fname, :curly)    # where clause
                fname = fname.args[1]
                modified = true
            end
            if isexpr(fname, :., 2)        # module-qualified
                fname = fname.args[2]
                @assert isa(fname, QuoteNode)
                fname = fname.value
                modified = true
            end
            if isexpr(fname, :(::))
                fname = fname.args[end]
                modified = true
            end
            if isexpr(fname, :where)
                fname = fname.args[1]
                modified = true
            end
        end
        if !(isa(fname, Symbol) && is_gensym(fname)) && !isexpr(fname, :$)
            if fname === :Type && isexpr(ex.args[1], :where) && isexpr(callex.args[1], :(::)) && isexpr(callex.args[1].args[end], :curly)
                Tsym = callex.args[1].args[end].args[2]
                whereex = ex.args[1]
                while true
                    found = false
                    for wheretyp in whereex.args[2:end]
                        isexpr(wheretyp, :(<:)) || continue
                        if Tsym == wheretyp.args[1]
                            fname = wheretyp.args[2]
                            found = true
                            break
                        end
                    end
                    found && break
                    whereex = whereex.args[1]
                end
            end
            # match the function name
            if isexpr(fname, :curly)
                fname = fname.args[1]
            end
            fname === strip_gensym(meth.name) || return false
        end
        exargs = callex.args[2:end]
    end
    # match the argnames
    if !isempty(exargs) && isexpr(first(exargs), :parameters)
        popfirst!(exargs)   # don't match kwargs
    end
    margs = Base.method_argnames(meth)
    _, idx = kwmethod_basename(meth)
    if idx > 0
        margs = margs[idx:end]
    end
    for (arg, marg) in zip(exargs, margs[2:end])
        if isexpr(arg, :$)
            # If this is a splat, we may not even have the right number of args. In that case,
            # just trust the matching we've done so far.
            lastarg = arg.args[end]
            isexpr(lastarg, :...) && return true
            continue
        end
        if isexpr(arg, :...)   # also test the other order of $ and ..., e.g., `c470($argnames...)`
            lastarg = only(arg.args)
            isexpr(lastarg, :$) && return true
        end
        aname = get_argname(arg)
        aname === :_ && continue
        aname === marg || (aname === Symbol("#unused#") && marg === Symbol("")) || return false
    end
    return true  # this will match any fcn `() -> ...`, but file/line is the only thing we have
end

function get_argname(@nospecialize(ex))
    isa(ex, Symbol) && return ex
    isexpr(ex, :(::), 2) && return get_argname(ex.args[1])      # type-asserted
    isexpr(ex, :(::), 1) && return Symbol("#unused#") # nameless args (e.g., `::Type{String}`)
    isexpr(ex, :kw) && return get_argname(ex.args[1])           # default value
    isexpr(ex, :(=)) && return get_argname(ex.args[1])          # default value inside `@nospecialize`
    isexpr(ex, :macrocall) && return get_argname(ex.args[end])  # @nospecialize
    isexpr(ex, :...) && return get_argname(only(ex.args))       # varargs
    isexpr(ex, :tuple) && return Symbol("")                     # tuple-destructuring
    dump(ex)
    error("unexpected argument ", ex)
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

# This regex matches the pseudo-file name of a REPL history entry.
const rREPL = r"^REPL\[(\d+)\]$"
# Match anonymous function names
const rexfanon = r"^#\d+$"
# Match kwfunc method names
const rexkwfunc = r"^#.*##kw$"

is_gensym(s::Symbol) = is_gensym(string(s))
is_gensym(str::AbstractString) = startswith(str, '#')

strip_gensym(s::Symbol) = strip_gensym(string(s))
function strip_gensym(str::AbstractString)
    if startswith(str, '#')
        idx = findnext('#', str, 2)
        if idx !== nothing
            return Symbol(str[2:idx-1])
        end
    end
    endswith(str, "##kw") && return Symbol(str[1:end-4])
    return Symbol(str)
end

if isdefined(Core, :kwcall)
    is_kw_call(m::Method) = Base.unwrap_unionall(m.sig).parameters[1] === typeof(Core.kwcall)
else
    function is_kw_call(m::Method)
        T = Base.unwrap_unionall(m.sig).parameters[1]
        return match(rexkwfunc, string(T.name.name)) !== nothing
    end
end

# is_body_fcn(m::Method, basename::Symbol) = match(Regex("^#$basename#\\d+\$"), string(m.name)) !== nothing
# function is_body_fcn(m::Method, basename::Expr)
#     basename.head == :. || return false
#     return is_body_fcn(m, get_basename(basename))
# end
# is_body_fcn(m::Method, ::Nothing) = false
# function get_basename(basename::Expr)
#     bn = basename.args[end]
#     @assert isa(bn, QuoteNode)
#     return is_body_fcn(m, bn.value)
# end

function kwmethod_basename(meth::Method)
    name = meth.name
    sname = string(name)
    mtch = match(r"^(.*)##kw$", sname)
    if mtch === nothing
        mtch = match(r"^#+(.*)#", sname)
    end
    name = mtch === nothing ? name : Symbol(only(mtch.captures))
    ftypname = Symbol(string('#', name))
    idx = findfirst(Base.unwrap_unionall(meth.sig).parameters) do @nospecialize(T)
        if isa(T, DataType)
            Tname = T.name.name
            if Tname === :Type
                p1 = Base.unwrap_unionall(T.parameters[1])
                Tname = isa(p1, DataType) ? p1.name.name :
                        isa(p1, TypeVar) ? p1.name : error("unexpected type ", typeof(p1), "for ", meth)
                return Tname == name
            end
            return ftypname === Tname
        end
        false
    end
    idx === nothing && return name, 0
    return name, idx
end

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
    isfile(origin) || return nothing
    return read(origin, String)
end

function src_from_REPL(origin::AbstractString, repl = Base.active_repl)
    hist_idx = parse(Int, origin)
    hp = repl.interface.modes[1].hist
    return hp.history[hp.start_idx+hist_idx]
end

function basepath(id::PkgId)
    id.name ∈ ("Main", "Base", "Core") && return ""
    loc = Base.locate_package(id)
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
const BUILDBOT_STDLIB_PATH = dirname(abspath(String((@which uuid1()).file), "..", "..", ".."))
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

# Robust across Julia versions
getpkgid(project::AbstractString, libname) = getpkgid(Base.project_deps_get(project, libname), libname)
getpkgid(id::PkgId, libname) = id
getpkgid(uuid::UUID, libname) = PkgId(uuid, libname)

# Because IdDict's `setindex!` uses `@nospecialize` on both the key and value, it makes
# callers vulnerable to invalidation. These convenience utilities allow callers to insulate
# themselves from invalidation. These are used by Revise.
# example package triggering invalidation: StaticArrays (new `convert(Type{Array{T,N}}, ::AbstractArray)` methods)
invoked_setindex!(dct::IdDict{K,V}, @nospecialize(val), @nospecialize(key)) where {K,V} = Base.invokelatest(setindex!, dct, val, key)::typeof(dct)
invoked_get!(::Type{T}, dct::IdDict{K,V}, @nospecialize(key)) where {K,V,T<:V} = Base.invokelatest(get!, T, dct, key)::V
