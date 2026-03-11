# AISC 360 Chapter F - Design of Members for Flexure

"""
    get_Lp_Lr(s::ISymmSection, mat::Metal) -> NamedTuple(:Lp, :Lr, :c)

Limiting unbraced lengths for lateral-torsional buckling per AISC 360-16.

# Returns
- `Lp`: Limiting laterally unbraced length for yielding (Eq. F2-5)
- `Lr`: Limiting laterally unbraced length for inelastic LTB (Eq. F2-6)
- `c`: LTB modification factor (1.0 for doubly symmetric I-shapes)
"""
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

"""
    get_Fcr_LTB(s::ISymmSection, mat::Metal, Lb; Cb=1.0) -> Pressure

Critical stress for elastic lateral-torsional buckling per AISC 360-16 Eq. F2-4.

# Arguments
- `Lb`: Laterally unbraced length
- `Cb`: Lateral-torsional buckling modification factor (default 1.0)
"""
function get_Fcr_LTB(s::ISymmSection, mat::Metal, Lb; Cb=1.0)
    E = mat.E
    J, Sx, ho, rts = s.J, s.Sx, s.ho, s.rts
    c = 1.0
    lb_rts = Lb / rts
    return Cb * π^2 * E / lb_rts^2 * sqrt(1 + 0.078 * (J * c) / (Sx * ho) * lb_rts^2)
end

"""
    get_Mn(s::ISymmSection, mat::Metal; Lb, Cb=1.0, axis=:strong) -> Moment

Nominal flexural strength per AISC 360-16 Chapter F.

Strong axis (F2): considers yielding, lateral-torsional buckling, and
flange local buckling. Weak axis (F6): considers yielding and flange
local buckling.

# Arguments
- `Lb`: Laterally unbraced length (default 0 = full bracing)
- `Cb`: LTB modification factor (default 1.0)
- `axis`: `:strong` (F2) or `:weak` (F6)

# Returns
- `Mn`: Nominal moment capacity, taking the minimum of all applicable limit states
"""
function get_Mn(s::ISymmSection, mat::Metal; Lb=zero(s.d), Cb=1.0, axis=:strong)
    E, Fy = mat.E, mat.Fy
    
    if axis == :strong
        # --- Strong Axis Bending (F2) ---
        Zx, Sx = s.Zx, s.Sx
        Mp = Fy * Zx
        Mn = Mp
        
        # 1. LTB (F2-2, F2-3)
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
        
        # 2. Flange Local Buckling (F3 - Compression Flange)
        # Note: For rolled W-shapes, F2 applies to compact/noncompact webs.
        # Check flange compactness.
        sl = get_slenderness(s, mat)
        λ_f, λp_f, λr_f = sl.λ_f, sl.λp_f, sl.λr_f
        
        if sl.class_f == :slender
            # F3-2
            kc = clamp(4 / sqrt(s.λ_w), 0.35, 0.76)
            Mn = min(Mn, 0.9 * E * kc * Sx / λ_f^2)
        elseif sl.class_f == :noncompact
            # F3-1
            Mn = min(Mn, Mp - (Mp - 0.7 * Fy * Sx) * ((λ_f - λp_f) / (λr_f - λp_f)))
        end
        
        return Mn

    else
        # --- Weak Axis Bending (F6) ---
        # I-shapes bent about minor axis
        Zy, Sy = s.Zy, s.Sy
        Mp = min(Fy * Zy, 1.6 * Fy * Sy) # F6-1 limit
        Mn = Mp
        
        # 1. Flange Local Buckling (F6-2, F6-3)
        sl = get_slenderness(s, mat)
        λ = sl.λ_f
        λp = 0.38 * sqrt(E / Fy)
        λr = 1.0 * sqrt(E / Fy)
        
        if λ > λr
            # F6-3 (Slender)
            Fcr = 0.69 * E / λ^2
            Mn = min(Mn, Fcr * Sy)
        elseif λ > λp
            # F6-2 (Non-compact)
            Mn = min(Mn, Mp - (Mp - 0.7 * Fy * Sy) * ((λ - λp) / (λr - λp)))
        end
        
        return Mn
    end
end

"""
    get_ϕMn(s::ISymmSection, mat::Metal; Lb, Cb=1.0, axis=:strong, ϕ=0.9) -> Moment

Design flexural strength ϕMn per AISC 360-16 (LRFD). `ϕ_b = 0.9` per Section F1.
"""
get_ϕMn(s::ISymmSection, mat::Metal; Lb=zero(s.d), Cb=1.0, axis=:strong, ϕ=0.9) = 
    ϕ * get_Mn(s, mat; Lb=Lb, Cb=Cb, axis=axis)
