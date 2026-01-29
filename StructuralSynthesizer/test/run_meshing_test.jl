using Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()

include(joinpath(@__DIR__, "test_meshing.jl"))
