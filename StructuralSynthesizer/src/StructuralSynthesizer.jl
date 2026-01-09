module StructuralSynthesizer

import GLMakie
import Meshes
import Graphs
import Asap
using Unitful

include("./core/_core.jl")
include("./external/_external.jl")
include("./generate/_generate.jl")
include("./visualization/_visualization.jl")
include("./analyze/_analyze.jl")

using .AsapToolkit 

# Package Initialization
function __init__()
    # registers custom structural units (psf, kip, lbf) defined in Constants
    # so they are available via u"..." throughout the package and for users.
    Unitful.register(Constants)
end

export gen_medium_office
export BuildingSkeleton, BuildingStructure
export visualize
export add_vertex!, add_element!, find_faces!, rebuild_stories!, initialize_slabs!, to_asap

export AsapToolkit

end # module StructuralSynthesizer