# ==============================================================================
# Flat Plate / Flat Slab Method Comparison — Visualizations
# ==============================================================================
#
# All plots are side-by-side: Flat Plate (left) | Flat Slab (right),
# with matched y-axes for direct comparison.
#
# Usage:
#   include("src/flat_plate_methods/vis.jl")
#   df = load_results("path/to/dual_sweep.csv")
#   generate_all(df)
#
# Available:
#   01  Slab thickness vs span
#   02  Static moment M₀ vs span
#   03  Punching shear ratio vs span
#   04  Deflection ratio vs span
#   05  Column sizes vs span (bar chart, hatched for flat slab)
#   06  Total rebar vs span
#   07  Runtime vs span (log scale)
#   08  Drop panel dimensions (flat slab only)
#   09  Depth heatmap — Flat Plate  (Lx × Ly, requires heatmap_sweep data)
#   10  Depth heatmap — Flat Slab   (Lx × Ly, requires heatmap_sweep data)
#
# ==============================================================================

include(joinpath(@__DIR__, "..", "init.jl"))

using StructuralPlots   # provides CairoMakie / GLMakie, Figure, Axis, etc.
using Statistics
using Printf

@isdefined(FP_FIGS_DIR)    || (const FP_FIGS_DIR    = joinpath(@__DIR__, "figs"))
@isdefined(FP_RESULTS_DIR) || (const FP_RESULTS_DIR = joinpath(@__DIR__, "results"))

# ==============================================================================
# I/O
# ==============================================================================

function load_results(path::String)
    df = CSV.read(path, DataFrame)
    println("Loaded $(nrow(df)) rows from $(basename(path))")
    return df
end

function _save_fig(fig, name)
    ensure_dir(FP_FIGS_DIR)
    path = joinpath(FP_FIGS_DIR, name)
    save(path, fig; px_per_unit = 2)
    println("  Saved: $path")
    return fig
end

# ==============================================================================
# Constants
# ==============================================================================

const METHOD_ORDER = ["MDDM", "DDM (Full)", "EFM (HC)", "EFM (ASAP)", "FEA"]
const METHOD_COLORS = Dict(
    "MDDM"       => :steelblue,
    "DDM (Full)"  => :royalblue,
    "EFM (HC)"    => :darkorange,
    "EFM (ASAP)"  => :orangered,
    "FEA"         => :forestgreen,
)
_color(m) = get(METHOD_COLORS, m, :gray)

_at_ll(df, ll) = filter(r -> r.live_psf ≈ ll, df)

"""Add `span_ft` column (= `lx_ft`) if missing."""
function _ensure_span(df)
    hasproperty(df, :span_ft) && return df
    hasproperty(df, :lx_ft) || error("DataFrame has neither `span_ft` nor `lx_ft`")
    out = copy(df)
    out.span_ft = out.lx_ft
    return out
end

"""Split df by floor_type; returns (flat_plate_df, flat_slab_df)."""
function _split_ft(df)
    fp = hasproperty(df, :floor_type) ? filter(r -> r.floor_type == "flat_plate", df) : df
    fs = hasproperty(df, :floor_type) ? filter(r -> r.floor_type == "flat_slab",  df) : DataFrame()
    return fp, fs
end

# ==============================================================================
# Generic side-by-side helper (line plots)
# ==============================================================================

