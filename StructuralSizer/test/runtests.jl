# Main test runner for StructuralSizer
# Run with: julia --project=. test/runtests.jl

using Test
using StructuralSizer

@testset "StructuralSizer Tests" begin
    include("cip/test_cip.jl")
    include("haile_vault/test_vault.jl")
end
