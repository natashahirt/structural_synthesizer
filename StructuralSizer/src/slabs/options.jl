# FloorOptions: user-facing configuration for floor/slab sizing
#
# Motivation:
# - Many sizing methods accept impactful keyword args (e.g. ACI support conditions),
#   but those keywords are hard to discover through higher-level APIs that forward kwargs.
# - A single structured `FloorOptions` object makes defaults explicit, composable, and
#   easier to document and introspect.

# =============================================================================
# Option structs
# =============================================================================

"""CIP (ACI 318) minimum thickness options for cast-in-place concrete slabs."""
Base.@kwdef struct CIPOptions
    support::SupportCondition = BOTH_ENDS_CONT
    # Reinforcement material used for ACI minimum thickness tables (via `material.Fy`).
    # Default corresponds to Grade 60 reinforcement.
    rebar_material::Metal = Rebar_60

    # Two-way / plate / waffle exterior conditions
    has_edge_beam::Bool = false

    # PT options
    has_drop_panels::Bool = false
end

"""Haile vault sizing options (unreinforced parabolic vault)."""
Base.@kwdef struct VaultOptions
    rise = nothing               # length (same unit as span)
    lambda::Union{Real,Nothing} = nothing
    thickness = nothing          # length (same unit as span)

    trib_depth = nothing         # length (default handled by sizing code)
    rib_depth = nothing          # length
    rib_apex_rise = nothing      # length

    finishing_load = nothing     # force/area
    allowable_stress::Union{Real,Nothing} = nothing
    deflection_limit = nothing   # length
    check_asymmetric::Union{Bool,Nothing} = nothing
end

"""
Unified options container for floor sizing.

Only the relevant sub-options for a given floor type are used.
"""
Base.@kwdef struct FloorOptions
    cip::CIPOptions = CIPOptions()
    vault::VaultOptions = VaultOptions()
end

# =============================================================================
# Guidance helpers (used for docs / discoverability)
# =============================================================================

"""
    required_floor_options(ft::AbstractFloorSystem) -> Vector{Symbol}

Return the option keys that materially affect sizing for `ft`.
This is meant for UI/help; it does not validate values.
"""
required_floor_options(::AbstractFloorSystem) = Symbol[]

required_floor_options(::OneWay) = [:cip_support, :cip_rebar_material]
required_floor_options(::TwoWay) = [:cip_support, :cip_rebar_material, :cip_has_edge_beam]
required_floor_options(::FlatPlate) = [:cip_support, :cip_rebar_material, :cip_has_edge_beam]
required_floor_options(::FlatSlab) = [:cip_support, :cip_rebar_material, :cip_has_edge_beam]
required_floor_options(::Waffle) = [:cip_support, :cip_rebar_material, :cip_has_edge_beam]
required_floor_options(::PTBanded) = [:cip_support, :cip_has_drop_panels]

required_floor_options(::Vault) = [:vault_rise_or_lambda, :vault_thickness, :vault_trib_depth, :vault_ribs, :vault_checks]

"""
    floor_options_help(ft::AbstractFloorSystem) -> String

Human-readable guidance on which `FloorOptions` fields matter for `ft`.
"""
function floor_options_help(ft::AbstractFloorSystem)
    opts = required_floor_options(ft)
    isempty(opts) && return "No special options required for $(typeof(ft))."
    return "Options for $(typeof(ft)): " * join(string.(opts), ", ")
end

