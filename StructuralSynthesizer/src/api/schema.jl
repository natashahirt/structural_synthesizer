# =============================================================================
# API Schema — JSON input/output struct definitions
# =============================================================================
#
# These structs mirror the JSON wire format. They are plain data containers
# with no Unitful quantities — conversion happens in deserialize.jl and
# serialize.jl at the boundary.
# =============================================================================

using JSON3
using StructTypes

# ─── Input Schema ────────────────────────────────────────────────────────────
# Input structs are `mutable` so that StructTypes.Mutable() can construct them
# via the no-arg constructor and then set only the fields present in JSON.
# This lets missing JSON keys fall back to @kwdef defaults.

"""Raw edge groups from JSON: `{"beams": [[1,2],...], "columns": [[3,4],...], "braces": [...]}`."""
Base.@kwdef mutable struct APIEdgeGroups
    beams::Vector{Vector{Int}} = Vector{Int}[]
    columns::Vector{Vector{Int}} = Vector{Int}[]
    braces::Vector{Vector{Int}} = Vector{Int}[]
end

"""Raw face groups from JSON (optional). Keys are category names, values are
arrays of polylines (each polyline is an array of [x,y,z] arrays)."""
const APIFaceGroups = Dict{String, Vector{Vector{Vector{Float64}}}}

"""Raw load parameters from JSON."""
Base.@kwdef mutable struct APILoads
    floor_LL_psf::Float64 = 80.0
    roof_LL_psf::Float64 = 20.0
    grade_LL_psf::Float64 = 100.0
    floor_SDL_psf::Float64 = 15.0
    roof_SDL_psf::Float64 = 15.0
    wall_SDL_psf::Float64 = 10.0
end

"""Raw floor options from JSON."""
Base.@kwdef mutable struct APIFloorOptions
    method::String = "DDM"
    deflection_limit::String = "L_360"
    punching_strategy::String = "grow_columns"
end

"""Raw material selections from JSON."""
Base.@kwdef mutable struct APIMaterials
    concrete::String = "NWC_4000"
    rebar::String = "Rebar_60"
    steel::String = "A992"
end

"""Design parameters block from JSON."""
Base.@kwdef mutable struct APIParams
    unit_system::String = "imperial"
    loads::APILoads = APILoads()
    floor_type::String = "flat_plate"
    floor_options::APIFloorOptions = APIFloorOptions()
    materials::APIMaterials = APIMaterials()
    column_type::String = "rc_rect"
    beam_type::String = "steel_w"
    fire_rating::Float64 = 0.0
    optimize_for::String = "weight"
    size_foundations::Bool = false
    foundation_soil::String = "medium_sand"
end

"""Top-level input payload from JSON."""
Base.@kwdef mutable struct APIInput
    units::String = ""
    vertices::Vector{Vector{Float64}} = Vector{Float64}[]
    edges::APIEdgeGroups = APIEdgeGroups()
    supports::Vector{Int} = Int[]
    stories_z::Vector{Float64} = Float64[]
    faces::APIFaceGroups = APIFaceGroups()
    params::APIParams = APIParams()
    geometry_hash::String = ""
end

# ─── JSON3 StructType registrations ──────────────────────────────────────────
# Use Mutable() for input types so missing JSON keys use @kwdef defaults.

StructTypes.StructType(::Type{APIEdgeGroups}) = StructTypes.Mutable()
StructTypes.StructType(::Type{APILoads}) = StructTypes.Mutable()
StructTypes.StructType(::Type{APIFloorOptions}) = StructTypes.Mutable()
StructTypes.StructType(::Type{APIMaterials}) = StructTypes.Mutable()
StructTypes.StructType(::Type{APIParams}) = StructTypes.Mutable()
StructTypes.StructType(::Type{APIInput}) = StructTypes.Mutable()

# ─── Output Schema ───────────────────────────────────────────────────────────
# Output structs are immutable (write-only, never parsed from JSON).

"""Slab result for JSON output."""
Base.@kwdef struct APISlabResult
    id::Int = 0
    thickness_in::Float64 = 0.0
    converged::Bool = true
    failure_reason::String = ""
    failing_check::String = ""
    iterations::Int = 0
    deflection_ok::Bool = true
    deflection_ratio::Float64 = 0.0
    punching_ok::Bool = true
    punching_max_ratio::Float64 = 0.0
end

"""Column result for JSON output."""
Base.@kwdef struct APIColumnResult
    id::Int = 0
    section::String = ""
    c1_in::Float64 = 0.0
    c2_in::Float64 = 0.0
    shape::String = "rectangular"
    axial_ratio::Float64 = 0.0
    interaction_ratio::Float64 = 0.0
    ok::Bool = true
end

"""Beam result for JSON output."""
Base.@kwdef struct APIBeamResult
    id::Int = 0
    section::String = ""
    flexure_ratio::Float64 = 0.0
    shear_ratio::Float64 = 0.0
    ok::Bool = true
end

"""Foundation result for JSON output."""
Base.@kwdef struct APIFoundationResult
    id::Int = 0
    length_ft::Float64 = 0.0
    width_ft::Float64 = 0.0
    depth_ft::Float64 = 0.0
    bearing_ratio::Float64 = 0.0
    ok::Bool = true
