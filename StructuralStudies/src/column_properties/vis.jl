# ==============================================================================
# Column Parametric Study Visualizations
# ==============================================================================
# Explores trade-offs between Ag, ρ, f'c, fy for RC column design.
# ==============================================================================

include("../init.jl")

using StructuralPlots
using Statistics

const FIGS_DIR = joinpath(@__DIR__, "figs")

# ==============================================================================
# Data Loading
# ==============================================================================

"""Load study results from CSV and convert string columns to symbols."""
function load_study_results(filepath::String)
    df = CSV.read(filepath, DataFrame)
    for col in [:shape, :arrangement, :tie_type]
        if hasproperty(df, col) && eltype(df[!, col]) <: AbstractString
            df[!, col] = Symbol.(df[!, col])
        end
    end
    println("Loaded $(nrow(df)) records from $filepath")
    return df
end

"""Get latest results file from a results directory."""
function latest_results(results_dir::String)
    files = filter(f -> endswith(f, ".csv") && startswith(f, "column_study"), readdir(results_dir))
    isempty(files) && error("No column_study CSV files found in $results_dir")
    return joinpath(results_dir, sort(files)[end])
end

# ==============================================================================
# Colors
# ==============================================================================

const COLORS = (
    rect      = sp_ceruleanblue,
    circ      = sp_magenta,
    tied      = sp_gold,
    spiral    = sp_irispurple,
    concrete  = sp_charcoalgrey,
    steel     = sp_skyblue,
    fc3       = sp_powderblue,
    fc4       = sp_skyblue,
    fc5       = sp_ceruleanblue,
    fc6       = sp_irispurple,
    fc8       = sp_darkpurple,
)

# ==============================================================================
# Save Helper
# ==============================================================================

function save_fig(path::String, fig::Figure)
    fig.scene.backgroundcolor[] = RGBf(1, 1, 1)
    save(path, fig)
end

# ==============================================================================
# Helper: Add error ribbon/bars to grouped data
# ==============================================================================

"""Compute mean and std for a column grouped by x."""
function stats_by_group(df::DataFrame, xcol::Symbol, ycol::Symbol)
    grouped = combine(groupby(df, xcol),
        ycol => mean => :ymean,
        ycol => std => :ystd,
        ycol => length => :n
    )
    sort!(grouped, xcol)
    # Replace NaN std with 0
    grouped.ystd = coalesce.(grouped.ystd, 0.0)
    replace!(grouped.ystd, NaN => 0.0)
    return grouped
end

# ==============================================================================
# 1a. Capacity vs Carbon (by shape)
# ==============================================================================

function plot_capacity_vs_carbon(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 600))
    ax = Axis(fig[1,1], xlabel="Embodied Carbon (kg CO₂e)", ylabel="φPn,max (kip)",
              title="Capacity vs Carbon — Rectangular (tied), Circular (spiral)")
    
    rect = filter(r -> r.shape == :rect && r.tie_type == :tied, df)
    circ = filter(r -> r.shape == :circular && r.tie_type == :spiral, df)
    
    scatter!(ax, rect.carbon_total_kg, rect.phi_Pn_max_kip,
        color=COLORS.rect, alpha=0.4, markersize=5, strokewidth=0)
    scatter!(ax, circ.carbon_total_kg, circ.phi_Pn_max_kip,
        color=COLORS.circ, alpha=0.4, markersize=5, strokewidth=0)
    
    # Manual legend with solid colors
    leg = Legend(fig[1,2], 
        [MarkerElement(color=COLORS.rect, marker=:circle, markersize=10),
         MarkerElement(color=COLORS.circ, marker=:circle, markersize=10)],
        ["Rectangular (tied)", "Circular (spiral)"])
    leg.tellheight = false
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 1b. Capacity vs Carbon (color by ρ)
# ==============================================================================

