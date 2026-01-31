# =============================================================================
# CIP Flat Plate Design per ACI 318-14/19
# =============================================================================
#
# Methodology: StructurePoint Design Examples (ACI 318-14)
# Equations: Broyles, Solnosky, Brown (2024) - Supplementary Document
#
# Reference: DE-Two-Way-Flat-Plate-Concrete-Floor-System-Analysis-and-Design-ACI-318-14-spSlab-v1000.pdf
# Example: 18 ft × 14 ft panel, 16" columns, f'c=4000 psi (slab), fy=60 ksi
#
# =============================================================================
# UNIT CONVENTION
# =============================================================================
#
# All public functions use Unitful type signatures for type safety:
#   - Lengths:   Length   (accepts m, ft, inch, etc.)
#   - Areas:     Area     (accepts m², ft², inch², etc.)
#   - Pressures: Pressure (accepts Pa, psi, ksi, psf, etc.)
#   - Moments:   Moment   (accepts N·m, kip·ft, lb·in, etc.)
#
# Internal calculations convert to a consistent system (typically US customary
# for ACI compatibility) and return results with explicit units.
#
# Example:
#   h = min_thickness_flat_plate(16.67u"ft")  # Returns Quantity in inches
#   fc = 4000u"psi"
#   Ec_val = Ec(fc)  # Returns Quantity in psi
#
# =============================================================================

using Unitful
using Unitful: @u_str
using StructuralBase.StructuralUnits: kip, ksi, ksf, psf, pcf
using StructuralBase.StructuralUnits: Length, Area, Volume, Inertia, Pressure, Force, Moment, LinearLoad

# Register custom units so u"psf", u"ksi" etc. work in docstrings and code
Unitful.register(StructuralBase.StructuralUnits)

# =============================================================================
# Material Properties
# =============================================================================

"""
Concrete modulus of elasticity per ACI 19.2.2.1.
"""
function Ec(fc::Pressure)
    fc_psi = ustrip(u"psi", fc)
    return 57000 * sqrt(fc_psi) * u"psi"
end

"""
Stress block factor β₁ per ACI 22.2.2.4.3.
"""
function β1(fc::Pressure)
    fc_psi = ustrip(u"psi", fc)
    if fc_psi <= 4000
        return 0.85
    elseif fc_psi >= 8000
        return 0.65
    else
        return 0.85 - 0.05 * (fc_psi - 4000) / 1000
    end
end

"""
Concrete rupture modulus for deflection calculations per ACI 19.2.3.1.
"""
function fr(fc::Pressure)
    fc_psi = ustrip(u"psi", fc)
    return 7.5 * sqrt(fc_psi) * u"psi"
end

# =============================================================================
# Phase 2: Slab Thickness (ACI 8.3.1.1)
# =============================================================================

"""
    min_thickness_flat_plate(ln; discontinuous_edge=false)

Minimum flat plate thickness per ACI 318-14 Table 8.3.1.1.

# Arguments
- `ln`: Clear span (face-to-face of columns) - longer span governs
- `discontinuous_edge`: true if slab has discontinuous edge (exterior panel)

# Returns
- Minimum thickness h (with 5 inch absolute minimum)

# Reference
- ACI 318-14 Table 8.3.1.1, Row 1 (flat plates)
- StructurePoint Example: ln = 16.67 ft → h_min = 6.06 in → use 7 in
"""
function min_thickness_flat_plate(ln::Length; discontinuous_edge::Bool=false)
    ln_in = ustrip(u"inch", ln)
    
    if discontinuous_edge
        # Exterior panels: ln/30
        h_min = ln_in / 30
    else
        # Interior panels: ln/33
        h_min = ln_in / 33
    end
    
    # Absolute minimum per ACI 8.3.1.1
    h_min = max(h_min, 5.0)
    
    return h_min * u"inch"
end

"""
    clear_span(l, c)

Clear span from face-to-face of supports.

# Arguments
- `l`: Center-to-center span
- `c`: Column dimension in span direction
"""
function clear_span(l::Length, c::Length)
    return l - c
end

# =============================================================================
# Phase 3: Static Moment & Moment Distribution (ACI 8.10)
# =============================================================================

