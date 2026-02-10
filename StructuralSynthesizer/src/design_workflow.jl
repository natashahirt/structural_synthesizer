# =============================================================================
# Design Workflow — Pipeline-Based Building Design
# =============================================================================
#
# The design pipeline is composable: `build_pipeline` returns a Vector of
# closures (stages) that are executed in sequence, with `sync_asap!` between
# each stage to keep the analysis model consistent.
#
#   for stage! in build_pipeline(params)
#       stage!(struc)
#       sync_asap!(struc; params)
#   end
#
# Adding a new stage (e.g., lateral design, connection design) requires only
# a new push! in build_pipeline — design_building itself never changes.
#
# Example:
#   skel = gen_medium_office(54u"ft", 42u"ft", 13u"ft", 3, 3, 3)
#   struc = BuildingStructure(skel)
#   
#   design1 = design_building(struc, DesignParameters(
#       name = "Option A - 4ksi concrete",
#       floor_options = FloorOptions(flat_plate=FlatPlateOptions(material=RC_4000_60)),
#       foundation_options = FoundationParameters(soil=medium_sand),
#   ))
#   
#   design2 = design_building(struc, DesignParameters(
#       name = "Option B - 6ksi concrete",
#       floor_options = FloorOptions(flat_plate=FlatPlateOptions(material=RC_6000_60)),
#   ))
#   
#   compare_designs(design1, design2)
# =============================================================================

using Dates

# =============================================================================
# Pipeline Construction
# =============================================================================

"""
    build_pipeline(params::DesignParameters) -> Vector{Function}

Compose the design pipeline from `DesignParameters`.

Returns a vector of `struc -> ()` closures. Each stage mutates the structure
(sizing members, updating loads). Between stages, `design_building` calls
`sync_asap!` to keep the analysis model consistent.

# Stages (by floor type)

**Flat plate** (:flat_plate)
1. Size slabs (DDM/EFM/FEA — includes column P-M design)
2. Reconcile columns (take max of slab-designed and Asap-found)
3. Size foundations (if requested)

**One-way slab / two-way slab** (:one_way, :two_way)
1. Size slabs
2. Size beams + columns (iterative convergence loop)
3. Size foundations (if requested)

**Vault** (:vault)
1. Size slabs (vault geometry)
2. Size beams + columns (iterative — beam must resist thrust)
3. Size foundations (if requested)
"""
function build_pipeline(params::DesignParameters)
    stages = Function[]
    
    opts = something(params.floor_options, StructuralSizer.FloorOptions())
    floor_type = _infer_floor_type(opts)
    
    # ─── Stage 1: Slab sizing (always) ───
    push!(stages, struc -> begin
        StructuralSizer.size_slabs!(struc; options=opts, verbose=false,
                                    max_iterations=params.max_iterations)
        update_slab_volumes!(struc; options=opts)
    end)
    
    # ─── Stage 2: Beam + column sizing ───
    if floor_type == :flat_plate
        # Flat plate: columns already sized in slab loop.
        # Reconcile with Asap model forces (multi-story load accumulation).
        push!(stages, struc -> _reconcile_columns!(struc, params))
    else
        # Beam-based systems: iterative beam/column sizing
        push!(stages, struc -> _size_beams_columns!(struc, params))
    end
    
    # ─── Stage 3: Foundations (if requested) ───
    if !isnothing(params.foundation_options)
        push!(stages, struc -> _size_foundations!(struc, params.foundation_options))
    end
    
    return stages
end

# =============================================================================
# Main Entry Point
# =============================================================================

"""
    design_building(struc::BuildingStructure, params::DesignParameters) -> BuildingDesign

Run the complete design pipeline and return a `BuildingDesign` with all results.

Uses `snapshot!` / `restore!` to leave `struc` unchanged after design,
enabling multiple designs from the same structure:

```julia
d1 = design_building(struc, params_a)   # struc is restored after
d2 = design_building(struc, params_b)   # struc is restored after
compare_designs(d1, d2)
```

# Pipeline
1. Initialize structure (cells, slabs, tributaries, members)
2. Estimate initial column sizes
3. Build Asap model
4. **Snapshot** pristine state
5. Run stages from `build_pipeline(params)` with `sync_asap!` between each
6. Capture results into `BuildingDesign`
7. **Restore** to pristine state
"""
function design_building(struc::BuildingStructure, params::DesignParameters)
    t_start = time()
    
    # ─── Initialize ───
    opts = something(params.floor_options, StructuralSizer.FloorOptions())
    floor_type = _infer_floor_type(opts)
    
    initialize!(struc; loads=params.loads, floor_type=floor_type, floor_kwargs=(options=opts,))
    
    fc = _get_design_fc(params)
    estimate_column_sizes!(struc; fc=fc)
    
    to_asap!(struc; params=params)
    
    # ─── Snapshot pristine state ───
    snapshot!(struc)
    
    # ─── Run pipeline ───
    for stage! in build_pipeline(params)
        stage!(struc)
        sync_asap!(struc; params=params)
    end
    
    # ─── Capture results ───
    design = BuildingDesign(struc, params)
    _populate_slab_results!(design, struc)
    _populate_column_results!(design, struc)
    _populate_beam_results!(design, struc)
    _populate_foundation_results!(design, struc)
    _compute_design_summary!(design, struc, params)
    
    # ─── Restore ───
    restore!(struc)
    sync_asap!(struc; params=params)
    
    design.compute_time_s = time() - t_start
    return design
