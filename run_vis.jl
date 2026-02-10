# Generate plots from the latest dual sweep results (no re-running the sweep)
include(joinpath(@__DIR__, "StructuralStudies", "src", "init.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "flat_plate_method_comparison.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "vis.jl"))

# Find the latest dual_sweep CSV
results_dir = joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "results")
csvs = filter(f -> startswith(f, "dual_sweep") && endswith(f, ".csv"), readdir(results_dir))
isempty(csvs) && error("No dual_sweep CSVs found in $results_dir")
latest = joinpath(results_dir, sort(csvs)[end])

df = load_results(latest)
generate_all(df)
