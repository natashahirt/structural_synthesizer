# =============================================================================
# Flat Plate Design Pipeline (DDM / MDDM / EFM)
# =============================================================================
#
# Complete design workflow for cast-in-place flat plate slabs using:
# - DDM: Direct Design Method (ACI 318 Table coefficients)
# - MDDM: Modified Direct Design Method (simplified coefficients)
# - EFM: Equivalent Frame Method (full stiffness-based analysis) [future]
#
# Reference: ACI 318-19, StructurePoint DE-Two-Way-Flat-Plate Example
#
# =============================================================================
# WORKFLOW
# =============================================================================
#
#  1. Identify supporting columns and compute tributary axial loads (Pu)
#  2. Estimate initial slab thickness and column sizes
#  3. Run moment analysis (DDM/MDDM coefficients or EFM) → get Mu at columns
#  4. Design columns via P-M interaction → get actual column sizes
#  5. If column sizes changed significantly → re-run analysis (step 3)
#  6. Check punching shear with real columns
#  7. If punching fails → increase slab thickness → loop back to step 3
#  8. Check two-way deflection (crossing beam method per StructurePoint)
#  9. Check one-way shear
# 10. Design reinforcement
# 11. Return design results
#
# =============================================================================

using Logging

# Import types we need from parent module
# (already available via StructuralSizer includes)

# =============================================================================
# Main Pipeline Function
# =============================================================================

