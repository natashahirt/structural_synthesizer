# ==============================================================================
# PixelFrame Embodied Carbon
# ==============================================================================
# Embodied carbon calculation for PixelFrame sections.
# Reference: Wongsittikan (2024), Eqs. 2.16–2.17.
#
#   carbon = ec · A_c + fiber_ecc · ρ_steel · (dosage · A_c + A_s)  [kgCO₂e/m]
#
# where:
#   ec = 4.57 fc′ + 217  [kgCO₂e/m³]  (linear fit from ASME data, Eq. 2.17)
#   fiber_ecc = 1.4 kgCO₂e/kg          (original Pixelframe.jl, steel fiber + tendon)
#   ρ_steel = 7860 kg/m³               (steel density)
#
# This overrides the standard MinCarbon objective (A × L × ρ × ecc) because
# PixelFrame sections include steel tendon and fiber contributions that the
# generic formula does not capture.
# ==============================================================================

using Unitful

# Steel density for tendon + fiber carbon calculation
const _STEEL_DENSITY_KGM3 = 7860.0  # kg/m³

"""
    pf_concrete_ecc(fc′) -> Float64

Embodied carbon coefficient of concrete as a function of fc′.
Linear fit from ASME data (Wongsittikan 2024, Eq. 2.17).

    ec = 4.57 × fc′ [MPa] + 217  [kgCO₂e/m³]

# Arguments
- `fc′`: Concrete compressive strength (Unitful Pressure)

# Returns
Embodied carbon in kgCO₂e per m³ of concrete.
"""
function pf_concrete_ecc(fc′::Pressure)
    fc′_MPa = ustrip(u"MPa", fc′)
    return 4.57 * fc′_MPa + 217.0
end

"""
    pf_carbon_per_meter(s::PixelFrameSection) -> Float64

Embodied carbon per unit length of a PixelFrame section [kgCO₂e/m].

Accounts for three contributions:
1. Concrete: ec(fc′) × A_c
2. Steel fiber: fiber_ecc × ρ_steel × dosage × A_c
3. Tendon steel: fiber_ecc × ρ_steel × A_s

Reference: Wongsittikan (2024) Eq. 2.16

# Returns
Carbon intensity in kgCO₂e/m (bare Float64).
"""
function pf_carbon_per_meter(s::PixelFrameSection)
    A_c_m2 = ustrip(u"m^2", section_area(s))
    A_s_m2 = ustrip(u"m^2", s.A_s)
    fc′ = s.material.fc′
    dosage = s.material.fiber_dosage  # kg-fiber / m³ concrete
    fiber_ecc = s.material.fiber_ecc  # kgCO₂e / kg-steel

    # Concrete carbon [kgCO₂e/m]
    ec = pf_concrete_ecc(fc′)  # kgCO₂e/m³
    carbon_concrete = ec * A_c_m2

    # Steel (fiber + tendon) carbon [kgCO₂e/m]
    # Fiber: dosage [kg/m³] × A_c [m²] → kg-fiber/m
    # Tendon: ρ_steel [kg/m³] × A_s [m²] → kg-tendon/m
    carbon_steel = fiber_ecc * (dosage * A_c_m2 + _STEEL_DENSITY_KGM3 * A_s_m2)

    return carbon_concrete + carbon_steel
end

# ==============================================================================
# MinCarbon objective override for PixelFrameSection
# ==============================================================================

"""
    objective_value(::MinCarbon, s::PixelFrameSection, ::AbstractMaterial, L) -> Float64

PixelFrame-specific embodied carbon objective.

Overrides the generic `A × L × ρ × ecc` formula to include concrete, fiber,
and tendon contributions per Wongsittikan (2024) Eq. 2.16.

Returns total carbon in kgCO₂e (bare Float64, no units) for use in MIP.
"""
function objective_value(::MinCarbon, s::PixelFrameSection, ::AbstractMaterial, L)
    L_m = L isa Unitful.Quantity ? ustrip(u"m", L) : Float64(L)
    pf_carbon_per_meter(s) * L_m
end
