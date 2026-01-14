# Plot vault stress curves - Julia equivalent of BasePlotsWithLim.m
#
# Run with: julia --project=. test/plot_vault_curves.jl
#
# Requires GLMakie: ] add GLMakie

using StructuralSizer
using GLMakie

# =============================================================================
# Parameters (matching BasePlotsWithLim.m exactly)
# =============================================================================

span_range = 2.0:0.1:10.5
base_lambdas = 5:1:30           # All ratios
highlight_lambdas = 5:5:30      # Ratios to label
MOE_values = [500, 1000, 2000, 4000, 8000]  # MPa

# Fixed parameters (matching MATLAB)
trib_depth = 1.0        # [m]
thickness = 0.05        # 5 cm (Brick_Thick)
rib_depth = 0.10        # 10 cm (Wall_Thick)
rib_apex_rise = 0.05    # 5 cm (Apex_Rise)
density = 2000.0        # [kg/m³]
applied_load = 7.0      # [kN/m²] (= 7000 N/m² in MATLAB)
finishing_load = 1.0    # [kN/m²] (= 1000 N/m² in MATLAB)

# =============================================================================
# Part 1: Generate Base Stress-Span Curves
# =============================================================================

println("Generating base stress curves...")

fig = Figure(size=(1100, 800))

# Primary axis (left)
ax = Axis(fig[1, 1],
    xlabel="Span (m)",
    ylabel="Stress (MPa)",
    title="Vault Stress vs. Span with Deflection-Based Failure Limits",
    limits=(2, 10.5, 0, 9),
    xticks=2:1:10,
    yticks=0:1:9,
    xminorticks=IntervalsBetween(2),
    yminorticks=IntervalsBetween(2),
    xminorgridvisible=true,
    yminorgridvisible=true
)

# Secondary axis (right) - for span/rise ratio labels
ax_right = Axis(fig[1, 1],
    ylabel="Span/Rise Ratio",
    yaxisposition=:right,
    limits=(2, 10.5, 0, 9),
    yticks=(
        [vault_stress_symmetric(10.5, 10.5/λ, trib_depth, thickness, rib_depth, rib_apex_rise, density, applied_load, finishing_load).σ_MPa for λ in highlight_lambdas],
        ["Span/$λ" for λ in highlight_lambdas]
    ),
    xticksvisible=false,
    xticklabelsvisible=false,
    xlabelvisible=false,
    xgridvisible=false,
    ygridvisible=false
)

hidespines!(ax_right)
hidexdecorations!(ax_right)

# Store curve data for labeling
curve_endpoints = Dict{Int, Tuple{Float64, Float64}}()

for λ in base_lambdas
    spans_vec = Float64[]
    stress_vec = Float64[]
    
    for span in span_range
        rise = span / λ
        result = vault_stress_symmetric(
            span, rise, trib_depth, thickness,
            rib_depth, rib_apex_rise, density,
            applied_load, finishing_load
        )
        push!(spans_vec, span)
        push!(stress_vec, result.σ_MPa)
    end
    
    curve_endpoints[λ] = (spans_vec[end], stress_vec[end])
    
    if λ in highlight_lambdas
        lines!(ax, spans_vec, stress_vec, linewidth=2.0, color=(:gray50, 1.0))
    else
        lines!(ax, spans_vec, stress_vec, linewidth=1.0, color=(:gray75, 0.8))
    end
end

# =============================================================================
# Part 2: Generate Deflection Limit Curves (matching BasePlotsWithLim.m)
# =============================================================================

println("Calculating deflection limit curves...")

colors = [:red, :orange, :gold, :green, :blue]

for (i, E_MPa) in enumerate(MOE_values)
    println("  MOE = $E_MPa MPa...")
    
    limit_spans_raw = Float64[]
    limit_stresses_raw = Float64[]
    
    # MATLAB uses fine lambda resolution: min:0.05:max
    fine_lambdas = minimum(highlight_lambdas):0.05:maximum(highlight_lambdas)
    
    for λ in fine_lambdas
        last_good_span = NaN
        
        for span in span_range
            rise = span / λ
            deflection_limit = span / 240
            
            # Get self-weight from symmetric analysis
            sym = vault_stress_symmetric(
                span, rise, trib_depth, thickness,
                rib_depth, rib_apex_rise, density,
                applied_load, finishing_load
            )
            
            # MATLAB: total_load_Pa = AppliedLoad + (weight_at_test * 1000)
            # Note: MATLAB does NOT include FinishLoad in the solver call
            total_load_Pa = applied_load * 1000 + sym.self_weight_kN_m² * 1000
            
            # Check elastic shortening with deflection limit
            eq = solve_equilibrium_rise(
                span, rise, total_load_Pa, thickness, trib_depth, Float64(E_MPa);
                deflection_limit=deflection_limit
            )
            
            if eq.converged && eq.deflection_ok
                last_good_span = span
            else
                break
            end
        end
        
        if !isnan(last_good_span)
            rise = last_good_span / λ
            result = vault_stress_symmetric(
                last_good_span, rise, trib_depth, thickness,
                rib_depth, rib_apex_rise, density,
                applied_load, finishing_load
            )
            push!(limit_spans_raw, last_good_span)
            push!(limit_stresses_raw, result.σ_MPa)
        end
    end
    
    if length(limit_spans_raw) > 1
        # --- Data Cleaning (matching MATLAB) ---
        
        # 1. Sort by span
        perm = sortperm(limit_spans_raw)
        sorted_spans = limit_spans_raw[perm]
        sorted_stresses = limit_stresses_raw[perm]
        
        # 2. Get unique spans and take MAX stress for each (envelope)
        unique_spans = unique(sorted_spans)
        unique_stresses = Float64[]
        
        for s in unique_spans
            mask = sorted_spans .== s
            push!(unique_stresses, maximum(sorted_stresses[mask]))
        end
        
        # Plot the envelope curve
        lines!(ax, unique_spans, unique_stresses,
            linewidth=2.5, color=colors[i])
        
        # Label at end of curve
        text!(ax, unique_spans[end] + 0.1, unique_stresses[end],
            text="E=$E_MPa", fontsize=9, color=colors[i], align=(:left, :center))
    end
end

# =============================================================================
# Save and Display
# =============================================================================

output_path = joinpath(@__DIR__, "vault_stress_curves.png")
save(output_path, fig, px_per_unit=2)
println("\nPlot saved to: $output_path")

display(fig)

println("\nPress Enter to close...")
readline()
