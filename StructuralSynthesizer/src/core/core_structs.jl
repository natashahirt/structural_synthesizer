# T can be Float64 (unitless meters) or Unitful.Quantity (units included)
# Default constructor for unitless meters
# BuildingSkeleton() = BuildingSkeleton{Float64}()

mutable struct BuildingSkeleton{T}
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

    # stories
    stories::Dict{Int, Story{T}}
    stories_z::Vector{T}

    BuildingSkeleton{T}() where T = new{T}(
        Meshes.Point[], 
        Meshes.Segment[], 
        Meshes.Polygon[],
        Tuple{Int, Int}[],
        Vector{Int}[],
        Dict{Symbol, Vector{Int}}(), 
        Dict{Symbol, Vector{Int}}(), 
        Dict{Symbol, Vector{Int}}(), 
        Graphs.SimpleGraph(0),
        Dict{Int, Story{T}}(),
        T[]
    )

end

mutable struct BuildingStructure{T}
    # BIM information (allows one BuildingSkeleton to have multiple structures, e.g.)

    skeleton::BuildingSkeleton{T} # reference geometry

    # BIM/analytical data
    slabs::Vector{Slab{T}}
    slab_sections::Dict{UInt64, SlabSection{T}}

    # beams...
    # columns...
    # foundations...
    
    asap_model::Asap.Model

    BuildingStructure(skel::BuildingSkeleton{T}) where T = new{T}(
        skel,
        Slab{T}[],
        Dict{UInt64, SlabSection{T}}(),
        Asap.Model(Asap.Node[], Asap.Element[], Asap.AbstractLoad[]),
    )
    
end