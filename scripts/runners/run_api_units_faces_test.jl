# Run only test/core/test_api_units_faces.jl.
# Usage: from repo root: julia --project=StructuralSynthesizer scripts/runners/run_api_units_faces_test.jl

ENV["SS_ENABLE_VISUALIZATION"] = "false"
using Pkg
Pkg.activate("StructuralSynthesizer")

root = dirname(dirname(@__DIR__))
synth = joinpath(root, "StructuralSynthesizer")
test_file = joinpath(synth, "test", "core", "test_api_units_faces.jl")
include(test_file)
