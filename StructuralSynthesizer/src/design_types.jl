# =============================================================================
# Design Result Types
# =============================================================================
#
# Separates building geometry/loads (BuildingStructure) from design results
# (BuildingDesign). This enables:
#   - Multiple designs for the same building (different materials)
#   - Parametric studies (sweep f'c, thickness, etc.)
#   - Design comparison and optimization
#
# Architecture:
#   BuildingStructure          → geometry, loads, tributaries (see building_types.jl)
#   BuildingDesign             → design results for a specific parameter set
#   DesignParameters           → material choices, optimization targets
#
# Unit Convention:
#   All design results are stored in coherent SI:
#     m, m², m³, kN, kN·m, kPa, kg
#   Analysis modules work in whatever units are natural internally,
#   then normalize at their return boundary.
#   DisplayUnits controls how values are presented to the user.
# =============================================================================

using Dates
using Unitful

# =============================================================================
# Display Unit Preferences
# =============================================================================

"""
    DisplayUnits(system::Symbol=:imperial)

Unit preferences for design output display. All design data is stored in
coherent SI (m, m², m³, kN, kN·m, kPa, kg). `DisplayUnits` controls what
units are shown to the user in summaries, reports, and visualization labels.

Use presets `imperial` or `metric`, or customize individual categories.

# Categories
`:length`, `:thickness`, `:span`, `:area`, `:volume`, `:force`, `:moment`,
`:pressure`, `:stress`, `:weight`, `:mass`, `:deflection`, `:spacing`,
`:rebar_dia`, `:rebar_area`

# Example
```julia
# Use presets
params = DesignParameters(display_units = imperial)
params = DesignParameters(display_units = metric)

# Customize: imperial but volume in m³
du = DisplayUnits(:imperial)
du.units[:volume] = u"m^3"
params = DesignParameters(display_units = du)
```
"""
mutable struct DisplayUnits
    units::Dict{Symbol, Any}
end

function DisplayUnits(system::Symbol)
    system === :imperial ? DisplayUnits(_imperial_units()) :
    system === :metric   ? DisplayUnits(_metric_units()) :
    error("Unknown unit system :$system. Use :imperial or :metric.")
end

function _imperial_units()
    Dict{Symbol, Any}(
        :length      => u"ft",
        :thickness   => u"inch",
        :span        => u"ft",
        :area        => u"ft^2",
        :volume      => u"ft^3",
        :force       => kip,
        :moment      => kip * u"ft",
        :pressure    => psf,
        :stress      => ksi,
        :weight      => u"lbf",
        :mass        => u"lb",
        :deflection  => u"inch",
        :spacing     => u"inch",
        :rebar_dia   => u"inch",
        :rebar_area  => u"inch^2",
    )
end

function _metric_units()
    Dict{Symbol, Any}(
        :length      => u"m",
        :thickness   => u"mm",
        :span        => u"m",
        :area        => u"m^2",
        :volume      => u"m^3",
        :force       => u"kN",
        :moment      => u"kN*m",
        :pressure    => u"kPa",
        :stress      => u"MPa",
        :weight      => u"kN",
        :mass        => u"kg",
        :deflection  => u"mm",
        :spacing     => u"mm",
        :rebar_dia   => u"mm",
        :rebar_area  => u"mm^2",
    )
end

const imperial = DisplayUnits(:imperial)
const metric   = DisplayUnits(:metric)

"""
    fmt(du::DisplayUnits, category::Symbol, value; digits=2)

Convert a Unitful value to display units and round.

# Example
```julia
fmt(imperial, :span, 12.192u"m")       # → 40.0 ft
fmt(imperial, :thickness, 0.2032u"m")  # → 8.0 inch
fmt(metric, :force, 100.0u"kN")        # → 100.0 kN
```
"""
fmt(du::DisplayUnits, cat::Symbol, val; digits=2) = round(du.units[cat], val; digits=digits)

# =============================================================================
# Foundation Parameters
# =============================================================================