"""
    size_flat_plate!(struc, slab, column_opts; opts, method, kwargs...)

Design a flat plate slab with integrated column P-M design.

This is the complete ACI 318 design workflow that:
1. Computes column axial loads from Voronoi tributary areas
2. Iterates between moment analysis and column P-M design
3. Checks punching shear with combined stress (Vu + γv×Mub)
4. Verifies two-way deflection using crossing beam method
5. Designs strip reinforcement per ACI moment distribution

# Arguments
- `struc::BuildingStructure`: Structure with skeleton, cells, columns, tributary cache
- `slab::Slab`: Slab to design (references cells via cell_indices)
- `column_opts::ConcreteColumnOptions`: Options for column P-M optimization

# Keyword Arguments
- `opts::CIPOptions = CIPOptions()`: Design options (φ factors, λ, etc.)
- `method::Symbol = :ddm`: Analysis method
  - `:ddm` - Direct Design Method (ACI 318 Table 8.10.4.2 coefficients)
  - `:mddm` - Modified DDM (simplified: 0.65 M0 negative, 0.35 M0 positive)
  - `:efm` - Equivalent Frame Method [placeholder, uses DDM for now]
- `material::Concrete = NWC_4000`: Slab concrete (also used for self-weight)
- `fy::Pressure = 60u"ksi"`: Rebar yield strength
- `cover::Length = 0.75u"inch"`: Clear cover
- `bar_size::Int = 5`: Typical bar size (#5 = 0.625" diameter)
- `max_iterations::Int = 10`: Maximum design iterations
- `column_tol::Float64 = 0.05`: Column size change tolerance to trigger re-analysis
- `verbose::Bool = false`: Enable @debug logging for engineer verification

# Returns
Named tuple with:
- `slab_result::FlatPlatePanelResult`: Geometry, moments, strip reinforcement, checks
- `column_results::Dict{Int, ColumnDesignSummary}`: Column designs keyed by index

# Mutates
- Updates `col.c1`, `col.c2` on supporting columns after P-M design
- Updates `cell.self_weight` after slab thickness is finalized

# Example
```julia
# Default DDM analysis
result = size_flat_plate!(struc, slab, ConcreteColumnOptions())

# With custom options
opts = CIPOptions(φ_shear=0.75, λ=0.85)  # Lightweight concrete
result = size_flat_plate!(struc, slab, ConcreteColumnOptions();
    opts = opts,
    method = :ddm,
    verbose = true
)
```

# Reference
- ACI 318-19 Sections 8.10 (DDM), 8.11 (EFM)
- StructurePoint DE-Two-Way-Flat-Plate Example
"""
function size_flat_plate!(
    struc,
    slab,
    column_opts;
    opts::CIPOptions = CIPOptions(),
    method::Symbol = :ddm,
    material = NWC_4000,
    fy::Pressure = 60u"ksi",
    cover::Length = 0.75u"inch",
    bar_size::Int = 5,
    max_iterations::Int = 10,
    column_tol::Float64 = 0.05,
    verbose::Bool = false
)
    # Validate method
    method in (:ddm, :mddm, :efm) || error("method must be :ddm, :mddm, or :efm")
    
    # Extract design parameters from options
    φ_flexure = opts.φ_flexure
    φ_shear = opts.φ_shear
    λ = opts.λ
    
    # =========================================================================
    # PHASE 1: INPUT SUMMARY & INITIALIZATION
    # =========================================================================
    fc = material.fc′
    γ_concrete = material.ρ
    Es = 29000u"ksi"
    Ecs = Ec(fc)
    
    bar_diameter = _bar_diameter(bar_size)
    slab_cell_indices = Set(slab.cell_indices)
    
    # Helper for self-weight calculation (DRY)
    _sw(h) = uconvert(u"psf", h * γ_concrete)
    
    method_name = Dict(:ddm => "DDM", :mddm => "MDDM", :efm => "EFM")[method]
    
    if verbose
        @debug "═══════════════════════════════════════════════════════════════════"
        @debug "FLAT PLATE DESIGN - $method_name (ACI 318-19)"
        @debug "═══════════════════════════════════════════════════════════════════"
        @debug "Panel geometry" primary_span=slab.spans.primary secondary_span=slab.spans.secondary n_cells=length(slab.cell_indices)
        @debug "Materials" fc=fc fy=fy wc=uconvert(u"pcf", γ_concrete)
        @debug "Options" φ_flexure=φ_flexure φ_shear=φ_shear λ=λ
    end
    
    # =========================================================================
    # PHASE 2: IDENTIFY SUPPORTING COLUMNS
    # =========================================================================
    supporting_columns = _find_supporting_columns(struc, slab_cell_indices)
    n_cols = length(supporting_columns)
    
    if n_cols == 0
        error("No supporting columns found for slab. Ensure tributary areas are computed.")
    end
    
    if verbose
        @debug "SUPPORTING COLUMNS" n_cols=n_cols
        for (i, col) in enumerate(supporting_columns)
            trib = column_tributary_area(struc, col)
            @debug "Column $i" vertex=col.vertex_idx position=col.position A_trib=trib
        end
    end
    
    # =========================================================================
    # PHASE 3: INITIAL ESTIMATES
    # =========================================================================
    ln_x = slab.spans.primary
    ln_y = slab.spans.secondary
    ln_max = max(ln_x, ln_y)
    
    has_edge = any(col.position != :interior for col in supporting_columns)
    h = min_thickness_flat_plate(ln_max; discontinuous_edge=has_edge)
    
    # Estimate self-weight from initial thickness
    sw_estimate = _sw(h)
    
    if verbose
        @debug "───────────────────────────────────────────────────────────────────"
        @debug "INITIAL ESTIMATES"
        @debug "───────────────────────────────────────────────────────────────────"
        @debug "Slab thickness" ln_max=ln_max h_min=h reason="ACI Table 8.3.1.1"
        @debug "Estimated self-weight" sw=sw_estimate
    end
    
    # =========================================================================
    # PHASE 4: COMPUTE COLUMN AXIAL LOADS (Pu)
    # =========================================================================
    Pu = _compute_column_axial_loads(struc, supporting_columns, slab_cell_indices, sw_estimate)
    
    if verbose
        @debug "───────────────────────────────────────────────────────────────────"
        @debug "COLUMN AXIAL LOADS (Pu = 1.2D + 1.6L)"
        @debug "───────────────────────────────────────────────────────────────────"
        for (i, col) in enumerate(supporting_columns)
            @debug "Column $i ($(col.position))" Pu=Pu[i]*u"kip"
        end
    end
    
    # Initialize column sizes if not set
    for (i, col) in enumerate(supporting_columns)
        if isnothing(col.c1) || col.c1 <= 0u"inch"
            col.c1 = estimate_column_size_from_span(ln_max)
            col.c2 = col.c1
        end
    end
    
    # =========================================================================
    # PHASE 5-9: ITERATIVE DESIGN LOOP
    # =========================================================================
    efm_results = nothing
    column_result = nothing
    punching_results = Dict{Int, Any}()
    final_deflection = 0.0u"inch"
    
    for iter in 1:max_iterations
        if verbose
            @debug "═══════════════════════════════════════════════════════════════════"
            @debug "ITERATION $iter"
            @debug "═══════════════════════════════════════════════════════════════════"
        end
        
        # -----------------------------------------------------------------
        # STEP 5: Moment Analysis with current geometry
        # -----------------------------------------------------------------
        efm_results = _run_moment_analysis(
            struc, slab, supporting_columns, h, fc, Ecs, γ_concrete;
            method=method, verbose=verbose
        )
        
        Mu = efm_results.column_moments  # kip-ft at each column
        
        # -----------------------------------------------------------------
        # STEP 6: Column P-M Design
        # -----------------------------------------------------------------
        if verbose
            @debug "───────────────────────────────────────────────────────────────────"
            @debug "COLUMN P-M DESIGN"
            @debug "───────────────────────────────────────────────────────────────────"
        end
        
        # Build geometries from column heights
        geometries = [
            ConcreteMemberGeometry(
                ustrip(u"m", col.base.L);
                Lu = ustrip(u"m", col.base.L),
                k = 1.0,
                braced = true
            )
            for col in supporting_columns
        ]
        
        column_result = size_columns(Pu, Mu, geometries, column_opts)
        
        # -----------------------------------------------------------------
        # STEP 7: Update column sizes, check if EFM re-run needed
        # -----------------------------------------------------------------
        columns_changed_significantly = false
        
        for (i, col) in enumerate(supporting_columns)
            section = column_result.sections[i]
            c1_new = section.b
            c2_new = section.h
            
            Δc1 = abs(ustrip(u"inch", c1_new) - ustrip(u"inch", col.c1)) / 
                  max(ustrip(u"inch", col.c1), 1.0)
            
            if Δc1 > column_tol
                columns_changed_significantly = true
            end
            
            if verbose
                status = Δc1 > column_tol ? "CHANGED" : "unchanged"
                @debug "Column $i" Pu=Pu[i]*u"kip" Mu=Mu[i]*u"kip*ft" 
                                 old_size="$(col.c1)×$(col.c2)"
                                 new_size="$(c1_new)×$(c2_new)"
                                 ρg=round(section.ρg, digits=3)
                                 status=status
            end
            
            # Always update to P-M designed size
            col.c1 = c1_new
            col.c2 = c2_new
        end
        
        if columns_changed_significantly
            if verbose
                @debug "⟳ Column sizes changed >$(round(column_tol*100))%, re-running EFM..."
            end
            continue
        end
        
        # -----------------------------------------------------------------
        # STEP 8: Punching Shear Check
        # -----------------------------------------------------------------
        if verbose
            @debug "───────────────────────────────────────────────────────────────────"
            @debug "PUNCHING SHEAR CHECK (ACI 22.6)"
            @debug "───────────────────────────────────────────────────────────────────"
        end
        
        d = effective_depth(h, cover, bar_diameter)
        punching_ok = true
        
        for (i, col) in enumerate(supporting_columns)
            Vu = efm_results.column_shears[i]
            Mub = efm_results.unbalanced_moments[i]
            
            result = _check_punching_for_column(
                col, Vu, Mub, d, h, fc;
                verbose=verbose, col_idx=i, λ=λ, φ_shear=φ_shear
            )
            
            col_idx_global = findfirst(==(col), struc.columns)
            punching_results[col_idx_global] = result
            
            if !result.ok
                punching_ok = false
            end
        end
        
        # -----------------------------------------------------------------
        # STEP 9: If punching fails, increase slab thickness
        # -----------------------------------------------------------------
        if !punching_ok
            h_new = h + 0.5u"inch"
            h_initial = min_thickness_flat_plate(ln_max; discontinuous_edge=has_edge)
            
            if h_new > 1.5 * h_initial
                @error "Slab thickness exceeded 1.5× minimum ($(1.5*h_initial)). Consider shear reinforcement."
                error("Punching shear cannot be resolved by thickness increase alone.")
            end
            
            h = h_new
            sw_estimate = _sw(h)
            Pu = _compute_column_axial_loads(struc, supporting_columns, slab_cell_indices, sw_estimate)
            
            if verbose
                @warn "Punching shear FAILED. Increasing slab thickness: h → $h"
            end
            continue
        end
        
        # -----------------------------------------------------------------
        # STEP 10: Two-Way Deflection Check (Crossing Beam Method)
        # -----------------------------------------------------------------
        if verbose
            @debug "───────────────────────────────────────────────────────────────────"
            @debug "TWO-WAY DEFLECTION CHECK (StructurePoint Crossing Beam)"
            @debug "───────────────────────────────────────────────────────────────────"
        end
        
        deflection_result = _check_two_way_deflection(
            efm_results, h, d, fc, fy, Es, Ecs, slab.spans, γ_concrete,
            supporting_columns;
            verbose=verbose, limit_type=opts.deflection_limit
        )
        final_deflection = deflection_result.Δ_total
        Δ_limit = deflection_result.Δ_limit
        
        if !deflection_result.ok
            h_new = h + 0.5u"inch"
            h = h_new
            sw_estimate = _sw(h)
            Pu = _compute_column_axial_loads(struc, supporting_columns, slab_cell_indices, sw_estimate)
            
            if verbose
                @warn "Deflection FAILED ($(deflection_result.Δ_total) > $(Δ_limit)). Increasing h → $h"
            end
            continue
        end
        
        # -----------------------------------------------------------------
        # STEP 11: One-Way Shear Check
        # -----------------------------------------------------------------
        if verbose
            @debug "───────────────────────────────────────────────────────────────────"
            @debug "ONE-WAY SHEAR CHECK (ACI 22.5)"
            @debug "───────────────────────────────────────────────────────────────────"
        end
        
        owv_result = _check_one_way_shear(efm_results, d, fc; verbose=verbose, λ=λ, φ_shear=φ_shear)
        
        if !owv_result.ok
            h_new = h + 0.5u"inch"
            h = h_new
            sw_estimate = _sw(h)
            Pu = _compute_column_axial_loads(struc, supporting_columns, slab_cell_indices, sw_estimate)
            
            if verbose
                @warn "One-way shear FAILED. Increasing h → $h"
            end
            continue
        end
        
        # -----------------------------------------------------------------
        # STEP 12: Integrity Reinforcement
        # -----------------------------------------------------------------
        cell = struc.cells[first(slab.cell_indices)]
        integrity = integrity_reinforcement(
            cell.area, cell.sdl + sw_estimate, cell.live_load, fy
        )
        
        if verbose
            @debug "───────────────────────────────────────────────────────────────────"
            @debug "INTEGRITY REINFORCEMENT (ACI 8.7.4.2)"
            @debug "───────────────────────────────────────────────────────────────────"
            @debug "Required" As_integrity=integrity.As_integrity Pu_resist=integrity.Pu_integrity
        end
        
        # -----------------------------------------------------------------
        # STEP 13: Design Reinforcement
        # -----------------------------------------------------------------
        if verbose
            @debug "───────────────────────────────────────────────────────────────────"
            @debug "REINFORCEMENT DESIGN"
            @debug "───────────────────────────────────────────────────────────────────"
        end
        
        rebar_design = _design_strip_reinforcement(
            efm_results, h, d, fc, fy, cover;
            verbose=verbose
        )
        
        # -----------------------------------------------------------------
        # STEP 14: Update cell self-weights
        # -----------------------------------------------------------------
        sw_final = _sw(h)
        for cell_idx in slab.cell_indices
            struc.cells[cell_idx].self_weight = sw_final
        end
        
        # -----------------------------------------------------------------
        # STEP 15: Build and return results
        # -----------------------------------------------------------------
        if verbose
            @debug "═══════════════════════════════════════════════════════════════════"
            @debug "DESIGN CONVERGED ✓"
            @debug "═══════════════════════════════════════════════════════════════════"
            @debug "Final slab" h=h sw=sw_final
            @debug "Final columns" sizes=["$(c.c1)×$(c.c2)" for c in supporting_columns]
            @debug "Iterations" n=iter
        end
        
        slab_result = _build_slab_result(
            h, sw_final, efm_results, rebar_design, 
            final_deflection, Δ_limit, punching_results
        )
        
        column_results = _build_column_results(
            struc, supporting_columns, column_result, 
            Pu, efm_results.column_moments, punching_results
        )
        
        return (slab_result=slab_result, column_results=column_results)
    end
    
    error("Design did not converge in $max_iterations iterations")
