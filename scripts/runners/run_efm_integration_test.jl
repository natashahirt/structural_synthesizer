#!/usr/bin/env julia
# Runner: execute EFM integration report test
using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer"))
include(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer", "test", "report_generators", "test_flat_plate_efm_integration.jl"))