"""
    total_static_moment(qu, l2, ln)

Total factored static moment per ACI 318-14 Eq. 8.10.3.2.

    M₀ = (qᵤ × l₂ × lₙ²) / 8

# Arguments
- `qu`: Factored uniform load (psf or kPa)
- `l2`: Panel width perpendicular to span direction
- `ln`: Clear span (face-to-face of columns)

# Reference
- ACI 318-14 Section 8.10.3.2
- StructurePoint Example: qu=0.193 ksf, l2=14 ft, ln=16.67 ft → M₀ = 93.82 k-ft
"""
function total_static_moment(qu::Pressure, l2::Length, ln::Length)
    return qu * l2 * ln^2 / 8
end

"""
M-DDM Coefficients for flat plates (αf = 0).

Simplified coefficients from Supplementary Document Table S-1.
These assume no beams (αf = 0) which is always true for flat plates.

Structure:
- First level: span type (:end_span or :interior_span)
- Second level: strip type (:column_strip or :middle_strip)  
- Third level: moment location

Note: All coefficients are fractions of M₀.
"""
const MDDM_COEFFICIENTS = (
    # End span (exterior span with one exterior support)
    # Supplementary Document Table S-1 values
    end_span = (
        # Column strip moments (% of M₀)
        column_strip = (
            ext_neg = 0.27,   # Exterior negative (at exterior column)
            pos = 0.345,      # Positive (midspan)
            int_neg = 0.55    # Interior negative (at first interior column)
        ),
        # Middle strip moments (% of M₀)
        middle_strip = (
            ext_neg = 0.00,   # Exterior negative (0 for flat plate w/o edge beam)
            pos = 0.235,      # Positive (midspan)
            int_neg = 0.18    # Interior negative
        )
    ),
    # Interior span (both supports are interior columns)
    interior_span = (
        column_strip = (
            neg = 0.535,      # Negative (at columns)
            pos = 0.186       # Positive (midspan)
        ),
        middle_strip = (
            neg = 0.175,      # Negative
            pos = 0.124       # Positive
        )
    )
)

"""
Full ACI DDM coefficients per Tables 8.10.4.2, 8.10.5.1-5.5, 8.10.5.7.

These vary with l₂/l₁ ratio. For flat plates (αf = 0), use column marked αf·l₂/l₁ = 0.
"""
const ACI_DDM_LONGITUDINAL = (
    # Table 8.10.4.2: Distribution of M₀ to negative and positive sections
    # (Same for all slab types)
    end_span = (
        ext_neg = 0.26,   # Exterior negative
        pos = 0.52,       # Positive  
        int_neg = 0.70    # Interior negative
    ),
    interior_span = (
        neg = 0.65,       # Negative at supports
        pos = 0.35        # Positive at midspan
    )
)

"""
ACI Table 8.10.5.1 - Column strip negative moment at interior supports.
For flat plates (αf = 0), always 75%.
"""
const ACI_COL_STRIP_INT_NEG = 0.75

"""
ACI Table 8.10.5.2 - Column strip negative moment at exterior supports.
Without edge beam (βt = 0), always 100%.
"""
const ACI_COL_STRIP_EXT_NEG_NO_BEAM = 1.00

"""
ACI Table 8.10.5.5 - Column strip positive moment.
For flat plates, 60% for l₂/l₁ = 1.0, varies with ratio.
"""
function aci_col_strip_positive(l2_l1::Float64)
    # Interpolate between 60% (l2/l1=0.5) and 60% (l2/l1=2.0)
    # For αf = 0 (flat plate), it's constant at 60%
    return 0.60
end

