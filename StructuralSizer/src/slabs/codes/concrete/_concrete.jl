# Concrete floor systems
# CIP, precast, and special concrete slabs

# Calculations and analysis (loads before sizing)
include("flat_plate/_flat_plate.jl")

# CIP sizing for all cast-in-place types (FlatPlate, FlatSlab, TwoWay, OneWay, Waffle, PTBanded)
include("sizing.jl")

# Precast (separate sizing)
include("hollow_core.jl")