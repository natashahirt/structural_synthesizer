# ==============================================================================
# Flat Plate Analysis Method Comparison Study
# ==============================================================================
#
# Compares all five flat plate sizing methods on square & rectangular bays:
#   1. MDDM        — Modified DDM (simplified 0.65/0.35 coefficients)
#   2. DDM          — Full ACI 318 Table 8.10 coefficients
#   3. EFM (HC)     — Equivalent Frame, Hardy Cross moment distribution
#   4. EFM (ASAP)   — Equivalent Frame, ASAP FEM stiffness solver
#   5. FEA          — 2D shell model with adaptive mesh
#
# Uses snapshot/restore so each geometry is built only once, then recycled
# across methods and live-load variations.
#
# FEA mesh adapts to span: target_edge ≈ min(Lx,Ly)/25, clamped to
# [0.25 m, 0.75 m], keeping ~25 elements per span direction regardless of
# bay size.  Larger bays also get scaled initial/max column sizes.
#
# Usage (from Julia REPL at project root):
#
#   include("src/flat_plate_methods/flat_plate_method_comparison.jl")
#
#   df = sweep()                          # full factorial
#   df = sweep(spans=[20, 24])            # custom span subset
#   df = sweep(live_loads=[40, 80])       # vary live load only
#
#   compare()                             # quick table for default 20 ft bay
#   compare(span=24.0, ll=80.0)           # custom quick table
#
#   save_results(df, "my_study")          # manual save
#
# ==============================================================================

include(joinpath(@__DIR__, "..", "init.jl"))

using Printf

const SR = StructuralSizer
const SS = StructuralSynthesizer

@isdefined(FP_RESULTS_DIR) || (const FP_RESULTS_DIR = joinpath(@__DIR__, "results"))

# ==============================================================================
# Method definitions
# ==============================================================================

# DDM / EFM methods are span-independent
const _BASE_METHODS = [
    (key=:mddm,   name="MDDM",       obj=SR.DDM(:simplified)),
    (key=:ddm,    name="DDM (Full)",  obj=SR.DDM(:full)),
    (key=:efm_hc, name="EFM (HC)",    obj=SR.EFM(:moment_distribution)),
    (key=:efm,    name="EFM (ASAP)",  obj=SR.EFM(:asap)),
]

# FEA() now auto-adapts mesh to span (~25 elements/span, clamped [0.15, 0.75] m)
const _FEA_METHOD = (key=:fea, name="FEA", obj=SR.FEA())

"""Return the full five-method list."""
function _method_configs(lx_ft::Float64, ly_ft::Float64)
    return vcat(_BASE_METHODS, [_FEA_METHOD])
end

# ==============================================================================
# Build structure helpers
# ==============================================================================

"""
    _adaptive_story_ht(span_ft)

Scale story height with span.  Short spans use a standard 12 ft story;
longer spans get taller stories, which is realistic (long-span flat plates
appear in lobbies, atriums, parking garages) and gives columns more
capacity via reduced slenderness effects.

| span (ft) | story_ht (ft) |
|-----------|---------------|
|    16     |      12       |
|    28     |      12       |
|    36     |      14       |
|    44     |      16       |
|    52     |      18       |
"""
_adaptive_story_ht(span_ft::Float64) = max(12.0, round(span_ft / 3.0))

"""Flat plate floor options with configurable max column size and stud strategy."""
function _flat_plate_opts(; max_col_in::Float64 = 36.0, shear_studs::Symbol = :if_needed)
    fp = SR.FlatPlateOptions(
        material        = SR.RC_4000_60,
        shear_studs     = shear_studs,
        max_column_size = max_col_in * u"inch",
    )
    return SR.FloorOptions(flat_plate = fp, tributary_axis = nothing)
end

"""Flat slab (with drop panels) floor options — wraps flat plate options."""
function _flat_slab_opts(; max_col_in::Float64 = 36.0, shear_studs::Symbol = :if_needed)
    fp = SR.FlatPlateOptions(
        material        = SR.RC_4000_60,
        shear_studs     = shear_studs,
        max_column_size = max_col_in * u"inch",
    )
    fs = SR.FlatSlabOptions(base = fp)
    return SR.FloorOptions(flat_plate = fp, flat_slab = fs, tributary_axis = nothing)
end

"""Return floor options for the given floor type symbol."""
function _floor_opts(ft::Symbol; max_col_in::Float64 = 36.0, shear_studs::Symbol = :if_needed)
    ft === :flat_slab ? _flat_slab_opts(; max_col_in, shear_studs) :
                        _flat_plate_opts(; max_col_in, shear_studs)
