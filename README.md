# CodeTracking

CodeTracking is a minimal package designed to work with (a future version of)
[Revise.jl](https://github.com/timholy/Revise.jl).
Its main purpose is to allow packages that need to know the location
(file and line number) of code that might move around as it's edited.

CodeTracking is a very lightweight dependency.

Demo:

```julia
julia> using CodeTracking

julia> m = @which sum([1,2,3])
sum(a::AbstractArray) in Base at reducedim.jl:648

julia> file, line = whereis(m)
("/home/tim/src/julia-1/usr/share/julia/base/reducedim.jl", 648)
```
