# ==============================================================================
# Optimization Module
# ==============================================================================
# Demand types, objective functions, and selection algorithms for
# structural member sizing optimization.

include("demands.jl")
include("objectives.jl")

# Future:
# include("selectors.jl")    # Discrete selection algorithms
# include("continuous.jl")   # Continuous optimization (NLP)
# include("integer.jl")      # Integer programming (MIP)
