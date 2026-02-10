# ==============================================================================
# Column Study Visualizations
# ==============================================================================
#
# Curated figures for RC column parametric study analysis.
#
# Usage (REPL, standalone):
#   include("src/column_properties/vis.jl")
#   df = load_results()           # loads latest CSV
#   generate_all(df)              # all 9 figures → figs/
#   plot_pareto(df)               # or individual
#
# Usage (REPL, after running a sweep):
#   include("src/column_properties/column_parametric_study.jl")
#   df = material_sweep()
#   include("src/column_properties/vis.jl")
#   plot_pareto(df)               # pass your df directly
#
# Available plots:
#   plot_pareto(df)               Capacity vs carbon Pareto frontier
#   plot_heatmap(df)              f'c × ρ capacity heatmap grid
#   plot_capacity_scaling(df)     φPn,max vs Ag and As
#   plot_slenderness(df)          δns boxplots by kLu/r
#   plot_efficiency(df)           Carbon efficiency vs ρ
#   plot_carbon_breakdown(df)     Stacked bar: concrete vs steel
#   plot_carbon_crossover(df)     Carbon fraction crossover
#   plot_fy_comparison(df)        Grade 60 vs 80
#   generate_all(df)              All of the above → figs/
#
# ==============================================================================

include(joinpath(@__DIR__, "..", "init.jl"))

using StructuralPlots
using Statistics

# Guard const definitions so vis.jl can be loaded after the study file
# or re-included after edits without hitting redefinition errors.
@isdefined(FIGS_DIR)    || (const FIGS_DIR    = joinpath(@__DIR__, "figs"))
@isdefined(RESULTS_DIR) || (const RESULTS_DIR = joinpath(@__DIR__, "results"))

# ==============================================================================
# I/O
# ==============================================================================

"""Load study results from the latest (or specified) CSV."""
function load_results(path::String=_latest_csv())
    df = CSV.read(path, DataFrame)
    for col in [:shape, :arrangement, :tie_type]
        hasproperty(df, col) && eltype(df[!, col]) <: AbstractString &&
            (df[!, col] = Symbol.(df[!, col]))
    end
    println("Loaded $(nrow(df)) rows from $(basename(path))")
    return df
end

function _latest_csv(dir=RESULTS_DIR)
    files = filter(f -> endswith(f, ".csv") && startswith(f, "column_study"),
                   readdir(dir))
    isempty(files) && error("No column_study CSVs in $dir")
    joinpath(dir, sort(files)[end])
end

# ==============================================================================
# Helpers
# ==============================================================================

# Color palette — guarded for re-include safety
if !@isdefined(_VIS_COLORS_LOADED)
    const _VIS_COLORS_LOADED = true
    const C = (
        rect      = sp_ceruleanblue,
        circ      = sp_magenta,
        concrete  = sp_charcoalgrey,
        steel     = sp_skyblue,
        fc3       = sp_powderblue,
        fc4       = sp_skyblue,
        fc5       = sp_ceruleanblue,
        fc6       = sp_irispurple,
        fc8       = sp_darkpurple,
    )
end

_save(path, fig) = (fig.scene.backgroundcolor[] = RGBf(1, 1, 1); save(path, fig))

"""Mean and std grouped by `xcol`."""
function stats_by(df, xcol, ycol)
    g = combine(groupby(df, xcol),
        ycol => mean => :μ,
        ycol => std  => :σ,
        ycol => length => :n)
    sort!(g, xcol)
    g.σ = coalesce.(g.σ, 0.0)
    replace!(g.σ, NaN => 0.0)
    return g
end

"""Filter to canonical tie types (rect→tied, circular→spiral)."""
function canonical(df)
    filter(r -> (r.shape == :rect && r.tie_type == :tied) ||
                (r.shape == :circular && r.tie_type == :spiral), df)
end

"""Bin rho_actual to nearest target bucket for cleaner heatmaps."""
function bin_rho(rho; targets=[0.01, 0.02, 0.03, 0.04, 0.06])
    _, i = findmin(abs.(rho .- targets))
    targets[i]
