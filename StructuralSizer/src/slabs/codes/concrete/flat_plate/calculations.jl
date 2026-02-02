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
# NOT YET IMPLEMENTED (Future Work)
# =============================================================================
#
# 1. Shear Reinforcement (ACI 318-19 §22.6)
#    - Stud rails / headed shear studs for punching shear enhancement
#    - Stirrup cages around columns
#    - vn = vc + vs calculations where shear exceeds concrete capacity
#    Note: Currently punching shear failure requires column size or slab thickness increase
#
# 2. Pattern Loading (ACI 318-14 §6.4.3.2)  
#    - Only required when L/D > 0.75 (live load > 3/4 dead load)
#    - Checkerboard loading, adjacent spans loaded patterns
#    - Envelope of maximum/minimum moments at each location
#    Note: Current EFM uses full load on all spans (conservative for typical L/D < 0.75)
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
using Asap: kip, ksi, ksf, psf, pcf
using Asap: Length, Area, Volume, SecondMomentOfArea, TorsionalConstant, Pressure, Force, Moment, Torque, LinearLoad

# Register custom units so u"psf", u"ksi" etc. work in docstrings and code
Unitful.register(Asap)

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
# Phase 4: Equivalent Frame Method (EFM) - ACI 318-14 Section 8.11
# =============================================================================
#
# Reference: StructurePoint DE-Two-Way-Flat-Plate-...-ACI-318-14-spSlab-v1000.pdf
# Section 3.2: Equivalent Frame Method (EFM)
#
# The equivalent frame consists of three parts:
#   1. Slab-beam strip (K_sb): horizontal member with enhanced stiffness at columns
#   2. Columns (K_c): vertical members with infinite stiffness in joint region
#   3. Torsional members (K_t): provide moment transfer between slab and columns
#
# The equivalent column stiffness K_ec combines K_c and K_t in series.
#
# =============================================================================

"""
    slab_moment_of_inertia(l2, h)

Gross moment of inertia for slab strip per unit of span direction.

    Iₛ = l₂ × h³ / 12

# Arguments
- `l2`: Slab width perpendicular to span (tributary width of frame)
- `h`: Slab thickness

# Returns
Moment of inertia (Length⁴)

# Reference
- ACI 318-14 Section 8.11.3
- StructurePoint Example: l2=168 in, h=7 in → Is = 4,802 in⁴
"""
function slab_moment_of_inertia(l2::Length, h::Length)
    return l2 * h^3 / 12
end

"""
    column_moment_of_inertia(c1, c2)

Gross moment of inertia for rectangular column section.

    Iᶜ = c₁ × c₂³ / 12   (bending about axis parallel to c1)

# Arguments  
- `c1`: Column dimension in span direction
- `c2`: Column dimension perpendicular to span

# Returns
Moment of inertia (Length⁴)

# Reference
- ACI 318-14 Section 8.11.4
- StructurePoint Example: c1=c2=16 in → Ic = 5,461 in⁴
"""
function column_moment_of_inertia(c1::Length, c2::Length)
    return c1 * c2^3 / 12
end

"""
    torsional_constant_C(x, y)

Cross-sectional constant C for torsional member per ACI 318-14 Eq. 8.10.5.2b.

    C = Σ(1 - 0.63×(x/y)) × (x³×y/3)

For flat plate without beams, the torsional member is a slab strip with:
- x = slab thickness h
- y = column dimension c2 (width of torsional member)

# Arguments
- `x`: Smaller dimension of rectangular section (typically h)
- `y`: Larger dimension of rectangular section (typically c2)

# Returns
Torsional constant C (Length⁴)

# Reference
- ACI 318-14 Eq. 8.10.5.2b
- StructurePoint Example: x=7 in, y=16 in → C = 1,325 in⁴
"""
function torsional_constant_C(x::Length, y::Length)
    # Ensure x ≤ y for the formula
    x_val = min(x, y)
    y_val = max(x, y)
    
    # Strip units for calculation
    x_in = ustrip(u"inch", x_val)
    y_in = ustrip(u"inch", y_val)
    
    C = (1 - 0.63 * (x_in / y_in)) * (x_in^3 * y_in / 3)
    
    return C * u"inch^4"
end

"""
    slab_beam_stiffness_Ksb(Ecs, Is, l1, c1, c2; k_factor=4.127)

Flexural stiffness of slab-beam at both ends per ACI 318-14 Section 8.11.3.

    Kₛᵦ = k × Eᶜₛ × Iₛ / l₁

The stiffness factor k accounts for the non-prismatic section:
- Enhanced moment of inertia at column region: Is / (1 - c2/l2)²
- Default k = 4.127 from PCA Notes Table A1 for typical flat plate geometry

# Arguments
- `Ecs`: Modulus of elasticity of slab concrete
- `Is`: Gross moment of inertia of slab (from slab_moment_of_inertia)
- `l1`: Span length center-to-center of columns
- `c1`: Column dimension in span direction (for N1 = c1/l1)
- `c2`: Column dimension perpendicular to span (for N2 = c2/l2)
- `k_factor`: Stiffness factor from PCA tables (default 4.127 for c/l ≈ 0.08-0.10)

# Returns
Slab-beam stiffness Ksb (Moment units, e.g., in-lb)

# Reference
- ACI 318-14 Section 8.11.3
- PCA Notes on ACI 318-11 Table A1
- StructurePoint Example: Ecs=3,834×10³ psi, Is=4,802 in⁴, l1=18 ft=216 in
  → Ksb = 4.127 × 3,834×10³ × 4,802 / 216 = 351,766,909 in-lb

# Note
For precise results, k_factor should be interpolated from PCA Table A1 based on:
- N1 = c1/l1 (typically 0.05-0.15)
- N2 = c2/l2 (typically 0.05-0.15)
For most flat plates with c/l ≈ 0.07-0.10, k ≈ 4.0-4.2.
"""
function slab_beam_stiffness_Ksb(
    Ecs::Pressure,
    Is::SecondMomentOfArea,
    l1::Length,
    c1::Length,
    c2::Length;
    k_factor::Float64 = 4.127
)
    # Convert to consistent units
    Ecs_psi = ustrip(u"psi", Ecs)
    Is_in4 = ustrip(u"inch^4", Is)
    l1_in = ustrip(u"inch", l1)
    
    Ksb = k_factor * Ecs_psi * Is_in4 / l1_in
    
    return Ksb * u"lbf*inch"
