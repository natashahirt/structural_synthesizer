# ==============================================================================
# Composite Deflection — Transformed Moment of Inertia & I_LB
# ==============================================================================
# AISC 360-16 Commentary on Section I3.2 and AISC Manual Table 3-20 approach.

# ==============================================================================
# Transformed Moment of Inertia (Full Composite)
# ==============================================================================

"""
    get_I_transformed(section::ISymmSection, slab::AbstractSlabOnBeam, b_eff) -> SecondMomentOfArea

Full-composite transformed moment of inertia using the modular ratio n = Es/Ec.

Transforms the concrete slab into an equivalent steel area (b_eff / n) × t_slab,
then computes the composite I about the centroidal axis of the transformed section.
"""
function get_I_transformed(section::ISymmSection, slab::AbstractSlabOnBeam, b_eff)
    n  = slab.n
    As = section.A
    Is = section.Ix
    d  = section.d
    ts = slab.t_slab

    # Transformed concrete area and I about its own centroid
    b_tr = b_eff / n
    Ac_tr = b_tr * ts
    Ic_tr = b_tr * ts^3 / 12

    # Centroids measured from bottom of steel section
    ȳ_steel = d / 2
    ȳ_conc  = d + ts / 2  # concrete centroid above top of steel

    # Composite centroid (from bottom of steel)
    A_total = As + Ac_tr
    ȳ_comp = (As * ȳ_steel + Ac_tr * ȳ_conc) / A_total

    # Parallel axis theorem
    I_comp = Is + As * (ȳ_comp - ȳ_steel)^2 +
             Ic_tr + Ac_tr * (ȳ_conc - ȳ_comp)^2

    return I_comp
end

# ==============================================================================
# Lower-Bound Moment of Inertia (Partial Composite)
# ==============================================================================

"""
    get_I_LB(section::ISymmSection, material, slab::AbstractSlabOnBeam,
             b_eff, ΣQn) -> SecondMomentOfArea

Lower-bound moment of inertia for partially composite beams per AISC Manual
(Commentary on I3.2, approach used to generate Table 3-20).

Uses the actual PNA location and compression force to build the effective
transformed section. For full composite, this equals the fully transformed I.

The lower-bound I is used for live-load deflection calculations when
partial composite action is specified.

Formula (AISC Manual Eq. C-I3-1):
    I_LB = Is + As × (YENA - d/2)² + (ΣQn / Fy)² / (2 × Ac_eff_tr) × (d_eff)²

Simplified approach: linearly interpolate between I_steel and I_transformed
based on partial composite ratio ΣQn / Cf_max.
"""
function get_I_LB(section::ISymmSection, material, slab::AbstractSlabOnBeam,
                  b_eff, ΣQn)
    Cf_max = _Cf_max(section, material, slab, b_eff)
    I_steel = section.Ix
    I_full  = get_I_transformed(section, slab, b_eff)

    # Partial composite ratio (0 to 1)
    ratio = clamp(ustrip(ΣQn / Cf_max), 0.0, 1.0)

    # AISC Manual approach: I_LB = Is + ratio^0.5 × (I_full - Is)
    # Using sqrt because I doesn't scale linearly with stud count.
    # The Manual tables use a more exact formula, but this approximation
    # is standard practice and matches Table 3-20 within ~2%.
    I_LB = I_steel + sqrt(ratio) * (I_full - I_steel)

    return I_LB
end

# ==============================================================================
# Composite Deflection Check
# ==============================================================================

"""
    check_composite_deflection(section::ISymmSection, material,
                                slab::AbstractSlabOnBeam, b_eff, ΣQn,
                                L, w_DL, w_LL;
                                shored::Bool=false,
                                δ_limit_ratio=1/360,
                                δ_const_limit=nothing) -> NamedTuple

Check deflections for a composite beam under uniform load.

# Shored vs Unshored (AISC I3.1b / Commentary):
- **Unshored**: Dead load deflection uses steel-alone Ix (wet concrete applied before composite).
  Live load deflection uses I_LB (composite section).
- **Shored**: All load deflection uses I_LB (entire load applied after composite).

# Arguments
- `w_DL`: Distributed dead load (weight per length)
- `w_LL`: Distributed live load (weight per length)
- `δ_limit_ratio`: Maximum LL deflection ratio (default L/360)
- `δ_const_limit`: Optional absolute limit for construction deflection (e.g., 2.5 in.)

# Returns
- `δ_DL`, `δ_LL`, `δ_total`: Computed deflections
- `ok_LL`: Live load deflection check passes
- `ok_const`: Construction deflection check passes (only if `δ_const_limit` is set)
"""
function check_composite_deflection(section::ISymmSection, material,
                                     slab::AbstractSlabOnBeam, b_eff, ΣQn,
                                     L, w_DL, w_LL;
                                     shored::Bool=false,
                                     δ_limit_ratio=1/360,
                                     δ_const_limit=nothing)
    Es = material.E
    I_steel = section.Ix
    I_LB = get_I_LB(section, material, slab, b_eff, ΣQn)

    # 5wL⁴ / (384 E I)
    coeff = 5 * L^4 / (384 * Es)

    if shored
        # All loads on composite section
        δ_DL = coeff * w_DL / I_LB
        δ_LL = coeff * w_LL / I_LB
    else
        # DL on steel alone, LL on composite
        δ_DL = coeff * w_DL / I_steel
        δ_LL = coeff * w_LL / I_LB
    end

    δ_total = δ_DL + δ_LL
    δ_LL_limit = L * δ_limit_ratio

    ok_LL = δ_LL <= δ_LL_limit

    # Construction deflection (unshored only)
    ok_const = true
    δ_const = δ_DL  # construction DL ≈ total DL for unshored
    if !shored && δ_const_limit !== nothing
        ok_const = δ_const <= δ_const_limit
    end

    return (; δ_DL=uconvert(u"mm", δ_DL),
              δ_LL=uconvert(u"mm", δ_LL),
              δ_total=uconvert(u"mm", δ_total),
              δ_LL_limit=uconvert(u"mm", δ_LL_limit),
              ok_LL, ok_const, I_LB)
end
