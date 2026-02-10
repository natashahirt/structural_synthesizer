include(joinpath(@__DIR__, "StructuralStudies", "src", "init.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "flat_plate_method_comparison.jl"))
include(joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "vis.jl"))

results_dir = joinpath(@__DIR__, "StructuralStudies", "src", "flat_plate_methods", "results")

# ══════════════════════════════════════════════════════════════
# 1. Dual sweep (square bays, Flat Plate + Flat Slab)
# ══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 60)
println("  1/3  Running dual sweep: Flat Plate + Flat Slab")
println("=" ^ 60 * "\n")

df_sweep = dual_sweep()

sweep_path = output_filename("dual_sweep", results_dir)
CSV.write(sweep_path, df_sweep)

n_fp = count(r -> r.floor_type == "flat_plate", eachrow(df_sweep))
n_fs = count(r -> r.floor_type == "flat_slab",  eachrow(df_sweep))
println("\nDual sweep complete: $(nrow(df_sweep)) rows  (FP=$n_fp, FS=$n_fs)")
println("  Saved: $sweep_path")

# Generate side-by-side line plots
generate_all(df_sweep)

# ══════════════════════════════════════════════════════════════
# 2. Dual heatmap sweep (Lx × Ly grid, Flat Plate + Flat Slab)
# ══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 60)
println("  2/3  Running dual heatmap sweep: Flat Plate + Flat Slab")
println("=" ^ 60 * "\n")

df_heat = dual_heatmap_sweep()

heat_path = output_filename("dual_heatmap", results_dir)
CSV.write(heat_path, df_heat)
println("\nHeatmap sweep complete: $(nrow(df_heat)) rows")
println("  Saved: $heat_path")

# Generate heatmap images (09/10)
plot_dual_heatmaps(df_heat)

# ══════════════════════════════════════════════════════════════
# 3. Shear stud comparison (FEA only, three stud strategies)
# ══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 60)
println("  3/3  Running stud comparison: never / if_needed / always")
println("=" ^ 60 * "\n")

df_stud = dual_stud_sweep()

stud_path = output_filename("stud_comparison", results_dir)
CSV.write(stud_path, df_stud)

n_fp_s = count(r -> r.floor_type == "flat_plate", eachrow(df_stud))
n_fs_s = count(r -> r.floor_type == "flat_slab",  eachrow(df_stud))
println("\nStud sweep complete: $(nrow(df_stud)) rows  (FP=$n_fp_s, FS=$n_fs_s)")
println("  Saved: $stud_path")

# Generate stud comparison plots (11)
plot_stud_comparison(df_stud)

# ══════════════════════════════════════════════════════════════
println("\n" * "=" ^ 60)
println("  All studies complete!")
println("=" ^ 60)
