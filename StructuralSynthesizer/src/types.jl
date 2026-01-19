# Core type definitions for StructuralSynthesizer

"""Data container for a specific elevation level."""
mutable struct Story{T}
    elevation::T
    vertices::Vector{Int}
    edges::Vector{Int}
    faces::Vector{Int}
end

Story{T}(elev::T) where T = Story{T}(elev, Int[], Int[], Int[])

# =============================================================================
# Tributary Area Types
# =============================================================================

"""Tributary polygon for one edge of a cell (2D, meters)."""
struct TributaryPolygon
    edge_idx::Int
    vertices::Vector{NTuple{2, Float64}}
    area::Float64
    fraction::Float64  # of total cell area
end

"""Grouping of geometrically identical cells with same directionality."""
struct CellGroup
    hash::UInt64
    cell_indices::Vector{Int}
end

CellGroup(hash::UInt64) = CellGroup(hash, Int[])

# =============================================================================
# Cell
# =============================================================================

"""Per-face analysis data (one bay)."""
mutable struct Cell{T, A, P}
    face_idx::Int
    area::A
    span_x::T
    span_y::T
    sdl::P
    live_load::P
    self_weight::P
    # Structural direction (from parent slab)
    span_axis::Union{NTuple{3, Float64}, Nothing}
    floor_type::Symbol
    # Tributary results (one polygon per edge)
    tributary::Union{Vector{TributaryPolygon}, Nothing}
end

function Cell(face_idx::Int, area::A, span_x::T, span_y::T, 
              sdl::P, live_load::P) where {T, A, P}
    Cell{T, A, P}(face_idx, area, span_x, span_y, sdl, live_load, zero(P),
                  nothing, :unknown, nothing)
end

"""Total factored dead load (SDL + self-weight)."""
total_dead_load(c::Cell) = c.sdl * Constants.DL_FACTOR + c.self_weight * Constants.DL_FACTOR

"""Total factored pressure (SDL + LL + SW)."""
total_factored_pressure(c::Cell) = (c.sdl + c.self_weight) * Constants.DL_FACTOR + c.live_load * Constants.LL_FACTOR

"""Physical slab (one or more connected cells)."""
mutable struct Slab{T, R<:AbstractFloorResult}
    cell_indices::Vector{Int}
    result::R
    floor_type::Symbol        # :one_way, :two_way, :pt_banded, :flat_plate
    span_axis::Union{Tuple{Float64, Float64, Float64}, Nothing}
    group_id::Union{UInt64, Nothing}
end

function Slab(cell_indices::Vector{Int}, result::R; 
              floor_type=:one_way, span_axis=nothing, group_id=nothing) where {R<:AbstractFloorResult}
    # T is the length type of the result thickness
    T = typeof(StructuralSizer.total_depth(result))
    Slab{T, R}(cell_indices, result, floor_type, span_axis, group_id)
end

# Single-cell slab convenience
Slab(cell_idx::Int, result::R; kwargs...) where {R<:AbstractFloorResult} = Slab([cell_idx], result; kwargs...)

# Interface for Slab to mirror Result interface
thickness(s::Slab) = StructuralSizer.total_depth(s.result)
self_weight(s::Slab) = StructuralSizer.self_weight(s.result)
structural_effects(s::Slab) = StructuralSizer.structural_effects(s.result)

"""
Backend-agnostic edge load specs produced from slabs.

These are converted to analysis-backend loads (e.g. ASAP) in `to_asap!`.
All magnitudes are expected to be plain Float64 in base SI.
"""
abstract type AbstractEdgeLoadSpec end

"""Point loads on an edge at normalized positions `xs ∈ [0,1]` (forces in N)."""
struct EdgePointLoadSpec <: AbstractEdgeLoadSpec
    edge_idx::Int
    xs::Vector{Float64}
    F::Vector{NTuple{3, Float64}}
end

"""Constant line load on an edge (global line-load vector in N/m)."""
struct EdgeLineLoadSpec <: AbstractEdgeLoadSpec
    edge_idx::Int
    w::NTuple{3, Float64}
end

"""Optimization grouping for similar slabs."""
mutable struct SlabGroup
    hash::UInt64
    slab_indices::Vector{Int}
    material::Union{AbstractMaterial, Nothing}
end

SlabGroup(hash::UInt64) = SlabGroup(hash, Int[], nothing)

