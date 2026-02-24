# =============================================================================
# Shear Cap Design for Punching Shear — ACI 318-11 §13.2.6 / §11.11.1.2(b)
# =============================================================================
#
# A shear cap is a localized projection below the slab at the column.
# It increases the effective depth d and moves the critical section to
# d/2 from the cap edge, enlarging b0.
#
# Geometry (§13.2.6):
#   The cap must extend horizontally from the column face at least the
#   projection depth:  extent ≥ h_cap.
#
# Critical section (§11.11.1.2(b)):
#   Located at d_eff/2 from the edge of the shear cap, where
#   d_eff = d_slab + h_cap.
#
# =============================================================================

using Unitful
using Unitful: @u_str
using Asap: Length, Pressure, Force, Moment, Area

"""
    design_shear_cap(vu, fc, d, h, position, c1, c2;
                     λ=1.0, φ=0.75, Vu=nothing, Mub=nothing,
                     max_projection=nothing, h_increment=0.25u"inch")

Design a shear cap to resolve punching shear failure at a column.

Iteratively increases the cap projection `h_cap` until punching is satisfied
or `max_projection` is reached.

# Algorithm
1. Start with `h_cap = h_increment` (typically 0.25")
2. Compute effective depth: `d_eff = d + h_cap`
3. Cap extent from column face: `extent = h_cap` (ACI §13.2.6 minimum)
4. Effective column dimensions at cap edge: `c1_cap = c1 + 2·extent`, `c2_cap = c2 + 2·extent`
5. Critical section at `d_eff/2` from cap edge → compute `b0_cap`
6. Re-check punching with new `d_eff` and `b0_cap`
7. If still failing, increase `h_cap` and repeat

# Arguments
- `vu`: Factored shear stress demand (psi)
- `fc`: Concrete compressive strength
- `d`: Effective slab depth (without cap)
- `h`: Total slab thickness
- `position`: Column position (:interior, :edge, :corner)
- `c1`, `c2`: Column dimensions

# Keyword Arguments
- `λ`: Lightweight concrete factor (default: 1.0)
- `φ`: Strength reduction factor (default: 0.75)
- `Vu`: Factored shear force (for combined stress check; optional)
- `Mub`: Unbalanced moment (for combined stress check; optional)
- `max_projection`: Maximum cap depth (default: h, i.e. cap ≤ slab thickness)
- `h_increment`: Cap depth increment (default: 0.25")

# Returns
`ShearCapDesign` struct

# Reference
- ACI 318-11 §13.2.6, §11.11.1.2(b)
"""
function design_shear_cap(
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
    h_increment::Length = 0.25u"inch"
)
    max_proj = isnothing(max_projection) ? h : max_projection
    vu_psi = ustrip(u"psi", vu)

    h_cap = h_increment
    while h_cap <= max_proj
        d_eff = d + h_cap

        # ACI §13.2.6: extent ≥ h_cap from each column face
        extent = h_cap

        # Effective column dimensions at the cap edge
        c1_cap = c1 + 2 * extent
        c2_cap = c2 + 2 * extent

        # Critical section at d_eff/2 from cap edge (§11.11.1.2(b))
        geom = punching_geometry(c1_cap, c2_cap, d_eff; position=position)
        b0_cap = geom.b0

        # Punching capacity at the cap critical section
        c1_cap_in = ustrip(u"inch", c1_cap)
        c2_cap_in = ustrip(u"inch", c2_cap)
        β = max(c1_cap_in, c2_cap_in) / max(min(c1_cap_in, c2_cap_in), 1.0)
        αs = punching_αs(position)
        vc = punching_capacity_stress(fc, β, αs, b0_cap, d_eff; λ=λ)
        φvc_psi = φ * ustrip(u"psi", vc)

        # Compute demand at the enlarged critical section
        if !isnothing(Vu) && !isnothing(Mub)
            # Full combined stress check with unbalanced moment
            γv_val = gamma_v(geom.b1, geom.b2)
            cAB = hasproperty(geom, :cAB) ? geom.cAB :
                   max(geom.cAB_x, geom.cAB_y)
            Jc = if position == :interior
                polar_moment_Jc_interior(geom.b1, geom.b2, d_eff)
            elseif position == :edge
                polar_moment_Jc_edge(geom.b1, geom.b2, d_eff, cAB)
            else
                polar_moment_Jc_edge(geom.b1, geom.b2, d_eff, cAB) / 2
            end
            vu_cap = combined_punching_stress(Vu, Mub, b0_cap, d_eff, γv_val, Jc, cAB)
            vu_cap_psi = ustrip(u"psi", vu_cap)
        else
            # Scale demand by perimeter and depth ratio (conservative approximation)
            # Original vu was at (b0_orig × d); new section is (b0_cap × d_eff)
            b0_orig = punching_geometry(c1, c2, d; position=position).b0
            vu_cap_psi = vu_psi * ustrip(u"inch", b0_orig) * ustrip(u"inch", d) /
                         (ustrip(u"inch", b0_cap) * ustrip(u"inch", d_eff))
        end

        ratio = vu_cap_psi / φvc_psi
        if ratio <= 1.0
            return ShearCapDesign(
                required = true,
                h_cap = uconvert(u"inch", h_cap),
                extent = uconvert(u"inch", extent),
                d_eff = uconvert(u"inch", d_eff),
                b0_cap = uconvert(u"inch", b0_cap),
                ratio = ratio,
                ok = true
            )
        end

        h_cap += h_increment
    end

    # Max projection reached — return best attempt
    d_eff = d + max_proj
    extent = max_proj
    c1_cap = c1 + 2 * extent
    c2_cap = c2 + 2 * extent
    geom = punching_geometry(c1_cap, c2_cap, d_eff; position=position)
    b0_cap = geom.b0

    β = max(ustrip(u"inch", c1_cap), ustrip(u"inch", c2_cap)) /
        max(min(ustrip(u"inch", c1_cap), ustrip(u"inch", c2_cap)), 1.0)
    αs = punching_αs(position)
    vc = punching_capacity_stress(fc, β, αs, b0_cap, d_eff; λ=λ)
    φvc_psi = φ * ustrip(u"psi", vc)

    if !isnothing(Vu) && !isnothing(Mub)
        γv_val = gamma_v(geom.b1, geom.b2)
        cAB = hasproperty(geom, :cAB) ? geom.cAB : max(geom.cAB_x, geom.cAB_y)
        Jc = if position == :interior
            polar_moment_Jc_interior(geom.b1, geom.b2, d_eff)
        elseif position == :edge
            polar_moment_Jc_edge(geom.b1, geom.b2, d_eff, cAB)
        else
            polar_moment_Jc_edge(geom.b1, geom.b2, d_eff, cAB) / 2
        end
        vu_cap = combined_punching_stress(Vu, Mub, b0_cap, d_eff, γv_val, Jc, cAB)
        vu_cap_psi = ustrip(u"psi", vu_cap)
    else
        b0_orig = punching_geometry(c1, c2, d; position=position).b0
        vu_cap_psi = vu_psi * ustrip(u"inch", b0_orig) * ustrip(u"inch", d) /
                     (ustrip(u"inch", b0_cap) * ustrip(u"inch", d_eff))
    end

    ratio = vu_cap_psi / φvc_psi
    return ShearCapDesign(
        required = true,
        h_cap = uconvert(u"inch", max_proj),
        extent = uconvert(u"inch", max_proj),
        d_eff = uconvert(u"inch", d_eff),
        b0_cap = uconvert(u"inch", b0_cap),
        ratio = ratio,
        ok = ratio <= 1.0
    )
end

"""
    check_punching_with_shear_cap(vu, cap::ShearCapDesign; φ=0.75)

Check punching shear adequacy with a shear cap.

# Returns
NamedTuple (ok, ratio, message)
"""
function check_punching_with_shear_cap(cap::ShearCapDesign)
    if !cap.required
        return (ok=false, ratio=Inf, message="Shear cap not designed")
    end
    msg = cap.ok ? "OK (shear cap h=$(cap.h_cap)): ratio=$(round(cap.ratio, digits=3))" :
                   "NG (shear cap h=$(cap.h_cap)): ratio=$(round(cap.ratio, digits=3)) > 1.0"
    return (ok=cap.ok, ratio=cap.ratio, message=msg)
end
