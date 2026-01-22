# Foundation type hierarchy and result types

# =============================================================================
# Abstract Hierarchy
# =============================================================================

abstract type AbstractFoundation end

# --- Shallow Foundations ---
abstract type AbstractShallowFoundation <: AbstractFoundation end

struct SpreadFooting <: AbstractShallowFoundation end
struct CombinedFooting <: AbstractShallowFoundation end
struct StripFooting <: AbstractShallowFoundation end
struct MatFoundation <: AbstractShallowFoundation end

# --- Deep Foundations ---
abstract type AbstractDeepFoundation <: AbstractFoundation end

struct DrivenPile <: AbstractDeepFoundation end
struct DrilledShaft <: AbstractDeepFoundation end
struct Micropile <: AbstractDeepFoundation end

# =============================================================================
# Soil Properties
# =============================================================================

"""
    Soil{T_P, T_D}

Geotechnical soil parameters for foundation design.

# Fields
- `qa`: Allowable bearing capacity (pressure)
- `γ`: Unit weight (force/volume)
- `ϕ`: Internal friction angle (degrees)
- `c`: Cohesion (pressure)
- `Es`: Soil elastic modulus (pressure) for settlement
- `qs`: Unit skin friction for piles (pressure), optional
- `qp`: Unit end bearing for piles (pressure), optional
"""
struct Soil{T_P, T_D}
    qa::T_P         # Allowable bearing capacity
    γ::T_D          # Unit weight
    ϕ::Float64      # Friction angle (degrees)
    c::T_P          # Cohesion
    Es::T_P         # Soil modulus
    qs::Union{T_P, Nothing}  # Skin friction (piles)
    qp::Union{T_P, Nothing}  # End bearing (piles)
end

function Soil(qa, γ, ϕ, c, Es; qs=nothing, qp=nothing)
    Soil{typeof(qa), typeof(γ)}(qa, γ, Float64(ϕ), c, Es, qs, qp)
end

# Common soil presets
const LOOSE_SAND = Soil(
    75.0u"kPa",         # qa
    16.0u"kN/m^3",      # γ
    28.0,               # ϕ
    0.0u"kPa",          # c
    10.0u"MPa"          # Es
)

const MEDIUM_SAND = Soil(
    150.0u"kPa",        # qa
    18.0u"kN/m^3",      # γ
    32.0,               # ϕ
    0.0u"kPa",          # c
    25.0u"MPa"          # Es
)

const DENSE_SAND = Soil(
    300.0u"kPa",        # qa
    20.0u"kN/m^3",      # γ
    38.0,               # ϕ
    0.0u"kPa",          # c
    50.0u"MPa"          # Es
)

const SOFT_CLAY = Soil(
    50.0u"kPa",         # qa
    16.0u"kN/m^3",      # γ
    0.0,                # ϕ
    25.0u"kPa",         # c (undrained shear strength)
    5.0u"MPa"           # Es
)

const STIFF_CLAY = Soil(
    150.0u"kPa",        # qa
    19.0u"kN/m^3",      # γ
    0.0,                # ϕ
    75.0u"kPa",         # c
    20.0u"MPa"          # Es
)

const HARD_CLAY = Soil(
    300.0u"kPa",        # qa
    21.0u"kN/m^3",      # γ
    0.0,                # ϕ
    150.0u"kPa",        # c
    50.0u"MPa"          # Es
)

# =============================================================================
# Result Types
# =============================================================================

abstract type AbstractFoundationResult end

"""
    SpreadFootingResult{L, V, F}

Design result for a spread (isolated) footing.

# Fields
- `B`: Footing width (square) or length
- `L`: Footing length (for rectangular; equals B for square)
- `D`: Footing depth/thickness
- `d`: Effective depth (to centroid of rebar)
- `As`: Rebar area per unit width
- `rebar_count`: Number of bars each way
- `rebar_dia`: Rebar diameter
- `concrete_volume`: Total concrete volume
- `steel_volume`: Total rebar volume
- `utilization`: Bearing pressure ratio (demand/capacity)
"""
struct SpreadFootingResult{L, V, F} <: AbstractFoundationResult
    B::L                # Width
    L_ftg::L            # Length (L_ftg to avoid conflict with L type param)
    D::L                # Depth/thickness
    d::L                # Effective depth
    As::typeof(1.0u"mm^2/m")  # Rebar area per unit width
    rebar_count::Int    # Number of bars each direction
    rebar_dia::L        # Rebar diameter
    concrete_volume::V  # Total concrete
    steel_volume::V     # Total rebar
    utilization::Float64
