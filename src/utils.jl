function isfuncexpr(ex)
    ex.head == :function && return true
    if ex.head == :(=)
        a = ex.args[1]
        if isa(a, Expr)
            while a.head == :where
                a = a.args[1]
                isa(a, Expr) || return false
            end
            a.head == :call && return true
        end
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
    ex.head == :line && return ex.args[1], true
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

function basepath(id::PkgId)
    id.name ∈ ("Main", "Base", "Core") && return ""
    loc = Base.locate_package(id)
    loc === nothing && return ""
    return dirname(dirname(loc))
end
