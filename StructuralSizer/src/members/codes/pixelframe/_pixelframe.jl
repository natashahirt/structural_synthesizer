# PixelFrame capacity functions (ACI 318-19 axial + flexure, embodied carbon)
include("axial.jl")
include("flexure.jl")
include("carbon.jl")
include("deflection.jl")
include("checker.jl")

# Per-pixel design + TendonDeviationResult type (depends on checker + carbon)
include("pixel_design.jl")

# Tendon deviation computation (depends on pixel_design + flexure)
include("tendon_deviation.jl")

# Catalog generation (depends on capacity functions above)
include("../../sections/concrete/catalogs/pixelframe_catalog.jl")
