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
struct Grade <: AbstractConcreteSlab end         # slab on grade (ground floor)

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
# Vault Analysis Methods
# =============================================================================

"""
    VaultAnalysisMethod

Abstract type for vault analysis methods. Allows dispatch between
analytical solutions and FEA-based approaches.

## Subtypes
- `HaileAnalytical`: Haile's 3-hinge parabolic arch (closed-form)
- `ShellFEA`: Shell finite element analysis (future)
"""
abstract type VaultAnalysisMethod end

"""
Haile's analytical method for unreinforced parabolic vaults.

Uses 3-hinge arch theory with elastic shortening correction.
Valid for parabolic intrados under uniform distributed load.

Reference: Haile method for three-hinge parabolic arch analysis.
"""
struct HaileAnalytical <: VaultAnalysisMethod end

"""
Shell FEA analysis for vault stress (future implementation).

Placeholder for FinEtools-based shell analysis for validation
and non-standard geometries.
"""
struct ShellFEA <: VaultAnalysisMethod end

# =============================================================================
# Flat Plate Analysis Methods
# =============================================================================
#
# Defined here (slab-level types) so that options.jl can reference them
# before codes/ is included.  Concrete subtypes live alongside the abstract
# type for locality.
#
# Reference: ACI 318-11 §13.6 (DDM), §13.7 (EFM)
# =============================================================================

"""
    FlatPlateAnalysisMethod

Abstract type for flat plate moment analysis methods.

Subtypes:
- `DDM`: Direct Design Method (ACI 318 coefficient-based)
- `EFM`: Equivalent Frame Method (stiffness-based frame analysis)
- `FEA`: Finite Element Analysis (shell model)
"""
abstract type FlatPlateAnalysisMethod end

"""
    DDM(variant::Symbol = :full)

Direct Design Method - ACI 318 coefficient-based moment distribution.

# Variants
- `:full` - Full ACI 318 Table 8.10.4.2 coefficients with l₂/l₁ interpolation
- `:simplified` - Modified DDM (0.65/0.35 simplified coefficients)

# Reference
- ACI 318-11 §13.6
"""
struct DDM <: FlatPlateAnalysisMethod
    variant::Symbol
    
    function DDM(variant::Symbol = :full)
        variant in (:full, :simplified) || error("DDM variant must be :full or :simplified")
        new(variant)
    end
end

"""
    EFM(; solver=:asap, column_stiffness=:Kec, cracked_columns=false, pattern_loading=true)

Equivalent Frame Method — stiffness-based frame analysis with composable options.

# Solver
- `:asap` — ASAP structural analysis (direct stiffness, default)
- `:hardy_cross` — Hardy Cross moment distribution

# Column Stiffness (`column_stiffness`)
- `:Kec` — Equivalent column stiffness with torsional reduction (standard ACI §13.7).
  `Kec = Kc×Kt/(Kc+Kt)`, where Kt is the torsional member stiffness.
- `:Kc`  — Raw column flexural stiffness (no torsional reduction). Provides a
  comparison point between standard EFM and FEA.

# Cracked Columns (`cracked_columns`)
- `false` (default) — Gross Ig for column stubs (PCA/ACI §13.7 convention).
  Matches Hardy Cross cross-validation.
- `true`  — 0.70 Ig for column stubs (ACI 318-11 §10.10.4.1).
  Provides a direct comparison with FEA column modeling.
  Only affects the `:asap` solver; Hardy Cross always uses gross Ig.

# Pattern Loading (`pattern_loading`)
- `true` (default) — Enable ACI 318-11 §13.7.6 checkerboard pattern loading.
- `false` — Full load on all spans (for direct comparison with DDM).

# Combinations
| Constructor                                               | Torsion | Cracking | Notes                    |
|-----------------------------------------------------------|---------|----------|--------------------------|
| `EFM()`                                                   | Kec     | Gross Ig | Standard EFM             |
| `EFM(column_stiffness=:Kc)`                               | Kc      | Gross Ig | Isolates torsion effect  |
| `EFM(column_stiffness=:Kc, cracked_columns=true)`         | Kc      | 0.70 Ig  | Matches FEA convention   |
| `EFM(solver=:hardy_cross)`                                | Kec     | Gross Ig | StructurePoint match     |
| `EFM(solver=:hardy_cross, column_stiffness=:Kc)`          | Kc      | Gross Ig | HC without torsion       |
| `EFM(cracked_columns=true)`                               | Kec     | 0.70 Ig  | Cracked + torsion        |

# Reference
- ACI 318-11 §13.7, PCA Notes on ACI 318-11 Appendix 20A
"""
struct EFM <: FlatPlateAnalysisMethod
    solver::Symbol
    column_stiffness::Symbol
    cracked_columns::Bool
    pattern_loading::Bool

    function EFM(;
        solver::Symbol = :asap,
        column_stiffness::Symbol = :Kec,
        cracked_columns::Bool = false,
        pattern_loading::Bool = true,
    )
        solver in (:asap, :hardy_cross) ||
            error("EFM solver must be :asap or :hardy_cross, got :$solver")
        column_stiffness in (:Kec, :Kc) ||
            error("EFM column_stiffness must be :Kec or :Kc, got :$column_stiffness")
        if cracked_columns && solver == :hardy_cross
            @warn "cracked_columns=true has no effect with :hardy_cross solver (PCA uses gross Ig)"
        end
        new(solver, column_stiffness, cracked_columns, pattern_loading)
    end
