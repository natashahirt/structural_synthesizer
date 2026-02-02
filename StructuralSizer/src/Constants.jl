# =============================================================================
# StructuralSizer Constants
# =============================================================================
# Structural engineering constants for design and analysis.

module Constants

using Unitful

# =============================================================================
# Embodied Carbon Coefficients (kgCO2e/kg)
# =============================================================================

const ECC_STEEL = 1.22
const ECC_CONCRETE = 0.152
const ECC_REBAR = 0.854

export ECC_STEEL, ECC_CONCRETE, ECC_REBAR

# =============================================================================
# Solver/Optimization Constants
# =============================================================================

const BIG_M = 1e9

export BIG_M

# =============================================================================
# Load Factors (ASCE 7 Strength)
# =============================================================================
# Note: For more flexible load combinations, see StructuralSynthesizer.LoadCombination

const DL_FACTOR = 1.2
const LL_FACTOR = 1.6

export DL_FACTOR, LL_FACTOR

# =============================================================================
# Standard Building Loads
# =============================================================================
# Conversion: 1 psf = 0.04788025898 kN/m²

const _PSF_TO_KNM2 = 0.04788025898

const LL_GRADE  = (100.0 * _PSF_TO_KNM2)u"kN/m^2"  # 100 psf
const LL_FLOOR  = (80.0  * _PSF_TO_KNM2)u"kN/m^2"  #  80 psf
const LL_ROOF   = (20.0  * _PSF_TO_KNM2)u"kN/m^2"  #  20 psf
const SDL_FLOOR = (15.0  * _PSF_TO_KNM2)u"kN/m^2"  #  15 psf
const SDL_ROOF  = (15.0  * _PSF_TO_KNM2)u"kN/m^2"  #  15 psf
const SDL_WALL  = (10.0  * _PSF_TO_KNM2)u"kN/m^2"  #  10 psf

export LL_GRADE, LL_FLOOR, LL_ROOF, SDL_FLOOR, SDL_ROOF, SDL_WALL

# =============================================================================
# Standard Units (for consistent internal representation)
# =============================================================================

const STANDARD_LENGTH = u"m"
const STANDARD_AREA = u"m^2"
const STANDARD_FORCE = u"kN"
const STANDARD_PRESSURE = u"kN/m^2"

export STANDARD_LENGTH, STANDARD_AREA, STANDARD_FORCE, STANDARD_PRESSURE

end # module
