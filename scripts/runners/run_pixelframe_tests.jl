# Runner script for PixelFrame tests
# Usage: julia --project=StructuralSizer scripts/runners/run_pixelframe_tests.jl

using Test
using Unitful
using StructuralSizer
using Asap

@testset "PixelFrame" begin
    include(joinpath(@__DIR__, "..", "..", "StructuralSizer", "test", "pixelframe", "test_pixelframe_capacities.jl"))
    include(joinpath(@__DIR__, "..", "..", "StructuralSizer", "test", "pixelframe", "test_pixelframe_checker.jl"))
end
