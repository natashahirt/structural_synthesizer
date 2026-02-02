# Slab types (dispatch targets)
include("types.jl")

# User-facing sizing options + guidance
include("options.jl")

# Sizing codes
include("codes/_codes.jl")

# ACI strip geometry utilities (column/middle strip split)
# Generic tributary computation is now in Asap
include("utils/_utils.jl")