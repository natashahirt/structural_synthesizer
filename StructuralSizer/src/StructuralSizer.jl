module StructuralSizer

using Logging
using CSV
using StructuralBase
using Unitful
using QuadGK: quadgk
using Roots: find_zero, Brent, Order0

# Types (Metal, etc.)
include("types.jl")

# Members (materials, sections, codes, optimization)
include("members/_members.jl")

# Slabs (types, codes, optimization)
include("slabs/_slabs.jl")

# === Exports ===

# Types
export Metal, Concrete, ISymmSection

# Demand types
export AbstractDemand, MemberDemand

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

# =============================================================================
# Floor System Types
# =============================================================================

# Abstract hierarchy
export AbstractFloorSystem
export AbstractConcreteSlab, AbstractSteelFloor, AbstractTimberFloor

# CIP Concrete types
export OneWay, TwoWay, FlatPlate, FlatSlab, PTBanded, Waffle
export HollowCore, Vault

# Steel floor types
export CompositeDeck, NonCompositeDeck, JoistRoofDeck

# Timber floor types
export CLT, DLT, NLT, MassTimberJoist

# Custom
export ShapedSlab

# Support conditions
export SupportCondition, SIMPLE, ONE_END_CONT, BOTH_ENDS_CONT, CANTILEVER

# Type mapping utilities
export floor_type, floor_symbol, infer_floor_type

# =============================================================================
# Floor Result Types
# =============================================================================

export AbstractFloorResult
export CIPSlabResult, ProfileResult
export CompositeDeckResult, JoistDeckResult
export TimberPanelResult, TimberJoistResult
export VaultResult, ShapedSlabResult

# Common interface
export self_weight, total_depth, volume_per_area
export has_structural_effects, apply_effects!
export required_materials

# =============================================================================
# Floor Sizing Interface
# =============================================================================

export size_floor

# =============================================================================
# Vault Analysis (advanced)
# =============================================================================

export vault_stress_symmetric, vault_stress_asymmetric
export solve_equilibrium_rise
export parabolic_arc_length

end # module
