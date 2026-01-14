module StructuralBase

using Unitful
using Reexport

# Constants submodule (loads, material densities, unit standards)
include("Constants.jl")
@reexport using .Constants

# Abstract types for inheritance
include("types.jl")

# Exports
export AbstractMaterial, AbstractDesignCode, AbstractSection
export AbstractStructuralSynthesizer, AbstractBuildingSkeleton, AbstractBuildingStructure
export Constants  # Allow qualified access: Constants.LL_FLOOR, Constants.GRAVITY, etc.

end # module StructuralBase