function plot_capacity_vs_carbon_by_rho(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(950, 600))
    ax = Axis(fig[1,1], xlabel="Embodied Carbon (kg CO₂e)", ylabel="φPn,max (kip)",
              title="Capacity vs Carbon — colored by ρ")
    
    df_filt = filter(r -> (r.shape == :rect && r.tie_type == :tied) || 
                          (r.shape == :circular && r.tie_type == :spiral), df)
    
    rho_cmap = cgrad([sp_powderblue, sp_ceruleanblue, sp_magenta])
    rho_range = extrema(df_filt.rho_actual .* 100)
    
    scatter!(ax, df_filt.carbon_total_kg, df_filt.phi_Pn_max_kip,
        color=df_filt.rho_actual .* 100, colormap=rho_cmap, colorrange=rho_range,
        markersize=5, strokewidth=0, alpha=0.5)
    
    Colorbar(fig[1,2], colormap=rho_cmap, colorrange=rho_range, label="ρ (%)")
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 2. Heatmap Grid (multiple sizes)
# ==============================================================================

"""Bin rho_actual into target buckets for cleaner heatmaps."""
function bin_rho(rho::Real; targets=[0.01, 0.02, 0.03, 0.04, 0.06])
    _, idx = findmin(abs.(rho .- targets))
    return targets[idx]
end

function plot_heatmap_grid(df::DataFrame; shape::Symbol=:rect, save_path=nothing)
    set_theme!(sp_light)
    
    sizes = shape == :rect ? [16, 20, 24, 30] : [16, 20, 24, 30]
    size_col = shape == :rect ? :b_in : :D_in
    tie_filter = shape == :rect ? :tied : :spiral
    tie_label = shape == :rect ? "tied" : "spiral"
    
    fig = Figure(size=(1200, 900))
    Label(fig[0, :], "φPn,max Heatmap — $(shape == :rect ? "Rectangular" : "Circular") ($tie_label)",
          fontsize=18, tellwidth=false)
    
    for (idx, sz) in enumerate(sizes)
        row, col = divrem(idx-1, 2) .+ 1
        
        filtered = filter(r -> r.shape == shape && r[size_col] == sz && r.tie_type == tie_filter, df)
        isempty(filtered) && continue
        
        # Bin rho values into target buckets for cleaner heatmap
        filtered_copy = copy(filtered)
        filtered_copy.rho_binned = bin_rho.(filtered_copy.rho_actual)
        
        grouped = combine(groupby(filtered_copy, [:fc_ksi, :rho_binned]),
            :phi_Pn_max_kip => mean => :cap)
        
        fc_vals = sort(unique(grouped.fc_ksi))
        rho_vals = sort(unique(grouped.rho_binned))
        
        # Build matrix: mat[fc_idx, rho_idx] = capacity (x, y order for heatmap)
        n_rho, n_fc = length(rho_vals), length(fc_vals)
        mat = zeros(n_fc, n_rho)
        for r in eachrow(grouped)
            rho_idx = findfirst(==(r.rho_binned), rho_vals)
            fc_idx = findfirst(==(r.fc_ksi), fc_vals)
            !isnothing(rho_idx) && !isnothing(fc_idx) && (mat[fc_idx, rho_idx] = r.cap)
        end
        
        ax = Axis(fig[row, col],
            xlabel = "f'c (ksi)", ylabel = "ρ",
            title = "$(sz)\" $(shape == :rect ? "square" : "dia")",
            xticks = (1:n_fc, string.(Int.(fc_vals))),
            yticks = (1:n_rho, ["$(round(r*100,digits=1))%" for r in rho_vals]),
            xgridvisible = false,
            ygridvisible = false)
        
        # heatmap!(mat) puts mat[i,j] at (i,j), so first dim = x, second dim = y
        hm = heatmap!(ax, mat, colormap=blue2gold)
        
        # Tight limits to exactly match data cells
        xlims!(ax, 0.5, n_fc + 0.5)
        ylims!(ax, 0.5, n_rho + 0.5)
        
        if col == 2
            Colorbar(fig[row, 3], hm, label="φPn,max (kip)")
        end
    end
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 4a. Slenderness (color by Ag)
# ==============================================================================