end

"""Indices of Pareto-optimal points (minimize x, maximize y)."""
function pareto_indices(x, y)
    order = sortperm(x)
    idx   = Int[]
    best  = -Inf
    for i in order
        if y[i] > best
            push!(idx, i)
            best = y[i]
        end
    end
    return idx
end

# ==============================================================================
# 1. Pareto Frontier — Capacity vs Carbon
# ==============================================================================

"""
    plot_pareto(df; save_path=nothing)

Scatter of all designs (grey) with Pareto frontier highlighted.
Shows the efficient capacity-vs-carbon trade-off.
"""
function plot_pareto(df; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 600))
    ax = Axis(fig[1,1],
        xlabel = "Embodied Carbon (kg CO₂e)",
        ylabel = "φPn,max (kip)",
        title  = "Capacity vs Carbon — Pareto Frontier")

    d = canonical(df)
    x, y = d.carbon_total_kg, d.phi_Pn_max_kip

    scatter!(ax, x, y,
        color=(sp_mediumgray, 0.15), markersize=3, strokewidth=0)

    idx = pareto_indices(x, y)
    lines!(ax, x[idx], y[idx], color=sp_ceruleanblue, linewidth=3)
    scatter!(ax, x[idx], y[idx],
        color=sp_ceruleanblue, markersize=6, strokewidth=0)

    Legend(fig[1,2],
        [MarkerElement(color=(sp_mediumgray, 0.5), marker=:circle, markersize=8),
         LineElement(color=sp_ceruleanblue, linewidth=3)],
        ["All designs", "Pareto frontier"])

    !isnothing(save_path) && _save(save_path, fig)
    return fig
end

# ==============================================================================
# 2. Material Heatmap — f'c × ρ → φPn,max
# ==============================================================================

"""
    plot_heatmap(df; shape=:rect, save_path=nothing)

2×2 grid of heatmaps (16/20/24/30\") showing how f'c and ρ jointly drive capacity.
"""
function plot_heatmap(df; shape=:rect, save_path=nothing)
    set_theme!(sp_light)
    sizes    = [16, 20, 24, 30]
    size_col = shape == :rect ? :b_in : :D_in
    tie      = shape == :rect ? :tied : :spiral
    label    = shape == :rect ? "Rectangular (tied)" : "Circular (spiral)"

    fig = Figure(size=(1200, 900))
    Label(fig[0,:], "φPn,max Heatmap — $label", fontsize=18, tellwidth=false)

    for (idx, sz) in enumerate(sizes)
        row, col = divrem(idx - 1, 2) .+ 1
        sub = filter(r -> r.shape == shape && r[size_col] == sz &&
                          r.tie_type == tie, df)
        isempty(sub) && continue

        sub = copy(sub)
        sub.rho_bin = bin_rho.(sub.rho_actual)
        g = combine(groupby(sub, [:fc_ksi, :rho_bin]),
            :phi_Pn_max_kip => mean => :cap)

        fc_vals  = sort(unique(g.fc_ksi))
        rho_vals = sort(unique(g.rho_bin))
        mat = zeros(length(fc_vals), length(rho_vals))
        for r in eachrow(g)
            fi = findfirst(==(r.fc_ksi), fc_vals)
            ri = findfirst(==(r.rho_bin), rho_vals)
            !isnothing(fi) && !isnothing(ri) && (mat[fi, ri] = r.cap)
        end

        ax = Axis(fig[row, col],
            xlabel = "f'c (ksi)", ylabel = "ρ",
            title = "$(sz)\" $(shape == :rect ? "square" : "dia")",
            xticks = (1:length(fc_vals), string.(Int.(fc_vals))),
            yticks = (1:length(rho_vals),
                      ["$(round(r*100,digits=1))%" for r in rho_vals]),
            xgridvisible = false, ygridvisible = false)

        hm = heatmap!(ax, mat, colormap=blue2gold)
        xlims!(ax, 0.5, length(fc_vals) + 0.5)
        ylims!(ax, 0.5, length(rho_vals) + 0.5)
        col == 2 && Colorbar(fig[row, 3], hm, label="φPn,max (kip)")
    end

    !isnothing(save_path) && _save(save_path, fig)
    return fig