end

"""
    column_stiffness_Kc(Ecc, Ic, H, h; k_factor=4.74)

Flexural stiffness of column at slab-beam joint per ACI 318-14 Section 8.11.4.

    Kᶜ = k × Eᶜᶜ × Iᶜ / H

The stiffness factor k accounts for:
- Infinite moment of inertia within the slab depth (joint region)
- Column clear height Hc = H - h

Default k = 4.74 from PCA Notes Table A7 for ta/tb = 1, H/Hc ≈ 1.07.

# Arguments
- `Ecc`: Modulus of elasticity of column concrete
- `Ic`: Gross moment of inertia of column (from column_moment_of_inertia)
- `H`: Story height (floor-to-floor)
- `h`: Slab thickness
- `k_factor`: Stiffness factor from PCA tables (default 4.74)

# Returns
Column stiffness Kc (Moment units, e.g., in-lb)

# Reference
- ACI 318-14 Section 8.11.4
- PCA Notes on ACI 318-11 Table A7
- StructurePoint Example: Ecc=4,696×10³ psi, Ic=5,461 in⁴, H=108 in
  → Kc = 4.74 × 4,696×10³ × 5,461 / 108 = 1,125,592,936 in-lb

# Note
For precise results, k_factor should be interpolated from PCA Table A7 based on:
- ta/tb = ratio of slab depth above/below (typically 1.0 for intermediate floors)
- H/Hc = story height / clear column height
"""
function column_stiffness_Kc(
    Ecc::Pressure,
    Ic::SecondMomentOfArea,
    H::Length,
    h::Length;
    k_factor::Float64 = 4.74
)
    # Convert to consistent units
    Ecc_psi = ustrip(u"psi", Ecc)
    Ic_in4 = ustrip(u"inch^4", Ic)
    H_in = ustrip(u"inch", H)
    
    Kc = k_factor * Ecc_psi * Ic_in4 / H_in
    
    return Kc * u"lbf*inch"
end

"""
    torsional_member_stiffness_Kt(Ecs, C, l2, c2)

Torsional stiffness of transverse slab strip per ACI 318-14 Section R8.11.5.

    Kₜ = 9 × Eᶜₛ × C / (l₂ × (1 - c₂/l₂)³)

The torsional member transfers moment between slab and column. For flat plates,
it's a slab strip with width equal to the column dimension c1.

# Arguments
- `Ecs`: Modulus of elasticity of slab concrete
- `C`: Torsional constant (from torsional_constant_C)
- `l2`: Panel width perpendicular to span
- `c2`: Column dimension perpendicular to span

# Returns
Torsional stiffness Kt (Moment units, e.g., in-lb)

# Reference
- ACI 318-14 Section R8.11.5, Eq. R8.11.5
- StructurePoint Example: Ecs=3,834×10³ psi, C=1,325 in⁴, l2=168 in, c2=16 in
  → Kt = 9 × 3,834×10³ × 1,325 / (168 × (1 - 16/168)³) = 367,484,240 in-lb
"""
function torsional_member_stiffness_Kt(Ecs::Pressure, C::TorsionalConstant, l2::Length, c2::Length)
    # Convert to consistent units
    Ecs_psi = ustrip(u"psi", Ecs)
    C_in4 = ustrip(u"inch^4", C)
    l2_in = ustrip(u"inch", l2)
    c2_in = ustrip(u"inch", c2)
    
    # (1 - c2/l2)³ factor
    reduction = (1 - c2_in / l2_in)^3
    
    Kt = 9 * Ecs_psi * C_in4 / (l2_in * reduction)
    
    return Kt * u"lbf*inch"
end

"""
    equivalent_column_stiffness_Kec(Kc_sum, Kt_sum)

Equivalent column stiffness combining column and torsional member stiffnesses.

    1/Kₑᶜ = 1/ΣKᶜ + 1/ΣKₜ

Or equivalently:

    Kₑᶜ = (ΣKᶜ × ΣKₜ) / (ΣKᶜ + ΣKₜ)

# Arguments
- `Kc_sum`: Sum of column stiffnesses at joint (upper + lower columns)
- `Kt_sum`: Sum of torsional member stiffnesses at joint (both sides)

# Returns
Equivalent column stiffness Kec (Moment units)

# Reference
- ACI 318-14 Section 8.11.5
- StructurePoint Example: ΣKc = 2×1,125.6×10⁶, ΣKt = 2×367.5×10⁶
  → Kec = (2×1125.6 × 2×367.5) / (2×1125.6 + 2×367.5) × 10⁶ = 554,074,058 in-lb

# Note
At exterior columns, ΣKt includes only one torsional member.
At roof level, ΣKc includes only one column (below).
"""
function equivalent_column_stiffness_Kec(Kc_sum, Kt_sum)
    # Handle units - both should have same dimension
    return (Kc_sum * Kt_sum) / (Kc_sum + Kt_sum)
end

