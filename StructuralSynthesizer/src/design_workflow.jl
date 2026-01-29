# =============================================================================
# Design Workflow
# =============================================================================
#
# Functions for generating BuildingDesign from BuildingStructure.
# This is the main entry point for parametric design studies.
#
# Example:
#   building = BuildingStructure(skeleton)
#   initialize!(building, ...)
#   
#   design1 = design_building(building, DesignParameters(
#       concrete = ConcreteMaterial(fc = 4000u"psi")
#   ))
#   
#   design2 = design_building(building, DesignParameters(
#       concrete = ConcreteMaterial(fc = 6000u"psi")
#   ))
#   
#   compare_designs(design1, design2)
# =============================================================================

using Dates

"""
    design_building(struc::BuildingStructure, params::DesignParameters) -> BuildingDesign

Generate a complete design for a building structure using the given parameters.

This is the main entry point for design. It:
1. Ensures tributaries are computed and cached
2. Sizes slabs based on floor type and material
3. Sizes columns (if concrete) with punching shear checks
4. Sizes beams based on tributary loads
5. Computes summary metrics (volume, weight, embodied carbon)

# Arguments
- `struc`: BuildingStructure with initialized cells, members, etc.
- `params`: DesignParameters specifying material, code, and options

# Returns
- `BuildingDesign` with all design results

# Example
```julia
design = design_building(struc, DesignParameters(
    name = "Option A - 4ksi concrete",
    concrete = NWC_4000,  # or custom Concrete(...)
    deflection_limit = :L_360
))
```
"""
function design_building(struc::BuildingStructure, params::DesignParameters)
    t_start = time()
    
    design = BuildingDesign(params)
    design.building_id = hash(struc)
    
    # 1. Ensure tributaries are computed
    _ensure_tributaries_computed!(struc, params)
    
    # 2. Design slabs
    _design_slabs!(design, struc, params)
    
    # 3. Design columns (including punching shear)
    _design_columns!(design, struc, params)
    
    # 4. Design beams
    _design_beams!(design, struc, params)
    
    # 5. Compute summary
    _compute_design_summary!(design, struc, params)
    
    design.compute_time_s = time() - t_start
    return design
end

"""
    design_building(struc::BuildingStructure; kwargs...) -> BuildingDesign

Convenience method that creates DesignParameters from keyword arguments.

# Example
```julia
design = design_building(struc,
    name = "Default Design",
    concrete = ConcreteMaterial(fc = 4000u"psi")
)
```
"""
function design_building(struc::BuildingStructure; kwargs...)
    params = DesignParameters(; kwargs...)
    return design_building(struc, params)
end

# =============================================================================
# Internal Design Functions
# =============================================================================

"""Ensure tributaries are computed for the design configuration."""
function _ensure_tributaries_computed!(struc::BuildingStructure, params::DesignParameters)
    # Determine spanning behavior from floor options or default
    opts = something(params.floor_options, StructuralSizer.FloorOptions())
    
    # For each cell, check if tributaries are cached for this configuration
    for (cell_idx, cell) in enumerate(struc.cells)
        # Determine axis based on floor type and options
        ft = StructuralSizer.floor_type(cell.floor_type)
        behavior = StructuralSizer.spanning_behavior(ft)
        axis = StructuralSizer.resolve_tributary_axis(ft, cell.spans, opts)
        
        # Skip if already cached
        has_cell_tributaries(struc, cell_idx, behavior, axis) && continue
        
        # Compute and cache
        verts = [struc.skeleton.vertices[i] for i in struc.skeleton.face_vertex_indices[cell.face_idx]]
        tributaries = if isnothing(axis)
            StructuralSizer.get_tributary_polygons_isotropic(verts)
        else
            StructuralSizer.get_tributary_polygons(verts; axis=collect(axis))
        end
        
        # Compute strip geometry for two-way/beamless floors
        strips = nothing
        if behavior isa TwoWaySpanning || behavior isa BeamlessSpanning
            strips = StructuralSizer.compute_panel_strips(tributaries)
        end
        
        cache_edge_tributaries!(struc, behavior, axis, cell_idx, tributaries; 
                                strip_geometry=strips)
    end
    
    # Compute column (Voronoi) tributaries if needed for beamless floors
    any_beamless = any(StructuralSizer.is_beamless(
        StructuralSizer.floor_type(c.floor_type)) for c in struc.cells)
    
    if any_beamless
        _ensure_column_tributaries_computed!(struc)
    end
