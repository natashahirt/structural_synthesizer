# AISC 360 Chapter G - Design of Members for Shear

"""Web shear coefficient Cv1 (G2.1)."""
function get_Cv1(s::ISymmSection, mat::Metal; kv=5.34, rolled=true)
    E, Fy = mat.E, mat.Fy
    λ_w = s.λ_w
    
    if rolled
        limit = 2.24 * sqrt(E / Fy)
        Cv1 = λ_w <= limit ? 1.0 : 1.10 * sqrt(kv * E / Fy) / λ_w
    else
        limit = 1.10 * sqrt(kv * E / Fy)
        Cv1 = λ_w <= limit ? 1.0 : 1.10 * sqrt(kv * E / Fy) / λ_w
    end
    return Cv1
end

"""Nominal shear strength (G2.1 Strong Axis / G7 Weak Axis)."""
function get_Vn(s::ISymmSection, mat::Metal; axis=:strong, kv=5.34, rolled=true)
    if axis == :strong
        # G2.1: Shear in Web
        Cv1 = get_Cv1(s, mat; kv=kv, rolled=rolled)
        return 0.6 * mat.Fy * s.Aw * Cv1
    else
        # G7: Shear in Flanges (Weak Axis)
        # Vn = 0.6 * Fy * Aw_flanges * Cv2
        # Aw = 2 * bf * tf
        # For flanges of rolled shapes, Cv2 is typically 1.0 (compact)
        Aw_weak = 2 * s.bf * s.tf
        Cv2 = 1.0 # Simplified assumption for rolled shapes
        return 0.6 * mat.Fy * Aw_weak * Cv2
    end
end

"""Design shear strength (LRFD). ϕ=1.0 for most rolled I-shapes (Strong), ϕ=0.9 for Weak."""
function get_ϕVn(s::ISymmSection, mat::Metal; axis=:strong, kv=5.34, rolled=true, ϕ=nothing)
    if axis == :strong
        # G2.1(a): ϕ=1.0 for rolled I-shapes satisfying h/tw limit (most do)
        # Default ϕ=1.0 if not provided
        ϕ_use = isnothing(ϕ) ? 1.0 : ϕ
    else
        # G7: Weak axis shear -> G1 says ϕ=0.9 usually
        ϕ_use = isnothing(ϕ) ? 0.9 : ϕ
    end
    return ϕ_use * get_Vn(s, mat; axis=axis, kv=kv, rolled=rolled)
end
