# AISC 360 Chapter E - Design of Members for Compression

"""Elastic buckling stress (E3-4)."""
function get_Fe(s::ISymmSection, mat::Metal, L; axis=:weak)
    E = mat.E
    r = axis == :weak ? s.ry : s.rx
    KL_r = L / r
    return π^2 * E / KL_r^2
end

"""Critical stress for flexural buckling (E3-2, E3-3)."""
function get_Fcr_flexural(s::ISymmSection, mat::Metal, L; axis=:weak)
    E, Fy = mat.E, mat.Fy
    r = axis == :weak ? s.ry : s.rx
    
    KL_r_val = ustrip(L / r)
    if KL_r_val <= 1e-6 || isnan(KL_r_val) || isinf(KL_r_val)
        return Fy
    end
    
    KL_r = L / r
    Fe = π^2 * E / KL_r^2
    limit = 4.71 * sqrt(E / Fy)
    
    if KL_r <= limit
        Fe_val = ustrip(Fe)
        Fcr = (Fe_val > 0 && !isinf(Fe_val)) ? (0.658^(Fy / Fe)) * Fy : Fy
    else
        Fcr = 0.877 * Fe
    end
    return Fcr
end

"""Nominal compressive strength (E3-1)."""
function get_Pn(s::ISymmSection, mat::Metal, L; axis=:weak)
    Fcr = get_Fcr_flexural(s, mat, L; axis=axis)
    return Fcr * s.A
end

"""Design compressive strength (LRFD)."""
get_ϕPn(s::ISymmSection, mat::Metal, L; axis=:weak, ϕ=0.90) = ϕ * get_Pn(s, mat, L; axis=axis)