function plot_slenderness_by_Ag(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(950, 600))
    ax = Axis(fig[1,1], xlabel="Slenderness Ratio (kLu/r)", ylabel="Moment Magnification δns",
              title="Slenderness Effect — colored by Gross Area")
    
    kLu_levels = [30, 50, 70]
    cols = [:kLu_r_30_delta_ns, :kLu_r_50_delta_ns, :kLu_r_70_delta_ns]
    
    df_filt = filter(r -> (r.shape == :rect && r.tie_type == :tied) || 
                          (r.shape == :circular && r.tie_type == :spiral), df)
    
    # Collect all points with their Ag
    xs = Float64[]
    ys = Float64[]
    Ags = Float64[]
    
    for row in eachrow(df_filt)
        for (kLu, col) in zip(kLu_levels, cols)
            val = row[col]
            if isfinite(val) && val < 5  # Cap at 5 for visibility
                push!(xs, Float64(kLu) + randn() * 1.5)
                push!(ys, val)
                push!(Ags, row.Ag_in2)
            end
        end
    end
    
    Ag_cmap = cgrad([sp_powderblue, sp_ceruleanblue, sp_irispurple, sp_darkpurple])
    Ag_range = extrema(Ags)
    
    scatter!(ax, xs, ys, color=Ags, colormap=Ag_cmap, colorrange=Ag_range,
        markersize=4, strokewidth=0, alpha=0.5)
    
    Colorbar(fig[1,2], colormap=Ag_cmap, colorrange=Ag_range, label="Ag (in²)")
    
    hlines!(ax, [1.0], color=sp_mediumgray, linestyle=:dash)
    hlines!(ax, [1.4], color=sp_orange, linestyle=:dash)
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 4b. Slenderness (color by safety margin - how close to buckling)
# ==============================================================================

function plot_slenderness_by_safety(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(950, 600))
    ax = Axis(fig[1,1], xlabel="Slenderness Ratio (kLu/r)", ylabel="Moment Magnification δns",
              title="Slenderness Effect — colored by Safety (δns: cyan=safe, oranger=danger)")
    
    kLu_levels = [30, 50, 70]
    cols = [:kLu_r_30_delta_ns, :kLu_r_50_delta_ns, :kLu_r_70_delta_ns]
    
    df_filt = filter(r -> (r.shape == :rect && r.tie_type == :tied) || 
                          (r.shape == :circular && r.tie_type == :spiral), df)
    
    xs = Float64[]
    ys = Float64[]
    
    for row in eachrow(df_filt)
        for (kLu, col) in zip(kLu_levels, cols)
            val = row[col]
            if isfinite(val) && val < 5
                push!(xs, Float64(kLu) + randn() * 1.5)
                push!(ys, val)
            end
        end
    end
    
    # Color by δns value itself (1.0 = safe cyan, 2.0+ = danger orange)
    safety_cmap = cgrad([sp_ceruleanblue, sp_gold, sp_orange])
    safety_range = (1.0, 2.5)
    
    scatter!(ax, xs, ys, color=ys, colormap=safety_cmap, colorrange=safety_range,
        markersize=4, strokewidth=0, alpha=0.5)
    
    Colorbar(fig[1,2], colormap=safety_cmap, colorrange=safety_range, label="δns (magnification)")
    
    hlines!(ax, [1.0], color=sp_mediumgray, linestyle=:dash)
    hlines!(ax, [1.4], color=:black, linestyle=:dash, linewidth=2)
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 5. Capacity vs Area (color by f'c)
# ==============================================================================

function plot_capacity_vs_area(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(1100, 500))
    
    df_filt = filter(r -> (r.shape == :rect && r.aspect_ratio == 1.0 && r.tie_type == :tied) ||
                          (r.shape == :circular && r.tie_type == :spiral), df)
    
    fc_cmap = cgrad([sp_skyblue, sp_ceruleanblue, sp_gold, sp_orange])
    fc_range = extrema(df_filt.fc_ksi)
    
    # Panel 1: vs Ag, colored by f'c
    ax1 = Axis(fig[1,1], xlabel="Gross Area Ag (in²)", ylabel="φPn,max (kip)",
               title="Capacity vs Gross Area — colored by f'c")
    scatter!(ax1, df_filt.Ag_in2, df_filt.phi_Pn_max_kip, 
        color=df_filt.fc_ksi, colormap=fc_cmap, colorrange=fc_range,
        markersize=4, strokewidth=0, alpha=0.5)
    
    # Panel 2: vs As, colored by f'c
    ax2 = Axis(fig[1,2], xlabel="Steel Area As (in²)", ylabel="φPn,max (kip)",
               title="Capacity vs Steel Area — colored by f'c")
    scatter!(ax2, df_filt.As_in2, df_filt.phi_Pn_max_kip, 
        color=df_filt.fc_ksi, colormap=fc_cmap, colorrange=fc_range,
        markersize=4, strokewidth=0, alpha=0.5)
    
    Colorbar(fig[1,3], colormap=fc_cmap, colorrange=fc_range, label="f'c (ksi)")
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 6a. Efficiency vs ρ (by shape)
# ==============================================================================

function plot_efficiency_vs_rho(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 600))
    ax = Axis(fig[1,1], xlabel="Reinforcement Ratio ρ (%)", ylabel="φPn,max / Carbon (kip / kg CO₂e)",
              title="Carbon Efficiency vs ρ — Rectangular (tied), Circular (spiral)")
    
    # All points - filter by appropriate tie type
    df_valid = filter(r -> r.carbon_total_kg > 0, df)
    df_valid.efficiency = df_valid.phi_Pn_max_kip ./ df_valid.carbon_total_kg
    
    rect = filter(r -> r.shape == :rect && r.tie_type == :tied, df_valid)
    circ = filter(r -> r.shape == :circular && r.tie_type == :spiral, df_valid)
    
    scatter!(ax, rect.rho_actual .* 100, rect.efficiency, color=COLORS.rect, alpha=0.3, markersize=4, strokewidth=0)
    scatter!(ax, circ.rho_actual .* 100, circ.efficiency, color=COLORS.circ, alpha=0.3, markersize=4, strokewidth=0)
    
    # Mean + std band for rect
    stats = stats_by_group(rect, :rho_actual, :efficiency)
    stats.x = stats.rho_actual .* 100
    band!(ax, stats.x, stats.ymean .- stats.ystd, stats.ymean .+ stats.ystd, color=(COLORS.rect, 0.2))
    lines!(ax, stats.x, stats.ymean, color=COLORS.rect, linewidth=3)
    
    leg = Legend(fig[1,2],
        [MarkerElement(color=COLORS.rect, marker=:circle, markersize=10),
         MarkerElement(color=COLORS.circ, marker=:circle, markersize=10)],
        ["Rectangular (tied)", "Circular (spiral)"])
    leg.tellheight = false
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 6b. Efficiency vs ρ (color by Ag)
# ==============================================================================