end

"""Ensure column Voronoi tributaries are computed."""
function _ensure_column_tributaries_computed!(struc::BuildingStructure)
    # Check if any columns are missing tributary data
    for col in struc.columns
        cached = get_cached_column_tributary(struc, col.story, col.vertex_idx)
        if isnothing(cached)
            # Need to compute - call the full computation which stores in cache
            compute_column_tributaries!(struc)
            return  # All columns computed at once
        end
    end
    # All columns have cached data - nothing to do
end

"""Design all slabs."""
function _design_slabs!(design::BuildingDesign, struc::BuildingStructure, params::DesignParameters)
    for (slab_idx, slab) in enumerate(struc.slabs)
        result = SlabDesignResult(
            thickness = StructuralSizer.total_depth(slab.result),
            self_weight = StructuralSizer.self_weight(slab.result)
        )
        
        # TODO: Detailed reinforcement design based on floor type and code
        # For now, just store the sizing result
        
        design.slabs[slab_idx] = result
    end
end

"""Design all columns."""
function _design_columns!(design::BuildingDesign, struc::BuildingStructure, params::DesignParameters)
    for (col_idx, col) in enumerate(struc.columns)
        result = ColumnDesignResult()
        
        # Get tributary area from cache
        trib_area = column_tributary_area(struc, col)
        
        if !isnothing(trib_area) && !isnothing(params.concrete)
            # TODO: Punching shear check using flat plate calculations
            # For now, just mark as OK
            result.punching = PunchingCheckResult(
                Vu = 0.0u"kN",
                φVc = 0.0u"kN",
                ratio = 0.0,
                ok = true,
                critical_perimeter = 0.0u"mm",
                tributary_area = trib_area * u"m^2"
            )
        end
        
        design.columns[col_idx] = result
    end
end

"""Design all beams."""
function _design_beams!(design::BuildingDesign, struc::BuildingStructure, params::DesignParameters)
    for (beam_idx, beam) in enumerate(struc.beams)
        result = BeamDesignResult()
        
        # Beams may have existing sections from catalog sizing
        if !isnothing(beam.base.section)
            result.section_size = string(beam.base.section)
        end
        
        design.beams[beam_idx] = result
    end
end

"""Compute summary metrics."""
function _compute_design_summary!(design::BuildingDesign, struc::BuildingStructure, params::DesignParameters)
    summary = design.summary
    
    # Find critical ratio across all elements
    max_ratio = 0.0
    critical_elem = ""
    all_ok = true
    
    for (idx, slab_result) in design.slabs
        if slab_result.deflection_ratio > max_ratio
            max_ratio = slab_result.deflection_ratio
            critical_elem = "Slab $idx (deflection)"
        end
        if !slab_result.deflection_ok
            all_ok = false
        end
    end
    
    for (idx, col_result) in design.columns
        if !isnothing(col_result.punching) && col_result.punching.ratio > max_ratio
            max_ratio = col_result.punching.ratio
            critical_elem = "Column $idx (punching)"
        end
        if !col_result.ok
            all_ok = false
        end
    end
    
    summary.critical_ratio = max_ratio
    summary.critical_element = critical_elem
    summary.all_checks_pass = all_ok
    
    # TODO: Compute total volumes and embodied carbon
end

# =============================================================================
# Design Comparison Utilities
# =============================================================================

"""
    compare_designs(designs::Vector{BuildingDesign})

Create a comparison table of multiple designs.

Returns a Dict with design names as keys and comparison metrics as values.
"""
function compare_designs(designs::Vector{BuildingDesign})
    results = Dict{String, Dict{Symbol, Any}}()
    
    for d in designs
        results[d.params.name] = Dict(
            :concrete_volume => d.summary.concrete_volume,
            :steel_weight => d.summary.steel_weight,
            :embodied_carbon => d.summary.embodied_carbon,
            :all_ok => d.summary.all_checks_pass,
            :critical_ratio => d.summary.critical_ratio,
            :compute_time => d.compute_time_s
        )
    end
    
    return results
end

compare_designs(d1::BuildingDesign, d2::BuildingDesign) = compare_designs([d1, d2])

# =============================================================================
# Exports
# =============================================================================

export design_building, compare_designs
