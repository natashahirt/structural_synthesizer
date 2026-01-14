# Floor System Sizing Interface
# Generic functions dispatched on floor system types

# =============================================================================
# Generic Interface
# =============================================================================

"""
Size a floor system for given span and load.
Returns an AbstractFloorResult subtype appropriate to the floor system.

## Unified Signature
    size_floor(type, span, load; material=..., **kwargs) → AbstractFloorResult

All floor types use positional args (type, span, load) plus keyword args.

## Type-Specific Keywords
- CIP concrete: `support`, `fy_ksi`, `has_edge_beam`
- HollowCore: `fire_rating`
- Vault: `rise` (required)
- ShapedSlab: `span_y` (defaults to span)
- CompositeDeck: `deck_mat`, `fill_mat`
- Timber: `fire_rating`, `spacing`, `deck_type`

## Examples
    size_floor(OneWay(), 6.0, 5.0; material=NWC_4000)
    size_floor(Vault(), 8.0, 3.0; material=NWC_4000, rise=2.0)
    size_floor(CLT(), 5.0, 4.0; fire_rating=2)
"""
function size_floor end

"""
Minimum slab thickness per code tables (CIP concrete only).
Internal helper - use `size_floor` for the public API.
"""
function min_thickness end

# =============================================================================
# Constants
# =============================================================================

# Minimum thickness floor (3" = 0.075m for fire/cover, often use 5" = 0.125m practical)
const MIN_SLAB_THICKNESS = 0.125  # meters

# =============================================================================
# Floor System Implementations
# =============================================================================

include("concrete/_concrete.jl")
include("vault/_vault.jl")
include("steel/_steel.jl")
include("timber/_timber.jl")
include("custom/_custom.jl")

# =============================================================================
# Generic Unitful Overloads (single location for all types)
# =============================================================================

# size_floor with Unitful span
function size_floor(st::AbstractFloorSystem, span::Unitful.Length, load::Real; kwargs...)
    result = size_floor(st, ustrip(u"m", span), load; kwargs...)
    return result  # Result types already use Float64 internally
end

# min_thickness with Unitful span (internal helper, CIP concrete only)
function min_thickness(st::AbstractConcreteSlab, span::Unitful.Length, mat::Concrete; kwargs...)
    h_m = min_thickness(st, ustrip(u"m", span), mat; kwargs...)
    return h_m * u"m"
end
