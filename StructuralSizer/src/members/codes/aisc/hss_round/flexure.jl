# ==============================================================================
# AISC 360-16 - Flexure for Round HSS / Pipe (Section F8)
# ==============================================================================

function get_Mn(s::HSSRoundSection, mat::Metal; Lb=zero(s.OD), Cb=1.0, axis=:strong)
    E, Fy = mat.E, mat.Fy
    Mp = Fy * s.Z
    My = Fy * s.S

    sl = get_slenderness(s, mat)
    if sl.class == :compact
        return Mp
    elseif sl.class == :noncompact
        Mn = _linear_interp(sl.λ, sl.λp, sl.λr, Mp, My)
        return min(Mn, Mp)
    else
        # Slender: Mn = Fcr*S (F8-3). Conservative local-buckling stress model:
        Fcr = min(0.33 * E / sl.λ, Fy)
        return Fcr * s.S
    end
end

get_ϕMn(s::HSSRoundSection, mat::Metal; Lb=zero(s.OD), Cb=1.0, axis=:strong, ϕ=0.9) =
    ϕ * get_Mn(s, mat; Lb=Lb, Cb=Cb, axis=axis)

