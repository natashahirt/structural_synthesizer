# Main test runner for StructuralSizer
# Run with: julia --project=. test/runtests.jl

using Test
using StructuralSizer
using StructuralUnits  # For u"ksi", u"kip" etc. in tests

@testset "StructuralSizer Tests" begin
    include("cip/test_cip.jl")
    include("haile_vault/test_vault.jl")
    include("steel_member/test_aisc_beam_examples.jl")
    include("steel_member/test_handcalc_beam.jl")
    include("steel_member/test_aisc_column_examplesjl")
end