function plot_efficiency_vs_rho_by_Ag(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(950, 600))
    ax = Axis(fig[1,1], xlabel="Reinforcement Ratio ρ (%)", ylabel="φPn,max / Carbon (kip / kg CO₂e)",
              title="Carbon Efficiency vs ρ — colored by Gross Area")
    
    df_valid = filter(r -> r.carbon_total_kg > 0 && 
                          ((r.shape == :rect && r.tie_type == :tied) || 
                           (r.shape == :circular && r.tie_type == :spiral)), df)
    df_valid.efficiency = df_valid.phi_Pn_max_kip ./ df_valid.carbon_total_kg
    
    Ag_cmap = cgrad([sp_powderblue, sp_ceruleanblue, sp_irispurple, sp_darkpurple])
    Ag_range = extrema(df_valid.Ag_in2)
    
    scatter!(ax, df_valid.rho_actual .* 100, df_valid.efficiency, 
        color=df_valid.Ag_in2, colormap=Ag_cmap, colorrange=Ag_range,
        markersize=4, strokewidth=0, alpha=0.5)
    
    Colorbar(fig[1,2], colormap=Ag_cmap, colorrange=Ag_range, label="Ag (in²)")
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 7. Capacity vs ρ by f'c
# ==============================================================================

function plot_capacity_vs_rho_by_fc(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 600))
    ax = Axis(fig[1,1], xlabel="Reinforcement Ratio ρ (%)", ylabel="φPn,max (kip)",
              title="Capacity vs ρ (by Concrete Strength) — 20\" Square (tied)")
    
    # Filter to 20" square, tied only
    df_20 = filter(r -> r.shape == :rect && r.b_in == 20 && r.aspect_ratio == 1.0 && 
                        r.fy_ksi == 60.0 && r.tie_type == :tied, df)
    
    fc_colors = [3.0 => COLORS.fc3, 4.0 => COLORS.fc4, 5.0 => COLORS.fc5, 
                 6.0 => COLORS.fc6, 8.0 => COLORS.fc8]
    
    legend_entries = MarkerElement[]
    legend_labels = String[]
    
    for (fc, color) in fc_colors
        sub = filter(r -> r.fc_ksi == fc, df_20)
        isempty(sub) && continue
        
        scatter!(ax, sub.rho_actual .* 100, sub.phi_Pn_max_kip, 
            color=color, alpha=0.4, markersize=5, strokewidth=0)
        
        stats = stats_by_group(sub, :rho_actual, :phi_Pn_max_kip)
        lines!(ax, stats.rho_actual .* 100, stats.ymean, color=color, linewidth=2)
        
        push!(legend_entries, MarkerElement(color=color, marker=:circle, markersize=10))
        push!(legend_labels, "f'c = $(Int(fc)) ksi")
    end
    
    leg = Legend(fig[1,2], legend_entries, legend_labels)
    leg.tellheight = false
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 8. Capacity vs ρ by Ag
# ==============================================================================