end

"""
    FEA(; target_edge=nothing, pattern_loading=true)

Finite Element Analysis — 2D shell model with column stubs.

No geometric restrictions — works for any slab shape or column layout.

# Options
- `target_edge::Length`: Target mesh edge length (default: adaptive from span).
- `pattern_loading::Bool`: Enable ACI 318-11 §13.7.6 pattern loading amplification (default: `true`).
  FEA uses EFM-derived amplification factors (always ≥ 1.0, conservative).
  Set to `false` for direct comparison with DDM which uses fixed coefficients.

# Reference
- ACI 318-11 §13.2.1
"""
struct FEA <: FlatPlateAnalysisMethod
    target_edge::Union{Nothing, typeof(1.0u"m")}
    pattern_loading::Bool

    function FEA(; target_edge::Union{Nothing, Unitful.Length} = nothing, pattern_loading::Bool = true)
        if target_edge !== nothing
            ustrip(u"m", target_edge) > 0 || error("FEA target_edge must be > 0")
            new(uconvert(u"m", target_edge), pattern_loading)
        else
            new(nothing, pattern_loading)
        end
    end
end

"""
    RuleOfThumb <: FlatPlateAnalysisMethod

Rule-of-thumb slab sizing: use ACI `min_thickness`, run one pass of all
design checks, and report results even when checks fail.

Wraps an underlying analysis method (default: simplified DDM) for moment
analysis.  The slab thickness is NOT iterated — it is fixed at the ACI
minimum, and each check result (punching, deflection, shear, flexure) is
recorded regardless of pass/fail.

# Fields
- `analysis`: Underlying moment analysis method (default `DDM(:simplified)`)

# Example
```julia
RuleOfThumb()                      # uses DDM(:simplified) internally
RuleOfThumb(FEA())                 # uses FEA for moments
```
"""
struct RuleOfThumb <: FlatPlateAnalysisMethod
    analysis::FlatPlateAnalysisMethod
end
RuleOfThumb() = RuleOfThumb(DDM(:simplified))

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