"""
Foundation sizing parameters.

# Fields
- `soil`: Soil profile (bearing capacity, settlement params)
- `options`: ACI/IS design options (`FoundationOptions` from StructuralSizer).
  Controls code selection (`:aci` / `:is`), strategy (`:auto`, `:all_spread`,
  `:all_strip`, `:mat`), and per-type knobs (spread, strip, mat options).
- `concrete`: Concrete grade for footings (IS path only; ACI uses `options.spread.material`)
- `rebar`: Rebar grade for footings (IS path only)
- `pier_width`: Column/pier width (IS path only; ACI uses `options.spread.pier_c1`)
- `min_depth`: Minimum footing depth (IS path only; ACI uses `options.spread.min_depth`)
- `group_tolerance`: Tolerance for grouping similar foundations (default 0.15 = 15%)

# Example
```julia
# ACI (default) — material/detailing in options
fp = FoundationParameters(soil = medium_sand)

# IS legacy path
fp = FoundationParameters(
    soil = medium_sand,
    options = FoundationOptions(code = :is),
    concrete = NWC_4000,
    min_depth = 0.5u"m",
)
```
"""
Base.@kwdef struct FoundationParameters
    soil::StructuralSizer.Soil = StructuralSizer.medium_sand
    options::StructuralSizer.FoundationOptions = StructuralSizer.FoundationOptions()
    concrete::StructuralSizer.Concrete = StructuralSizer.NWC_4000
    rebar::StructuralSizer.RebarSteel = StructuralSizer.Rebar_60
    pier_width::typeof(1.0u"m") = 0.35u"m"
    min_depth::typeof(1.0u"m") = 0.4u"m"
    group_tolerance::Float64 = 0.15
end

# =============================================================================
# Design Parameters
# =============================================================================

"""
Parameters that define a design configuration.

Different `DesignParameters` on the same `BuildingStructure` produce
different `BuildingDesign` results, enabling parametric studies.

# Materials
Use existing types from StructuralSizer:
- `concrete::Concrete` - with fc′, E, ρ, etc.
- `steel::StructuralSteel` - with Fy, Fu, E, etc.
- `rebar::RebarSteel` - for reinforcement

# Member Sizing Options
Optional overrides for column/beam sizing:
- `columns`: `SteelColumnOptions` or `ConcreteColumnOptions`
- `beams`: `SteelBeamOptions`

# Loads
- `loads::GravityLoads` - Unfactored service loads (default: `default_loads`)
- `load_combinations::Vector{LoadCombination}` - Factored combinations for
  envelope analysis. The Asap model uses `envelope_pressure(combos, D, L)`.

# Analysis Settings
- `diaphragm_mode::Symbol` - `:none`, `:rigid`, or `:shell`
- `default_frame_E/G/ρ` - Placeholder frame properties
- `column_I_factor` / `beam_I_factor` - ACI cracking factors

# Example
```julia
# Simple: just set materials
params = DesignParameters(
    steel = A992_Steel,
    concrete = NWC_5000,
)

# Full control: materials, loads, sizing, and analysis
params = DesignParameters(
    name = "High-Rise Office",
    
    # Loads
    loads = office_loads,                                # 50 psf LL
    load_combinations = [strength_1_2D_1_6L, service],  # envelope + serviceability
    
    # Materials
    steel = A992_Steel,
    concrete = NWC_5000,
    
    # Concrete columns with specific settings
    columns = ConcreteColumnOptions(
        grade = NWC_5000,
        max_depth = 0.6,
    ),
    
    # Steel beams with strict deflection
    beams = SteelBeamOptions(
        deflection_limit = 1/480,
    ),
    
    # Analysis settings
    diaphragm_mode = :rigid,
    optimize_for = :carbon,
)

# Parametric live load sweep
for ll in [40, 50, 65, 80, 100]
    design = design_building(struc, DesignParameters(
        loads = GravityLoads(floor_LL = Float64(ll) * psf),
    ))
end
```
"""
Base.@kwdef mutable struct DesignParameters
    # Identifiers
    name::String = "default"
    description::String = ""
    
    # ─── Gravity Loads (unfactored service level) ───
    # Stamped onto cells during initialize_cells!
    loads::GravityLoads = GravityLoads()
    
    # ─── Materials ───
    # Defaults for the building (used when section-specific material not provided)
    concrete::Union{StructuralSizer.Concrete, Nothing} = nothing
    steel::Union{StructuralSizer.StructuralSteel, Nothing} = nothing
    rebar::Union{StructuralSizer.RebarSteel, Nothing} = nothing
    timber::Union{StructuralSizer.Timber, Nothing} = nothing
    
    # ─── Member Sizing Options ───
    # Override material defaults for specific member types
    columns::Union{StructuralSizer.ColumnOptions, Nothing} = nothing
    beams::Union{StructuralSizer.BeamOptions, Nothing} = nothing
    
    # ─── Floor Options ───
    floor_options::Union{StructuralSizer.FloorOptions, Nothing} = nothing
    
    # ─── Foundation Options ───
    foundation_options::Union{FoundationParameters, Nothing} = nothing
    
    # ─── Design Targets ───
    deflection_limit::Symbol = :L_360        # :L_240, :L_360, :L_480
    optimize_for::Symbol = :weight           # :weight, :carbon, :cost
    
    # ─── Load Combinations (factored) ───
    # Vector of combinations for envelope analysis.
    # The Asap model applies max(factored_pressure(c, D, L) for c in combos).
    # Default: standard gravity strength combination only.
    load_combinations::Vector{LoadCombination} = [default_combo]
    
    # Diaphragm modeling for lateral analysis
    diaphragm_mode::Symbol = :none           # :none, :rigid, :shell
    diaphragm_E::Union{typeof(1.0u"Pa"), Nothing} = nothing  # override E (default: 1e15 Pa for rigid, 30 GPa for shell)
    diaphragm_ν::Float64 = 0.2
    
    # Default frame element properties (before member sizing)
    # Placeholder section in to_asap! before actual sizing.
    # Defaults from A992 steel; override via params.steel material.
    default_frame_E::typeof(1.0u"Pa") = uconvert(u"Pa", A992_Steel.E)
    default_frame_G::typeof(1.0u"Pa") = uconvert(u"Pa", A992_Steel.G)
    default_frame_ρ::typeof(1.0u"kg/m^3") = uconvert(u"kg/m^3", A992_Steel.ρ)
    
    # ─── ACI Cracking Factors ───
    # For converting RC sections to Asap.Section (effective stiffness)
    column_I_factor::Float64 = 0.70    # ACI 318-14 §6.6.3.1.1 for columns
    beam_I_factor::Float64 = 0.35      # ACI 318-14 §6.6.3.1.1 for beams
    
    # ─── Iteration Control ───
    max_iterations::Int = 20              # Slab/column convergence loop limit
    
    # ─── Display Preferences ───
    # Controls how SI-stored values are shown in summaries and reports
    display_units::DisplayUnits = imperial
