# Focused test runner for circular column support in slabs
# Run: julia --project=. _test_circular_slabs.jl

println("Loading packages...")
t0 = time()
using StructuralSizer
using StructuralSynthesizer
using Asap
using Unitful
using Unitful: @u_str
using Test
using Printf
using Meshes
t1 = time()
println("Loaded in $(round(t1-t0, digits=1))s\n")

# ═══════════════════════════════════════════════════════════════════════════════
# 1. Core slab calculations with circular columns (StructuralSizer)
# ═══════════════════════════════════════════════════════════════════════════════

println("═"^60)
println("  1. Core slab calculations — circular columns")
println("═"^60)

t2 = time()
include("StructuralSizer/test/slabs/test_flat_plate.jl")
println("  ✓ test_flat_plate.jl ($(round(time()-t2, digits=1))s)")

t2 = time()
include("StructuralSizer/test/slabs/test_shear_transfer.jl")
println("  ✓ test_shear_transfer.jl ($(round(time()-t2, digits=1))s)")

t2 = time()
include("StructuralSizer/test/slabs/test_efm_pipeline.jl")
println("  ✓ test_efm_pipeline.jl ($(round(time()-t2, digits=1))s)")

t2 = time()
include("StructuralSizer/test/slabs/test_size_flat_plate.jl")
println("  ✓ test_size_flat_plate.jl ($(round(time()-t2, digits=1))s)")

# ═══════════════════════════════════════════════════════════════════════════════
# 2. FEA with circular columns (needs StructuralSynthesizer for gen_medium_office)
# ═══════════════════════════════════════════════════════════════════════════════

println("\n", "═"^60)
println("  2. FEA — circular column octagonal mesh patch")
println("═"^60)

t2 = time()
include("StructuralSizer/test/test_fea_flat_plate.jl")
println("  ✓ test_fea_flat_plate.jl ($(round(time()-t2, digits=1))s)")

println("\n", "═"^60)
println("  All circular column slab tests complete! ($(round(time()-t0, digits=1))s total)")
println("═"^60)