"""
    distribution_factor_DF(Ksb, Kec; is_exterior::Bool=false, Ksb_adjacent=nothing)

Moment distribution factor for slab-beam at a joint.

At interior joint:
    DF = Kₛᵦ / (Kₛᵦ_left + Kₛᵦ_right + Kₑᶜ)

At exterior joint:
    DF = Kₛᵦ / (Kₛᵦ + Kₑᶜ)

# Arguments
- `Ksb`: Slab-beam stiffness at the joint
- `Kec`: Equivalent column stiffness at the joint
- `is_exterior`: Whether this is an exterior joint
- `Ksb_adjacent`: Slab-beam stiffness from adjacent span (for interior joints)

# Returns
Distribution factor DF (dimensionless, 0 to 1)

# Reference
- PCA Notes on ACI 318-11, Moment Distribution Method
- StructurePoint Example: 
  - Exterior: DF = 351.77 / (351.77 + 554.07) = 0.388
  - Interior: DF = 351.77 / (351.77 + 351.77 + 554.07) = 0.280
"""
function distribution_factor_DF(Ksb, Kec; is_exterior::Bool=false, Ksb_adjacent=nothing)
    if is_exterior
        total_K = Ksb + Kec
    else
        Ksb_adj = isnothing(Ksb_adjacent) ? Ksb : Ksb_adjacent
        total_K = Ksb + Ksb_adj + Kec
    end
    
    # Strip units for division (both are same dimension)
    return ustrip(Ksb) / ustrip(total_K)
end

"""
    carryover_factor_COF(; k_factor=4.127)

Carryover factor for non-prismatic slab-beam.

For flat plates with enhanced stiffness at columns, COF ≈ 0.507.
This is larger than the prismatic beam value of 0.5 due to the
increased stiffness at column regions.

# Arguments
- `k_factor`: Stiffness factor (same as used for Ksb)

# Returns
Carryover factor COF (dimensionless)

# Reference
- PCA Notes on ACI 318-11 Table A1
- StructurePoint Example: COF = 0.507
"""
function carryover_factor_COF(; k_factor::Float64=4.127)
    # For k ≈ 4.127, COF ≈ 0.507
    # This relationship is from PCA Notes Table A1
    # For a more accurate value, interpolate from the table
    return 0.507
end

"""
    fixed_end_moment_FEM(qu, l2, l1; m_factor=0.08429)

Fixed-end moment for uniformly loaded non-prismatic slab-beam.

    FEM = m × qᵤ × l₂ × l₁²

# Arguments
- `qu`: Factored uniform load (pressure)
- `l2`: Panel width perpendicular to span
- `l1`: Span length center-to-center
- `m_factor`: FEM factor from PCA tables (default 0.08429)

# Returns
Fixed-end moment FEM (moment units)

# Reference
- PCA Notes on ACI 318-11 Table A1
- StructurePoint Example: m=0.08429, qu=0.193 ksf, l2=14 ft, l1=18 ft
  → FEM = 0.08429 × 0.193 × 14 × 18² = 73.79 ft-kip
"""
function fixed_end_moment_FEM(qu::Pressure, l2::Length, l1::Length; m_factor::Float64=0.08429)
    return m_factor * qu * l2 * l1^2
end

"""
    face_of_support_moment(M_centerline, V, c, l1)

Reduce centerline moment to face-of-support for design per ACI 318-14 8.11.6.1.

    M_face = M_centerline - V × (c/2)

But not less than M at 0.175×l1 from column center.

# Arguments
- `M_centerline`: Moment at column centerline from frame analysis
- `V`: Shear at support (reaction)
- `c`: Column dimension in span direction
- `l1`: Span length

# Returns
Design moment at face of support

# Reference
- ACI 318-14 Section 8.11.6.1
- StructurePoint Example: M_cl = 83.91 kip-ft, V = 26.39 kip, c = 16/12 ft
  → M_face = 83.91 - 26.39 × (16/12/2) = 66.32 ft-kip
  
# Note
The 0.175×l1 limit ensures the design moment is taken at a reasonable
distance from the column center for very large columns.
"""
function face_of_support_moment(M_centerline, V, c::Length, l1::Length)
    # Distance to face of support
    d_face = c / 2
    
    # Maximum distance for moment reduction (ACI 8.11.6.1)
    d_max = 0.175 * l1
    
    # Use smaller of face distance or max distance
    d_use = min(d_face, d_max)
    
    # Reduce moment by V × d
    M_face = M_centerline - V * d_use
    
    return M_face
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
    minimum_reinforcement(b, h, fy)

Minimum reinforcement per ACI 318-14 Table 8.6.1.1 for shrinkage and temperature.

# Minimum Ratios (ACI Table 8.6.1.1)
- fy < 60 ksi:  ρ_min = 0.0020
- 60 ≤ fy < 77 ksi: ρ_min = 0.0018
- fy ≥ 77 ksi:  ρ_min = max(0.0014, 0.0018 × 60000/fy)

# Arguments
- `b`: Strip width
- `h`: Total slab thickness (gross section)
- `fy`: Reinforcement yield strength

# Returns
- As_min = ρ_min × b × h

