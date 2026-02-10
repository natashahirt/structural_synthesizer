# =============================================================================
# Flat Plate Design Pipeline
# =============================================================================
#
# Main orchestration for flat plate design per ACI 318-19.
# This file contains only the high-level workflow - all helper functions
# are in separate modules (helpers.jl, checks.jl, reinforcement.jl, results.jl).
#
# Workflow:
#   Phase A: Moment Analysis (method-specific: DDM or EFM)
#   Phase B: Design Loop (shared)
#     1. Column P-M design
#     2. Punching shear check
#     3. Two-way deflection check  
#     4. One-way shear check
#     5. Reinforcement design
#
# Reference: ACI 318-19 Chapters 8, 22, 24
#
# =============================================================================

using Logging

# =============================================================================
# Main Pipeline Function
# =============================================================================

"""
    size_flat_plate!(struc, slab, column_opts; method, opts, max_iterations, verbose)

Design a flat plate slab with integrated column P-M design.

# Analysis Methods
- `DDM()` - Direct Design Method (ACI 318 coefficient-based) - default
- `DDM(:simplified)` - Modified DDM with simplified coefficients
- `EFM()` - Equivalent Frame Method (ASAP stiffness analysis)

# Design Workflow
1. Identify supporting columns from Voronoi tributary areas
2. Compute column axial loads (Pu)
3. Iterate:
   a. Run moment analysis (DDM or EFM) → MomentAnalysisResult
   b. Design columns via P-M interaction → update column sizes
   c. Check punching shear → increase h or columns if needed
   d. Check two-way deflection → increase h if needed
   e. Check one-way shear → increase h if needed
4. Design strip reinforcement per ACI 8.10.5
5. Build result structures

# Arguments
- `struc::BuildingStructure`: Structure with skeleton, cells, columns
- `slab::Slab`: Slab to design (references cells via cell_indices)
- `column_opts::ConcreteColumnOptions`: Options for column P-M optimization

# Keyword Arguments
- `method::FlatPlateAnalysisMethod = DDM()`: Analysis method
- `opts::FlatPlateOptions = FlatPlateOptions()`: Design options
- `max_iterations::Int = 10`: Maximum design iterations
- `column_tol::Float64 = 0.05`: Column size change tolerance
- `h_increment::Length = 0.5u"inch"`: Thickness rounding increment
- `verbose::Bool = false`: Enable debug logging

# Returns
Named tuple with fields:
- `slab_result::FlatPlatePanelResult`: Panel design result (thickness, reinforcement, deflection)
- `column_results::Dict`: Column P-M results keyed by global column index
- `drop_panel::Union{Nothing, DropPanelGeometry}`: Drop panel geometry (if flat slab)
- `integrity`: Structural integrity reinforcement demand (ACI 8.7.4.2)
- `integrity_check`: Pass/fail for integrity reinforcement vs provided bottom steel
- `transfer_results::Vector{Union{Nothing, NamedTuple}}`: Moment transfer reinforcement at each column (ACI 8.4.2.3)
- `ρ_prime::Float64`: Estimated compression reinforcement ratio for long-term deflection

# Example
```julia
result = size_flat_plate!(struc, slab, ConcreteColumnOptions())
result = size_flat_plate!(struc, slab, col_opts; method=EFM(), verbose=true)
```
"""
function size_flat_plate!(
    struc,
    slab,
    column_opts;
    method::FlatPlateAnalysisMethod = DDM(),
    opts::FlatPlateOptions = FlatPlateOptions(),
    max_iterations::Int = 10,
    column_tol::Float64 = 0.05,
    h_increment::Length = 0.5u"inch",
    verbose::Bool = false,
    _col_cache = nothing,
    slab_idx::Int = 0,
    drop_panel::Union{Nothing, DropPanelGeometry} = nothing,
)
    # =========================================================================
    # PHASE 1: SETUP
    # =========================================================================
    
    # Extract material parameters
    material = opts.material
    fc = material.concrete.fc′
    fy = material.rebar.Fy
    γ_concrete = material.concrete.ρ
    cover = opts.cover
    bar_size = opts.bar_size
    φ_flexure = opts.φ_flexure
    φ_shear = opts.φ_shear
    λ = isnothing(opts.λ) ? material.concrete.λ : opts.λ
    Es = material.rebar.E
    wc_pcf = ustrip(pcf, γ_concrete)          # mass density → pcf (≈ 150 for NWC)
    Ecs = Ec(fc, wc_pcf)                       # ACI 19.2.2.1.a: 33 × wc^1.5 × √f'c
    
    # Slab geometry
    slab_cell_indices = Set(slab.cell_indices)
    ln_max = max(slab.spans.primary, slab.spans.secondary)
    
    # Self-weight helper
    slab_sw(h) = slab_self_weight(h, γ_concrete)
    
    if verbose
        @debug "═══════════════════════════════════════════════════════════════════"
        @debug "FLAT PLATE DESIGN - $(method_name(method)) (ACI 318-19)"
        @debug "═══════════════════════════════════════════════════════════════════"
        @debug "Panel geometry" primary=slab.spans.primary secondary=slab.spans.secondary n_cells=length(slab.cell_indices)
        @debug "Materials" fc=fc fy=fy wc=uconvert(pcf, γ_concrete)
    end
    
    # =========================================================================
    # PHASE 2: IDENTIFY SUPPORTING COLUMNS
    # =========================================================================
    
    columns = find_supporting_columns(struc, slab_cell_indices)
    n_cols = length(columns)
    
    if n_cols == 0
        error("No supporting columns found for slab. Ensure tributary areas are computed.")
    end
    
    if verbose
        @debug "SUPPORTING COLUMNS" n_cols=n_cols
        for (i, col) in enumerate(columns)
            trib_m2 = sum(values(col.tributary_cell_areas); init=0.0)
            @debug "Column $i" vertex=col.vertex_idx position=col.position A_trib_m²=trib_m2
        end
    end
    
    # Check method applicability — auto-fallback to FEA if DDM/EFM not permitted
    try
        enforce_method_applicability(method, struc, slab, columns; verbose=verbose, ρ_concrete=γ_concrete)
    catch e
        if e isa DDMApplicabilityError || e isa EFMApplicabilityError
            old_name = method_name(method)
            viol_str = join(e.violations, "; ")
            @warn "$(old_name) not applicable — falling back to FEA" violations=viol_str
            method = FEA()
            enforce_method_applicability(method, struc, slab, columns; verbose=verbose, ρ_concrete=γ_concrete)
        else
            rethrow()
        end
    end
    
    # =========================================================================
    # PHASE 3: INITIAL ESTIMATES
    # =========================================================================
    
    has_edge = any(col.position != :interior for col in columns)
    if !isnothing(opts.min_h)
        h = opts.min_h  # User override — bypass ACI minimum
    elseif !isnothing(drop_panel)
        # Flat slab: reduced minimum thickness (ACI Table 8.3.1.1 Row 2)
        h = min_thickness_flat_slab(ln_max; discontinuous_edge=has_edge)
    else
        h = min_thickness_flat_plate(ln_max; discontinuous_edge=has_edge)
    end
    h_initial = h
    sw_estimate = slab_sw(h)
    
    # For flat slab, re-check drop panel depth after initial h
    # The drop panel depth must be ≥ h/4 (ACI 8.2.4(a))
    if !isnothing(drop_panel) && drop_panel.h_drop < h / 4
        # Auto-resize drop depth to satisfy ACI with current h
        dp_new_depth = auto_size_drop_depth(h)
        drop_panel = DropPanelGeometry(dp_new_depth, drop_panel.a_drop_1, drop_panel.a_drop_2)
        verbose && @debug "Drop panel depth adjusted to satisfy ACI 8.2.4(a)" h_drop=dp_new_depth h=h
    end
    
    bar_dia = bar_diameter(bar_size)
    c_span_min = estimate_column_size_from_span(ln_max)
    
    # Initialize column sizes
    for col in columns
        if isnothing(col.c1) || col.c1 <= 0u"inch"
            col.c1 = c_span_min
            col.c2 = c_span_min
        end
    end
    
    if verbose
        @debug "INITIAL ESTIMATES" h_min=h sw=sw_estimate c_span_min=c_span_min
    end
    
    # =========================================================================
    # PHASE 4: COMPUTE INITIAL AXIAL LOADS
    # =========================================================================
    
    Pu = compute_column_axial_loads(struc, columns, slab_cell_indices, sw_estimate)
    
    if verbose
        @debug "COLUMN AXIAL LOADS (Pu = 1.2D + 1.6L)"
        for (i, col) in enumerate(columns)
            @debug "Column $i ($(col.position))" Pu=Pu[i]*kip
        end
    end
    
    # =========================================================================
    # PHASE 4b: PRE-BUILD P-M CACHE (hoisted outside iteration loop)
    # =========================================================================
    
    # Reuse shared cache from size_slabs! when available (avoids duplicate P-M diagrams).
    if isnothing(_col_cache)
        _col_cat = isnothing(column_opts.custom_catalog) ?
            rc_column_catalog(column_opts.section_shape, column_opts.catalog) :
            column_opts.custom_catalog
        
        _col_checker = ACIColumnChecker(;
            include_slenderness = column_opts.include_slenderness,
            include_biaxial = column_opts.include_biaxial,
            fy_ksi = ustrip(ksi, column_opts.rebar_grade.Fy),
            Es_ksi = ustrip(ksi, column_opts.rebar_grade.E),
            max_depth = column_opts.max_depth,
        )
        
        _col_cache = create_cache(_col_checker, length(_col_cat))
        precompute_capacities!(_col_checker, _col_cache, _col_cat, column_opts.grade, column_opts.objective)
    end
    
    # =========================================================================
    # PHASE 5: ITERATIVE DESIGN LOOP
    # =========================================================================
    
    # Precompute local→global column index mapping via objectid (O(n) vs O(n²) findfirst)
    _col_id_to_idx = Dict{UInt64, Int}(objectid(struc.columns[i]) => i for i in eachindex(struc.columns))
    local_to_global = [_col_id_to_idx[objectid(col)] for col in columns]
    
    # Analysis cache: pull from struc._analysis_caches if slab_idx is known,
    # otherwise create a local cache.  This allows caches to persist across
    # design_building calls (parametric studies, method comparisons).
    analysis_cache = if slab_idx > 0 && hasproperty(struc, :_analysis_caches)
        slab_caches = get!(struc._analysis_caches, slab_idx, Dict{Symbol, Any}())
        if method isa EFM && method.solver == :asap
            get!(slab_caches, :efm, EFMModelCache())
        elseif method isa FEA
            get!(slab_caches, :fea, FEAModelCache())
        else
            nothing
        end
    else
        if method isa EFM && method.solver == :asap
            EFMModelCache()
        elseif method isa FEA
            FEAModelCache()
        else
            nothing
        end
    end
    
    moment_results = nothing
    column_result = nothing
    # Use local Vector for punching results (convert to Dict at output boundary)
    punching_local = Vector{Any}(undef, n_cols)
    
    # Preallocate column geometries (only column height matters; updated if it changes)
    geometries = [
        ConcreteMemberGeometry(col.base.L; Lu=col.base.L, k=1.0, braced=true)
        for col in columns
    ]
    
    # Preallocate Mu buffer (reused each iteration instead of comprehension)
    Mu = Vector{Float64}(undef, n_cols)
    
    for iter in 1:max_iterations
        if verbose
            @debug "═══════════════════════════════════════════════════════════════════"
            @debug "ITERATION $iter"
            @debug "═══════════════════════════════════════════════════════════════════"
        end
        
        # ─── STEP 5a: Moment Analysis ───
        # Compute edge beam βt if applicable (depends on current h and column sizes)
        _βt = 0.0
        if !isnothing(opts.edge_beam_βt)
            _βt = opts.edge_beam_βt
        elseif opts.has_edge_beam
            _c1_avg = sum(col.c1 for col in columns) / length(columns)
            _c2_avg = sum(col.c2 for col in columns) / length(columns)
            _βt = edge_beam_βt(h, _c1_avg, _c2_avg, slab.spans.secondary)
        end
        
        moment_results = run_moment_analysis(
            method, struc, slab, columns, h, fc, Ecs, γ_concrete;
            ν_concrete = material.concrete.ν,
            verbose=verbose,
            efm_cache = analysis_cache isa EFMModelCache ? analysis_cache : nothing,
            cache     = analysis_cache isa FEAModelCache ? analysis_cache : nothing,
            drop_panel = drop_panel,
            βt = _βt,
        )
        
        # Check pattern loading (first iteration only)
        if iter == 1
            check_pattern_loading_requirement(moment_results; verbose=verbose)
        end
        
        @inbounds for i in eachindex(Mu)
            Mu[i] = ustrip(kip*u"ft", moment_results.column_moments[i])
        end
        
        # ─── STEP 5b: Column P-M Design ───
        if verbose
            @debug "COLUMN P-M DESIGN"
        end
        
        column_result = size_columns(Pu, Mu, geometries, column_opts; cache=_col_cache)
        
        # ─── STEP 5c: Update Column Sizes ───
        columns_changed = false
        
        for (i, col) in enumerate(columns)
            section = column_result.sections[i]
            c1_pm = section.b
            c2_pm = section.h
            c1_old = col.c1
            c2_old = col.c2
            
            # Column size = max(span_minimum, P-M_design, current_size)
            col.c1 = max(c_span_min, c1_pm, c1_old)
            col.c2 = max(c_span_min, c2_pm, c2_old)
            
            # Create section with final dimensions
            # If dimensions match P-M design, use that section directly
            # Otherwise, re-design reinforcement for the larger dimensions using P-M interaction
            if col.c1 ≈ c1_pm && col.c2 ≈ c2_pm
                col.base.section = section
            else
                # Need larger section - properly design reinforcement for new dimensions
                # Use the full ReinforcedConcreteMaterial for P-M interaction analysis
                col.base.section = resize_column_with_reinforcement(
                    section, col.c1, col.c2,
                    Pu[i], Mu[i], material
                )
            end
            
            # Check for significant change
            Δc1 = abs(ustrip(u"inch", col.c1) - ustrip(u"inch", c1_old)) / 
                  max(ustrip(u"inch", c1_old), 1.0)
            
            if Δc1 > column_tol
                columns_changed = true
            end
            
            if verbose
                status = Δc1 > column_tol ? "CHANGED" : "unchanged"
                @debug "Column $i" pm_design=c1_pm final="$(col.c1)×$(col.c2)" ρg=round(col.base.section.ρg, digits=3) status=status
            end
        end
        
        if columns_changed
            verbose && @debug "⟳ Column sizes changed, re-running analysis..."
            continue
        end
        
        # ─── STEP 5d: Punching Shear Check ───
        if verbose
            @debug "PUNCHING SHEAR CHECK (ACI 22.6)"
        end
        
        d = effective_depth(h; cover=cover, bar_diameter=bar_dia)
        
        # Punching shear checks (each column is independent)
        # For flat slab: dual check at column face (total depth) and drop panel edge (slab depth)
        n_cols_ps = length(columns)
        if !isnothing(drop_panel)
            h_total = total_depth_at_drop(h, drop_panel)
            d_total = effective_depth(h_total; cover=cover, bar_diameter=bar_dia)
            
            for i in 1:n_cols_ps
                punching_local[i] = check_punching_flat_slab(
                    columns[i], moment_results.column_shears[i],
                    moment_results.unbalanced_moments[i],
                    h, d, h_total, d_total, fc, drop_panel;
                    qu=moment_results.qu,
                    verbose=false, col_idx=i, λ=λ, φ_shear=φ_shear
                )
            end
        elseif Threads.nthreads() > 1
            Threads.@threads for i in 1:n_cols_ps
                punching_local[i] = check_punching_for_column(
                    columns[i], moment_results.column_shears[i],
                    moment_results.unbalanced_moments[i], d, h, fc;
                    verbose=false, col_idx=i, λ=λ, φ_shear=φ_shear
                )
            end
        else
            for i in 1:n_cols_ps
                punching_local[i] = check_punching_for_column(
                    columns[i], moment_results.column_shears[i],
                    moment_results.unbalanced_moments[i], d, h, fc;
                    verbose=false, col_idx=i, λ=λ, φ_shear=φ_shear
                )
            end
        end

        # Classify failures (sequential for thread-safe push!)
        interior_fails = Int[]
        edge_corner_fails = Int[]
        for i in 1:n_cols_ps
            if !punching_local[i].ok
                if columns[i].position == :interior
                    push!(interior_fails, i)
                else
                    push!(edge_corner_fails, i)
                end
            end
            if verbose
                r = punching_local[i]
                status = r.ok ? "OK" : "FAIL"
                @debug "Punching Column $i ($(columns[i].position))" ratio=round(r.ratio, digits=3) status=status
            end
        end
        
        # Handle punching failures using shear stud strategy
        # Strategies:
        #   :never = grow columns only, error if maxed
        #   :if_needed = try columns first, use studs if columns maxed
        #   :always = use studs first, grow columns if studs insufficient
        all_fails = vcat(interior_fails, edge_corner_fails)
        
        if !isempty(all_fails)
            c_max = opts.max_column_size
            c_increment = 2.0u"inch"
            stud_strategy = opts.shear_studs
            stud_mat = opts.stud_material
            stud_diam = opts.stud_diameter
            fyt = stud_mat.Fy
            
            columns_grew = false
            studs_designed = false
            
            for i in all_fails
                col = columns[i]
                pr = punching_local[i]
                ratio = pr.ratio
                vu = pr.vu
                
                # Get punching parameters for stud design
                c1_in = ustrip(u"inch", col.c1)
                c2_in = ustrip(u"inch", col.c2)
                β = max(c1_in, c2_in) / max(min(c1_in, c2_in), 1.0)
                αs = punching_αs(col.position)
                b0 = pr.b0
                
                if stud_strategy == :always
                    studs = design_shear_studs(vu, fc, β, αs, b0, d, col.position, 
                                               fyt, stud_diam; λ=λ, φ=φ_shear)
                    stud_check = check_punching_with_studs(vu, studs; φ=φ_shear)
                    
                    if stud_check.ok
                        punching_local[i] = (
                            ok = true,
                            ratio = stud_check.ratio,
                            vu = vu,
                            φvc = studs.vcs + studs.vs,
                            b0 = b0,
                            Jc = pr.Jc,
                            studs = studs
                        )
                        studs_designed = true
                        if verbose
                            @info "Column $i ($(col.position)): Shear studs designed - $(studs.n_rails) rails × $(studs.n_studs_per_rail) studs"
                        end
                    else
                        c1_new = col.c1 + c_increment
                        if c1_new > c_max
                            h_new = round_up_thickness(h + h_increment, h_increment)
                            h = h_new
                            d = effective_depth(h; cover=cover, bar_diameter=bar_dia)
                            sw_estimate = slab_sw(h)
                            Pu = compute_column_axial_loads(struc, columns, slab_cell_indices, sw_estimate)
                            
                            @warn "Column $i: Studs and columns at max. Increasing h → $h"
                            columns_grew = true
                            break
                        else
                            col.c1 = c1_new
                            col.c2 = c1_new
                            columns_grew = true
                            if verbose
                                @warn "Column $i: Studs insufficient, growing column: $(col.c1 - c_increment) → $(c1_new)"
                            end
                        end
                    end
                    
                elseif stud_strategy == :if_needed
                    c1_original = col.c1
                    c1_new = col.c1 + c_increment
                    
                    if c1_new <= c_max
                        col.c1 = c1_new
                        col.c2 = c1_new
                        columns_grew = true
                        if verbose
                            @warn "Column $i punching FAILED (ratio=$(round(ratio, digits=2))). Growing: $(c1_original) → $(c1_new)"
                        end
                    else
                        col.c1 = c1_original
                        col.c2 = c1_original
                        
                        studs = design_shear_studs(vu, fc, β, αs, b0, d, col.position,
                                                   fyt, stud_diam; λ=λ, φ=φ_shear)
                        stud_check = check_punching_with_studs(vu, studs; φ=φ_shear)
                        
                        if stud_check.ok
                            punching_local[i] = (
                                ok = true,
                                ratio = stud_check.ratio,
                                vu = vu,
                                φvc = studs.vcs + studs.vs,
                                b0 = b0,
                                Jc = pr.Jc,
                                studs = studs
                            )
                            studs_designed = true
                            if verbose
                                @info "Column $i at max size - using shear studs: $(studs.n_rails) rails"
                            end
                        else
                            h_new = round_up_thickness(h + h_increment, h_increment)
                            h = h_new
                            d = effective_depth(h; cover=cover, bar_diameter=bar_dia)
                            sw_estimate = slab_sw(h)
                            Pu = compute_column_axial_loads(struc, columns, slab_cell_indices, sw_estimate)
                            
                            @warn "Column $i: Max size and studs insufficient. Increasing h → $h"
                            columns_grew = true
                            break
                        end
                    end
                    
                else  # :never (default)
                    c1_new = col.c1 + c_increment
                    
                    if c1_new > c_max
                        @error "Column $i at max size ($c_max), shear_studs=:never" position=col.position ratio=ratio
                        error("Punching cannot be resolved. Set shear_studs=:if_needed to allow studs.")
                    end
                    
                    col.c1 = c1_new
                    col.c2 = c1_new
                    columns_grew = true
                    
                    if verbose
                        @warn "Column $i punching FAILED (ratio=$(round(ratio, digits=2))). Growing: $(col.c1 - c_increment) → $(c1_new)"
                    end
                end
            end
            
            if columns_grew
                continue
            end
        end
        
        # ─── STEP 5e: Two-Way Deflection Check ───
        if verbose
            @debug "TWO-WAY DEFLECTION CHECK (ACI 24.2)"
        end
        
        # Estimate ρ' (compression reinforcement ratio at midspan) from negative
        # moment demand.  Top bars from column-strip negative regions extend into
        # midspan and act as compression steel for the positive moment region.
        # Using ρ' instead of 0.0 gives a more accurate (lower) long-term
        # deflection multiplier λ_Δ = ξ / (1 + 50ρ').
        _l2_defl = moment_results.l2
        _As_neg_est = required_reinforcement(
            0.75 * moment_results.M_neg_int, _l2_defl / 2, d, fc, fy
        )
        _As_neg_est = max(_As_neg_est, minimum_reinforcement(_l2_defl / 2, h, fy))
        # Only a portion of the top steel extends to midspan (~50% of column strip bars)
        ρ_prime_est = 0.5 * ustrip(u"inch^2", _As_neg_est) /
                      (ustrip(u"inch", _l2_defl / 2) * ustrip(u"inch", d))
        
        if verbose
            @debug "ρ' estimate for long-term deflection" As_neg_est=_As_neg_est ρ_prime=round(ρ_prime_est, digits=5)
        end
        
        deflection_result = if !isnothing(drop_panel)
            check_two_way_deflection_flat_slab(
                moment_results, h, d, fc, fy, Es, Ecs, slab.spans, γ_concrete, columns,
                drop_panel;
                verbose=verbose, limit_type=opts.deflection_limit,
                ρ_prime=ρ_prime_est
            )
        else
            check_two_way_deflection(
                moment_results, h, d, fc, fy, Es, Ecs, slab.spans, γ_concrete, columns;
                verbose=verbose, limit_type=opts.deflection_limit,
                ρ_prime=ρ_prime_est
            )
        end
        # deflection_result carries .ok, .Δ_check, .Δ_total, .Δ_limit, etc.
        
        if !deflection_result.ok
            h_new = round_up_thickness(h + h_increment, h_increment)
            h = h_new
            sw_estimate = slab_sw(h)
            Pu = compute_column_axial_loads(struc, columns, slab_cell_indices, sw_estimate)
            
            verbose && @warn "Deflection FAILED. Increasing h → $h"
            continue
        end
        
        # ─── STEP 5f: One-Way Shear Check ───
        if verbose
            @debug "ONE-WAY SHEAR CHECK (ACI 22.5)"
        end
        
        shear_result = check_one_way_shear(moment_results, d, fc; verbose=verbose, λ=λ, φ_shear=φ_shear)
        
        if !shear_result.ok
            h_new = round_up_thickness(h + h_increment, h_increment)
            h = h_new
            sw_estimate = slab_sw(h)
            Pu = compute_column_axial_loads(struc, columns, slab_cell_indices, sw_estimate)
            
            verbose && @warn "One-way shear FAILED. Increasing h → $h"
            continue
        end
        
        # =========================================================================
        # PHASE 6: FINAL DESIGN
        # =========================================================================
        
        # ─── 6a: Face-of-Support Moment Reduction (ACI 8.11.6.1) ───
        # For EFM, centerline moments are conservative because the column has
        # finite width.  Reduce negative moments to face of support.
        # DDM coefficients already account for this implicitly, so skip for DDM.
        if method isa EFM
            # Per-column-type face-of-support reduction (ACI 8.11.6.1)
            # Use minimum c1 within each column class for the most conservative
            # (smallest) moment reduction.
            ext_cols = filter(c -> c.position != :interior, columns)
            int_cols = filter(c -> c.position == :interior, columns)
            
            c1_ext = isempty(ext_cols) ? moment_results.c_avg : minimum(c.c1 for c in ext_cols)
            c1_int = isempty(int_cols) ? moment_results.c_avg : minimum(c.c1 for c in int_cols)
            
            Vu_face = moment_results.Vu_max
            
            # Convert back to the same unit as M0 to keep the parametric type uniform
            M_unit = unit(moment_results.M0)
            M_neg_ext_reduced = uconvert(M_unit, face_of_support_moment(
                moment_results.M_neg_ext, Vu_face, c1_ext, moment_results.l1
            ))
            M_neg_int_reduced = uconvert(M_unit, face_of_support_moment(
                moment_results.M_neg_int, Vu_face, c1_int, moment_results.l1
            ))
            
            if verbose
                @debug "FACE-OF-SUPPORT MOMENT REDUCTION (ACI 8.11.6.1)" c1_ext=c1_ext c1_int=c1_int M_neg_ext_cl=moment_results.M_neg_ext M_neg_ext_face=M_neg_ext_reduced M_neg_int_cl=moment_results.M_neg_int M_neg_int_face=M_neg_int_reduced
            end
            
            # Update the moment results for design (rebuild with reduced moments)
            moment_results = MomentAnalysisResult(
                moment_results.M0,
                M_neg_ext_reduced, M_neg_int_reduced,
                moment_results.M_pos,
                moment_results.qu, moment_results.qD, moment_results.qL,
                moment_results.l1, moment_results.l2, moment_results.ln, moment_results.c_avg,
                moment_results.column_moments,
                moment_results.column_shears,
                moment_results.unbalanced_moments,
                moment_results.Vu_max
            )
        end
        
        # ─── 6b: Strip Reinforcement Design ───
        if verbose
            @debug "REINFORCEMENT DESIGN"
        end
        
        rebar_design = design_strip_reinforcement(
            moment_results, columns, h, d, fc, fy, cover;
            verbose=verbose
        )
        
        # ─── 6c: Moment Transfer Reinforcement (ACI 8.4.2.3) ───
        # Check that enough reinforcement falls within bb = c₂ + 3h at each
        # column to resist γf × Mub.  If not, additional bars are needed.
        transfer_results = Union{Nothing, NamedTuple}[nothing for _ in 1:n_cols]
        for (i, col) in enumerate(columns)
            Mub_i = moment_results.unbalanced_moments[i]
            if abs(ustrip(kip * u"ft", Mub_i)) < 1e-6
                continue  # transfer_results[i] already nothing
            end
            
            c2_i = col.c2
            bb = c2_i + 3 * h  # effective slab width for moment transfer
            
            # Critical section dimensions for γf
            b1 = col.c1 + d
            b2 = col.c2 + d
            γf_val = gamma_f(b1, b2)
            
            # Required transfer reinforcement within bb
            As_transfer = transfer_reinforcement(abs(Mub_i), γf_val, bb, d, fc, fy)
            
            # Get provided column strip steel at this column
            cs_neg_idx = col.position == :interior ? 3 : 1  # int_neg or ext_neg
            As_provided_cs = rebar_design.column_strip_reinf[cs_neg_idx].As_provided
            selected = select_bars(As_provided_cs, rebar_design.column_strip_width)
            Ab = bar_area(selected.bar_size)  # area per bar
            
            transfer = additional_transfer_bars(
                As_transfer, As_provided_cs, bb,
                rebar_design.column_strip_width, Ab
            )
            
            transfer_results[i] = transfer
            
            if verbose && transfer.n_bars_additional > 0
                @debug "MOMENT TRANSFER (ACI 8.4.2.3) — Column $i ($(col.position))" Mub=Mub_i γf=round(γf_val, digits=3) bb=bb As_transfer=As_transfer As_within_bb=transfer.As_within_bb n_additional=transfer.n_bars_additional
            end
        end
        
        # ─── 6d: Structural Integrity Reinforcement (ACI 8.7.4.2) ───
        cell = struc.cells[first(slab.cell_indices)]
        integrity = integrity_reinforcement(
            cell.area, cell.sdl + sw_estimate, cell.live_load, fy
        )
        
        # Enforce: check that positive (bottom) steel in column strip is sufficient.
        # The bottom bars must pass through the column core.
        cs_pos_reinf = rebar_design.column_strip_reinf[2]  # :pos location
        integrity_check = check_integrity_reinforcement(
            cs_pos_reinf.As_provided, integrity.As_integrity
        )
        
        if verbose
            @debug "INTEGRITY REINFORCEMENT (ACI 8.7.4.2)" As_integrity=integrity.As_integrity As_bottom=cs_pos_reinf.As_provided ok=integrity_check.ok utilization=round(integrity_check.utilization, digits=2)
        end
        
        if !integrity_check.ok
            # Bump bottom steel so integrity requirement is satisfied (ACI 8.7.4.2)
            cs_width = rebar_design.column_strip_width
            bumped = select_bars(integrity.As_integrity, cs_width)
            rebar_design.column_strip_reinf[2] = StripReinforcement(
                :pos,
                cs_pos_reinf.Mu,
                cs_pos_reinf.As_reqd,
                cs_pos_reinf.As_min,
                uconvert(u"m^2", bumped.As_provided),
                bumped.bar_size,
                uconvert(u"m", bumped.spacing),
                bumped.n_bars
            )
            if verbose
                @debug "Integrity reinforcement governs — bumped midspan bottom steel" As_before=cs_pos_reinf.As_provided As_after=bumped.As_provided As_integrity=integrity.As_integrity bar_size=bumped.bar_size n_bars=bumped.n_bars
            end
        end
        
        # ─── Update Cell Self-Weights ───
        sw_final = slab_sw(h)
        for cell_idx in slab.cell_indices
            struc.cells[cell_idx].self_weight = sw_final
        end
        
        # ─── Update Asap Model ───
        update_asap_column_sections!(struc, columns, column_opts.grade)
        
        # ─── Build Results ───
        if verbose
            @debug "═══════════════════════════════════════════════════════════════════"
            @debug "DESIGN CONVERGED ✓"
            @debug "═══════════════════════════════════════════════════════════════════"
            @debug "Final slab" h=h sw=sw_final method=method_name(method)
            @debug "Final columns" sizes=["$(c.c1)×$(c.c2)" for c in columns]
            @debug "Iterations" n=iter
        end
        
        # Convert local punching Vector → Dict keyed by global column index
        punching_results = Dict{Int, Any}(
            local_to_global[i] => punching_local[i] for i in 1:n_cols
        )
        
        slab_result = build_slab_result(
            h, sw_final, moment_results, rebar_design,
            deflection_result, punching_results;
            γ_concrete = γ_concrete * GRAVITY
        )
        
        column_results = build_column_results(
            struc, columns, column_result,
            Pu, moment_results.column_moments, punching_results
        )
        
        return (
            slab_result=slab_result,
            column_results=column_results,
            drop_panel=drop_panel,
            integrity=integrity,
            integrity_check=integrity_check,
            transfer_results=transfer_results,
            ρ_prime=ρ_prime_est,
        )
    end
    
    error("Design did not converge in $max_iterations iterations")
end