"""
    VaultResult{L, P, F}

Vault sizing result with geometry, thrust, and design checks.

# Geometry
- `thickness`: Shell thickness
- `rise`: Crown rise (final, after elastic shortening)
- `arc_length`: Parabolic arc length (for material takeoff)

# Thrust (line loads at supports, perpendicular to span)
- `thrust_dead`: Horizontal thrust from dead load
- `thrust_live`: Horizontal thrust from live load

# Material
- `volume_per_area`: Concrete volume per plan area [L³/L² = L]
- `self_weight`: Self-weight pressure [F/L²]

# Analysis
- `σ_max`: Maximum compressive stress [MPa]
- `governing_case`: Which load case governs (`:symmetric` or `:asymmetric`)

# Design Checks
- `stress_check`: Named tuple with `(σ, σ_allow, ratio, ok)`
- `deflection_check`: Named tuple with `(δ, limit, ratio, ok)`
- `convergence_check`: Named tuple with `(converged, iterations)`
"""
struct VaultResult{L, P, F} <: AbstractFloorResult
    # Geometry
    thickness::L
    rise::L
    arc_length::L
    
    # Thrust (line loads at supports)
    thrust_dead::P
    thrust_live::P
    
    # Material
    volume_per_area::L
    self_weight::F
    
    # Analysis outputs
    σ_max::Float64
    governing_case::Symbol
    
    # Design checks (structured like FlatPlatePanelResult)
    stress_check::NamedTuple{(:σ, :σ_allow, :ratio, :ok), Tuple{Float64, Float64, Float64, Bool}}
    deflection_check::NamedTuple{(:δ, :limit, :ratio, :ok), Tuple{Float64, Float64, Float64, Bool}}
    convergence_check::NamedTuple{(:converged, :iterations), Tuple{Bool, Int}}
end

# Accessors
total_thrust(r::VaultResult) = r.thrust_dead + r.thrust_live

"""Check if vault design passes all checks."""
is_adequate(r::VaultResult) = r.stress_check.ok && r.deflection_check.ok && r.convergence_check.converged

"""Custom/shaped slab result."""
struct ShapedSlabResult{L, F} <: AbstractFloorResult
    volume_per_area::L
    self_weight::F
    thickness_fn::Union{Function, Nothing}  # (x,y) → h(x,y) for visualization
    custom::Dict{Symbol, Any}
end

ShapedSlabResult(vol::L, sw::F) where {L, F} = ShapedSlabResult{L, F}(vol, sw, nothing, Dict{Symbol,Any}())

# =============================================================================
# Shear Stud Design (for Punching Shear Reinforcement)
# =============================================================================

"""
    ShearStudDesign

Per-column shear stud design per ACI 318-11 §11.11.5 / Ancon Shearfix.

# Fields
- `required`: Whether studs are needed for this column
- `stud_diameter`: Stud diameter (typically 3/8" or 1/2")
- `fyt`: Stud yield strength (from material)
- `n_rails`: Number of stud rails (min 8 for interior, 4-6 for edge/corner)
- `n_studs_per_rail`: Studs per rail (determines shear-reinforced zone extent)
- `s0`: First stud spacing from column face (0.35d to 0.5d)
- `s`: Subsequent spacing (≤ 0.75d, or ≤ 0.5d if high stress)
- `Av_per_line`: Total stud area per peripheral line
- `vs`: Steel contribution to shear stress
- `vcs`: Concrete contribution with studs (reduced)
- `vc_max`: Compression strut limit
- `outer_ok`: Whether outer critical section passes

# Reference
- ACI 318-11 §11.11.5
- Ancon Shearfix Design Manual (adapted to ACI 318-11)
"""
Base.@kwdef struct ShearStudDesign{L<:Asap.Length, A<:Asap.Area, P<:Asap.Pressure}
    required::Bool = false
    catalog_name::Symbol = :generic  # :generic, :incon_iss, :ancon_shearfix
    stud_diameter::L = 0.5u"inch"
    fyt::P = 51000.0u"psi"
    n_rails::Int = 0
    n_studs_per_rail::Int = 0
    s0::L = 0.0u"inch"              # First spacing (from column face)
    s::L = 0.0u"inch"               # Subsequent spacing
    Av_per_line::A = 0.0u"inch^2"   # Total stud area per peripheral line
    vs::P = 0.0u"psi"               # Steel contribution
    vcs::P = 0.0u"psi"              # Reduced concrete contribution
    vc_max::P = 0.0u"psi"           # Compression strut limit
    outer_ok::Bool = true           # Outer critical section passes
end

"""Check if stud design is adequate."""
is_adequate(s::ShearStudDesign) = !s.required || (s.n_rails > 0 && s.outer_ok)

# =============================================================================
# Closed Stirrup Design (for Punching Shear Reinforcement)
# =============================================================================

