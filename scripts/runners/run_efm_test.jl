#!/usr/bin/env julia
# Runner: execute EFM pipeline test
using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSizer"))
include(joinpath(@__DIR__, "..", "..", "StructuralSizer", "test", "slabs", "test_efm_pipeline.jl"))