end

"""
    CombinedFootingResult{L, V, F}

Design result for a combined footing supporting multiple columns.
"""
struct CombinedFootingResult{L, V, F} <: AbstractFoundationResult
    B::L                # Width
    L_ftg::L            # Length
    D::L                # Depth
    d::L                # Effective depth
    As_bot::typeof(1.0u"mm^2/m")  # Bottom rebar (tension)
    As_top::typeof(1.0u"mm^2/m")  # Top rebar (for hogging moment)
    concrete_volume::V
    steel_volume::V
    utilization::Float64
end

"""
    PileCapResult{L, V}

Design result for a pile group with cap.
"""
struct PileCapResult{L, V} <: AbstractFoundationResult
    n_piles::Int        # Number of piles
    pile_dia::L         # Pile diameter
    pile_length::L      # Pile embedment length
    pile_spacing::L     # Center-to-center spacing
    cap_B::L            # Pile cap width
    cap_L::L            # Pile cap length  
    cap_D::L            # Pile cap depth
    concrete_volume::V  # Cap + piles (if cast-in-place)
    steel_volume::V     # Reinforcement volume
    utilization::Float64
end

# =============================================================================
# Common Interface
# =============================================================================

"""Concrete volume of foundation."""
concrete_volume(r::AbstractFoundationResult) = r.concrete_volume

"""Steel/rebar volume of foundation."""
steel_volume(r::AbstractFoundationResult) = r.steel_volume

"""Overall footprint area."""
footprint_area(r::SpreadFootingResult) = r.B * r.L_ftg
footprint_area(r::CombinedFootingResult) = r.B * r.L_ftg
footprint_area(r::PileCapResult) = r.cap_B * r.cap_L

"""Utilization ratio (demand/capacity)."""
utilization(r::AbstractFoundationResult) = r.utilization

# =============================================================================
# Foundation Demand
# =============================================================================

"""
    FoundationDemand{F, M}

Reaction forces from structural analysis at a support node.

# Fields
- `Pu`: Factored axial load (compression positive)
- `Mux`: Factored moment about x-axis
- `Muy`: Factored moment about y-axis
- `Vux`: Factored shear in x
- `Vuy`: Factored shear in y
- `Ps`: Service axial load (for settlement)
"""
struct FoundationDemand{F, M}
    group_idx::Int
    Pu::F       # Factored axial (compression +)
    Mux::M      # Moment about x
    Muy::M      # Moment about y
    Vux::F      # Shear x
    Vuy::F      # Shear y
    Ps::F       # Service axial (for settlement)
end

function FoundationDemand(idx::Int; 
                          Pu=0.0u"kN", Mux=0.0u"kN*m", Muy=0.0u"kN*m",
                          Vux=0.0u"kN", Vuy=0.0u"kN", Ps=0.0u"kN")
    FoundationDemand{typeof(Pu), typeof(Mux)}(idx, Pu, Mux, Muy, Vux, Vuy, Ps)
end

# =============================================================================
# Symbol ↔ Type Mapping
# =============================================================================

const FOUNDATION_TYPE_MAP = Dict{Symbol, AbstractFoundation}(
    :spread => SpreadFooting(),
    :combined => CombinedFooting(),
    :strip => StripFooting(),
    :mat => MatFoundation(),
    :driven_pile => DrivenPile(),
    :drilled_shaft => DrilledShaft(),
    :micropile => Micropile(),
)

const FOUNDATION_SYMBOL_MAP = Dict{Type, Symbol}(
    typeof(v) => k for (k, v) in pairs(FOUNDATION_TYPE_MAP)
)

"""Convert symbol to foundation type for dispatch."""
function foundation_type(s::Symbol)
    haskey(FOUNDATION_TYPE_MAP, s) || throw(KeyError("Unknown foundation type: $s"))
    return FOUNDATION_TYPE_MAP[s]
end

"""Convert foundation type to symbol for storage."""
function foundation_symbol(t::AbstractFoundation)
    T = typeof(t)
    haskey(FOUNDATION_SYMBOL_MAP, T) || throw(KeyError("Unknown foundation type: $T"))
    return FOUNDATION_SYMBOL_MAP[T]
end
