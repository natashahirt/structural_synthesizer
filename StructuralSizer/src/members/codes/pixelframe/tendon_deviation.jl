# ==============================================================================
# Tendon Deviation Axial Force — Computation
# ==============================================================================
# Computes the axial clamping force at deviator points for friction-based
# shear transfer between PixelFrame pixels.
#
# At each deviator (pixel boundary), the post-tensioning tendon changes
# direction. The horizontal component of the tendon force provides axial
# compression that helps transfer shear via friction (μ_s ≈ 0.3).
#
# If the horizontal PT component alone is insufficient to provide the
# required normal force for friction (N = V_max / μ_s), an additional
# clamping force is needed — this is the "tendon deviation axial force"
# reported for connection design.
#
# The TendonDeviationResult struct is defined in pixel_design.jl.
#
# Reference: Wongsittikan (2024) — designPixelframe.jl, lines 474–536
# ==============================================================================

"""
    pf_tendon_deviation_force(design, V_max; d_ps_support, f_ps, μ_s) -> TendonDeviationResult

Compute the tendon deviation axial force for connection design.

At the support deviator, the tendon changes direction from `d_ps_support`
(eccentricity at the support pixel) to `d_ps` (eccentricity at the next pixel).
The tendon angle creates a horizontal force component that provides axial
compression for friction-based shear transfer.

# Arguments
- `design`: `PixelFrameDesign` — provides section geometry, tendon properties, and pixel length
- `V_max`: Maximum shear demand along the member (Unitful force)

# Keyword Arguments
- `d_ps_support`: Tendon eccentricity at the support face [Unitful length].
  Default: `0.0u"mm"` (tendon at centroid at supports, per typical EPT profile).
  For a straight tendon, set equal to `design.section.d_ps`.
- `f_ps`: Tendon stress at ultimate [Unitful pressure].
  Default: computed from `pf_flexural_capacity` of the governing section.
- `μ_s`: Static friction coefficient for pixel-to-pixel shear transfer.
  Default: `0.3` (concrete-to-concrete friction per Wongsittikan 2024).

# Returns
`TendonDeviationResult` with the tendon angle, horizontal PT component,
required friction force, and additional clamping force.

# Physics
```
    θ = atan((d_ps_next − d_ps_support) / pixel_length)
    P_horizontal = A_ps × f_ps × cos(θ)
    N_friction = V_max / μ_s
    N_additional = N_friction − P_horizontal
```

If `N_additional < 0`, the PT alone provides sufficient clamping.

# Reference
Wongsittikan (2024) — `designPixelframe.jl`, lines 474–536
"""
function pf_tendon_deviation_force(
    design::PixelFrameDesign,
    V_max;
    d_ps_support = 0.0u"mm",
    f_ps::Union{Nothing, Unitful.Pressure} = nothing,
    μ_s::Real = 0.3,
)
    sec = design.section
    L_px = design.pixel_length

    # Tendon area and stress
    A_s = sec.A_s
    if f_ps === nothing
        fl = pf_flexural_capacity(sec)
        f_ps = fl.f_ps
    end

    # Tendon eccentricity at the next pixel (constant in our model)
    d_ps_next = sec.d_ps

    # Tendon angle at the support deviator
    # θ = atan(Δd_ps / pixel_length)
    Δd_ps = ustrip(u"mm", d_ps_next) - ustrip(u"mm", d_ps_support)
    L_px_mm = ustrip(u"mm", L_px)
    θ = atan(Δd_ps / L_px_mm)

    # Horizontal component of PT force
    P_horizontal = uconvert(u"kN", A_s * f_ps * cos(θ))

    # Required normal force for friction-based shear transfer
    V_max_kN = uconvert(u"kN", V_max)
    N_friction = V_max_kN / μ_s

    # Additional clamping force needed
    N_additional = N_friction - P_horizontal

    TendonDeviationResult(θ, P_horizontal, V_max_kN, N_friction, N_additional, Float64(μ_s))
end
