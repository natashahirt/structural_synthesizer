# =============================================================================
# Flat Plate Reinforcement Design
# =============================================================================
#
# Strip reinforcement design per ACI 318-11 §13.6.4 (transverse distribution).
#
# Note: This file is included in StructuralSizer, inheriting Logging, etc.
# =============================================================================

# =============================================================================
# Strip Reinforcement Design
# =============================================================================

"""
    _design_strips_from_moments(M_neg_ext_cs, M_neg_int_cs, M_pos_cs,
                                M_neg_ext_ms, M_neg_int_ms, M_pos_ms,
                                l2, d, fc, fy, h; label="", verbose=false)

Shared core: given six Unitful design moments (column-strip and middle-strip
for exterior negative, positive, and interior negative), design reinforcement
for all strip locations.

Returns the standard named tuple
`(column_strip_width, column_strip_reinf, middle_strip_width,
  middle_strip_reinf, section_adequate)`.
"""
function _design_strips_from_moments(
    M_neg_ext_cs, M_neg_int_cs, M_pos_cs,
    M_neg_ext_ms, M_neg_int_ms, M_pos_ms,
    l2, d, fc, fy, h;
    label::String = "",
    verbose::Bool = false,
)
    cs_width = l2 / 2  # Column strip = half of panel width
    ms_width = l2 / 2  # Middle strip = half of panel width

    column_strip_reinf = StripReinforcement[
        design_single_strip(:ext_neg, M_neg_ext_cs, cs_width, d, fc, fy, h),
        design_single_strip(:pos,     M_pos_cs,     cs_width, d, fc, fy, h),
        design_single_strip(:int_neg, M_neg_int_cs, cs_width, d, fc, fy, h),
    ]

    middle_strip_reinf = StripReinforcement[
        design_single_strip(:pos,     M_pos_ms,     ms_width, d, fc, fy, h),
        design_single_strip(:int_neg, M_neg_int_ms, ms_width, d, fc, fy, h),
    ]

    all_strips = vcat(column_strip_reinf, middle_strip_reinf)
    section_adequate = all(sr.section_adequate for sr in all_strips)

    if verbose
        tag = isempty(label) ? "Column strip" : "Column strip ($label)"
        @debug tag width=cs_width
        for sr in column_strip_reinf
            @debug "  $(sr.location)" Mu=uconvert(kip*u"ft", sr.Mu) As_reqd=sr.As_reqd As_provided=sr.As_provided adequate=sr.section_adequate
        end
        tag_ms = isempty(label) ? "Middle strip" : "Middle strip ($label)"
        @debug tag_ms width=ms_width
        for sr in middle_strip_reinf
            @debug "  $(sr.location)" Mu=uconvert(kip*u"ft", sr.Mu) As_reqd=sr.As_reqd As_provided=sr.As_provided adequate=sr.section_adequate
        end
    end

    return (
        column_strip_width = cs_width,
        column_strip_reinf = column_strip_reinf,
        middle_strip_width = ms_width,
        middle_strip_reinf = middle_strip_reinf,
        section_adequate   = section_adequate,
    )
end

"""
    design_strip_reinforcement(moment_results, columns, h, d, fc, fy, cover; verbose=false)

Design strip reinforcement using ACI 8.10.5 transverse distribution.

Design moments are derived from `moment_results.column_moments` — the
per-column moment vector populated by DDM, EFM, or FEA.  ACI transverse
distribution factors are applied per-column and then enveloped:

- Exterior columns: 100% of `column_moments[i]` → column strip
- Interior columns: 75% / 25% → column strip / middle strip
- Positive: 60% / 40% → column strip / middle strip

# Arguments
- `moment_results`: MomentAnalysisResult (column_moments is the primary data)
- `columns`: Vector of column structs with `.position` field
- `h`: Slab thickness
- `d`: Effective depth
- `fc`, `fy`: Material strengths
- `cover`: Clear cover

# Returns
Named tuple with column_strip and middle_strip reinforcement vectors.
"""
function design_strip_reinforcement(moment_results, columns, h, d, fc, fy, cover; verbose=false)
    l2 = moment_results.l2

    # ACI 8.10.5 — derive design moments from per-column data
    zero_M = zero(moment_results.M0)
    M_neg_ext_cs = zero_M   # exterior → 100% column strip
    M_neg_int_cs = zero_M   # interior → 75% column strip
    M_neg_int_ms = zero_M   # interior → 25% middle strip

    for (i, col) in enumerate(columns)
        m = moment_results.column_moments[i]
        if col.position == :interior
            M_neg_int_cs = max(M_neg_int_cs, 0.75 * m)
            M_neg_int_ms = max(M_neg_int_ms, 0.25 * m)
        else
            M_neg_ext_cs = max(M_neg_ext_cs, 1.00 * m)
        end
    end

    M_pos_cs = 0.60 * moment_results.M_pos
    M_pos_ms = 0.40 * moment_results.M_pos

    # Exterior negative middle strip is zero (100% goes to column strip)
    M_neg_ext_ms = zero_M

    return _design_strips_from_moments(
        M_neg_ext_cs, M_neg_int_cs, M_pos_cs,
        M_neg_ext_ms, M_neg_int_ms, M_pos_ms,
        l2, d, fc, fy, h;
        label="ACI fractions", verbose=verbose,
    )
