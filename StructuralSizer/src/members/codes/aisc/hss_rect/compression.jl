# ==============================================================================
# AISC 360-16 - Compression for Rectangular/Square HSS
# ==============================================================================
# Implements global buckling per E3 using Euler stress + column curve.
# Adds a conservative local-buckling area reduction for slender walls (Table B4.1a)
# until full E7 effective-width iteration is implemented.

"""
Conservative effective area reduction for rectangular HSS with slender walls.

If walls are slender per Table B4.1a, reduce area linearly by λr/λmax.
This is a placeholder for full E7 effective-width calculations.
"""
function _Ae_rect_hss(s::HSSRectSection, mat::Metal)
    lim = get_compression_limits(s, mat)
    λmax = max(lim.λ_f, lim.λ_w)
    if λmax <= lim.λr
        return s.A
    end
    return s.A * (lim.λr / λmax)
end

function get_Pn(s::HSSRectSection, mat::Metal, L; axis=:weak)
    E, Fy = mat.E, mat.Fy
    r = axis === :weak ? s.ry : s.rx
    Fe = _Fe_euler(E, L, r)
    Fcr = _Fcr_column(Fe, Fy)
    Ae = _Ae_rect_hss(s, mat)
    return Fcr * Ae
end

function get_ϕPn(s::HSSRectSection, mat::Metal, L; axis=:weak, ϕ=0.9)
    axis_eff = axis === :torsional ? :weak : axis
    return ϕ * get_Pn(s, mat, L; axis=axis_eff)
end

