include(joinpath(@__DIR__, "StructuralStudies", "src", "init.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "flat_plate_method_comparison.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "vis.jl"))

println("\n" * "=" ^ 60)
println("  Running dual heatmap sweep: Flat Plate + Flat Slab")
println("=" ^ 60 * "\n")

df = dual_heatmap_sweep()

# Save combined
outpath = output_filename("dual_heatmap",
    joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "results"))
CSV.write(outpath, df)
println("\nSaved: $outpath")

# Generate heatmap images
plot_dual_heatmaps(df)
