# Floor system type hierarchy and result types

# =============================================================================
# Abstract Hierarchy
# =============================================================================

abstract type AbstractFloorSystem end

# --- Concrete floors ---
abstract type AbstractConcreteSlab <: AbstractFloorSystem end

# CIP concrete subtypes (used for min_thickness dispatch)
struct OneWay <: AbstractConcreteSlab end
struct TwoWay <: AbstractConcreteSlab end
struct FlatPlate <: AbstractConcreteSlab end
struct FlatSlab <: AbstractConcreteSlab end      # with drop panels
struct PTBanded <: AbstractConcreteSlab end
struct Waffle <: AbstractConcreteSlab end

# Precast concrete
struct HollowCore <: AbstractConcreteSlab end

# Special concrete (has structural effects)
struct Vault <: AbstractConcreteSlab end

# --- Steel floors ---
abstract type AbstractSteelFloor <: AbstractFloorSystem end

struct CompositeDeck <: AbstractSteelFloor end
struct NonCompositeDeck <: AbstractSteelFloor end
struct JoistRoofDeck <: AbstractSteelFloor end

# --- Timber floors ---
abstract type AbstractTimberFloor <: AbstractFloorSystem end

struct CLT <: AbstractTimberFloor end
struct DLT <: AbstractTimberFloor end
struct NLT <: AbstractTimberFloor end
struct MassTimberJoist <: AbstractTimberFloor end

# --- Custom/Shaped ---
struct ShapedSlab <: AbstractFloorSystem
    sizing_fn::Function  # (span_x, span_y, load, material) → ShapedSlabResult
end

# =============================================================================
# Support Conditions
# =============================================================================

@enum SupportCondition begin
    SIMPLE          # simply supported
    ONE_END_CONT    # one end continuous
    BOTH_ENDS_CONT  # both ends continuous
    CANTILEVER      # cantilever
end

# =============================================================================
# Result Types (each floor system returns one of these)
# =============================================================================

abstract type AbstractFloorSection end

"""CIP concrete slab result."""
struct SlabSection <: AbstractFloorSection
    thickness::Float64
    self_weight::Float64
end

"""Precast/catalog-based result."""
struct ProfileSection <: AbstractFloorSection
    profile_id::String
    depth::Float64
    self_weight::Float64
end

"""Composite deck result."""
struct CompositeDeckSpec <: AbstractFloorSection
    deck_profile::String
    deck_depth::Float64
    deck_gauge::Int
    fill_depth::Float64
    total_depth::Float64
    self_weight::Float64
end

"""Steel joist + deck result."""
struct JoistDeckSpec <: AbstractFloorSection
    joist_designation::String
    joist_depth::Float64
    joist_spacing::Float64
    deck_profile::String
    deck_depth::Float64
    total_depth::Float64
    self_weight::Float64
end

"""Timber panel result (CLT, DLT, NLT)."""
struct TimberPanelSection <: AbstractFloorSection
    panel_id::String
    depth::Float64
    ply_count::Int
    self_weight::Float64
end

"""Mass timber joist result."""
struct TimberJoistSpec <: AbstractFloorSection
    joist_size::String
    joist_depth::Float64
    joist_spacing::Float64
    deck_type::String
    total_depth::Float64
    self_weight::Float64
end

"""Vault result (includes thrust)."""
struct VaultSection <: AbstractFloorSection
    thickness::Float64
    rise::Float64
    thrust::Float64          # horizontal thrust magnitude
    self_weight::Float64
end

"""Custom/shaped slab result."""
struct ShapedSlabResult <: AbstractFloorSection
    volume_per_area::Float64
    self_weight::Float64
    thickness_fn::Union{Function, Nothing}  # (x,y) → h(x,y) for visualization
    custom::Dict{Symbol, Any}
end

ShapedSlabResult(vol, sw) = ShapedSlabResult(vol, sw, nothing, Dict{Symbol,Any}())

# =============================================================================
# Common Interface (all result types)
# =============================================================================

"""Self-weight in force per area (kN/m² or similar)."""
self_weight(s::AbstractFloorSection) = s.self_weight

"""Total depth of floor system."""
total_depth(s::SlabSection) = s.thickness
total_depth(s::ProfileSection) = s.depth
total_depth(s::CompositeDeckSpec) = s.total_depth
total_depth(s::JoistDeckSpec) = s.total_depth
total_depth(s::TimberPanelSection) = s.depth
total_depth(s::TimberJoistSpec) = s.total_depth
total_depth(s::VaultSection) = s.thickness + s.rise
total_depth(s::ShapedSlabResult) = s.volume_per_area  # approximate

"""Volume per unit area (for carbon calculations)."""
volume_per_area(s::SlabSection) = s.thickness
volume_per_area(s::ShapedSlabResult) = s.volume_per_area
# Other types: implement as needed

# =============================================================================
# Structural Effects Interface
# =============================================================================

"""Does this floor type add structural effects beyond gravity load?"""
has_structural_effects(::AbstractFloorSystem) = false
has_structural_effects(::Vault) = true

"""Apply structural effects to the model (thrust, etc.). Default no-op."""
apply_effects!(::AbstractFloorSystem, struc, slab, section) = nothing

# =============================================================================
# Material Requirements
# =============================================================================

required_materials(::AbstractConcreteSlab) = (:concrete,)
required_materials(::CompositeDeck) = (:steel, :concrete)
required_materials(::NonCompositeDeck) = (:steel,)
required_materials(::JoistRoofDeck) = (:steel,)
required_materials(::AbstractTimberFloor) = (:timber,)
required_materials(::ShapedSlab) = ()  # user-defined

# =============================================================================
# Symbol ↔ Type Mapping
# =============================================================================

const FLOOR_TYPE_MAP = Dict{Symbol, AbstractFloorSystem}(
    # CIP Concrete
    :one_way => OneWay(),
    :two_way => TwoWay(),
    :flat_plate => FlatPlate(),
    :flat_slab => FlatSlab(),
    :pt_banded => PTBanded(),
    :waffle => Waffle(),
    # Precast
    :hollow_core => HollowCore(),
    # Special
    :vault => Vault(),
    # Steel
    :composite_deck => CompositeDeck(),
    :non_composite_deck => NonCompositeDeck(),
    :joist_roof_deck => JoistRoofDeck(),
    # Timber
    :clt => CLT(),
    :dlt => DLT(),
    :nlt => NLT(),
    :mass_timber_joist => MassTimberJoist(),
)

const FLOOR_SYMBOL_MAP = Dict{Type, Symbol}(
    v => k for (k, v) in pairs(FLOOR_TYPE_MAP) if v isa AbstractFloorSystem
)

"""Convert symbol to floor type for dispatch."""
floor_type(s::Symbol) = get(FLOOR_TYPE_MAP, s, OneWay())

"""Convert floor type to symbol for storage."""
floor_symbol(t::AbstractFloorSystem) = get(FLOOR_SYMBOL_MAP, typeof(t), :one_way)

# Legacy aliases for backwards compatibility
const slab_type = floor_type
const slab_symbol = floor_symbol
const AbstractSlabType = AbstractConcreteSlab
const SLAB_TYPE_MAP = FLOOR_TYPE_MAP
const SLAB_SYMBOL_MAP = FLOOR_SYMBOL_MAP

"""Infer CIP slab type from aspect ratio."""
function infer_slab_type(span_x::Real, span_y::Real)
    ratio = max(span_x, span_y) / min(span_x, span_y)
    return ratio > 2.0 ? :one_way : :two_way
end
