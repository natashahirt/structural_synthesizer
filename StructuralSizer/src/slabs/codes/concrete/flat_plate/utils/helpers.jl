# =============================================================================
# Flat Plate Design Helpers
# =============================================================================
#
# Support functions for the flat plate design pipeline:
# - Column finding and ordering
# - Frame line construction
# - Axial load computation
# - Asap model updates
#
# Note: This file is included in StructuralSizer, inheriting Logging, Meshes, etc.
# =============================================================================

# =============================================================================
# Column Accessor Functions
# =============================================================================
# These provide a stable interface for column properties that may or may not
# exist on the input object (e.g., NamedTuple from standalone tests vs. a full
# Column struct from StructuralSynthesizer).

"""Column cross-section shape (`:rectangular` or `:circular`)."""
col_shape(col)::Symbol = hasproperty(col, :shape) ? col.shape : :rectangular

"""Skeleton vertex index for the column (0 = not available)."""
col_vertex_idx(col)::Int = hasproperty(col, :vertex_idx) ? col.vertex_idx : 0

"""Story index for the column (default 1)."""
col_story(col)::Int = hasproperty(col, :story) ? col.story : 1

"""Boundary edge directions for the column (empty = interior)."""
col_boundary_edge_dirs(col) = hasproperty(col, :boundary_edge_dirs) ? col.boundary_edge_dirs : NTuple{2, Float64}[]

# =============================================================================
# Analysis Method Utilities
# =============================================================================

"""Display name for DDM analysis method."""
method_name(method::DDM) = method.variant == :simplified ? "MDDM (Simplified)" : "DDM (ACI 8.10)"

"""Display name for EFM analysis method."""
method_name(method::EFM) = "EFM (ACI 8.11, $(method.solver == :asap ? "ASAP FEM" : "Hardy Cross"))"

"""Display name for FEA analysis method."""
method_name(method::FEA) = "FEA (Shell + Springs, edge=$(method.target_edge))"

"""
    round_up_thickness(h, increment) -> Length

Round slab thickness up to the nearest increment.

# Example
```julia
round_up_thickness(7.3u"inch", 0.5u"inch")  # → 7.5u"inch"
```
"""
function round_up_thickness(h::Length, increment::Length)
    h_val = ustrip(u"inch", h)
    inc_val = ustrip(u"inch", increment)
    h_rounded = ceil(h_val / inc_val) * inc_val
    return h_rounded * u"inch"
end

# =============================================================================
# Column Finding
# =============================================================================

"""
    find_supporting_columns(struc, slab_cell_indices) -> Vector{Column}

Find columns whose tributary area includes any of the slab's cells.

Uses `col.tributary_cell_indices` (populated by `compute_vertex_tributaries!`).
"""
function find_supporting_columns(struc, slab_cell_indices::Set{Int})
    supporting = typeof(struc.columns)()
    for col in struc.columns
        if !isempty(col.tributary_cell_indices)
            if any(cell_idx in slab_cell_indices for cell_idx in col.tributary_cell_indices)
                push!(supporting, col)
            end
        end
    end
    return supporting
end

# =============================================================================
# Frame Line Construction
# =============================================================================

"""
    build_frame_line(struc, columns, l2, direction::Symbol=:x) -> FrameLine

Build a FrameLine from columns and tributary width for EFM analysis.

# Arguments
- `struc`: BuildingStructure with skeleton for column positions
- `columns`: Vector of Column objects
- `l2`: Tributary width (panel width perpendicular to frame)
- `direction`: Frame direction (:x or :y)
"""
function build_frame_line(struc, columns, l2, direction::Symbol=:x)
    vc = struc.skeleton.geometry.vertex_coords
    # Position accessor: reads from cached coordinate matrix
    function get_position(col)
        (vc[col.vertex_idx, 1], vc[col.vertex_idx, 2])
    end
    
    # Width accessor: returns column width in frame direction
    function get_width(col, dir::NTuple{2, Float64})
        if abs(dir[1]) > abs(dir[2])
            return col.c1  # X-direction
        else
            return col.c2  # Y-direction
        end
    end
    
    return FrameLine(direction, columns, l2, get_position, get_width)
end

"""
    build_frame_lines_both_directions(struc, columns, slab) -> (fl_primary, fl_secondary)

Build frame lines for analysis in both directions (for crossing beam deflection method).
"""
function build_frame_lines_both_directions(struc, columns, slab)
    l1 = slab.spans.primary
    l2 = slab.spans.secondary
    
    fl_primary = build_frame_line(struc, columns, l2, :x)
    fl_secondary = build_frame_line(struc, columns, l1, :y)
    
    return (fl_primary, fl_secondary)
end

# =============================================================================
# Load Computation
# =============================================================================