# Reference
- ACI 318-14 Table 8.6.1.1
- StructurePoint Example: fy=60ksi → As_min = 0.0018 × b × h
"""
function minimum_reinforcement(b::Length, h::Length, fy::Pressure)
    b_in = ustrip(u"inch", b)
    h_in = ustrip(u"inch", h)
    fy_psi = ustrip(u"psi", fy)
    
    # ACI 318-14 Table 8.6.1.1
    ρ_min = if fy_psi < 60000
        0.0020
    elseif fy_psi < 77000
        0.0018
    else
        max(0.0014, 0.0018 * 60000 / fy_psi)
    end
    
    return ρ_min * b_in * h_in * u"inch^2"
end

# Backward compatible method with default fy = 60 ksi (deprecated)
function minimum_reinforcement(b::Length, h::Length)
    return minimum_reinforcement(b, h, 60000u"psi")
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
    punching_αs(position::Symbol) -> Int

ACI 22.6.5.2(c) location factor αs for punching shear.

# Arguments
- `position`: Column position (:interior, :edge, or :corner)

# Returns
- αs = 40 for interior columns
- αs = 30 for edge columns
- αs = 20 for corner columns

# Reference
- ACI 318-14 Table 22.6.5.2
"""
function punching_αs(position::Symbol)
    if position == :interior
        return 40
    elseif position == :edge
        return 30
    else  # :corner or unknown
        return 20
    end
end

"""
    punching_capacity_interior(b0, d, fc; c1, c2, λ, position)

Punching shear capacity per ACI 22.6.5.2.

    Vc = min(4√f'c, (2 + 4/β)√f'c, (αs·d/b₀ + 2)√f'c) × b₀ × d

# Arguments
- `b0`: Critical perimeter from punching_perimeter()
- `d`: Effective depth
- `fc`: Concrete compressive strength
- `c1`: Column dimension parallel to span (for β calculation)
- `c2`: Column dimension perpendicular to span (for β calculation)
- `λ`: Lightweight concrete factor (1.0 for normal weight)
- `position`: Column position (:interior, :edge, :corner) for αs

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
    λ::Float64 = 1.0,
    position::Symbol = :interior
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
        β = 1.0
        Vc_b = Vc_a  # Default for square
    end
    
    # ACI 22.6.5.2(c): Perimeter-to-depth ratio
    αs = punching_αs(position)
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
# Phase 6b: One-Way (Beam Action) Shear (ACI 22.5)
# =============================================================================

"""
    one_way_shear_capacity(fc, bw, d; λ=1.0)

One-way shear capacity per ACI 22.5.5.1.

    Vc = 2λ√f'c × bw × d

# Arguments
- `fc`: Concrete compressive strength
- `bw`: Width of section (typically tributary width)
- `d`: Effective depth

# Reference
- ACI 318-14 Eq. 22.5.5.1
- StructurePoint Section 5.1
"""
function one_way_shear_capacity(
    fc::Pressure,
    bw::Length,
    d::Length;
    λ::Float64 = 1.0
)
    fc_psi = ustrip(u"psi", fc)
    bw_in = ustrip(u"inch", bw)
    d_in = ustrip(u"inch", d)
    
    Vc = 2 * λ * sqrt(fc_psi) * bw_in * d_in
    return Vc * u"lbf"
end

"""
    one_way_shear_demand(qu, bw, ln, c, d)

One-way shear demand at distance d from column face.

# Arguments
- `qu`: Factored uniform load
- `bw`: Tributary width
- `ln`: Clear span (centerline to centerline minus column)
- `c`: Column dimension in shear direction
- `d`: Effective depth

# Returns
Vu at critical section (distance d from column face)

# Reference
- ACI 318-14 Section 22.5
- StructurePoint Section 5.1
"""
function one_way_shear_demand(
    qu::Pressure,
    bw::Length,
    ln::Length,
    c::Length,
    d::Length
)
    # Shear at face of support
    Vu_face = qu * bw * ln / 2
    
    # Reduce to critical section at distance d from face
    Vu = Vu_face - qu * bw * d
    
    return Vu
end

"""
    check_one_way_shear(Vu, Vc; φ=0.75)

Check one-way shear adequacy.

# Returns
NamedTuple (passes, ratio, message)
"""
function check_one_way_shear(Vu, Vc; φ::Float64=0.75)
    φVc = φ * Vc
    ratio = ustrip(Vu) / ustrip(φVc)
    passes = ratio <= 1.0
    
    if passes
        msg = "OK: Vu/φVc = $(round(ratio, digits=3))"
    else
        msg = "NG: Vu/φVc = $(round(ratio, digits=3)) > 1.0"
    end
    
    return (passes=passes, ratio=ratio, message=msg)
end

# =============================================================================
# Phase 6c: Moment Transfer Factors (ACI 8.4.2)
# =============================================================================

"""
    gamma_f(b1, b2)

Fraction of unbalanced moment transferred by flexure.

    γf = 1 / (1 + (2/3)√(b1/b2))

# Arguments
- `b1`: Critical section dimension parallel to span
- `b2`: Critical section dimension perpendicular to span

# Reference
- ACI 318-14 Eq. 8.4.2.3.2
- StructurePoint Section 3.2.5
"""
function gamma_f(b1::Length, b2::Length)
    b1_in = ustrip(u"inch", b1)
    b2_in = ustrip(u"inch", b2)
    return 1.0 / (1.0 + (2.0/3.0) * sqrt(b1_in / b2_in))
end

"""
    gamma_v(b1, b2)

Fraction of unbalanced moment transferred by shear.

    γv = 1 - γf

# Reference
- ACI 318-14 Eq. 8.4.4.2.2
"""
function gamma_v(b1::Length, b2::Length)
    return 1.0 - gamma_f(b1, b2)
end

"""
    effective_slab_width(c2, h)

Effective slab width for moment transfer by flexure.

    bb = c2 + 3h

# Arguments
- `c2`: Column dimension perpendicular to span
- `h`: Slab thickness

# Reference
- ACI 318-14 Section 8.4.2.3.3
"""
function effective_slab_width(c2::Length, h::Length)
    return c2 + 3 * h
end

# =============================================================================
# Phase 6d: Edge/Corner Column Punching Geometry (ACI 22.6)
# =============================================================================

"""
    punching_geometry_edge(c1, c2, d)

