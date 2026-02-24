# =============================================================================
# Runner: Shear stud catalog and design tests
# =============================================================================
# Usage (from repo root):
#   julia scripts/runners/run_stud_tests.jl           # all stud tests
#   julia scripts/runners/run_stud_tests.jl catalog    # catalog only
#   julia scripts/runners/run_stud_tests.jl design     # design only
# =============================================================================

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))

using Test, Unitful
using StructuralSizer

# ─── Parse CLI filter ────────────────────────────────────────────────────────
filter = length(ARGS) >= 1 ? ARGS[1] : "all"
test_root = joinpath(@__DIR__, "..", "..", "StructuralSizer", "test", "slabs")

println("═"^60)
println("  Shear Stud Tests")
println("  Filter: $(filter)")
println("═"^60)

@testset "Shear Studs" begin
    if filter in ("all", "catalog")
        @testset "Stud Catalog" begin
            include(joinpath(test_root, "test_stud_catalog.jl"))
        end
    end
    if filter in ("all", "design")
        @testset "Stud Design" begin
            include(joinpath(test_root, "test_shear_studs.jl"))
        end
    end
end
