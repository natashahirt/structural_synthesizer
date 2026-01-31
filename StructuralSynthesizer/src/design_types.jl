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
# =============================================================================

using Dates
using Unitful

# =============================================================================
# Design Parameters
# =============================================================================

"""
Parameters that define a design configuration.

Different `DesignParameters` on the same `BuildingStructure` produce
different `BuildingDesign` results, enabling parametric studies.

# Materials (defaults)
Use existing types from StructuralSizer:
- `concrete::Concrete` - with fc′, E, ρ, etc.
- `steel::StructuralSteel` - with Fy, Fu, E, etc.
- `rebar::RebarSteel` - for reinforcement

# Member Sizing Options
Optional overrides for column/beam sizing:
- `columns`: `SteelColumnOptions` or `ConcreteColumnOptions`
- `beams`: `SteelBeamOptions`

# Example
```julia
# Simple: just set materials
params = DesignParameters(
    steel = A992_Steel,
    concrete = NWC_5000,
)

# Full control: specify sizing options
params = DesignParameters(
    name = "High-Rise Office",
    
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
    
    optimize_for = :carbon,
)

# Then sizing auto-uses these:
size_columns!(struc)  # uses params.columns
size_beams!(struc)    # uses params.beams
```
"""
Base.@kwdef mutable struct DesignParameters
    # Identifiers
    name::String = "default"
    description::String = ""
    
    # Materials - defaults for the building
    concrete::Union{StructuralSizer.Concrete, Nothing} = nothing
    steel::Union{StructuralSizer.StructuralSteel, Nothing} = nothing
    rebar::Union{StructuralSizer.RebarSteel, Nothing} = nothing
    timber::Union{StructuralSizer.Timber, Nothing} = nothing
    
    # Member sizing options (override material defaults)
    columns::Union{StructuralSizer.SteelColumnOptions, StructuralSizer.ConcreteColumnOptions, Nothing} = nothing
    beams::Union{StructuralSizer.SteelBeamOptions, Nothing} = nothing
    
    # Floor options (from StructuralSizer)
    floor_options::Union{StructuralSizer.FloorOptions, Nothing} = nothing
    
    # Design targets
    deflection_limit::Symbol = :L_360        # :L_240, :L_360, :L_480
    optimize_for::Symbol = :weight           # :weight, :carbon, :cost
end

# =============================================================================
# Design Results
# =============================================================================

"""
Strip reinforcement design at a moment location.
"""
struct StripReinforcementDesign
    Mu::typeof(1.0u"kN*m")           # Factored moment
    As_required::typeof(1.0u"mm^2")  # Required steel area
    As_minimum::typeof(1.0u"mm^2")   # Minimum steel area
    As_provided::typeof(1.0u"mm^2")  # Provided steel area
    bar_size::String                  # e.g., "#5", "16M"
    spacing::typeof(1.0u"mm")         # Bar spacing
    n_bars::Int                       # Number of bars
end

"""
Design result for a slab panel.
"""
Base.@kwdef mutable struct SlabDesignResult
    # Sizing
    thickness::typeof(1.0u"mm")
    self_weight::typeof(1.0u"kN/m^2")
    
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
"""
Base.@kwdef mutable struct PunchingCheckResult
    Vu::typeof(1.0u"kN")             # Demand
    φVc::typeof(1.0u"kN")            # Capacity (factored)
    ratio::Float64                    # Vu / φVc
    ok::Bool                          # ratio ≤ 1.0
    critical_perimeter::typeof(1.0u"mm")
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
    punching::Union{PunchingCheckResult, Nothing} = nothing
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
    
    # Summary
    summary::DesignSummary
    
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
        DesignSummary(),
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

"""Check if all design checks pass."""
all_ok(d::BuildingDesign) = d.summary.all_checks_pass

"""Get the governing (critical) design ratio."""
critical_ratio(d::BuildingDesign) = d.summary.critical_ratio