"""
    _side_by_side(df, col, ylabel, suptitle, filename; ll, limit_line, yscale)

Side-by-side Flat Plate | Flat Slab figure for column `col`.
Shared y-axis range for direct comparison.
"""
function _side_by_side(df, col::Symbol, ylabel::String,
                       suptitle::String, filename::String;
                       ll::Float64 = 50.0,
                       limit_line::Union{Nothing,Float64} = nothing,
                       yscale = identity)
    sub = _at_ll(_ensure_span(df), ll)
    fp, fs = _split_ft(sub)

    fig = Figure(size = (1100, 450))
    Label(fig[0, 1:2], suptitle * " — LL = $(Int(ll)) psf";
          fontsize = 16, font = :bold, tellwidth = false)

    # Shared y range (start at 0 for linear scale)
    all_vals = filter(!isnan, sub[!, col])
    if yscale === identity
        y_lo = 0.0
        y_hi = isempty(all_vals) ? 1.0 : maximum(all_vals)
        if !isnothing(limit_line)
            y_hi = max(y_hi, limit_line)
        end
        y_hi += y_hi * 0.08
    else
        y_lo = isempty(all_vals) ? 0.1 : minimum(all_vals)
        y_hi = isempty(all_vals) ? 1.0 : maximum(all_vals)
        y_lo = max(y_lo * 0.8, 1e-6)
        y_hi *= 1.2
    end

    # Shared x range
    all_spans = sub.span_ft
    x_lo = isempty(all_spans) ? 0.0 : minimum(all_spans)
    x_hi = isempty(all_spans) ? 1.0 : maximum(all_spans)
    x_pad = (x_hi - x_lo) * 0.04
    x_lo -= x_pad;  x_hi += x_pad

    for (j, (ft_df, title)) in enumerate([(fp, "Flat Plate"), (fs, "Flat Slab")])
        ax = Axis(fig[1, j];
                  xlabel = "Span (ft)",
                  ylabel = j == 1 ? ylabel : "",
                  title  = title,
                  yscale = yscale)

        if !isnothing(limit_line)
            hlines!(ax, [limit_line]; color = :red, linestyle = :dash,
                    linewidth = 1, label = "Limit")
        end

        for m in METHOD_ORDER
            md = filter(r -> r.method == m, ft_df)
            isempty(md) && continue
            sp = sort(unique(md.span_ft))
            yv = Float64[filter(r -> r.span_ft == s, md)[1, col] for s in sp]
            lines!(ax, sp, yv; label = m, color = _color(m), linewidth = 2)
            scatter!(ax, sp, yv; color = _color(m), markersize = 8)
        end

        ylims!(ax, y_lo, y_hi)
        xlims!(ax, x_lo, x_hi)
        j == 2 && axislegend(ax; position = :lt, labelsize = 10)
    end

    return _save_fig(fig, filename)
end

# ==============================================================================
# Side-by-side plots (01 – 04, 06 – 07)
# ==============================================================================

plot_thickness(df; ll=50.0) =
    _side_by_side(df, :h_in, "h (in)", "Slab Thickness", "01_thickness.png"; ll)

plot_moments(df; ll=50.0) =
    _side_by_side(df, :M0_kipft, "M₀ (kip-ft)", "Static Moment M₀", "02_M0.png"; ll)

plot_punching(df; ll=50.0) =
    _side_by_side(df, :punch_ratio, "Punch ratio (vu / φvc)", "Punching Shear",
                  "03_punching.png"; ll, limit_line=1.0)

plot_deflection(df; ll=50.0) =
    _side_by_side(df, :defl_ratio, "Defl ratio (Δ / Δ_limit)", "Deflection",
                  "04_deflection.png"; ll, limit_line=1.0)

plot_rebar(df; ll=50.0) =
    _side_by_side(df, :As_total_in2, "Total As (in²)", "Total Rebar Area",
                  "06_rebar.png"; ll)

plot_runtime(df; ll=50.0) =
    _side_by_side(df, :runtime_s, "Runtime (s)", "Runtime",
                  "07_runtime.png"; ll, yscale=log10)

# ==============================================================================
# 05 — Column sizes (grouped bar chart with hatching for flat slab)
# ==============================================================================

"""Side-by-side column size bar chart. Flat Slab bars get a cross-hatch overlay."""
function plot_columns(df; ll = 50.0)
    sub = _at_ll(_ensure_span(df), ll)
    fp, fs = _split_ft(sub)

    fig = Figure(size = (1100, 450))
    Label(fig[0, 1:2], "Final Column Sizes — LL = $(Int(ll)) psf";
          fontsize = 16, font = :bold, tellwidth = false)

    # shared spans and y range
    all_spans = sort(unique(sub.span_ft))
    all_col = filter(!isnan, sub.col_max_in)
    y_hi = isempty(all_col) ? 40.0 : maximum(all_col) * 1.1

    for (j, (ft_df, title)) in enumerate([(fp, "Flat Plate"), (fs, "Flat Slab")])
        ax = Axis(fig[1, j];
                  xlabel = "Span (ft)", ylabel = j == 1 ? "Column size (in)" : "",
                  title  = title)

        spans = all_spans
        nm = length(METHOD_ORDER)
        w  = 0.15

        for (i, m) in enumerate(METHOD_ORDER)
            md = filter(r -> r.method == m, ft_df)
            isempty(md) && continue
            xs  = [findfirst(==(s), spans) for s in md.span_ft]
            off = (i - (nm + 1) / 2) * w
            barplot!(ax, xs .+ off, md.col_max_in;
                     width = w, color = _color(m), label = m,
                     strokewidth = j == 2 ? 1.0 : 0.0,
                     strokecolor = j == 2 ? :black : :transparent)
        end

        ax.xticks = (1:length(spans), string.(Int.(spans)))
        ylims!(ax, 0, y_hi)
        j == 2 && axislegend(ax; position = :lt, labelsize = 10)
    end

    return _save_fig(fig, "05_columns.png")