end

"""
    design_building(struc::BuildingStructure; kwargs...) -> BuildingDesign

Convenience method that creates DesignParameters from keyword arguments.
"""
function design_building(struc::BuildingStructure; kwargs...)
    params = DesignParameters(; kwargs...)
    return design_building(struc, params)
end

# =============================================================================
# Pipeline Stage Implementations
# =============================================================================

"""
Reconcile column sizes after flat-plate slab sizing.

The slab loop designs columns from tributary Pu (single-floor tributary).
For multi-story buildings, Asap model forces may be larger due to load
accumulation from upper floors. This stage takes the maximum of the
slab-designed c1/c2 and what Asap forces require.
"""
function _reconcile_columns!(struc::BuildingStructure, params::DesignParameters)
    fc = _get_design_fc(params)
    fc_Pa = ustrip(u"Pa", uconvert(u"Pa", fc))
    grew = 0
    
    for col in struc.columns
        isnothing(col.c1) && continue
        
        # Extract max axial from Asap model
        Pu_N = _column_asap_Pu(struc, col)
        Pu_N ≤ 0 && continue
        
        # Required area: ϕ Pn = 0.65 × 0.80 × f'c × Ag  (ACI 318 pure compression)
        Ag_required_m2 = Pu_N / (0.65 * 0.80 * fc_Pa)
        c_required = sqrt(Ag_required_m2) * u"m"
        
        if c_required > col.c1
            col.c1 = c_required
            col.c2 = c_required
            grew += 1
        end
    end
    
    grew > 0 && @info "Column reconciliation: $grew columns grew from Asap model forces"
    return struc
end

"""Extract max axial force (N) for a column from the Asap model."""
function _column_asap_Pu(struc::BuildingStructure, col)
    Pu = 0.0
    for seg_idx in segment_indices(col)
        seg = struc.segments[seg_idx]
        edge_idx = seg.edge_idx
        (edge_idx < 1 || edge_idx > length(struc.asap_model.elements)) && continue
        el = struc.asap_model.elements[edge_idx]
        isempty(el.forces) && continue
        n_dof = length(el.forces)
        Pu_start = abs(el.forces[1])
        Pu_end = n_dof >= 7 ? abs(el.forces[7]) : Pu_start
        Pu = max(Pu, Pu_start, Pu_end)
    end
    return Pu
end

"""
Iterative beam + column sizing for beam-based floor systems.

Beams and columns are coupled: beam self-weight affects column demands, and
column stiffness affects beam moments. This loop converges their sizes.
"""
function _size_beams_columns!(struc::BuildingStructure, params::DesignParameters)
    beam_opts   = something(params.beams,   StructuralSizer.SteelBeamOptions())
    column_opts = something(params.columns, StructuralSizer.SteelColumnOptions())
    tol = 0.05
    max_iter = params.max_iterations
    
    prev_demands = nothing
    
    for iter in 1:max_iter
        size_beams!(struc, beam_opts; reanalyze=false)
        
        if struc.asap_model.processed
            Asap._reprocess_stiffness_and_loads!(struc.asap_model)
        else
            Asap.process!(struc.asap_model)
        end
        Asap.solve!(struc.asap_model)
        
        size_columns!(struc, column_opts; reanalyze=false)
        
        if struc.asap_model.processed
            Asap._reprocess_stiffness_and_loads!(struc.asap_model)
        else
            Asap.process!(struc.asap_model)
        end
        Asap.solve!(struc.asap_model)
        
        current = _extract_column_demands(struc)
        if !isnothing(prev_demands) && _max_demand_change(prev_demands, current) < tol
            break
        end
        prev_demands = current
    end
    
    return struc
end

# =============================================================================
# Internal Helpers
# =============================================================================

"""Infer floor type from floor options."""
_infer_floor_type(opts::StructuralSizer.FloorOptions) = opts.floor_type

"""Get concrete f'c from design parameters (for initial column estimates)."""
function _get_design_fc(params::DesignParameters)
    if !isnothing(params.floor_options) && !isnothing(params.floor_options.flat_plate)
        mat = params.floor_options.flat_plate.material
        if !isnothing(mat)
            return mat.concrete.fc′
        end
    end
    if !isnothing(params.concrete)
        return params.concrete.fc′
    end
    return 4000u"psi"
end

"""Size foundations using FoundationParameters."""
function _size_foundations!(struc::BuildingStructure, fp::FoundationParameters)
    initialize_supports!(struc)
    initialize_foundations!(struc)
    group_foundations_by_reaction!(struc; tolerance=fp.group_tolerance)
    size_foundations_grouped!(struc;
        soil = fp.soil,
        concrete = fp.concrete,
        rebar = fp.rebar,
        pier_width = fp.pier_width,
        min_depth = fp.min_depth,
    )
