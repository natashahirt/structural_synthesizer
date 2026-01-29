# Floor system type hierarchy and result types

# =============================================================================
# Abstract Hierarchy
# =============================================================================

abstract type AbstractFloorSystem end

# =============================================================================
# Spanning Behavior Traits
# =============================================================================

"""
Spanning behavior trait - determines how a floor system transfers load.

This is an intrinsic property of the floor type and cannot be overridden
by user options. It determines:
- Load distribution pattern (to edges vs columns)
- Which design code provisions apply  
- Default tributary area computation method

## Subtypes
- `OneWaySpanning`: Loads span primarily in one direction to edges
- `TwoWaySpanning`: Loads distribute to all edges (two-way action)
- `BeamlessSpanning`: Loads transfer directly to columns (no beams)
"""
abstract type SpanningBehavior end

"""One-way spanning: loads distributed to edges perpendicular to span direction."""
struct OneWaySpanning <: SpanningBehavior end

"""Two-way spanning: loads distributed to all edges (isotropic behavior)."""
struct TwoWaySpanning <: SpanningBehavior end

"""Beamless: loads transfer directly to columns (flat plate, flat slab)."""
struct BeamlessSpanning <: SpanningBehavior end

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
struct ShapedSlab <: AbstractConcreteSlab
    sizing_fn::Function  # (span_x, span_y, load, material) → ShapedSlabResult
end

# =============================================================================
# Spanning Behavior Trait Implementations
# =============================================================================

"""
    spanning_behavior(ft::AbstractFloorSystem) -> SpanningBehavior

Return the spanning behavior trait for a floor type.
This is intrinsic to the floor type and cannot be overridden by options.
"""
spanning_behavior(::AbstractFloorSystem) = OneWaySpanning()  # Conservative default

# --- One-way spanning ---
spanning_behavior(::OneWay) = OneWaySpanning()
spanning_behavior(::CompositeDeck) = OneWaySpanning()
spanning_behavior(::NonCompositeDeck) = OneWaySpanning()
spanning_behavior(::JoistRoofDeck) = OneWaySpanning()
spanning_behavior(::HollowCore) = OneWaySpanning()
spanning_behavior(::CLT) = OneWaySpanning()
spanning_behavior(::DLT) = OneWaySpanning()
spanning_behavior(::NLT) = OneWaySpanning()
spanning_behavior(::MassTimberJoist) = OneWaySpanning()
spanning_behavior(::Vault) = OneWaySpanning()

# --- Two-way spanning ---
spanning_behavior(::TwoWay) = TwoWaySpanning()
spanning_behavior(::Waffle) = TwoWaySpanning()
spanning_behavior(::PTBanded) = TwoWaySpanning()

# --- Beamless (columns only) ---
spanning_behavior(::FlatPlate) = BeamlessSpanning()
spanning_behavior(::FlatSlab) = BeamlessSpanning()

# --- Shaped follows inner function ---
spanning_behavior(::ShapedSlab) = TwoWaySpanning()  # Most shaped slabs are 2-way

# Convenience query functions
"""Is this floor type one-way spanning?"""
is_one_way(ft::AbstractFloorSystem) = spanning_behavior(ft) isa OneWaySpanning

"""Is this floor type two-way spanning (to edges)?"""
is_two_way(ft::AbstractFloorSystem) = spanning_behavior(ft) isa TwoWaySpanning

"""Is this floor type beamless (loads to columns)?"""
is_beamless(ft::AbstractFloorSystem) = spanning_behavior(ft) isa BeamlessSpanning

"""Does this floor type require column tributary areas (Voronoi)?"""
requires_column_tributaries(ft::AbstractFloorSystem) = is_beamless(ft)

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
# Result Types (parametric for unit flexibility)
# =============================================================================

abstract type AbstractFloorResult end

"""CIP concrete slab result."""
struct CIPSlabResult{L, F} <: AbstractFloorResult
    thickness::L        # length
    volume_per_area::L  # length (m³/m² = m)
    self_weight::F      # force/area
end

"""Precast/catalog-based result."""
struct ProfileResult{L, F} <: AbstractFloorResult
    profile_id::String
    depth::L
    volume_per_area::L  # accounts for voids
    self_weight::F
end

"""Composite deck result."""
struct CompositeDeckResult{L, F} <: AbstractFloorResult
    deck_profile::String
    deck_depth::L
    deck_gauge::Int
    fill_depth::L
    total_depth::L
    steel_vol_per_area::L
    concrete_vol_per_area::L
    self_weight::F
end

"""Steel joist + deck result."""
struct JoistDeckResult{L, F} <: AbstractFloorResult
    joist_designation::String
    joist_depth::L
    joist_spacing::L
    deck_profile::String
    deck_depth::L
    total_depth::L
    steel_vol_per_area::L
    self_weight::F
