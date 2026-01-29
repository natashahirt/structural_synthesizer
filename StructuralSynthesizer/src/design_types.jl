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

# Materials
Use existing types from StructuralSizer:
- `concrete::Concrete` - with fc′, E, ρ, etc.
- `steel::StructuralSteel` - with Fy, Fu, E, etc.
- `rebar::RebarSteel` - for reinforcement

# Example
```julia
params = DesignParameters(
    name = "4ksi Concrete",
    concrete = Concrete(
        57000*sqrt(4000)*u"psi",  # E
        4000.0u"psi",              # fc′
        150.0u"lbf/ft^3",          # ρ
        0.2,                       # ν
        0.12                       # ecc
    )
)
```
"""
Base.@kwdef mutable struct DesignParameters
    # Identifiers
    name::String = "default"
    description::String = ""
    
    # Materials - use existing types from StructuralSizer
    concrete::Union{StructuralSizer.Concrete, Nothing} = nothing
    steel::Union{StructuralSizer.StructuralSteel, Nothing} = nothing
    rebar::Union{StructuralSizer.RebarSteel, Nothing} = nothing
    timber::Union{StructuralSizer.Timber, Nothing} = nothing
    
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

Multiple BuildingDesign instances can reference the same BuildingStructure,
enabling comparison of different material choices or optimization targets.

# Example
```julia
building = BuildingStructure(skeleton)
# ... initialize cells, members ...

design1 = design_building(building, DesignParameters(
    name = "Concrete 4ksi",
    concrete = NWC_4000
))

design2 = design_building(building, DesignParameters(
    name = "Concrete 6ksi", 
    concrete = NWC_6000
))

compare_designs(design1, design2)  # Compare thickness, weight, carbon
```
"""
mutable struct BuildingDesign
    # Reference to source building (not owned, just referenced)
    building_id::UInt64               # hash(building) for serialization
    
    # Design configuration
    params::DesignParameters
    
    # Design results (keyed by element index)
    slabs::Dict{Int, SlabDesignResult}
    columns::Dict{Int, ColumnDesignResult}
    beams::Dict{Int, BeamDesignResult}
    
    # Summary
    summary::DesignSummary
    
    # Metadata
    created::DateTime
    compute_time_s::Float64
end

function BuildingDesign(params::DesignParameters)
    BuildingDesign(
        UInt64(0),
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