end

"""Design summary for JSON output."""
Base.@kwdef struct APISummary
    all_pass::Bool = true
    concrete_volume_ft3::Float64 = 0.0
    steel_weight_lb::Float64 = 0.0
    rebar_weight_lb::Float64 = 0.0
    embodied_carbon_kgCO2e::Float64 = 0.0
    critical_ratio::Float64 = 0.0
    critical_element::String = ""
end

"""Error response payload."""
Base.@kwdef struct APIError
    status::String = "error"
    error::String = ""
    message::String = ""
    traceback::String = ""
end

# ─── Visualization Schema ────────────────────────────────────────────────────────

"""Node position and displacement from analysis model."""
Base.@kwdef struct APIVisualizationNode
    node_id::Int = 0              # 1-based node index in analysis model
    position_ft::Vector{Float64} = [0.0, 0.0, 0.0]  # Original position [x, y, z] in feet
    displacement_ft::Vector{Float64} = [0.0, 0.0, 0.0]  # [dx, dy, dz] in feet
end

"""Frame element with connectivity and design data."""
Base.@kwdef struct APIVisualizationFrameElement
    element_id::Int = 0           # Element index in analysis model
    node_start::Int = 0            # 1-based start node index
    node_end::Int = 0              # 1-based end node index
    element_type::String = ""     # "beam", "column", "brace"
    utilization_ratio::Float64 = 0.0
    ok::Bool = true
    section_name::String = ""      # e.g., "W14x90", "16x16"
    # Section geometry for rendering
    section_type::String = ""      # "W-shape", "rectangular", "HSS_rect", "HSS_round", etc.
    section_depth_ft::Float64 = 0.0
    section_width_ft::Float64 = 0.0
    # Additional dimensions for W-shapes
    flange_width_ft::Float64 = 0.0
    web_thickness_ft::Float64 = 0.0
    flange_thickness_ft::Float64 = 0.0
    # 2D section polygon in local y-z coordinates (centroid at origin)
    # Each vertex is [y, z] in feet, where y = width direction, z = depth direction
    section_polygon::Vector{Vector{Float64}} = []  # [[y1, z1], [y2, z2], ...]
    # Interpolated deflected curve (cubic interpolation from FEA)
    original_points::Vector{Vector{Float64}} = []   # [[x,y,z], ...] original positions in feet
    displacement_vectors::Vector{Vector{Float64}} = []  # [[dx,dy,dz], ...] displacements at each point in feet
end

"""Slab geometry for sized mode (3D boxes from cell boundaries)."""
Base.@kwdef struct APISizedSlab
    slab_id::Int = 0
    boundary_vertices::Vector{Vector{Float64}} = []  # [[x,y,z], ...] cell boundary vertices in feet
    thickness_ft::Float64 = 0.0
    z_top_ft::Float64 = 0.0  # Top surface elevation
    utilization_ratio::Float64 = 0.0
    ok::Bool = true
end

"""Slab mesh for deflected mode (analysis model triangulation)."""
Base.@kwdef struct APIDeflectedSlabMesh
    slab_id::Int = 0
    vertices::Vector{Vector{Float64}} = []  # [[x,y,z], ...] original positions in feet
    vertex_displacements::Vector{Vector{Float64}} = []  # [[dx,dy,dz], ...] displacements at each vertex in feet
    faces::Vector{Vector{Int}} = []         # [[i1,i2,i3], ...] triangle indices (1-based)
    thickness_ft::Float64 = 0.0
    utilization_ratio::Float64 = 0.0
    ok::Bool = true
end

"""Complete visualization data from analysis model."""
Base.@kwdef struct APIVisualization
    nodes::Vector{APIVisualizationNode} = []
    frame_elements::Vector{APIVisualizationFrameElement} = []
    sized_slabs::Vector{APISizedSlab} = []
    deflected_slab_meshes::Vector{APIDeflectedSlabMesh} = []
    suggested_scale_factor::Float64 = 1.0
    max_displacement_ft::Float64 = 0.0
end

"""Top-level output payload."""
Base.@kwdef struct APIOutput
    status::String = "ok"
    compute_time_s::Float64 = 0.0
    summary::APISummary = APISummary()
    slabs::Vector{APISlabResult} = APISlabResult[]
    columns::Vector{APIColumnResult} = APIColumnResult[]
    beams::Vector{APIBeamResult} = APIBeamResult[]
    foundations::Vector{APIFoundationResult} = APIFoundationResult[]
    geometry_hash::String = ""
    visualization::Union{APIVisualization, Nothing} = nothing
end

StructTypes.StructType(::Type{APISlabResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIColumnResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIBeamResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIFoundationResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{APISummary}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIOutput}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIError}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIVisualizationNode}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIVisualizationFrameElement}) = StructTypes.Struct()
StructTypes.StructType(::Type{APISizedSlab}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIDeflectedSlabMesh}) = StructTypes.Struct()
StructTypes.StructType(::Type{APIVisualization}) = StructTypes.Struct()