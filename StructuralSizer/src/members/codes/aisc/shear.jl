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

"""Nominal shear strength (G2.1)."""
function get_Vn(s::ISymmSection, mat::Metal; kv=5.34, rolled=true)
    Cv1 = get_Cv1(s, mat; kv=kv, rolled=rolled)
    return 0.6 * mat.Fy * s.Aw * Cv1
end

"""Design shear strength (LRFD). ϕ=1.0 for most rolled I-shapes."""
get_ϕVn(s::ISymmSection, mat::Metal; kv=5.34, ϕ=1.0, rolled=true) = 
    ϕ * get_Vn(s, mat; kv=kv, rolled=rolled)