end

# ==============================================================================
# 08 — Drop panel dimensions (flat slab only)
# ==============================================================================

"""
    plot_drop_panels(df; ll=50.0)

Show drop panel depth (h_drop) and extent (a_drop) vs span for the flat slab
data.  Left axis = h_drop (in), right axis = a_drop (ft).
Only plots flat_slab rows; requires `h_drop_in`, `a_drop1_ft` columns.
"""
function plot_drop_panels(df; ll = 50.0)
    sub = _at_ll(_ensure_span(df), ll)
    fs_all = hasproperty(sub, :floor_type) ? filter(r -> r.floor_type == "flat_slab", sub) : sub
    (isempty(fs_all) || !hasproperty(fs_all, :h_drop_in)) && begin
        println("  Skipping drop panel plot — no flat_slab data with drop panel columns")
        return nothing
    end

    fig = Figure(size = (700, 450))
    ax1 = Axis(fig[1, 1];
               xlabel = "Span (ft)", ylabel = "Drop depth h_drop (in)",
               title  = "Flat Slab — Drop Panel Dimensions (LL = $(Int(ll)) psf)",
               yticklabelcolor = :steelblue)

    ax2 = Axis(fig[1, 1];
               ylabel = "Drop extent a_drop (ft)",
               yaxisposition = :right,
               yticklabelcolor = :darkorange)
    hidexdecorations!(ax2)
    hidespines!(ax2)

    # Use first method per span (drop panel geometry is method-independent)
    first_per_span = DataFrame()
    for sp in sort(unique(fs_all.span_ft))
        rows_sp = filter(r -> r.span_ft == sp, fs_all)
        isempty(rows_sp) && continue
        push!(first_per_span, rows_sp[1, :])
    end

    if !isempty(first_per_span)
        sp = first_per_span.span_ft

        # h_drop
        lines!(ax1, sp, first_per_span.h_drop_in;
               color = :steelblue, linewidth = 2, label = "h_drop")
        scatter!(ax1, sp, first_per_span.h_drop_in;
                 color = :steelblue, markersize = 10)

        # a_drop (use direction 1; they're typically equal for square bays)
        lines!(ax2, sp, first_per_span.a_drop1_ft;
               color = :darkorange, linewidth = 2, linestyle = :dash, label = "a_drop")
        scatter!(ax2, sp, first_per_span.a_drop1_ft;
                 color = :darkorange, markersize = 10, marker = :utriangle)

        # Annotate total slab+drop depth
        for row in eachrow(first_per_span)
            h_total = row.h_in + row.h_drop_in
            text!(ax1, row.span_ft, row.h_drop_in;
                  text = @sprintf("h_tot=%.1f\"", h_total),
                  align = (:center, :bottom), fontsize = 9, offset = (0, 5))
        end
    end

    # Legend manually
    Legend(fig[1, 2],
           [LineElement(color=:steelblue, linewidth=2),
            LineElement(color=:darkorange, linewidth=2, linestyle=:dash)],
           ["h_drop (in)", "a_drop (ft)"];
           labelsize = 11)

    return _save_fig(fig, "08_drop_panels.png")
end

# ==============================================================================
# 09/10 — Depth heatmaps (one per floor type, separate images)
# ==============================================================================

