# T can be Float64 (unitless meters) or Unitful.Quantity (units included)
# Default constructor for unitless meters
# StructureSkeleton() = StructureSkeleton{Float64}()

# container for data at a specific elevation
# links to main StructureSkeleton struct
mutable struct Level{T}
    elevation::T
    vertices::Vector{Int}
    edges::Vector{Int}
    faces::Vector{Int}
end
mutable struct StructureSkeleton{T}
    # raw geometry
    # three-element vector (always 3d) probably with a unit
    vertices::Vector{Meshes.Point}
    edges::Vector{Meshes.Segment}
    faces::Vector{Meshes.Polygon}

    # connectivity
    edge_indices::Vector{Tuple{Int, Int}} # stores (v1_idx, v2_idx) for each edge
    face_indices::Vector{Vector{Int}}

    # categories
    groups_vertices::Dict{Symbol, Vector{Int}} # eg :support => [1,2,4], :beams => [3,5]
    groups_edges::Dict{Symbol, Vector{Int}} # eg :columns => [1,2,4], :beams => [3,5]
    groups_faces::Dict{Symbol, Vector{Int}} # eg :rc_flat => [1,2,4], :steel_deck => [3,5]

    # topology
    graph::Graphs.SimpleGraph{Int}

    # levels
    levels::Dict{Int, Level{T}}
    floors::Vector{T}

    StructureSkeleton{T}() where T = new{T}(
        Meshes.Point[], 
        Meshes.Segment[], 
        Meshes.Polygon[],
        Tuple{Int, Int}[],
        Vector{Int}[],
        Dict{Symbol, Vector{Int}}(), 
        Dict{Symbol, Vector{Int}}(), 
        Dict{Symbol, Vector{Int}}(), 
        Graphs.SimpleGraph(0),
        Dict{Int, Level{T}}(),
        T[]
    )

end