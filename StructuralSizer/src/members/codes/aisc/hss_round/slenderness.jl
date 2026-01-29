# ==============================================================================
# AISC 360-16 - Round HSS / Pipe Slenderness (Table B4.1a / B4.1b)
# ==============================================================================

"""
Flexure slenderness classification for round HSS / pipe (Table B4.1b).

Returns: `(; λ, λp, λr, class)` where λ = D/t.
"""
function get_slenderness(s::HSSRoundSection, mat::Metal)
    E, Fy = mat.E, mat.Fy
    λ = s.D_t

    # Table B4.1b: Round HSS: λp = 0.07(E/Fy), λr = 0.31(E/Fy)
    λp = 0.07 * (E / Fy)
    λr = 0.31 * (E / Fy)

    class = λ > λr ? :slender : (λ > λp ? :noncompact : :compact)
    return (; λ, λp, λr, class)
end

"""
Compression slenderness limit for round HSS / pipe (Table B4.1a).

Returns: `(; λ, λr)` where λ = D/t.
"""
function get_compression_limits(s::HSSRoundSection, mat::Metal)
    E, Fy = mat.E, mat.Fy
    λ = s.D_t
    # Table B4.1a: Round HSS: λr = 0.11(E/Fy)
    λr = 0.11 * (E / Fy)
    return (; λ, λr)
end