"""Per-edge analysis data (one per skeleton edge / ASAP element)."""
mutable struct Segment{T}
    edge_idx::Int
    L::T
    Lb::T
    Cb::Float64
end

function Segment(edge_idx::Int, L::T; Lb=L, Cb=1.0) where T
    Segment{T}(edge_idx, L, Lb, Float64(Cb))
end

"""Physical member (one or more connected segments)."""
mutable struct Member{T}
    segment_indices::Vector{Int}
    # Governing values for sizing
    L::T
    Lb::T
    Kx::Float64
    Ky::Float64
    Cb::Float64
    group_id::Union{UInt64, Nothing}
end

function Member(seg_indices::Vector{Int}, L::T; Lb=L, Kx=1.0, Ky=1.0, Cb=1.0, group_id=nothing) where T
    Member{T}(seg_indices, L, Lb, Float64(Kx), Float64(Ky), Float64(Cb), group_id)
end

# Single-segment member convenience
Member(seg_idx::Int, L::T; kwargs...) where T = Member([seg_idx], L; kwargs...)

"""Shared properties for a group of similar members (for optimization)."""
mutable struct MemberGroup
    hash::UInt64
    member_indices::Vector{Int}
    section::Union{AbstractSection, Nothing}
    material::Union{AbstractMaterial, Nothing}
end

MemberGroup(hash::UInt64) = MemberGroup(hash, Int[], nothing, nothing)

"""Geometric and topological representation of a building."""
mutable struct BuildingSkeleton{T} <: AbstractBuildingSkeleton
    vertices::Vector{Meshes.Point}
    edges::Vector{Meshes.Segment}
    faces::Vector{Meshes.Polygon}
    edge_indices::Vector{Tuple{Int, Int}}
    face_vertex_indices::Vector{Vector{Int}}
    face_edge_indices::Vector{Vector{Int}}
    graph::Graphs.SimpleGraph{Int}
    groups_vertices::Dict{Symbol, Vector{Int}}
    groups_edges::Dict{Symbol, Vector{Int}}
    groups_faces::Dict{Symbol, Vector{Int}}
    stories::Dict{Int, Story{T}}
    stories_z::Vector{T}

    function BuildingSkeleton{T}() where T
        new{T}(
            Meshes.Point[], Meshes.Segment[], Meshes.Polygon[],
            Tuple{Int, Int}[], Vector{Int}[], Vector{Int}[],
            Graphs.SimpleGraph(0),
            Dict{Symbol, Vector{Int}}(), Dict{Symbol, Vector{Int}}(), Dict{Symbol, Vector{Int}}(),
            Dict{Int, Story{T}}(), T[]
        )
    end
end

"""Analytical layer wrapping a BuildingSkeleton."""
mutable struct BuildingStructure{T, A, P} <: AbstractBuildingStructure
    skeleton::BuildingSkeleton{T}
    # Slabs
    cells::Vector{Cell{T, A, P}}
    cell_groups::Dict{UInt64, CellGroup}
    slabs::Vector{Slab{T, <:AbstractFloorResult}}
    slab_groups::Dict{UInt64, SlabGroup}
    # Framing
    segments::Vector{Segment{T}}
    members::Vector{Member{T}}
    member_groups::Dict{UInt64, MemberGroup}
    # Analysis
    asap_model::Asap.Model
end

function BuildingStructure(skel::BuildingSkeleton{T}) where T
    A = typeof(1.0u"m^2")
    P = typeof(1.0u"kN/m^2")
    BuildingStructure{T, A, P}(
        skel,
        Cell{T, A, P}[], Dict{UInt64, CellGroup}(),
        Slab{T, AbstractFloorResult}[], Dict{UInt64, SlabGroup}(),
        Segment{T}[], Member{T}[], Dict{UInt64, MemberGroup}(),
        Asap.Model(Asap.Node[], Asap.Element[], Asap.AbstractLoad[])
    )
end

function BuildingStructure{T, A, P}(skel::BuildingSkeleton{T}) where {T, A, P}
    BuildingStructure{T, A, P}(
        skel,
        Cell{T, A, P}[], Dict{UInt64, CellGroup}(),
        Slab{T, AbstractFloorResult}[], Dict{UInt64, SlabGroup}(),
        Segment{T}[], Member{T}[], Dict{UInt64, MemberGroup}(),
        Asap.Model(Asap.Node[], Asap.Element[], Asap.AbstractLoad[])
    )
end