"""
    ClosedStirrupDesign

Per-column closed stirrup design for punching shear per ACI 318-11 §11.11.3.

# Key differences from headed studs (§11.11.5):
- Vc capped at 2λ√f'c (vs 3λ√f'c for studs)
- Vn capped at 6√f'c·b0·d (vs 8√f'c for studs)
- Minimum d ≥ 6 in. and d ≥ 16·d_b
- Anchorage per §12.13 (difficult in slabs < 10 in.)

# Fields
- `required`: Whether stirrups are needed
- `bar_size`: Stirrup bar designation (#3, #4, etc.)
- `fyt`: Stirrup yield strength
- `n_legs`: Number of stirrup legs per peripheral line
- `n_lines`: Number of peripheral lines (determines reinforced zone extent)
- `s0`: First stirrup spacing from column face (≤ d/2)
- `s`: Subsequent radial spacing (≤ d/2)
- `Av_per_line`: Total stirrup area per peripheral line (n_legs × Ab)
- `vs`: Steel contribution to shear stress (psi)
- `vcs`: Concrete contribution with stirrups (capped at 2λ√f'c, psi)
- `vc_max`: Maximum nominal shear stress (6√f'c, psi)
- `outer_ok`: Whether outer critical section (d/2 beyond last line) passes

# Reference
- ACI 318-11 §11.11.3
"""
Base.@kwdef struct ClosedStirrupDesign{L<:Asap.Length, A<:Asap.Area, P<:Asap.Pressure}
    required::Bool = false
    bar_size::Int = 3                   # Stirrup bar designation (#3, #4, etc.)
    fyt::P = 60000.0u"psi"
    n_legs::Int = 0                     # Legs per peripheral line
    n_lines::Int = 0                    # Number of peripheral lines
    s0::L = 0.0u"inch"                 # First spacing from column face
    s::L = 0.0u"inch"                  # Radial spacing
    Av_per_line::A = 0.0u"inch^2"      # Total stirrup area per line
    vs::P = 0.0u"psi"                  # Steel contribution
    vcs::P = 0.0u"psi"                 # Reduced concrete contribution
    vc_max::P = 0.0u"psi"              # 6√f'c limit
    outer_ok::Bool = true
end

"""Check if stirrup design is adequate."""
is_adequate(s::ClosedStirrupDesign) = !s.required || (s.n_legs > 0 && s.outer_ok)

# =============================================================================
# Shear Cap Design (for Punching Shear Reinforcement)
# =============================================================================

"""
    ShearCapDesign

Per-column shear cap design for punching shear per ACI 318-11 §13.2.6.

A shear cap is a localized thickening below the slab at the column.
It increases the effective depth `d` and the critical perimeter `b0`
by moving the critical section to `d/2` from the cap edge.

# Geometry Rule (§13.2.6)
The cap must extend horizontally from the column face at least the
projection depth: `extent ≥ h_cap`.

# Fields
- `required`: Whether a shear cap is needed
- `h_cap`: Projection depth below the slab soffit
- `extent`: Horizontal extent from column face (≥ h_cap)
- `d_eff`: Effective depth at the cap (d_slab + h_cap)
- `b0_cap`: Critical perimeter at d_eff/2 from cap edge
- `ratio`: vu / φvc at the cap critical section
- `ok`: Whether the cap resolves punching

# Reference
- ACI 318-11 §13.2.6, §11.11.1.2(b)
"""
Base.@kwdef struct ShearCapDesign{L<:Asap.Length}
    required::Bool = false
    h_cap::L = 0.0u"inch"              # Projection below slab
    extent::L = 0.0u"inch"             # Horizontal extent from column face
    d_eff::L = 0.0u"inch"              # Effective depth at cap
    b0_cap::L = 0.0u"inch"             # Critical perimeter at cap edge
    ratio::Float64 = 0.0               # vu / φvc
    ok::Bool = true
end

"""Check if shear cap design is adequate."""
is_adequate(s::ShearCapDesign) = !s.required || s.ok

# =============================================================================
# Column Capital Design (for Punching Shear Reinforcement)
# =============================================================================

