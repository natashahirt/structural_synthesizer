# AISC 360 Chapter E - Design of Members for Compression

"""
    get_Fe_flexural(s::ISymmSection, mat::Metal, L; axis=:weak) -> Pressure

Elastic flexural buckling stress per AISC 360-16 Eq. E3-4: Fe = π²E / (KL/r)².

# Arguments
- `L`: Effective length KL
- `axis`: `:strong` or `:weak` (determines radius of gyration used)
"""
function get_Fe_flexural(s::ISymmSection, mat::Metal, L; axis=:weak)
    E = mat.E
    r = axis == :weak ? s.ry : s.rx
    KL_r = L / r
    return π^2 * E / KL_r^2
end

"""
    get_Fe_torsional(s::ISymmSection, mat::Metal, Lz) -> Pressure

Elastic torsional buckling stress for doubly symmetric I-shapes per AISC 360-16 Eq. E4-4.

# Arguments
- `Lz`: Effective length for torsional buckling
"""
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

"""
    calculate_Fcr(Fe, Fy, Q) -> Pressure

Critical buckling stress Fcr per AISC 360-16 Eqs. E7-2/E7-3.
Accounts for slender element reduction factor `Q = Qs × Qa`.
Falls back to E3-2/E3-3 when Q = 1.0 (no slender elements).
"""
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

"""
    get_Pn(s::ISymmSection, mat::Metal, L; axis=:weak) -> Force

Nominal compressive strength per AISC 360-16 Chapters E3/E4/E7.
Considers flexural buckling (strong/weak axis) or torsional buckling,
with slender element reduction via Q factors.

# Arguments
- `L`: Effective length KL
- `axis`: `:strong`, `:weak`, or `:torsional`
"""
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

"""
    get_ϕPn(s::ISymmSection, mat::Metal, L; axis=:weak, ϕ=0.90) -> Force

Design compressive strength ϕPn per AISC 360-16 (LRFD). `ϕ_c = 0.90` per Section E1.
"""
get_ϕPn(s::ISymmSection, mat::Metal, L; axis=:weak, ϕ=0.90) = ϕ * get_Pn(s, mat, L; axis=axis)
