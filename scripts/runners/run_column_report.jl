# Run the column sizing validation report
# Usage: julia --project=StructuralSynthesizer scripts/runners/run_column_report.jl

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer"))

include(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer", "test", "report_generators", "test_column_sizing_report.jl"))
