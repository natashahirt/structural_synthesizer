__precompile__()  # allow package precompilation
module StructuralSynthesizer

using Logging
using StructuralBase
using StructuralSizer

# Extend StructuralSizer's floor-result interface functions for local wrapper types
# (e.g. `Slab`). In Julia, adding methods requires `import`, not `using`.
import StructuralSizer: self_weight, total_depth, structural_effects

import GLMakie
import Meshes
import Graphs
import Asap
import LinearAlgebra: norm, normalize
using Unitful

include("types.jl")
include("./core/_core.jl")
include("./external/_external.jl")
using .AsapToolkit
include("./generate/_generate.jl")
include("./visualization/_visualization.jl")
include("./analyze/_analyze.jl")

# Geometry generation
export gen_medium_office

# Core types
export BuildingSkeleton, BuildingStructure, Story
export Cell, Slab, SlabGroup, total_dead_load
export Segment, Member, MemberGroup

# Functions
export visualize
export visualize_slabs, print_slab_summary
export add_vertex!, add_element!, find_faces!, rebuild_stories!, to_asap!
export initialize!
export initialize_cells!, initialize_slabs!
export initialize_segments!, initialize_members!, update_bracing!

# Internal toolkit
export AsapToolkit

end # module StructuralSynthesizer
