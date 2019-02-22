# CodeTracking

CodeTracking is a minimal package designed to work with (a future version of)
[Revise.jl](https://github.com/timholy/Revise.jl).
Its main purpose is to support packages that need to interact with code that might move
around as it's edited.

CodeTracking is a very lightweight dependency.

Example:

```julia
julia> using CodeTracking

julia> m = @which sum([1,2,3])
sum(a::AbstractArray) in Base at reducedim.jl:648

julia> file, line = whereis(m)
("/home/tim/src/julia-1/usr/share/julia/base/reducedim.jl", 642)
```

In this (ficticious) example, `sum` moved because I deleted a few lines higher in the file;
these didn't affect the functionality of `sum` (so we didn't need to redefine and recompile it),
but it does change the starting line number of the file at which this method appears.

Other features:

```julia
julia> using CodeTracking, ColorTypes

julia> pkgfiles(ColorTypes)
PkgFiles(ColorTypes [3da002f7-5984-5a60-b8a6-cbb66c0b333f]):
  basedir: /home/tim/.julia/packages/ColorTypes/BsAWO
  files: ["src/ColorTypes.jl", "src/types.jl", "src/traits.jl", "src/conversions.jl", "src/show.jl", "src/operations.jl"]

julia> m = @which red(RGB(1,1,1))
red(c::AbstractRGB) in ColorTypes at /home/tim/.julia/packages/ColorTypes/BsAWO/src/traits.jl:14

julia> definition(m)
:(red(c::AbstractRGB) = begin
          #= /home/tim/.julia/packages/ColorTypes/BsAWO/src/traits.jl:14 =#
          c.r
      end)

julia> definition(m, String)
"red(c::AbstractRGB   ) = c.r\n"
```

## A few details

CodeTracking won't do anything *useful* unless the user is also running Revise,
because Revise will be responsible for updating CodeTracking's internal variables.
(Using `whereis` as an example, CodeTracking will just return the
file/line info in the method itself if Revise isn't running.)

However, Revise is a fairly large (and fairly complex) package, and currently it's not
easy to discover how to extract particular kinds of information from its internal storage.
CodeTracking is designed to be the new "query" part of Revise.jl.
The aim is to have a very simple API that developers can learn in a few minutes and then
incorporate into their own packages; its lightweight nature means that they potentially gain
a lot of functionality without being forced to take a big hit in startup time.

## Status

If you want CodeTracking to do anything useful, currently you have to check out the `teh/codetracking`
branch of Revise.