function plot_capacity_vs_rho_by_Ag(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 600))
    ax = Axis(fig[1,1], xlabel="Reinforcement Ratio ρ (%)", ylabel="φPn,max (kip)",
              title="Capacity vs ρ (by Section Size) — Square (tied), f'c=4, fy=60")
    
    df_filt = filter(r -> r.shape == :rect && r.aspect_ratio == 1.0 && 
                          r.fc_ksi == 4.0 && r.fy_ksi == 60.0 && r.tie_type == :tied, df)
    
    sizes = [16, 20, 24, 30]
    legend_entries = MarkerElement[]
    legend_labels = String[]
    
    for (idx, sz) in enumerate(sizes)
        sub = filter(r -> r.b_in == sz, df_filt)
        isempty(sub) && continue
        
        color = harmonic[idx]
        scatter!(ax, sub.rho_actual .* 100, sub.phi_Pn_max_kip,
            color=color, alpha=0.4, markersize=5, strokewidth=0)
        
        stats = stats_by_group(sub, :rho_actual, :phi_Pn_max_kip)
        lines!(ax, stats.rho_actual .* 100, stats.ymean, color=color, linewidth=2)
        
        push!(legend_entries, MarkerElement(color=color, marker=:circle, markersize=10))
        push!(legend_labels, "$(sz)\" × $(sz)\"")
    end
    
    leg = Legend(fig[1,2], legend_entries, legend_labels)
    leg.tellheight = false
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 9. Grade 60 vs 80 - Efficiency Trade-off
# ==============================================================================

function plot_fy_efficiency(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(1000, 500))
    
    df_sq = filter(r -> r.shape == :rect && r.aspect_ratio == 1.0 && r.fc_ksi == 4.0 && r.tie_type == :tied, df)
    
    Ag_cmap = cgrad([sp_powderblue, sp_ceruleanblue, sp_irispurple, sp_darkpurple])
    Ag_range = extrema(df_sq.Ag_in2)
    
    # Panel 1: Grade 60, colored by Ag
    ax1 = Axis(fig[1,1], xlabel="ρ (%)", ylabel="P₀ / Ag (ksi)", title="Grade 60 — colored by Ag")
    sub60 = filter(r -> r.fy_ksi == 60.0, df_sq)
    if !isempty(sub60)
        scatter!(ax1, sub60.rho_actual .* 100, sub60.P0_per_Ag_ksi,
            color=sub60.Ag_in2, colormap=Ag_cmap, colorrange=Ag_range,
            markersize=5, strokewidth=0, alpha=0.5)
    end
    
    # Panel 2: Grade 80, colored by Ag
    ax2 = Axis(fig[1,2], xlabel="ρ (%)", ylabel="P₀ / Ag (ksi)", title="Grade 80 — colored by Ag")
    sub80 = filter(r -> r.fy_ksi == 80.0, df_sq)
    if !isempty(sub80)
        scatter!(ax2, sub80.rho_actual .* 100, sub80.P0_per_Ag_ksi,
            color=sub80.Ag_in2, colormap=Ag_cmap, colorrange=Ag_range,
            markersize=5, strokewidth=0, alpha=0.5)
    end
    
    Colorbar(fig[1,3], colormap=Ag_cmap, colorrange=Ag_range, label="Ag (in²)")
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 9. Tied vs Spiral - Separate plots for rect and circular
# ==============================================================================

