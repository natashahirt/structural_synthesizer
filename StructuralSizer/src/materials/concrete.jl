# ==============================================================================
# Concrete Material Presets
# ==============================================================================
# ECC values from ICE Database v4.1 (Oct 2025) [kgCO₂e/kg]
# Source: data/ICE DB Educational V4.1 - Oct 2025.xlsx
#
# ICE Concrete ECC (per kg):
#   OPC (300 kg cement/m³): 0.138
#   50% GGBS replacement:   0.099
#   30% PFA replacement:    0.112
#   40/50 MPa (UK avg):     0.173

# ==============================================================================
# Standard OPC Concrete (by compressive strength in psi)
# ==============================================================================

# 3000 psi (~20 MPa) - lower strength for non-critical applications
const NWC_3000 = Concrete(
    26.0u"GPa",         # E (57000√3000 psi ≈ 26 GPa)
    20.7u"MPa",         # fc′ (3000 psi ≈ 21 MPa)
    2380.0u"kg/m^3",    # ρ
    0.20,               # ν
    0.130               # ecc - slightly lower cement content
)

# 4000 psi (~28 MPa) - standard for columns and beams
const NWC_4000 = Concrete(
    29.0u"GPa",         # E (57000√4000 psi ≈ 29 GPa)
    27.6u"MPa",         # fc′ (4000 psi ≈ 28 MPa)
    2380.0u"kg/m^3",    # ρ  (from ICE)
    0.20,               # ν
    0.138               # ecc [kgCO₂e/kg] - ICE: OPC 300kg cement/m³
)

# 5000 psi (~35 MPa) - higher strength for columns
const NWC_5000 = Concrete(
    32.0u"GPa",         # E (57000√5000 psi ≈ 32 GPa)
    34.5u"MPa",         # fc′ (5000 psi ≈ 34.5 MPa)
    2385.0u"kg/m^3",    # ρ
    0.20,               # ν
    0.155               # ecc - moderate
)

# 6000 psi (~41 MPa) - high strength for columns
const NWC_6000 = Concrete(
    35.0u"GPa",         # E (57000√6000 psi ≈ 35 GPa)
    41.4u"MPa",         # fc′ (6000 psi ≈ 41 MPa)
    2385.0u"kg/m^3",    # ρ  (from ICE)
    0.20,               # ν
    0.173               # ecc [kgCO₂e/kg] - ICE: 40/50 MPa
)

# Low-carbon: 50% GGBS cement replacement
const NWC_GGBS = Concrete(
    29.0u"GPa",         # E
    27.6u"MPa",         # fc′ (~28 MPa typical)
    2380.0u"kg/m^3",    # ρ
    0.20,               # ν
    0.099               # ecc [kgCO₂e/kg] - ICE: 50% GGBS
)

# Low-carbon: 30% PFA cement replacement
const NWC_PFA = Concrete(
    29.0u"GPa",         # E
    27.6u"MPa",         # fc′ (~28 MPa typical)
    2380.0u"kg/m^3",    # ρ
    0.20,               # ν
    0.112               # ecc [kgCO₂e/kg] - ICE: 30% PFA
)

# ==============================================================================
# Display Names
# ==============================================================================

"""Get short display name for a concrete material."""
function material_name(mat::Concrete)
    mat === NWC_3000 && return "NWC_3000"
    mat === NWC_4000 && return "NWC_4000"
    mat === NWC_5000 && return "NWC_5000"
    mat === NWC_6000 && return "NWC_6000"
    mat === NWC_GGBS && return "NWC_GGBS"
    mat === NWC_PFA && return "NWC_PFA"
    # Fallback: show fc' in psi
    fc_psi = round(ustrip(psi, mat.fc′), digits=0)
    return "Concrete ($(Int(fc_psi)) psi)"
end
