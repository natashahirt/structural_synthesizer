using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))

using Test

@testset "Punching Shear Reinforcement" begin
    include(joinpath(@__DIR__, "..", "..", "StructuralSizer", "test", "slabs", "test_punching_reinforcement.jl"))
end
