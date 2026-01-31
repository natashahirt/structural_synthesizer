# Main test runner for StructuralSizer
# Run with: julia --project=. test/runtests.jl

using Test
using Unitful
using StructuralSizer
using StructuralBase: StructuralUnits  # For u"ksi", u"kip" etc. in tests
using StructuralSynthesizer

@testset "StructuralSynthesizer Tests" begin
    include("test_core_structs.jl")
    include("test_design_architecture.jl")
    include("test_member_hierarchy.jl")
    include("test_meshing.jl")
    include("test_voronoi_vis.jl")
end