"""
    distribute_moments_mddm(M0, span_type::Symbol)

Distribute total static moment using simplified M-DDM coefficients.

# Arguments
- `M0`: Total static moment from total_static_moment()
- `span_type`: :end_span or :interior_span

# Returns
Named tuple with column_strip and middle_strip moments at each location.

# Reference
- Supplementary Document Table S-1
"""
function distribute_moments_mddm(M0, span_type::Symbol)
    coeffs = span_type == :end_span ? MDDM_COEFFICIENTS.end_span : MDDM_COEFFICIENTS.interior_span
    
    if span_type == :end_span
        return (
            column_strip = (
                ext_neg = coeffs.column_strip.ext_neg * M0,
                pos = coeffs.column_strip.pos * M0,
                int_neg = coeffs.column_strip.int_neg * M0
            ),
            middle_strip = (
                ext_neg = coeffs.middle_strip.ext_neg * M0,
                pos = coeffs.middle_strip.pos * M0,
                int_neg = coeffs.middle_strip.int_neg * M0
            )
        )
    else
        return (
            column_strip = (
                neg = coeffs.column_strip.neg * M0,
                pos = coeffs.column_strip.pos * M0
            ),
            middle_strip = (
                neg = coeffs.middle_strip.neg * M0,
                pos = coeffs.middle_strip.pos * M0
            )
        )
    end
end

"""
    distribute_moments_aci(M0, span_type::Symbol, l2_l1::Float64; edge_beam::Bool=false)

Distribute moments using full ACI DDM procedure (Tables 8.10.4-5).

# Arguments
- `M0`: Total static moment
- `span_type`: :end_span or :interior_span
- `l2_l1`: Ratio of panel width to span length
- `edge_beam`: Whether exterior edge has a beam (affects βt)

# Returns
Named tuple with distributed moments to column and middle strips.
"""
function distribute_moments_aci(M0, span_type::Symbol, l2_l1::Float64; edge_beam::Bool=false)
    if span_type == :end_span
        # Step 1: Longitudinal distribution (Table 8.10.4.2)
        M_ext_neg = ACI_DDM_LONGITUDINAL.end_span.ext_neg * M0
        M_pos = ACI_DDM_LONGITUDINAL.end_span.pos * M0
        M_int_neg = ACI_DDM_LONGITUDINAL.end_span.int_neg * M0
        
        # Step 2: Transverse distribution to column strip
        # Interior negative: Table 8.10.5.1 (75% for αf=0)
        cs_int_neg = ACI_COL_STRIP_INT_NEG * M_int_neg
        
        # Exterior negative: Table 8.10.5.2
        cs_ext_neg_frac = edge_beam ? 0.75 : ACI_COL_STRIP_EXT_NEG_NO_BEAM
        cs_ext_neg = cs_ext_neg_frac * M_ext_neg
        
        # Positive: Table 8.10.5.5
        cs_pos = aci_col_strip_positive(l2_l1) * M_pos
        
        # Middle strip gets remainder
        ms_ext_neg = M_ext_neg - cs_ext_neg
        ms_pos = M_pos - cs_pos
        ms_int_neg = M_int_neg - cs_int_neg
        
        return (
            column_strip = (ext_neg = cs_ext_neg, pos = cs_pos, int_neg = cs_int_neg),
            middle_strip = (ext_neg = ms_ext_neg, pos = ms_pos, int_neg = ms_int_neg)
        )
    else
        # Interior span
        M_neg = ACI_DDM_LONGITUDINAL.interior_span.neg * M0
        M_pos = ACI_DDM_LONGITUDINAL.interior_span.pos * M0
        
        cs_neg = ACI_COL_STRIP_INT_NEG * M_neg
        cs_pos = aci_col_strip_positive(l2_l1) * M_pos
        
        ms_neg = M_neg - cs_neg
        ms_pos = M_pos - cs_pos
        
        return (
            column_strip = (neg = cs_neg, pos = cs_pos),
            middle_strip = (neg = ms_neg, pos = ms_pos)
        )
    end
end

# =============================================================================
# Phase 5: Reinforcement Design (ACI 8.6, 22.2)
# =============================================================================