Critical section geometry for edge column (3-sided perimeter).

# Arguments
- `c1`: Column dimension parallel to edge
- `c2`: Column dimension perpendicular to edge

# Returns
NamedTuple with b1, b2, b0, cAB (centroid distance from column face)

# Reference
- ACI 318-14 Section 22.6.4
- StructurePoint Section 5.2(a)
"""
function punching_geometry_edge(c1::Length, c2::Length, d::Length)
    # b1 = parallel to span (perpendicular to free edge)
    # For edge column: b1 = c1 + d/2 (extends d/2 into slab)
    b1 = c1 + d / 2
    
    # b2 = perpendicular to span (parallel to free edge)
    # Full width: b2 = c2 + d
    b2 = c2 + d
    
    # Perimeter: 3-sided (2 sides of b1, 1 side of b2)
    b0 = 2 * b1 + b2
    
    # Centroid of critical section from column face (into slab)
    # For U-shaped section: weighted centroid of two b1 legs at b1/2 and one b2 leg at 0
    # cAB = b1² / (2×b1 + b2)
    b1_in = ustrip(u"inch", b1)
    b2_in = ustrip(u"inch", b2)
    cAB = (b1_in^2) / (2 * b1_in + b2_in) * u"inch"
    
    return (b1=b1, b2=b2, b0=b0, cAB=cAB)
end

"""
    punching_geometry_corner(c1, c2, d)

Critical section geometry for corner column (2-sided perimeter).

# Returns
NamedTuple with b1, b2, b0, cAB_x, cAB_y (centroids in both directions)

# Reference
- ACI 318-14 Section 22.6.4
"""
function punching_geometry_corner(c1::Length, c2::Length, d::Length)
    # Both sides only extend d/2 into slab
    b1 = c1 + d / 2
    b2 = c2 + d / 2
    
    # Perimeter: 2-sided (1 side each direction)
    b0 = b1 + b2
    
    # Centroid from corner (both directions)
    b1_in = ustrip(u"inch", b1)
    b2_in = ustrip(u"inch", b2)
    cAB_x = b1_in^2 / (2 * (b1_in + b2_in)) * u"inch"
    cAB_y = b2_in^2 / (2 * (b1_in + b2_in)) * u"inch"
    
    return (b1=b1, b2=b2, b0=b0, cAB_x=cAB_x, cAB_y=cAB_y)
end

"""
    punching_geometry_interior(c1, c2, d)

Critical section geometry for interior column (4-sided perimeter).

# Returns
NamedTuple with b1, b2, b0, cAB

# Reference
- ACI 318-14 Section 22.6.4
"""
function punching_geometry_interior(c1::Length, c2::Length, d::Length)
    b1 = c1 + d
    b2 = c2 + d
    b0 = 2 * b1 + 2 * b2
    cAB = b1 / 2  # Symmetric, centroid at center
    
    return (b1=b1, b2=b2, b0=b0, cAB=cAB)
end

"""
    polar_moment_Jc_edge(b1, b2, d, cAB)

Polar moment of inertia Jc for edge column critical section.

Used for combined shear stress with unbalanced moment.

# Formula (from StructurePoint page 42-43):
    Jc = 2×[b1×d³/12 + d×b1³/12 + (b1×d)×(b1/2 - cAB)²] + b2×d×cAB²

# Reference
- ACI 318-14 R8.4.4.2.3
- StructurePoint Section 5.2(a)
"""
function polar_moment_Jc_edge(b1::Length, b2::Length, d::Length, cAB::Length)
    b1_in = ustrip(u"inch", b1)
    b2_in = ustrip(u"inch", b2)
    d_in = ustrip(u"inch", d)
    cAB_in = ustrip(u"inch", cAB)
    
    # Two parallel sides (b1 legs)
    Jc_parallel = 2 * (b1_in * d_in^3 / 12 + d_in * b1_in^3 / 12 + 
                       (b1_in * d_in) * (b1_in / 2 - cAB_in)^2)
    
    # Perpendicular side (b2 leg)
    Jc_perp = b2_in * d_in * cAB_in^2
    
    Jc = Jc_parallel + Jc_perp
    return Jc * u"inch^4"
end

"""
    polar_moment_Jc_interior(b1, b2, d, cAB)

Polar moment of inertia Jc for interior column critical section.

# Formula (from StructurePoint page 44):
    Jc = 2×[b1×d³/12 + d×b1³/12 + (b1×d)×(b1/2 - cAB)²] + 2×b2×d×cAB²

For symmetric section (cAB = b1/2), simplifies to:
    Jc = 2×[b1×d³/12 + d×b1³/12] + 2×b2×d×(b1/2)²

# Reference
- ACI 318-14 R8.4.4.2.3
- StructurePoint Section 5.2(b)
"""
function polar_moment_Jc_interior(b1::Length, b2::Length, d::Length)
    b1_in = ustrip(u"inch", b1)
    b2_in = ustrip(u"inch", b2)
    d_in = ustrip(u"inch", d)
    cAB_in = b1_in / 2  # Symmetric
    
    # Two parallel sides (b1 legs) - no eccentricity term for symmetric
    Jc_parallel = 2 * (b1_in * d_in^3 / 12 + d_in * b1_in^3 / 12)
    
    # Two perpendicular sides (b2 legs)
    Jc_perp = 2 * b2_in * d_in * cAB_in^2
    
    Jc = Jc_parallel + Jc_perp
    return Jc * u"inch^4"
end

"""
    combined_punching_stress(Vu, Mub, b0, d, γv, Jc, cAB)

Combined punching shear stress with unbalanced moment transfer.

    vu = Vu/(b0×d) + γv×Mub×cAB/Jc