function plot_tie_comparison(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(1000, 500))
    
    # Panel 1: Rectangular
    ax1 = Axis(fig[1,1], xlabel="ρ (%)", ylabel="φPn,max (kip)", title="Tied vs Spiral — Rectangular (20\")")
    rect = filter(r -> r.shape == :rect && r.b_in == 20 && r.aspect_ratio == 1.0, df)
    
    for (tie, color, _) in [(:tied, COLORS.tied, "Tied"), (:spiral, COLORS.spiral, "Spiral")]
        sub = filter(r -> r.tie_type == tie, rect)
        isempty(sub) && continue
        scatter!(ax1, sub.rho_actual .* 100, sub.phi_Pn_max_kip, color=color, alpha=0.5, markersize=6, strokewidth=0)
    end
    
    # Panel 2: Circular
    ax2 = Axis(fig[1,2], xlabel="ρ (%)", ylabel="φPn,max (kip)", title="Tied vs Spiral — Circular (20\")")
    circ = filter(r -> r.shape == :circular && r.D_in == 20, df)
    
    for (tie, color, _) in [(:tied, COLORS.tied, "Tied"), (:spiral, COLORS.spiral, "Spiral")]
        sub = filter(r -> r.tie_type == tie, circ)
        isempty(sub) && continue
        scatter!(ax2, sub.rho_actual .* 100, sub.phi_Pn_max_kip, color=color, alpha=0.5, markersize=6, strokewidth=0)
    end
    
    # Shared legend
    leg = Legend(fig[1,3],
        [MarkerElement(color=COLORS.tied, marker=:circle, markersize=10),
         MarkerElement(color=COLORS.spiral, marker=:circle, markersize=10)],
        ["Tied", "Spiral"])
    leg.tellheight = false
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 10. Cover Effect with Error Bars
# ==============================================================================

function plot_cover_effect(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(800, 500))
    ax = Axis(fig[1,1], xlabel="Clear Cover (in)", ylabel="φMn,max (kip-ft)",
              title="Cover Effect on Moment Capacity — 20\" Square (tied)")
    
    df_20 = filter(r -> r.shape == :rect && r.b_in == 20 && r.aspect_ratio == 1.0 && r.tie_type == :tied, df)
    
    for (idx, rho_target) in enumerate([0.02, 0.03, 0.04])
        sub = filter(r -> abs(r.rho_actual - rho_target) < 0.005, df_20)
        isempty(sub) && continue
        
        color = harmonic[idx]
        
        # All points
        scatter!(ax, sub.cover_in, sub.phi_Mn_max_kipft, color=color, alpha=0.4, markersize=5, strokewidth=0)
        
        # Mean + error bars
        stats = stats_by_group(sub, :cover_in, :phi_Mn_max_kipft)
        errorbars!(ax, stats.cover_in, stats.ymean, stats.ystd, color=color, linewidth=2)
        scatter!(ax, stats.cover_in, stats.ymean, color=color, markersize=10, strokewidth=0, label="ρ ≈ $(Int(rho_target*100))%")
    end
    
    axislegend(ax, position=:rt)
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 11. f'c Effect with Error Bars
# ==============================================================================

function plot_fc_effect(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 500))
    ax = Axis(fig[1,1], xlabel="Concrete Strength f'c (ksi)", ylabel="P₀ / Ag (ksi)",
              title="Concrete Strength Effect — 20\" Square (tied), fy=60")
    
    df_20 = filter(r -> r.shape == :rect && r.b_in == 20 && r.aspect_ratio == 1.0 && 
                        r.fy_ksi == 60.0 && r.tie_type == :tied, df)
    
    for (idx, rho_target) in enumerate([0.01, 0.02, 0.03, 0.04])
        sub = filter(r -> abs(r.rho_actual - rho_target) < 0.005, df_20)
        isempty(sub) && continue
        
        color = harmonic[idx]
        
        scatter!(ax, sub.fc_ksi, sub.P0_per_Ag_ksi, color=color, alpha=0.4, markersize=5, strokewidth=0)
        
        stats = stats_by_group(sub, :fc_ksi, :P0_per_Ag_ksi)
        errorbars!(ax, stats.fc_ksi, stats.ymean, stats.ystd, color=color, linewidth=2)
        scatter!(ax, stats.fc_ksi, stats.ymean, color=color, markersize=10, strokewidth=0, label="ρ ≈ $(Int(rho_target*100))%")
    end
    
    axislegend(ax, position=:rb)
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 13. Aspect Ratio Effect (colored by ρ)
# ==============================================================================