"""
    ColumnCapitalDesign

Per-column capital design for punching shear per ACI 318-11 §13.1.2.

A column capital is a flared enlargement of the column head. The effective
support area is defined by the 45° cone/pyramid rule: the capital increases
the effective column dimensions by `2 × h_cap` in each direction.

# 45° Rule (§13.1.2)
Effective support = intersection of slab soffit with the largest right
circular cone / right pyramid whose surfaces are within the column and
capital, oriented ≤ 45° to the column axis.

# Fields
- `required`: Whether a capital is needed
- `h_cap`: Capital projection below the slab soffit
- `c1_eff`: Effective column dimension in direction 1 (c1 + 2·h_cap)
- `c2_eff`: Effective column dimension in direction 2 (c2 + 2·h_cap)
- `b0_eff`: Critical perimeter using effective dimensions
- `ratio`: vu / φvc at the effective critical section
- `ok`: Whether the capital resolves punching

# Reference
- ACI 318-11 §13.1.2
"""
Base.@kwdef struct ColumnCapitalDesign{L<:Asap.Length}
    required::Bool = false
    h_cap::L = 0.0u"inch"              # Capital projection below slab
    c1_eff::L = 0.0u"inch"             # Effective c1 (c1 + 2·h_cap)
    c2_eff::L = 0.0u"inch"             # Effective c2 (c2 + 2·h_cap)
    b0_eff::L = 0.0u"inch"             # Critical perimeter with capital
    ratio::Float64 = 0.0               # vu / φvc
    ok::Bool = true
end

"""Check if column capital design is adequate."""
is_adequate(s::ColumnCapitalDesign) = !s.required || s.ok

"""
    PunchingCheckResult

Per-column punching shear check result with optional reinforcement design.

# Fields
- `ok`: Whether check passes (with or without reinforcement)
- `ratio`: vu / φvc (or vu / φ(vcs+vs) with reinforcement)
- `vu`: Factored shear stress
- `φvc`: Design capacity (concrete only without reinforcement)
- `b0`: Critical perimeter at column
- `Jc`: Polar moment of inertia
- `Vu`: Factored shear force
- `Mub`: Unbalanced moment
- `studs`: Headed shear stud design (nothing if not used)
- `stirrups`: Closed stirrup design (nothing if not used)
- `shear_cap`: Shear cap design (nothing if not used)
- `capital`: Column capital design (nothing if not used)

# Reference
- ACI 318-11 §11.11
"""
Base.@kwdef struct PunchingCheckResult{L<:Asap.Length, P<:Asap.Pressure, F<:Asap.Force, M<:Asap.Moment}
    ok::Bool
    ratio::Float64
    vu::P
    φvc::P
    b0::L
    Jc::Asap.SecondMomentOfArea
    Vu::F
    Mub::M
    studs::Union{ShearStudDesign, Nothing} = nothing
    stirrups::Union{ClosedStirrupDesign, Nothing} = nothing
    shear_cap::Union{ShearCapDesign, Nothing} = nothing
    capital::Union{ColumnCapitalDesign, Nothing} = nothing
end

"""
Strip reinforcement design result (flat plate/slab design).

When `section_adequate = false`, the section is too thin for the moment demand
(Whitney block solution is imaginary). The iteration loop should increase h.
"""
struct StripReinforcement{L<:Asap.Length, A<:Asap.Area, M<:Asap.Moment}
    location::Symbol          # :ext_neg, :pos, :int_neg
    Mu::M                     # Design moment
    As_reqd::A                # Required steel area
    As_min::A                 # Minimum steel area
    As_provided::A            # Provided steel area
    bar_size::Int             # Bar designation (#4, #5, etc.)
    spacing::L                # Bar spacing
    n_bars::Int               # Number of bars
    section_adequate::Bool    # false if section too thin (As_reqd = Inf)
end

