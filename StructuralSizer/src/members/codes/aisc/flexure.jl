# AISC 360 Chapter F - Design of Members for Flexure

"""Limiting unbraced lengths for LTB (F2-5, F2-6). Returns (Lp, Lr, c)."""
function get_Lp_Lr(s::ISymmSection, mat::Metal)
    E, Fy = mat.E, mat.Fy
    ry, J, Sx, ho, rts = s.ry, s.J, s.Sx, s.ho, s.rts
    c = 1.0  # doubly symmetric I-shape
    
    # Eq F2-5: Limiting length for yielding
    Lp = 1.76 * ry * sqrt(E / Fy)
    jc_term = (J * c) / (Sx * ho)
    Lr = 1.95 * rts * (E / (0.7 * Fy)) * sqrt(jc_term + sqrt(jc_term^2 + 6.76 * (0.7 * Fy / E)^2))
    
    return (Lp=Lp, Lr=Lr, c=c)
end

"""Critical stress for elastic LTB (F2-4)."""
function get_Fcr_LTB(s::ISymmSection, mat::Metal, Lb; Cb=1.0)
    E = mat.E
    J, Sx, ho, rts = s.J, s.Sx, s.ho, s.rts
    c = 1.0
    lb_rts = Lb / rts
    return Cb * π^2 * E / lb_rts^2 * sqrt(1 + 0.078 * (J * c) / (Sx * ho) * lb_rts^2)
end

"""Nominal flexural strength (Chapter F2). Considers yielding, LTB, and FLB."""
function get_Mn(s::ISymmSection, mat::Metal; Lb=zero(s.d), Cb=1.0)
    E, Fy = mat.E, mat.Fy
    Zx, Sx = s.Zx, s.Sx
    
    Mp = Fy * Zx
    Mn = Mp
    
    # LTB
    if Lb > zero(Lb)
        ltb = get_Lp_Lr(s, mat)
        Lp, Lr = ltb.Lp, ltb.Lr
        
        if Lb > Lr
            Fcr = get_Fcr_LTB(s, mat, Lb; Cb=Cb)
            Mn = min(Mn, Fcr * Sx)
        elseif Lb > Lp
            Mn_LTB = Cb * (Mp - (Mp - 0.7 * Fy * Sx) * ((Lb - Lp) / (Lr - Lp)))
            Mn = min(Mn, min(Mn_LTB, Mp))
        end
    end
    
    # FLB
    sl = get_slenderness(s, mat)
    λ_f, λp_f, λr_f = sl.λ_f, sl.λp_f, sl.λr_f
    
    if sl.class_f == :slender
        kc = clamp(4 / sqrt(s.λ_w), 0.35, 0.76)
        Mn = min(Mn, 0.9 * E * kc * Sx / λ_f^2)
    elseif sl.class_f == :noncompact
        Mn = min(Mn, Mp - (Mp - 0.7 * Fy * Sx) * ((λ_f - λp_f) / (λr_f - λp_f)))
    end
    
    return Mn
end

"""Design flexural strength (LRFD)."""
get_ϕMn(s::ISymmSection, mat::Metal; Lb=zero(s.d), Cb=1.0, ϕ=0.9) = ϕ * get_Mn(s, mat; Lb=Lb, Cb=Cb)