end

# =============================================================================
# Helper Functions
# =============================================================================

"""Find columns whose tributary area includes any of the slab's cells."""
function _find_supporting_columns(struc, slab_cell_indices::Set{Int})::Vector
    supporting = typeof(struc.columns)()  # Properly typed vector
    for col in struc.columns
        by_cell = column_tributary_by_cell(struc, col)
        if any(cell_idx in slab_cell_indices for cell_idx in keys(by_cell))
            push!(supporting, col)
        end
    end
    return supporting
end

"""Compute factored axial loads Pu (in kips) for each column from tributary areas."""
function _compute_column_axial_loads(struc, supporting_columns, slab_cell_indices, sw_estimate)::Vector{Float64}
    n_cols = length(supporting_columns)
    Pu = Vector{Float64}(undef, n_cols)
    
    for (i, col) in enumerate(supporting_columns)
        by_cell = column_tributary_by_cell(struc, col)
        load = 0.0u"kip"
        
        for (cell_idx, area) in by_cell
            cell_idx in slab_cell_indices || continue
            cell = struc.cells[cell_idx]
            
            # Use estimated self-weight if cell.self_weight is zero
            sw = iszero(cell.self_weight) ? sw_estimate : cell.self_weight
            
            # Factored load: 1.2D + 1.6L
            qD = cell.sdl + sw
            qL = cell.live_load
            q_factored = qD * 1.2 + qL * 1.6
            
            load += q_factored * area
        end
        
        Pu[i] = ustrip(u"kip", load)
    end
    
    return Pu
