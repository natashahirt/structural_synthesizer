# AISC 360 Table B4.1b - Slenderness Limits

"""Slenderness ratios and limits for flanges and web."""
function get_slenderness(s::ISymmSection, mat::Metal)
    λ_f, λ_w = s.λ_f, s.λ_w
    E, Fy = mat.E, mat.Fy
    
    # Flange (Case 10)
    λp_f = 0.38 * sqrt(E / Fy)
    λr_f = 1.0 * sqrt(E / Fy)
    class_f = λ_f > λr_f ? :slender : (λ_f > λp_f ? :noncompact : :compact)
    
    # Web (Case 15)
    λp_w = 3.76 * sqrt(E / Fy)
    λr_w = 5.70 * sqrt(E / Fy)
    class_w = λ_w > λr_w ? :slender : (λ_w > λp_w ? :noncompact : :compact)
    
    return (λ_f=λ_f, λp_f=λp_f, λr_f=λr_f, class_f=class_f,
            λ_w=λ_w, λp_w=λp_w, λr_w=λr_w, class_w=class_w)
end

"""Check if section is compact in both flange and web."""
function is_compact(s::ISymmSection, mat::Metal)
    sl = get_slenderness(s, mat)
    return sl.class_f == :compact && sl.class_w == :compact
end
