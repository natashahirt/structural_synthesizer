# Run steel tests only
using Test
using Unitful
using StructuralSizer
# Units are re-exported from StructuralSizer (via Asap)

@testset "Steel Member Tests" begin
    include("steel_member/test_hss_sections.jl")
    include("steel_member/test_aisc_companion_manual_1.jl")
    include("steel_member/test_aisc_360_reference.jl")
end
