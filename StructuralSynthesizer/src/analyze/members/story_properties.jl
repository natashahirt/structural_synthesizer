# =============================================================================
# Story Properties for Sway Magnification (ACI 318-19 §6.6.4.6)
# =============================================================================
#
# Computes story-level properties needed for sway moment magnification:
# - ΣPu: Sum of factored axial loads on all columns in story
# - ΣPc: Sum of critical buckling loads (placeholder until sections known)
# - Vus: Factored story shear
# - Δo: First-order story drift
# - lc: Story height (center-to-center of joints)
#
# These properties are assigned to each column's `story_properties` field
# after structural analysis when displacements and forces are available.
#
# =============================================================================

"""
    compute_story_properties!(struc; concrete=NWC_4000, verbose=false)

Compute and assign story properties to all columns for sway magnification.

This function should be called after structural analysis (ASAP solve) when
displacements and member forces are available. It populates the `story_properties`
field on each Column for use in ACI 318-19 sway moment magnification.

# Keyword Arguments
- `concrete`: Concrete material for Ec estimation (default: `NWC_4000`)
- `verbose`: Print diagnostic info

# Story-Level Properties (all returned as Unitful quantities)
- `ΣPu`: Sum of factored axial loads on all columns in story (Force)
- `ΣPc`: Sum of critical buckling loads (Force, estimated, refined during sizing)
- `Vus`: Factored story shear (Force)
- `Δo`: First-order story drift (Length)
- `lc`: Story height (Length)

# Notes
- ΣPc uses Ec from the provided concrete material (ACI 19.2.2.1)
- Actual ΣPc will be refined during column sizing when sections are known
- Δo is computed from ASAP analysis node displacements

# Example
```julia
# After creating model and running analysis
struc, model = create_asap_model(struc; analyze=true)

# Compute and assign story properties (uses NWC_4000 by default)
compute_story_properties!(struc; verbose=true)

# Column now has story_properties for sway magnification
col = struc.columns[1]
Q = stability_index(col.story_properties)  # Story stability index
```
"""
function compute_story_properties!(struc; concrete::StructuralSizer.Concrete = NWC_4000, verbose::Bool = false)
    # Group columns by story
    columns_by_story = Dict{Int, Vector}()
    for col in struc.columns
        story = col.story
        if !haskey(columns_by_story, story)
            columns_by_story[story] = []
        end
        push!(columns_by_story[story], col)
    end
    
    # For each story, compute properties
    for (story, cols) in columns_by_story
        props = _compute_story_props(struc, cols, story; concrete=concrete, verbose=verbose)
        
        # Assign to all columns in this story
        for col in cols
            col.story_properties = props
        end
    end
    
    if verbose
        n_stories = length(columns_by_story)
        @info "Computed story properties for $n_stories stories, $(length(struc.columns)) columns"
    end
    
    return struc
end

"""
    _compute_story_props(struc, cols, story; verbose=false) -> NamedTuple

Compute story properties for a single story level.
Returns all values as proper Unitful quantities.
"""
function _compute_story_props(struc, cols, story::Int; concrete::StructuralSizer.Concrete = NWC_4000, verbose::Bool = false)
    n_cols = length(cols)
    
    # --- Story height (lc) ---
    # Use average column length in the story
    lc = sum(col.base.L for col in cols) / n_cols
    
    # --- Sum of factored axial loads (ΣPu) ---
    # Get from ASAP results if available, otherwise estimate from tributary
    ΣPu = 0.0u"kip"
    for col in cols
        # Try to get from analysis results first
        Pu = _get_column_axial_from_analysis(struc, col)
        if isnothing(Pu)
            # Estimate from tributary area if analysis not available
            Pu = _estimate_column_axial(struc, col)
        end
        ΣPu += Pu
    end
    
    # --- Sum of critical buckling loads (ΣPc) ---
    # Use simplified formula: Pc = π²EI/(kLu)²
    # EI estimated as 0.4EcIg until section is known
    ΣPc = _estimate_Pc_sum(struc, cols; concrete=concrete)
    
    # --- Story shear (Vus) ---
    # Sum of column shears at the story level
    Vus = _estimate_story_shear(struc, cols, story)
    
    # --- First-order drift (Δo) ---
    # From ASAP analysis node displacements
    Δo = _compute_story_drift(struc, cols, story)
    
    if verbose
        @debug "Story $story properties:" ΣPu=ΣPu ΣPc=ΣPc Vus=Vus Δo=Δo lc=lc
    end
    
    return (ΣPu=ΣPu, ΣPc=ΣPc, Vus=Vus, Δo=Δo, lc=lc)