"""
    FlatPlatePanelResult

Panel design result for flat plate per ACI 318 DDM/EFM.

Extends `CIPSlabResult` with strip reinforcement and design checks.
Main result type for flat plate design - includes all fields needed
for visualization, analysis, and documentation.

# Core Fields (same interface as CIPSlabResult)
- `thickness`: Slab thickness (same as `h` for compatibility)
- `volume_per_area`: Concrete volume per plan area [m]
- `self_weight`: Self-weight pressure

# Geometry
- `l1`, `l2`: Panel spans in each direction
- `M0`: Total static moment

# Reinforcement Design
- `column_strip_width`, `column_strip_reinf`: Column strip design
- `middle_strip_width`, `middle_strip_reinf`: Middle strip design

# Design Checks
- `punching_check`: Punching shear verification
- `deflection_check`: Two-way deflection verification

# Example
```julia
result = size_flat_plate!(struc, slab, col_opts)
result.thickness          # Slab thickness
result.deflection_ok      # Quick deflection status
result.column_strip_reinf # Reinforcement details
```
"""
struct FlatPlatePanelResult{L<:Asap.Length, F<:Asap.Pressure, M<:Asap.Moment} <: AbstractFloorResult
    # Core fields (CIPSlabResult interface)
    thickness::L              # Slab thickness
    volume_per_area::L        # Concrete volume per plan area [m]
    self_weight::F            # Self-weight pressure
    
    # Loads
    qu::F                     # Factored uniform load: max(1.2D+1.6L, 1.4D)
    
    # Geometry
    l1::L                     # Span in direction 1
    l2::L                     # Span in direction 2
    
    # Analysis
    M0::M                     # Total static moment (primary direction)
    
    # Primary direction reinforcement
    column_strip_width::L
    column_strip_reinf::Vector{<:StripReinforcement}
    
    # Middle strip design  
    middle_strip_width::L
    middle_strip_reinf::Vector{<:StripReinforcement}
    
    # Secondary (perpendicular) direction reinforcement
    # These are populated when secondary moment analysis is performed.
    secondary_column_strip_width::L
    secondary_column_strip_reinf::Vector{<:StripReinforcement}
    secondary_middle_strip_width::L
    secondary_middle_strip_reinf::Vector{<:StripReinforcement}
    
    # Checks
    punching_check::NamedTuple
    deflection_check::NamedTuple
end

# Convenience constructor from h-based inputs.
# Accepts mixed length units and normalizes to coherent SI internally.
function FlatPlatePanelResult(
    l1::Asap.Length, l2::Asap.Length, h::Asap.Length, M0::M,
    qu::Asap.Pressure,
    cs_width::Asap.Length, cs_reinf::Vector{<:StripReinforcement},
    ms_width::Asap.Length, ms_reinf::Vector{<:StripReinforcement},
    punching::NamedTuple, deflection::NamedTuple;
    γ_concrete = NWC_4000.ρ * GRAVITY,
    sec_cs_width::Asap.Length = 0.0u"m",
    sec_cs_reinf::Vector{<:StripReinforcement} = StripReinforcement[],
    sec_ms_width::Asap.Length = 0.0u"m",
    sec_ms_reinf::Vector{<:StripReinforcement} = StripReinforcement[],
) where {M<:Asap.Moment}
    L = typeof(1.0u"m")
    
    thickness_m  = uconvert(u"m", h)
    l1_m         = uconvert(u"m", l1)
    l2_m         = uconvert(u"m", l2)
    cs_width_m   = uconvert(u"m", cs_width)
    ms_width_m   = uconvert(u"m", ms_width)
    M0_si        = uconvert(u"kN*m", M0)
    qu_si        = uconvert(u"kPa", qu)

    sec_cs_w_m = uconvert(u"m", sec_cs_width)
    sec_ms_w_m = uconvert(u"m", sec_ms_width)

    sw = uconvert(u"kPa", γ_concrete * h)
    vol_per_area = thickness_m
    
    return FlatPlatePanelResult{L, typeof(sw), typeof(M0_si)}(
        thickness_m, vol_per_area, sw, qu_si,
        l1_m, l2_m, M0_si,
        cs_width_m, cs_reinf,
        ms_width_m, ms_reinf,
        sec_cs_w_m, sec_cs_reinf,
        sec_ms_w_m, sec_ms_reinf,
        punching, deflection
    )
end

# Interface accessors
total_depth(r::FlatPlatePanelResult) = r.thickness

"""Quick check: does deflection pass?"""
deflection_ok(r::FlatPlatePanelResult) = r.deflection_check.ok