end

"""Timber panel result (CLT, DLT, NLT)."""
struct TimberPanelResult{L, F} <: AbstractFloorResult
    panel_id::String
    depth::L
    ply_count::Int
    volume_per_area::L
    self_weight::F
end

"""Mass timber joist result."""
struct TimberJoistResult{L, F} <: AbstractFloorResult
    joist_size::String
    joist_depth::L
    joist_spacing::L
    deck_type::String
    total_depth::L
    volume_per_area::L
    self_weight::F
end

"""Vault result (includes thrust)."""
struct VaultResult{L, P, F} <: AbstractFloorResult
    thickness::L        # shell thickness
    rise::L             # crown rise
    thrust_dead::P      # horizontal thrust (dead load component)
    thrust_live::P      # horizontal thrust (live load component)
    volume_per_area::L  # concrete volume (length units = m^3/m^2)
    self_weight::F      # force/area (service)
end

# Total thrust accessor
total_thrust(r::VaultResult) = r.thrust_dead + r.thrust_live

"""Custom/shaped slab result."""
struct ShapedSlabResult{L, F} <: AbstractFloorResult
    volume_per_area::L
    self_weight::F
    thickness_fn::Union{Function, Nothing}  # (x,y) → h(x,y) for visualization
    custom::Dict{Symbol, Any}
end

ShapedSlabResult(vol::L, sw::F) where {L, F} = ShapedSlabResult{L, F}(vol, sw, nothing, Dict{Symbol,Any}())

# =============================================================================
# Common Interface
# =============================================================================

"""Self-weight (force per area)."""
self_weight(s::AbstractFloorResult) = s.self_weight

"""Total depth of floor system."""
total_depth(s::CIPSlabResult) = s.thickness
total_depth(s::ProfileResult) = s.depth
total_depth(s::CompositeDeckResult) = s.total_depth
total_depth(s::JoistDeckResult) = s.total_depth
total_depth(s::TimberPanelResult) = s.depth
total_depth(s::TimberJoistResult) = s.total_depth
total_depth(s::VaultResult) = s.thickness + s.rise
total_depth(s::ShapedSlabResult) = s.volume_per_area  # approximate

"""Volume per unit area (single-material floors)."""
volume_per_area(s::CIPSlabResult) = s.volume_per_area
volume_per_area(s::ProfileResult) = s.volume_per_area
volume_per_area(s::TimberPanelResult) = s.volume_per_area
volume_per_area(s::TimberJoistResult) = s.volume_per_area
volume_per_area(s::VaultResult) = s.volume_per_area
volume_per_area(s::ShapedSlabResult) = s.volume_per_area

# =============================================================================
# Material Volumes Interface
# =============================================================================

"""Query which materials are present in a floor result."""
materials(::CIPSlabResult) = (:concrete,)
materials(::ProfileResult) = (:concrete,)
materials(::CompositeDeckResult) = (:steel, :concrete)
materials(::JoistDeckResult) = (:steel,)
materials(::TimberPanelResult) = (:timber,)
materials(::TimberJoistResult) = (:timber,)
materials(::VaultResult) = (:concrete,)
materials(::ShapedSlabResult) = (:concrete,)

"""Get material volume per unit floor plan area."""
function volume_per_area(r::AbstractFloorResult, mat::Symbol)
    mat in materials(r) || throw(ArgumentError("$(typeof(r)) does not contain material :$mat"))
    return _volume_impl(r, Val(mat))
end

# _volume_impl returns stored values (computed at sizing time)
_volume_impl(r::CIPSlabResult, ::Val{:concrete}) = r.volume_per_area
_volume_impl(r::ProfileResult, ::Val{:concrete}) = r.volume_per_area
_volume_impl(r::CompositeDeckResult, ::Val{:steel}) = r.steel_vol_per_area
_volume_impl(r::CompositeDeckResult, ::Val{:concrete}) = r.concrete_vol_per_area
_volume_impl(r::JoistDeckResult, ::Val{:steel}) = r.steel_vol_per_area
_volume_impl(r::TimberPanelResult, ::Val{:timber}) = r.volume_per_area
_volume_impl(r::TimberJoistResult, ::Val{:timber}) = r.volume_per_area
_volume_impl(r::VaultResult, ::Val{:concrete}) = r.volume_per_area
_volume_impl(r::ShapedSlabResult, ::Val{:concrete}) = r.volume_per_area

"""Get all material volumes as a dictionary."""
function material_volumes(r::AbstractFloorResult)
    return Dict(mat => volume_per_area(r, mat) for mat in materials(r))
end

# =============================================================================
# Structural Effects Interface
# =============================================================================

"""Abstract type for non-gravity structural effects (thrust, etc.)."""
abstract type AbstractStructuralEffect end

