# ==============================================================================
# Construction Stage Checks — AISC 360-16 Section I3.1b
# ==============================================================================
# When temporary shores are not used, the steel section alone must support
# all loads applied prior to the concrete attaining 75% of fc'.

"""
    check_construction(section::ISymmSection, material, Mu_const, Vu_const;
                       Lb_const, Cb_const=1.0, ϕ_b=0.9, ϕ_v=1.0) -> NamedTuple

Construction-stage check per AISC I3.1b: steel section alone must resist
all loads applied before the concrete reaches 75% of fc'.

Uses Chapter F (flexure) and Chapter G (shear) for the bare steel section.
`Lb_const` is the unbraced length during construction — typically the full beam
span unless temporary bracing or deck attachment provides lateral support.

# Returns
- `flexure_ok`:  `ϕMn_steel ≥ Mu_const`
- `shear_ok`:    `ϕVn_steel ≥ Vu_const`
- `ϕMn_steel`:   Design flexural strength of steel section alone
- `ϕVn_steel`:   Design shear strength of steel section alone
"""
function check_construction(section::ISymmSection, material, Mu_const, Vu_const;
                             Lb_const, Cb_const=1.0, ϕ_b=0.9, ϕ_v=1.0)
    # Flexure — Chapter F with construction-stage unbraced length
    ϕMn_steel = get_ϕMn(section, material; Lb=Lb_const, Cb=Cb_const, axis=:strong, ϕ=ϕ_b)

    # Shear — Chapter G
    ϕVn_steel = get_ϕVn(section, material; axis=:strong, ϕ=ϕ_v)

    flexure_ok = ϕMn_steel >= Mu_const
    shear_ok   = ϕVn_steel >= Vu_const

    return (; flexure_ok, shear_ok, ϕMn_steel, ϕVn_steel)
end
