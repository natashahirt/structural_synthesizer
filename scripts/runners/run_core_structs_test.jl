# Run only test/core/test_core_structs.jl (BuildingSkeleton, face lookup).
# Usage: from repo root: julia --project=StructuralSynthesizer scripts/runners/run_core_structs_test.jl

ENV["SS_ENABLE_VISUALIZATION"] = "false"
using Pkg
Pkg.activate("StructuralSynthesizer")

# Run from StructuralSynthesizer so include path is correct
root = dirname(dirname(@__DIR__))
synth = joinpath(root, "StructuralSynthesizer")
test_file = joinpath(synth, "test", "core", "test_core_structs.jl")
include(test_file)
