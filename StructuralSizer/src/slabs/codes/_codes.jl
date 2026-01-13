# Floor System Sizing Interface
# Generic functions dispatched on floor system types

# =============================================================================
# Generic Interface
# =============================================================================

"""
Size a floor system for given span and load.
Returns an AbstractFloorSection subtype appropriate to the floor system.

Dispatch signatures vary by floor type:
- CIP concrete: size_floor(::OneWay, span, load; material) → SlabSection
- Precast: size_floor(::HollowCore, span, load) → ProfileSection
- Steel deck: size_floor(::CompositeDeck, span, load; deck_mat, fill_mat) → CompositeDeckSpec
- Timber: size_floor(::CLT, span, load) → TimberPanelSection
- Custom: size_floor(::ShapedSlab, span_x, span_y, load; material) → ShapedSlabResult
"""
function size_floor end

"""
Minimum slab thickness per code tables (CIP concrete only).
Returns thickness in same units as span (or meters if unitless).
"""
function min_thickness end

"""
Required slab thickness for given loads (CIP concrete only).
More detailed calculation considering actual demands.
"""
function required_thickness end

"""
Check if slab capacity is adequate at given thickness.
Returns (ok::Bool, utilization::Float64).
"""
function check_slab_capacity end

# =============================================================================
# Constants
# =============================================================================

# Minimum thickness floor (3" = 0.075m for fire/cover, often use 5" = 0.125m practical)
const MIN_SLAB_THICKNESS = 0.125  # meters

# =============================================================================
# CIP Concrete Implementations (min_thickness based)
# =============================================================================

include("simplified.jl")
include("aci.jl")

# =============================================================================
# Other Floor System Implementations
# =============================================================================

include("concrete/_concrete.jl")
include("steel/_steel.jl")
include("timber/_timber.jl")
include("custom/_custom.jl")