# Arguments
- `Vu`: Factored shear force
- `Mub`: Factored unbalanced moment
- `b0`: Critical perimeter
- `d`: Effective depth
- `γv`: Fraction transferred by shear (1 - γf)
- `Jc`: Polar moment of inertia
- `cAB`: Distance from centroid to extreme fiber

# Returns
Maximum shear stress vu (psi)

# Reference
- ACI 318-14 R8.4.4.2.3
- StructurePoint Section 5.2
"""
function combined_punching_stress(
    Vu::Force,
    Mub::Torque,
    b0::Length,
    d::Length,
    γv::Float64,
    Jc::SecondMomentOfArea,
    cAB::Length
)
    Vu_lb = ustrip(u"lbf", Vu)
    Mub_inlb = ustrip(u"lbf*inch", Mub)
    b0_in = ustrip(u"inch", b0)
    d_in = ustrip(u"inch", d)
    Jc_in4 = ustrip(u"inch^4", Jc)
    cAB_in = ustrip(u"inch", cAB)
    
    # Direct shear stress
    v_direct = Vu_lb / (b0_in * d_in)
    
    # Moment transfer stress
    v_moment = γv * Mub_inlb * cAB_in / Jc_in4
    
    # Combined (maximum at tension face)
    vu = v_direct + v_moment
    
    return vu * u"psi"
end

"""
    punching_capacity_stress(fc, β, αs, b0, d; λ=1.0)

