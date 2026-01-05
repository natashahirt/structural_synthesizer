# introduce some useful, standard US units
Unitful.@unit lbf "lbf" PoundForce 4.4482216152605u"N" false
Unitful.@unit kip "kip" Kip 1000u"lbf" false
Unitful.@unit psf "psf" PoundPerSquareFoot 47.88025898u"N/m^2" false
Unitful.register(@__MODULE__)

# Physical Constants
const GRAVITY = 9.80665u"m/s^2" # acceleration due to gravity

# Material Densities (kg/m³)
const ρ_CONCRETE = 2400.0u"kg/m^3"
const ρ_STEEL = 7850.0u"kg/m^3"
const ρ_REBAR = 7850.0u"kg/m^3"

# conversion example: ρ_CONCRETE_KIPIN3 = uconvert(u"kip/inch^3", ρ_CONCRETE * GRAVITY)
# make sure to multiply by gravity since kg is a mass and kip or N are just units of force

# Embodied Carbon Coefficients (assumed dimensionless: tCO2e/t for steel, tCO2e/m³ for concrete, etc.)
const ECC_STEEL = 1.22
const ECC_CONCRETE = 0.152 # from CLF
const ECC_REBAR = 0.854

# Big M
const BIG_M = 1e9