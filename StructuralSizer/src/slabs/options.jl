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

"""
    CIPOptions

CIP (ACI 318) options for cast-in-place concrete slabs.

# Analysis Method Options
- `analysis_method`: Analysis method for two-way slabs
  - `:mddm` - Modified Direct Design Method (simplified coefficients, fastest)
  - `:ddm` - Direct Design Method (full ACI tables, requires regular geometry)
  - `:efm` - Equivalent Frame Method (most accurate, handles irregular geometry)
  Default: `:ddm` for regular grids (compliant with ACI 8.10), `:efm` for irregular.

# Slab Grouping Strategy
- `grouping`: How to group slabs for envelope-based sizing
  - `:individual` - Size each slab separately (most economical, complex forming)
  - `:by_floor` - All slabs on same floor get same thickness (typical)
  - `:building_wide` - All slabs in building get same thickness (simplest forming)
  Default: `:by_floor`

# Strength Reduction Factors (ACI 318-14 Table 21.2.1)
- `φ_flexure`: Flexure in tension-controlled sections (default: 0.90)
- `φ_shear`: Shear and torsion (default: 0.75)
- `φ_compression`: Compression-controlled sections (default: 0.65)
- `λ`: Lightweight concrete factor (default: 1.0 for normal weight)

# Deflection Control
- `deflection_limit`: Serviceability deflection limit
  - `:L_240` - L/240 (floors with non-sensitive finishes)
  - `:L_360` - L/360 (typical floors, ACI default)
  - `:L_480` - L/480 (floors supporting sensitive elements)
  Default: `:L_360`
- `check_long_term`: Apply ACI λΔ multiplier for long-term deflection (default: true)

# EFM-Specific Options
- `efm_k_slab`: Stiffness factor for non-prismatic slab-beam (PCA Table A1, default: 4.127)
- `efm_k_col`: Stiffness factor for column in joint (PCA Table A7, default: 4.74)
- `efm_cof`: Carryover factor for non-prismatic slab-beam (default: 0.507)
- `efm_max_iterations`: Max iterations for slab↔column sizing convergence (default: 5)
- `efm_convergence_tol`: Thickness convergence tolerance as fraction (default: 0.05 = 5%)

# Reference
- ACI 318-14/19 Chapter 8 (Two-Way Slabs)
- ACI 318-14 Table 21.2.1 (Strength Reduction Factors)
- StructurePoint Design Examples
"""
Base.@kwdef struct CIPOptions
    # ─── Support Conditions ───
    support::SupportCondition = BOTH_ENDS_CONT
    
    # Reinforcement material used for ACI minimum thickness tables (via `material.Fy`).
    # Default corresponds to Grade 60 reinforcement.
    rebar_material::Metal = Rebar_60

    # Two-way / plate / waffle exterior conditions
    has_edge_beam::Bool = false

    # PT options
    has_drop_panels::Bool = false
    
    # ─── Analysis Method ───
    # :mddm = Modified DDM (simplified coefficients)
    # :ddm = Direct Design Method (full ACI tables)  
    # :efm = Equivalent Frame Method (most accurate)
    analysis_method::Symbol = :ddm
    
    # ─── Slab Grouping Strategy ───
    # :individual = each slab sized separately
    # :by_floor = all slabs on floor get max thickness
    # :building_wide = all slabs in building get max thickness
    grouping::Symbol = :by_floor
    
    # ─── Strength Reduction Factors (ACI 318-14 Table 21.2.1) ───
    φ_flexure::Float64 = 0.90       # Tension-controlled sections (moment)
    φ_shear::Float64 = 0.75         # Shear and torsion
    φ_compression::Float64 = 0.65   # Compression-controlled sections
    λ::Float64 = 1.0                # Lightweight concrete factor (1.0 = normal weight)
    
    # ─── Deflection Control ───
    deflection_limit::Symbol = :L_360  # :L_240, :L_360, :L_480
    check_long_term::Bool = true
    
    # ─── EFM Stiffness Factors ───
    # From PCA Notes on ACI 318-11 Tables A1/A7
    # These are defaults for typical flat plate geometry (c/l ≈ 0.08-0.10)
    efm_k_slab::Float64 = 4.127     # Slab-beam stiffness factor
    efm_k_col::Float64 = 4.74       # Column stiffness factor
    efm_cof::Float64 = 0.507        # Carryover factor
    efm_fem_factor::Float64 = 0.08429  # Fixed-end moment factor
    
    # ─── Iteration Control ───
    efm_max_iterations::Int = 5
    efm_convergence_tol::Float64 = 0.05  # 5% thickness change = converged
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
    
    # Material for EC calculation (uses primary if nothing)
    concrete_material::Union{Concrete, Nothing} = nothing