end

"""
    _run_moment_analysis(struc, slab, columns, h, fc, Ecs, γ_concrete; method, verbose)

Run moment analysis using DDM, MDDM, or EFM coefficients.

# DDM Coefficients (ACI 318-14 Table 8.10.4.2)
For end span with no edge beam:
- Exterior negative: 0.26 M0
- Positive: 0.52 M0  
- Interior negative: 0.70 M0

# MDDM Coefficients (Simplified)
- Negative: 0.65 M0
- Positive: 0.35 M0
"""
function _run_moment_analysis(struc, slab, supporting_columns, h, fc, Ecs, γ_concrete; 
                               method::Symbol=:ddm, verbose=false)
    # Build span properties
    l1 = slab.spans.primary  # Span in analysis direction
    l2 = slab.spans.secondary  # Tributary width
    
    # Average column dimensions
    n_cols = length(supporting_columns)
    c1_avg = sum(ustrip(u"inch", col.c1) for col in supporting_columns) / n_cols * u"inch"
    c2_avg = sum(ustrip(u"inch", col.c2) for col in supporting_columns) / n_cols * u"inch"
    
    # Clear span (l1 - average column dimension)
    ln = clear_span(l1, c1_avg)
    
    # Get loads from first cell
    cell = struc.cells[first(slab.cell_indices)]
    sw = uconvert(u"psf", h * γ_concrete)
    qD = cell.sdl + sw
    qL = cell.live_load
    qu = 1.2 * qD + 1.6 * qL
    
    # Total static moment: M0 = qu × l2 × ln² / 8
    M0 = total_static_moment(qu, l2, ln)
    
    # Determine if span is exterior or interior
    has_exterior = any(col.position != :interior for col in supporting_columns)
    
    # Get moment coefficients based on method
    if method == :mddm
        # Modified DDM: simplified coefficients
        coef_neg = 0.65
        coef_pos = 0.35
        M_neg_ext = coef_neg * M0
        M_neg_int = coef_neg * M0
        M_pos = coef_pos * M0
    else  # :ddm or :efm (EFM uses DDM for now)
        # DDM: ACI 318-14 Table 8.10.4.2
        # For flat plate with no edge beam, exterior span:
        M_neg_ext = 0.26 * M0  # Exterior negative
        M_neg_int = 0.70 * M0  # Interior negative (first interior support)
        M_pos = 0.52 * M0      # Positive
    end
    
    if verbose
        method_name = Dict(:ddm => "DDM", :mddm => "MDDM", :efm => "EFM (DDM)")[method]
        @debug "───────────────────────────────────────────────────────────────────"
        @debug "MOMENT ANALYSIS ($method_name)"
        @debug "───────────────────────────────────────────────────────────────────"
        @debug "Geometry" l1=l1 l2=l2 ln=ln c_avg=c1_avg h=h
        @debug "Loads" qD=qD qL=qL qu=qu
        @debug "Total static moment" M0=uconvert(u"kip*ft", M0)
        @debug "Moments" M_neg_ext=uconvert(u"kip*ft", M_neg_ext) M_pos=uconvert(u"kip*ft", M_pos) M_neg_int=uconvert(u"kip*ft", M_neg_int)
    end
    
    # Column moments and shears
    column_moments = Float64[]
    column_shears = typeof(1.0u"kip")[]
    unbalanced_moments = typeof(1.0u"kip*ft")[]
    
    # Shear at column (from equilibrium)
    V_base = qu * l2 * ln / 2
    
    for col in supporting_columns
        if col.position == :interior
            # Interior column: moment from both sides approximately equal
            Mu = ustrip(u"kip*ft", M_neg_int)
            # Unbalanced moment is zero at symmetric interior (moments balance)
            Mub = 0.0u"kip*ft"
        else
            # Edge/corner column: exterior negative moment governs
            Mu = ustrip(u"kip*ft", M_neg_ext)
            # At edge, the exterior moment itself IS the unbalanced moment
            # (there's moment on one side, essentially nothing on the exterior)
            Mub = M_neg_ext
        end
        push!(column_moments, Mu)
        push!(column_shears, V_base)
        push!(unbalanced_moments, abs(Mub))
    end
    
    return (
        M0 = M0,
        M_neg_ext = M_neg_ext,
        M_neg_int = M_neg_int,
        M_pos = M_pos,
        qu = qu,
        qD = qD,
        qL = qL,
        l1 = l1,
        l2 = l2,
        ln = ln,
        column_moments = column_moments,
        column_shears = column_shears,
        unbalanced_moments = unbalanced_moments,
        Vu_max = V_base,
        c_avg = c1_avg
    )