"""
    required_reinforcement(Mu, b, d, fc, fy)

Required steel area per Supplementary Document Eq. 1.7 derivation.

Uses the quadratic solution for As from moment equilibrium:
    As = (β₁·f'c·b·d / fy) × (1 - √(1 - 2Rn/(β₁·f'c)))

where Rn = Mu / (φ·b·d²)

# Arguments
- `Mu`: Factored moment demand
- `b`: Strip width
- `d`: Effective depth (h - cover - db/2)
- `fc`: Concrete compressive strength
- `fy`: Steel yield strength

# Returns
Required steel area As

# Reference
- Supplementary Document Section 1.7 (Setareh & Darvas derivation)
- StructurePoint Example Section 3.1.3
"""
function required_reinforcement(Mu::Moment, b::Length, d::Length, fc::Pressure, fy::Pressure)
    φ = 0.9  # Tension-controlled section (ACI 21.2.2)
    
    # Convert to consistent units (lbf, in)
    Mu_lbin = ustrip(u"lbf*inch", Mu)
    b_in = ustrip(u"inch", b)
    d_in = ustrip(u"inch", d)
    fc_psi = ustrip(u"psi", fc)
    fy_psi = ustrip(u"psi", fy)
    
    # Resistance coefficient (Rn)
    Rn = Mu_lbin / (φ * b_in * d_in^2)
    
    # Stress block factor
    β = β1(fc)
    
    # Check if section is adequate
    # Maximum Rn for tension-controlled section
    Rn_max = 0.319 * β * fc_psi  # Approximate limit
    if Rn > Rn_max
        @warn "Section may not be tension-controlled, Rn=$Rn > Rn_max=$Rn_max"
    end
    
    # Required steel ratio (from quadratic solution)
    term = 2 * Rn / (β * fc_psi)
    if term > 1.0
        error("Section inadequate: required Rn exceeds capacity. Increase h or f'c.")
    end
    
    ρ = (β * fc_psi / fy_psi) * (1 - sqrt(1 - term))
    
    # Required area
    As = ρ * b_in * d_in
    
    return As * u"inch^2"
end

"""
    minimum_reinforcement(b, h)

Minimum reinforcement per ACI 8.6.1.1 for shrinkage and temperature.

    As_min = 0.0018 × b × h  (for fy = 60 ksi)

# Reference
- ACI 318-14 Section 8.6.1.1
"""
function minimum_reinforcement(b::Length, h::Length)
    b_in = ustrip(u"inch", b)
    h_in = ustrip(u"inch", h)
    return 0.0018 * b_in * h_in * u"inch^2"
end

"""
    effective_depth(h; cover=0.75u"inch", bar_diameter=0.5u"inch")

Effective depth d = h - cover - db/2.

# Arguments
- `h`: Total slab thickness
- `cover`: Clear cover to reinforcement (default 0.75" for interior slab)
- `bar_diameter`: Assumed bar diameter (default #4 = 0.5")
"""
function effective_depth(h::Length; cover=0.75u"inch", bar_diameter=0.5u"inch")
    return h - cover - bar_diameter / 2
end

"""
    max_bar_spacing(h)

Maximum bar spacing per ACI 8.7.2.2.

    s_max = min(2h, 18 in)

# Reference
- ACI 318-14 Section 8.7.2.2
"""
function max_bar_spacing(h::Length)
    h_in = ustrip(u"inch", h)
    return min(2 * h_in, 18.0) * u"inch"
end

# =============================================================================
# Phase 6: Punching Shear (ACI 22.6)
# =============================================================================

"""
    punching_perimeter(c1, c2, d)

Critical perimeter for punching shear at d/2 from column face.

# Arguments
- `c1`: Column dimension in direction 1
- `c2`: Column dimension in direction 2
- `d`: Effective slab depth

# Returns
Perimeter b₀ = 2(c1 + d) + 2(c2 + d)

# Reference
- ACI 318-14 Section 22.6.4
"""
function punching_perimeter(c1::Length, c2::Length, d::Length)
    return 2 * (c1 + d) + 2 * (c2 + d)
end

