# =============================================================================
# Foundation Design Options
# =============================================================================
#
# User-facing knobs for spread, strip, and mat footing design.
# Mirrors the pattern established by FloorOptions / FlatPlateOptions.
# =============================================================================

# =============================================================================
# Mat Analysis Method Types
# =============================================================================

abstract type AbstractMatMethod end

"""Rigid mat: uniform/linear pressure, strip statics. No k_s required."""
struct RigidMat <: AbstractMatMethod end

"""Hetenyi beam-on-elastic-foundation closed-form. Requires soil.ks."""
struct Hetenyi <: AbstractMatMethod end

"""FEA plate on Winkler springs (Asap.Spring). Requires soil.ks."""
Base.@kwdef struct WinklerFEA <: AbstractMatMethod
    mesh_density::Int = 8
end

# =============================================================================
# Spread Footing Options
# =============================================================================

"""
    SpreadFootingOptions

Design parameters for ACI 318-14 spread (isolated) footing design.

All lengths stored as Unitful quantities — stripped to imperial at the
calculation boundary inside `design_spread_footing`.
"""
Base.@kwdef struct SpreadFootingOptions
    # Materials & Detailing
    material::ReinforcedConcreteMaterial = RC_4000_60
    cover::Length            = 3.0u"inch"       # ACI 7.7.1: ≥ 3" cast against soil
    bar_size::Int            = 8                 # Rebar designation (e.g. 8 → #8)

    # Column / pier interface
    pier_shape::Symbol       = :rect             # :rect or :circular
    pier_c1::Length           = 18.0u"inch"      # Column dimension parallel to L (or diameter)
    pier_c2::Length           = 18.0u"inch"      # Column dimension parallel to B (ignored for :circular)
    footing_shape::Symbol    = :rect             # :rect (square when B==L)

    # Geometry bounds
    min_depth::Length         = 12.0u"inch"      # ACI 13.3.1.2: ≥ 6" above bottom rebar
    depth_increment::Length   = 1.0u"inch"       # Round-up increment for h
    size_increment::Length    = 3.0u"inch"        # Round B,L to nearest 3"

    # Strength reduction factors — ACI 318-14 Table 21.2.1
    ϕ_flexure::Float64       = 0.90
    ϕ_shear::Float64         = 0.75
    ϕ_bearing::Float64       = 0.65              # ACI Table 21.2.1 (bearing)

    # Lightweight concrete factor (nothing → pull from material.concrete.λ)
    λ::Union{Float64, Nothing} = nothing

    # Column concrete strength (may differ from footing concrete)
    # nothing → same as footing fc'
    fc_col::Union{Pressure, Nothing} = nothing

    # Checks to perform
    check_bearing::Bool      = true              # ACI 22.8 bearing at column-footing joint
    check_dowels::Bool       = true              # Design dowel reinforcement
    check_development::Bool  = true              # Verify Ld ≤ available anchorage

    # Objective for optimization
    objective::AbstractObjective = MinVolume()
end

# =============================================================================
# Strip Footing Options
# =============================================================================

"""
    StripFootingOptions

Design parameters for ACI 318-14 strip / combined footing design.
"""
Base.@kwdef struct StripFootingOptions
    # Materials & Detailing
    material::ReinforcedConcreteMaterial = RC_4000_60
    cover::Length            = 3.0u"inch"
    bar_size_long::Int       = 7                 # Longitudinal bars
    bar_size_trans::Int      = 5                 # Transverse bars

    # Column / pier dimensions (applied at each column)
    pier_c1::Length           = 18.0u"inch"      # Column dimension along strip axis
    pier_c2::Length           = 18.0u"inch"      # Column dimension transverse to strip

    # Geometry
    min_depth::Length         = 12.0u"inch"
    depth_increment::Length   = 1.0u"inch"
    width_increment::Length   = 3.0u"inch"
    max_depth_ratio::Float64  = 0.5              # Widen B if h > ratio × B (typical h/B ≈ 0.3–0.5)

    # Analysis
    analysis::Symbol         = :rigid            # :rigid (K_r > 0.5) — only option for now

    # Strength reduction
    ϕ_flexure::Float64       = 0.90
    ϕ_shear::Float64         = 0.75
    ϕ_bearing::Float64       = 0.65
    λ::Union{Float64, Nothing} = nothing

    # Auto-merge thresholds (spread → strip)
    merge_gap_factor::Float64    = 2.5           # Merge when gap < factor × D_max
    eccentricity_limit::Float64  = 0.15          # Merge when e/L > limit

    # Objective
    objective::AbstractObjective = MinVolume()
end

# =============================================================================
# Mat Footing Options
# =============================================================================

"""
    MatFootingOptions

Design parameters for mat foundation design per ACI 336.2R.
"""
Base.@kwdef struct MatFootingOptions
    # Materials & Detailing
    material::ReinforcedConcreteMaterial = RC_4000_60
    cover::Length            = 3.0u"inch"
    bar_size_x::Int          = 8
    bar_size_y::Int          = 8

    # Geometry
    min_depth::Length         = 24.0u"inch"      # Mats typically thicker
    depth_increment::Length   = 1.0u"inch"
    edge_overhang::Union{Length, Nothing} = nothing  # nothing → auto (d or 0.5× avg span)

    # Analysis method
    analysis_method::AbstractMatMethod = RigidMat()

    # Strength reduction
    ϕ_flexure::Float64       = 0.90
    ϕ_shear::Float64         = 0.75
    λ::Union{Float64, Nothing} = nothing

    # Objective
    objective::AbstractObjective = MinVolume()
end

# =============================================================================
# Top-Level Foundation Options
# =============================================================================

"""
    FoundationOptions

Top-level container for all foundation design parameters.

# Fields
- `code`: Design code — `:aci` (ACI 318-14 / 336.2R) or `:is` (IS 456).
  Only `:aci` is wired into the auto-dispatch pipeline; IS footings can still
  be called directly via the standalone `design_spread_footing` overload.
- `strategy`: Auto-selection mode — `:auto`, `:all_spread`, `:all_strip`, `:mat`.
- `mat_coverage_threshold`: Switch to mat when coverage ratio exceeds this (default 0.50).
"""
Base.@kwdef struct FoundationOptions
    # Design code
    code::Symbol = :aci             # :aci or :is (only :aci wired for now)

    # Sub-option blocks
    spread::SpreadFootingOptions   = SpreadFootingOptions()
    strip::StripFootingOptions     = StripFootingOptions()
    mat::MatFootingOptions         = MatFootingOptions()

    # Auto-selection strategy
    strategy::Symbol = :auto        # :auto, :all_spread, :all_strip, :mat

    # Mat heuristic thresholds (used when strategy = :auto)
    mat_coverage_threshold::Float64 = 0.50  # Switch to mat if coverage > 50%
end
