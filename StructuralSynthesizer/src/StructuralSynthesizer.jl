module StructuralSynthesizer

using Logging
using StructuralBase
using StructuralSizer
using AsapToolkit

# Extend StructuralSizer's floor-result interface functions for local wrapper types
# (e.g. `Slab`). In Julia, adding methods requires `import`, not `using`.
import StructuralSizer: self_weight, total_depth, structural_effects

import GLMakie
import Meshes
import Graphs
import Asap
import LinearAlgebra: norm, normalize
using Unitful
using StructuralBase: StructuralUnits  # Shared unit definitions (already registered)
import StructuralPlots  # Colors and themes for visualization

# =============================================================================
# File includes (order matters!)
# =============================================================================

# Building types first (includes TributaryCache, BuildingStructure, etc.)
include("building_types.jl")

# Design types (BuildingDesign, DesignParameters, result structs)
include("design_types.jl")

# Core functionality (includes tributary_accessors.jl)
include("./core/_core.jl")

# Design workflow (uses both building_types and design_types)
include("design_workflow.jl")

# Other modules
include("./generate/_generate.jl")
include("./visualization/_visualization.jl")
include("./analyze/_analyze.jl")
include("./postprocess/_postprocess.jl")

# =============================================================================
# Exports
# =============================================================================

# --- Geometry generation ---
export gen_medium_office

# --- Building types ---
export BuildingSkeleton, BuildingStructure, Story
export SiteConditions, MaterialVolumes, VolumeType
export Cell, Slab, SlabGroup, thickness
export CellGroup, TributaryPolygon, SpanInfo, vertices
export Segment, MemberGroup

# --- Tributary cache types ---
export TributaryCache, TributaryCacheKey
export CellTributaryResult, ColumnTributaryResult
# Re-export Unitful type aliases from StructuralBase for convenience
export AreaQuantity, LengthQuantity
export has_edge_tributaries, has_vertex_tributaries
export get_edge_tributaries, set_edge_tributaries!
export get_vertex_tributary, set_vertex_tributary!

# --- Tributary accessors (core/tributary_accessors.jl) ---
export tributary_cache_key
export get_cached_edge_tributaries, cache_edge_tributaries!
export get_cached_column_tributary, cache_column_tributary!
export column_tributary_area, column_tributary_by_cell, column_tributary_polygons
export cell_edge_tributaries, cell_strip_geometry, has_cell_tributaries
export clear_tributary_cache!, list_cached_tributary_keys

# --- Design types ---
export DesignParameters
export BuildingDesign, SlabDesignResult, ColumnDesignResult, BeamDesignResult
export PunchingCheckResult, StripReinforcementDesign, DesignSummary
export structure, skeleton  # BuildingDesign accessors
export slab_design, column_design, beam_design, all_ok, critical_ratio

# --- Design workflow ---
export design_building, compare_designs

# --- Member type hierarchy ---
export AbstractMember, MemberBase, Beam, Column, Strut
export all_members, segment_indices, member_length, unbraced_length
export group_id, section, volumes, set_group_id!, set_section!, set_volumes!
export Support, Foundation, FoundationGroup, FoundationDemand

# --- Visualization ---
export visualize
export visualize_cell_groups, visualize_cell_tributary, visualize_cell_tributaries
export visualize_vertex_tributaries, visualize_tributaries_combined
export vis_embodied_carbon_summary

# --- Building operations ---
export add_vertex!, add_element!, find_faces!, rebuild_stories!, to_asap!, to_asap_with_diaphragms!
export initialize!, size!
export create_slab_diaphragm_shells

# --- Lookup utilities ---
export SkeletonLookup, enable_lookup!, build_lookup!, disable_lookup!
export find_vertex, find_edge, find_face, validate_lookup
export initialize_cells!, initialize_slabs!
export initialize_segments!, initialize_members!, update_bracing!
export build_slab_groups!, build_cell_groups!, compute_cell_tributaries!
export update_slab_loads!, update_all_slab_loads!

# --- Member sizing ---
export build_member_groups!, member_group_demands, size_members_discrete!
export size_columns!
export rc_section_to_asap
export estimate_column_sizes!

# --- Foundation sizing ---
export initialize_supports!, initialize_foundations!, size_foundations!
export support_demands, foundation_summary, build_foundation_groups!
export group_foundations_by_reaction!, size_foundations_grouped!, foundation_group_summary

# --- Internal toolkit ---
export AsapToolkit

# --- Meshing for shell elements ---
export ElementSpec, is_quad_suitable
export mesh_face, mesh_faces
export create_shell_elements, create_diaphragm_elements

# --- Postprocessing (Embodied Carbon) ---
export element_ec, compute_building_ec, ec_summary
export ElementECResult, BuildingECResult

end # module StructuralSynthesizer
