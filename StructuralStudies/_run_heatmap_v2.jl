# Runner: heatmap sweep (Lx × Ly × LL × method) + depth heatmap plot
include(joinpath(@__DIR__, "src", "flat_plate_methods", "flat_plate_method_comparison.jl"))
include(joinpath(@__DIR__, "src", "flat_plate_methods", "vis.jl"))

println("\n=== Running heatmap sweep with snapshot/restore ===\n")
t0 = time()
df = heatmap_sweep()
elapsed = time() - t0
println("\nHeatmap sweep wall-clock time: $(round(elapsed; digits=1))s")
println("Rows: $(nrow(df))")

println("\n=== Generating depth heatmap ===\n")
plot_depth_heatmap(df)
println("\nDone!")
