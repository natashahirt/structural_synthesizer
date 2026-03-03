using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSizer"))
Pkg.test(; test_args=["slabs/test_flat_plate_methods.jl"])
