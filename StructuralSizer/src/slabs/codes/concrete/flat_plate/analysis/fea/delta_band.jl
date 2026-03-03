# =============================================================================
# δ-Band Moment Integration
# =============================================================================

"""
    _integrate_at(element_data, tri_indices, pos, ax, δ; include_torsion=true)

Integrate span-direction moment across a δ-band at `pos` using
precomputed per-element data.  Returns bare N·m.

Tensor projection projects global span axis `ax` into each element's local
frame via the cached LCS axes.

When `include_torsion=false`, the Mxy cross-term is dropped from the
projection (intentionally unconservative baseline).
"""
function _integrate_at(
    element_data::Vector{FEAElementData},
    tri_indices::Vector{Int},
    pos::NTuple{2,Float64},
    ax::NTuple{2,Float64},
    δ::Float64;
    include_torsion::Bool = true,
)
    s_eval = ax[1] * pos[1] + ax[2] * pos[2]
    half_δ = δ / 2
    Mn_A = 0.0   # N·m·m accumulator
    @inbounds for k in tri_indices
        ed = element_data[k]
        abs(ax[1] * ed.cx + ax[2] * ed.cy - s_eval) > half_δ && continue
        axl = (ax[1]*ed.ex[1] + ax[2]*ed.ex[2], ax[1]*ed.ey[1] + ax[2]*ed.ey[2])
        Mn = ed.Mxx*axl[1]^2 + ed.Myy*axl[2]^2
        if include_torsion
            Mn += 2*ed.Mxy*axl[1]*axl[2]
        end
        Mn_A += Mn * ed.area
    end
    return Mn_A / δ
end

# =============================================================================
# Strip-Filtered Moment Integration
# =============================================================================

"""
    _integrate_at_subset(element_data, tri_subset, pos, span_axis, δ;
                         include_torsion=true)

Same as `_integrate_at` but operates on a pre-filtered subset of triangle
indices (e.g. only column-strip or only middle-strip elements).
Returns bare N·m.
"""
function _integrate_at_subset(
    element_data::Vector{FEAElementData},
    tri_subset::Vector{Int},
    pos::NTuple{2,Float64},
    span_axis::NTuple{2,Float64},
    δ::Float64;
    include_torsion::Bool = true,
)
    s_eval = span_axis[1] * pos[1] + span_axis[2] * pos[2]
    half_δ = δ / 2
    Mn_A = 0.0
    @inbounds for k in tri_subset
        ed = element_data[k]
        abs(span_axis[1] * ed.cx + span_axis[2] * ed.cy - s_eval) > half_δ && continue
        axl = (span_axis[1]*ed.ex[1] + span_axis[2]*ed.ex[2],
               span_axis[1]*ed.ey[1] + span_axis[2]*ed.ey[2])
        Mn = ed.Mxx*axl[1]^2 + ed.Myy*axl[2]^2
        if include_torsion
            Mn += 2*ed.Mxy*axl[1]*axl[2]
        end
        Mn_A += Mn * ed.area
    end
    return Mn_A / δ
end
