# AISC 360 Chapter E - Design of Members for Compression

"""Elastic flexural buckling stress (E3-4)."""
function get_Fe_flexural(s::ISymmSection, mat::Metal, L; axis=:weak)
    E = mat.E
    r = axis == :weak ? s.ry : s.rx
    KL_r = L / r
    return π^2 * E / KL_r^2
end

"""Elastic torsional buckling stress (E4-4)."""
function get_Fe_torsional(s::ISymmSection, mat::Metal, Lz)
    E, G = mat.E, mat.G
    Cw, J = s.Cw, s.J
    Ix, Iy = s.Ix, s.Iy
    
    # E4-4
    # Fe = (π^2 * E * Cw / Lz^2 + G * J) * (1 / (Ix + Iy))
    term1 = π^2 * E * Cw / Lz^2
    term2 = G * J
    return (term1 + term2) / (Ix + Iy)
end

"""Calculate Fcr from Fe and Q (E3-2, E3-3, E7)."""
function calculate_Fcr(Fe, Fy, Q)
    # E3-2 applies if Fy/Fe <= 2.25. E3-3 applies if Fy/Fe > 2.25.
    # With Q: E7-2 applies if Q*Fy/Fe <= 2.25
    
    ratio = Q * Fy / Fe
    
    if ratio <= 2.25
        # E7-2
        val = 0.658^ratio
        return Q * val * Fy
    else
        # E7-3
        return 0.877 * Fe
    end
end

"""Nominal compressive strength (E3/E4/E7)."""
function get_Pn(s::ISymmSection, mat::Metal, L; axis=:weak)
    # 1. Slenderness reduction Q
    q_factors = get_compression_factors(s, mat)
    Q = q_factors.Q
    Fy = mat.Fy

    # 2. Elastic Buckling Stress Fe
    if axis == :torsional
        Fe = get_Fe_torsional(s, mat, L) # L here is Lz
    else
        Fe = get_Fe_flexural(s, mat, L; axis=axis)
    end
    
    # 3. Critical Stress Fcr
    Fcr = calculate_Fcr(Fe, Fy, Q)
    
    return Fcr * s.A
end

"""Design compressive strength (LRFD)."""
get_ϕPn(s::ISymmSection, mat::Metal, L; axis=:weak, ϕ=0.90) = ϕ * get_Pn(s, mat, L; axis=axis)
