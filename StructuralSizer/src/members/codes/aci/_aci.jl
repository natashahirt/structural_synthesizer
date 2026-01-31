# ==============================================================================
# ACI 318 Concrete Design
# ==============================================================================
# ACI 318-19 Building Code Requirements for Structural Concrete

# P-M interaction must come first (defines PMInteractionDiagram used by checker)
include("column_pm_rect.jl")
include("column_pm_circular.jl")  # Circular column P-M calculations
include("slenderness.jl")
include("biaxial.jl")
# Checker depends on column_pm, slenderness, biaxial
include("checker.jl")

# Future:
# include("flexure.jl")      # Chapter 22: Sectional Strength (beams)
# include("shear.jl")        # Chapter 22: Shear Strength
# include("slenderness.jl")  # Chapter 6: Slenderness Effects
# include("development.jl")  # Chapter 25: Development Length
# include("serviceability.jl") # Chapter 24: Deflection, Cracking
