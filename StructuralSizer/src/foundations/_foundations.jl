# Foundation sizing: types, soils, options, design codes

# Types (foundation hierarchy, soil, results, demands)
include("types.jl")

# Design options (must come after types, before codes)
include("options.jl")

# Design code implementations
include("codes/_codes.jl")
