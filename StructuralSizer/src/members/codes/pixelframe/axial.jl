# ==============================================================================
# PixelFrame Axial Capacity
# ==============================================================================
# Axial capacity of PixelFrame sections per ACI 318-19 §22.4.
# Reference: Wongsittikan (2024), Eqs. 2.1–2.2.
#
# Since there is no non-prestressed longitudinal reinforcement, duct, or
# sheathing, the general equation simplifies to:
#
#   P_o = 0.85 fc′ (A_g − A_s) − (f_pe − 0.003 E_s) A_s   (Eq. 2.1)
#   P_n = 0.80 × P_o                                        (Table 22.4.2.1)
#   P_u = ϕ × P_n                                           (Eq. 2.2)
#
# where ϕ = 0.65 for compression-controlled prestressed members
# (ACI 318-19 Table 21.2.1) and the 0.80 factor is the ACI maximum
# nominal strength limit for members with ties (Table 22.4.2.1).
# ==============================================================================

using Unitful

"""
    pf_axial_capacity(s::PixelFrameSection; E_s, ϕ_compression) -> (Po, Pn, Pu)

Nominal and design axial capacity of a PixelFrame section.

# Arguments
- `s`: PixelFrameSection (provides A_g, A_s, f_pe, and material fc′)
- `E_s`: Tendon elastic modulus (default 200 GPa per typical strand)
- `ϕ_compression`: Strength reduction factor (default 0.65, ACI 318-19 Table 21.2.1)

# Returns
Named tuple `(Po, Pn, Pu)` where:
- `Po`: Nominal axial strength from Eq. 22.4.2.3a
- `Pn`: Maximum nominal strength = 0.80 × Po (Table 22.4.2.1)
- `Pu`: Design axial capacity = ϕ × Pn

# Reference
ACI 318-19 §22.4.2.3 (Eq. 22.4.2.3a simplified for no bonded reinforcement)
ACI 318-19 Table 22.4.2.1 (0.80 factor for tied members)
ACI 318-19 Table 21.2.1 (ϕ = 0.65 for compression-controlled prestressed)
Wongsittikan (2024) Eq. 2.1–2.2
"""
function pf_axial_capacity(s::PixelFrameSection;
                           E_s::Pressure = 200.0u"GPa",
                           ϕ_compression::Real = 0.65)
    fc′ = s.material.fc′
    A_g = section_area(s)
    A_s = s.A_s
    f_pe = s.f_pe

    # ACI 318-19 §22.4.2.3 (simplified — no bonded reinforcement)
    Po = 0.85 * fc′ * (A_g - A_s) - (f_pe - 0.003 * E_s) * A_s

    # ACI 318-19 Table 22.4.2.1 — maximum nominal strength for tied members
    Pn = 0.80 * Po

    # Design capacity
    Pu = ϕ_compression * Pn

    return (; Po, Pn, Pu)
end