end

"""Primary (governing) strength combination from a DesignParameters."""
governing_combo(p::DesignParameters) = first(p.load_combinations)

# =============================================================================
# Design Results
# =============================================================================

"""
Strip reinforcement design at a moment location.
All values stored in coherent SI (m, m², kN·m).
"""
struct StripReinforcementDesign
    Mu::typeof(1.0u"kN*m")           # Factored moment
    As_required::typeof(1.0u"m^2")   # Required steel area
    As_minimum::typeof(1.0u"m^2")    # Minimum steel area
    As_provided::typeof(1.0u"m^2")   # Provided steel area
    bar_size::String                  # e.g., "#5", "16M"
    spacing::typeof(1.0u"m")          # Bar spacing
    n_bars::Int                       # Number of bars
end

"""
Design result for a slab panel.
All values stored in coherent SI (m, kPa, kN·m).
"""
Base.@kwdef mutable struct SlabDesignResult
    # Sizing
    thickness::typeof(1.0u"m")
    self_weight::typeof(1.0u"kPa")
    
    # Analysis
    M0::Union{typeof(1.0u"kN*m"), Nothing} = nothing  # Total static moment
    
    # Reinforcement (by location)
    column_strip::Dict{Symbol, StripReinforcementDesign} = Dict()  # :ext_neg, :pos, :int_neg
    middle_strip::Dict{Symbol, StripReinforcementDesign} = Dict()
    
    # Checks
    deflection_ok::Bool = true
    deflection_ratio::Float64 = 0.0  # actual / limit
end

"""
Punching shear check result for a column.
All values stored in coherent SI (kN, m, m²).
"""
Base.@kwdef mutable struct PunchingDesignResult
    Vu::typeof(1.0u"kN")             # Demand
    φVc::typeof(1.0u"kN")            # Capacity (factored)
    ratio::Float64                    # Vu / φVc
    ok::Bool                          # ratio ≤ 1.0
    critical_perimeter::typeof(1.0u"m")
    tributary_area::typeof(1.0u"m^2")
end

"""
Design result for a column.
"""
Base.@kwdef mutable struct ColumnDesignResult
    # Sizing
    section_size::String = ""         # e.g., "W14x90", "16x16"
    
    # Demands
    Pu::typeof(1.0u"kN") = 0.0u"kN"
    Mu_x::typeof(1.0u"kN*m") = 0.0u"kN*m"
    Mu_y::typeof(1.0u"kN*m") = 0.0u"kN*m"
    
    # Capacity ratios
    axial_ratio::Float64 = 0.0
    interaction_ratio::Float64 = 0.0
    ok::Bool = true
    
    # Punching (if supporting flat slab)
    punching::Union{PunchingDesignResult, Nothing} = nothing
end

"""
Design result for a beam.
"""
Base.@kwdef mutable struct BeamDesignResult
    section_size::String = ""
    Mu::typeof(1.0u"kN*m") = 0.0u"kN*m"
    Vu::typeof(1.0u"kN") = 0.0u"kN"
    flexure_ratio::Float64 = 0.0
    shear_ratio::Float64 = 0.0
    ok::Bool = true
end

