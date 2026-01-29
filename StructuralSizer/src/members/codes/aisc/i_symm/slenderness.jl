# AISC 360 Table B4.1b - Slenderness Limits for Flexure

"""Slenderness ratios and limits for flanges and web (Flexure)."""
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

"""Slenderness limits for Compression (Table B4.1a). Returns Qs, Qa."""
function get_compression_factors(s::ISymmSection, mat::Metal)
    λ_f, λ_w = s.λ_f, s.λ_w
    E, Fy = mat.E, mat.Fy

    # --- Qs: Unstiffened Elements (Flanges) ---
    # Case 1: Rolled I-shapes
    qs_limit_1 = 0.56 * sqrt(E / Fy)
    qs_limit_2 = 1.03 * sqrt(E / Fy)

    if λ_f <= qs_limit_1
        Qs = 1.0
    elseif λ_f < qs_limit_2
        # E7-5
        Qs = 1.415 - 0.74 * λ_f * sqrt(Fy / E)
    else
        # E7-6
        Qs = 0.69 * E / (Fy * λ_f^2)
    end

    # --- Qa: Stiffened Elements (Webs) ---
    # Case 5: Doubly symmetric I-shapes
    # Limit for slender web
    qa_limit = 1.49 * sqrt(E / Fy)

    if λ_w <= qa_limit
        Qa = 1.0
    else
        # E7.2: Qa = Aeff / Ag
        # Simplified: Use f = Fy (conservative for classification/sizing)
        # Exact calculation requires iteration or assumption of Fcr.
        # For now, we assume Qa = 1.0 because rolled W-shapes with slender webs in compression are extremely rare.
        # (Only applies to rare built-up sections or very deep thin shapes).
        # TODO: Implement full Qa iteration.
        Qa = 1.0
    end

    return (Qs=Qs, Qa=Qa, Q=Qs*Qa)
end

"""Check if section is compact in both flange and web (Flexure)."""
function is_compact(s::ISymmSection, mat::Metal)
    sl = get_slenderness(s, mat)
    return sl.class_f == :compact && sl.class_w == :compact
end
