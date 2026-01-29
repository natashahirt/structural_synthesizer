# ==============================================================================
# AISC 360-16 - Flexure for Rectangular/Square HSS (Section F7)
# ==============================================================================

"""
Approximate effective-width reduction for slender rectangular HSS walls in flexure.

Computes an effective section modulus `Se` by scaling the elastic section modulus
by an effective width ratio. Conservative and avoids rebuilding section geometry.
"""
function _Se_rect_hss(s::HSSRectSection, mat::Metal; axis::Symbol)
    E, Fy = mat.E, mat.Fy
    bcomp = axis === :weak ? s.h : s.b
    λ = ustrip(bcomp / s.t)

    rt = sqrt(E / Fy)
    be = 1.92 * s.t * rt * (1 - 0.34 * rt / λ)
    be = clamp(be, zero(be), bcomp)

    S = axis === :weak ? s.Sy : s.Sx
    return S * ustrip(be / bcomp)
end

function get_Mn(s::HSSRectSection, mat::Metal; Lb=zero(s.H), Cb=1.0, axis=:strong)
    Fy = mat.Fy
    Z = axis === :weak ? s.Zy : s.Zx
    S = axis === :weak ? s.Sy : s.Sx
    Mp = Fy * Z
    My = Fy * S

    sl = get_slenderness(s, mat)
    class_f = sl.class_f
    class_w = sl.class_w

    # Compact: Mn = Mp (F7-1)
    if class_f == :compact && class_w == :compact
        return Mp
    end

    # Slender: Mn = Fy*Se (F7-3 style; Se is computed approximately)
    if class_f == :slender || class_w == :slender
        Se = _Se_rect_hss(s, mat; axis=axis)
        return Fy * Se
    end

    # Noncompact: interpolate between Mp and My (F7-2 style)
    if class_f == :noncompact
        Mn = _linear_interp(sl.λ_f, sl.λp_f, sl.λr_f, Mp, My)
        return min(Mn, Mp)
    else
        Mn = _linear_interp(sl.λ_w, sl.λp_w, sl.λr_w, Mp, My)
        return min(Mn, Mp)
    end
end

get_ϕMn(s::HSSRectSection, mat::Metal; Lb=zero(s.H), Cb=1.0, axis=:strong, ϕ=0.9) =
    ϕ * get_Mn(s, mat; Lb=Lb, Cb=Cb, axis=axis)

