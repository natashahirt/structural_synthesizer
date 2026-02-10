# Runner: generate all flat plate comparison visualizations
include(joinpath(@__DIR__, "src", "flat_plate_methods", "vis.jl"))

df = load_results()
generate_all(df)
println("\nAll plots saved to: $(FP_FIGS_DIR)")