end

"""
    _build_and_snapshot!(lx_ft, ly_ft, story_ht_ft, n_bays; sdl_psf, live_psf, col_in)

Build a rectangular-bay flat plate structure, take a snapshot, and return
`(struc, opts)`.  The snapshot captures the pristine state so subsequent runs
can `restore!` cheaply instead of rebuilding from scratch.

Initial column size and max column size scale with the longer span so that
large-bay cases have a fighting chance at passing punching shear:

| span_max (ft) | col_in (in) | max_col (in) |
|---------------|-------------|--------------|
|       16      |      16     |      36      |
|       28      |      17     |      36      |
|       40      |      24     |      36      |
|       52      |      31     |      47      |
"""
function _build_and_snapshot!(lx_ft::Float64, ly_ft::Float64,
                              story_ht_ft::Float64, n_bays::Int;
                              sdl_psf::Float64  = 20.0,
                              live_psf::Float64 = 50.0,
                              col_in::Float64   = 0.0,
                              floor_type::Symbol = :flat_plate,
                              shear_studs::Symbol = :if_needed)
    span_max = max(lx_ft, ly_ft)

    # Auto-scale initial column size and max with span
    col_in  = col_in > 0.0 ? col_in : clamp(round(span_max * 0.6), 16.0, 48.0)
    max_col = clamp(round(span_max * 0.9), 36.0, 60.0)

    total_x = lx_ft * n_bays * u"ft"
    total_y = ly_ft * n_bays * u"ft"
    ht      = story_ht_ft * u"ft"

    skel  = gen_medium_office(total_x, total_y, ht, n_bays, n_bays, 1)
    struc = BuildingStructure(skel)
    opts  = _floor_opts(floor_type; max_col_in = max_col, shear_studs)

    initialize!(struc; floor_type = floor_type, floor_kwargs = (options = opts,))

    for cell in struc.cells
        cell.sdl       = uconvert(u"kN/m^2", sdl_psf * psf)
        cell.live_load = uconvert(u"kN/m^2", live_psf * psf)
    end
    for col in struc.columns
        col.c1 = col_in * u"inch"
        col.c2 = col_in * u"inch"
    end

    to_asap!(struc)
    snapshot!(struc)

    return struc, opts
end

"""
    _set_live_load!(struc, live_psf)

Overwrite every cell's live load and re-sync the Asap model pressures.
"""
function _set_live_load!(struc, live_psf::Float64)
    ll = uconvert(u"kN/m^2", live_psf * psf)
    for cell in struc.cells
        cell.live_load = ll
    end
    sync_asap!(struc)
end

# ==============================================================================
# Run one method on a pre-built structure
# ==============================================================================

