# The variables here get populated by Revise.jl.

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
    files::Vector{String}
end

PkgFiles(id::PkgId, path::AbstractString) = PkgFiles(id, path, String[])
PkgFiles(id::PkgId, ::Nothing) = PkgFiles(id, "")
PkgFiles(id::PkgId) = PkgFiles(id, normpath(basepath(id)))
PkgFiles(id::PkgId, files::AbstractVector{<:AbstractString}) =
    PkgFiles(id, normpath(basepath(id)), files)

# Abstraction interface
Base.PkgId(info::PkgFiles) = info.id
srcfiles(info::PkgFiles) = info.files
basedir(info::PkgFiles) = info.basedir

const method_locations = IdDict{Type,LineInfoNode}()

const method_definitions = IdDict{Type,Expr}()

const _pkgfiles = Dict{PkgId,PkgFiles}()

const method_lookup_callback = Ref{Any}(nothing)