end

# --- Helper functions ---

"""
    _get_column_axial_from_analysis(struc, col) -> Union{Force, Nothing}

Extract the worst-case factored axial compression from ASAP analysis results.
Returns `nothing` if the model has not been solved.
"""
function _get_column_axial_from_analysis(struc, col)
    # Need a solved ASAP model
    if !hasfield(typeof(struc), :asap_model) || isnothing(struc.asap_model)
        return nothing
    end
    model = struc.asap_model
    hasfield(typeof(model), :processed) && !model.processed && return nothing

    element_loads = Asap.get_elemental_loads(model)

    Pu_max = 0.0  # track worst-case compression (positive = compression)
    for seg_idx in segment_indices(col)
        seg = struc.segments[seg_idx]
        edge_idx = seg.edge_idx
        edge_idx > 0 || continue

        el = model.elements[edge_idx]
        el_loads = get(element_loads, el.elementID, nothing)
        isnothing(el_loads) && continue

        fd = Asap.ElementForceAndDisplacement(el, el_loads; resolution=10)
        # Convention: negative P = compression
        min_P = minimum(fd.forces.P)
        if min_P < 0
            Pu_max = max(Pu_max, abs(min_P))
        end
    end

    Pu_max > 0 ? uconvert(u"kip", Pu_max * u"N") : nothing
end

"""Estimate column axial load from tributary area and loads. Returns Force (kip)."""
function _estimate_column_axial(struc, col)
    # Get tributary area
    trib = column_tributary_by_cell(struc, col)
    
    Pu = 0.0u"kip"
    for (cell_idx, area_m2) in trib
        cell = struc.cells[cell_idx]
        area = area_m2 * u"m^2"
        
        # Factored load (ACI strength: 1.2D + 1.6L)
        qD = cell.sdl + cell.self_weight
        qL = cell.live_load
        qu = factored_pressure(default_combo, qD, qL)
        
        Pu += uconvert(u"kip", qu * area)
    end
    
    return Pu
end

"""Estimate sum of critical buckling loads for columns in story. Returns Force (kip)."""
function _estimate_Pc_sum(struc, cols; concrete::StructuralSizer.Concrete = NWC_4000)
    # Use simplified EI = 0.4EcIg per ACI 6.6.4.4.4
    # Pc = π²(0.4EcIg)/(kLu)²
    
    Ec_val = StructuralSizer.Ec(concrete)
    ΣPc = 0.0u"kip"
    
    for col in cols
        # Get column dimensions (fall back to defaults if not set)
        c1 = col.c1
        c2 = col.c2
        if isnothing(c1) || isnothing(c2)
            @warn "Column dimensions not yet sized — using 18\" default for stability index" col.base.edge_idx c1 c2 maxlog=1
            c1 = something(c1, 18.0u"inch")
            c2 = something(c2, 18.0u"inch")
        end
        
        # Gross moment of inertia (assuming rectangular)
        Ig = c1 * c2^3 / 12  # About weak axis (conservative)
        
        # Effective stiffness (simplified per ACI 6.6.4.4.4)
        EI_eff = 0.4 * Ec_val * Ig
        
        # Unsupported length
        Lu = col.base.Lu
        k = col.base.Ky  # Use y-axis (weak)
        
        # Critical buckling load
        if ustrip(k * Lu) > 0
            Pc = π^2 * EI_eff / (k * Lu)^2
            ΣPc += uconvert(u"kip", Pc)
        end
    end
    
    return ΣPc
end

"""Estimate story shear (placeholder - uses ΣPu × 0.05 as lateral fraction). Returns Force."""
function _estimate_story_shear(struc, cols, story::Int)
    # Placeholder: assume 5% of total vertical load as lateral
    # This should be replaced with actual lateral analysis results
    ΣPu = sum(_estimate_column_axial(struc, col) for col in cols)
    return 0.05 * ΣPu
end

"""Compute story drift from ASAP analysis (placeholder). Returns Length."""
function _compute_story_drift(struc, cols, story::Int)
    # Placeholder: return 0.5 inch as typical first-order drift
    # This should be extracted from ASAP node displacements
    # TODO: Implement extraction from ASAP results
    return 0.5u"inch"
end