"""
Run `size_flat_plate!` on an already-built (and snapshotted) structure.
Restores the snapshot first, applies the requested live load, then sizes.
Returns a result row NamedTuple, or `nothing` on failure.
"""
function _run_on_prebuilt(struc, opts, method_cfg;
                          lx_ft::Float64, ly_ft::Float64,
                          live_psf::Float64,
                          floor_type::Symbol = :flat_plate)
    restore!(struc)
    _set_live_load!(struc, live_psf)

    slab     = struc.slabs[1]
    # High-capacity columns with 6 ksi concrete for long-span feasibility
    col_opts = SR.ConcreteColumnOptions(
        grade   = SR.NWC_6000,
        catalog = :high_capacity,
    )

    fp_opts = opts.flat_plate

    # ── Pre-check DDM/EFM applicability ──────────────────────────────
    # If the requested method is DDM or EFM but the geometry makes it
    # inapplicable, return nothing instead of letting the pipeline
    # silently fall back to FEA.  This keeps the heatmap honest: each
    # cell shows the result *for that method* or nothing.
    slab_cell_indices = Set(slab.cell_indices)
    columns = SR.find_supporting_columns(struc, slab_cell_indices)
    method  = method_cfg.obj
    if method isa SR.DDM
        chk = SR.check_ddm_applicability(struc, slab, columns; throw_on_failure=false)
        if !chk.ok
            return nothing   # not applicable → white cell
        end
    elseif method isa SR.EFM
        chk = SR.check_efm_applicability(struc, slab, columns; throw_on_failure=false)
        if !chk.ok
            return nothing
        end
    end

    t0 = time()
    full_result = try
        if floor_type === :flat_slab
            # Build drop panel geometry, then use the shared pipeline with it
            dp = SR._build_drop_panel_geometry(opts.flat_slab, struc, slab)
            SR.size_flat_plate!(struc, slab, col_opts;
                                method         = method_cfg.obj,
                                opts           = fp_opts,
                                max_iterations = 50,
                                verbose        = false,
                                slab_idx       = 1,
                                drop_panel     = dp)
        else
            SR.size_flat_plate!(struc, slab, col_opts;
                                method         = method_cfg.obj,
                                opts           = fp_opts,
                                max_iterations = 50,
                                verbose        = false)
        end
    catch e
        @warn "$(method_cfg.name) failed" lx=lx_ft ly=ly_ft live=live_psf exception=e
        return nothing
    end
    elapsed = time() - t0

    r = full_result.slab_result

    cols_in = [ustrip(u"inch", c.c1) for c in struc.columns]
    As_cs   = sum(sr.As_provided for sr in r.column_strip_reinf; init = 0.0u"inch^2")
    As_ms   = sum(sr.As_provided for sr in r.middle_strip_reinf; init = 0.0u"inch^2")

    # Story height from the z-coordinates
    zs = struc.skeleton.stories_z
    ht_ft = length(zs) >= 2 ? ustrip(u"ft", zs[2] - zs[1]) : NaN

    # Drop panel info (flat slab only)
    dp = hasproperty(full_result, :drop_panel) ? full_result.drop_panel : nothing
    h_drop_in  = !isnothing(dp) ? ustrip(u"inch", dp.h_drop)    : 0.0
    a_drop1_ft = !isnothing(dp) ? ustrip(u"ft",   dp.a_drop_1)  : 0.0
    a_drop2_ft = !isnothing(dp) ? ustrip(u"ft",   dp.a_drop_2)  : 0.0

    # ── Additional data worth recording ──────────────────────────────

    # Self-weight (how much of qu is self-weight?)
    sw_psf = ustrip(psf, r.self_weight)

    # Concrete volume intensity (volume per plan area — key for cost / carbon)
    vol_per_area_in = ustrip(u"inch", r.volume_per_area)

    # Actual deflection values (not just the ratio)
    defl_in  = ustrip(u"inch", r.deflection_check.Δ_check)
    defl_lim_in = ustrip(u"inch", r.deflection_check.Δ_limit)

    # Punching: detect whether studs were used on any column
    # (punching_check.details is a Dict{Int, NamedTuple}; stud key only present when designed)
    punch_details = r.punching_check.details
    _has_stud(v) = hasproperty(v, :studs) && !isnothing(v.studs)
    has_studs = any(_has_stud(v) for v in values(punch_details))
    n_stud_cols = count(_has_stud, values(punch_details))

    # Worst-case stud layout (total rails × studs per rail at worst column)
    stud_rails_max = 0
    stud_per_rail_max = 0
    if has_studs
        for v in values(punch_details)
            _has_stud(v) || continue
            s = v.studs
            if s.n_rails > stud_rails_max
                stud_rails_max    = s.n_rails
                stud_per_rail_max = s.n_studs_per_rail
            end
        end
    end

    # Worst-column punching stress demand (psi)
    vu_max_psi = maximum(ustrip(u"psi", v.vu) for v in values(punch_details); init=0.0)

    # Column reinforcement ratio (ρg) — how hard the columns are working
    col_res = full_result.column_results
    ρg_vals = [v.ρg for v in values(col_res)]
    col_rho_max = isempty(ρg_vals) ? NaN : maximum(ρg_vals)

    # Structural integrity check (ACI 8.7.4.2)
    integrity_ok = full_result.integrity_check.ok

    # Moment transfer additional bars (ACI 8.4.2.3)
    n_transfer_add = sum(
        isnothing(tr) ? 0 : tr.n_bars_additional
        for tr in full_result.transfer_results;
        init = 0
    )

    return (
        floor_type        = string(floor_type),
        lx_ft             = lx_ft,
        ly_ft             = ly_ft,
        story_ht_ft       = ht_ft,
        live_psf          = live_psf,
        method            = string(method_cfg.name),
        h_in              = ustrip(u"inch", r.thickness),
        sw_psf            = sw_psf,
        vol_per_area_in   = vol_per_area_in,
        M0_kipft          = to_kipft(r.M0),
        qu_psf            = ustrip(psf, r.qu),
        punch_ratio       = r.punching_check.max_ratio,
        punch_ok          = r.punching_check.ok,
        vu_max_psi        = vu_max_psi,
        has_studs         = has_studs,
        n_stud_cols       = n_stud_cols,
        stud_rails_max    = stud_rails_max,
        stud_per_rail_max = stud_per_rail_max,
        defl_ratio        = r.deflection_check.ratio,
        defl_ok           = r.deflection_check.ok,
        defl_in           = defl_in,
        defl_limit_in     = defl_lim_in,
        col_min_in        = minimum(cols_in),
        col_max_in        = maximum(cols_in),
        col_rho_max       = col_rho_max,
        As_cs_in2         = ustrip(u"inch^2", As_cs),
        As_ms_in2         = ustrip(u"inch^2", As_ms),
        As_total_in2      = ustrip(u"inch^2", As_cs + As_ms),
        integrity_ok      = integrity_ok,
        n_transfer_bars   = n_transfer_add,
        runtime_s         = round(elapsed; digits = 3),
        h_drop_in         = h_drop_in,
        a_drop1_ft        = a_drop1_ft,
        a_drop2_ft        = a_drop2_ft,
    )
