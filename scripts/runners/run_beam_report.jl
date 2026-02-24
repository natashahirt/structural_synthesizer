# Run the beam sizing validation report
# Usage: julia --project=StructuralSynthesizer scripts/runners/run_beam_report.jl

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer"))

include(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer", "test", "report_generators", "test_beam_sizing_report.jl"))
