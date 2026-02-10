# Runner: heatmap sweep (Lx × Ly × LL × method) + depth heatmap plot
# Limited to 16–40 ft since flat plates beyond ~42 ft exceed RC column capacity
include(joinpath(@__DIR__, "src", "flat_plate_methods", "flat_plate_method_comparison.jl"))
include(joinpath(@__DIR__, "src", "flat_plate_methods", "vis.jl"))

println("\n=== Running heatmap sweep (16–40 ft, adaptive FEA) ===\n")
t0 = time()
df = heatmap_sweep(
    spans_x = collect(16.0:4.0:40.0),   # [16, 20, 24, 28, 32, 36, 40]
    spans_y = collect(16.0:4.0:40.0),
)
elapsed = time() - t0
println("\nHeatmap sweep wall-clock time: $(round(elapsed; digits=1))s")
println("Rows: $(nrow(df))")

println("\n=== Generating depth heatmap ===\n")
plot_depth_heatmap(df)
println("\nDone!")
