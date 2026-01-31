# ==============================================================================
# Optimization Module
# ==============================================================================
# NOTE: Include order is controlled by _members.jl due to cross-dependencies
# with sections/ and codes/. This file documents the module structure.
#
# Structure:
#   core/       - Abstract types, geometry, demands, objectives
#   solvers/    - Generic optimization algorithms (MIP, NLP)
#   types/      - Member-type specific APIs (columns, beams)
#   options.jl  - Configuration types for each member type
#
# Include order (in _members.jl):
#   1. core/_core.jl    - AbstractCapacityChecker, geometry, demands, objectives
#   2. (sections and codes loaded)
#   3. solvers/_solvers.jl  - optimize_discrete()
#   4. options.jl           - SteelColumnOptions, ConcreteColumnOptions, etc.
#   5. types/_types.jl      - size_columns(), size_beams()