"""
    compute_column_axial_loads(struc, columns, slab_cell_indices, sw_estimate) -> Vector{Float64}

Compute factored axial loads Pu (in kips) for each column from tributary areas.

Uses `col.tributary_cell_areas` which maps cell_idx → area in m².
"""
function compute_column_axial_loads(struc, columns, slab_cell_indices, sw_estimate)::Vector{Float64}
    n_cols = length(columns)
    Pu = Vector{Float64}(undef, n_cols)
    
    for (i, col) in enumerate(columns)
        load = 0.0kip
        
        for (cell_idx, area_m2) in col.tributary_cell_areas
            cell_idx in slab_cell_indices || continue
            cell = struc.cells[cell_idx]
            area = area_m2 * u"m^2"
            
            sw = iszero(cell.self_weight) ? sw_estimate : cell.self_weight
            qD = cell.sdl + sw
            qL = cell.live_load
            q_factored = qD * 1.2 + qL * 1.6
            
            load += q_factored * area
        end
        
        Pu[i] = ustrip(kip, load)
    end
    
    return Pu
end

# =============================================================================
# Asap Model Updates
# =============================================================================

"""
    update_asap_column_sections!(struc, columns, material::Concrete)

Propagate final column geometry to Asap model after design converges.

Updates Asap elements with final column sections so subsequent structural 
analyses reflect the actual column sizes.
"""
function update_asap_column_sections!(struc, columns, material::Concrete)
    model = struc.asap_model
    
    for col in columns
        section = col.base.section
        isnothing(section) && continue
        
        asap_sec = to_asap_section(section, material)
        
        for seg_idx in col.base.segment_indices
            edge_idx = struc.segments[seg_idx].edge_idx
            if edge_idx > 0 && edge_idx <= length(model.elements)
                model.elements[edge_idx].section = asap_sec
            end
        end
    end
    
    # Re-process model with updated sections
    if model.processed
        Asap.process!(model)
    end
end

# =============================================================================
# Method Applicability Checks
# =============================================================================

"""
    check_pattern_loading_requirement(moment_results; verbose=false, threshold=0.75)

Check if pattern loading may be required per ACI 318-14 §6.4.3.2.

When L/D > 0.75, pattern loading can increase peak moments by up to 15%.
Issues a warning if the ratio exceeds the threshold.
"""
function check_pattern_loading_requirement(moment_results; verbose::Bool=false, threshold::Float64=0.75)
    qL = moment_results.qL
    qD = moment_results.qD
    
    qD_val = ustrip(qD)
    if qD_val < 1e-10
        return  # No dead load, skip check
    end
    
    ratio = ustrip(qL) / qD_val
    
    if ratio > threshold
        @warn "L/D = $(round(ratio, digits=2)) > $threshold. " *
              "Pattern loading may be required per ACI 318-14 §6.4.3.2. " *
              "Results may underestimate peak moments by up to 15%." qL qD
    elseif verbose
        @debug "Pattern loading check" L_D_ratio=round(ratio, digits=2) threshold=threshold status="OK"
    end
end

"""
    enforce_method_applicability(method::DDM, struc, slab, columns; verbose=false)

Enforce that DDM is valid for the given geometry. Throws if not applicable.
"""
function enforce_method_applicability(method::DDM, struc, slab, columns; verbose::Bool=false, ρ_concrete::Density = NWC_4000.ρ)
    if verbose
        @debug "───────────────────────────────────────────────────────────────────"
        @debug "CHECKING DDM APPLICABILITY (ACI 318-19 §8.10.2)"
        @debug "───────────────────────────────────────────────────────────────────"
    end
    
    result = check_ddm_applicability(struc, slab, columns; throw_on_failure=true, ρ_concrete=ρ_concrete)
    
    if verbose && result.ok
        @debug "DDM applicability check: ✓ PASSED"
    end
end

"""
    enforce_method_applicability(method::EFM, struc, slab, columns; verbose=false)

Enforce that EFM is valid for the given geometry. Throws if not applicable.
"""
function enforce_method_applicability(method::EFM, struc, slab, columns; verbose::Bool=false, kwargs...)
    if verbose
        @debug "───────────────────────────────────────────────────────────────────"
        @debug "CHECKING EFM APPLICABILITY (ACI 318-19 §8.11)"
        @debug "───────────────────────────────────────────────────────────────────"
    end
    
    result = check_efm_applicability(struc, slab, columns; throw_on_failure=true)
    
    if verbose && result.ok
        @debug "EFM applicability check: ✓ PASSED"
    end
end

"""
    enforce_method_applicability(method::FEA, struc, slab, columns; verbose=false)

FEA has no geometric restrictions — always applicable.
"""
function enforce_method_applicability(method::FEA, struc, slab, columns; verbose::Bool=false, kwargs...)
    n_cols = length(columns)
    if n_cols < 2
        error("FEA requires at least 2 supporting columns; found $n_cols")
    end
    if verbose
        @debug "───────────────────────────────────────────────────────────────────"
        @debug "FEA APPLICABILITY: ✓ No geometric restrictions"
        @debug "  $(n_cols) columns, target edge = $(method.target_edge)"
        @debug "───────────────────────────────────────────────────────────────────"
    end
end

