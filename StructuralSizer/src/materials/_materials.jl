# Import units for material display functions
using Asap: ksi
using Unitful: psi

# Material type definitions first
include("types.jl")

# Preset instances
include("steel.jl")
include("concrete.jl")
include("timber.jl")
