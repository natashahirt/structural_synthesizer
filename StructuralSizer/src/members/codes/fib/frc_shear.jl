# ==============================================================================
# Fiber Reinforced Concrete Shear Capacity — fib Model Code 2010
# ==============================================================================
# Shear capacity of FRC sections per fib MC2010 §7.7.3.2.2, Eq. (7.7-5).
# Reference: Wongsittikan (2024), Eqs. 2.13–2.15.
#
# Linear model for ultimate fiber tensile strength (fib §5.6.4, Eq. 5.6-3):
#   f_Fts = 0.45 × fR1
#   f_Ftuk = f_Fts − (wu / CMOD3) × (f_Fts − 0.5 × fR3 + 0.2 × fR1)
#   where wu = 1.5 mm, CMOD3 = 2.5 mm
#
# NOTE: The original Pixelframe.jl (and thesis) used the linear model with
# both fR1 and fR3. The rigid-plastic model (fR3/3) is a simpler alternative
# but less accurate for typical fiber dosages.
#
# Design shear resistance (fib §7.7.3.2.2, Eq. 7.7-5, all stresses in MPa):
#   V_Rd,F = [ (0.18/γ_c) · k · (100 · ρ_l · (1 + 7.5 · f_Ftuk/f_ctk) · f_ck)^(1/3)
#              + 0.15 · σ_cp ] · A_shear
#
# For rectangular sections: A_shear = b_w · d.
# For non-rectangular sections (PixelFrame Y-shape): A_shear = A_c · shear_ratio.
#
# Size effect factor (fib §7.7.3.2.2):
#   k = 1 + √(200/d) ≤ 2.0       (d in mm)
#
# Minimum shear resistance (fib §7.7.3.2.2, Eq. 7.7-6):
#   V_Rd,Fmin = (v_min + 0.15 · σ_cp) · A_shear
#   v_min = 0.035 · k^(3/2) · f_ck^(1/2)
#
# Concrete tensile strength: f_ct = 0.17√fc′ (ACI convention, per thesis).
# ==============================================================================

using Unitful

"""
    frc_shear_capacity(; bw, d, fc′, fR1, fR3, ρ_l, σ_cp, γ_c) -> Force

Shear capacity of a fiber-reinforced concrete section per fib MC2010 §7.7.3.2.2.
Rectangular section variant — uses bw × d as the shear area.

Returns `max(V_Rd,F, V_Rd,Fmin)` — the main formula (Eq. 7.7-5) floored by
the minimum shear resistance (Eq. 7.7-6).

# Arguments
- `bw`: Section web width
- `d`: Effective depth (to tendon centroid)
- `fc′`: Concrete compressive strength (characteristic, f_ck)
- `fR1`: Residual flexural tensile strength at CMOD=0.5mm [MPa bare number]
- `fR3`: Residual flexural tensile strength at CMOD=2.5mm [MPa bare number]
- `ρ_l`: Longitudinal reinforcement ratio (A_s / (bw × d))
- `σ_cp`: Average compressive stress from prestress (= f_pe × A_s / A_g)
- `γ_c`: Partial safety factor for concrete (default 1.0, thesis convention)

# Returns
Design shear capacity `V_Rd,F` in force units (N).

# Reference
- fib Model Code 2010, §7.7.3.2.2, Eqs. (7.7-5) and (7.7-6)
- fib Model Code 2010, §5.6.4, Eq. (5.6-3) — linear model
- Wongsittikan (2024), Eqs. 2.13–2.15
"""
function frc_shear_capacity(;
    bw::Length,
    d::Length,
    fc′::Pressure,
    fR1::Real,          # MPa (bare number, per fib convention)
    fR3::Real,          # MPa (bare number, per fib convention)
    ρ_l::Real,
    σ_cp::Pressure,
    γ_c::Real = 1.0,
)
    d_mm = ustrip(u"mm", d)
    bw_mm = ustrip(u"mm", bw)
    A_shear_mm2 = bw_mm * d_mm

    _frc_shear_core(;
        d_mm, A_shear_mm2,
        fc′_MPa = ustrip(u"MPa", fc′),
        fR1_MPa = Float64(fR1),
        fR3_MPa = Float64(fR3),
        ρ_l = Float64(ρ_l),
        σ_cp_MPa = ustrip(u"MPa", σ_cp),
        γ_c = Float64(γ_c),
    )
end

