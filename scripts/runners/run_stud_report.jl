# ==============================================================================
# Runner: Punching Shear Strategy & Reinforcement Report
# ==============================================================================
# Runs tests and generates .txt report to:
#   StructuralSynthesizer/test/reports/stud_catalog_report.txt
#
# Compares 6 reinforcement types × 3 strategies across multiple spans:
#   Studs (Generic, INCON, Ancon), Closed Stirrups, Shear Caps, Col. Capitals
#
# Usage:
#   julia --project scripts/runners/run_stud_report.jl
# ==============================================================================

include(joinpath(@__DIR__, "..", "..", "StructuralSynthesizer", "test", "report_generators", "stud_catalog_comparison.jl"))

stud_catalog_report()