end

"""Check punching shear for a single column."""
function _check_punching_for_column(col, Vu, Mub, d, h, fc; verbose=false, col_idx=1, λ=1.0, φ_shear=0.75)
    c1 = col.c1
    c2 = col.c2
    
    if col.position == :interior
        geom = punching_geometry_interior(c1, c2, d)
        Jc = polar_moment_Jc_interior(c1, c2, d)
        γv_val = gamma_v(c1, c2)
        cAB = (c1 + d) / 2  # Distance to critical section centroid
    elseif col.position == :edge
        geom = punching_geometry_edge(c1, c2, d)
        Jc = polar_moment_Jc_edge(c1, c2, d)
        γv_val = gamma_v(c1, c2)
        cAB = geom.cAB
    else  # :corner
        geom = punching_geometry_corner(c1, c2, d)
        # Approximate for corner
        Jc = polar_moment_Jc_edge(c1, c2, d) / 2
        γv_val = gamma_v(c1, c2)
        cAB = geom.cAB
    end
    
    b0 = geom.b0
    
    # Combined punching stress
    vu = combined_punching_stress(Vu, Mub, b0, d, γv_val, Jc, cAB)
    
    # Punching capacity stress per ACI 22.6.5.2
    # β = column aspect ratio (long/short dimension)
    c1_in = ustrip(u"inch", c1)
    c2_in = ustrip(u"inch", c2)
    β = max(c1_in, c2_in) / max(min(c1_in, c2_in), 1.0)
    
    # αs = location factor (40 interior, 30 edge, 20 corner)
    αs = punching_αs(col.position)
    
    # Nominal capacity stress
    vc = punching_capacity_stress(fc, β, αs, b0, d; λ=λ)
    φvc = φ_shear * vc
    
    ok = vu <= φvc
    ratio = ustrip(u"psi", vu) / ustrip(u"psi", φvc)
    
    if verbose
        status = ok ? "✓ PASS" : "✗ FAIL"
        @debug "Column $col_idx ($(col.position))" c1=c1 c2=c2 b0=b0 β=round(β, digits=2) αs=αs
        @debug "  Demand" Vu=Vu γv=round(γv_val, digits=3) Mub=Mub
        @debug "  Stress" vu=round(ustrip(u"psi", vu), digits=1) φvc=round(ustrip(u"psi", φvc), digits=1) ratio=round(ratio, digits=2) status=status
    end
    
    return (ok=ok, ratio=ratio, vu=vu, φvc=φvc, b0=b0, Jc=Jc)
