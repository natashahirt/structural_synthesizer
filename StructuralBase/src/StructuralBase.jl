module StructuralBase

using Unitful
using Reexport

# Units submodule (kip, ksi, psf, GRAVITY)
# Keeps the StructuralUnits name for Unitful.register() compatibility
include("Units.jl")
@reexport using .StructuralUnits

# Constants submodule (loads, material densities, unit standards)
include("Constants.jl")
@reexport using .Constants

# Abstract types for inheritance
include("types.jl")

# Exports
export AbstractMaterial, AbstractDesignCode, AbstractSection
export AbstractStructuralSynthesizer, AbstractBuildingSkeleton, AbstractBuildingStructure
export Constants, StructuralUnits  # Allow qualified access

end # module StructuralBase
