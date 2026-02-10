include(joinpath(@__DIR__, "StructuralStudies", "src", "init.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "flat_plate_method_comparison.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "vis.jl"))

println("\n" * "=" ^ 60)
println("  Running shear stud comparison: never / if_needed / always")
println("  Floor types: Flat Plate + Flat Slab  (FEA only)")
println("=" ^ 60 * "\n")

df = dual_stud_sweep()

# Save combined
outpath = output_filename("stud_comparison",
    joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "results"))
CSV.write(outpath, df)

n_fp = count(r -> r.floor_type == "flat_plate", eachrow(df))
n_fs = count(r -> r.floor_type == "flat_slab",  eachrow(df))
println("\nStud sweep complete: $(nrow(df)) rows total")
println("  Flat Plate: $n_fp rows")
println("  Flat Slab:  $n_fs rows")
println("  Saved: $outpath")

# Generate stud comparison plots
plot_stud_comparison(df)