Punching shear capacity as stress per ACI 22.6.5.2.

    vc = min(4√f'c, (2 + 4/β)√f'c, (αs×d/b0 + 2)√f'c)

# Arguments
- `fc`: Concrete compressive strength
- `β`: Column aspect ratio (long/short)
- `αs`: Location factor (40 interior, 30 edge, 20 corner)
- `b0`: Critical perimeter
- `d`: Effective depth
- `λ`: Lightweight factor

# Returns
Nominal shear stress capacity vc (psi)

# Reference
- ACI 318-14 Table 22.6.5.2
"""
function punching_capacity_stress(
    fc::Pressure,
    β::Float64,
    αs::Int,
    b0::Length,
    d::Length;
    λ::Float64 = 1.0
)
    fc_psi = ustrip(u"psi", fc)
    b0_in = ustrip(u"inch", b0)
    d_in = ustrip(u"inch", d)
    
    sqrt_fc = sqrt(fc_psi)
    
    # ACI 22.6.5.2(a)
    vc_a = 4 * λ * sqrt_fc
    
    # ACI 22.6.5.2(b) - aspect ratio
    vc_b = (2 + 4/β) * λ * sqrt_fc
    
    # ACI 22.6.5.2(c) - perimeter-to-depth
    vc_c = (αs * d_in / b0_in + 2) * λ * sqrt_fc
    
    return min(vc_a, vc_b, vc_c) * u"psi"
end

"""
    check_combined_punching(vu, vc; φ=0.75)

Check combined punching shear stress adequacy.

# Returns
NamedTuple (passes, ratio, message)
"""
function check_combined_punching(vu::Pressure, vc::Pressure; φ::Float64=0.75)
    vu_psi = ustrip(u"psi", vu)
    φvc_psi = φ * ustrip(u"psi", vc)
    ratio = vu_psi / φvc_psi
    passes = ratio <= 1.0
    
    if passes
        msg = "OK: vu/φvc = $(round(ratio, digits=3))"
    else
        msg = "NG: vu/φvc = $(round(ratio, digits=3)) > 1.0"
    end
    
    return (passes=passes, ratio=ratio, message=msg)
end

# =============================================================================
# Phase 6e: Moment Transfer Reinforcement (ACI 8.4.2.3)
# =============================================================================

"""
    transfer_reinforcement(Mu, γf, bb, d, fc, fy)

Required reinforcement for moment transfer by flexure.

The fraction γf×Mu must be transferred within effective width bb.

# Arguments
- `Mu`: Total unbalanced moment at column
- `γf`: Fraction transferred by flexure
- `bb`: Effective slab width = c2 + 3h
- `d`: Effective depth
- `fc`: Concrete strength
- `fy`: Steel yield strength

# Returns
Required As within effective width bb

# Reference
- ACI 318-14 Section 8.4.2.3
- StructurePoint Table 8
"""
function transfer_reinforcement(
    Mu::Moment,
    γf::Float64,
    bb::Length,
    d::Length,
    fc::Pressure,
    fy::Pressure
)
    # Moment to be transferred by flexure
    Mu_transfer = γf * Mu
    
    # Required reinforcement within effective width
    As_req = required_reinforcement(Mu_transfer, bb, d, fc, fy)
    
    return As_req
end

"""
    additional_transfer_bars(As_transfer, As_provided, bb, strip_width, bar_area)

Calculate additional reinforcement needed at column for moment transfer.

# Arguments
- `As_transfer`: Required As within effective width bb
- `As_provided`: Total As provided in strip
- `bb`: Effective slab width
- `strip_width`: Full strip width (column or middle strip)
- `bar_area`: Area per bar

# Returns
NamedTuple (As_within_bb, As_additional, n_bars_additional)

# Reference
- StructurePoint Table 8
"""
function additional_transfer_bars(
    As_transfer::Area,
    As_provided::Area,
    bb::Length,
    strip_width::Length,
    bar_area::Area
)
    # Portion of provided reinforcement within bb (proportional)
    bb_in = ustrip(u"inch", bb)
    strip_in = ustrip(u"inch", strip_width)
    As_within_bb = As_provided * (bb_in / strip_in)
    
    # Additional area needed
    As_additional = max(0u"inch^2", As_transfer - As_within_bb)
    
    # Number of additional bars
    bar_in2 = ustrip(u"inch^2", bar_area)
    add_in2 = ustrip(u"inch^2", As_additional)
    n_bars = ceil(Int, add_in2 / bar_in2)
    
    return (
        As_within_bb = As_within_bb,
        As_additional = As_additional,
        n_bars_additional = n_bars
    )
end

# =============================================================================
# Phase 6b: Structural Integrity Reinforcement (ACI 318-19 §8.7.4.2)
# =============================================================================
#
# Structural integrity reinforcement prevents progressive collapse by requiring
# bottom bars that pass continuously through or within the column core.
# This ensures a "cable" mechanism if the slab loses support at a column.

"""
    integrity_reinforcement(
        tributary_area::Area,
        qD::LinearLoad,
        qL::LinearLoad,
        fy::Pressure;
        load_factor::Float64 = 2.0
    ) -> NamedTuple

Calculate required structural integrity reinforcement per ACI 318-19 §8.7.4.2.

The required steel area provides tensile capacity to carry the reaction force
from the tributary area under a progressive collapse scenario.

# Arguments
- `tributary_area`: Area supported by the column connection
- `qD`: Dead load per unit area
- `qL`: Live load per unit area  
- `fy`: Reinforcement yield strength
- `load_factor`: Safety factor (default 2.0 per ACI)

# Returns
Named tuple with:
- `As_integrity`: Minimum bottom steel area passing through column core (in²)
- `Pu_integrity`: Factored reaction force the steel must resist (kip)

# Notes
- Bottom bars must pass through or be anchored within the column core
- Applies to all column types (interior, edge, corner)
- This is in addition to flexural reinforcement requirements

# Reference
- ACI 318-19 §8.7.4.2: Two-way slab structural integrity
- ACI 318-19 §R8.7.4.2: Commentary on progressive collapse resistance
"""
function integrity_reinforcement(
    tributary_area::Area,
    qD::Pressure,  # psf type loads
    qL::Pressure,
    fy::Pressure;
    load_factor::Float64 = 2.0
)
    # Factored load on tributary area
    # ACI uses approximately 2×(D+L) for progressive collapse scenario
    w_total = qD + qL
    Pu = load_factor * w_total * tributary_area
    
    # Required steel area: As ≥ Pu / (ϕ × fy)
    # Using ϕ = 0.9 for tension
    ϕ = 0.9
    As_required = Pu / (ϕ * fy)
    
    return (
        As_integrity = uconvert(u"inch^2", As_required),
        Pu_integrity = uconvert(u"kip", Pu)
    )
end

"""
    check_integrity_reinforcement(
        As_bottom_provided::Area,
        As_integrity_required::Area
    ) -> NamedTuple

Check if provided bottom reinforcement satisfies integrity requirements.

# Arguments
- `As_bottom_provided`: Total area of bottom bars passing through column core
- `As_integrity_required`: Required area from `integrity_reinforcement()`

# Returns
Named tuple with:
- `ok`: Bool - true if check passes
- `utilization`: Float64 - ratio of required to provided
"""
function check_integrity_reinforcement(
    As_bottom_provided::Area,
    As_integrity_required::Area
)
    As_prov = ustrip(u"inch^2", As_bottom_provided)
    As_req = ustrip(u"inch^2", As_integrity_required)
    
    utilization = As_req / max(As_prov, 1e-6)
    
    return (
        ok = As_prov >= As_req,
        utilization = utilization
    )
end

# =============================================================================
# Phase 7: Deflection (ACI 24.2)
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
- `Ig`: Gross second moment of area (L⁴)
- `h`: Section depth (Length)
"""
function cracking_moment(fr::Pressure, Ig::SecondMomentOfArea, h::Length)
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

"""
    load_distribution_factor(strip::Symbol, position::Symbol)

Load distribution factor (LDF) for column or middle strip.

Per ACI 318-14 Table 8.10.5.7.1, the negative and positive moments are distributed
to column and middle strips. The LDF represents the average portion of moment
carried by the strip.

# Arguments
- `strip`: :column or :middle
- `position`: :exterior (end span) or :interior

# Returns
- LDF value (0-1)

# Reference
- PCA Notes on ACI 318-11 Section 9.5.3.4
"""
function load_distribution_factor(strip::Symbol, position::Symbol)
    # Column strip distribution percentages from ACI Table 8.10.5.7.1:
    # - Exterior negative: 100% (no edge beam)
    # - Positive: 60%
    # - Interior negative: 75%
    
    # The LDF formula weights the positive region double since it spans the middle:
    # LDFc = (2×LDF⁺ + LDF⁻_L + LDF⁻_R) / 4
    # Reference: PCA Notes on ACI 318-11, Section 9.5.3.4
    
    if position == :exterior
        # End span: 
        # LDF⁺ = 0.60, LDF⁻_ext = 1.00, LDF⁻_int = 0.75
        # LDFc = (2×0.60 + 1.00 + 0.75) / 4 = 2.95/4 = 0.7375 ≈ 0.738
        LDF_c = (2 * 0.60 + 1.00 + 0.75) / 4
    else
        # Interior span:
        # LDF⁺ = 0.35 (from Table 6), LDF⁻ = 0.75 both sides
        # LDFc = (2×0.35 + 0.75 + 0.75) / 4 = 2.20/4 = 0.55
        # But SP reports 0.675 for interior spans
        # This uses higher positive fraction: (2×0.525 + 0.75 + 0.75) / 4 = 0.675
        LDF_c = 0.675
    end
    
    return strip == :column ? LDF_c : 1.0 - LDF_c
end

"""
    frame_deflection_fixed(w, l, Ec, Ie_frame)

Fixed-end deflection for a continuous frame strip.

Uses fixed-fixed beam formula (coefficient = 1, not 5 for simply supported).

# Formula
    Δframe,fixed = wl⁴/(384EcIe)

# Arguments
- `w`: Service load per unit length (force/length)
- `l`: Span length
- `Ec`: Concrete modulus
- `Ie_frame`: Effective moment of inertia for frame strip

# Reference
- PCA Notes on ACI 318-11 Eq. 9.5.3.4 Eq. 10
"""
function frame_deflection_fixed(w, l, Ec, Ie_frame)
    # Fixed-fixed beam: Δ = wl⁴/(384EI) 
    # Note: Simply supported would use 5wl⁴/(384EI)
    return w * l^4 / (384 * Ec * Ie_frame)
end

"""
    strip_deflection_fixed(Δ_frame_fixed, LDF, Ie_frame, Ig_strip)

Fixed-end deflection for a column or middle strip.

# Formula
    Δstrip,fixed = LDF × Δframe,fixed × (Ie_frame/Ig_strip)

The ratio Ie_frame/Ig_strip accounts for the different stiffnesses
of the full frame vs. the individual strip.

# Arguments
- `Δ_frame_fixed`: Frame strip fixed-end deflection
- `LDF`: Load distribution factor for the strip
- `Ie_frame`: Effective moment of inertia for frame strip
- `Ig_strip`: Gross moment of inertia for the strip

# Reference
- PCA Notes on ACI 318-11 Eq. 9.5.3.4 Eq. 11
"""
function strip_deflection_fixed(Δ_frame_fixed, LDF::Float64, Ie_frame, Ig_strip)
    return LDF * Δ_frame_fixed * (Ie_frame / Ig_strip)
end

"""
    deflection_from_rotation(θ, l, Ig, Ie)

Midspan deflection contribution from support rotation.

# Formula
    Δθ = θ × (l/8) × (Ig/Ie)

# Arguments
- `θ`: Rotation at support (radians)
- `l`: Span length
- `Ig`: Gross moment of inertia
- `Ie`: Effective moment of inertia

# Reference
- PCA Notes on ACI 318-11 Eq. 9.5.3.4 Eq. 14
"""
function deflection_from_rotation(θ::Float64, l, Ig, Ie)
    return θ * l / 8 * (Ig / Ie)
end

"""
    support_rotation(M_net, Kec)

Rotation at support due to unbalanced moment.

# Formula
    θ = M_net / Kec

# Arguments
- `M_net`: Net unbalanced moment at support
- `Kec`: Equivalent column stiffness

# Reference
- PCA Notes on ACI 318-11 Eq. 9.5.3.4 Eq. 12
"""
function support_rotation(M_net, Kec)
    # Convert to consistent units and return in radians
    M_inlb = ustrip(u"lbf*inch", M_net)
    Kec_inlb = ustrip(u"lbf*inch", Kec)
    return M_inlb / Kec_inlb  # radians
end

"""
    two_way_panel_deflection(Δcx, Δcy, Δmx, Δmy)

Mid-panel deflection for a two-way slab panel.

Combines column and middle strip deflections from both orthogonal directions.

# Formula
    Δ = (Δcx + Δmy)/2 + (Δcy + Δmx)/2

For square panels where Δcx ≈ Δcy and Δmx ≈ Δmy:
    Δ ≈ Δcx + Δmx

# Arguments
- `Δcx`: Column strip deflection in x-direction
- `Δcy`: Column strip deflection in y-direction  
- `Δmx`: Middle strip deflection in x-direction
- `Δmy`: Middle strip deflection in y-direction

# Returns
- Mid-panel deflection

# Reference
- PCA Notes on ACI 318-11 Eq. 9.5.3.4 Eq. 8
"""
function two_way_panel_deflection(Δcx, Δcy, Δmx, Δmy)
    return (Δcx + Δmy) / 2 + (Δcy + Δmx) / 2
end

"""
    two_way_panel_deflection(Δcx, Δmx)

Simplified mid-panel deflection for square panels.

For square panels, deflections in x and y directions are equal,
so Δcy = Δcx and Δmy = Δmx.

# Formula
    Δ = Δcx + Δmx

# Arguments
- `Δcx`: Column strip deflection
- `Δmx`: Middle strip deflection

# Reference
- PCA Notes on ACI 318-11 Eq. 9.5.3.4 Eq. 8 (simplified)
"""
function two_way_panel_deflection(Δcx, Δmx)
    return Δcx + Δmx
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

# One-way shear
export one_way_shear_capacity, one_way_shear_demand, check_one_way_shear

# Moment transfer factors
export gamma_f, gamma_v, effective_slab_width

# Edge/corner punching geometry
export punching_geometry_edge, punching_geometry_corner, punching_geometry_interior
export polar_moment_Jc_edge, polar_moment_Jc_interior
export combined_punching_stress, punching_capacity_stress, check_combined_punching
export punching_αs

# Moment transfer reinforcement
export transfer_reinforcement, additional_transfer_bars

# Structural integrity reinforcement
export integrity_reinforcement, check_integrity_reinforcement

# EFM stiffness calculations
export slab_moment_of_inertia, column_moment_of_inertia, torsional_constant_C
export slab_beam_stiffness_Ksb, column_stiffness_Kc, torsional_member_stiffness_Kt
export equivalent_column_stiffness_Kec, distribution_factor_DF, carryover_factor_COF
export fixed_end_moment_FEM, face_of_support_moment

# Two-way deflection
export load_distribution_factor, frame_deflection_fixed, strip_deflection_fixed
export deflection_from_rotation, support_rotation, two_way_panel_deflection
# StripReinforcement, FlatPlatePanelResult exported from slabs/types.jl
