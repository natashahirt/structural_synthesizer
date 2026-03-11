# Optimization solvers
include("discrete_mip.jl")    # MIP for discrete catalog selection
include("continuous_nlp.jl")  # NLP for continuous optimization
include("binary_search.jl")   # Binary search for lightest feasible section
