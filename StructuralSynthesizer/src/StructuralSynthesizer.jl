module StructuralSynthesizer

using Logging
using StructuralBase
using StructuralSizer

import GLMakie
import Meshes
import Graphs
import Asap
using Unitful

include("types.jl")
include("./core/_core.jl")
include("./external/_external.jl")
include("./generate/_generate.jl")
include("./visualization/_visualization.jl")
include("./analyze/_analyze.jl")

using .AsapToolkit

# Geometry generation
export gen_medium_office

# Core types
export BuildingSkeleton, BuildingStructure, Story
export Cell, Slab, SlabGroup, total_dead_load
export Segment, Member, MemberGroup

# Functions
export visualize
export add_vertex!, add_element!, find_faces!, rebuild_stories!, to_asap!
export initialize!
export initialize_cells!, initialize_slabs!
export initialize_segments!, initialize_members!, update_bracing!

# Internal toolkit
export AsapToolkit

end # module StructuralSynthesizer