"""
    punching_capacity_interior(b0, d, fc; λ=1.0)

Punching shear capacity at interior column per ACI 22.6.5.2.

    Vc = min(4√f'c, (2 + 4/β)√f'c, (αs·d/b₀ + 2)√f'c) × b₀ × d

For square interior columns (β = 1, αs = 40):
    Vc = 4√f'c × b₀ × d  (usually governs)

# Arguments
- `b0`: Critical perimeter from punching_perimeter()
- `d`: Effective depth
- `fc`: Concrete compressive strength
- `λ`: Lightweight concrete factor (1.0 for normal weight)

# Returns
Nominal shear capacity Vn (unfactored)

# Reference
- ACI 318-14 Section 22.6.5.2
- StructurePoint Example Section 3.3
"""
function punching_capacity_interior(
    b0::Length,
    d::Length,
    fc::Pressure;
    c1::Length = 0u"inch",
    c2::Length = 0u"inch",
    λ::Float64 = 1.0
)
    fc_psi = ustrip(u"psi", fc)
    b0_in = ustrip(u"inch", b0)
    d_in = ustrip(u"inch", d)
    
    sqrt_fc = sqrt(fc_psi)
    
    # ACI 22.6.5.2(a): Basic 4√f'c
    Vc_a = 4 * λ * sqrt_fc * b0_in * d_in
    
    # ACI 22.6.5.2(b): Column aspect ratio
    if c1 > 0u"inch" && c2 > 0u"inch"
        β = max(ustrip(u"inch", c1), ustrip(u"inch", c2)) / 
            min(ustrip(u"inch", c1), ustrip(u"inch", c2))
        Vc_b = (2 + 4/β) * λ * sqrt_fc * b0_in * d_in
    else
        Vc_b = Vc_a  # Default for square
    end
    
    # ACI 22.6.5.2(c): Perimeter-to-depth ratio (αs = 40 for interior)
    αs = 40  # Interior column
    Vc_c = (αs * d_in / b0_in + 2) * λ * sqrt_fc * b0_in * d_in
    
    Vn = min(Vc_a, Vc_b, Vc_c)
    
    return Vn * u"lbf"
end

"""
    punching_demand(qu, l1, l2, c1, c2)

Punching shear demand at interior column.

    Vu = qu × (l1 × l2 - (c1 + d)(c2 + d))

Simplified as tributary area minus critical section area.

# Reference
- ACI 318-14 Section 22.6.4
"""
function punching_demand(
    qu::Pressure,
    At::Area,  # Tributary area from Voronoi
    c1::Length,
    c2::Length,
    d::Length
)
    # Critical section area
    Ac = (c1 + d) * (c2 + d)
    
    # Net loaded area
    A_net = At - Ac
    
    return qu * A_net
end

"""
    check_punching_shear(Vu, Vc; φ=0.75)

Check punching shear adequacy.

# Returns
(passes::Bool, ratio::Float64, message::String)
"""
function check_punching_shear(Vu, Vc; φ::Float64=0.75)
    φVc = φ * Vc
    ratio = Vu / φVc
    passes = ratio <= 1.0
    
    if passes
        msg = "OK: Vu/φVc = $(round(ratio, digits=3))"
    else
        msg = "NG: Vu/φVc = $(round(ratio, digits=3)) > 1.0 - increase h or add shear reinforcement"
    end
    
    return (passes=passes, ratio=ratio, message=msg)
end

# =============================================================================
# Phase 6: Deflection (ACI 24.2)
# =============================================================================

"""
    cracked_moment_of_inertia(As, b, d, Ec, Es)

Cracked section moment of inertia Icr per ACI 24.2.3.5.

Uses transformed section analysis with modular ratio n = Es/Ec.
"""
function cracked_moment_of_inertia(
    As::Area,
    b::Length,
    d::Length,
    Ec::Pressure,
    Es::Pressure = 29000ksi
)
    # Modular ratio n = Es/Ec (convert to same units first)
    n = ustrip(u"psi", Es) / ustrip(u"psi", Ec)
    
    As_in2 = ustrip(u"inch^2", As)
    b_in = ustrip(u"inch", b)
    d_in = ustrip(u"inch", d)
    
    # Neutral axis depth from transformed section analysis
    # Equilibrium: b·c²/2 = n·As·(d-c)
    # Quadratic: c² + (2n·As/b)·c - (2n·As·d/b) = 0
    # Using quadratic formula: c = (-B + √(B² - 4AC)) / 2A where A=1
    k1 = 2 * n * As_in2 / b_in  # Coefficient B
    k2 = -k1 * d_in             # Coefficient C (negative)
    c = (-k1 + sqrt(k1^2 - 4*k2)) / 2
    
    # Cracked moment of inertia
    # Icr = b·c³/3 + n·As·(d-c)²
    Icr = b_in * c^3 / 3 + n * As_in2 * (d_in - c)^2
    
    return Icr * u"inch^4"
