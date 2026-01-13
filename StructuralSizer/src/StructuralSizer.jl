module StructuralSizer

using Logging
using CSV
using StructuralBase
using Unitful

# Types (Metal, etc.)
include("types.jl")

# Materials
include("materials/steel.jl")
include("materials/concrete.jl")

# Sections (geometry + catalogs)
include("sections/_sections.jl")

# Design code checks
include("codes/_codes.jl")

# Optimization
include("optimize/_optimize.jl")

# === Exports ===

# Types
export Metal, Concrete, ISymmSection

# Demand types
export AbstractDemand, FlexuralDemand, CompressionDemand, TensionDemand
export demand_type

# Objectives
export AbstractObjective, MinWeight, MinVolume, MinCost, MinCarbon
export objective_value, total_objective

# Materials - Steel
export A992_Steel, S355_Steel, Rebar_40, Rebar_60, Rebar_75, Rebar_80
# Materials - Concrete
export NWC_4000, NWC_6000, NWC_GGBS, NWC_PFA

# Section Interface (generic)
export area, depth, width, weight_per_length

# Sections
export W, W_names, all_W
export Rebar, rebar, rebar_sizes, all_rebar
export update!, update, geometry, get_coords

# Capacity Interface (generic)
export get_Mn, get_Vn, get_Pn, get_Tn
export get_ϕMn, get_ϕVn, get_ϕPn, get_ϕTn
export check_interaction

# AISC-specific
export get_slenderness, is_compact
export get_Lp_Lr, get_Fcr_LTB, get_Fcr_flexural, get_Fe, get_Cv1
export check_PM_interaction, check_PMxMy_interaction

end # module