end

# ==============================================================================
# Main sweep
# ==============================================================================

"""
    sweep(; spans, live_loads, n_bays, sdl, save)

Run all method × span × live-load combinations and return a DataFrame.

Each unique span builds the structure **once**; all (live_load, method)
combinations reuse the same geometry via snapshot/restore.

FEA mesh resolution adapts to span via `_adaptive_fea`.
Story height adapts to span via `_adaptive_story_ht`.

# Defaults
- `spans      = [16, 20, 24, 28, 32, 36, 40, 44, 48, 52]` (ft, square bays)
- `live_loads = [40, 50, 80]`                               (psf)
- `n_bays    = 3`                                            (3×3 grid)
- `sdl       = 20.0`                                         (psf)
- `save      = true`
"""
function sweep(;
    spans::Vector{Float64}     = [16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0, 52.0],
    live_loads::Vector{Float64} = [40.0, 50.0, 80.0],
    n_bays::Int                = 3,
    sdl::Float64               = 20.0,
    save::Bool                 = true,
    floor_type::Symbol         = :flat_plate,
)
    ft_label = floor_type === :flat_slab ? "Flat Slab" : "Flat Plate"
    n_methods = 5
    n_total   = length(spans) * length(live_loads) * n_methods

    print_header("$(ft_label) Method Comparison — Square Bays (adaptive story ht)")
    println("  Floor type: $(ft_label)")
    println("  Spans:      $(spans) ft")
    println("  Story hts:  $([_adaptive_story_ht(s) for s in spans]) ft")
    println("  Live loads: $(live_loads) psf")
    println("  Methods:    $n_methods  (FEA mesh adapts per span)")
    println("  Geometries: $(length(spans))  (built once each)")
    println("  Total runs: $n_total")
    println()

    rows   = NamedTuple[]
    n_fail = 0
    p      = Progress(n_total; desc = "Sweep ($(ft_label)): ")

    for span in spans
        ht = _adaptive_story_ht(span)
        struc, opts = _build_and_snapshot!(span, span, ht, n_bays;
                                           sdl_psf = sdl,
                                           floor_type = floor_type)
        methods = _method_configs(span, span)
        for ll in live_loads, mcfg in methods
            row = _run_on_prebuilt(struc, opts, mcfg;
                                   lx_ft = span, ly_ft = span, live_psf = ll,
                                   floor_type = floor_type)
            if isnothing(row)
                n_fail += 1
            else
                push!(rows, row)
            end
            next!(p)
        end
    end

    df = DataFrame(rows)

    outfile = nothing
    if save && !isempty(df)
        tag = floor_type === :flat_slab ? "flat_slab_methods" : "flat_plate_methods"
        outfile = output_filename(tag, FP_RESULTS_DIR)
        CSV.write(outfile, df)
    end

    print_footer(nrow(df), n_fail, outfile)
    return df
end

# ==============================================================================
# Convenience sweeps
# ==============================================================================

"""Sweep spans only (single live load)."""
span_sweep(; ll = 50.0, kw...) = sweep(; live_loads = [ll], kw...)

"""Sweep live loads only (single span)."""
load_sweep(; span = 20.0, kw...) = sweep(; spans = [span], kw...)

"""Run sweep for both flat plate and flat slab, return combined DataFrame."""
function dual_sweep(; kw...)
    df_fp = sweep(; floor_type = :flat_plate, kw...)
    df_fs = sweep(; floor_type = :flat_slab,  kw...)
    return vcat(df_fp, df_fs)
