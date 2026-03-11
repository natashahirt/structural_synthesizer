# ==============================================================================
# Effective Slab Width — AISC 360-16 Section I3.1a
# ==============================================================================

"""
    get_b_eff(slab::AbstractSlabOnBeam, L_beam) -> Length

Effective width of the concrete slab for composite action per AISC 360-16 §I3.1a.

The effective width is the sum of the effective widths on each side of the beam
centerline, each of which shall not exceed:
  (a) one-eighth of the beam span, center-to-center of supports
  (b) one-half the distance to the centerline of the adjacent beam
  (c) the distance to the edge of the slab

Returns a length in the same units as `L_beam`.
"""
function get_b_eff(slab::AbstractSlabOnBeam, L_beam)
    b_left  = _effective_half_width(L_beam, slab.beam_spacing_left,  slab.edge_dist_left)
    b_right = _effective_half_width(L_beam, slab.beam_spacing_right, slab.edge_dist_right)
    return b_left + b_right
end

"""
Effective width for one side of the beam centerline.

Limits (AISC I3.1a):
  (a) L_beam / 8
  (b) beam_spacing / 2
  (c) edge_dist (if applicable)
"""
function _effective_half_width(L_beam, beam_spacing, edge_dist)
    b = min(L_beam / 8, beam_spacing / 2)
    if edge_dist !== nothing
        b = min(b, edge_dist)
    end
    return b
end
