# AISC 360 Chapter D - Design of Members for Tension

"""Nominal tensile strength (D2). Considers Yielding and Rupture."""
function get_Pn_tension(s::ISymmSection, mat::Metal; Ae_ratio=0.75)
    # D2-1: Tensile Yielding
    # Pn = Fy * Ag
    Pn_yield = mat.Fy * s.A

    # D2-2: Tensile Rupture
    # Pn = Fu * Ae
    # Ae = An * U
    # Without connection details, we assume an effective net area ratio.
    # U typically 0.8-0.9 for W-shapes. An depends on bolt holes.
    # 0.75 is a conservative placeholder for Ae/Ag.
    # Note: Optimization of members usually controlled by gross yielding.
    # Connection design handles rupture locally.
    Pn_rupture = mat.Fu * (s.A * Ae_ratio)

    return min(Pn_yield, Pn_rupture)
end

"""Design tensile strength (LRFD)."""
function get_ϕPn_tension(s::ISymmSection, mat::Metal; Ae_ratio=0.75)
    # ϕ = 0.90 for yielding
    ϕ_yield = 0.90
    ϕPn_yield = ϕ_yield * (mat.Fy * s.A)

    # ϕ = 0.75 for rupture
    ϕ_rupture = 0.75
    ϕPn_rupture = ϕ_rupture * (mat.Fu * (s.A * Ae_ratio))

    return min(ϕPn_yield, ϕPn_rupture)
end