end

"""Run heatmap_sweep for both flat plate and flat slab, return combined DataFrame."""
function dual_heatmap_sweep(; kw...)
    df_fp = heatmap_sweep(; floor_type = :flat_plate, kw...)
    df_fs = heatmap_sweep(; floor_type = :flat_slab,  kw...)
    return vcat(df_fp, df_fs)
end

# ==============================================================================
# Pretty-print comparison table
# ==============================================================================

"""
    compare(; span=20.0, ll=50.0, n_bays=3, sdl=20.0)

Quick five-method comparison table for one span and live load.
Builds the geometry once and cycles through all methods.
"""
function compare(; span = 20.0, ll = 50.0,
                   n_bays = 3, sdl = 20.0)
    ht = _adaptive_story_ht(span)
    struc, opts = _build_and_snapshot!(span, span, ht, n_bays;
                                       sdl_psf = sdl, live_psf = ll)
    methods = _method_configs(span, span)

    println()
    @printf("  Square flat plate: %.0f ft × %.0f ft bays  |  LL = %.0f psf  |  %d×%d grid\n",
            span, span, ll, n_bays, n_bays)
    bar = "─" ^ 80
    println("  $bar")
    @printf("  %-16s │ h (in) │ M₀ (k-ft) │ Punch │ Defl  │ Columns    │  Time\n", "Method")
    println("  $bar")

    for mcfg in methods
        row = _run_on_prebuilt(struc, opts, mcfg;
                               lx_ft = span, ly_ft = span, live_psf = ll)
        if isnothing(row)
            @printf("  %-16s │  FAIL\n", mcfg.name)
        else
            col_str = row.col_min_in ≈ row.col_max_in ?
                @sprintf("%.0f\"", row.col_min_in) :
                @sprintf("%.0f\"–%.0f\"", row.col_min_in, row.col_max_in)
            @printf("  %-16s │ %5.1f  │  %7.2f  │ %5.3f │ %5.3f │ %-10s │ %5.2fs\n",
                    mcfg.name, row.h_in, row.M0_kipft, row.punch_ratio,
                    row.defl_ratio, col_str, row.runtime_s)
        end
    end
    println("  $bar")
    println()
end

# ==============================================================================
# Save / load helpers
# ==============================================================================

"""Save a DataFrame to the results directory."""
save_results(df, name = "flat_plate_methods") =
    CSV.write(output_filename(name, FP_RESULTS_DIR), df)

"""Load the latest results CSV."""
function load_results(dir = FP_RESULTS_DIR)
    csvs = filter(f -> endswith(f, ".csv"), readdir(dir; join = true))
    isempty(csvs) && error("No CSV files in $dir")
    latest = sort(csvs; by = mtime, rev = true)[1]
    println("Loading: $latest")
    return CSV.read(latest, DataFrame)
end

# ==============================================================================
# Heatmap sweep (Lx × Ly × LL × method)
# ==============================================================================

