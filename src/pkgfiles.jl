"""
`MapExprFile(mapexpr, filename::String)` stores the arguments needed for
`include(mapexpr, filename)`. `mapexpr` is a function mapping `Expr` to an
`Expr`, which is applied to the parsed expressions from `filename` before
evaluation. This is sometimes used for preprocessing files before they are
loaded.

Otherwise, `MapExprFile` behaves like a string, allowing it to be used
wherever a file path is expected.
"""
struct MapExprFile <: AbstractString
    mapexpr
    filename::String
end
MapExprFile(filename::String) = MapExprFile(identity, filename)

Base.show(io::IO, mapfile::MapExprFile) =
    print(io, "MapExprFile(", mapfile.mapexpr, ", \"", mapfile.filename, "\")")

# AbstractString interface
Base.iterate(mapfile::MapExprFile) = iterate(mapfile.filename)
Base.iterate(mapfile::MapExprFile, state::Integer) = iterate(mapfile.filename, state)

Base.getindex(mapfile::MapExprFile, i::Integer) = getindex(mapfile.filename, i)

Base.ncodeunits(mapfile::MapExprFile) = ncodeunits(mapfile.filename)
Base.codeunit(mapfile::MapExprFile, i::Integer) = codeunit(mapfile.filename, i)

Base.:(==)(mapfile1::MapExprFile, mapfile2::MapExprFile) =
    (mapfile1.mapexpr == mapfile2.mapexpr) & (mapfile1.filename == mapfile2.filename)
Base.:(==)(mapfile1::MapExprFile, file2::AbstractString) = false
Base.:(==)(file1::AbstractString, mapfile2::MapExprFile) = false

# Don't lose the `mapexpr` from common path operations
Base.:(*)(mapfile::MapExprFile, path::AbstractString) =
    MapExprFile(mapfile.mapexpr, mapfile.filename * path)
Base.:(*)(path::AbstractString, mapfile::MapExprFile) =
    MapExprFile(mapfile.mapexpr, path * mapfile.filename)
# The above would be enough for `joinpath` except for its return-type assertion ::String
function Base.joinpath(mapfile::MapExprFile, path::AbstractString)
    @assert !isa(path, MapExprFile) "Cannot join MapExprFile with another MapExprFile"
    return MapExprFile(mapfile.mapexpr, joinpath(mapfile.filename, path))
end
function Base.joinpath(path::AbstractString, mapfile::MapExprFile)
    @assert !isa(path, MapExprFile) "Cannot join MapExprFile with another MapExprFile"
    return MapExprFile(mapfile.mapexpr, joinpath(path, mapfile.filename))
end
Base.normpath(mapfile::MapExprFile) = MapExprFile(mapfile.mapexpr, normpath(mapfile.filename))
Base.abspath(mapfile::MapExprFile) = MapExprFile(mapfile.mapexpr, abspath(mapfile.filename))
function Base.relpath(mapfile::MapExprFile, path::AbstractString)
    @assert !isa(path, MapExprFile) "Cannot get relative path from MapExprFile to another MapExprFile"
    return MapExprFile(mapfile.mapexpr, relpath(mapfile.filename, path))
end

"""
PkgFiles encodes information about the current location of a package.
Fields:
- `id`: the `PkgId` of the package
- `basedir`: the current base directory of the package
- `files`: a list of files (relative path to `basedir`) that define the package.

Note that `basedir` may be subsequently updated by Pkg operations such as `add` and `dev`.
"""
mutable struct PkgFiles
    id::PkgId
    basedir::String
    files::Vector{Any}    # might contain `filename::String`, `::MapExprFile`, or custom file types (https://github.com/timholy/Revise.jl/pull/680)
end

PkgFiles(id::PkgId, path::AbstractString) = PkgFiles(id, path, Any[])
PkgFiles(id::PkgId, ::Nothing) = PkgFiles(id, "")
PkgFiles(id::PkgId) = PkgFiles(id, normpath(basepath(id)))
PkgFiles(id::PkgId, files::Vector{Any}) =
    PkgFiles(id, normpath(basepath(id)), files)

# Abstraction interface
Base.PkgId(info::PkgFiles) = info.id
srcfiles(info::PkgFiles) = info.files
basedir(info::PkgFiles) = info.basedir

function Base.show(io::IO, info::PkgFiles)
    compact = get(io, :compact, false)
    if compact
        print(io, "PkgFiles(", info.id.name, ", ", info.basedir, ", ")
        show(io, info.files)
        print(io, ')')
    else
        println(io, "PkgFiles(", info.id, "):")
        println(io, "  basedir: \"", info.basedir, '"')
        print(io, "  files: ")
        show(io, info.files)
    end
end