"""Horizontal thrust from a vault or arch."""
struct LateralThrust{P} <: AbstractStructuralEffect
    dead::P
    live::P
end

"""Query structural effects from a sizing result."""
structural_effects(::AbstractFloorResult) = AbstractStructuralEffect[]
structural_effects(r::VaultResult) = [LateralThrust(r.thrust_dead, r.thrust_live)]

"""Does this floor type add structural effects beyond gravity load?"""
has_structural_effects(::AbstractFloorSystem) = false
has_structural_effects(::Vault) = true

"""Apply structural effects to the model (thrust, etc.). Default no-op."""
apply_effects!(::AbstractFloorSystem, struc, slab) = nothing

# =============================================================================
# Load Distribution Interface
# =============================================================================

"""
Describes how a floor system transfers loads to its boundary.
"""
@enum LoadDistributionType begin
    DISTRIBUTION_ONE_WAY    # Distribute to edges perpendicular to span axis
    DISTRIBUTION_TWO_WAY    # Distribute to all surrounding edges
    DISTRIBUTION_POINT      # Distribute to specific support points (e.g. columns)
    DISTRIBUTION_CUSTOM     # User defined
end

"""
    load_distribution(ft::AbstractFloorSystem) -> LoadDistributionType

Get the load distribution behavior of the floor system.
Dispatches on the spanning behavior trait.
"""
load_distribution(ft::AbstractFloorSystem) = load_distribution(spanning_behavior(ft))

# Trait-based dispatch
load_distribution(::OneWaySpanning) = DISTRIBUTION_ONE_WAY
load_distribution(::TwoWaySpanning) = DISTRIBUTION_TWO_WAY
load_distribution(::BeamlessSpanning) = DISTRIBUTION_POINT

# Override for custom types
load_distribution(::ShapedSlab) = DISTRIBUTION_CUSTOM

"""
Get the gravity load magnitude (pressure) from the result.
Returns (dead_pressure, live_pressure)
"""
function get_gravity_loads(result::AbstractFloorResult, sdl, live)
    sw = self_weight(result)
    # Ensure units are consistent (converting sw to sdl units if possible)
    # For now, assuming callers handle unit consistency or Unitful handles it.
    return (sdl + sw, live)
end

# =============================================================================
# Tributary Axis (Analysis Direction)
# =============================================================================

"""
    default_tributary_axis(ft, spans) -> Union{NTuple{2,Float64}, Nothing}

Default tributary axis for a floor type, based on its spanning behavior trait.

Returns:
- `(x, y)` tuple for one-way systems: directed partitioning along span axis
- `nothing` for two-way/beamless: isotropic straight skeleton
"""
default_tributary_axis(ft::AbstractFloorSystem, spans) = default_tributary_axis(spanning_behavior(ft), spans)

# Trait-based dispatch
default_tributary_axis(::OneWaySpanning, spans) = spans.axis     # Use span direction
default_tributary_axis(::TwoWaySpanning, spans) = nothing        # Isotropic
default_tributary_axis(::BeamlessSpanning, spans) = nothing      # Isotropic (for edge tribs)

# Convenience: no options → use floor type default
resolve_tributary_axis(ft::AbstractFloorSystem, spans) = default_tributary_axis(ft, spans)

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
    :one_way => OneWay(),
    :two_way => TwoWay(),
    :flat_plate => FlatPlate(),
    :flat_slab => FlatSlab(),
    :pt_banded => PTBanded(),
    :waffle => Waffle(),
    :hollow_core => HollowCore(),
    :vault => Vault(),
    :composite_deck => CompositeDeck(),
    :non_composite_deck => NonCompositeDeck(),
    :joist_roof_deck => JoistRoofDeck(),
    :clt => CLT(),
    :dlt => DLT(),
    :nlt => NLT(),
    :mass_timber_joist => MassTimberJoist(),
)

const FLOOR_SYMBOL_MAP = Dict{Type, Symbol}(
    typeof(v) => k for (k, v) in pairs(FLOOR_TYPE_MAP)
)

"""Convert symbol to floor type for dispatch."""
function floor_type(s::Symbol)
    haskey(FLOOR_TYPE_MAP, s) || throw(KeyError("Unknown floor type: $s"))
    return FLOOR_TYPE_MAP[s]
end

"""Convert floor type to symbol for storage."""
function floor_symbol(t::AbstractFloorSystem)
    T = typeof(t)
    haskey(FLOOR_SYMBOL_MAP, T) || throw(KeyError("Unknown floor type: $T"))
    return FLOOR_SYMBOL_MAP[T]
end

"""Infer slab type from aspect ratio."""
function infer_floor_type(span_x, span_y)
    ratio = max(span_x, span_y) / min(span_x, span_y)
    return ratio > 2.0 ? :one_way : :two_way
end