function plot_aspect_ratio_effect(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 500))
    ax = Axis(fig[1,1], xlabel="Aspect Ratio (h/b)", ylabel="φMn,max / Ag (kip-ft / in²)",
              title="Moment Efficiency vs Aspect Ratio — b=16\" (tied), colored by ρ")
    
    # Use wider ρ range to get more data points
    df_16 = filter(r -> r.shape == :rect && r.b_in == 16 && 
                        r.fc_ksi == 4.0 && r.tie_type == :tied, df)
    
    rho_cmap = cgrad([sp_powderblue, sp_ceruleanblue, sp_magenta])
    
    if !isempty(df_16)
        df_16.Mn_per_Ag = df_16.phi_Mn_max_kipft ./ df_16.Ag_in2
        rho_range = extrema(df_16.rho_actual .* 100)
        
        scatter!(ax, df_16.aspect_ratio, df_16.Mn_per_Ag, 
            color=df_16.rho_actual .* 100, colormap=rho_cmap, colorrange=rho_range,
            markersize=6, strokewidth=0, alpha=0.5)
        
        Colorbar(fig[1,2], colormap=rho_cmap, colorrange=rho_range, label="ρ (%)")
        
        # Still show mean line
        stats = stats_by_group(df_16, :aspect_ratio, :Mn_per_Ag)
        lines!(ax, stats.aspect_ratio, stats.ymean, color=:black, linewidth=2, linestyle=:dash)
    end
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 13. Carbon Breakdown (grey concrete, light blue steel)
# ==============================================================================

function plot_carbon_breakdown(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 500))
    ax = Axis(fig[1,1], xlabel="Reinforcement Ratio ρ (%)", ylabel="Embodied Carbon (kg CO₂e)",
              title="Carbon Breakdown: Concrete vs Steel — 20\" Square (tied)")
    
    df_20 = filter(r -> r.shape == :rect && r.b_in == 20 && r.aspect_ratio == 1.0 && 
                        r.fc_ksi == 4.0 && r.tie_type == :tied, df)
    
    grouped = combine(groupby(df_20, :rho_actual),
        :carbon_concrete_kg => mean => :concrete,
        :carbon_steel_kg => mean => :steel)
    sort!(grouped, :rho_actual)
    
    if !isempty(grouped)
        rho_pct = grouped.rho_actual .* 100
        barplot!(ax, rho_pct, grouped.concrete, color=COLORS.concrete, label="Concrete", width=0.8)
        barplot!(ax, rho_pct, grouped.steel, color=COLORS.steel, label="Steel", width=0.8,
            offset=grouped.concrete)
        axislegend(ax, position=:lt)
    end
    
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# 14. Carbon Fraction vs ρ (crossover plot)
# ==============================================================================

function plot_carbon_fraction(df::DataFrame; save_path=nothing)
    set_theme!(sp_light)
    fig = Figure(size=(900, 500))
    ax = Axis(fig[1,1], xlabel="Reinforcement Ratio ρ (%)", ylabel="Carbon Fraction (%)",
              title="Concrete vs Steel Carbon Share — 20\" Square (tied)")
    
    df_20 = filter(r -> r.shape == :rect && r.b_in == 20 && r.aspect_ratio == 1.0 && r.tie_type == :tied, df)
    df_20.concrete_frac = df_20.carbon_concrete_kg ./ df_20.carbon_total_kg .* 100
    df_20.steel_frac = df_20.carbon_steel_kg ./ df_20.carbon_total_kg .* 100
    
    scatter!(ax, df_20.rho_actual .* 100, df_20.concrete_frac, color=COLORS.concrete, alpha=0.4, markersize=4, strokewidth=0)
    scatter!(ax, df_20.rho_actual .* 100, df_20.steel_frac, color=COLORS.steel, alpha=0.4, markersize=4, strokewidth=0)
    
    # Mean lines
    stats_c = stats_by_group(df_20, :rho_actual, :concrete_frac)
    stats_s = stats_by_group(df_20, :rho_actual, :steel_frac)
    
    lines!(ax, stats_c.rho_actual .* 100, stats_c.ymean, color=COLORS.concrete, linewidth=3)
    lines!(ax, stats_s.rho_actual .* 100, stats_s.ymean, color=COLORS.steel, linewidth=3)
    
    hlines!(ax, [50], color=sp_mediumgray, linestyle=:dash)
    
    leg = Legend(fig[1,2],
        [MarkerElement(color=COLORS.concrete, marker=:circle, markersize=10),
         MarkerElement(color=COLORS.steel, marker=:circle, markersize=10),
         LineElement(color=sp_mediumgray, linestyle=:dash)],
        ["Concrete", "Steel", "50% crossover"])
    leg.tellheight = false
    !isnothing(save_path) && save_fig(save_path, fig)
    return fig