end

"""Composite deck options (steel deck + concrete fill)."""
Base.@kwdef struct CompositeDeckOptions
    deck_material::Metal = A992_Steel
    fill_material::Union{Concrete, Nothing} = nothing  # Uses primary if nothing
    deck_profile::String = "2VLI"
end

"""Timber panel options (CLT, DLT, NLT)."""
Base.@kwdef struct TimberOptions
    timber_material::Union{AbstractMaterial, Nothing} = nothing  # Uses primary if nothing
end

"""
    FloorOptions(; cip, vault, composite, timber, tributary_axis)

Unified options container for floor sizing and analysis.

Only the relevant sub-options for a given floor type are used.

## Fields
- `cip::CIPOptions`: ACI 318 options for cast-in-place concrete
- `vault::VaultOptions`: Haile vault sizing options
- `composite::CompositeDeckOptions`: Steel composite deck options
- `timber::TimberOptions`: Timber panel options (CLT, DLT, NLT)
- `tributary_axis`: Tributary area *computation* direction override
  - `nothing` (default): use floor type default based on `spanning_behavior(ft)`
  - `:isotropic`: force isotropic straight skeleton for edge tributaries
  - `(x, y)` tuple: custom axis direction for directed partitioning

## Important: Spanning Behavior is Intrinsic

The `spanning_behavior` of a floor type (OneWay, TwoWay, Beamless) is determined
by the floor type itself and **cannot be changed** via options. Use `spanning_behavior(ft)`
to query a floor type's intrinsic spanning behavior.

The `tributary_axis` option only affects *how tributary areas are computed* for
visualization and load application—not the underlying structural behavior.

## Examples

```julia
using StructuralSizer, StructuralSynthesizer

# Default behavior: spanning behavior comes from floor type
# OneWay → OneWaySpanning → directed tribs along span axis
# TwoWay → TwoWaySpanning → isotropic tribs
# FlatPlate → BeamlessSpanning → isotropic edge tribs + Voronoi vertex tribs
opts = FloorOptions(cip=CIPOptions(support=ONE_END_CONT))
initialize!(struc; floor_type=:flat_plate, floor_kwargs=(options=opts,))

# Query spanning behavior (intrinsic, not affected by options)
ft = floor_type(:flat_plate)
spanning_behavior(ft)  # → BeamlessSpanning()
is_beamless(ft)        # → true
requires_column_tributaries(ft)  # → true

# Force isotropic tributary computation on a one-way slab (for comparison only)
# Note: This doesn't change the spanning behavior, just how tribs are computed
opts = FloorOptions(tributary_axis=:isotropic)
initialize!(struc; floor_type=:one_way, floor_kwargs=(options=opts,))
```
"""
Base.@kwdef struct FloorOptions
    cip::CIPOptions = CIPOptions()
    vault::VaultOptions = VaultOptions()
    composite::CompositeDeckOptions = CompositeDeckOptions()
    timber::TimberOptions = TimberOptions()
    tributary_axis::Union{Nothing, Symbol, NTuple{2, Float64}} = nothing
end

# Constructor that accepts any Real values for tributary_axis and converts to Float64
function FloorOptions(cip::CIPOptions, vault::VaultOptions, composite::CompositeDeckOptions,
                      timber::TimberOptions, tributary_axis::NTuple{2, <:Real})
    FloorOptions(cip, vault, composite, timber, (Float64(tributary_axis[1]), Float64(tributary_axis[2])))
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
required_floor_options(::TwoWay) = [:cip_support, :cip_rebar_material, :cip_has_edge_beam, :cip_analysis_method]
required_floor_options(::FlatPlate) = [:cip_support, :cip_rebar_material, :cip_has_edge_beam, :cip_analysis_method, :cip_grouping]
required_floor_options(::FlatSlab) = [:cip_support, :cip_rebar_material, :cip_has_edge_beam, :cip_analysis_method, :cip_grouping]
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