"""
Design result for a foundation.
"""
Base.@kwdef mutable struct FoundationDesignResult
    # Geometry
    length::typeof(1.0u"m") = 0.0u"m"
    width::typeof(1.0u"m") = 0.0u"m"
    depth::typeof(1.0u"m") = 0.0u"m"
    
    # Demands
    reaction::typeof(1.0u"kN") = 0.0u"kN"
    
    # Checks
    bearing_ratio::Float64 = 0.0      # actual / allowable bearing pressure
    punching_ratio::Float64 = 0.0     # punching shear check
    flexure_ratio::Float64 = 0.0      # flexure check
    ok::Bool = true
    
    # Group assignment
    group_id::Int = 0
end

"""
Design summary with aggregate metrics.
"""
Base.@kwdef mutable struct DesignSummary
    # Volumes/weights
    concrete_volume::typeof(1.0u"m^3") = 0.0u"m^3"
    steel_weight::typeof(1.0u"kg") = 0.0u"kg"
    rebar_weight::typeof(1.0u"kg") = 0.0u"kg"
    timber_volume::typeof(1.0u"m^3") = 0.0u"m^3"
    
    # Derived metrics
    embodied_carbon::Float64 = 0.0    # kgCO₂e
    cost_estimate::Float64 = 0.0      # $
    
    # Status
    all_checks_pass::Bool = true
    critical_element::String = ""      # Element with highest ratio
    critical_ratio::Float64 = 0.0
end

"""
A complete design solution for a BuildingStructure.

Holds a reference to the source `BuildingStructure` for geometry access,
enabling a clean API: `visualize(design)` works without passing structure separately.

Multiple BuildingDesign instances can reference the same BuildingStructure,
enabling comparison of different material choices or optimization targets.

# Example
```julia
building = BuildingStructure(skeleton)
# ... initialize cells, members ...

design1 = BuildingDesign(building, DesignParameters(
    name = "Concrete 4ksi",
    concrete = NWC_4000
))

design2 = BuildingDesign(building, DesignParameters(
    name = "Concrete 6ksi", 
    concrete = NWC_6000
))

visualize(design1)  # Self-contained: accesses geometry via design.structure
compare_designs(design1, design2)
```
"""
mutable struct BuildingDesign{T, A, P}
    # Reference to source building (pointer, not copy)
    structure::BuildingStructure{T, A, P}
    
    # Design configuration
    params::DesignParameters
    
    # Design results (keyed by member index)
    slabs::Dict{Int, SlabDesignResult}
    columns::Dict{Int, ColumnDesignResult}
    beams::Dict{Int, BeamDesignResult}
    foundations::Dict{Int, FoundationDesignResult}
    
    # Summary
    summary::DesignSummary
    
    # ─── Analysis Model ───
    # Frame+shell model for global deflection analysis (built after design)
    # Separate from struc.asap_model to preserve the design-phase frame model
    asap_model::Union{Asap.Model, Nothing}
    
    # Metadata
    created::DateTime
    compute_time_s::Float64
end

function BuildingDesign(struc::BuildingStructure{T, A, P}, params::DesignParameters=DesignParameters()) where {T, A, P}
    BuildingDesign{T, A, P}(
        struc,
        params,
        Dict{Int, SlabDesignResult}(),
        Dict{Int, ColumnDesignResult}(),
        Dict{Int, BeamDesignResult}(),
        Dict{Int, FoundationDesignResult}(),
        DesignSummary(),
        nothing,  # asap_model (built via build_analysis_model!)
        now(),
        0.0
    )
end

# =============================================================================
# BuildingDesign Accessors
# =============================================================================

"""Get the source BuildingStructure."""
structure(d::BuildingDesign) = d.structure

"""Get the source BuildingSkeleton (shorthand for d.structure.skeleton)."""
skeleton(d::BuildingDesign) = d.structure.skeleton

"""Get slab design result by index."""
slab_design(d::BuildingDesign, idx::Int) = get(d.slabs, idx, nothing)

"""Get column design result by index."""
column_design(d::BuildingDesign, idx::Int) = get(d.columns, idx, nothing)

"""Get beam design result by index."""
beam_design(d::BuildingDesign, idx::Int) = get(d.beams, idx, nothing)

"""Get foundation design result by index."""
foundation_design(d::BuildingDesign, idx::Int) = get(d.foundations, idx, nothing)

"""Check if all design checks pass."""
all_ok(d::BuildingDesign) = d.summary.all_checks_pass

"""Get the governing (critical) design ratio."""
critical_ratio(d::BuildingDesign) = d.summary.critical_ratio

"""Check if the analysis model (frame+shell) has been built."""
has_analysis_model(d::BuildingDesign) = !isnothing(d.asap_model)