end

# ==============================================================================
# Generate All
# ==============================================================================

function generate_all_visualizations(df::DataFrame; output_dir::String=FIGS_DIR)
    isdir(output_dir) || mkpath(output_dir)
    p(name) = joinpath(output_dir, "$(name).png")
    
    println("Generating visualizations to: $output_dir\n")
    
    # 01: Capacity vs Carbon (two versions)
    println("  01a: capacity_vs_carbon (by shape)")
    plot_capacity_vs_carbon(df; save_path=p("01a_capacity_vs_carbon"))
    
    println("  01b: capacity_vs_carbon (by rho)")
    plot_capacity_vs_carbon_by_rho(df; save_path=p("01b_capacity_vs_carbon_by_rho"))
    
    # 02-03: Heatmaps
    println("  02: heatmap_rect_grid")
    plot_heatmap_grid(df; shape=:rect, save_path=p("02_heatmap_rect_grid"))
    
    println("  03: heatmap_circ_grid")
    plot_heatmap_grid(df; shape=:circular, save_path=p("03_heatmap_circ_grid"))
    
    # 04: Slenderness (two versions)
    println("  04a: slenderness (by Ag)")
    plot_slenderness_by_Ag(df; save_path=p("04a_slenderness_by_Ag"))
    
    println("  04b: slenderness (by safety)")
    plot_slenderness_by_safety(df; save_path=p("04b_slenderness_by_safety"))
    
    # 05: Capacity vs Area
    println("  05: capacity_vs_area (by fc)")
    plot_capacity_vs_area(df; save_path=p("05_capacity_vs_area"))
    
    # 06: Efficiency vs rho (two versions)
    println("  06a: efficiency_vs_rho (by shape)")
    plot_efficiency_vs_rho(df; save_path=p("06a_efficiency_vs_rho"))
    
    println("  06b: efficiency_vs_rho (by Ag)")
    plot_efficiency_vs_rho_by_Ag(df; save_path=p("06b_efficiency_vs_rho_by_Ag"))
    
    # 07-08: Capacity vs rho
    println("  07: capacity_vs_rho_by_fc")
    plot_capacity_vs_rho_by_fc(df; save_path=p("07_capacity_vs_rho_by_fc"))
    
    println("  08: capacity_vs_rho_by_Ag")
    plot_capacity_vs_rho_by_Ag(df; save_path=p("08_capacity_vs_rho_by_Ag"))
    
    # 09: fy efficiency (now colored by Ag)
    println("  09: fy_efficiency (by Ag)")
    plot_fy_efficiency(df; save_path=p("09_fy_vs_efficiency"))
    
    # 10: Tie comparison
    println("  10: tie_comparison")
    plot_tie_comparison(df; save_path=p("10_tied_vs_spiral"))
    
    # 11-12: Cover and f'c effects
    println("  11: cover_vs_moment")
    plot_cover_effect(df; save_path=p("11_cover_vs_moment"))
    
    println("  12: fc_vs_efficiency")
    plot_fc_effect(df; save_path=p("12_fc_vs_efficiency"))
    
    # 13: Aspect ratio (now colored by Ag)
    println("  13: aspect_vs_moment (by Ag)")
    plot_aspect_ratio_effect(df; save_path=p("13_aspect_vs_moment"))
    
    # 14-15: Carbon
    println("  14: carbon_breakdown")
    plot_carbon_breakdown(df; save_path=p("14_carbon_vs_rho"))
    
    println("  15: carbon_fraction")
    plot_carbon_fraction(df; save_path=p("15_carbon_fraction_vs_rho"))
    
    println("\n✓ All 18 figures saved to: $output_dir")
end

# ==============================================================================
println("Visualization loaded. Usage:")
println("  df = load_study_results(latest_results(RESULTS_DIR))")
println("  generate_all_visualizations(df)")