end

"""
    _check_two_way_deflection(efm_results, h, d, fc, fy, Es, Ecs, spans, γ_concrete, columns; kwargs)

Two-way slab deflection check using StructurePoint's crossing beam method.

This properly computes mid-panel deflection by:
1. Computing frame strip deflection (fixed-end + rotation at supports)
2. Distributing to column and middle strips via Load Distribution Factors
3. Combining: Δ_panel = Δcx + Δmx (for square panels)

Reference: StructurePoint DE-Two-Way-Flat-Plate, Section 6 (Pages 55-58)
"""
function _check_two_way_deflection(efm_results, h, d, fc, fy, Es, Ecs, spans, γ_concrete,
                                    supporting_columns;
                                    verbose=false, limit_type::Symbol=:L_360)
    l1 = spans.primary
    l2 = spans.secondary
    ln = efm_results.ln
    
    # Determine span position for LDF
    has_exterior = any(col.position != :interior for col in supporting_columns)
    position = has_exterior ? :exterior : :interior
    
    # Service loads (unfactored)
    w_D = efm_results.qD * l2  # Dead load line load
    w_L = efm_results.qL * l2  # Live load line load
    w_service = w_D + w_L
    
    # Frame strip gross moment of inertia
    Ig_frame = slab_moment_of_inertia(l2, h)
    
    # Column/middle strip gross I (each is half the frame width)
    Ig_cs = slab_moment_of_inertia(l2/2, h)
    Ig_ms = slab_moment_of_inertia(l2/2, h)
    
    # Cracking moment
    fr_val = fr(fc)
    Mcr = cracking_moment(fr_val, Ig_frame, h)
    
    # Service moment at midspan (approximately)
    Ma = efm_results.M_pos / 1.4  # Unfactor from 1.2D + 1.6L → D + L
    
    # Effective moment of inertia for frame
    As_est = minimum_reinforcement(l2, h, fy)
    Icr = cracked_moment_of_inertia(As_est, l2, d, Ecs, Es)
    Ie_frame = effective_moment_of_inertia(Mcr, Ma, Ig_frame, Icr)
    
    # For uncracked section (dead load only case), Ie = Ig
    Ie_uncracked = Ig_frame
    
    # Load Distribution Factors
    LDF_c = load_distribution_factor(:column, position)
    LDF_m = load_distribution_factor(:middle, position)
    
    # =======================================================================
    # Frame fixed-end deflection
    # =======================================================================
    # For continuous span: Δ = wl⁴/(384EI) (fixed-fixed coefficient)
    Δ_frame_D = frame_deflection_fixed(w_D, l1, Ecs, Ie_uncracked)
    Δ_frame_DL = frame_deflection_fixed(w_service, l1, Ecs, Ie_frame)
    
    # =======================================================================
    # Strip fixed-end deflections
    # =======================================================================
    # Δstrip,fixed = LDF × Δframe,fixed × (Ie_frame/Ig_strip)
    Δc_fixed_D = strip_deflection_fixed(Δ_frame_D, LDF_c, Ie_uncracked, Ig_cs)
    Δm_fixed_D = strip_deflection_fixed(Δ_frame_D, LDF_m, Ie_uncracked, Ig_ms)
    
    # For total load case, use cracked stiffness
    Δc_fixed_DL = strip_deflection_fixed(Δ_frame_DL, LDF_c, Ie_frame, Ig_cs)
    Δm_fixed_DL = strip_deflection_fixed(Δ_frame_DL, LDF_m, Ie_frame, Ig_ms)
    
    # =======================================================================
    # Rotation contribution (simplified - assume small)
    # =======================================================================
    # Full StructurePoint method computes θ = M_net/Kec at each support
    # For now, use approximate 10% addition for rotation effects
    Δc_rotation = 0.10 * Δc_fixed_DL
    Δm_rotation = 0.10 * Δm_fixed_DL
    
    # Total immediate strip deflections
    Δcx_i = uconvert(u"inch", Δc_fixed_DL + Δc_rotation)
    Δmx_i = uconvert(u"inch", Δm_fixed_DL + Δm_rotation)
    
    # =======================================================================
    # Two-way panel deflection (crossing beam)
    # =======================================================================
    # For square panels: Δ_panel = Δcx + Δmx
    # For rectangular: Δ = (Δcx + Δmy)/2 + (Δcy + Δmx)/2
    # Assume square/near-square for simplicity
    Δ_panel_i = two_way_panel_deflection(Δcx_i, Δmx_i)
    
    # =======================================================================
    # Long-term deflection
    # =======================================================================
    λ_Δ = long_term_deflection_factor(2.0, 0.0)  # ξ=2.0, no compression steel
    
    # Sustained load immediate deflection (dead load only for creep)
    Δcx_D = uconvert(u"inch", Δc_fixed_D + 0.10 * Δc_fixed_D)
    Δmx_D = uconvert(u"inch", Δm_fixed_D + 0.10 * Δm_fixed_D)
    Δ_panel_D = two_way_panel_deflection(Δcx_D, Δmx_D)
    
    # Total long-term: Δ_sust × (1 + λΔ) + (Δ_total - Δ_sust)
    Δ_total = Δ_panel_D * (1 + λ_Δ) + (Δ_panel_i - Δ_panel_D)
    
    # =======================================================================
    # Limit check
    # =======================================================================
    # Map CIPOptions deflection_limit to limit type
    limit_sym = if limit_type == :L_240
        :total
    elseif limit_type == :L_480
        :sensitive
    else  # :L_360
        :immediate_ll
    end
    
    Δ_limit = deflection_limit(l1, limit_sym)
    ok = Δ_total <= Δ_limit
    
    if verbose
        status = ok ? "✓ PASS" : "✗ FAIL"
        @debug "Frame strip" Ig=Ig_frame Ie=Ie_frame Mcr=uconvert(u"kip*ft", Mcr) Ma=uconvert(u"kip*ft", Ma)
        @debug "Load distribution" LDF_c=round(LDF_c, digits=3) LDF_m=round(LDF_m, digits=3) position=position
        @debug "Strip deflections (immed)" Δcx=Δcx_i Δmx=Δmx_i
        @debug "Panel deflection" Δ_panel_i=Δ_panel_i λ_Δ=λ_Δ Δ_total=Δ_total
        @debug "Limit check" Δ_limit=Δ_limit ratio=round(ustrip(Δ_total)/ustrip(Δ_limit), digits=2) status=status
    end
    
    return (ok=ok, Δ_total=Δ_total, Δ_limit=Δ_limit, Δi=Δ_panel_i, λ_Δ=λ_Δ,
            Δcx=Δcx_i, Δmx=Δmx_i, LDF_c=LDF_c, LDF_m=LDF_m)
