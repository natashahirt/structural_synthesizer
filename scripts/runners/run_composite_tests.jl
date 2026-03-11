using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSizer"))
include(joinpath(@__DIR__, "..", "..", "StructuralSizer", "test", "steel_member", "composite", "test_composite_beam.jl"))
