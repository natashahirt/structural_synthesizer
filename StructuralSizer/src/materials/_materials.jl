# Import units for material display functions
using StructuralBase.StructuralUnits: ksi
using Unitful: psi

# Material type definitions first
include("types.jl")

# Preset instances
include("steel.jl")
include("concrete.jl")
include("timber.jl")