end

"""Check one-way shear."""
function _check_one_way_shear(efm_results, d, fc; verbose=false, λ=1.0, φ_shear=0.75)
    Vu = efm_results.Vu_max
    l2 = efm_results.l2  # Tributary width (slab width for shear)
    
    # One-way shear capacity per ACI 22.5.5.1: Vc = 2λ√f'c × bw × d
    Vc = one_way_shear_capacity(fc, l2, d; λ=λ)
    
    # Check adequacy
    result = check_one_way_shear(Vu, Vc; φ=φ_shear)
    
    if verbose
        status = result.passes ? "✓ PASS" : "✗ FAIL"
        φVc = φ_shear * Vc
        @debug "One-way shear" Vu=Vu Vc=Vc φVc=φVc ratio=round(result.ratio, digits=2) status=status
    end
    
    # Return with consistent field names
    return (ok=result.passes, ratio=result.ratio, Vu=Vu, Vc=Vc, message=result.message)
end

"""Design strip reinforcement, returning vectors of StripReinforcement."""
function _design_strip_reinforcement(efm_results, h, d, fc, fy, cover; verbose=false)
    # Column strip width = l2/2 each side (total l2)
    # Note: Per ACI 8.4.1.5, column strip width = l2/4 each side of column centerline
    #       but for design we use l2/2 as the half-width for each strip
    l2 = efm_results.l2
    cs_width = l2 / 2  # Column strip half-width
    ms_width = l2 / 2  # Middle strip half-width
    
    # Column strip moments (0.75 of negative for interior, 0.60 of positive)
    M_neg_ext_cs = 1.00 * efm_results.M_neg_ext  # 100% to column strip at exterior
    M_neg_int_cs = 0.75 * efm_results.M_neg_int  # 75% to column strip at interior
    M_pos_cs = 0.60 * efm_results.M_pos          # 60% to column strip
    
    # Middle strip moments (remainder)
    M_neg_int_ms = 0.25 * efm_results.M_neg_int  # 25% to middle strip
    M_pos_ms = 0.40 * efm_results.M_pos          # 40% to middle strip
    
    # Design column strip reinforcement
    column_strip_reinf = StripReinforcement[
        _design_single_strip(:ext_neg, M_neg_ext_cs, cs_width, d, fc, fy, h),
        _design_single_strip(:pos, M_pos_cs, cs_width, d, fc, fy, h),
        _design_single_strip(:int_neg, M_neg_int_cs, cs_width, d, fc, fy, h)
    ]
    
    # Design middle strip reinforcement
    middle_strip_reinf = StripReinforcement[
        _design_single_strip(:pos, M_pos_ms, ms_width, d, fc, fy, h),
        _design_single_strip(:int_neg, M_neg_int_ms, ms_width, d, fc, fy, h)
    ]
    
    if verbose
        @debug "Column strip" width=cs_width
        for sr in column_strip_reinf
            @debug "  $(sr.location)" Mu=uconvert(u"kip*ft", sr.Mu) As_reqd=sr.As_reqd As_provided=sr.As_provided
        end
        @debug "Middle strip" width=ms_width
        for sr in middle_strip_reinf
            @debug "  $(sr.location)" Mu=uconvert(u"kip*ft", sr.Mu) As_reqd=sr.As_reqd As_provided=sr.As_provided
        end
    end
    
    return (
        column_strip_width = cs_width,
        column_strip_reinf = column_strip_reinf,
        middle_strip_width = ms_width,
        middle_strip_reinf = middle_strip_reinf
    )
