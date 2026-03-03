# =============================================================================
# Rebar Direction — Reinforcement Axis Resolution & Moment Rotation
# =============================================================================
#
# When the user specifies a `rebar_direction` angle (radians from global x),
# the reinforcement axis may differ from the span axis.  This module provides:
#
#   1. `_resolve_rebar_axis` — returns the unit direction for moment projection,
#      using the user's rebar direction if set, otherwise the span axis.
#
#   2. `_rotate_moments_to_rebar!` — rotates the per-element moment tensors
#      (Mxx, Myy, Mxy) from the global frame into the rebar frame.  After
#      rotation, Mxx is the moment about the primary rebar axis and Myy is
#      about the transverse rebar axis.
#
# The rotation is a standard 2D tensor transformation:
#   M'xx = Mxx cos²θ + Myy sin²θ + 2 Mxy cosθ sinθ
#   M'yy = Mxx sin²θ + Myy cos²θ − 2 Mxy cosθ sinθ
#   M'xy = (Myy − Mxx) cosθ sinθ + Mxy (cos²θ − sin²θ)
#
# where θ is the angle from global-x to the rebar direction.
#
# =============================================================================

"""
    _resolve_rebar_axis(method::FEA, span_axis) -> NTuple{2, Float64}

Return the unit direction vector for moment projection / integration.

If `method.rebar_direction` is set, returns `(cos(θ), sin(θ))`.
Otherwise returns the normalized span axis.
"""
function _resolve_rebar_axis(method::FEA, span_axis::NTuple{2, Float64})
    if !isnothing(method.rebar_direction)
        θ = method.rebar_direction
        return (cos(θ), sin(θ))
    else
        ax_len = hypot(span_axis...)
        return ax_len > 1e-9 ? (span_axis[1] / ax_len, span_axis[2] / ax_len) :
                               (1.0, 0.0)
    end
end

"""
    _resolve_rebar_axes(method::FEA, span_axis) -> (ax_prime, ay_prime)

Return the primary (x') and secondary (y') reinforcement axis unit vectors.

If `method.rebar_direction` is set, uses that angle for x' and angle+π/2 for y'.
Otherwise uses the span axis for x' and its perpendicular for y'.
"""
function _resolve_rebar_axes(method::FEA, span_axis::NTuple{2, Float64})
    if !isnothing(method.rebar_direction)
        θ = method.rebar_direction
        ax_prime = (cos(θ), sin(θ))
        ay_prime = (cos(θ + π/2), sin(θ + π/2))
    else
        ax_len = hypot(span_axis...)
        if ax_len > 1e-9
            ax_prime = (span_axis[1] / ax_len, span_axis[2] / ax_len)
        else
            ax_prime = (1.0, 0.0)
        end
        ay_prime = (-ax_prime[2], ax_prime[1])
    end
    return (ax_prime, ay_prime)
end

"""
    _rotate_moments_to_rebar(Mxx, Myy, Mxy, rebar_ax, rebar_ay)
        -> (Mxx', Myy', Mxy')

Rotate global bending moments to the reinforcement axes (x', y').
Standard 2D moment tensor transformation.

- `rebar_ax`: unit vector for x' (primary rebar direction)
- `rebar_ay`: unit vector for y' (secondary rebar direction)
"""
function _rotate_moments_to_rebar(Mxx::Float64, Myy::Float64, Mxy::Float64,
                                  rebar_ax::NTuple{2, Float64},
                                  rebar_ay::NTuple{2, Float64})
    cx, sx = rebar_ax
    cy, sy = rebar_ay
    Mxx_p = Mxx * cx^2 + Myy * sx^2 + 2 * Mxy * cx * sx
    Myy_p = Mxx * cy^2 + Myy * sy^2 + 2 * Mxy * cy * sy
    Mxy_p = Mxx * cx * cy + Myy * sx * sy + Mxy * (cx * sy + sx * cy)
    return (Mxx_p, Myy_p, Mxy_p)
end

"""
    _project_moment_onto_axis(Mxx, Myy, Mxy, axis) -> Float64

Project the moment tensor onto a single axis direction.
Returns M_n = Mxx·ax² + Myy·ay² + 2·Mxy·ax·ay.
"""
function _project_moment_onto_axis(Mxx::Float64, Myy::Float64, Mxy::Float64,
                                   axis::NTuple{2, Float64})
    ax, ay = axis
    return Mxx * ax^2 + Myy * ay^2 + 2 * Mxy * ax * ay
end

"""
    _project_moment_no_torsion(Mxx, Myy, axis) -> Float64

Project the moment tensor onto an axis direction, **ignoring Mxy**.
Returns M_n = Mxx·ax² + Myy·ay².

This is intentionally unconservative — it drops the twisting moment
contribution.  Use only as a baseline to quantify the effect of Mxy.
See Parsekian (2018) and Shin & Alemdar (2020).
"""
function _project_moment_no_torsion(Mxx::Float64, Myy::Float64,
                                    axis::NTuple{2, Float64})
    ax, ay = axis
    return Mxx * ax^2 + Myy * ay^2
end

"""
    _rotate_moments_to_rebar!(cache, θ)

Rotate all per-element moment tensors in `cache.element_data` from the
global frame into the rebar frame defined by angle `θ` (radians from global x).

After this call, `ed.Mxx` is the bending moment about the primary rebar axis,
`ed.Myy` about the transverse axis, and `ed.Mxy` is the twisting moment in
the rebar frame.

This is a standard 2D stress/moment tensor rotation (Mohr's transformation):
```
  M'xx = Mxx cos²θ + Myy sin²θ + 2 Mxy cosθ sinθ
  M'yy = Mxx sin²θ + Myy cos²θ − 2 Mxy cosθ sinθ
  M'xy = (Myy − Mxx) cosθ sinθ + Mxy (cos²θ − sin²θ)
```

**Note**: This mutates `cache.element_data` in place.  If you need the
global-frame moments later, save them first or re-run `_precompute_element_data!`.
"""
function _rotate_moments_to_rebar!(cache::FEAModelCache, θ::Float64)
    c = cos(θ)
    s = sin(θ)
    c2 = c * c
    s2 = s * s
    cs = c * s

    @inbounds for ed in cache.element_data
        Mxx = ed.Mxx
        Myy = ed.Myy
        Mxy = ed.Mxy

        ed.Mxx = Mxx * c2 + Myy * s2 + 2 * Mxy * cs
        ed.Myy = Mxx * s2 + Myy * c2 - 2 * Mxy * cs
        ed.Mxy = (Myy - Mxx) * cs + Mxy * (c2 - s2)
    end

    # Also rotate the D/L case moments if they exist
    if !isempty(cache.element_data_D)
        cache.element_data_D = [
            ElementMoments(
                m.Mxx * c2 + m.Myy * s2 + 2 * m.Mxy * cs,
                m.Mxx * s2 + m.Myy * c2 - 2 * m.Mxy * cs,
                (m.Myy - m.Mxx) * cs + m.Mxy * (c2 - s2),
            ) for m in cache.element_data_D
        ]
    end
    if !isempty(cache.element_data_L)
        cache.element_data_L = [
            ElementMoments(
                m.Mxx * c2 + m.Myy * s2 + 2 * m.Mxy * cs,
                m.Mxx * s2 + m.Myy * c2 - 2 * m.Mxy * cs,
                (m.Myy - m.Mxx) * cs + m.Mxy * (c2 - s2),
            ) for m in cache.element_data_L
        ]
    end
end