"""
    heatmap_sweep(; spans_x, spans_y, live_loads, ...)

Sweep Lx × Ly × LL × method for depth heatmap plots.

Each unique (Lx, Ly) pair builds the structure **once**; all (live_load, method)
combinations reuse the same geometry via snapshot/restore.

FEA mesh resolution adapts to span via `_adaptive_fea`.
Story height adapts to span via `_adaptive_story_ht`.

# Defaults
- `spans_x    = [16, 20, 24, 28, 32, 36, 40, 44, 48, 52]`  (ft)
- `spans_y    = [16, 20, 24, 28, 32, 36, 40, 44, 48, 52]`  (ft)
- `live_loads = [40, 50, 80]`                                 (psf)
"""
function heatmap_sweep(;
    spans_x::Vector{Float64}    = [16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0, 52.0],
    spans_y::Vector{Float64}    = [16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0, 52.0],
    live_loads::Vector{Float64} = [40.0, 50.0, 80.0],
    n_bays::Int                 = 3,
    sdl::Float64                = 20.0,
    save::Bool                  = true,
    floor_type::Symbol          = :flat_plate,
)
    ft_label = floor_type === :flat_slab ? "Flat Slab" : "Flat Plate"
    n_methods = 5
    n_geom   = length(spans_x) * length(spans_y)
    n_runs   = length(live_loads) * n_methods
    n_total  = n_geom * n_runs

    print_header("$(ft_label) Depth Heatmap — Rectangular Bays (adaptive FEA + story ht)")
    println("  Floor type: $(ft_label)")
    println("  Lx spans:   $(spans_x) ft")
    println("  Ly spans:   $(spans_y) ft")
    println("  Live loads: $(live_loads) psf")
    println("  Methods:    $n_methods  (FEA mesh adapts per geometry)")
    println("  Geometries: $n_geom  (built once each)")
    println("  Total runs: $n_total")
    println()

    rows   = NamedTuple[]
    n_fail = 0
    p      = Progress(n_total; desc="Heatmap ($(ft_label)): ")

    for lx in spans_x, ly in spans_y
        ht = _adaptive_story_ht(max(lx, ly))
        struc, opts = _build_and_snapshot!(lx, ly, ht, n_bays;
                                           sdl_psf = sdl,
                                           floor_type = floor_type)
        methods = _method_configs(lx, ly)
        for ll in live_loads, mcfg in methods
            row = _run_on_prebuilt(struc, opts, mcfg;
                                   lx_ft = lx, ly_ft = ly, live_psf = ll,
                                   floor_type = floor_type)
            if isnothing(row)
                n_fail += 1
            else
                push!(rows, row)
            end
            next!(p)
        end
    end

    df = DataFrame(rows)

    outfile = nothing
    if save && !isempty(df)
        tag = floor_type === :flat_slab ? "flat_slab_heatmap" : "flat_plate_heatmap"
        outfile = output_filename(tag, FP_RESULTS_DIR)
        CSV.write(outfile, df)
    end

    print_footer(nrow(df), n_fail, outfile)
    return df
end  # heatmap_sweep

# ==============================================================================
# Shear stud comparison sweep
# ==============================================================================

"""
    stud_sweep(; spans, live_loads, studs_list, floor_type, ...)

Sweep span × live_load × stud_strategy for a single floor type using FEA only.
Compares `:never`, `:if_needed`, `:always` stud strategies.

Returns a DataFrame with a `stud_strategy` column.
"""
function stud_sweep(;
    spans::Vector{Float64}      = [16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0, 52.0],
    live_loads::Vector{Float64}  = [50.0],
    studs_list::Vector{Symbol}   = [:never, :if_needed, :always],
    floor_type::Symbol           = :flat_plate,
    n_bays::Int                  = 3,
    sdl::Float64                 = 20.0,
    save::Bool                   = true,
)
    ft_label = floor_type === :flat_slab ? "Flat Slab" : "Flat Plate"
    n_total  = length(spans) * length(live_loads) * length(studs_list)

    print_header("$(ft_label) Shear Stud Comparison — FEA Only")
    println("  Floor type: $(ft_label)")
    println("  Spans:      $(spans) ft")
    println("  Live loads: $(live_loads) psf")
    println("  Stud modes: $(studs_list)")
    println("  Total runs: $n_total")
    println()

    rows   = NamedTuple[]
    n_fail = 0
    p      = Progress(n_total; desc = "Stud sweep: ")

    for stud_mode in studs_list
        for span in spans
            ht = _adaptive_story_ht(span)
            struc, opts = _build_and_snapshot!(span, span, ht, n_bays;
                                               sdl_psf = sdl,
                                               floor_type = floor_type,
                                               shear_studs = stud_mode)
            fea_cfg = (key = :fea, name = "FEA (studs=$(stud_mode))", obj = SR.FEA())
            for ll in live_loads
                row = _run_on_prebuilt(struc, opts, fea_cfg;
                                       lx_ft = span, ly_ft = span, live_psf = ll,
                                       floor_type = floor_type)
                if isnothing(row)
                    n_fail += 1
                else
                    # Tag with stud strategy
                    row = merge(row, (stud_strategy = string(stud_mode),))
                    push!(rows, row)
                end
                next!(p)
            end
        end
    end

    df = DataFrame(rows)

    outfile = nothing
    if save && !isempty(df)
        outfile = output_filename("stud_comparison_$(floor_type)", FP_RESULTS_DIR)
        CSV.write(outfile, df)
    end

    print_footer(nrow(df), n_fail, outfile)
    return df
end

"""Run stud comparison for both flat plate and flat slab."""
function dual_stud_sweep(; kw...)
    df_fp = stud_sweep(; floor_type = :flat_plate, kw...)
    df_fs = stud_sweep(; floor_type = :flat_slab,  kw...)
    return vcat(df_fp, df_fs)
end