end

# ==============================================================================
# 3. Capacity Scaling — φPn,max vs Ag / As
# ==============================================================================

"""
    plot_capacity_scaling(df; save_path=nothing)

Two-panel scatter: capacity vs gross area and vs steel area, colored by f'c.
Shows how section size and steel drive capacity.
"""
function plot_capacity_scaling(df; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(1100, 500))

    d = filter(r -> (r.shape == :rect && r.aspect_ratio == 1.0 &&
                     r.tie_type == :tied) ||
                    (r.shape == :circular && r.tie_type == :spiral), df)

    cmap = cgrad([sp_skyblue, sp_ceruleanblue, sp_gold, sp_orange])
    cr   = extrema(d.fc_ksi)

    ax1 = Axis(fig[1,1], xlabel="Ag (in²)", ylabel="φPn,max (kip)",
               title="Capacity vs Gross Area")
    scatter!(ax1, d.Ag_in2, d.phi_Pn_max_kip,
        color=d.fc_ksi, colormap=cmap, colorrange=cr,
        markersize=4, strokewidth=0, alpha=0.5)

    ax2 = Axis(fig[1,2], xlabel="As (in²)", ylabel="φPn,max (kip)",
               title="Capacity vs Steel Area")
    scatter!(ax2, d.As_in2, d.phi_Pn_max_kip,
        color=d.fc_ksi, colormap=cmap, colorrange=cr,
        markersize=4, strokewidth=0, alpha=0.5)

    Colorbar(fig[1,3], colormap=cmap, colorrange=cr, label="f'c (ksi)")

    !isnothing(save_path) && _save(save_path, fig)
    return fig
end

# ==============================================================================
# 4. Slenderness — Boxplots at each kLu/r
# ==============================================================================

"""
    plot_slenderness(df; save_path=nothing)

Box plots showing moment magnification distribution at kLu/r = 30, 50, 70.
Reference lines at δns=1.0 (no effect) and δns=1.4 (design concern).
"""
function plot_slenderness(df; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(800, 500))
    ax = Axis(fig[1,1],
        xlabel = "kLu/r",
        ylabel = "Moment Magnification δns",
        title  = "Slenderness Effect — Distribution by kLu/r",
        xticks = ([30, 50, 70], ["30", "50", "70"]))

    d = canonical(df)
    kLu_levels = [30, 50, 70]
    cols = [:kLu_r_30_delta_ns, :kLu_r_50_delta_ns, :kLu_r_70_delta_ns]

    xs, ys = Float64[], Float64[]
    for row in eachrow(d)
        for (k, c) in zip(kLu_levels, cols)
            v = row[c]
            isfinite(v) && v < 5 && (push!(xs, Float64(k)); push!(ys, v))
        end
    end

    boxplot!(ax, xs, ys,
        color=sp_ceruleanblue, whiskerwidth=0.5,
        mediancolor=:white, show_outliers=false)

    hlines!(ax, [1.0], color=sp_mediumgray, linestyle=:dash)
    hlines!(ax, [1.4], color=sp_orange, linestyle=:dash, linewidth=2)

    text!(ax, 72, 1.05, text="no effect", fontsize=11,
        color=sp_mediumgray, align=(:right, :bottom))
    text!(ax, 72, 1.45, text="design concern", fontsize=11,
        color=sp_orange, align=(:right, :bottom))

    !isnothing(save_path) && _save(save_path, fig)
    return fig
end

# ==============================================================================
# 5. Carbon Efficiency — φPn,max / Carbon vs ρ
# ==============================================================================