end

"""
    effective_moment_of_inertia(Mcr, Ma, Ig, Icr)

Effective moment of inertia per ACI 24.2.3.5.

    Ie = Icr + (Ig - Icr) × (Mcr/Ma)³  when Ma > Mcr
    Ie = Ig                             when Ma ≤ Mcr

# Arguments
- `Mcr`: Cracking moment = fr × Ig / yt
- `Ma`: Service moment
- `Ig`: Gross moment of inertia
- `Icr`: Cracked moment of inertia

# Reference
- ACI 318-14 Eq. 24.2.3.5a
"""
function effective_moment_of_inertia(Mcr, Ma, Ig, Icr)
    if Ma <= Mcr
        return Ig
    end
    
    ratio = Mcr / Ma
    Ie = Icr + (Ig - Icr) * ratio^3
    
    # Ie cannot exceed Ig
    return min(Ie, Ig)
end

"""
    cracking_moment(fr, Ig, h)

Cracking moment per ACI 24.2.3.5.

    Mcr = fr × Ig / yt

where yt = h/2 for rectangular sections.

# Arguments
- `fr`: Modulus of rupture (Pressure)
- `Ig`: Gross moment of inertia (Inertia = L⁴)
- `h`: Section depth (Length)
"""
function cracking_moment(fr::Pressure, Ig::Inertia, h::Length)
    yt = h / 2
    return fr * Ig / yt
end

"""
    immediate_deflection(w, l, Ec, Ie)

Immediate deflection for uniformly loaded member.

    Δi = 5 × w × l⁴ / (384 × Ec × Ie)

# Reference
- Standard beam formula
"""
function immediate_deflection(
    w::Force,  # Load per unit length
    l::Length,
    Ec::Pressure,
    Ie::Volume
)
    return 5 * w * l^4 / (384 * Ec * Ie)
end

"""
    long_term_deflection_factor(ξ, ρ_prime)

Long-term deflection multiplier per ACI 24.2.4.1.

    λΔ = ξ / (1 + 50ρ')

where:
- ξ = time-dependent factor (2.0 for 5+ years)
- ρ' = compression reinforcement ratio

# Reference
- ACI 318-14 Section 24.2.4.1
"""
function long_term_deflection_factor(ξ::Float64=2.0, ρ_prime::Float64=0.0)
    return ξ / (1 + 50 * ρ_prime)
end

"""
    deflection_limit(l, limit_type::Symbol)

Allowable deflection per ACI Table 24.2.2.

# Arguments
- `l`: Span length
- `limit_type`: :immediate_ll (l/360), :total (l/240), :sensitive (l/480)
"""
function deflection_limit(l::Length, limit_type::Symbol)
    l_in = ustrip(u"inch", l)
    
    divisor = if limit_type == :immediate_ll
        360  # Immediate deflection due to live load
    elseif limit_type == :total
        240  # Total deflection after attachment of elements
    elseif limit_type == :sensitive
        480  # Members supporting sensitive elements
    else
        240  # Default
    end
    
    return (l_in / divisor) * u"inch"
end

# =============================================================================
# Initial Column Estimate (Phase 2)
# =============================================================================

