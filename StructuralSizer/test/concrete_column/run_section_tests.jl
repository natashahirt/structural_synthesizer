# Run RC Column tests (section + P-M interaction + slenderness + biaxial)
cd(@__DIR__)

using Pkg
Pkg.activate(joinpath(@__DIR__, "..", ".."))

using Test
using Unitful
using StructuralSizer

# Load verified StructurePoint test data
include("test_data/tied_column_16x16.jl")

# Include and run tests
include("test_rc_column_section.jl")
include("test_column_pm.jl")
include("test_slenderness.jl")
include("test_biaxial.jl")