"""
    plot_efficiency(df; save_path=nothing)

Carbon efficiency (kip per kg CO₂e) vs reinforcement ratio, colored by Ag.
Shows that lower ρ and larger sections are more carbon-efficient.
"""
function plot_efficiency(df; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(950, 600))
    ax = Axis(fig[1,1],
        xlabel = "Reinforcement Ratio ρ (%)",
        ylabel = "φPn,max / Carbon (kip / kg CO₂e)",
        title  = "Carbon Efficiency vs Reinforcement Ratio")

    d = filter(r -> r.carbon_total_kg > 0, canonical(df))
    d = copy(d)
    d.eff = d.phi_Pn_max_kip ./ d.carbon_total_kg

    cmap = cgrad([sp_powderblue, sp_ceruleanblue, sp_irispurple, sp_darkpurple])
    cr   = extrema(d.Ag_in2)

    scatter!(ax, d.rho_actual .* 100, d.eff,
        color=d.Ag_in2, colormap=cmap, colorrange=cr,
        markersize=4, strokewidth=0, alpha=0.5)
    Colorbar(fig[1,2], colormap=cmap, colorrange=cr, label="Ag (in²)")

    !isnothing(save_path) && _save(save_path, fig)
    return fig
end

# ==============================================================================
# 6. Carbon Breakdown — Stacked bar: concrete vs steel
# ==============================================================================

"""
    plot_carbon_breakdown(df; size=20, save_path=nothing)

Stacked bar chart showing concrete vs steel carbon at each ρ level.
"""
function plot_carbon_breakdown(df; size=20, save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 500))
    ax = Axis(fig[1,1],
        xlabel = "Reinforcement Ratio ρ (%)",
        ylabel = "Embodied Carbon (kg CO₂e)",
        title  = "Carbon Breakdown — $(size)\" Square (tied)")

    d = filter(r -> r.shape == :rect && r.b_in == size &&
                    r.aspect_ratio == 1.0 && r.fc_ksi == 4.0 &&
                    r.tie_type == :tied, df)

    g = combine(groupby(d, :rho_actual),
        :carbon_concrete_kg => mean => :concrete,
        :carbon_steel_kg    => mean => :steel)
    sort!(g, :rho_actual)

    if !isempty(g)
        x = g.rho_actual .* 100
        barplot!(ax, x, g.concrete,
            color=C.concrete, label="Concrete", width=0.8)
        barplot!(ax, x, g.steel,
            color=C.steel, label="Steel", width=0.8,
            offset=g.concrete)
        axislegend(ax, position=:lt)
    end

    !isnothing(save_path) && _save(save_path, fig)
    return fig
end

# ==============================================================================
# 7. Carbon Crossover — Fraction by material
# ==============================================================================

"""
    plot_carbon_crossover(df; size=20, save_path=nothing)

Concrete vs steel carbon fraction vs ρ, showing the ~2.5% crossover point
where steel carbon overtakes concrete.
"""
function plot_carbon_crossover(df; size=20, save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 500))
    ax = Axis(fig[1,1],
        xlabel = "Reinforcement Ratio ρ (%)",
        ylabel = "Carbon Fraction (%)",
        title  = "Concrete vs Steel Carbon Share — $(size)\" Square (tied)")

    d = filter(r -> r.shape == :rect && r.b_in == size &&
                    r.aspect_ratio == 1.0 && r.tie_type == :tied, df)
    d = copy(d)
    d.cf = d.carbon_concrete_kg ./ d.carbon_total_kg .* 100
    d.sf = d.carbon_steel_kg    ./ d.carbon_total_kg .* 100

    scatter!(ax, d.rho_actual .* 100, d.cf,
        color=C.concrete, alpha=0.4, markersize=4, strokewidth=0)
    scatter!(ax, d.rho_actual .* 100, d.sf,
        color=C.steel, alpha=0.4, markersize=4, strokewidth=0)

    sc = stats_by(d, :rho_actual, :cf)
    ss = stats_by(d, :rho_actual, :sf)
    lines!(ax, sc.rho_actual .* 100, sc.μ, color=C.concrete, linewidth=3)
    lines!(ax, ss.rho_actual .* 100, ss.μ, color=C.steel,    linewidth=3)

    hlines!(ax, [50], color=sp_mediumgray, linestyle=:dash)

    Legend(fig[1,2],
        [MarkerElement(color=C.concrete, marker=:circle, markersize=10),
         MarkerElement(color=C.steel,    marker=:circle, markersize=10),
         LineElement(color=sp_mediumgray, linestyle=:dash)],
        ["Concrete", "Steel", "50% crossover"])

    !isnothing(save_path) && _save(save_path, fig)
    return fig