"""
    plot_depth_heatmap(df; floor_type, h_range)

Hartwell-style heatmap grid: methods (rows) × live loads (columns).
Generates a single image for the given `floor_type`.
Pass `h_range=(lo,hi)` to lock colorbar across companion plots.
"""
function plot_depth_heatmap(df; floor_type::String = "flat_plate",
                                h_range = nothing)
    work = hasproperty(df, :floor_type) ? filter(r -> r.floor_type == floor_type, df) : df
    isempty(work) && begin
        println("  Skipping heatmap for $floor_type — no data")
        return nothing
    end

    ft_label = floor_type == "flat_slab" ? "Flat Slab" : "Flat Plate"

    methods    = METHOD_ORDER
    live_loads = sort(unique(work.live_psf))
    lx_vals    = sort(unique(work.lx_ft))
    ly_vals    = sort(unique(work.ly_ft))

    n_methods = length(methods)
    n_loads   = length(live_loads)

    h_min = isnothing(h_range) ? floor(minimum(work.h_in)) : h_range[1]
    h_max = isnothing(h_range) ? ceil(maximum(work.h_in))  : h_range[2]

    lo_x, hi_x = extrema(lx_vals)
    lo_y, hi_y = extrema(ly_vals)

    fig = Figure(size = (340 * n_loads + 120, 260 * n_methods + 100))

    Label(fig[0, 1:n_loads],
          "$ft_label — Optimal Slab Depth by Plan Dimensions";
          fontsize = 18, font = :bold, tellwidth = false)

    for (i, m) in enumerate(methods)
        for (j, ll) in enumerate(live_loads)
            sub = filter(r -> r.method == m && r.live_psf ≈ ll, work)

            Z = fill(NaN, length(lx_vals), length(ly_vals))
            for row in eachrow(sub)
                xi = findfirst(==(row.lx_ft), lx_vals)
                yi = findfirst(==(row.ly_ft), ly_vals)
                !isnothing(xi) && !isnothing(yi) && (Z[xi, yi] = row.h_in)
            end

            ax = Axis(fig[i, j];
                      xlabel  = i == n_methods ? "Lx (ft)" : "",
                      ylabel  = j == 1 ? "Ly (ft)" : "",
                      title   = i == 1 ? "LL = $(Int(ll)) psf" : "",
                      aspect  = DataAspect(),
                      xticklabelsize = 10, yticklabelsize = 10)

            if !all(isnan.(Z))
                heatmap!(ax, lx_vals, ly_vals, Z;
                         colormap = :viridis, colorrange = (h_min, h_max),
                         interpolate = true, nan_color = (:gray, 0.3))
            end

            xlims!(ax, lo_x, hi_x)
            ylims!(ax, lo_y, hi_y)

            diag_hi = min(hi_x, hi_y)
            lines!(ax, [lo_x, diag_hi], [lo_x, diag_hi];
                   color = :white, linestyle = :dash, linewidth = 0.8)

            x2_end = min(hi_x, hi_y / 2)
            x2_end > lo_x && lines!(ax, [lo_x, x2_end], [2lo_x, 2x2_end];
                                     color = :white, linestyle = :dot, linewidth = 0.7)
            y2_end = min(hi_y, hi_x / 2)
            y2_end > lo_y && lines!(ax, [2lo_y, 2y2_end], [lo_y, y2_end];
                                     color = :white, linestyle = :dot, linewidth = 0.7)

            for row in eachrow(sub)
                row.lx_ft ≈ row.ly_ft || continue
                text!(ax, row.lx_ft, row.ly_ft;
                      text = @sprintf("%.0f\"", row.h_in),
                      align = (:center, :center), fontsize = 9,
                      color = :white, strokewidth = 0.5, strokecolor = :black)
            end
        end

        Label(fig[i, 0], m;
              fontsize = 12, font = :bold, rotation = π/2, tellheight = false)
    end

    Colorbar(fig[1:n_methods, n_loads + 1];
             colormap = :viridis, colorrange = (h_min, h_max),
             label = "Depth (in)", labelsize = 12)

    tag = floor_type == "flat_slab" ? "flat_slab" : "flat_plate"
    return _save_fig(fig, "$(floor_type == "flat_slab" ? "10" : "09")_heatmap_$(tag).png")
end