end

"""
    design_strip_reinforcement_fea(fea_strip_moments, l2, h, d, fc, fy, cover; verbose=false)

Design strip reinforcement using FEA-derived strip moments (direct integration).

Instead of applying ACI 8.10.5 tabulated fractions to frame-level moments,
this function uses column-strip and middle-strip moments extracted directly
from the shell model via `_extract_fea_strip_moments`.

# Arguments
- `fea_strip_moments`: NamedTuple from `_extract_fea_strip_moments` with
  `M_neg_ext_cs`, `M_neg_int_cs`, `M_pos_cs`, `M_neg_ext_ms`, `M_neg_int_ms`, `M_pos_ms`
  (bare Float64 in N·m).
- `l2`: Panel width (for strip width calculation)
- `h`, `d`, `fc`, `fy`, `cover`: Same as `design_strip_reinforcement`

# Returns
Same named tuple format as `design_strip_reinforcement`.
"""
function design_strip_reinforcement_fea(fea_strip_moments, l2, h, d, fc, fy, cover; verbose=false)
    # Convert bare N·m to Unitful moments
    M_neg_ext_cs = fea_strip_moments.M_neg_ext_cs * u"N*m"
    M_neg_int_cs = fea_strip_moments.M_neg_int_cs * u"N*m"
    M_pos_cs     = fea_strip_moments.M_pos_cs * u"N*m"
    M_neg_ext_ms = fea_strip_moments.M_neg_ext_ms * u"N*m"
    M_neg_int_ms = fea_strip_moments.M_neg_int_ms * u"N*m"
    M_pos_ms     = fea_strip_moments.M_pos_ms * u"N*m"

    return _design_strips_from_moments(
        M_neg_ext_cs, M_neg_int_cs, M_pos_cs,
        M_neg_ext_ms, M_neg_int_ms, M_pos_ms,
        l2, d, fc, fy, h;
        label="FEA direct", verbose=verbose,
    )
end

"""
    design_single_strip(location, Mu, b, d, fc, fy, h) -> StripReinforcement

Design reinforcement for a single strip location.

# Arguments
- `location`: Strip location symbol (:ext_neg, :pos, :int_neg)
- `Mu`: Design moment
- `b`: Strip width
- `d`: Effective depth
- `fc`, `fy`: Material strengths
- `h`: Slab thickness (for minimum reinforcement)

# Returns
`StripReinforcement` with `section_adequate = false` if the section is too thin
(moment demand exceeds Whitney block capacity). Caller should increase depth.
"""
function design_single_strip(location::Symbol, Mu, b, d, fc, fy, h)
    As_reqd = required_reinforcement(Mu, b, d, fc, fy)
    As_min = minimum_reinforcement(b, h, fy)

    # Check for inadequate section (whitney.jl returns Inf when term > 1)
    if isinf(As_reqd)
        # Return a placeholder result with section_adequate = false
        return StripReinforcement(
            location,
            to_newton_meters(Mu) * u"N*m",
            Inf * u"m^2",
            uconvert(u"m^2", As_min),
            Inf * u"m^2",
            0,              # no bar size
            0.0u"m",        # no spacing
            0,              # no bars
            false           # section_adequate = false
        )
    end

    As_design = max(As_reqd, As_min)
    bars = select_bars(As_design, b)
    
    # Normalize all values to coherent SI (m², m, N·m)
    # Use to_newton_meters for moment (handles kip·ft → N·m conversion)
    return StripReinforcement(
        location,
        to_newton_meters(Mu) * u"N*m",
        uconvert(u"m^2", As_reqd),
        uconvert(u"m^2", As_min),
        uconvert(u"m^2", bars.As_provided),
        bars.bar_size,
        uconvert(u"m", bars.spacing),
        bars.n_bars,
        true            # section_adequate = true
    )
end