end

"""Extract column axial demands for convergence checking."""
function _extract_column_demands(struc::BuildingStructure)
    n = length(struc.columns)
    demands = Vector{Float64}(undef, n)
    for (i, col) in enumerate(struc.columns)
        demands[i] = _column_asap_Pu(struc, col)
    end
    return demands
end

"""Compute maximum relative change in column demands."""
function _max_demand_change(prev::Vector{Float64}, curr::Vector{Float64})
    length(prev) == length(curr) || return 1.0
    max_change = 0.0
    for (p, c) in zip(prev, curr)
        if p > 0
            change = abs(c - p) / p
            max_change = max(max_change, change)
        elseif c > 0
            max_change = 1.0
        end
    end
    return max_change
end

# =============================================================================
# Result Population Functions
# =============================================================================

"""Populate slab design results from struc.slabs (all values normalized to SI)."""
function _populate_slab_results!(design::BuildingDesign, struc::BuildingStructure)
    for (slab_idx, slab) in enumerate(struc.slabs)
        isnothing(slab.result) && continue
        
        result = SlabDesignResult(
            thickness = uconvert(u"m", StructuralSizer.total_depth(slab.result)),
            self_weight = uconvert(u"kPa", StructuralSizer.self_weight(slab.result))
        )
        
        if hasproperty(slab.result, :M0)
            result.M0 = uconvert(u"kN*m", slab.result.M0)
        end
        
        if hasproperty(slab.result, :deflection_check)
            dc = slab.result.deflection_check
            result.deflection_ok = dc.ok
            result.deflection_ratio = dc.ratio
        end
        
        design.slabs[slab_idx] = result
    end
end

"""Populate column design results from struc.columns."""
function _populate_column_results!(design::BuildingDesign, struc::BuildingStructure)
    for (col_idx, col) in enumerate(struc.columns)
        result = ColumnDesignResult()
        
        if !isnothing(col.c1) && !isnothing(col.c2)
            c1_in = round(Int, ustrip(u"inch", col.c1))
            c2_in = round(Int, ustrip(u"inch", col.c2))
            result.section_size = "$(c1_in)×$(c2_in)"
        end
        
        trib_area = column_tributary_area(struc, col)
        if !isnothing(trib_area)
            result.punching = PunchingDesignResult(
                Vu = 0.0u"kN",
                φVc = 0.0u"kN",
                ratio = 0.0,
                ok = true,
                critical_perimeter = 0.0u"m",
                tributary_area = uconvert(u"m^2", trib_area)
            )
        end
        
        design.columns[col_idx] = result
    end
end

"""Populate beam design results from struc.beams."""
function _populate_beam_results!(design::BuildingDesign, struc::BuildingStructure)
    for (beam_idx, beam) in enumerate(struc.beams)
        result = BeamDesignResult()
        if !isnothing(beam.base.section)
            result.section_size = string(beam.base.section)
        end
        design.beams[beam_idx] = result
    end
end

"""Populate foundation design results from struc.foundations (all values normalized to SI)."""
function _populate_foundation_results!(design::BuildingDesign, struc::BuildingStructure)
    for (fdn_idx, fdn) in enumerate(struc.foundations)
        isnothing(fdn.result) && continue
        
        total_reaction = 0.0u"kN"
        for sup_idx in fdn.support_indices
            sup = struc.supports[sup_idx]
            total_reaction += uconvert(u"kN", sup.forces[3])
        end
        
        gid = isnothing(fdn.group_id) ? 0 : Int(fdn.group_id % typemax(Int))
        
        result = FoundationDesignResult(
            length = uconvert(u"m", StructuralSizer.footing_length(fdn.result)),
            width = uconvert(u"m", StructuralSizer.footing_width(fdn.result)),
            depth = uconvert(u"m", fdn.result.D),
            reaction = total_reaction,
            bearing_ratio = StructuralSizer.utilization(fdn.result),
            ok = StructuralSizer.utilization(fdn.result) <= 1.0,
            group_id = gid,
        )
        
        design.foundations[fdn_idx] = result
    end
end

"""Compute summary metrics."""
function _compute_design_summary!(design::BuildingDesign, struc::BuildingStructure, params::DesignParameters)
    summary = design.summary
    
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
    
    for (idx, fdn_result) in design.foundations
        if fdn_result.bearing_ratio > max_ratio
            max_ratio = fdn_result.bearing_ratio
            critical_elem = "Foundation $idx (bearing)"
        end
        if !fdn_result.ok
            all_ok = false
        end
    end
    
    summary.critical_ratio = max_ratio
    summary.critical_element = critical_elem
    summary.all_checks_pass = all_ok
    
    total_conc_vol = 0.0u"m^3"
    summary.concrete_volume = total_conc_vol
end

# =============================================================================
# Design Comparison Utilities
# =============================================================================

"""
    compare_designs(designs::Vector{BuildingDesign})

Create a comparison table of multiple designs.
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
