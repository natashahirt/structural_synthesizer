# container for data at a specific elevation
# links to main BuildingSkeleton struct
mutable struct Story{T}
    elevation::T
    vertices::Vector{Int}
    edges::Vector{Int}
    faces::Vector{Int}
end

# container for engineering data of multiple slabs (e.g. one if all fifty in a structure are identical)
mutable struct SlabSection{T}
    # matching key for identical counterparts logic (from get_slab_hash)
    geometry_hash::UInt64

    # BIM metadata
    thickness::T # e.g. 10cm
    material::Symbol # can change this to a material struct? for now maybe :concrete_3000psi
    area::Unitful.Area # e.g. 100m² 

    # engineering metadata
    slab_type::Symbol # :one_way, :two_way, :isotropic
    span_axis::Union{Meshes.Vec{3, T}, Nothing} # direction of span (vector)

    dead_load::Unitful.Pressure # e.g. 50psf
    live_load::Unitful.Pressure # e.g. 100psf
end

# specific individual slabs (e.g. all fifty in a structure)
# derives from polygon but is not the same thing (has more metadata)
mutable struct Slab{T}
    face_idx::Int # link to polygon in skeleton
    section::SlabSection{T} # link to the section
    beams::Vector{Int} # relates to ASAP model element list
end