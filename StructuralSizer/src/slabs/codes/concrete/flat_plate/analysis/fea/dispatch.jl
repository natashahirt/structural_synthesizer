# =============================================================================
# FEA Dispatch — Routes Design Approach + Knobs to Extraction Functions
# =============================================================================
#
# The new dispatch system uses the FEA struct's knobs:
#   - design_approach:   :frame, :strip, :area
#   - moment_transform:  :projection, :wood_armer, :no_torsion
#   - field_smoothing:   :element, :nodal
#   - cut_method:        :delta_band, :isoparametric
#   - iso_alpha:         Float64 ∈ [0, 1]
#   - sign_treatment:    :signed, :separate_faces
#
# Legacy `strip_design` symbols are mapped to these knobs in the FEA
# constructor (see slabs/types.jl).
#
# All strip-level methods return the same NamedTuple signature:
#   (M_neg_ext_cs, M_neg_int_cs, M_pos_cs,
#    M_neg_ext_ms, M_neg_int_ms, M_pos_ms)
# in N·m (bare Float64).
# =============================================================================

"""
    _dispatch_fea_strip_extraction(method::FEA, cache, struc, slab, columns,
                                    span_axis; verbose=false) -> NamedTuple

Dispatch to the appropriate FEA strip moment extraction method based on the
FEA struct's knobs.

# Routing Logic (for `design_approach = :strip`)

| moment_transform     | field_smoothing | cut_method      | Function                              |
|----------------------|-----------------|-----------------|---------------------------------------|
| :projection/:no_tor  | :element        | :delta_band     | `_extract_fea_strip_moments`          |
| :projection/:no_tor  | :nodal          | :isoparametric  | `_extract_nodal_strip_moments`        |
| :projection/:no_tor  | :nodal          | :delta_band     | `_extract_nodal_strip_moments` (δ-fb) |
| :wood_armer          | any             | any             | `_extract_wood_armer_strip_moments`   |

For `design_approach = :frame`, this function is not called — the frame-level
extraction path in `run.jl` handles it directly.

For `design_approach = :area`, see `_extract_area_design_moments` (Step 8).
"""
function _dispatch_fea_strip_extraction(
    method::FEA,
    cache::FEAModelCache,
    struc, slab, columns,
    span_axis::NTuple{2, Float64};
    rebar_axis::Union{Nothing, NTuple{2, Float64}} = nothing,
    torsion_discount::Union{Nothing, NamedTuple} = nothing,
    verbose::Bool = false,
)
    mt = method.moment_transform
    fs = method.field_smoothing
    cm = method.cut_method
    incl_torsion = mt != :no_torsion
    sign_treat = method.sign_treatment

    # ── Wood–Armer always uses its own dedicated function ──
    if mt == :wood_armer
        return _extract_wood_armer_strip_moments(
            cache, struc, slab, columns, span_axis;
            rebar_axis=rebar_axis, torsion_discount=torsion_discount,
            verbose=verbose)
    end

    # ── Projection-based methods (includes :no_torsion) ──
    if fs == :nodal
        # Nodal-smoothed section cuts (isoparametric or δ-band fallback)
        return _extract_nodal_strip_moments(
            cache, struc, slab, columns, span_axis;
            rebar_axis=rebar_axis, iso_alpha=method.iso_alpha,
            include_torsion=incl_torsion, sign_treatment=sign_treat,
            verbose=verbose)
    else
        # Element-centroid δ-band integration (default/fastest)
        return _extract_fea_strip_moments(
            cache, struc, slab, columns, span_axis;
            rebar_axis=rebar_axis, include_torsion=incl_torsion,
            verbose=verbose)
    end
end

# =============================================================================
# Legacy Dispatch (backward compatibility)
# =============================================================================

"""
    _dispatch_fea_strip_extraction(strip_design::Symbol, cache, struc, slab,
                                    columns, span_axis; verbose=false)

Legacy dispatch using the old `strip_design` symbol.  Maps to the new
knob-based dispatch via a temporary FEA struct.

This method is kept for backward compatibility with code that still passes
`strip_design` as a bare symbol.  New code should pass the full `method::FEA`.
"""
function _dispatch_fea_strip_extraction(
    strip_design::Symbol,
    cache::FEAModelCache,
    struc, slab, columns,
    span_axis::NTuple{2, Float64};
    verbose::Bool = false,
)
    # Create a temporary FEA with the legacy strip_design mapping
    method = FEA(strip_design=strip_design)
    return _dispatch_fea_strip_extraction(
        method, cache, struc, slab, columns, span_axis; verbose=verbose)
end
