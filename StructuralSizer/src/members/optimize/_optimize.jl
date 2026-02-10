# ==============================================================================
# Member-Specific Optimization
# ==============================================================================
# Depends on: sections/, codes/ (must be included after them)
# Uses: optimize/core/ and optimize/solvers/ (loaded earlier)

# Catalog builders (depend on sections)
include("catalogs.jl")

# Smooth P-M interaction (analytical Whitney stress block for RC NLP)
include("smooth_pm.jl")

# NLP problem definitions (for continuous optimization)
include("problems.jl")
include("problems_circular.jl")
include("problems_beam.jl")
include("problems_tbeam.jl")

# High-level API (depends on catalogs, checkers, solvers, problems)
include("api.jl")
