module Constants
    using Unitful

    # Note: GRAVITY is now in StructuralUnits (StructuralBase.StructuralUnits.GRAVITY)

    # Embodied Carbon Coefficients (kgCO2e/kg)
    const ECC_STEEL = 1.22
    const ECC_CONCRETE = 0.152
    const ECC_REBAR = 0.854

    # Solver/Optimization Constants
    const BIG_M = 1e9

    # Load Factors (ASCE 7 Strength)
    const DL_FACTOR = 1.2
    const LL_FACTOR = 1.6

    # Standard Building Loads in kN/m² (converted from psf at compile time)
    # Conversion: 1 psf = 0.04788025898 kN/m²
    const _PSF_TO_KNM2 = 0.04788025898
    const LL_GRADE  = (100.0 * _PSF_TO_KNM2)u"kN/m^2"  # 100 psf
    const LL_FLOOR  = (80.0  * _PSF_TO_KNM2)u"kN/m^2"  #  80 psf
    const LL_ROOF   = (20.0  * _PSF_TO_KNM2)u"kN/m^2"  #  20 psf
    const SDL_FLOOR = (15.0  * _PSF_TO_KNM2)u"kN/m^2"  #  15 psf
    const SDL_ROOF  = (15.0  * _PSF_TO_KNM2)u"kN/m^2"  #  15 psf
    const SDL_WALL  = (10.0  * _PSF_TO_KNM2)u"kN/m^2"  #  10 psf

    # Standard Units
    const STANDARD_LENGTH = u"m"
    const STANDARD_AREA = u"m^2"
    const STANDARD_FORCE = u"kN"
    const STANDARD_PRESSURE = u"kN/m^2"
end
