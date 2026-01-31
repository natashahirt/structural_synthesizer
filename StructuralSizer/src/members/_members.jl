# Member sizing: materials, sections, codes, optimization

# Core optimization abstractions (must come first - used by codes and sections)
include("optimize/core/_core.jl")

# Sections (geometry + catalogs)
include("sections/_sections.jl")

# Design code checks (checkers use AbstractCapacityChecker from core)
include("codes/_codes.jl")

# Optimization solvers (use checkers from codes)
include("optimize/solvers/_solvers.jl")

# Sizing options (must come before types which use them)
include("optimize/options.jl")

# Member-type specific APIs
include("optimize/types/_types.jl")
