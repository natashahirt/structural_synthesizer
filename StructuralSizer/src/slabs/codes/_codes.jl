# Sizing Logic Entry Points

"""
Common interface for floor sizing.
Each implementation should define:
    size_floor(type, span, sdl, live; material=..., **kwargs) → AbstractFloorResult
"""

# =============================================================================
# Generic Dispatch Wrappers
# =============================================================================

# Include all code implementations
include("concrete/_concrete.jl")
include("steel/_steel.jl")
include("timber/_timber.jl")
include("vault/_vault.jl")
include("custom/_custom.jl")

"""
    size_floor(st::AbstractFloorSystem, span, sdl, live; kwargs...)
Base dispatch for sizing floor systems using parametric Unitful types.
"""
function size_floor(st::AbstractFloorSystem, span, sdl, live; kwargs...)
    # This will catch cases where the specific type doesn't have an implementation
    # or doesn't match the signature.
    error("size_floor not implemented for $(typeof(st)) with arguments: span=$(typeof(span)), sdl=$(typeof(sdl)), live=$(typeof(live))")
end