end

"""Design reinforcement for a single strip location, returning StripReinforcement."""
function _design_single_strip(location::Symbol, Mu, b, d, fc, fy, h)
    As_reqd = required_reinforcement(Mu, b, d, fc, fy)
    As_min = minimum_reinforcement(b, h, fy)
    As_design = max(As_reqd, As_min)
    
    # Select bars and spacing
    bars = _select_bars(As_design, b)
    
    return StripReinforcement(
        location,
        Mu,
        As_reqd,
        As_min,
        bars.As_provided,
        bars.bar_size,
        bars.spacing,
        bars.n_bars
    )
end

"""Get bar diameter from bar size number."""
function _bar_diameter(bar_size::Int)
    diameters = Dict(
        3 => 0.375u"inch",
        4 => 0.5u"inch",
        5 => 0.625u"inch",
        6 => 0.75u"inch",
        7 => 0.875u"inch",
        8 => 1.0u"inch",
        9 => 1.128u"inch",
        10 => 1.27u"inch",
        11 => 1.41u"inch"
    )
    return get(diameters, bar_size, 0.625u"inch")
end

"""Get bar area from bar size number."""
function _bar_area(bar_size::Int)
    areas = Dict(
        3 => 0.11u"inch^2",
        4 => 0.20u"inch^2",
        5 => 0.31u"inch^2",
        6 => 0.44u"inch^2",
        7 => 0.60u"inch^2",
        8 => 0.79u"inch^2",
        9 => 1.00u"inch^2",
        10 => 1.27u"inch^2",
        11 => 1.56u"inch^2"
    )
    return get(areas, bar_size, 0.31u"inch^2")
end

"""Select bar size and compute spacing to provide required area."""
function _select_bars(As_reqd::Area, strip_width::Length; max_spacing=18u"inch")
    # Try bar sizes from #4 to #8
    for bar_size in [4, 5, 6, 7, 8]
        Ab = _bar_area(bar_size)
        
        # Number of bars needed
        n_bars = ceil(Int, ustrip(u"inch^2", As_reqd) / ustrip(u"inch^2", Ab))
        n_bars = max(n_bars, 2)  # Minimum 2 bars
        
        # Compute spacing
        spacing = strip_width / n_bars
        
        # Check if spacing is reasonable
        if spacing <= max_spacing
            As_provided = n_bars * Ab
            return (bar_size=bar_size, n_bars=n_bars, spacing=spacing, As_provided=As_provided)
        end
    end
    
    # Fallback: use #8 bars with max density
    bar_size = 8
    Ab = _bar_area(bar_size)
    n_bars = ceil(Int, ustrip(u"inch", strip_width) / ustrip(u"inch", 6u"inch"))  # 6" spacing
    As_provided = n_bars * Ab
    spacing = strip_width / n_bars
    
    return (bar_size=bar_size, n_bars=n_bars, spacing=spacing, As_provided=As_provided)
end

"""Build FlatPlatePanelResult from design outputs."""
function _build_slab_result(h, sw, efm_results, rebar_design, Δ_total, Δ_limit, punching_results)
    # Build punching check summary
    punching_check = (
        passes = all(pr.ok for pr in values(punching_results)),
        max_ratio = maximum(pr.ratio for pr in values(punching_results); init=0.0),
        details = punching_results
    )
    
    # Build deflection check summary
    deflection_check = (
        passes = Δ_total <= Δ_limit,
        Δ_total = Δ_total,
        Δ_limit = Δ_limit,
        ratio = ustrip(Δ_total) / ustrip(Δ_limit)
    )
    
    return FlatPlatePanelResult(
        efm_results.l1,
        efm_results.l2,
        h,
        efm_results.M0,
        rebar_design.column_strip_width,
        rebar_design.column_strip_reinf,
        rebar_design.middle_strip_width,
        rebar_design.middle_strip_reinf,
        punching_check,
        deflection_check
    )
end

"""Build ColumnDesignResult dict from design outputs."""
function _build_column_results(struc, supporting_columns, column_result, Pu, Mu, punching_results)
    results = Dict{Int, Any}()
    
    for (i, col) in enumerate(supporting_columns)
        col_idx = findfirst(==(col), struc.columns)
        section = column_result.sections[i]
        
        b_in = ustrip(u"inch", section.b)
        h_in = ustrip(u"inch", section.h)
        results[col_idx] = (
            section_size = "$(b_in)×$(h_in)",
            b = section.b,
            h = section.h,
            ρg = section.ρg,
            Pu = uconvert(u"kN", Pu[i] * u"kip"),
            Mu = uconvert(u"kN*m", Mu[i] * u"kip*ft"),
            punching = punching_results[col_idx]
        )
    end
    
    return results
end

# =============================================================================
# Backward Compatibility
# =============================================================================

"""Alias for backward compatibility - use `size_flat_plate!` instead."""
const size_flat_plate_efm! = size_flat_plate!

# =============================================================================
# Exports
# =============================================================================

export size_flat_plate!, size_flat_plate_efm!
