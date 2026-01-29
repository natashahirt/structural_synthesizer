# ==============================================================================
# AISC 360-16 - Shear for Round HSS / Pipe (Section G5)
# ==============================================================================

"""
Nominal shear strength for round HSS per AISC 360-16 Section G5.

Vn = Fcr * Ag / 2 (G5-1), where Fcr is the larger of the shear buckling stresses
(G5-2a, G5-2b) but shall not exceed 0.6Fy.

Note: The buckling stresses depend on `Lv` (distance from max to zero shear). The
generic capacity interface does not currently pass member geometry, so we conservatively
use shear yielding (Fcr = 0.6Fy). This matches the spec user note for standard sections.
"""
function get_Vn(s::HSSRoundSection, mat::Metal; axis=:strong, kv=5.0, rolled=false)
    Fy = mat.Fy
    Fcr = 0.6 * Fy
    return Fcr * s.A / 2
end

"""Design shear strength (LRFD)."""
get_ϕVn(s::HSSRoundSection, mat::Metal; axis=:strong, kv=5.0, rolled=false, ϕ=nothing) =
    (isnothing(ϕ) ? 0.9 : ϕ) * get_Vn(s, mat; axis=axis, kv=kv, rolled=rolled)