# =============================================================================
# Tributary Axis Resolution
# =============================================================================

"""
    resolve_tributary_axis(ft, spans, opts) -> Union{NTuple{2,Float64}, Nothing}

Resolve the tributary axis for a floor type, respecting user override in FloorOptions.

## Returns
- `nothing`: Use isotropic straight skeleton (two-way tributary areas)
- `(x, y)` tuple: Use directed partitioning along this axis (one-way tributary areas)

## Resolution Priority
1. `opts.tributary_axis === :isotropic` → `nothing` (force isotropic)
2. `opts.tributary_axis isa NTuple{2,Float64}` → use that custom axis
3. Otherwise → `default_tributary_axis(ft, spans)` (floor type default)

## Examples

```julia
ft = OneWay()
spans = SpanInfo(verts)  # e.g., axis = (1.0, 0.0)

# Default: one-way uses span axis
resolve_tributary_axis(ft, spans, FloorOptions())  # → (1.0, 0.0)

# Override to isotropic
resolve_tributary_axis(ft, spans, FloorOptions(tributary_axis=:isotropic))  # → nothing

# Override to custom 45° axis
resolve_tributary_axis(ft, spans, FloorOptions(tributary_axis=(0.707, 0.707)))  # → (0.707, 0.707)
```
"""
function resolve_tributary_axis(ft::AbstractFloorSystem, spans, opts::FloorOptions)
    tax = opts.tributary_axis
    
    # Explicit override: force isotropic
    if tax === :isotropic
        return nothing
    end
    
    # Explicit override: custom axis (accept any Real tuple, convert to Float64)
    if tax isa NTuple{2, <:Real}
        return (Float64(tax[1]), Float64(tax[2]))
    end
    
    # Use floor type default
    return default_tributary_axis(ft, spans)
end

# =============================================================================
# Material Resolution (for EC calculation)
# =============================================================================

"""
    result_materials(result, primary_mat, opts) -> Dict{Symbol, AbstractMaterial}

Get material dict for a floor result, mapping material symbols to actual material objects.
Uses type-specific options for secondary materials, falling back to primary for unspecified.

## Example
```julia
result = CIPSlabResult(...)
mats = result_materials(result, NWC_4000, FloorOptions())
# → Dict(:concrete => NWC_4000, :steel => Rebar_60)
```
"""
function result_materials end

function result_materials(::CIPSlabResult, primary_mat, opts::FloorOptions)
    Dict{Symbol, AbstractMaterial}(
        :concrete => primary_mat,
        :steel => opts.cip.rebar_material
    )
end

function result_materials(::ProfileResult, primary_mat, opts::FloorOptions)
    Dict{Symbol, AbstractMaterial}(:concrete => primary_mat)
end

function result_materials(::CompositeDeckResult, primary_mat, opts::FloorOptions)
    Dict{Symbol, AbstractMaterial}(
        :steel => opts.composite.deck_material,
        :concrete => something(opts.composite.fill_material, primary_mat)
    )
end

function result_materials(::JoistDeckResult, primary_mat, opts::FloorOptions)
    Dict{Symbol, AbstractMaterial}(:steel => opts.composite.deck_material)
end

function result_materials(::TimberPanelResult, primary_mat, opts::FloorOptions)
    Dict{Symbol, AbstractMaterial}(
        :timber => something(opts.timber.timber_material, primary_mat)
    )
end

function result_materials(::TimberJoistResult, primary_mat, opts::FloorOptions)
    Dict{Symbol, AbstractMaterial}(
        :timber => something(opts.timber.timber_material, primary_mat)
    )
end

function result_materials(::VaultResult, primary_mat, opts::FloorOptions)
    Dict{Symbol, AbstractMaterial}(
        :concrete => something(opts.vault.concrete_material, primary_mat)
    )
end

function result_materials(::ShapedSlabResult, primary_mat, opts::FloorOptions)
    Dict{Symbol, AbstractMaterial}(:concrete => primary_mat)
end
