# Runner: flat plate method comparison with snapshot/restore
include(joinpath(@__DIR__, "src", "flat_plate_methods", "flat_plate_method_comparison.jl"))

println("\n\n=== Running sweep with snapshot/restore ===\n")
t0 = time()
df = sweep()
elapsed = time() - t0
println("\nTotal wall-clock time: $(round(elapsed; digits=1))s")
println("Rows: $(nrow(df))")
println("\nFirst few rows:")
show(first(df, 10); allcols=true)
println()