"""Quick check: does punching shear pass?"""
punching_ok(r::FlatPlatePanelResult) = r.punching_check.ok

"""Maximum punching utilization ratio across all columns."""
max_punching_ratio(r::FlatPlatePanelResult) = r.punching_check.max_ratio

"""Deflection ratio (Δ_total / Δ_limit)."""
deflection_ratio(r::FlatPlatePanelResult) = r.deflection_check.ratio

# Backward compatibility: h accessor
Base.getproperty(r::FlatPlatePanelResult, s::Symbol) = 
    s === :h ? getfield(r, :thickness) : getfield(r, s)

# Include both concrete and steel for EC calculations
materials(::FlatPlatePanelResult) = (:concrete, :steel)

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

# FlatPlatePanelResult: concrete is just thickness, steel calculated from reinforcement
_volume_impl(r::FlatPlatePanelResult, ::Val{:concrete}) = r.volume_per_area
_volume_impl(r::FlatPlatePanelResult, ::Val{:steel}) = _calc_rebar_volume_per_area(r)

"""
    _calc_rebar_volume_per_area(r::FlatPlatePanelResult) -> Length

Calculate reinforcing steel volume per plan area for EC calculations.

Sums As_provided from all strip reinforcement in both directions:
- Primary direction: bars run parallel to l1, with width = strip_width
- Secondary direction: bars run parallel to l2, with width = strip_width

When secondary reinforcement is available (from dual-direction moment analysis),
uses the actual designed reinforcement.  Falls back to the conservative 2× estimate
for legacy results that only have primary reinforcement.

# Returns
Volume per plan area [m³/m² = m], same units as concrete volume_per_area.
"""
function _calc_rebar_volume_per_area(r::FlatPlatePanelResult)
    l1 = r.l1
    l2 = r.l2
    panel_area = l1 * l2
    
    total_steel_volume = 0.0u"m^3"
    
    # ─── Primary direction: bars run parallel to l1 ───
    for reinf in r.column_strip_reinf
        As = uconvert(u"m^2", reinf.As_provided)
        total_steel_volume += As * l1 * r.column_strip_width / (1.0u"m")
    end
    for reinf in r.middle_strip_reinf
        As = uconvert(u"m^2", reinf.As_provided)
        total_steel_volume += As * l1 * r.middle_strip_width / (1.0u"m")
    end
    
    # ─── Secondary direction: bars run parallel to l2 ───
    has_secondary = !isempty(r.secondary_column_strip_reinf)
    if has_secondary
        for reinf in r.secondary_column_strip_reinf
            As = uconvert(u"m^2", reinf.As_provided)
            total_steel_volume += As * l2 * r.secondary_column_strip_width / (1.0u"m")
        end
        for reinf in r.secondary_middle_strip_reinf
            As = uconvert(u"m^2", reinf.As_provided)
            total_steel_volume += As * l2 * r.secondary_middle_strip_width / (1.0u"m")
        end
    else
        # Fallback: assume similar reinforcement in perpendicular direction
        total_steel_volume *= 2.0
    end
    
    # Add ~10% for lap splices, hooks, and integrity reinforcement
    total_steel_volume *= 1.10
    
    return uconvert(u"m", total_steel_volume / panel_area)
end

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

const floor_type_map = Dict{Symbol, AbstractFloorSystem}(
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
    :grade => Grade(),
)

const floor_symbol_map = Dict{Type, Symbol}(
    typeof(v) => k for (k, v) in pairs(floor_type_map)
)

"""Convert symbol to floor type for dispatch."""
function floor_type(s::Symbol)
    haskey(floor_type_map, s) || throw(KeyError("Unknown floor type: $s"))
    return floor_type_map[s]
end

"""Convert floor type to symbol for storage."""
function floor_symbol(t::AbstractFloorSystem)
    T = typeof(t)
    haskey(floor_symbol_map, T) || throw(KeyError("Unknown floor type: $T"))
    return floor_symbol_map[T]
end

"""Infer slab type from aspect ratio."""
function infer_floor_type(span_x, span_y)
    ratio = max(span_x, span_y) / min(span_x, span_y)
    return ratio > 2.0 ? :one_way : :two_way
end
