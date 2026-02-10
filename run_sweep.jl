include(joinpath(@__DIR__, "StructuralStudies", "src", "init.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "flat_plate_method_comparison.jl"))

# Run sweep for both flat plate and flat slab (same spans/loads/methods)
println("\n" * "=" ^ 60)
println("  Running dual sweep: Flat Plate + Flat Slab")
println("=" ^ 60 * "\n")

df = dual_sweep()

# Save combined results
outpath = output_filename("dual_sweep",
    joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "results"))
CSV.write(outpath, df)

n_fp = count(r -> r.floor_type == "flat_plate", eachrow(df))
n_fs = count(r -> r.floor_type == "flat_slab",  eachrow(df))
println("\nDual sweep complete: $(nrow(df)) rows total")
println("  Flat Plate: $n_fp rows")
println("  Flat Slab:  $n_fs rows")
println("  Saved: $outpath")

# Generate plots
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "vis.jl"))
generate_all(df)
