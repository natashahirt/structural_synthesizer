# ==============================================================================
# Optimization Module
# ==============================================================================
# Demand types, objective functions, and selection algorithms for
# structural member sizing optimization.

include("demands.jl")
include("objectives.jl")

# Discrete selection (MIP)
include("discrete_mip.jl")

# Future:
# include("continuous.jl")   # Continuous optimization (NLP)