end

# ==============================================================================
# 8. Grade 60 vs 80 Comparison
# ==============================================================================

"""
    plot_fy_comparison(df; save_path=nothing)

Side-by-side panels comparing Grade 60 vs Grade 80 rebar: P₀/Ag vs ρ,
colored by Ag. Shows the marginal benefit of higher-strength rebar.
"""
function plot_fy_comparison(df; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(1000, 500))

    d = filter(r -> r.shape == :rect && r.aspect_ratio == 1.0 &&
                    r.fc_ksi == 4.0 && r.tie_type == :tied, df)

    cmap = cgrad([sp_powderblue, sp_ceruleanblue, sp_irispurple, sp_darkpurple])
    isempty(d) && return fig
    cr = extrema(d.Ag_in2)

    for (panel, grade, title) in [(1, 60.0, "Grade 60"), (2, 80.0, "Grade 80")]
        ax = Axis(fig[1, panel],
            xlabel = "ρ (%)",
            ylabel = "P₀ / Ag (ksi)",
            title  = "$title — colored by Ag")
        sub = filter(r -> r.fy_ksi == grade, d)
        !isempty(sub) && scatter!(ax, sub.rho_actual .* 100, sub.P0_per_Ag_ksi,
            color=sub.Ag_in2, colormap=cmap, colorrange=cr,
            markersize=5, strokewidth=0, alpha=0.5)
    end

    Colorbar(fig[1,3], colormap=cmap, colorrange=cr, label="Ag (in²)")

    !isnothing(save_path) && _save(save_path, fig)
    return fig
end

# ==============================================================================
# Generate All
# ==============================================================================

"""Generate all 9 figures and save to `figs/` directory."""
function generate_all(df; dir=FIGS_DIR)
    isdir(dir) || mkpath(dir)
    p(name) = joinpath(dir, "$name.png")

    println("Generating figures → $dir\n")

    figures = [
        ("01_pareto",           () -> plot_pareto(df;           save_path=p("01_pareto"))),
        ("02_heatmap_rect",     () -> plot_heatmap(df;          shape=:rect,     save_path=p("02_heatmap_rect"))),
        ("03_heatmap_circ",     () -> plot_heatmap(df;          shape=:circular, save_path=p("03_heatmap_circ"))),
        ("04_capacity_scaling", () -> plot_capacity_scaling(df;  save_path=p("04_capacity_scaling"))),
        ("05_slenderness",      () -> plot_slenderness(df;      save_path=p("05_slenderness"))),
        ("06_efficiency",       () -> plot_efficiency(df;        save_path=p("06_efficiency"))),
        ("07_carbon_breakdown", () -> plot_carbon_breakdown(df;  save_path=p("07_carbon_breakdown"))),
        ("08_carbon_crossover", () -> plot_carbon_crossover(df;  save_path=p("08_carbon_crossover"))),
        ("09_fy_comparison",    () -> plot_fy_comparison(df;     save_path=p("09_fy_comparison"))),
    ]

    for (name, fn) in figures
        print("  $name ... ")
        fn()
        println("✓")
    end

    println("\n✓ $(length(figures)) figures saved to $dir")
end

# ==============================================================================
println("\nVisualization loaded. Try:")
println("  df = load_results()           # latest CSV")
println("  generate_all(df)              # all figures → figs/")
println("  plot_pareto(df)               # individual figure")
println()
println("Or pass a DataFrame from a sweep directly:")
println("  df = material_sweep()")
println("  plot_pareto(df)")
