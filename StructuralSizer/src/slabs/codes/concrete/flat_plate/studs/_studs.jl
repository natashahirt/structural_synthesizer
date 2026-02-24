# Barrel file for punching shear reinforcement design
include("stud_catalog.jl")       # Headed stud catalogs (StudSpec, INCON, Ancon)
include("shear_caps.jl")         # Shear cap design (ACI §13.2.6)
include("column_capitals.jl")    # Column capital design (ACI §13.1.2)
include("closed_stirrups.jl")    # Closed stirrup design (ACI §11.11.3)
