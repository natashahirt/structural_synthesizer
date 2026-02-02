# ==============================================================================
# ACI 318 Concrete Design
# ==============================================================================
# ACI 318-19 Building Code Requirements for Structural Concrete

# Material utilities must come first (defines beta1, Ec, extractors used by all)
include("aci_material_utils.jl")

# P-M interaction (defines PMInteractionDiagram used by checker)
include("column_pm_rect.jl")
include("column_pm_circular.jl")  # Circular column P-M calculations
include("slenderness.jl")
include("biaxial.jl")

# Checker depends on column_pm, slenderness, biaxial
include("checker.jl")

# Future:
# include("flexure.jl")      # Chapter 22: Sectional Strength (beams)
# include("shear.jl")        # Chapter 22: Shear Strength
# include("development.jl")  # Chapter 25: Development Length
# include("serviceability.jl") # Chapter 24: Deflection, Cracking
