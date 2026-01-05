module StructuralSynthesizer

import GLMakie
import Meshes
import Graphs
import Asap
using Unitful

include("./core/_core.jl")
include("./generate/_generate.jl")
include("./visualization/_visualization.jl")

export gen_medium_office
export BuildingSkeleton, BuildingStructure
export visualize
export add_vertex!, add_element!, find_faces!, rebuild_stories!

end # module StructuralSynthesizer