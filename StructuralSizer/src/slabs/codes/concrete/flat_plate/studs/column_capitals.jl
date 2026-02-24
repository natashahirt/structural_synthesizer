# =============================================================================
# Column Capital Design for Punching Shear — ACI 318-11 §13.1.2
# =============================================================================
#
# A column capital is a flared enlargement of the column head. The effective
# support area is defined by the intersection of the slab soffit with the
# largest right circular cone / right pyramid / tapered wedge whose surfaces
# are within the column and capital, oriented ≤ 45° to the column axis.
#
# 45° Rule (§13.1.2):
#   With a capital projection h_cap below the slab, the effective column
#   dimensions increase by 2·h_cap in each direction (one h_cap per side,
#   from the 45° flare):
#     c1_eff = c1 + 2·h_cap
#     c2_eff = c2 + 2·h_cap
#
# The critical section is then at d/2 from the effective column face,
# using the standard ACI §11.11.1.2 geometry.
#
# =============================================================================

using Unitful
using Unitful: @u_str
using Asap: Length, Pressure, Force, Moment, Area

"""
    design_column_capital(vu, fc, d, h, position, c1, c2;
                          λ=1.0, φ=0.75, Vu=nothing, Mub=nothing,
                          max_projection=nothing, h_increment=0.5u"inch")

Design a column capital to resolve punching shear failure.

Iteratively increases the capital projection `h_cap` until punching is
satisfied or `max_projection` is reached.

# Algorithm
1. Start with `h_cap = h_increment`
2. Effective column dims: `c1_eff = c1 + 2·h_cap`, `c2_eff = c2 + 2·h_cap` (45° rule)
3. Critical section at `d/2` from effective column face → compute `b0_eff`
4. Re-check punching with new `b0_eff` (slab `d` unchanged)
5. If still failing, increase `h_cap` and repeat

# Key Difference from Shear Caps
- Capital enlarges the *effective column* but does NOT increase `d`
- Shear cap increases both `d` (locally) and moves the critical section

# Arguments
- `vu`: Factored shear stress demand
- `fc`: Concrete compressive strength
- `d`: Effective slab depth
- `h`: Total slab thickness
- `position`: Column position (:interior, :edge, :corner)
- `c1`, `c2`: Column dimensions

# Keyword Arguments
- `λ`: Lightweight concrete factor (default: 1.0)
- `φ`: Strength reduction factor (default: 0.75)
- `Vu`: Factored shear force (for combined stress check; optional)
- `Mub`: Unbalanced moment (for combined stress check; optional)
- `max_projection`: Maximum capital depth (default: min(c1,c2), i.e. capital
  projection ≤ shorter column dimension)
- `h_increment`: Capital depth increment (default: 0.5")

# Returns
`ColumnCapitalDesign` struct

# Reference
- ACI 318-11 §13.1.2
"""
function design_column_capital(
    vu::Pressure,
    fc::Pressure,
    d::Length,
    h::Length,
    position::Symbol,
    c1::Length,
    c2::Length;
    λ::Float64 = 1.0,
    φ::Float64 = 0.75,
    Vu::Union{Force, Nothing} = nothing,
    Mub::Union{Moment, Nothing} = nothing,
    max_projection::Union{Length, Nothing} = nothing,
    h_increment::Length = 0.5u"inch"
)
    # Default max projection: shorter column dimension (practical limit)
    max_proj = isnothing(max_projection) ? min(c1, c2) : max_projection
    vu_psi = ustrip(u"psi", vu)

    h_cap = h_increment
    while h_cap <= max_proj
        # 45° rule: effective column dimensions
        c1_eff = c1 + 2 * h_cap
        c2_eff = c2 + 2 * h_cap

        # Critical section at d/2 from effective column face (standard geometry)
        geom = punching_geometry(c1_eff, c2_eff, d; position=position)
        b0_eff = geom.b0

        # Punching capacity at the effective critical section
        c1_eff_in = ustrip(u"inch", c1_eff)
        c2_eff_in = ustrip(u"inch", c2_eff)
        β = max(c1_eff_in, c2_eff_in) / max(min(c1_eff_in, c2_eff_in), 1.0)
        αs = punching_αs(position)
        vc = punching_capacity_stress(fc, β, αs, b0_eff, d; λ=λ)
        φvc_psi = φ * ustrip(u"psi", vc)

        # Compute demand at the enlarged critical section
        if !isnothing(Vu) && !isnothing(Mub)
            γv_val = gamma_v(geom.b1, geom.b2)
            cAB = hasproperty(geom, :cAB) ? geom.cAB :
                   max(geom.cAB_x, geom.cAB_y)
            Jc = if position == :interior
                polar_moment_Jc_interior(geom.b1, geom.b2, d)
            elseif position == :edge
                polar_moment_Jc_edge(geom.b1, geom.b2, d, cAB)
            else
                polar_moment_Jc_edge(geom.b1, geom.b2, d, cAB) / 2
            end
            vu_eff = combined_punching_stress(Vu, Mub, b0_eff, d, γv_val, Jc, cAB)
            vu_eff_psi = ustrip(u"psi", vu_eff)
        else
            # Scale demand by perimeter ratio (d unchanged for capitals)
            b0_orig = punching_geometry(c1, c2, d; position=position).b0
            vu_eff_psi = vu_psi * ustrip(u"inch", b0_orig) / ustrip(u"inch", b0_eff)
        end

        ratio = vu_eff_psi / φvc_psi
        if ratio <= 1.0
            return ColumnCapitalDesign(
                required = true,
                h_cap = uconvert(u"inch", h_cap),
                c1_eff = uconvert(u"inch", c1_eff),
                c2_eff = uconvert(u"inch", c2_eff),
                b0_eff = uconvert(u"inch", b0_eff),
                ratio = ratio,
                ok = true
            )
        end

        h_cap += h_increment
    end

    # Max projection reached — return best attempt
    c1_eff = c1 + 2 * max_proj
    c2_eff = c2 + 2 * max_proj
    geom = punching_geometry(c1_eff, c2_eff, d; position=position)
    b0_eff = geom.b0

    β = max(ustrip(u"inch", c1_eff), ustrip(u"inch", c2_eff)) /
        max(min(ustrip(u"inch", c1_eff), ustrip(u"inch", c2_eff)), 1.0)
    αs = punching_αs(position)
    vc = punching_capacity_stress(fc, β, αs, b0_eff, d; λ=λ)
    φvc_psi = φ * ustrip(u"psi", vc)

    if !isnothing(Vu) && !isnothing(Mub)
        γv_val = gamma_v(geom.b1, geom.b2)
        cAB = hasproperty(geom, :cAB) ? geom.cAB : max(geom.cAB_x, geom.cAB_y)
        Jc = if position == :interior
            polar_moment_Jc_interior(geom.b1, geom.b2, d)
        elseif position == :edge
            polar_moment_Jc_edge(geom.b1, geom.b2, d, cAB)
        else
            polar_moment_Jc_edge(geom.b1, geom.b2, d, cAB) / 2
        end
        vu_eff = combined_punching_stress(Vu, Mub, b0_eff, d, γv_val, Jc, cAB)
        vu_eff_psi = ustrip(u"psi", vu_eff)
    else
        b0_orig = punching_geometry(c1, c2, d; position=position).b0
        vu_eff_psi = vu_psi * ustrip(u"inch", b0_orig) / ustrip(u"inch", b0_eff)
    end

    ratio = vu_eff_psi / φvc_psi
    return ColumnCapitalDesign(
        required = true,
        h_cap = uconvert(u"inch", max_proj),
        c1_eff = uconvert(u"inch", c1_eff),
        c2_eff = uconvert(u"inch", c2_eff),
        b0_eff = uconvert(u"inch", b0_eff),
        ratio = ratio,
        ok = ratio <= 1.0
    )
end

"""
    check_punching_with_capital(capital::ColumnCapitalDesign)

Check punching shear adequacy with a column capital.

# Returns
NamedTuple (ok, ratio, message)
"""
function check_punching_with_capital(capital::ColumnCapitalDesign)
    if !capital.required
        return (ok=false, ratio=Inf, message="Column capital not designed")
    end
    msg = capital.ok ?
        "OK (capital h=$(capital.h_cap)): ratio=$(round(capital.ratio, digits=3))" :
        "NG (capital h=$(capital.h_cap)): ratio=$(round(capital.ratio, digits=3)) > 1.0"
    return (ok=capital.ok, ratio=capital.ratio, message=msg)
end