"""
    estimate_column_size(At, qu, n_stories_above, fc; fy=60000u"psi", shape=:square)

Estimate initial column size from tributary area before full column design.

This provides an initial estimate needed for slab clear span calculation (ln = l - c).
The estimate is intentionally conservative (tends to undersize) so that:
- Slab clear span is slightly overestimated → thicker slab (safe)
- Proper column sizing will give larger columns → shorter clear span (safe)

# Arguments
- `At`: Tributary area per floor (from Voronoi, m²)
- `qu`: Factored floor load (kPa or psf)
- `n_stories_above`: Number of stories supported by column
- `fc`: Concrete compressive strength (f'c)
- `fy`: Reinforcement yield strength (default 60 ksi)
- `shape`: :square (default) or :rectangular

# Returns
- Column dimension c (for square) as Length
- For rectangular, returns (c1, c2) tuple with c2 = 1.5 × c1

# Method
Uses simplified capacity formula:
    Pu ≈ At × qu × n_stories_above
    Ag_required ≈ Pu / (φ × 0.80 × [0.85 f'c (1-ρg) + ρg × fy])
    
Assumes ρg ≈ 2% (typical), φ = 0.65 (compression-controlled)
Simplifies to: Ag ≈ Pu / (0.40 × f'c)  for f'c ≤ 6000 psi

# Reference
- ACI 318-14 Section 22.4.2 (nominal axial strength)
- Rule of thumb: c ≈ √(Ag)

# Example
```julia
At = 100u"m^2"      # 100 m² tributary
qu = 10u"kPa"       # ~200 psf factored
n = 5               # 5 stories above
fc = 4000u"psi"
c = estimate_column_size(At, qu, n, fc)  # ≈ 16-18 inches
```
"""
function estimate_column_size(
    At::Area,
    qu::Pressure,
    n_stories_above::Int,
    fc::Pressure;
    fy::Pressure = 60000u"psi",
    shape::Symbol = :square
)
    # Convert to consistent units
    At_ft2 = ustrip(u"ft^2", At)
    qu_psf = ustrip(u"psf", qu)
    fc_psi = ustrip(u"psi", fc)
    
    # Estimated factored axial load
    Pu_lb = At_ft2 * qu_psf * n_stories_above
    
    # Required gross area (simplified for typical reinforcement)
    # Full formula: φPn = φ × 0.80 × [0.85f'c(Ag - As) + fy×As]
    # Simplified with ρg ≈ 2%, φ = 0.65:
    # Ag ≈ Pu / (0.65 × 0.80 × [0.85×f'c×0.98 + fy×0.02])
    # For fc=4ksi, fy=60ksi: ≈ Pu / (0.40 × f'c)
    
    # Use conservative formula (will give smaller column → safe for slab design)
    Ag_in2 = Pu_lb / (0.40 * fc_psi)
    
    # Apply minimum column size (ACI practical minimum ~10")
    Ag_min = 100.0  # 10" × 10" = 100 in²
    Ag_in2 = max(Ag_in2, Ag_min)
    
    if shape == :square
        c_in = sqrt(Ag_in2)
        # Round up to nearest inch
        c_in = ceil(c_in)
        return c_in * u"inch"
    else
        # Rectangular: c2 = 1.5 × c1 (typical aspect ratio)
        # Ag = c1 × c2 = c1 × 1.5c1 = 1.5c1²
        c1_in = sqrt(Ag_in2 / 1.5)
        c2_in = 1.5 * c1_in
        return (ceil(c1_in) * u"inch", ceil(c2_in) * u"inch")
    end
end

"""
    estimate_column_size_from_span(span; ratio=15)

Alternative column estimate from span using rule of thumb.

# Arguments
- `span`: Center-to-center span
- `ratio`: Span-to-column ratio (default 15, typical range 12-18)

# Returns
Column dimension c = span / ratio

# Reference
Common practice for preliminary design:
- High-rise: c ≈ L/12 to L/14
- Mid-rise: c ≈ L/15 to L/18
- Low-rise: c ≈ L/18 to L/20
"""
function estimate_column_size_from_span(span::Length; ratio::Float64=15.0)
    c = span / ratio
    # Round up to nearest inch
    c_in = ceil(ustrip(u"inch", c))
    return c_in * u"inch"
end

# =============================================================================
# Design Result Types
# =============================================================================
# Note: StripReinforcement and FlatPlatePanelResult are defined in 
# StructuralSizer/src/slabs/types.jl for consistency with other floor results.

# =============================================================================
# Exports
# =============================================================================

export Ec, β1, fr
export min_thickness_flat_plate, clear_span
export total_static_moment, distribute_moments_mddm, distribute_moments_aci
export required_reinforcement, minimum_reinforcement, effective_depth, max_bar_spacing
export punching_perimeter, punching_capacity_interior, punching_demand, check_punching_shear
export cracked_moment_of_inertia, effective_moment_of_inertia, cracking_moment
export immediate_deflection, long_term_deflection_factor, deflection_limit
export MDDM_COEFFICIENTS, ACI_DDM_LONGITUDINAL
export estimate_column_size, estimate_column_size_from_span
# StripReinforcement, FlatPlatePanelResult exported from slabs/types.jl