"""
    _frc_shear_core(; d_mm, A_shear_mm2, fc′_MPa, fR1_MPa, fR3_MPa, ρ_l, σ_cp_MPa, γ_c) -> Force

Core shear capacity computation. Works with any shear area (rectangular or polygon-based).

Uses the **linear model** for f_Ftuk (fib MC2010 §5.6.4, Eq. 5.6-3):
  f_Fts = 0.45 × fR1
  f_Ftuk = f_Fts − (wu/CMOD3) × (f_Fts − 0.5×fR3 + 0.2×fR1)

All arguments are bare Float64 in mm / MPa.
"""
function _frc_shear_core(;
    d_mm::Float64,
    A_shear_mm2::Float64,
    fc′_MPa::Float64,
    fR1_MPa::Float64,
    fR3_MPa::Float64,
    ρ_l::Float64,
    σ_cp_MPa::Float64,
    γ_c::Float64 = 1.0,
)
    # Ultimate fiber tensile strength — linear model (fib Eq. 5.6-3)
    # f_Fts = 0.45 × fR1
    # f_Ftuk = f_Fts − (wu/CMOD3) × (f_Fts − 0.5×fR3 + 0.2×fR1)
    # where wu = 1.5 mm, CMOD3 = 2.5 mm
    f_Fts = 0.45 * fR1_MPa
    wu = 1.5
    CMOD3 = 2.5
    f_Ftuk = max(f_Fts - wu / CMOD3 * (f_Fts - 0.5 * fR3_MPa + 0.2 * fR1_MPa), 0.0)

    # Concrete tensile strength (ACI convention, per thesis): f_ct = 0.17√fc′ [MPa]
    f_ct = 0.17 * sqrt(fc′_MPa)

    # Size effect factor (fib §7.7.3.2.2), d in mm
    k = min(1.0 + sqrt(200.0 / max(d_mm, 1.0)), 2.0)

    # Fiber contribution factor
    fiber_factor = 1.0 + 7.5 * f_Ftuk / max(f_ct, 1e-6)

    # Main shear capacity — fib Eq. (7.7-5), result in N
    V_Rd_F = ((0.18 / γ_c) * k * cbrt(100.0 * ρ_l * fiber_factor * fc′_MPa) +
               0.15 * σ_cp_MPa) * A_shear_mm2

    # Minimum shear resistance — fib Eq. (7.7-6)
    v_min = 0.035 * k^1.5 * sqrt(fc′_MPa)
    V_Rd_Fmin = (v_min + 0.15 * σ_cp_MPa) * A_shear_mm2

    return max(V_Rd_F, V_Rd_Fmin) * u"N"
end

"""
    frc_shear_capacity(s::PixelFrameSection; E_s, γ_c, shear_ratio) -> Force

Compute FRC shear capacity for a PixelFrame Y-section.

For the Y-shaped PixelFrame section, the shear area is NOT bw × d (rectangular).
Instead, per the original Pixelframe.jl: `A_shear = A_c × shear_ratio`.

The effective depth `d` for the size-effect factor `k` uses `L_px` (arm length),
consistent with the original Pixelframe.jl where `d = L`.

# Arguments
- `s`: PixelFrameSection
- `E_s`: Tendon elastic modulus (unused, kept for API consistency)
- `γ_c`: fib partial safety factor for concrete (default 1.0)
- `shear_ratio`: Fraction of concrete area effective in shear (default 1.0)

# Reference
Pixelframe.jl `get_shear_capacity_fib2010` (Keith JL)
"""
function frc_shear_capacity(s::PixelFrameSection;
                            E_s::Pressure = 200.0u"GPa",
                            γ_c::Real = 1.0,
                            shear_ratio::Real = 1.0)
    fc′ = s.material.fc′
    fR1 = s.material.fR1
    fR3 = s.material.fR3
    A_c_mm2 = s.section.area  # polygon area [mm²]
    A_s_mm2 = ustrip(u"mm^2", s.A_s)
    f_pe_MPa = ustrip(u"MPa", s.f_pe)

    # Shear area: polygon area × shear_ratio (not bw × d)
    A_shear_mm2 = A_c_mm2 * Float64(shear_ratio)

    # Effective depth for k-factor: L_px (arm length), per original Pixelframe.jl
    d_mm = ustrip(u"mm", s.L_px)

    # Reinforcement ratio: A_ps / A_shear
    ρ_l = A_s_mm2 / A_shear_mm2

    # Average prestress on concrete section
    # Original: σ_cp = min(0.33 × fpe × Aps / Ac, 0.2 × fc′)
    σ_cp_MPa = clamp(
        0.33 * f_pe_MPa * A_s_mm2 / A_c_mm2,
        0.0,
        0.2 * ustrip(u"MPa", fc′),
    )

    _frc_shear_core(;
        d_mm,
        A_shear_mm2,
        fc′_MPa = ustrip(u"MPa", fc′),
        fR1_MPa = Float64(fR1),
        fR3_MPa = Float64(fR3),
        ρ_l,
        σ_cp_MPa,
        γ_c = Float64(γ_c),
    )
end