"""Generate both heatmap images with matched color range."""
function plot_dual_heatmaps(df)
    h_lo = floor(minimum(df.h_in))
    h_hi = ceil(maximum(df.h_in))
    h_range = (h_lo, h_hi)
    plot_depth_heatmap(df; floor_type = "flat_plate", h_range)
    plot_depth_heatmap(df; floor_type = "flat_slab",  h_range)
end

# ==============================================================================
# Generate all
# ==============================================================================

"""
    generate_all(df; ll=50.0)

Generate all comparison figures from a dual-sweep DataFrame.
"""
function generate_all(df; ll = 50.0)
    println("\nGenerating Flat Plate vs Flat Slab figures (LL = $(Int(ll)) psf)...")
    plot_thickness(df; ll)
    plot_moments(df; ll)
    plot_punching(df; ll)
    plot_deflection(df; ll)
    plot_columns(df; ll)
    plot_rebar(df; ll)
    plot_runtime(df; ll)
    plot_drop_panels(df; ll)

    # Heatmaps if rectangular data exists (lx ≠ ly for some rows)
    has_rect = any(r -> r.lx_ft != r.ly_ft, eachrow(df))
    if has_rect
        plot_dual_heatmaps(df)
    else
        println("  (Skipping heatmaps — square-bay data only; run dual_heatmap_sweep() for Lx×Ly grid)")
    end

    println("\nDone — figures saved to $FP_FIGS_DIR")
end

# ==============================================================================
# 11 — Shear stud comparison plots
# ==============================================================================

const STUD_STYLES = Dict(
    "never"     => (color = :steelblue,   linestyle = :solid),
    "if_needed" => (color = :darkorange,  linestyle = :dash),
    "always"    => (color = :forestgreen, linestyle = :dot),
)

"""
    plot_stud_comparison(df; ll = 50.0)

Side-by-side Flat Plate | Flat Slab: compare thickness, punching ratio,
and column sizes across stud strategies.

Expects `stud_strategy` column from `stud_sweep`.
"""
function plot_stud_comparison(df; ll = 50.0)
    hasproperty(df, :stud_strategy) || begin
        println("  Skipping stud comparison — no stud_strategy column")
        return nothing
    end

    sub = _at_ll(_ensure_span(df), ll)
    fp, fs = _split_ft(sub)

    metrics = [
        (:h_in,        "h (in)",                "Slab Thickness"),
        (:punch_ratio, "Punch ratio (vu/φvc)",   "Punching Shear"),
        (:col_max_in,  "Column size (in)",       "Max Column Size"),
    ]

    for (col, ylabel, title) in metrics
        fig = Figure(size = (1100, 450))
        Label(fig[0, 1:2], "$(title) — Stud Strategy Comparison (LL=$(Int(ll)) psf)";
              fontsize = 16, font = :bold, tellwidth = false)

        for (j, (ft_df, ft_title)) in enumerate([(fp, "Flat Plate"), (fs, "Flat Slab")])
            ax = Axis(fig[1, j];
                      xlabel = "Span (ft)",
                      ylabel = j == 1 ? ylabel : "",
                      title  = ft_title)

            if col === :punch_ratio
                hlines!(ax, [1.0]; color = :red, linestyle = :dash, linewidth = 1, label = "Limit")
            end

            for stud in ["never", "if_needed", "always"]
                sd = filter(r -> r.stud_strategy == stud, ft_df)
                isempty(sd) && continue
                sp = sort(unique(sd.span_ft))
                yv = Float64[]
                for s in sp
                    rows_s = filter(r -> r.span_ft == s, sd)
                    push!(yv, isempty(rows_s) ? NaN : rows_s[1, col])
                end
                sty = get(STUD_STYLES, stud, (color=:gray, linestyle=:solid))
                lines!(ax, sp, yv; label = "studs=$stud",
                       color = sty.color, linestyle = sty.linestyle, linewidth = 2)
                scatter!(ax, sp, yv; color = sty.color, markersize = 8)
            end

            ylims!(ax, 0, nothing)
            j == 2 && axislegend(ax; position = :lt, labelsize = 10)
        end

        slug = replace(string(col), r"\W" => "_")
        _save_fig(fig, "11_stud_$(slug).png")
    end
end
