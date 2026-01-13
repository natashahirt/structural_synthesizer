# Core type definitions for StructuralSynthesizer

"""Data container for a specific elevation level."""
mutable struct Story{T}
    elevation::T
    vertices::Vector{Int}
    edges::Vector{Int}
    faces::Vector{Int}
end

Story{T}(elev::T) where T = Story{T}(elev, Int[], Int[], Int[])

"""BIM and engineering metadata shared by multiple physical slabs."""
mutable struct SlabSection{T, A, P}
    geometry_hash::UInt64
    thickness::T
    material::Union{Symbol, AbstractMaterial}
    area::A
    slab_type::Symbol
    span_axis::Union{Meshes.Vec{3, T}, Nothing}
    dead_load::P
    live_load::P
end

function SlabSection(hash::UInt64, thickness::T, material, area::A, 
                     slab_type::Symbol, span_axis, dead_load::P, live_load::P) where {T, A, P}
    axis = isnothing(span_axis) ? nothing : Meshes.Vec{3, T}(span_axis...)
    SlabSection{T, A, P}(hash, thickness, material, area, slab_type, axis, dead_load, live_load)
end

"""Individual slab instance linked to a skeleton face."""
mutable struct Slab{T, A, P}
    face_idx::Int
    section::SlabSection{T, A, P}
    beams::Vector{Int}
end

Slab(idx::Int, sec::SlabSection{T, A, P}) where {T, A, P} = Slab{T, A, P}(idx, sec, Int[])

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
    slabs::Vector{Slab{T, A, P}}
    slab_sections::Dict{UInt64, SlabSection{T, A, P}}
    asap_model::Asap.Model
end

function BuildingStructure(skel::BuildingSkeleton{T}) where T
    A = typeof(1.0u"m^2")
    P = typeof(1.0u"kN/m^2")
    BuildingStructure{T, A, P}(
        skel, Slab{T, A, P}[], Dict{UInt64, SlabSection{T, A, P}}(),
        Asap.Model(Asap.Node[], Asap.Element[], Asap.AbstractLoad[])
    )
end

function BuildingStructure{T, A, P}(skel::BuildingSkeleton{T}) where {T, A, P}
    BuildingStructure{T, A, P}(
        skel, Slab{T, A, P}[], Dict{UInt64, SlabSection{T, A, P}}(),
        Asap.Model(Asap.Node[], Asap.Element[], Asap.AbstractLoad[])
    )
end
