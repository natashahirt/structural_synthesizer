# ==============================================================================
# Runner: Dual Heatmap Sweep (Flat Plate + Flat Slab)
# ==============================================================================
# Runs the full Lx × Ly × LL × method sweep for both floor types.
# Results saved to StructuralStudies/src/flat_plate_methods/results/
#
# Usage:
#   julia scripts/runners/run_heatmap_sweep.jl           # default (ACI only)
#   julia scripts/runners/run_heatmap_sweep.jl quick      # 3×3 quick smoke test
#   julia scripts/runners/run_heatmap_sweep.jl full       # ACI + no-minimum
# ==============================================================================

# ── Sweep parameters (edit these) ────────────────────────────────────────────

const SPANS_X    = collect(16.0:4.0:52.0)   # ft — bay widths
const SPANS_Y    = collect(16.0:4.0:52.0)   # ft — bay depths
const LIVE_LOADS = [50.0, 150.0, 250.0]     # psf
const N_BAYS     = 3                        # bays per direction (3×3 grid)
const SDL        = 20.0                     # psf — superimposed dead load
const MAX_COL_IN = nothing                  # in — fixed max column size (nothing = use adaptive)
const COL_RATIO  = 1.1                      # adaptive multiplier: col = span_ft × ratio, clamped 36–60"
const DEFL_LIMIT = :L_360                   # :L_240, :L_360, or :L_480 (ACI Table 24.2.2)

# Quick-test subset (used with `quick` CLI arg)
const SPANS_QUICK = [20.0, 32.0, 44.0]
const LL_QUICK    = [50.0]

# ── Load study code ──────────────────────────────────────────────────────────

include(joinpath(@__DIR__, "..", "..", "StructuralStudies", "src",
                 "flat_plate_methods", "flat_plate_method_comparison.jl"))
using Unitful

# ── Run sweep ────────────────────────────────────────────────────────────────

mode = length(ARGS) > 0 ? ARGS[1] : "default"

df = if mode == "quick"
    println("\n=== QUICK TEST ($(length(SPANS_QUICK))×$(length(SPANS_QUICK)) grid, $(length(LL_QUICK)) LL, ACI only) ===\n")
    dual_heatmap_sweep(;
        spans_x          = SPANS_QUICK,
        spans_y          = SPANS_QUICK,
        live_loads       = LL_QUICK,
        n_bays           = N_BAYS,
        sdl              = SDL,
        max_col_in       = MAX_COL_IN,
        col_ratio        = COL_RATIO,
        deflection_limit = DEFL_LIMIT,
    )
elseif mode == "full"
    println("\n=== FULL SWEEP ($(length(SPANS_X))×$(length(SPANS_Y)) grid, ACI + no-minimum) ===\n")
    dual_heatmap_sweep(;
        spans_x          = SPANS_X,
        spans_y          = SPANS_Y,
        live_loads       = LIVE_LOADS,
        n_bays           = N_BAYS,
        sdl              = SDL,
        max_col_in       = MAX_COL_IN,
        col_ratio        = COL_RATIO,
        deflection_limit = DEFL_LIMIT,
        min_h_variants   = [
            ("ACI",   nothing),       # ACI Table 8.3.1.1 minimum thickness
            ("nomin", 1.0u"inch"),     # strength/serviceability governs
        ],
    )
else
    println("\n=== DEFAULT SWEEP ($(length(SPANS_X))×$(length(SPANS_Y)) grid, ACI only) ===\n")
    dual_heatmap_sweep(;
        spans_x          = SPANS_X,
        spans_y          = SPANS_Y,
        live_loads       = LIVE_LOADS,
        n_bays           = N_BAYS,
        sdl              = SDL,
        max_col_in       = MAX_COL_IN,
        col_ratio        = COL_RATIO,
        deflection_limit = DEFL_LIMIT,
    )
end

# ── Generate figures ─────────────────────────────────────────────────────────

include(joinpath(@__DIR__, "..", "..", "StructuralStudies", "src",
                 "flat_plate_methods", "vis.jl"))
using CairoMakie
CairoMakie.activate!()

println("\n=== Generating line plots (01–08) ===\n")
Base.invokelatest(generate_all, df)

println("\n=== Generating heatmap plots (per variant, imperial + metric) ===\n")
valid_h = filter(!isnan, df.h_in)
if isempty(valid_h)
    println("  Skipping heatmaps — no valid h_in values")
else
    h_range = (0.0, ceil(maximum(valid_h)))

    if hasproperty(df, :min_h_rule)
        for v in sort(unique(df.min_h_rule))
            sub = filter(r -> r.min_h_rule == v, df)
            for metric in (false, true)
                sfx = metric ? "_$(v)_metric" : "_$v"
                Base.invokelatest(plot_depth_heatmap, sub; floor_type="flat_plate",
                                  h_range, title_suffix=" [$v]", file_suffix=sfx, metric)
                Base.invokelatest(plot_depth_heatmap, sub; floor_type="flat_slab",
                                  h_range, title_suffix=" [$v]", file_suffix=sfx, metric)
            end
        end
    else
        Base.invokelatest(plot_dual_heatmaps, df; file_suffix="")
        Base.invokelatest(plot_dual_heatmaps, df; file_suffix="_metric", metric=true)
    end
end

println("\nDone. $(nrow(df)) records written.")
